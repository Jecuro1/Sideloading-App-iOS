import SwiftUI

struct MoreView: View {
    var body: some View {
        Page(title: "Mehr", subtitle: "So funktioniert IPA Beam auf dem iPhone.") {
            VStack(alignment: .leading, spacing: 16) {
                step(1, "arrow.down.doc.fill", "IPA holen",
                     "In Safari, Mail, Dateien oder per AirDrop eine .ipa öffnen und „Öffnen in IPA Beam“ wählen.")
                step(2, "key.fill", "Zertifikat hinzufügen",
                     "Einmalig dein .p12-Zertifikat samt Passwort und das passende Provisioning-Profil importieren.")
                step(3, "bolt.fill", "Beamen",
                     "App auswählen und „Signieren & beamen“ tippen – IPA Beam prüft Zertifikat und Profil direkt am iPhone.")
                step(4, "desktopcomputer", "Mit PC/Mac",
                     "IPA Beam für Windows & macOS installiert Apps per USB‑C oder WLAN – und auch IPA Beam selbst aufs iPhone.")
            }
            .glassCard()

            VStack(alignment: .leading, spacing: 8) {
                SectionLabel(title: "Status", symbol: "waveform.path.ecg")
                row("Import & Analyse von IPAs", done: true)
                row("Bibliothek", done: true)
                row("Zertifikate & Profile prüfen", done: true)
                row("Signieren auf dem iPhone", done: false)
                row("Installieren ohne Computer", done: false)
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

    private func step(_ number: Int, _ symbol: String, _ title: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            ZStack {
                Circle().fill(Theme.accent.opacity(0.25)).frame(width: 40, height: 40)
                Image(systemName: symbol).font(.system(size: 16, weight: .bold)).foregroundStyle(Theme.cyan)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text("\(number). \(title)").font(.system(size: 15, weight: .bold, design: .rounded))
                Text(text).font(.system(size: 13)).foregroundStyle(.white.opacity(0.6))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func row(_ title: String, done: Bool) -> some View {
        HStack(spacing: 10) {
            Image(systemName: done ? "checkmark.circle.fill" : "clock.fill")
                .foregroundStyle(done ? Theme.success : Theme.warning)
            Text(title).font(.system(size: 14, weight: .medium))
            Spacer()
            Text(done ? "Fertig" : "Nächstes Update")
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundStyle(done ? Theme.success : Theme.warning)
        }
    }
}
