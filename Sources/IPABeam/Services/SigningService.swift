import Foundation

struct SigningIdentity: Identifiable, Hashable, Sendable {
    /// SHA-1 fingerprint used by codesign.
    let id: String
    let name: String

    /// Team id is shown in parentheses at the end, e.g. "Apple Development: Max (ABCDE12345)".
    var teamID: String? {
        guard let groups = TextMatching.firstMatch(#"\(([A-Z0-9]{10})\)\s*$"#, in: name), groups.count > 1 else {
            return nil
        }
        return groups[1]
    }

    var shortName: String {
        name.replacingOccurrences(of: #"\s*\([A-Z0-9]{10}\)\s*$"#, with: "", options: .regularExpression)
    }
}

struct ProvisioningProfile: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let teamName: String
    let teamID: String
    let applicationIdentifier: String
    let expirationDate: Date
    let provisionedDevices: [String]
    let provisionsAllDevices: Bool
    let url: URL
    let entitlementsData: Data

    /// e.g. "com.example.app", "com.example.*" or "*"
    var bundleIDPattern: String {
        let prefix = teamID + "."
        return applicationIdentifier.hasPrefix(prefix)
            ? String(applicationIdentifier.dropFirst(prefix.count))
            : applicationIdentifier
    }

    var isWildcard: Bool { bundleIDPattern.hasSuffix("*") }
    var isExpired: Bool { expirationDate < Date() }

    func includes(udid: String?) -> Bool {
        if provisionsAllDevices { return true }
        guard let udid else { return true }
        return provisionedDevices.contains { $0.caseInsensitiveCompare(udid) == .orderedSame }
    }

    func matches(bundleID: String) -> Bool {
        let pattern = bundleIDPattern
        if pattern == "*" { return true }
        if pattern.hasSuffix("*") { return bundleID.hasPrefix(String(pattern.dropLast())) }
        return pattern == bundleID
    }
}

struct SigningConfig: Sendable {
    let identity: SigningIdentity
    let profile: ProvisioningProfile
    let customBundleID: String?
    let removeExtensions: Bool
}

enum SigningError: LocalizedError {
    case missingBundleID
    case bundleIDNotAllowed(String, String)
    case invalidProfile

    var errorDescription: String? {
        switch self {
        case .missingBundleID:
            return "Die App hat keine Bundle-ID."
        case .bundleIDNotAllowed(let id, let pattern):
            return "Die Bundle-ID „\(id)“ passt nicht zum Profil („\(pattern)“)."
        case .invalidProfile:
            return "Das Provisioning-Profil konnte nicht gelesen werden."
        }
    }
}

enum SigningService {
    // MARK: Discovery

    static func loadIdentities() async -> [SigningIdentity] {
        guard let result = try? await ProcessRunner.run(
            SystemTool.security, ["find-identity", "-v", "-p", "codesigning"], timeout: 20
        ), result.succeeded else { return [] }

        var identities: [SigningIdentity] = []
        for line in result.stdout.split(whereSeparator: \.isNewline) {
            guard let groups = TextMatching.firstMatch(#"^\s*\d+\)\s+([0-9A-F]{40})\s+"(.+)""#, in: String(line)),
                  groups.count > 2 else { continue }
            if !identities.contains(where: { $0.id == groups[1] }) {
                identities.append(SigningIdentity(id: groups[1], name: groups[2]))
            }
        }
        return identities.sorted { $0.name < $1.name }
    }

    static var profileDirectories: [URL] {
        let library = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library")
        return [
            library.appendingPathComponent("Developer/Xcode/UserData/Provisioning Profiles"),
            library.appendingPathComponent("MobileDevice/Provisioning Profiles")
        ]
    }

    static func loadProfiles() async -> [ProvisioningProfile] {
        var profiles: [ProvisioningProfile] = []
        for directory in profileDirectories {
            let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
            for file in files where file.pathExtension == "mobileprovision" {
                if let profile = try? await readProfile(at: file),
                   !profiles.contains(where: { $0.id == profile.id }) {
                    profiles.append(profile)
                }
            }
        }
        return profiles
            .filter { !$0.isExpired }
            .sorted { $0.expirationDate > $1.expirationDate }
    }

    static func readProfile(at url: URL) async throws -> ProvisioningProfile {
        let raw = try Data(contentsOf: url)
        var plistData = embeddedPlist(in: raw)
        if plistData == nil {
            let decoded = try await ProcessRunner.run(SystemTool.security, ["cms", "-D", "-i", url.path], timeout: 20)
            if decoded.succeeded { plistData = decoded.stdoutData }
        }
        guard let plistData,
              let plist = try? PropertyListSerialization.propertyList(from: plistData, format: nil) as? [String: Any],
              let uuid = plist["UUID"] as? String,
              let entitlements = plist["Entitlements"] as? [String: Any] else {
            throw SigningError.invalidProfile
        }

        if let platforms = plist["Platform"] as? [String], !platforms.contains("iOS") {
            throw SigningError.invalidProfile
        }

        let teamID = (plist["TeamIdentifier"] as? [String])?.first
            ?? (entitlements["com.apple.developer.team-identifier"] as? String)
            ?? ""
        let entitlementsData = try PropertyListSerialization.data(fromPropertyList: entitlements, format: .xml, options: 0)

        return ProvisioningProfile(
            id: uuid,
            name: plist["Name"] as? String ?? url.lastPathComponent,
            teamName: plist["TeamName"] as? String ?? "",
            teamID: teamID,
            applicationIdentifier: entitlements["application-identifier"] as? String ?? "\(teamID).*",
            expirationDate: plist["ExpirationDate"] as? Date ?? .distantPast,
            provisionedDevices: plist["ProvisionedDevices"] as? [String] ?? [],
            provisionsAllDevices: plist["ProvisionsAllDevices"] as? Bool ?? false,
            url: url,
            entitlementsData: entitlementsData
        )
    }

    /// A .mobileprovision is a CMS envelope with a plain XML plist inside – grab it directly.
    private static func embeddedPlist(in data: Data) -> Data? {
        guard let start = data.range(of: Data("<?xml".utf8)),
              let end = data.range(of: Data("</plist>".utf8), in: start.lowerBound..<data.endIndex) else {
            return nil
        }
        return data.subdata(in: start.lowerBound..<end.upperBound)
    }

    // MARK: Re-signing

    static func targetBundleID(original: String, profile: ProvisioningProfile, custom: String?) throws -> String {
        let pattern = profile.bundleIDPattern
        if let custom = custom?.trimmingCharacters(in: .whitespaces), !custom.isEmpty {
            guard profile.matches(bundleID: custom) else {
                throw SigningError.bundleIDNotAllowed(custom, pattern)
            }
            return custom
        }
        if profile.matches(bundleID: original) { return original }
        if pattern.hasSuffix(".*") {
            return String(pattern.dropLast(2)) + "." + original
        }
        return pattern
    }

    /// Re-signs an extracted `.app` in place. Returns the final bundle identifier.
    static func resign(
        app appURL: URL,
        config: SigningConfig,
        workDirectory: URL,
        log: @escaping @Sendable (String) -> Void
    ) async throws -> String {
        let fileManager = FileManager.default
        let profile = config.profile

        if config.removeExtensions {
            for folder in ["PlugIns", "Extensions", "Watch", "AppClips"] {
                let url = appURL.appendingPathComponent(folder)
                if fileManager.fileExists(atPath: url.path) {
                    try fileManager.removeItem(at: url)
                    log("Entfernt: \(folder)")
                }
            }
        }

        // Bundle identifier
        let infoURL = appURL.appendingPathComponent("Info.plist")
        var info = try readPlist(infoURL)
        guard let originalID = info["CFBundleIdentifier"] as? String else { throw SigningError.missingBundleID }
        let newID = try targetBundleID(original: originalID, profile: profile, custom: config.customBundleID)
        if newID != originalID {
            info["CFBundleIdentifier"] = newID
            try writePlist(info, to: infoURL)
            log("Bundle-ID: \(originalID) → \(newID)")
        } else {
            log("Bundle-ID: \(newID)")
        }

        // Embed provisioning profile
        try replaceItem(at: appURL.appendingPathComponent("embedded.mobileprovision"), with: profile.url)
        log("Profil eingebettet: \(profile.name)")

        let baseEntitlements = (try? PropertyListSerialization.propertyList(
            from: profile.entitlementsData, format: nil
        ) as? [String: Any]) ?? [:]

        var entitlementCounter = 0
        func entitlementsFile(for bundleID: String) throws -> URL {
            var entitlements = baseEntitlements
            entitlements["application-identifier"] = "\(profile.teamID).\(bundleID)"
            if !profile.teamID.isEmpty {
                entitlements["com.apple.developer.team-identifier"] = profile.teamID
            }
            entitlementCounter += 1
            let url = workDirectory.appendingPathComponent("entitlements-\(entitlementCounter).plist")
            try writePlist(entitlements, to: url)
            return url
        }

        // Sign nested code from the deepest level upwards.
        let nested = nestedCode(in: appURL)
        for item in nested {
            try Task.checkCancellation()
            let ext = item.pathExtension.lowercased()
            let relative = item.path.replacingOccurrences(of: appURL.path + "/", with: "")
            if ext == "appex" || ext == "app" {
                let nestedInfoURL = item.appendingPathComponent("Info.plist")
                var nestedInfo = (try? readPlist(nestedInfoURL)) ?? [:]
                var nestedID = nestedInfo["CFBundleIdentifier"] as? String ?? newID
                if nestedID.hasPrefix(originalID), newID != originalID {
                    nestedID = newID + nestedID.dropFirst(originalID.count)
                    nestedInfo["CFBundleIdentifier"] = nestedID
                }
                if let companion = nestedInfo["WKCompanionAppBundleIdentifier"] as? String, companion == originalID {
                    nestedInfo["WKCompanionAppBundleIdentifier"] = newID
                }
                if !nestedInfo.isEmpty { try writePlist(nestedInfo, to: nestedInfoURL) }
                if !profile.matches(bundleID: nestedID) {
                    log("⚠︎ \(relative) (\(nestedID)) passt nicht zum Profil – ggf. „Erweiterungen entfernen“ aktivieren.")
                }
                try replaceItem(at: item.appendingPathComponent("embedded.mobileprovision"), with: profile.url)
                try await codesign(item, identity: config.identity, entitlements: entitlementsFile(for: nestedID))
            } else {
                try await codesign(item, identity: config.identity, entitlements: nil)
            }
            log("Signiert: \(relative)")
        }

        try await codesign(appURL, identity: config.identity, entitlements: entitlementsFile(for: newID))
        log("Signiert: \(appURL.lastPathComponent) mit \(config.identity.shortName)")

        let verify = try await ProcessRunner.run(SystemTool.codesign, ["--verify", "--deep", "--strict", appURL.path])
        if verify.succeeded {
            log("Signatur geprüft ✓")
        } else {
            log("⚠︎ Signaturprüfung meldet: \(verify.combinedOutput)")
        }
        return newID
    }

    private static func codesign(_ url: URL, identity: SigningIdentity, entitlements: URL?) async throws {
        var args = ["--force", "--sign", identity.id, "--timestamp=none"]
        if let entitlements {
            args += ["--entitlements", entitlements.path, "--generate-entitlement-der"]
        }
        args.append(url.path)
        try await ProcessRunner.runChecked(SystemTool.codesign, args, timeout: 300, name: "codesign")
    }

    /// All frameworks, dylibs, app extensions and nested apps – deepest first.
    private static func nestedCode(in appURL: URL) -> [URL] {
        var result: [URL] = []
        guard let enumerator = FileManager.default.enumerator(
            at: appURL, includingPropertiesForKeys: [.isSymbolicLinkKey], options: []
        ) else { return [] }

        for case let url as URL in enumerator {
            let isLink = (try? url.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) ?? false
            if isLink { continue }
            switch url.pathExtension.lowercased() {
            case "framework", "dylib", "appex", "app", "xpc":
                result.append(url)
            default:
                break
            }
        }
        return result.sorted { $0.pathComponents.count > $1.pathComponents.count }
    }

    private static func readPlist(_ url: URL) throws -> [String: Any] {
        let data = try Data(contentsOf: url)
        guard let plist = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else {
            throw IPAError.invalidInfoPlist
        }
        return plist
    }

    private static func writePlist(_ plist: [String: Any], to url: URL) throws {
        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        try data.write(to: url, options: .atomic)
    }

    private static func replaceItem(at destination: URL, with source: URL) throws {
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: destination.path) {
            try fileManager.removeItem(at: destination)
        }
        try fileManager.copyItem(at: source, to: destination)
    }
}
