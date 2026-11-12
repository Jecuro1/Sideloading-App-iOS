import SwiftUI
import UIKit

/// Sample content shown when launched with `-demo <scenario>` (used for simulator screenshots).
/// Scenarios: ready, empty, run, library, certs, more
extension AppState {
    func loadDemo(_ scenario: String) {
        let nebula = Self.demoIcon(hue: 0.75, symbol: "sparkles")
        apps = [
            demoApp("Nebula Notes", "com.example.nebulanotes", "2.4.1", "128", 48_213_000, nebula, extensions: true),
            demoApp("Pixel Forge", "dev.alex.pixelforge", "1.0.3", "17", 22_400_000, Self.demoIcon(hue: 0.03, symbol: "paintbrush.pointed.fill")),
            demoApp("Orbit Player", "io.orbit.player", "5.2", "5.2", 61_900_000, Self.demoIcon(hue: 0.55, symbol: "play.fill")),
            demoApp("Trail Log", "app.traillog.ios", "3.1.0", "301", 18_700_000, Self.demoIcon(hue: 0.38, symbol: "map.fill")),
            demoApp("Synth Pad", "io.synthpad.app", "0.9", "90", 35_100_000, Self.demoIcon(hue: 0.88, symbol: "waveform")),
            demoApp("Retro Arcade", "app.retro.arcade", "1.6", "44", 74_300_000, Self.demoIcon(hue: 0.13, symbol: "gamecontroller.fill"))
        ]
        let profile = ProfileInfo(
            name: "IPA Beam Wildcard", teamName: "Alex Beispiel", teamID: "ABCDE12345",
            applicationIdentifier: "ABCDE12345.*", expirationDate: Date().addingTimeInterval(86_400 * 290),
            deviceCount: 3, provisionsAllDevices: false, isDevelopment: true
        )
        signingSets = [
            SigningSet(id: UUID(), certificateName: "Apple Development: Alex Beispiel (ABCDE12345)",
                       certificateFile: "", profileFile: "", profile: profile, addedAt: Date()),
            SigningSet(id: UUID(), certificateName: "Apple Development: Test Team",
                       certificateFile: "", profileFile: "",
                       profile: ProfileInfo(name: "Free Profile", teamName: "Test Team", teamID: "ZYXWV98765",
                                            applicationIdentifier: "ZYXWV98765.com.example.nebulanotes",
                                            expirationDate: Date().addingTimeInterval(86_400 * 5),
                                            deviceCount: 1, provisionsAllDevices: false, isDevelopment: true),
                       addedAt: Date())
        ]
        selectedAppID = apps.first?.id
        selectedSigningID = signingSets.first?.id

        switch scenario {
        case "empty":
            apps = []
            selectedAppID = nil
        case "library":
            tab = .library
        case "certs":
            tab = .certificates
        case "more":
            tab = .settings
        case "run":
            run = BeamRun(steps: [.certificate: .done, .profile: .done, .sign: .running, .install: .pending],
                          message: nil, finished: false)
        default:
            break
        }
    }

    private func demoApp(_ name: String, _ bundleID: String, _ version: String, _ build: String,
                         _ size: Int64, _ icon: Data?, extensions: Bool = false) -> LibraryApp {
        LibraryApp(id: UUID(), fileName: "", name: name, bundleID: bundleID, version: version, build: build,
                   minimumOSVersion: "17.0", size: size, hasExtensions: extensions, iconData: icon, importedAt: Date())
    }

    static func demoIcon(hue: Double, symbol: String) -> Data? {
        let view = ZStack {
            LinearGradient(colors: [Color(hue: hue, saturation: 0.65, brightness: 1.0),
                                    Color(hue: fract(hue + 0.1), saturation: 0.9, brightness: 0.55)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            Circle().fill(.white.opacity(0.18)).frame(width: 150).offset(x: 50, y: -60).blur(radius: 12)
            Image(systemName: symbol)
                .font(.system(size: 84, weight: .semibold))
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.25), radius: 6, y: 3)
        }
        .frame(width: 180, height: 180)
        let renderer = ImageRenderer(content: view)
        renderer.scale = 1
        return renderer.uiImage?.pngData()
    }
}
