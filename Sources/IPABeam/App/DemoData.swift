import AppKit
import SwiftUI

/// Sample content used when the app is started with `IPABEAM_DEMO=<scenario>`.
/// Scenarios: idle, drop, ready, installing, success, failed.
/// Used to render screenshots on CI without a real iPhone attached.
extension AppModel {
    func loadDemo(_ scenario: String) {
        tools = ToolStatus(
            checked: true,
            devicectl: true,
            ideviceID: URL(fileURLWithPath: "/opt/homebrew/bin/idevice_id"),
            ideviceInfo: URL(fileURLWithPath: "/opt/homebrew/bin/ideviceinfo"),
            ideviceInstaller: URL(fileURLWithPath: "/opt/homebrew/bin/ideviceinstaller"),
            idevicePair: URL(fileURLWithPath: "/opt/homebrew/bin/idevicepair")
        )

        let udid = "00008140-001A2B3C4D5E801E"
        devices = [
            Device(id: "demo-iphone", udid: udid, name: "iPhone von Alex", model: "iPhone 16 Pro",
                   osVersion: "18.2", deviceClass: "iPhone", connection: .usb, backend: .devicectl,
                   developerModeEnabled: true),
            Device(id: "demo-ipad", udid: "00008103-000A11B22C33D44E", name: "iPad Air", model: "iPad Air (M2)",
                   osVersion: "18.1", deviceClass: "iPad", connection: .wifi, backend: .devicectl),
            Device(id: "demo-old", udid: "00008110-0009AA77BB66CC55", name: "Test-iPhone", model: "iPhone 13 mini",
                   osVersion: "17.6", deviceClass: "iPhone", connection: .offline, backend: .libimobiledevice)
        ]
        selectedDeviceID = scenario == "idle-nodevice" ? nil : "demo-iphone"
        if scenario == "idle-nodevice" { devices = [] }

        let mainIcon = Self.demoIcon(hue: 0.72, symbol: "sparkles")
        recents = [
            demoRecent(name: "Nebula Notes", bundleID: "com.example.nebulanotes", version: "2.4.1", icon: mainIcon),
            demoRecent(name: "Pixel Forge", bundleID: "dev.alex.pixelforge", version: "1.0.3",
                       icon: Self.demoIcon(hue: 0.03, symbol: "paintbrush.pointed.fill")),
            demoRecent(name: "Orbit Player", bundleID: "io.orbit.player", version: "5.2", icon: Self.demoIcon(hue: 0.5, symbol: "play.fill")),
            demoRecent(name: "Trail Log", bundleID: "app.traillog.ios", version: "3.1.0", icon: Self.demoIcon(hue: 0.33, symbol: "map.fill"))
        ]

        identities = [SigningIdentity(id: String(repeating: "A1", count: 20), name: "Apple Development: Alex Beispiel (ABCDE12345)")]
        profiles = [
            ProvisioningProfile(
                id: "demo-profile", name: "IPA Beam Wildcard", teamName: "Alex Beispiel", teamID: "ABCDE12345",
                applicationIdentifier: "ABCDE12345.*", expirationDate: Date().addingTimeInterval(86_400 * 290),
                provisionedDevices: [udid], provisionsAllDevices: false,
                url: URL(fileURLWithPath: "/dev/null"), entitlementsData: Data()
            )
        ]
        selectedIdentityID = identities.first?.id
        selectedProfileID = profiles.first?.id
        signingEnabled = true

        history = [
            demoFinishedJob(app: "Pixel Forge", device: "iPad Air", connection: .wifi),
            demoFinishedJob(app: "Orbit Player", device: "iPhone von Alex", connection: .usb)
        ]

        guard scenario != "idle", scenario != "idle-nodevice" else { return }
        if scenario == "drop" {
            forceDropTargeted = true
            return
        }

        let ipa = IPAInfo(
            url: URL(fileURLWithPath: "/Users/alex/Downloads/NebulaNotes.ipa"),
            displayName: "Nebula Notes",
            bundleID: "com.example.nebulanotes",
            version: "2.4.1",
            build: "128",
            minimumOSVersion: "17.0",
            fileSize: 48_213_000,
            iconData: mainIcon,
            hasExtensions: true
        )
        currentIPA = ipa
        guard scenario != "ready" else { return }

        let job = InstallJob(appName: ipa.displayName, bundleID: ipa.bundleID, deviceName: "iPhone von Alex", connection: .usb)
        job.append("Nebula Notes v2.4.1 (128) → iPhone von Alex (USB‑C, Apple devicectl)")
        job.begin(.prepare)
        job.append("Entpacke NebulaNotes.ipa …")
        job.append("App gefunden: NebulaNotes.app")
        job.complete(.prepare)
        job.begin(.sign)
        job.append("Entfernt: PlugIns")
        job.append("Bundle-ID: com.example.nebulanotes")
        job.append("Profil eingebettet: IPA Beam Wildcard")
        job.append("Signiert: Frameworks/NebulaKit.framework")
        job.append("Signiert: NebulaNotes.app mit Apple Development: Alex Beispiel")
        job.append("Signatur geprüft ✓")
        job.complete(.sign)
        job.begin(.install)
        job.append("Installing app on device…")
        job.append("42%… 58%… 64%…")
        job.installProgress = 0.64

        switch scenario {
        case "success":
            job.append("App installed: com.example.nebulanotes")
            job.succeed()
            history.insert(job, at: 0)
        case "failed":
            job.fail("„devicectl“ ist fehlgeschlagen (Code 1):\nThe operation couldn’t be completed. (Developer Mode disabled)\n\n💡 Aktiviere auf dem iPhone: Einstellungen → Datenschutz & Sicherheit → Entwicklermodus.")
        default:
            break
        }
        self.job = job
    }

    private func demoFinishedJob(app: String, device: String, connection: ConnectionType) -> InstallJob {
        let job = InstallJob(appName: app, bundleID: "", deviceName: device, connection: connection)
        job.skip(.sign)
        job.succeed()
        return job
    }

    private func demoRecent(name: String, bundleID: String, version: String, icon: Data?) -> RecentIPA {
        var recent = RecentIPA(info: IPAInfo(
            url: URL(fileURLWithPath: "/Users/alex/Downloads/\(name.replacingOccurrences(of: " ", with: "")).ipa"),
            displayName: name, bundleID: bundleID, version: version, build: "", minimumOSVersion: nil,
            fileSize: 0, iconData: icon, hasExtensions: false
        ))
        recent.lastUsed = Date()
        return recent
    }

    static func demoIcon(hue: Double, symbol: String) -> Data? {
        let view = ZStack {
            LinearGradient(
                colors: [Color(hue: hue, saturation: 0.65, brightness: 1.0),
                         Color(hue: fract(hue + 0.1), saturation: 0.9, brightness: 0.55)],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
            Circle()
                .fill(.white.opacity(0.18))
                .frame(width: 150)
                .offset(x: 50, y: -60)
                .blur(radius: 12)
            Image(systemName: symbol)
                .font(.system(size: 84, weight: .semibold))
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.25), radius: 6, y: 3)
        }
        .frame(width: 180, height: 180)

        let renderer = ImageRenderer(content: view)
        renderer.scale = 1
        guard let cgImage = renderer.cgImage else { return nil }
        return NSBitmapImageRep(cgImage: cgImage).representation(using: .png, properties: [:])
    }
}
