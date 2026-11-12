import AppKit
import SwiftUI

struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettings()
                .tabItem { Label("Allgemein", systemImage: "gearshape") }
            SigningSettings()
                .tabItem { Label("Signierung", systemImage: "signature") }
            ToolSettings()
                .tabItem { Label("Werkzeuge", systemImage: "wrench.and.screwdriver") }
        }
        .frame(width: 560)
        .padding(.vertical, 8)
    }
}

private struct GeneralSettings: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        Form {
            Section {
                Picker("Installationsweg", selection: $model.backendPreference) {
                    ForEach(BackendPreference.allCases) { preference in
                        Text(preference.title).tag(preference)
                    }
                }
                Toggle("Geräte automatisch suchen", isOn: $model.autoRefresh)
            } footer: {
                Text("„Automatisch“ nutzt Apples devicectl (Xcode) und ergänzt Geräte über libimobiledevice, falls installiert. Beide unterstützen USB‑C und WLAN.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section("Drahtlos (WLAN)") {
                Text("1. iPhone einmal per USB‑C verbinden und vertrauen.\n2. Xcode → Window → Devices and Simulators → „Connect via network“ aktivieren – oder im Finder „Dieses iPhone im WLAN anzeigen“.\n3. Mac und iPhone im selben WLAN, iPhone entsperrt lassen.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .formStyle(.grouped)
    }
}

private struct SigningSettings: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        Form {
            Section {
                Toggle("IPA vor der Installation neu signieren", isOn: $model.signingEnabled)
                Picker("Zertifikat", selection: $model.selectedIdentityID) {
                    Text("Keins").tag(String?.none)
                    ForEach(model.identities) { identity in
                        Text(identity.name).tag(Optional(identity.id))
                    }
                }
                Picker("Provisioning-Profil", selection: $model.selectedProfileID) {
                    Text("Keins").tag(String?.none)
                    ForEach(model.profiles) { profile in
                        Text("\(profile.name) (\(profile.bundleIDPattern))").tag(Optional(profile.id))
                    }
                }
            }

            Section {
                TextField("Eigene Bundle-ID (optional)", text: $model.customBundleID, prompt: Text("z. B. com.deinname.app"))
                Toggle("App-Erweiterungen & Watch-App entfernen", isOn: $model.removeExtensions)
            } footer: {
                Text("Kostenlose Apple‑IDs erlauben nur explizite App-IDs ohne Erweiterungen. Apps laufen dann 7 Tage und müssen danach neu installiert werden.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section {
                HStack {
                    Button("Zertifikate & Profile neu laden") {
                        Task { await model.reloadSigningAssets() }
                    }
                    if model.isLoadingSigningAssets {
                        ProgressView().controlSize(.small)
                    }
                    Spacer()
                    Button("Profilordner öffnen") {
                        if let folder = SigningService.profileDirectories.first(where: {
                            FileManager.default.fileExists(atPath: $0.path)
                        }) {
                            NSWorkspace.shared.open(folder)
                        }
                    }
                }
                Text("\(model.identities.count) Zertifikat(e), \(model.profiles.count) gültige(s) Profil(e) gefunden.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

private struct ToolSettings: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Form {
            Section("Status") {
                ToolChecklist()
                Button("Erneut prüfen") {
                    Task {
                        await model.reloadTools()
                        await model.refreshDevices()
                    }
                }
            }
            Section("libimobiledevice installieren (optional)") {
                Text("brew install libimobiledevice ideviceinstaller")
                    .font(.system(.callout, design: .monospaced))
                    .textSelection(.enabled)
                Text("Homebrew bekommst du unter brew.sh. Nach der Installation „Erneut prüfen“ klicken.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}
