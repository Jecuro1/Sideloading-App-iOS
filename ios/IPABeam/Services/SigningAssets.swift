import Foundation
import Security

enum SigningAssetError: LocalizedError {
    case wrongPassword
    case invalidCertificate
    case invalidProfile

    var errorDescription: String? {
        switch self {
        case .wrongPassword: return "Das Passwort für das Zertifikat ist falsch."
        case .invalidCertificate: return "Die .p12-Datei enthält kein gültiges Zertifikat."
        case .invalidProfile: return "Das Provisioning-Profil konnte nicht gelesen werden."
        }
    }
}

enum SigningAssets {
    /// Opens a .p12 with its password and returns the certificate's display name.
    static func certificateName(p12: Data, password: String) throws -> String {
        let options = [kSecImportExportPassphrase as String: password] as CFDictionary
        var items: CFArray?
        let status = SecPKCS12Import(p12 as CFData, options, &items)
        if status == errSecAuthFailed { throw SigningAssetError.wrongPassword }
        guard status == errSecSuccess,
              let list = items as? [[String: Any]],
              let first = list.first,
              let identityRef = first[kSecImportItemIdentity as String] else {
            throw SigningAssetError.invalidCertificate
        }
        let identity = identityRef as! SecIdentity // swiftlint:disable:this force_cast
        var certificate: SecCertificate?
        SecIdentityCopyCertificate(identity, &certificate)
        guard let certificate else { throw SigningAssetError.invalidCertificate }
        return (SecCertificateCopySubjectSummary(certificate) as String?) ?? "Zertifikat"
    }

    /// Reads the plain XML plist embedded in a .mobileprovision.
    static func readProfile(_ data: Data) throws -> ProfileInfo {
        guard let start = data.range(of: Data("<?xml".utf8)),
              let end = data.range(of: Data("</plist>".utf8), in: start.lowerBound..<data.endIndex),
              let plist = try? PropertyListSerialization.propertyList(
                  from: data.subdata(in: start.lowerBound..<end.upperBound), format: nil
              ) as? [String: Any] else {
            throw SigningAssetError.invalidProfile
        }
        let entitlements = plist["Entitlements"] as? [String: Any] ?? [:]
        let teamID = (plist["TeamIdentifier"] as? [String])?.first
            ?? entitlements["com.apple.developer.team-identifier"] as? String
            ?? ""
        return ProfileInfo(
            name: plist["Name"] as? String ?? "Profil",
            teamName: plist["TeamName"] as? String ?? "",
            teamID: teamID,
            applicationIdentifier: entitlements["application-identifier"] as? String ?? "\(teamID).*",
            expirationDate: plist["ExpirationDate"] as? Date ?? .distantPast,
            deviceCount: (plist["ProvisionedDevices"] as? [String])?.count ?? 0,
            provisionsAllDevices: plist["ProvisionsAllDevices"] as? Bool ?? false,
            isDevelopment: entitlements["get-task-allow"] as? Bool ?? false
        )
    }
}

/// Stores certificate passwords in the iOS keychain.
enum PasswordVault {
    private static let service = "app.ipabeam.ios.p12"

    static func save(_ password: String, for id: UUID) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: id.uuidString
        ]
        SecItemDelete(query as CFDictionary)
        var item = query
        item[kSecValueData as String] = Data(password.utf8)
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(item as CFDictionary, nil)
    }

    static func load(for id: UUID) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: id.uuidString,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func delete(for id: UUID) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: id.uuidString
        ]
        SecItemDelete(query as CFDictionary)
    }
}
