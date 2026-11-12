import Foundation
import Observation
import SwiftUI

enum Tab: String, CaseIterable, Identifiable {
    case beam, library, certificates, settings
    var id: String { rawValue }

    var title: String {
        switch self {
        case .beam: return "Beam"
        case .library: return "Bibliothek"
        case .certificates: return "Zertifikate"
        case .settings: return "Mehr"
        }
    }

    var symbol: String {
        switch self {
        case .beam: return "bolt.fill"
        case .library: return "square.stack.3d.up.fill"
        case .certificates: return "key.fill"
        case .settings: return "ellipsis.circle.fill"
        }
    }
}

struct BeamRun: Equatable {
    var steps: [BeamStep: StepState]
    var message: String?
    var finished: Bool
}

@MainActor
@Observable
final class AppState {
    var tab: Tab = .beam
    var apps: [LibraryApp] = []
    var signingSets: [SigningSet] = []
    var selectedAppID: UUID?
    var selectedSigningID: UUID?
    var importError: String?
    var isImporting = false
    var run: BeamRun?
    var toast: String?

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
        selectedAppID = apps.first?.id
        selectedSigningID = signingSets.first?.id
    }

    private func save() {
        guard !isDemo else { return }
        let encoder = JSONEncoder()
        try? encoder.encode(apps).write(to: baseURL.appendingPathComponent("library.json"), options: .atomic)
        try? encoder.encode(signingSets).write(to: baseURL.appendingPathComponent("signing.json"), options: .atomic)
    }

    var selectedApp: LibraryApp? { apps.first { $0.id == selectedAppID } }
    var selectedSigning: SigningSet? { signingSets.first { $0.id == selectedSigningID } }

    func fileURL(for app: LibraryApp) -> URL {
        appsURL.appendingPathComponent(app.fileName)
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

    /// Set when a .p12/.mobileprovision was opened from outside; the certificate sheet picks it up.
    var pendingCertificateFile: URL?

    func importIPA(from source: URL) {
        isImporting = true
        importError = nil
        let accessing = source.startAccessingSecurityScopedResource()
        defer {
            if accessing { source.stopAccessingSecurityScopedResource() }
            isImporting = false
        }

        let id = UUID()
        let target = appsURL.appendingPathComponent("\(id.uuidString).ipa")
        do {
            try fileManager.copyItem(at: source, to: target)
            let meta = try IPAReader.read(target)
            let size = (try? fileManager.attributesOfItem(atPath: target.path)[.size] as? NSNumber)?.int64Value ?? 0
            let app = LibraryApp(
                id: id,
                fileName: target.lastPathComponent,
                name: meta.name,
                bundleID: meta.bundleID,
                version: meta.version,
                build: meta.build,
                minimumOSVersion: meta.minimumOSVersion,
                size: size,
                hasExtensions: meta.hasExtensions,
                iconData: meta.iconData,
                importedAt: Date()
            )
            withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
                apps.insert(app, at: 0)
                selectedAppID = app.id
                tab = .beam
                run = nil
            }
            save()
            showToast("\(app.name) importiert")
        } catch {
            try? fileManager.removeItem(at: target)
            importError = error.localizedDescription
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
        try p12Data.write(to: certsURL.appendingPathComponent(certFile), options: .completeFileProtection)
        try profileData.write(to: certsURL.appendingPathComponent(profileFile), options: .completeFileProtection)
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

    // MARK: - Beam

    var signingWarning: String? {
        guard let set = selectedSigning else { return "Füge zuerst ein Zertifikat (.p12) + Profil hinzu." }
        if set.profile.isExpired { return "Das Profil ist abgelaufen." }
        if let app = selectedApp, !set.profile.allows(bundleID: app.bundleID), !set.profile.bundlePattern.hasSuffix("*") {
            return "Das Profil gilt nur für „\(set.profile.bundlePattern)“ – die Bundle-ID wird beim Signieren angepasst."
        }
        return nil
    }

    /// Runs every check that can happen on the device today. Signing + installing on-device is the next stage.
    func beam() {
        guard let set = selectedSigning, selectedApp != nil else { return }
        var steps: [BeamStep: StepState] = [:]
        for step in BeamStep.allCases { steps[step] = .pending }
        run = BeamRun(steps: steps, message: nil, finished: false)

        Task { @MainActor in
            await advance(.certificate) {
                let data = try Data(contentsOf: self.certsURL.appendingPathComponent(set.certificateFile))
                _ = try SigningAssets.certificateName(p12: data, password: PasswordVault.load(for: set.id) ?? "")
            }
            guard run?.steps[.certificate] == .done else { return }
            await advance(.profile) {
                if set.profile.isExpired { throw SigningAssetError.invalidProfile }
            }
            guard run?.steps[.profile] == .done else { return }
            withAnimation(.snappy) {
                run?.steps[.sign] = .upcoming
                run?.steps[.install] = .upcoming
                run?.message = "Zertifikat und Profil sind gültig ✓\nSignieren & Installieren direkt auf dem iPhone kommt im nächsten Update. Bis dahin: IPA mit IPA Beam am PC/Mac installieren."
                run?.finished = true
            }
        }
    }

    private func advance(_ step: BeamStep, _ work: @escaping () throws -> Void) async {
        withAnimation(.snappy) { run?.steps[step] = .running }
        try? await Task.sleep(for: .milliseconds(650))
        do {
            try work()
            withAnimation(.snappy) { run?.steps[step] = .done }
        } catch {
            withAnimation(.snappy) {
                run?.steps[step] = .failed
                run?.message = error.localizedDescription
                run?.finished = true
            }
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
