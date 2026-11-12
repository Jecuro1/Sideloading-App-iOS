import SwiftUI

struct BeamView: View {
    @Environment(AppState.self) private var state
    @Binding var showImporter: Bool

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                header
                if let app = state.selectedApp {
                    HeroApp(app: app)
                    SigningSummary()
                    if let run = state.run, run.appID == app.id {
                        RunCard(run: run)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                    actionButton
                    if !state.availableUpdates.isEmpty {
                        UpdatesCard()
                            .padding(.top, 6)
                    }
                } else {
                    ImportCard(showImporter: $showImporter)
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 110)
        }
        .scrollIndicators(.hidden)
    }

    private var header: some View {
        HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Theme.accent)
                    .frame(width: 34, height: 34)
                    .shadow(color: Theme.indigo.opacity(0.8), radius: 10)
                Image(systemName: "arrow.down.app.fill")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(.white)
            }
            HStack(spacing: 5) {
                Text("IPA").foregroundStyle(.white)
                Text("Beam").foregroundStyle(Theme.accent)
            }
            .font(.system(size: 24, weight: .black, design: .rounded))
            Spacer()
            Button {
                showImporter = true
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 16, weight: .bold))
                    .frame(width: 40, height: 40)
                    .background(.ultraThinMaterial, in: Circle())
                    .overlay(Circle().strokeBorder(.white.opacity(0.15), lineWidth: 1))
            }
            .buttonStyle(PressableStyle())
        }
        .padding(.top, 8)
    }

    @ViewBuilder
    private var actionButton: some View {
        let running = state.isBeaming
        Button {
            state.beam()
        } label: {
            Label(running ? "Läuft …" : (state.selectedApp?.installedAt == nil ? "Signieren & installieren" : "Erneut installieren"),
                  systemImage: "bolt.fill")
        }
        .buttonStyle(BeamButtonStyle())
        .disabled(state.selectedSigning == nil || running)
        .padding(.top, 4)

        Text(hint)
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(.white.opacity(0.5))
            .multilineTextAlignment(.center)
    }

    private var hint: String {
        if state.selectedSigning == nil { return "Füge unter „Zertifikate“ dein .p12 + Profil hinzu." }
        if state.installReady == false { return "Einmalig nötig: „Mehr → Installation einrichten“." }
        if let expires = state.selectedApp?.expiresAt {
            let days = max(0, Calendar.current.dateComponents([.day], from: Date(), to: expires).day ?? 0)
            return "Signatur gültig noch \(days) Tage – danach einfach erneut installieren."
        }
        return "Signiert und installiert direkt auf diesem iPhone."
    }
}

// MARK: - Import card

private struct ImportCard: View {
    @Binding var showImporter: Bool

    var body: some View {
        VStack(spacing: 18) {
            TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
                let t = timeline.date.timeIntervalSinceReferenceDate
                ZStack {
                    ForEach(0..<3, id: \.self) { ring in
                        let phase = fract(t / 2.4 + Double(ring) / 3)
                        Circle()
                            .stroke(Theme.cyan.opacity(1 - phase), lineWidth: 1.5)
                            .frame(width: 90 + phase * 110, height: 90 + phase * 110)
                    }
                    Circle()
                        .fill(Theme.accent)
                        .frame(width: 92, height: 92)
                        .shadow(color: Theme.indigo, radius: 24)
                    Image(systemName: "arrow.down")
                        .font(.system(size: 40, weight: .heavy))
                        .foregroundStyle(.white)
                        .offset(y: sin(t * 3) * 4)
                }
                .frame(height: 210)
            }

            VStack(spacing: 6) {
                Text("IPA importieren")
                    .font(.system(size: 26, weight: .black, design: .rounded))
                Text("Aus der Dateien-App wählen, in Safari/AirDrop „Öffnen in IPA Beam“ tippen – oder Apps aus einer Quelle laden.")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.white.opacity(0.6))
                    .multilineTextAlignment(.center)
            }

            Button {
                showImporter = true
            } label: {
                Label("Datei auswählen", systemImage: "folder.fill")
            }
            .buttonStyle(BeamButtonStyle())
        }
        .padding(24)
        .frame(maxWidth: .infinity)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 30, style: .continuous))
        .neonBorder(cornerRadius: 30, lineWidth: 1.5)
        .padding(.top, 20)
    }
}

// MARK: - Hero

private struct HeroApp: View {
    let app: LibraryApp

    var body: some View {
        VStack(spacing: 16) {
            TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
                let t = timeline.date.timeIntervalSinceReferenceDate
                ZStack {
                    Circle()
                        .fill(RadialGradient(colors: [Theme.cyan.opacity(0.55), .clear],
                                             center: .center, startRadius: 4, endRadius: 110))
                        .frame(width: 220, height: 220)
                    AppIconView(data: app.iconData, size: 112)
                        .shadow(color: Theme.cyan.opacity(0.7), radius: 24)
                        .neonBorder(cornerRadius: 112 * 0.225, lineWidth: 1.5)
                        .offset(y: sin(t * 2) * 6)
                        .rotation3DEffect(.degrees(sin(t * 0.8) * 8), axis: (x: 0, y: 1, z: 0))
                }
                .frame(height: 210)
            }

            VStack(spacing: 6) {
                Text(app.name)
                    .font(.system(size: 28, weight: .black, design: .rounded))
                    .multilineTextAlignment(.center)
                Text(app.bundleID)
                    .font(.system(size: 13, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.5))
            }

            HStack(spacing: 6) {
                Pill(text: app.versionLabel, symbol: "tag.fill", tint: Theme.indigo)
                Pill(text: app.formattedSize, symbol: "shippingbox.fill", tint: Theme.cyan)
                if let minimum = app.minimumOSVersion {
                    Pill(text: "iOS \(minimum)+", symbol: "iphone", tint: Theme.magenta)
                }
            }
            if app.hasExtensions {
                Pill(text: "Enthält Erweiterungen", symbol: "puzzlepiece.extension.fill", tint: Theme.warning)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 6)
    }
}

// MARK: - Signing summary

private struct SigningSummary: View {
    @Environment(AppState.self) private var state

    var body: some View {
        Button {
            state.tab = .certificates
        } label: {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(state.selectedSigning == nil ? AnyShapeStyle(Color.white.opacity(0.1)) : AnyShapeStyle(Theme.accent))
                        .frame(width: 40, height: 40)
                    Image(systemName: "key.fill")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(.white)
                }
                VStack(alignment: .leading, spacing: 3) {
                    if let set = state.selectedSigning {
                        Text(set.certificateName)
                            .font(.system(size: 14, weight: .bold))
                            .lineLimit(1)
                        Text("\(set.profile.name) · noch \(set.profile.daysLeft) Tage")
                            .font(.system(size: 12))
                            .foregroundStyle(.white.opacity(0.55))
                            .lineLimit(1)
                    } else {
                        Text("Kein Zertifikat")
                            .font(.system(size: 14, weight: .bold))
                        Text("Tippen, um .p12 + Profil hinzuzufügen")
                            .font(.system(size: 12))
                            .foregroundStyle(.white.opacity(0.55))
                    }
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.white.opacity(0.4))
            }
            .glassCard(padding: 14, cornerRadius: 20)
        }
        .buttonStyle(PressableStyle())
        .foregroundStyle(.white)

        if let warning = state.signingWarning, state.selectedSigning != nil {
            Label(warning, systemImage: "exclamationmark.triangle.fill")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Theme.warning)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

// MARK: - Run progress

private struct RunCard: View {
    @Environment(AppState.self) private var state
    let run: BeamRun

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 0) {
                ForEach(Array(BeamStep.allCases.enumerated()), id: \.element.id) { index, step in
                    let stepState = run.steps[step] ?? .pending
                    VStack(spacing: 6) {
                        ZStack {
                            Circle()
                                .fill(fill(stepState))
                                .frame(width: 34, height: 34)
                                .shadow(color: glow(stepState), radius: 8)
                            if stepState == .running {
                                ProgressView().tint(.white).controlSize(.small)
                            } else {
                                Image(systemName: symbol(step, stepState))
                                    .font(.system(size: 13, weight: .heavy))
                                    .foregroundStyle(.white)
                            }
                        }
                        Text(step.title)
                            .font(.system(size: 10, weight: .bold, design: .rounded))
                            .foregroundStyle(stepState == .pending || stepState == .upcoming ? Color.white.opacity(0.45) : Color.white)
                    }
                    .frame(width: 70)
                    if index < BeamStep.allCases.count - 1 {
                        Capsule()
                            .fill(stepState == .done ? AnyShapeStyle(Theme.accent) : AnyShapeStyle(Color.white.opacity(0.12)))
                            .frame(height: 3)
                            .padding(.bottom, 18)
                    }
                }
            }
            if let message = run.message {
                Text(message)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(run.steps.values.contains(.failed) ? Theme.danger : Color.white.opacity(0.85))
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            }
            if run.needsSetup {
                Button {
                    state.tab = .settings
                } label: {
                    Label("Installation einrichten", systemImage: "wrench.and.screwdriver.fill")
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
                        .background(Capsule().fill(Theme.accent))
                }
                .buttonStyle(PressableStyle())
            }
        }
        .glassCard(padding: 16, cornerRadius: 22)
    }

    private func fill(_ state: StepState) -> AnyShapeStyle {
        switch state {
        case .done: return AnyShapeStyle(Theme.success)
        case .failed: return AnyShapeStyle(Theme.danger)
        case .running: return AnyShapeStyle(Theme.accent)
        case .upcoming: return AnyShapeStyle(Theme.indigo.opacity(0.25))
        case .pending: return AnyShapeStyle(Color.white.opacity(0.1))
        }
    }

    private func glow(_ state: StepState) -> Color {
        switch state {
        case .done: return Theme.success.opacity(0.6)
        case .failed: return Theme.danger.opacity(0.6)
        case .running: return Theme.indigo.opacity(0.8)
        default: return .clear
        }
    }

    private func symbol(_ step: BeamStep, _ state: StepState) -> String {
        switch state {
        case .done: return "checkmark"
        case .failed: return "xmark"
        case .upcoming: return "clock"
        default: return step.symbol
        }
    }
}
