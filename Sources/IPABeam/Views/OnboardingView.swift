import SwiftUI

struct OnboardingView: View {
    @Environment(AppModel.self) private var model

    private struct Item: Identifiable {
        let id = UUID()
        let symbol: String
        let title: String
        let text: String
    }

    private let items: [Item] = [
        Item(symbol: "cable.connector",
             title: "Per USB‑C verbinden",
             text: "Schließe dein iPhone an, entsperre es und tippe auf „Diesem Computer vertrauen“."),
        Item(symbol: "hammer.fill",
             title: "Entwicklermodus aktivieren",
             text: "Auf dem iPhone: Einstellungen → Datenschutz & Sicherheit → Entwicklermodus → Ein. Danach neu starten. (Erscheint erst, nachdem das iPhone einmal mit dem Mac/Xcode verbunden war.)"),
        Item(symbol: "wifi",
             title: "Drahtlos installieren",
             text: "Einmal per Kabel koppeln, dann in Xcode → Window → Devices „Connect via network“ aktivieren (oder im Finder „Dieses iPhone im WLAN anzeigen“). Ab dann erscheint das iPhone im selben WLAN automatisch."),
        Item(symbol: "signature",
             title: "Signieren mit deiner Apple‑ID",
             text: "Melde dich in Xcode → Settings → Accounts mit deiner Apple‑ID an und erstelle einmal ein Profil (z. B. ein leeres Projekt auf dem iPhone starten). IPA Beam findet Zertifikat und Profil dann automatisch.")
    ]

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                AuroraBackground()
                VStack(spacing: 10) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .fill(Theme.accent)
                            .frame(width: 72, height: 72)
                            .shadow(color: Theme.indigo.opacity(0.6), radius: 20, y: 8)
                        Image(systemName: "arrow.down.app.fill")
                            .font(.system(size: 34, weight: .bold))
                            .foregroundStyle(.white)
                    }
                    Text("Willkommen bei IPA Beam")
                        .font(.system(size: 26, weight: .heavy, design: .rounded))
                    Text("In vier Schritten bereit zum Sideloaden.")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 28)
            }
            .frame(height: 210)
            .clipped()

            VStack(alignment: .leading, spacing: 16) {
                ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                    HStack(alignment: .top, spacing: 14) {
                        ZStack {
                            Circle().fill(Theme.accent.opacity(0.18)).frame(width: 38, height: 38)
                            Image(systemName: item.symbol)
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(Theme.accent)
                        }
                        VStack(alignment: .leading, spacing: 3) {
                            Text("\(index + 1). \(item.title)")
                                .font(.system(size: 14, weight: .bold, design: .rounded))
                            Text(item.text)
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }

                ToolChecklist()
                    .padding(.top, 4)
            }
            .padding(28)

            HStack {
                Text("Diese Hilfe findest du jederzeit unter „?“ in der Symbolleiste.")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                Spacer()
                Button("Los geht’s") { model.completeOnboarding() }
                    .buttonStyle(GradientButtonStyle(large: false))
                    .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 28)
            .padding(.bottom, 24)
        }
        .frame(width: 600)
    }
}

/// Shows which command line tools are installed and how to get the missing ones.
struct ToolChecklist: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            row(
                ok: model.tools.devicectl,
                title: "Xcode (devicectl)",
                detail: model.tools.devicectl
                    ? "Bereit – USB‑C & WLAN über Apples CoreDevice."
                    : "Xcode aus dem Mac App Store installieren und einmal starten."
            )
            row(
                ok: model.tools.libimobiledeviceReady,
                title: "libimobiledevice (optional)",
                detail: model.tools.libimobiledeviceReady
                    ? "Bereit – Alternative ohne Xcode."
                    : "Im Terminal: brew install libimobiledevice ideviceinstaller"
            )
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func row(ok: Bool, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: ok ? "checkmark.circle.fill" : "circle.dashed")
                .foregroundStyle(ok ? Theme.success : .secondary)
                .font(.system(size: 14, weight: .semibold))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 12, weight: .semibold))
                Text(detail)
                    .font(.system(size: 11, design: ok ? .default : .monospaced))
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
        }
    }
}
