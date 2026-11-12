import AppKit
import SwiftUI

/// Right column: app details, signing and live activity.
struct InspectorPanel: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                AppDetailsCard()
                SigningCard()
                ActivityCard()
            }
            .padding(.bottom, 4)
        }
        .scrollIndicators(.never)
    }
}

// MARK: - App details

private struct AppDetailsCard: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                SectionLabel(title: "App", symbol: "app.badge.fill")
                Spacer()
                if model.currentIPA != nil {
                    Button {
                        model.clearIPA()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 10, weight: .bold))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.white.opacity(0.5))
                    .disabled(model.isInstalling)
                    .help("Entfernen")
                }
            }

            if let ipa = model.currentIPA {
                HStack(spacing: 14) {
                    AppIconView(data: ipa.iconData, size: 58)
                        .shadow(color: Theme.indigo.opacity(0.6), radius: 12)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(ipa.displayName)
                            .font(.system(size: 18, weight: .heavy, design: .rounded))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                        Text(ipa.bundleID)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.5))
                            .lineLimit(1)
                            .textSelection(.enabled)
                    }
                }
                FlowPills(ipa: ipa)
            } else if model.isInspecting {
                HStack(spacing: 10) {
                    ProgressView().controlSize(.small)
                    Text("IPA wird analysiert …")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.white.opacity(0.7))
                }
            } else {
                Button {
                    model.presentImporter = true
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "arrow.down.doc.fill")
                            .font(.system(size: 20))
                            .foregroundStyle(Theme.accent)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("IPA auswählen")
                                .font(.system(size: 13, weight: .bold, design: .rounded))
                                .foregroundStyle(.white)
                            Text("oder irgendwo ins Fenster ziehen")
                                .font(.system(size: 11))
                                .foregroundStyle(.white.opacity(0.5))
                        }
                        Spacer()
                    }
                    .padding(12)
                    .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [5, 4]))
                            .foregroundStyle(.white.opacity(0.25))
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }

            if let error = model.inspectError {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Theme.danger)
            }
        }
        .glassCard(padding: 18)
    }
}

private struct FlowPills: View {
    let ipa: IPAInfo

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Pill(text: ipa.versionLabel, symbol: "tag.fill", tint: Theme.indigo)
                Pill(text: ipa.formattedSize, symbol: "shippingbox.fill", tint: Theme.cyan)
            }
            HStack(spacing: 6) {
                if let minimum = ipa.minimumOSVersion {
                    Pill(text: "iOS \(minimum)+", symbol: "iphone", tint: Theme.magenta)
                }
                if ipa.hasExtensions {
                    Pill(text: "Erweiterungen", symbol: "puzzlepiece.extension.fill", tint: Theme.warning)
                }
            }
        }
    }
}

// MARK: - Signing

private struct SigningCard: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model

        VStack(alignment: .leading, spacing: 12) {
            HStack {
                SectionLabel(title: "Signierung", symbol: "signature")
                Spacer()
                Toggle("Neu signieren", isOn: $model.signingEnabled.animation(.snappy))
                    .toggleStyle(.switch)
                    .labelsHidden()
                    .controlSize(.mini)
                    .tint(Theme.indigo)
            }

            if model.signingEnabled {
                VStack(alignment: .leading, spacing: 8) {
                    Picker("Zertifikat", selection: $model.selectedIdentityID) {
                        if model.identities.isEmpty {
                            Text("Keins gefunden").tag(String?.none)
                        }
                        ForEach(model.identities) { identity in
                            Text(identity.shortName).tag(Optional(identity.id))
                        }
                    }
                    Picker("Profil", selection: $model.selectedProfileID) {
                        if model.profiles.isEmpty {
                            Text("Keins gefunden").tag(String?.none)
                        }
                        ForEach(model.profiles) { profile in
                            Text("\(profile.name) · \(profile.bundleIDPattern)").tag(Optional(profile.id))
                        }
                    }
                }
                .font(.system(size: 11))
                .labelsHidden()

                if let warning = model.signingWarning {
                    Label(warning, systemImage: "exclamationmark.triangle.fill")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Theme.warning)
                        .fixedSize(horizontal: false, vertical: true)
                } else if let profile = model.selectedProfile {
                    Label("Gültig bis \(profile.expirationDate.formatted(date: .abbreviated, time: .omitted))",
                          systemImage: "checkmark.seal.fill")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Theme.success)
                }
            } else {
                Text("Original-Signatur wird verwendet. Einschalten, um mit deiner Apple‑ID zu signieren.")
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.5))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .glassCard(padding: 18)
        .disabled(model.isInstalling)
    }
}

// MARK: - Activity (steps + log)

private struct ActivityCard: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                SectionLabel(title: "Aktivität", symbol: "waveform.path.ecg")
                Spacer()
                if let job = model.job, job.state.isFinished {
                    Button {
                        model.dismissJob()
                    } label: {
                        Image(systemName: "xmark").font(.system(size: 10, weight: .bold))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.white.opacity(0.5))
                    .help("Zurücksetzen")
                }
            }

            if let job = model.job {
                StepTimeline(job: job)
                if let message = job.errorMessage {
                    Text(message)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Theme.danger)
                        .textSelection(.enabled)
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Theme.danger.opacity(0.12), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                TerminalView(lines: job.log)
                    .frame(height: 170)
            } else if let last = model.history.first {
                HStack(spacing: 8) {
                    Image(systemName: last.state == .succeeded ? "checkmark.circle.fill" : "xmark.octagon.fill")
                        .foregroundStyle(last.state == .succeeded ? Theme.success : Theme.danger)
                    Text("Zuletzt: \(last.appName) → \(last.deviceName)")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.white.opacity(0.6))
                }
            } else {
                Text("Hier siehst du live, was beim Beamen passiert.")
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.5))
            }
        }
        .glassCard(padding: 18)
    }
}

private struct StepTimeline: View {
    let job: InstallJob

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(InstallJob.Step.allCases.enumerated()), id: \.element.id) { index, step in
                let state = job.state(of: step)
                VStack(spacing: 6) {
                    StepNode(step: step, state: state)
                    Text(shortTitle(step))
                        .font(.system(size: 10, weight: state == .running ? .bold : .medium, design: .rounded))
                        .foregroundStyle(state == .pending || state == .skipped ? Color.white.opacity(0.4) : Color.white)
                }
                .frame(width: 64)
                if index < InstallJob.Step.allCases.count - 1 {
                    Capsule()
                        .fill(connectorFill(after: state))
                        .frame(height: 3)
                        .padding(.bottom, 18)
                }
            }
        }
    }

    private func shortTitle(_ step: InstallJob.Step) -> String {
        switch step {
        case .prepare: return "Entpacken"
        case .sign: return "Signieren"
        case .install: return "Installieren"
        }
    }

    private func connectorFill(after state: InstallJob.StepState) -> AnyShapeStyle {
        switch state {
        case .done, .skipped: return AnyShapeStyle(Theme.accent)
        case .failed: return AnyShapeStyle(Theme.danger)
        default: return AnyShapeStyle(Color.white.opacity(0.12))
        }
    }
}

private struct StepNode: View {
    let step: InstallJob.Step
    let state: InstallJob.StepState

    var body: some View {
        ZStack {
            Circle()
                .fill(fill)
                .frame(width: 30, height: 30)
                .shadow(color: glow, radius: 8)
            if state == .running {
                TimelineView(.animation(minimumInterval: 1.0 / 60.0)) { timeline in
                    Circle()
                        .trim(from: 0, to: 0.3)
                        .stroke(Theme.cyan, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                        .frame(width: 36, height: 36)
                        .rotationEffect(.degrees(fract(timeline.date.timeIntervalSinceReferenceDate) * 360))
                }
            }
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .heavy))
                .foregroundStyle(.white)
        }
        .frame(width: 38, height: 38)
    }

    private var symbol: String {
        switch state {
        case .done: return "checkmark"
        case .failed: return "xmark"
        case .skipped: return "minus"
        default: return step.symbol
        }
    }

    private var fill: AnyShapeStyle {
        switch state {
        case .done: return AnyShapeStyle(Theme.success)
        case .failed: return AnyShapeStyle(Theme.danger)
        case .running: return AnyShapeStyle(Theme.accent)
        case .pending, .skipped: return AnyShapeStyle(Color.white.opacity(0.10))
        }
    }

    private var glow: Color {
        switch state {
        case .done: return Theme.success.opacity(0.6)
        case .failed: return Theme.danger.opacity(0.6)
        case .running: return Theme.indigo.opacity(0.8)
        default: return .clear
        }
    }
}

/// Dark terminal-style live log.
struct TerminalView: View {
    let lines: [LogLine]

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                Circle().fill(Color(red: 1, green: 0.37, blue: 0.34)).frame(width: 8, height: 8)
                Circle().fill(Color(red: 1, green: 0.74, blue: 0.18)).frame(width: 8, height: 8)
                Circle().fill(Color(red: 0.16, green: 0.79, blue: 0.25)).frame(width: 8, height: 8)
                Spacer()
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(lines.map(\.text).joined(separator: "\n"), forType: .string)
                } label: {
                    Image(systemName: "doc.on.doc").font(.system(size: 10))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.white.opacity(0.5))
                .help("Protokoll kopieren")
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(Color.white.opacity(0.05))

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 3) {
                        ForEach(lines) { line in
                            HStack(alignment: .top, spacing: 6) {
                                Text(prefix(line.kind))
                                    .foregroundStyle(color(line.kind))
                                Text(line.text)
                                    .foregroundStyle(line.kind == .info ? Color.white.opacity(0.78) : color(line.kind))
                                    .fontWeight(line.kind == .step ? .bold : .regular)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .font(.system(size: 10.5, design: .monospaced))
                            .textSelection(.enabled)
                            .id(line.id)
                        }
                    }
                    .padding(10)
                }
                .onChange(of: lines.count) { _, _ in
                    if let last = lines.last { proxy.scrollTo(last.id, anchor: .bottom) }
                }
                .onAppear {
                    if let last = lines.last { proxy.scrollTo(last.id, anchor: .bottom) }
                }
            }
        }
        .background(Color.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(.white.opacity(0.08), lineWidth: 1)
        )
    }

    private func prefix(_ kind: LogLine.Kind) -> String {
        switch kind {
        case .info: return "›"
        case .step: return "▸"
        case .success: return "✓"
        case .error: return "✗"
        }
    }

    private func color(_ kind: LogLine.Kind) -> Color {
        switch kind {
        case .info: return Color.white.opacity(0.35)
        case .step: return Theme.cyan
        case .success: return Theme.success
        case .error: return Theme.danger
        }
    }
}
