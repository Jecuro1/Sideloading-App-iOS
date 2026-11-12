import Foundation

/// An IPA stored in the app's library.
struct LibraryApp: Identifiable, Codable, Hashable {
    var id: UUID
    var fileName: String
    var name: String
    var bundleID: String
    var version: String
    var build: String
    var minimumOSVersion: String?
    var size: Int64
    var hasExtensions: Bool
    var iconData: Data?
    var importedAt: Date
    /// Set after a successful on-device install (used for the 7-day refresh reminder).
    var installedAt: Date?
    var expiresAt: Date?

    var versionLabel: String {
        build.isEmpty || build == version ? "v\(version)" : "v\(version) (\(build))"
    }

    var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
    }
}

/// Parsed .mobileprovision.
struct ProfileInfo: Codable, Hashable {
    var name: String
    var teamName: String
    var teamID: String
    var applicationIdentifier: String
    var expirationDate: Date
    var deviceCount: Int
    var provisionsAllDevices: Bool
    var isDevelopment: Bool

    var bundlePattern: String {
        let prefix = teamID + "."
        return applicationIdentifier.hasPrefix(prefix)
            ? String(applicationIdentifier.dropFirst(prefix.count))
            : applicationIdentifier
    }

    var isExpired: Bool { expirationDate < Date() }

    var daysLeft: Int {
        max(0, Calendar.current.dateComponents([.day], from: Date(), to: expirationDate).day ?? 0)
    }

    func allows(bundleID: String) -> Bool {
        let pattern = bundlePattern
        if pattern == "*" { return true }
        if pattern.hasSuffix("*") { return bundleID.hasPrefix(String(pattern.dropLast())) }
        return pattern == bundleID
    }
}

/// A signing identity: certificate (.p12) + provisioning profile.
struct SigningSet: Identifiable, Codable, Hashable {
    var id: UUID
    var certificateName: String
    var certificateFile: String
    var profileFile: String
    var profile: ProfileInfo
    var addedAt: Date
}

/// Steps of the on-device beam pipeline.
enum BeamStep: String, CaseIterable, Identifiable {
    case certificate
    case profile
    case sign
    case install

    var id: String { rawValue }

    var title: String {
        switch self {
        case .certificate: return "Zertifikat"
        case .profile: return "Profil"
        case .sign: return "Signieren"
        case .install: return "Installieren"
        }
    }

    var symbol: String {
        switch self {
        case .certificate: return "key.fill"
        case .profile: return "checkmark.shield.fill"
        case .sign: return "signature"
        case .install: return "arrow.down.app.fill"
        }
    }
}

enum StepState: Equatable {
    case pending, running, done, failed, upcoming
}

struct AppUpdate: Identifiable, Hashable {
    var id: UUID { app.id }
    var app: LibraryApp
    var source: SourceApp
    var version: SourceVersion
}
