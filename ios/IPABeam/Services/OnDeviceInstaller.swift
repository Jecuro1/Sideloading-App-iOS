import Foundation
import Security
import UIKit
import ZSignKit

/// Installs signed IPAs directly on this iPhone:
/// a per-device local CA (trusted once by the user) secures a loopback HTTPS server,
/// and iOS' own installer is triggered with an `itms-services` link.
@MainActor
final class OnDeviceInstaller {
    static let shared = OnDeviceInstaller()

    enum InstallError: LocalizedError {
        case notTrusted
        case identity

        var errorDescription: String? {
            switch self {
            case .notTrusted:
                return "Die lokale Installation ist noch nicht eingerichtet. Öffne „Mehr → Installation einrichten“."
            case .identity:
                return "Das lokale Server-Zertifikat konnte nicht geladen werden."
            }
        }
    }

    private let fileManager = FileManager.default
    private var httpsServer: LocalServer?
    private var httpServer: LocalServer?
    private var backgroundTask: UIBackgroundTaskIdentifier = .invalid
    private let passwordKey = UUID(uuidString: "6F1B2A6C-3C55-4C1E-9C7B-1B9D2E0A7A11")!

    private var folder: URL {
        let url = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("IPABeam/LocalCA", isDirectory: true)
        try? fileManager.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private var caURL: URL { folder.appendingPathComponent("IPABeam-Local-CA.cer") }
    private var identityURL: URL { folder.appendingPathComponent("server.p12") }

    var hasCertificate: Bool {
        fileManager.fileExists(atPath: caURL.path) && fileManager.fileExists(atPath: identityURL.path)
    }

    // MARK: - Local CA

    func ensureCertificate() throws {
        if hasCertificate { return }
        let password = UUID().uuidString
        try ZSign.makeLocalCA(caCertificate: caURL, serverIdentity: identityURL, password: password)
        PasswordVault.save(password, for: passwordKey)
    }

    /// Creates a fresh CA (the user has to trust the new profile again).
    func resetCertificate() throws {
        httpsServer?.stop()
        httpsServer = nil
        try? fileManager.removeItem(at: caURL)
        try? fileManager.removeItem(at: identityURL)
        try ensureCertificate()
    }

    private func serverIdentity() throws -> SecIdentity {
        let data = try Data(contentsOf: identityURL)
        let password = PasswordVault.load(for: passwordKey) ?? ""
        let options = [kSecImportExportPassphrase as String: password] as CFDictionary
        var items: CFArray?
        guard SecPKCS12Import(data as CFData, options, &items) == errSecSuccess,
              let first = (items as? [[String: Any]])?.first,
              let identity = first[kSecImportItemIdentity as String] else {
            throw InstallError.identity
        }
        return identity as! SecIdentity // swiftlint:disable:this force_cast
    }

    /// Configuration profile that installs the local CA as a trusted root.
    func configurationProfile() throws -> Data {
        let certificate = try Data(contentsOf: caURL)
        let profile: [String: Any] = [
            "PayloadContent": [[
                "PayloadCertificateFileName": "IPABeam-Local-CA.cer",
                "PayloadContent": certificate,
                "PayloadDescription": "Erlaubt IPA Beam, Apps lokal auf diesem iPhone zu installieren (nur 127.0.0.1).",
                "PayloadDisplayName": "IPA Beam Local CA",
                "PayloadIdentifier": "app.ipabeam.localca.certificate",
                "PayloadType": "com.apple.security.root",
                "PayloadUUID": UUID().uuidString,
                "PayloadVersion": 1
            ]],
            "PayloadDescription": "Lokale Installation von Apps über IPA Beam. Das Zertifikat gilt ausschließlich für 127.0.0.1.",
            "PayloadDisplayName": "IPA Beam – lokale Installation",
            "PayloadIdentifier": "app.ipabeam.localca",
            "PayloadOrganization": "IPA Beam",
            "PayloadRemovalDisallowed": false,
            "PayloadType": "Configuration",
            "PayloadUUID": UUID().uuidString,
            "PayloadVersion": 1
        ]
        return try PropertyListSerialization.data(fromPropertyList: profile, format: .xml, options: 0)
    }

    // MARK: - Servers

    private func startHTTPS() async throws -> LocalServer {
        if let server = httpsServer, server.isRunning { return server }
        try ensureCertificate()
        let server = LocalServer(identity: try serverIdentity())
        server.setRoute("/ping", .init(contentType: "text/plain", body: .data(Data("ok".utf8))))
        _ = try await server.start()
        httpsServer = server
        return server
    }

    /// Step 1 of the setup: Safari downloads the configuration profile from the loopback server.
    func openProfileDownload() async throws {
        try ensureCertificate()
        if httpServer == nil || httpServer?.isRunning == false {
            let server = LocalServer(identity: nil)
            _ = try await server.start()
            httpServer = server
        }
        guard let server = httpServer else { return }
        server.setRoute("/IPABeam.mobileconfig", .init(contentType: "application/x-apple-aspen-config",
                                                       body: .data(try configurationProfile())))
        keepAlive(seconds: 60)
        if let url = URL(string: "http://127.0.0.1:\(server.port)/IPABeam.mobileconfig") {
            await UIApplication.shared.open(url)
        }
    }

    /// Checks whether iOS trusts the local CA (the HTTPS health check only succeeds then).
    func isTrusted() async -> Bool {
        guard hasCertificate, let server = try? await startHTTPS(),
              let url = URL(string: "https://127.0.0.1:\(server.port)/ping") else { return false }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 4
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        guard let (data, response) = try? await session.data(from: url),
              (response as? HTTPURLResponse)?.statusCode == 200 else { return false }
        return String(decoding: data, as: UTF8.self) == "ok"
    }

    // MARK: - Install

    /// Hands a signed IPA to iOS. iOS then shows its own "Install" dialog.
    func install(signedIPA: URL, bundleID: String, version: String, title: String) async throws {
        guard await isTrusted() else { throw InstallError.notTrusted }
        let server = try await startHTTPS()
        let base = "https://127.0.0.1:\(server.port)"
        let token = UUID().uuidString.prefix(8)
        server.setRoute("/\(token)/app.ipa", .init(contentType: "application/octet-stream", body: .file(signedIPA)))

        let manifest: [String: Any] = [
            "items": [[
                "assets": [[
                    "kind": "software-package",
                    "url": "\(base)/\(token)/app.ipa"
                ]],
                "metadata": [
                    "bundle-identifier": bundleID,
                    "bundle-version": version,
                    "kind": "software",
                    "title": title
                ]
            ]]
        ]
        let manifestData = try PropertyListSerialization.data(fromPropertyList: manifest, format: .xml, options: 0)
        server.setRoute("/\(token)/manifest.plist", .init(contentType: "text/xml", body: .data(manifestData)))

        keepAlive(seconds: 170)
        let manifestURL = "\(base)/\(token)/manifest.plist"
        let encoded = manifestURL.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? manifestURL
        if let url = URL(string: "itms-services://?action=download-manifest&url=\(encoded)") {
            await UIApplication.shared.open(url)
        }
    }

    /// Keeps the app (and therefore the loopback server) alive while iOS downloads the app.
    private func keepAlive(seconds: Double) {
        if backgroundTask != .invalid {
            UIApplication.shared.endBackgroundTask(backgroundTask)
        }
        backgroundTask = UIApplication.shared.beginBackgroundTask(withName: "IPABeam-Install") { [weak self] in
            Task { @MainActor in self?.endKeepAlive() }
        }
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            self?.endKeepAlive()
        }
    }

    private func endKeepAlive() {
        guard backgroundTask != .invalid else { return }
        UIApplication.shared.endBackgroundTask(backgroundTask)
        backgroundTask = .invalid
    }
}
