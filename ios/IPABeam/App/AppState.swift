import Foundation
import Observation
import SwiftUI
import ZSignKit

enum Tab: String, CaseIterable, Identifiable {
    case beam, library, sources, certificates, settings
    var id: String { rawValue }

    var title: String {
        switch self {
        case .beam: return "Beam"
        case .library: return "Bibliothek"
        case .sources: return "Quellen"
        case .certificates: return "Zertifikate"
        case .settings: return "Mehr"
        }
    }

    var symbol: String {
        switch self {
        case .beam: return "bolt.fill"
        case .library: return "square.stack.3d.up.fill"
        case .sources: return "antenna.radiowaves.left.and.right"
        case .certificates: return "key.fill"
        case .settings: return "ellipsis.circle.fill"
        }
    }
}

struct BeamRun: Equatable {
    var appID: UUID
    var steps: [BeamStep: StepState]
    var message: String?
    var finished: Bool
    var needsSetup = false
}

@MainActor
@Observable
final class AppState {
    var tab: Tab = .beam
    var apps: [LibraryApp] = []
    var signingSets: [SigningSet] = []
    var sources: [AppSource] = []
    var selectedAppID: UUID?
    var selectedSigningID: UUID?
    var importError: String?
    var isImporting = false
    var run: BeamRun?
    var toast: String?
    var downloads: [String: Double] = [:]
    var isRefreshingSources = false
    var installReady: Bool?
    var removeExtensions = true
    /// Set when a .p12/.mobileprovision was opened from outside; the certificate sheet picks it up.
    var pendingCertificateFile: URL?

    @ObservationIgnored let isDemo: Bool
    @ObservationIgnored private let fileManager = FileManager.default

    init() {
        let demo = UserDefaults.standard.string(forKey: "demo")
        isDemo = demo != nil
        if let demo {
            loadDemo(demo)
        } else {
            load()
        }
    }

    // MARK: - Storage

    private var baseURL: URL {
        let url = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("IPABeam", isDirectory: true)
        try? fileManager.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private var appsURL: URL { folder("Apps") }
    private var certsURL: URL { folder("Certificates") }

    private var cacheURL: URL {
        let url = fileManager.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("IPABeam", isDirectory: true)
        try? fileManager.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func folder(_ name: String) -> URL {
        let url = baseURL.appendingPathComponent(name, isDirectory: true)
        try? fileManager.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func load() {
        let decoder = JSONDecoder()
        if let data = try? Data(contentsOf: baseURL.appendingPathComponent("library.json")),
           let decoded = try? decoder.decode([LibraryApp].self, from: data) {
            apps = decoded
        }
        if let data = try? Data(contentsOf: baseURL.appendingPathComponent("signing.json")),
           let decoded = try? decoder.decode([SigningSet].self, from: data) {
            signingSets = decoded
        }
        if let data = try? Data(contentsOf: baseURL.appendingPathComponent("sources.json")),
           let decoded = try? decoder.decode([AppSource].self, from: data) {
            sources = decoded
        }
        removeExtensions = UserDefaults.standard.object(forKey: "removeExtensions") as? Bool ?? true
        selectedAppID = apps.first?.id
        selectedSigningID = signingSets.first?.id
    }

    func save() {
        guard !isDemo else { return }
        let encoder = JSONEncoder()
        try? encoder.encode(apps).write(to: baseURL.appendingPathComponent("library.json"), options: .atomic)
        try? encoder.encode(signingSets).write(to: baseURL.appendingPathComponent("signing.json"), options: .atomic)
        try? encoder.encode(sources).write(to: baseURL.appendingPathComponent("sources.json"), options: .atomic)
        UserDefaults.standard.set(removeExtensions, forKey: "removeExtensions")
    }

    var selectedApp: LibraryApp? { apps.first { $0.id == selectedAppID } }
    var selectedSigning: SigningSet? { signingSets.first { $0.id == selectedSigningID } }

    func fileURL(for app: LibraryApp) -> URL {
        appsURL.appendingPathComponent(app.fileName)
    }

    /// Called when the app becomes active.
    func onLaunch() async {
        guard !isDemo else { return }
        await refreshSources()
        await checkInstallSetup()
    }

    // MARK: - Import

    /// Handles any file handed to the app (Files, Safari, AirDrop, "Open in…").
    func handleIncoming(_ url: URL) {
        switch url.pathExtension.lowercased() {
        case "ipa":
            importIPA(from: url)
        case "mobileprovision", "p12", "pfx":
            tab = .certificates
            pendingCertificateFile = url
        default:
            importError = "Dieser Dateityp wird nicht unterstützt."
        }
    }

    func importIPA(from source: URL) {
        isImporting = true
        importError = nil
        defer { isImporting = false }
        do {
            let app = try addToLibrary(source, replacingSameBundle: false)
            withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
                selectedAppID = app.id
                tab = .beam
                run = nil
            }
            showToast("\(app.name) importiert")
        } catch {
            importError = error.localizedDescription
        }
    }

    /// Copies an IPA into the library. With `replacingSameBundle` an older entry with the same bundle ID is replaced.
    @discardableResult
    private func addToLibrary(_ source: URL, replacingSameBundle: Bool) throws -> LibraryApp {
        let accessing = source.startAccessingSecurityScopedResource()
        defer { if accessing { source.stopAccessingSecurityScopedResource() } }

        let id = UUID()
        let target = appsURL.appendingPathComponent("\(id.uuidString).ipa")
        do {
            try fileManager.copyItem(at: source, to: target)
            let meta = try IPAReader.read(target)
            let size = (try? fileManager.attributesOfItem(atPath: target.path)[.size] as? NSNumber)?.int64Value ?? 0
            var app = LibraryApp(
                id: id, fileName: target.lastPathComponent, name: meta.name, bundleID: meta.bundleID,
                version: meta.version, build: meta.build, minimumOSVersion: meta.minimumOSVersion,
                size: size, hasExtensions: meta.hasExtensions, iconData: meta.iconData, importedAt: Date()
            )
            withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
                if replacingSameBundle, let index = apps.firstIndex(where: { $0.bundleID == app.bundleID }) {
                    let old = apps[index]
                    app.installedAt = old.installedAt
                    app.expiresAt = old.expiresAt
                    try? fileManager.removeItem(at: fileURL(for: old))
                    apps[index] = app
                    if selectedAppID == old.id { selectedAppID = app.id }
                } else {
                    apps.insert(app, at: 0)
                }
            }
            save()
            return app
        } catch {
            try? fileManager.removeItem(at: target)
            throw error
        }
    }

    func delete(_ app: LibraryApp) {
        try? fileManager.removeItem(at: fileURL(for: app))
        apps.removeAll { $0.id == app.id }
        if selectedAppID == app.id { selectedAppID = apps.first?.id }
        save()
    }

    // MARK: - Certificates

    func addSigningSet(p12URL: URL, password: String, profileURL: URL) throws {
        let p12Access = p12URL.startAccessingSecurityScopedResource()
        let profileAccess = profileURL.startAccessingSecurityScopedResource()
        defer {
            if p12Access { p12URL.stopAccessingSecurityScopedResource() }
            if profileAccess { profileURL.stopAccessingSecurityScopedResource() }
        }
        let p12Data = try Data(contentsOf: p12URL)
        let profileData = try Data(contentsOf: profileURL)
        let name = try SigningAssets.certificateName(p12: p12Data, password: password)
        let profile = try SigningAssets.readProfile(profileData)

        let id = UUID()
        let certFile = "\(id.uuidString).p12"
        let profileFile = "\(id.uuidString).mobileprovision"
        try p12Data.write(to: certsURL.appendingPathComponent(certFile), options: .completeFileProtectionUntilFirstUserAuthentication)
        try profileData.write(to: certsURL.appendingPathComponent(profileFile), options: .completeFileProtectionUntilFirstUserAuthentication)
        PasswordVault.save(password, for: id)

        let set = SigningSet(id: id, certificateName: name, certificateFile: certFile,
                             profileFile: profileFile, profile: profile, addedAt: Date())
        withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
            signingSets.insert(set, at: 0)
            selectedSigningID = set.id
        }
        save()
        showToast("Zertifikat hinzugefügt")
    }

    func delete(_ set: SigningSet) {
        try? fileManager.removeItem(at: certsURL.appendingPathComponent(set.certificateFile))
        try? fileManager.removeItem(at: certsURL.appendingPathComponent(set.profileFile))
        PasswordVault.delete(for: set.id)
        signingSets.removeAll { $0.id == set.id }
        if selectedSigningID == set.id { selectedSigningID = signingSets.first?.id }
        save()
    }

    // MARK: - Sources & updates

    func addSource(_ text: String) async throws {
        var string = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if !string.lowercased().hasPrefix("http") { string = "https://" + string }
        guard let url = URL(string: string), url.host != nil else { throw SourceError.invalidURL }
        let source = try await SourceLoader.load(url)
        withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
            sources.removeAll { $0.url == source.url }
            sources.insert(source, at: 0)
        }
        save()
        showToast("Quelle „\(source.name)“ hinzugefügt")
    }

    func removeSource(_ source: AppSource) {
        sources.removeAll { $0.id == source.id }
        save()
    }

    func refreshSources() async {
        guard !isRefreshingSources, !sources.isEmpty else { return }
        isRefreshingSources = true
        defer { isRefreshingSources = false }
        var refreshed: [AppSource] = []
        for source in sources {
            if let updated = try? await SourceLoader.load(source.url) {
                refreshed.append(updated)
            } else {
                refreshed.append(source)
            }
        }
        withAnimation(.snappy) { sources = refreshed }
        save()
    }

    /// Library apps for which a source offers a newer version.
    var availableUpdates: [AppUpdate] {
        apps.compactMap { app in
            let candidates = sources.flatMap(\.apps).filter { $0.bundleID == app.bundleID }
            guard let best = candidates.compactMap({ candidate in candidate.latest.map { (candidate, $0) } })
                .max(by: { SourceLoader.isNewer($1.1.version, than: $0.1.version) }),
                  SourceLoader.isNewer(best.1.version, than: app.version) else { return nil }
            return AppUpdate(app: app, source: best.0, version: best.1)
        }
    }

    func libraryApp(for sourceApp: SourceApp) -> LibraryApp? {
        apps.first { $0.bundleID == sourceApp.bundleID }
    }

    /// Downloads the newest version from a source into the library; optionally signs + installs it right away.
    func download(_ sourceApp: SourceApp, thenBeam: Bool) async {
        guard let version = sourceApp.latest, downloads[sourceApp.bundleID] == nil else { return }
        downloads[sourceApp.bundleID] = 0
        defer { downloads[sourceApp.bundleID] = nil }

        let destination = cacheURL.appendingPathComponent("download-\(UUID().uuidString).ipa")
        let bundleID = sourceApp.bundleID
        let downloader = FileDownloader(destination: destination) { value in
            Task { @MainActor [weak self] in
                if self?.downloads[bundleID] != nil { self?.downloads[bundleID] = value }
            }
        }
        do {
            let file = try await downloader.download(version.downloadURL)
            defer { try? fileManager.removeItem(at: file) }
            let app = try addToLibrary(file, replacingSameBundle: true)
            selectedAppID = app.id
            showToast("\(app.name) \(app.versionLabel) geladen")
            if thenBeam, selectedSigning != nil {
                tab = .beam
                beam(app)
            }
        } catch {
            importError = "\(sourceApp.name): \(error.localizedDescription)"
        }
    }

    func updateAll() async {
        for update in availableUpdates {
            await download(update.source, thenBeam: false)
        }
    }

    // MARK: - On-device install setup

    func checkInstallSetup() async {
        guard !isDemo else { return }
        installReady = await OnDeviceInstaller.shared.isTrusted()
    }

    func startInstallSetup() async {
        do {
            try await OnDeviceInstaller.shared.openProfileDownload()
        } catch {
            importError = error.localizedDescription
        }
    }

    // MARK: - Beam (sign + install on this iPhone)

    var signingWarning: String? {
        guard let set = selectedSigning else { return "Füge zuerst ein Zertifikat (.p12) + Profil hinzu." }
        if set.profile.isExpired { return "Das Profil ist abgelaufen." }
        if let app = selectedApp, !set.profile.allows(bundleID: app.bundleID), !set.profile.bundlePattern.hasSuffix("*") {
            return "Das Profil gilt nur für „\(set.profile.bundlePattern)“ – die Bundle-ID wird beim Signieren angepasst."
        }
        return nil
    }

    var isBeaming: Bool { run.map { !$0.finished } ?? false }

    func beam(_ target: LibraryApp? = nil) {
        guard let set = selectedSigning, let app = target ?? selectedApp, !isBeaming else { return }
        var steps: [BeamStep: StepState] = [:]
        for step in BeamStep.allCases { steps[step] = .pending }
        withAnimation(.spring(response: 0.45, dampingFraction: 0.85)) {
            selectedAppID = app.id
            run = BeamRun(appID: app.id, steps: steps, message: nil, finished: false)
        }

        let p12URL = certsURL.appendingPathComponent(set.certificateFile)
        let profileURL = certsURL.appendingPathComponent(set.profileFile)
        let password = PasswordVault.load(for: set.id) ?? ""
        let ipaURL = fileURL(for: app)
        let signedURL = cacheURL.appendingPathComponent("signed-\(app.id.uuidString).ipa")
        let workURL = cacheURL.appendingPathComponent("work-\(UUID().uuidString)", isDirectory: true)
        let pattern = set.profile.bundlePattern
        let targetBundleID: String? = pattern.contains("*") ? nil : pattern
        let finalBundleID = targetBundleID ?? app.bundleID
        let removeExtensions = removeExtensions

        Task { @MainActor in
            defer { try? fileManager.removeItem(at: workURL) }

            guard await advance(.certificate, {
                let data = try Data(contentsOf: p12URL)
                _ = try SigningAssets.certificateName(p12: data, password: password)
            }) else { return }

            guard await advance(.profile, {
                if set.profile.isExpired { throw SigningAssetError.invalidProfile }
            }) else { return }

            guard await advance(.sign, {
                let output = await Task.detached(priority: .userInitiated) {
                    ZSign.sign(
                        ipa: ipaURL,
                        output: signedURL,
                        options: .init(p12: p12URL, password: password, profile: profileURL,
                                       bundleID: targetBundleID, removeExtensions: removeExtensions),
                        workDirectory: workURL
                    )
                }.value
                if !output.success {
                    let detail = output.log.split(separator: "\n").suffix(4).joined(separator: "\n")
                    throw BeamError.signing(detail)
                }
            }) else { return }

            guard await advance(.install, {
                try await OnDeviceInstaller.shared.install(
                    signedIPA: signedURL, bundleID: finalBundleID, version: app.version, title: app.name
                )
            }) else { return }

            if let index = apps.firstIndex(where: { $0.id == app.id }) {
                apps[index].installedAt = Date()
                apps[index].expiresAt = set.profile.expirationDate
                save()
            }
            withAnimation(.snappy) {
                run?.message = "Bestätige auf dem iPhone „Installieren“ – die App erscheint dann auf dem Homescreen."
                run?.finished = true
            }
        }
    }

    enum BeamError: LocalizedError {
        case signing(String)

        var errorDescription: String? {
            switch self {
            case .signing(let detail): return "Signieren fehlgeschlagen.\n\(detail)"
            }
        }
    }

    /// Runs one pipeline step. Returns false (and finishes the run) on failure.
    private func advance(_ step: BeamStep, _ work: () async throws -> Void) async -> Bool {
        withAnimation(.snappy) { run?.steps[step] = .running }
        try? await Task.sleep(for: .milliseconds(350))
        do {
            try await work()
            withAnimation(.snappy) { run?.steps[step] = .done }
            return true
        } catch {
            withAnimation(.snappy) {
                run?.steps[step] = .failed
                run?.message = error.localizedDescription
                run?.finished = true
                if let installError = error as? OnDeviceInstaller.InstallError, case .notTrusted = installError {
                    run?.needsSetup = true
                    installReady = false
                }
            }
            return false
        }
    }

    func showToast(_ text: String) {
        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) { toast = text }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(2.2))
            withAnimation(.easeOut) { if toast == text { toast = nil } }
        }
    }
}
