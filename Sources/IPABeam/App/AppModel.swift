import AppKit
import Observation
import SwiftUI

@MainActor
@Observable
final class AppModel {
    static let shared = AppModel()

    // MARK: Devices
    var devices: [Device] = []
    var selectedDeviceID: String? {
        didSet { defaults.set(selectedDeviceID, forKey: Keys.selectedDevice) }
    }
    var isRefreshingDevices = false
    var deviceError: String?
    var pairingMessage: String?

    // MARK: IPA
    var currentIPA: IPAInfo?
    var isInspecting = false
    var inspectError: String?
    var recents: [RecentIPA] = [] {
        didSet { saveRecents() }
    }
    var presentImporter = false
    var showOnboarding = false

    // MARK: Demo (screenshots)
    let demoScenario = ProcessInfo.processInfo.environment["IPABEAM_DEMO"]
    var isDemo: Bool { demoScenario != nil }
    var forceDropTargeted = false

    // MARK: Install
    var job: InstallJob?
    var history: [InstallJob] = []

    // MARK: Tools & signing
    var tools = ToolStatus()
    var identities: [SigningIdentity] = []
    var profiles: [ProvisioningProfile] = []
    var isLoadingSigningAssets = false

    // MARK: Settings
    var backendPreference: BackendPreference {
        didSet {
            defaults.set(backendPreference.rawValue, forKey: Keys.backend)
            Task { await refreshDevices() }
        }
    }
    var signingEnabled: Bool {
        didSet { defaults.set(signingEnabled, forKey: Keys.signingEnabled) }
    }
    var selectedIdentityID: String? {
        didSet { defaults.set(selectedIdentityID, forKey: Keys.identity) }
    }
    var selectedProfileID: String? {
        didSet { defaults.set(selectedProfileID, forKey: Keys.profile) }
    }
    var customBundleID: String {
        didSet { defaults.set(customBundleID, forKey: Keys.customBundleID) }
    }
    var removeExtensions: Bool {
        didSet { defaults.set(removeExtensions, forKey: Keys.removeExtensions) }
    }
    var autoRefresh: Bool {
        didSet { defaults.set(autoRefresh, forKey: Keys.autoRefresh) }
    }

    @ObservationIgnored private let defaults = UserDefaults.standard
    @ObservationIgnored private var refreshLoop: Task<Void, Never>?
    @ObservationIgnored private var installTask: Task<Void, Never>?
    @ObservationIgnored private var started = false

    private enum Keys {
        static let selectedDevice = "selectedDevice"
        static let recents = "recentIPAs"
        static let backend = "backendPreference"
        static let signingEnabled = "signingEnabled"
        static let identity = "signingIdentity"
        static let profile = "signingProfile"
        static let customBundleID = "customBundleID"
        static let removeExtensions = "removeExtensions"
        static let autoRefresh = "autoRefresh"
        static let onboarding = "onboardingCompleted"
    }

    private init() {
        let defaults = UserDefaults.standard
        defaults.register(defaults: [
            Keys.removeExtensions: true,
            Keys.autoRefresh: true,
            Keys.signingEnabled: false
        ])
        backendPreference = BackendPreference(rawValue: defaults.string(forKey: Keys.backend) ?? "") ?? .automatic
        signingEnabled = defaults.bool(forKey: Keys.signingEnabled)
        selectedIdentityID = defaults.string(forKey: Keys.identity)
        selectedProfileID = defaults.string(forKey: Keys.profile)
        customBundleID = defaults.string(forKey: Keys.customBundleID) ?? ""
        removeExtensions = defaults.bool(forKey: Keys.removeExtensions)
        autoRefresh = defaults.bool(forKey: Keys.autoRefresh)
        selectedDeviceID = defaults.string(forKey: Keys.selectedDevice)
        if let data = defaults.data(forKey: Keys.recents),
           let decoded = try? JSONDecoder().decode([RecentIPA].self, from: data) {
            recents = decoded
        }
        showOnboarding = !defaults.bool(forKey: Keys.onboarding)
            && ProcessInfo.processInfo.environment["IPABEAM_DEMO"] == nil
    }

    // MARK: - Lifecycle

    func start() async {
        guard !started else { return }
        started = true
        if let demoScenario {
            loadDemo(demoScenario)
            return
        }
        await reloadTools()
        async let signing: Void = reloadSigningAssets()
        await refreshDevices()
        await signing
        startRefreshLoop()
    }

    func configure(window: NSWindow) {
        window.isMovableByWindowBackground = true
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.backgroundColor = NSColor(red: 0.02, green: 0.022, blue: 0.055, alpha: 1)

        guard isDemo else { return }
        window.setContentSize(NSSize(width: 1440, height: 900))
        window.center()
        if let path = ProcessInfo.processInfo.environment["IPABEAM_WINDOW_FILE"] {
            let number = window.windowNumber
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                try? String(number).write(toFile: path, atomically: true, encoding: .utf8)
            }
        }
    }

    func reloadTools() async {
        tools = await ToolStatus.detect()
    }

    func completeOnboarding() {
        defaults.set(true, forKey: Keys.onboarding)
        showOnboarding = false
    }

    private func startRefreshLoop() {
        refreshLoop?.cancel()
        refreshLoop = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(4))
                guard let self else { return }
                if self.autoRefresh && !self.isInstalling {
                    await self.refreshDevices()
                }
            }
        }
    }

    // MARK: - Devices

    var selectedDevice: Device? {
        devices.first { $0.id == selectedDeviceID }
    }

    func refreshDevices() async {
        guard !isRefreshingDevices else { return }
        guard tools.checked else { return }
        isRefreshingDevices = true
        defer { isRefreshingDevices = false }

        let result = await DeviceManager.listDevices(preference: backendPreference, tools: tools)
        if result.devices != devices {
            withAnimation(.snappy) { devices = result.devices }
        }
        deviceError = result.devices.isEmpty ? result.error : nil

        if selectedDevice == nil || selectedDevice?.isAvailable == false,
           let firstAvailable = devices.first(where: \.isAvailable) {
            selectedDeviceID = firstAvailable.id
        } else if selectedDevice == nil {
            selectedDeviceID = devices.first?.id
        }
        autoSelectSigningAssets()
    }

    func pair(_ device: Device) async {
        pairingMessage = "Bitte auf dem iPhone „Vertrauen“ tippen und den Code eingeben …"
        do {
            let output = try await LibimobiledeviceClient.pair(udid: device.udid ?? device.id, tools: tools)
            pairingMessage = output.isEmpty ? "Gekoppelt ✓" : output
        } catch {
            pairingMessage = error.localizedDescription
        }
        await refreshDevices()
    }

    // MARK: - IPA

    func loadIPA(at url: URL) async {
        guard url.pathExtension.lowercased() == "ipa" else {
            inspectError = "Bitte wähle eine .ipa-Datei aus."
            return
        }
        inspectError = nil
        isInspecting = true
        defer { isInspecting = false }
        do {
            let info = try await IPAInspector.inspect(url)
            withAnimation(.spring(response: 0.45, dampingFraction: 0.82)) {
                currentIPA = info
                if job?.state.isFinished == true { job = nil }
            }
            remember(info)
        } catch {
            inspectError = error.localizedDescription
        }
    }

    func handleDrop(_ urls: [URL]) -> Bool {
        guard let ipa = urls.first(where: { $0.pathExtension.lowercased() == "ipa" }) else {
            inspectError = "Nur .ipa-Dateien werden unterstützt."
            return false
        }
        Task { await loadIPA(at: ipa) }
        return true
    }

    func clearIPA() {
        withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
            currentIPA = nil
            inspectError = nil
            if job?.state.isFinished == true { job = nil }
        }
    }

    private func remember(_ info: IPAInfo) {
        var list = recents.filter { $0.path != info.url.path }
        list.insert(RecentIPA(info: info), at: 0)
        recents = Array(list.prefix(8))
    }

    func removeRecent(_ recent: RecentIPA) {
        recents.removeAll { $0.id == recent.id }
    }

    private func saveRecents() {
        guard !isDemo else { return }
        if let data = try? JSONEncoder().encode(recents) {
            defaults.set(data, forKey: Keys.recents)
        }
    }

    // MARK: - Signing

    var selectedIdentity: SigningIdentity? {
        identities.first { $0.id == selectedIdentityID }
    }

    var selectedProfile: ProvisioningProfile? {
        profiles.first { $0.id == selectedProfileID }
    }

    func reloadSigningAssets() async {
        isLoadingSigningAssets = true
        async let loadedIdentities = SigningService.loadIdentities()
        async let loadedProfiles = SigningService.loadProfiles()
        identities = await loadedIdentities
        profiles = await loadedProfiles
        isLoadingSigningAssets = false
        autoSelectSigningAssets()
    }

    private func autoSelectSigningAssets() {
        if selectedProfile == nil, !profiles.isEmpty {
            let udid = selectedDevice?.udid
            selectedProfileID = (profiles.first { $0.includes(udid: udid) } ?? profiles.first)?.id
        }
        if selectedIdentity == nil, !identities.isEmpty {
            let team = selectedProfile?.teamID
            selectedIdentityID = (identities.first { $0.teamID == team } ?? identities.first)?.id
        }
    }

    var signingWarning: String? {
        guard signingEnabled else { return nil }
        if identities.isEmpty { return "Kein Signierzertifikat gefunden. Melde dich in Xcode mit deiner Apple‑ID an." }
        if profiles.isEmpty { return "Kein gültiges Provisioning-Profil gefunden." }
        guard let profile = selectedProfile else { return "Bitte ein Provisioning-Profil wählen." }
        guard let identity = selectedIdentity else { return "Bitte ein Zertifikat wählen." }
        if let team = identity.teamID, !profile.teamID.isEmpty, team != profile.teamID {
            return "Zertifikat (\(team)) und Profil (\(profile.teamID)) gehören zu unterschiedlichen Teams."
        }
        if let device = selectedDevice, !profile.includes(udid: device.udid) {
            return "„\(device.name)“ ist nicht im Profil enthalten – iOS wird die Installation ablehnen."
        }
        return nil
    }

    // MARK: - Install

    var isInstalling: Bool { job?.state == .running }

    /// Reason why installation can't start yet (shown under the button).
    var installBlocker: String? {
        if !tools.checked { return "Werkzeuge werden geprüft …" }
        if !tools.hasAnyBackend { return "Installiere Xcode oder libimobiledevice (siehe Einstellungen → Werkzeuge)." }
        guard currentIPA != nil else { return "Wähle zuerst eine IPA-Datei." }
        guard let device = selectedDevice else { return "Verbinde dein iPhone per USB‑C oder WLAN." }
        if device.needsTrust { return "Tippe auf dem iPhone auf „Vertrauen“, um es zu koppeln." }
        if device.connection == .offline { return "„\(device.name)“ ist gerade nicht erreichbar." }
        if signingEnabled && (selectedIdentity == nil || selectedProfile == nil) {
            return "Wähle Zertifikat und Profil für die Signierung."
        }
        return nil
    }

    func install() {
        guard installBlocker == nil, !isInstalling,
              let ipa = currentIPA, let device = selectedDevice else { return }

        var signing: SigningConfig?
        if signingEnabled, let identity = selectedIdentity, let profile = selectedProfile {
            signing = SigningConfig(
                identity: identity,
                profile: profile,
                customBundleID: customBundleID.isEmpty ? nil : customBundleID,
                removeExtensions: removeExtensions
            )
        }

        let job = InstallJob(
            appName: ipa.displayName,
            bundleID: ipa.bundleID,
            deviceName: device.name,
            connection: device.connection
        )
        withAnimation(.spring(response: 0.5, dampingFraction: 0.85)) {
            self.job = job
        }
        let tools = self.tools
        installTask = Task {
            await Self.runInstall(job: job, ipa: ipa, device: device, signing: signing, tools: tools)
            self.history.insert(job, at: 0)
            if self.history.count > 20 { self.history.removeLast() }
            if !NSApp.isActive { _ = NSApp.requestUserAttention(.informationalRequest) }
        }
    }

    func cancelInstall() {
        installTask?.cancel()
    }

    func dismissJob() {
        withAnimation(.spring(response: 0.45, dampingFraction: 0.85)) { job = nil }
    }

    private static func runInstall(
        job: InstallJob,
        ipa: IPAInfo,
        device: Device,
        signing: SigningConfig?,
        tools: ToolStatus
    ) async {
        let log: @Sendable (String) -> Void = { line in
            Task { @MainActor in job.append(line) }
        }
        let progress: @Sendable (Double) -> Void = { value in
            Task { @MainActor in
                withAnimation(.easeOut(duration: 0.25)) { job.installProgress = max(job.installProgress, value) }
            }
        }

        let workDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("IPABeam-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: workDirectory) }

        job.append("\(ipa.displayName) \(ipa.versionLabel) → \(device.name) (\(device.connection.title), \(device.backend.title))")

        do {
            // 1. Prepare
            job.begin(.prepare)
            try FileManager.default.createDirectory(at: workDirectory, withIntermediateDirectories: true)
            var installURL = ipa.url
            var appURL: URL?
            if signing != nil || device.backend == .devicectl {
                let extracted = try await IPAInspector.extract(ipa.url, to: workDirectory, log: log)
                appURL = extracted
                installURL = extracted
            }
            job.complete(.prepare)

            // 2. Sign
            if let signing, let appURL {
                job.begin(.sign)
                let finalID = try await SigningService.resign(
                    app: appURL, config: signing, workDirectory: workDirectory, log: log
                )
                job.finalBundleID = finalID
                if device.backend == .libimobiledevice {
                    let output = workDirectory.appendingPathComponent("signed.ipa")
                    try await IPAInspector.package(directory: workDirectory, to: output, log: log)
                    installURL = output
                }
                job.complete(.sign)
            } else {
                job.skip(.sign)
                job.append("Signierung übersprungen – Original-Signatur wird verwendet.")
            }

            // 3. Install
            try Task.checkCancellation()
            job.begin(.install)
            try await DeviceManager.install(installURL, on: device, tools: tools, progress: progress, log: log)

            // Let queued log/progress updates land before finishing.
            await Task.yield()
            withAnimation(.spring(response: 0.5, dampingFraction: 0.7)) { job.succeed() }
        } catch is CancellationError {
            job.cancel()
        } catch {
            if Task.isCancelled {
                job.cancel()
            } else {
                job.fail(Self.friendlyMessage(for: error))
            }
        }
    }

    /// Adds helpful hints to common iOS installation errors.
    private static func friendlyMessage(for error: Error) -> String {
        let message = error.localizedDescription
        let lower = message.lowercased()
        var hint: String?
        if lower.contains("developer mode") || lower.contains("developermode") {
            hint = "Aktiviere auf dem iPhone: Einstellungen → Datenschutz & Sicherheit → Entwicklermodus."
        } else if lower.contains("applicationverificationfailed") || lower.contains("signature") || lower.contains("0xe8008015") {
            hint = "Die App ist nicht gültig für dieses Gerät signiert. Aktiviere „Neu signieren“ mit einem Profil, das dein iPhone enthält."
        } else if lower.contains("provision") || lower.contains("0xe8008012") {
            hint = "Das Provisioning-Profil passt nicht zu App oder Gerät."
        } else if lower.contains("encrypted") || lower.contains("fairplay") {
            hint = "Die IPA ist verschlüsselt (App-Store-Kopie) und kann nicht installiert werden."
        } else if lower.contains("minimumosversion") || lower.contains("requires a newer version") {
            hint = "Die App benötigt eine neuere iOS-Version."
        } else if lower.contains("timed out") || lower.contains("rechtzeitig") {
            hint = "Prüfe die Verbindung zum iPhone (Kabel/WLAN) und entsperre das Gerät."
        }
        if let hint { return "\(message)\n\n💡 \(hint)" }
        return message
    }
}
