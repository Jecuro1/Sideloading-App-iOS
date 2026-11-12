import AppKit
import SwiftUI

@main
struct IPABeamApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var model = AppModel.shared

    var body: some Scene {
        WindowGroup("IPA Beam") {
            ContentView()
                .environment(model)
                .frame(minWidth: 960, minHeight: 660)
        }
        .windowToolbarStyle(.unified(showsTitle: false))
        .defaultSize(width: 1120, height: 760)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("IPA öffnen …") { model.presentImporter = true }
                    .keyboardShortcut("o")
            }
            CommandMenu("Gerät") {
                Button("Geräte aktualisieren") {
                    Task { await model.refreshDevices() }
                }
                .keyboardShortcut("r")

                Button("Installieren") { model.install() }
                    .keyboardShortcut(.return, modifiers: .command)
                    .disabled(model.installBlocker != nil || model.isInstalling)
            }
            CommandGroup(replacing: .help) {
                Button("Einrichtungshilfe anzeigen") { model.showOnboarding = true }
            }
        }

        Settings {
            SettingsView()
                .environment(model)
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Needed when launched via `swift run` (no app bundle) so the window comes to front.
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        guard let ipa = urls.first(where: { $0.pathExtension.lowercased() == "ipa" }) else { return }
        Task { @MainActor in
            await AppModel.shared.loadIPA(at: ipa)
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}
