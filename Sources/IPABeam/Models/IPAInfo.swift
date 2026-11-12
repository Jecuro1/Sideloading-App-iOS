import Foundation

/// Metadata read from an .ipa file without fully extracting it.
struct IPAInfo: Identifiable, Hashable, Sendable {
    var id: String { url.path }
    let url: URL
    let displayName: String
    let bundleID: String
    let version: String
    let build: String
    let minimumOSVersion: String?
    let fileSize: Int64
    let iconData: Data?
    let hasExtensions: Bool

    var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: fileSize, countStyle: .file)
    }

    var versionLabel: String {
        build.isEmpty || build == version ? "v\(version)" : "v\(version) (\(build))"
    }
}

/// A previously opened IPA, persisted for the "Zuletzt verwendet" list.
struct RecentIPA: Identifiable, Codable, Hashable, Sendable {
    var id: String { path }
    let path: String
    let name: String
    let bundleID: String
    let version: String
    let iconData: Data?
    var lastUsed: Date

    var url: URL { URL(fileURLWithPath: path) }
    var exists: Bool { FileManager.default.fileExists(atPath: path) }

    init(info: IPAInfo) {
        path = info.url.path
        name = info.displayName
        bundleID = info.bundleID
        version = info.version
        iconData = info.iconData
        lastUsed = Date()
    }
}
