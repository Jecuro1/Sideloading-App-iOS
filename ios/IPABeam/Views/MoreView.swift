import SwiftUI

struct MoreView: View {
    @Environment(AppState.self) private var state

    var body: some View {
        @Bindable var state = state

        Page(title: "Mehr", subtitle: "Einrichtung und Einstellungen.") {
            InstallSetupCard()

            VStack(alignment: .leading, spacing: 12) {
                SectionLabel(title: "Signieren", symbol: "signature")
                Toggle(isOn: $state.removeExtensions) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Erweiterungen & Watch-App entfernen")
                            .font(.system(size: 14, weight: .semibold))
                        Text("Nötig für kostenlose Apple‑IDs (keine Wildcard-Profile).")
                            .font(.system(size: 12))
                            .foregroundStyle(.white.opacity(0.55))
                    }
                }
                .tint(Theme.indigo)
                .onChange(of: state.removeExtensions) { _, _ in state.save() }
            }
            .glassCard()

            VStack(alignment: .leading, spacing: 14) {
                SectionLabel(title: "So funktioniert’s", symbol: "questionmark.circle.fill")
                step("arrow.down.doc.fill", "IPA holen",
                     "Aus Dateien/Safari/AirDrop öffnen oder aus einer Quelle laden – Updates kommen automatisch.")
                step("key.fill", "Zertifikat hinzufügen",
                     "Einmalig .p12 + Passwort und das Provisioning-Profil mit deinem iPhone importieren.")
                step("bolt.fill", "Signieren & installieren",
                     "IPA Beam signiert direkt auf dem iPhone und übergibt die App an den iOS-Installer.")
                step("arrow.triangle.2.circlepath", "Alle 7 Tage erneuern",
                     "Mit kostenloser Apple‑ID laufen Signaturen nach 7 Tagen ab – einfach „Erneut installieren“.")
            }
            .glassCard()

            HStack {
                Text("IPA Beam für iOS")
                Spacer()
                Text("Version \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0")")
            }
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(.white.opacity(0.4))
            .padding(.horizontal, 4)
        }
    }

    private func step(_ symbol: String, _ title: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            ZStack {
                Circle().fill(Theme.accent.opacity(0.25)).frame(width: 38, height: 38)
                Image(systemName: symbol).font(.system(size: 15, weight: .bold)).foregroundStyle(Theme.cyan)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.system(size: 15, weight: .bold, design: .rounded))
                Text(text).font(.system(size: 13)).foregroundStyle(.white.opacity(0.6))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// One-time setup: trust IPA Beam's local, device-only certificate.
struct InstallSetupCard: View {
    @Environment(AppState.self) private var state
    @State private var checking = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                SectionLabel(title: "Installation einrichten", symbol: "wrench.and.screwdriver.fill")
                Spacer()
                status
            }

            if state.installReady == true {
                Label("Fertig! IPA Beam kann Apps direkt auf diesem iPhone installieren.", systemImage: "checkmark.seal.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.success)
            } else {
                Text("Einmalig nötig, damit iOS Apps von IPA Beam annimmt. Das Zertifikat wird nur auf deinem iPhone erzeugt und gilt ausschließlich für 127.0.0.1.")
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.6))
                    .fixedSize(horizontal: false, vertical: true)

                setupStep(1, "Profil laden", "Tippen → Safari lädt das Profil „IPA Beam – lokale Installation“ → „Zulassen“.") {
                    Button("Profil laden") {
                        Task { await state.startInstallSetup() }
                    }
                    .buttonStyle(SmallGradientButton())
                }
                setupStep(2, "Profil installieren", "Einstellungen → Allgemein → VPN und Geräteverwaltung → „IPA Beam – lokale Installation“ → Installieren.") {
                    Button("Einstellungen") {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            UIApplication.shared.open(url)
                        }
                    }
                    .buttonStyle(SmallGradientButton())
                }
                setupStep(3, "Vertrauen einschalten", "Einstellungen → Allgemein → Info → Zertifikatsvertrauenseinstellungen → „IPA Beam Local CA“ aktivieren.", trailing: { EmptyView() })
            }

            Button {
                checking = true
                Task {
                    await state.checkInstallSetup()
                    checking = false
                }
            } label: {
                HStack(spacing: 8) {
                    if checking { ProgressView().tint(.white).controlSize(.small) }
                    Text(checking ? "Prüfe …" : "Einrichtung prüfen")
                }
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .frame(maxWidth: .infinity)
                .frame(height: 44)
                .background(.white.opacity(0.08), in: Capsule())
                .overlay(Capsule().strokeBorder(.white.opacity(0.18), lineWidth: 1))
            }
            .buttonStyle(PressableStyle())
            .foregroundStyle(.white)
            .disabled(checking)
        }
        .glassCard()
        .neonBorder(cornerRadius: 24, lineWidth: 1.2, active: state.installReady != true)
    }

    @ViewBuilder
    private var status: some View {
        switch state.installReady {
        case .some(true):
            Pill(text: "Bereit", symbol: "checkmark", tint: Theme.success)
        case .some(false):
            Pill(text: "Offen", symbol: "exclamationmark", tint: Theme.warning)
        case .none:
            Pill(text: "Unbekannt", symbol: "questionmark", tint: .white.opacity(0.6))
        }
    }

    private func setupStep<Trailing: View>(_ number: Int, _ title: String, _ text: String,
                                           @ViewBuilder trailing: () -> Trailing) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(number)")
                .font(.system(size: 14, weight: .black, design: .rounded))
                .frame(width: 28, height: 28)
                .background(Circle().fill(Theme.accent))
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.system(size: 14, weight: .bold))
                Text(text).font(.system(size: 12)).foregroundStyle(.white.opacity(0.6))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 4)
            trailing()
        }
    }
}

struct SmallGradientButton: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .heavy, design: .rounded))
            .foregroundStyle(.white)
            .padding(.horizontal, 12)
            .frame(height: 30)
            .background(Capsule().fill(Theme.accent))
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
            .animation(.spring(response: 0.2, dampingFraction: 0.6), value: configuration.isPressed)
    }
}
