import Foundation

/// Which tool chain is used to talk to a device.
enum DeviceBackend: String, Codable, Sendable {
    case devicectl
    case libimobiledevice

    var title: String {
        switch self {
        case .devicectl: return "Apple devicectl"
        case .libimobiledevice: return "libimobiledevice"
        }
    }
}

/// User preference for the backend.
enum BackendPreference: String, CaseIterable, Identifiable, Codable, Sendable {
    case automatic
    case devicectl
    case libimobiledevice

    var id: String { rawValue }

    var title: String {
        switch self {
        case .automatic: return "Automatisch (empfohlen)"
        case .devicectl: return "Nur Apple devicectl (Xcode)"
        case .libimobiledevice: return "Nur libimobiledevice"
        }
    }
}

enum ConnectionType: String, Codable, Sendable {
    case usb
    case wifi
    case offline

    var title: String {
        switch self {
        case .usb: return "USB‑C"
        case .wifi: return "WLAN"
        case .offline: return "Offline"
        }
    }

    var symbol: String {
        switch self {
        case .usb: return "cable.connector"
        case .wifi: return "wifi"
        case .offline: return "moon.zzz.fill"
        }
    }
}

struct Device: Identifiable, Hashable, Sendable {
    /// Identifier passed to the backend (CoreDevice identifier or UDID).
    var id: String
    var udid: String?
    var name: String
    var model: String
    var osVersion: String
    var deviceClass: String
    var connection: ConnectionType
    var backend: DeviceBackend
    var needsTrust: Bool = false
    var developerModeEnabled: Bool?

    var isAvailable: Bool { connection != .offline && !needsTrust }

    var symbol: String {
        deviceClass.lowercased().contains("ipad") ? "ipad" : "iphone"
    }

    var subtitle: String {
        var parts: [String] = []
        if !model.isEmpty { parts.append(model) }
        if !osVersion.isEmpty { parts.append("iOS \(osVersion)") }
        return parts.joined(separator: " · ")
    }

    var connectionDescription: String {
        switch connection {
        case .usb: return "Verbunden über USB‑C"
        case .wifi: return "Verbunden über WLAN"
        case .offline: return "Nicht erreichbar"
        }
    }
}

enum DeviceNames {
    private static let names: [String: String] = [
        "iPhone12,1": "iPhone 11", "iPhone12,3": "iPhone 11 Pro", "iPhone12,5": "iPhone 11 Pro Max",
        "iPhone12,8": "iPhone SE (2. Gen.)",
        "iPhone13,1": "iPhone 12 mini", "iPhone13,2": "iPhone 12", "iPhone13,3": "iPhone 12 Pro",
        "iPhone13,4": "iPhone 12 Pro Max",
        "iPhone14,4": "iPhone 13 mini", "iPhone14,5": "iPhone 13", "iPhone14,2": "iPhone 13 Pro",
        "iPhone14,3": "iPhone 13 Pro Max", "iPhone14,6": "iPhone SE (3. Gen.)",
        "iPhone14,7": "iPhone 14", "iPhone14,8": "iPhone 14 Plus", "iPhone15,2": "iPhone 14 Pro",
        "iPhone15,3": "iPhone 14 Pro Max",
        "iPhone15,4": "iPhone 15", "iPhone15,5": "iPhone 15 Plus", "iPhone16,1": "iPhone 15 Pro",
        "iPhone16,2": "iPhone 15 Pro Max",
        "iPhone17,3": "iPhone 16", "iPhone17,4": "iPhone 16 Plus", "iPhone17,1": "iPhone 16 Pro",
        "iPhone17,2": "iPhone 16 Pro Max", "iPhone17,5": "iPhone 16e"
    ]

    static func marketingName(for productType: String) -> String {
        names[productType] ?? productType
    }
}
