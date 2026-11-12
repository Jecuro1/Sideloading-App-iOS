import Foundation

enum IPAError: LocalizedError {
    case notAnArchive
    case noApplication
    case invalidInfoPlist
    case extractionFailed

    var errorDescription: String? {
        switch self {
        case .notAnArchive:
            return "Die Datei ist kein gültiges IPA-Archiv."
        case .noApplication:
            return "Im IPA wurde keine App (Payload/*.app) gefunden."
        case .invalidInfoPlist:
            return "Die Info.plist der App konnte nicht gelesen werden."
        case .extractionFailed:
            return "Das IPA konnte nicht entpackt werden."
        }
    }
}

enum IPAInspector {
    /// Reads name, bundle id, version and icon directly from the zip without extracting everything.
    static func inspect(_ url: URL) async throws -> IPAInfo {
        let listing = try await ProcessRunner.run(SystemTool.unzip, ["-Z1", url.path], timeout: 60, name: "unzip")
        guard listing.succeeded else { throw IPAError.notAnArchive }

        let entries = listing.stdout
            .split(whereSeparator: \.isNewline)
            .map(String.init)

        guard let infoEntry = entries.first(where: isMainInfoPlist) else {
            throw IPAError.noApplication
        }
        let appDirectory = String(infoEntry.dropLast("Info.plist".count))

        let plistData = try await extract(entry: infoEntry, from: url)
        guard let info = try? PropertyListSerialization.propertyList(from: plistData, format: nil) as? [String: Any] else {
            throw IPAError.invalidInfoPlist
        }

        let bundleID = info["CFBundleIdentifier"] as? String ?? "unbekannt"
        let name = (info["CFBundleDisplayName"] as? String)
            ?? (info["CFBundleName"] as? String)
            ?? url.deletingPathExtension().lastPathComponent

        var iconData: Data?
        if let iconEntry = bestIconEntry(info: info, entries: entries, appDirectory: appDirectory) {
            iconData = try? await extract(entry: iconEntry, from: url)
        }

        let hasExtensions = entries.contains { entry in
            entry.hasPrefix(appDirectory + "PlugIns/") || entry.hasPrefix(appDirectory + "Watch/")
                || entry.hasPrefix(appDirectory + "Extensions/")
        }

        let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
        let size = (attributes?[.size] as? NSNumber)?.int64Value ?? 0

        return IPAInfo(
            url: url,
            displayName: name,
            bundleID: bundleID,
            version: info["CFBundleShortVersionString"] as? String ?? "1.0",
            build: info["CFBundleVersion"] as? String ?? "",
            minimumOSVersion: info["MinimumOSVersion"] as? String,
            fileSize: size,
            iconData: iconData,
            hasExtensions: hasExtensions
        )
    }

    /// Fully extracts the IPA into `directory` and returns the URL of the `.app` bundle.
    static func extract(_ ipa: URL, to directory: URL, log: @escaping @Sendable (String) -> Void) async throws -> URL {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        log("Entpacke \(ipa.lastPathComponent) …")
        try await ProcessRunner.runChecked(SystemTool.ditto, ["-x", "-k", ipa.path, directory.path], name: "ditto")

        let payload = directory.appendingPathComponent("Payload")
        let contents = (try? FileManager.default.contentsOfDirectory(at: payload, includingPropertiesForKeys: nil)) ?? []
        guard let app = contents.first(where: { $0.pathExtension == "app" }) else {
            throw IPAError.noApplication
        }
        log("App gefunden: \(app.lastPathComponent)")
        return app
    }

    /// Packs `<directory>/Payload` into a new IPA.
    static func package(directory: URL, to output: URL, log: @escaping @Sendable (String) -> Void) async throws {
        log("Erzeuge signiertes IPA …")
        try? FileManager.default.removeItem(at: output)
        try await ProcessRunner.runChecked(
            SystemTool.zip,
            ["-qry", output.path, "Payload"],
            currentDirectory: directory,
            name: "zip"
        )
    }

    // MARK: - Helpers

    private static func isMainInfoPlist(_ entry: String) -> Bool {
        let parts = entry.split(separator: "/", omittingEmptySubsequences: false)
        return parts.count == 3
            && parts[0] == "Payload"
            && parts[1].hasSuffix(".app")
            && parts[2] == "Info.plist"
    }

    private static func extract(entry: String, from archive: URL) async throws -> Data {
        let result = try await ProcessRunner.run(
            SystemTool.unzip, ["-p", archive.path, escapeWildcards(entry)], timeout: 60, name: "unzip"
        )
        guard result.succeeded, !result.stdoutData.isEmpty else { throw IPAError.extractionFailed }
        return result.stdoutData
    }

    /// unzip treats *, ? and [ ] as wildcards – escape them so names match literally.
    private static func escapeWildcards(_ name: String) -> String {
        var escaped = ""
        for character in name {
            switch character {
            case "[": escaped += "[[]"
            case "*", "?": escaped += "[\(character)]"
            default: escaped.append(character)
            }
        }
        return escaped
    }

    private static func bestIconEntry(info: [String: Any], entries: [String], appDirectory: String) -> String? {
        var baseNames: [String] = []
        for key in ["CFBundleIcons", "CFBundleIcons~ipad"] {
            if let icons = info[key] as? [String: Any],
               let primary = icons["CFBundlePrimaryIcon"] as? [String: Any] {
                baseNames += primary["CFBundleIconFiles"] as? [String] ?? []
                if let name = primary["CFBundleIconName"] as? String { baseNames.append(name) }
            }
        }
        baseNames += info["CFBundleIconFiles"] as? [String] ?? []
        if let file = info["CFBundleIconFile"] as? String { baseNames.append(file) }
        baseNames.append("AppIcon")

        let rootPNGs = entries.filter { entry in
            guard entry.hasPrefix(appDirectory), entry.lowercased().hasSuffix(".png") else { return false }
            return !entry.dropFirst(appDirectory.count).contains("/")
        }

        let candidates = rootPNGs.filter { entry in
            let file = String(entry.dropFirst(appDirectory.count))
            return baseNames.contains { base in
                let stripped = base.replacingOccurrences(of: ".png", with: "")
                return !stripped.isEmpty && file.hasPrefix(stripped)
            }
        }

        func score(_ entry: String) -> Int {
            var value = 0
            if entry.contains("@3x") { value += 30 } else if entry.contains("@2x") { value += 20 }
            if entry.contains("60x60") || entry.contains("76x76") || entry.contains("83.5") { value += 10 }
            if entry.contains("~ipad") { value -= 5 }
            return value
        }

        return candidates.max { score($0) < score($1) }
    }
}
