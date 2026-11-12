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
                .frame(minWidth: 1200, minHeight: 780)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1440, height: 900)
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
                .preferredColorScheme(.dark)
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.appearance = NSAppearance(named: .darkAqua)
        // Needed when launched without an app bundle (`swift run`) so the window comes to front.
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
