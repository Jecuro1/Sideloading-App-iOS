import Foundation
import ZIPFoundation

enum IPAReaderError: LocalizedError {
    case notAnArchive
    case noApplication
    case invalidInfoPlist

    var errorDescription: String? {
        switch self {
        case .notAnArchive: return "Die Datei ist kein gültiges IPA-Archiv."
        case .noApplication: return "Im IPA wurde keine App (Payload/*.app) gefunden."
        case .invalidInfoPlist: return "Die Info.plist der App konnte nicht gelesen werden."
        }
    }
}

struct IPAMetadata {
    var name: String
    var bundleID: String
    var version: String
    var build: String
    var minimumOSVersion: String?
    var hasExtensions: Bool
    var iconData: Data?
}

/// Reads Info.plist and the app icon straight out of the zip.
/// UIKit decodes Apple's "CgBI" PNG icons natively, so the raw bytes can be used as-is.
enum IPAReader {
    static func read(_ url: URL) throws -> IPAMetadata {
        let archive: Archive
        do {
            archive = try Archive(url: url, accessMode: .read)
        } catch {
            throw IPAReaderError.notAnArchive
        }

        var entries: [Entry] = []
        for entry in archive { entries.append(entry) }

        guard let infoEntry = entries.first(where: { isMainInfoPlist($0.path) }) else {
            throw IPAReaderError.noApplication
        }
        let appDirectory = String(infoEntry.path.dropLast("Info.plist".count))

        let plistData = try data(of: infoEntry, in: archive)
        guard let info = try? PropertyListSerialization.propertyList(from: plistData, format: nil) as? [String: Any] else {
            throw IPAReaderError.invalidInfoPlist
        }

        var iconData: Data?
        if let iconEntry = bestIcon(info: info, entries: entries, appDirectory: appDirectory) {
            iconData = try? data(of: iconEntry, in: archive)
        }

        let hasExtensions = entries.contains { entry in
            ["PlugIns/", "Watch/", "Extensions/"].contains { entry.path.hasPrefix(appDirectory + $0) }
        }

        return IPAMetadata(
            name: (info["CFBundleDisplayName"] as? String)
                ?? (info["CFBundleName"] as? String)
                ?? url.deletingPathExtension().lastPathComponent,
            bundleID: info["CFBundleIdentifier"] as? String ?? "unbekannt",
            version: info["CFBundleShortVersionString"] as? String ?? "1.0",
            build: info["CFBundleVersion"] as? String ?? "",
            minimumOSVersion: info["MinimumOSVersion"] as? String,
            hasExtensions: hasExtensions,
            iconData: iconData
        )
    }

    private static func data(of entry: Entry, in archive: Archive) throws -> Data {
        var result = Data()
        _ = try archive.extract(entry, skipCRC32: true) { chunk in
            result.append(chunk)
        }
        return result
    }

    private static func isMainInfoPlist(_ path: String) -> Bool {
        let parts = path.split(separator: "/", omittingEmptySubsequences: false)
        return parts.count == 3 && parts[0] == "Payload" && parts[1].hasSuffix(".app") && parts[2] == "Info.plist"
    }

    private static func bestIcon(info: [String: Any], entries: [Entry], appDirectory: String) -> Entry? {
        var bases: [String] = []
        for key in ["CFBundleIcons", "CFBundleIcons~ipad"] {
            if let icons = info[key] as? [String: Any],
               let primary = icons["CFBundlePrimaryIcon"] as? [String: Any] {
                bases += primary["CFBundleIconFiles"] as? [String] ?? []
                if let name = primary["CFBundleIconName"] as? String { bases.append(name) }
            }
        }
        bases += info["CFBundleIconFiles"] as? [String] ?? []
        bases.append("AppIcon")
        bases = bases.map { $0.replacingOccurrences(of: ".png", with: "") }.filter { !$0.isEmpty }

        let candidates = entries.filter { entry in
            guard entry.path.hasPrefix(appDirectory), entry.path.lowercased().hasSuffix(".png") else { return false }
            let file = String(entry.path.dropFirst(appDirectory.count))
            return !file.contains("/") && bases.contains { file.hasPrefix($0) }
        }

        func score(_ path: String) -> Int {
            var value = 0
            if path.contains("@3x") { value += 30 } else if path.contains("@2x") { value += 20 }
            if path.contains("60x60") || path.contains("76x76") || path.contains("83.5") { value += 10 }
            if path.contains("~ipad") { value -= 5 }
            return value
        }
        return candidates.max { score($0.path) < score($1.path) }
    }
}
