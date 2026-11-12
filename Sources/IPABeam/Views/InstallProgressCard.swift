import AppKit
import SwiftUI

struct InstallProgressCard: View {
    @Environment(AppModel.self) private var model
    let job: InstallJob
    @State private var showLog = false

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .center, spacing: 24) {
                ProgressRing(progress: job.overallProgress, state: job.state)
                    .frame(width: 112, height: 112)

                VStack(alignment: .leading, spacing: 12) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(headline)
                            .font(.system(size: 20, weight: .bold, design: .rounded))
                            .contentTransition(.opacity)
                        Text("\(job.appName) → \(job.deviceName) · \(job.connection.title)")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(InstallJob.Step.allCases) { step in
                            StepRow(step: step, state: job.state(of: step))
                        }
                    }
                }
                Spacer(minLength: 0)
            }

            if let message = job.errorMessage {
                Text(message)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Theme.danger)
                    .textSelection(.enabled)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Theme.danger.opacity(0.10), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }

            HStack(spacing: 12) {
                Button {
                    withAnimation(.snappy) { showLog.toggle() }
                } label: {
                    Label(showLog ? "Protokoll ausblenden" : "Protokoll anzeigen",
                          systemImage: showLog ? "chevron.up" : "terminal")
                }
                .buttonStyle(.borderless)

                if showLog {
                    Button {
                        let text = job.log.map(\.text).joined(separator: "\n")
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(text, forType: .string)
                    } label: {
                        Label("Kopieren", systemImage: "doc.on.doc")
                    }
                    .buttonStyle(.borderless)
                }

                Spacer()

                if job.state == .running {
                    Button("Abbrechen", role: .cancel) { model.cancelInstall() }
                        .controlSize(.large)
                } else {
                    Button("Schließen") { model.dismissJob() }
                        .controlSize(.large)
                    Button {
                        model.install()
                    } label: {
                        Label(job.state == .succeeded ? "Erneut installieren" : "Nochmal versuchen",
                              systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(GradientButtonStyle(large: false))
                    .disabled(model.installBlocker != nil)
                }
            }
            .font(.system(size: 12, weight: .medium))

            if showLog {
                LogView(lines: job.log)
                    .frame(height: 200)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .glassCard(padding: 24)
    }

    private var headline: String {
        switch job.state {
        case .running:
            return job.currentStep.map { "\($0.title) …" } ?? "Wird vorbereitet …"
        case .succeeded:
            return "Installiert! 🎉"
        case .failed:
            return "Installation fehlgeschlagen"
        case .cancelled:
            return "Abgebrochen"
        }
    }
}

// MARK: - Progress ring

struct ProgressRing: View {
    let progress: Double
    let state: InstallJob.State
    @State private var spin = false

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.primary.opacity(0.08), lineWidth: 11)

            Circle()
                .trim(from: 0, to: max(progress, 0.02))
                .stroke(ringStyle, style: StrokeStyle(lineWidth: 11, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .shadow(color: shadowColor.opacity(0.55), radius: 10)
                .animation(.easeInOut(duration: 0.4), value: progress)

            if state == .running {
                Circle()
                    .trim(from: 0, to: 0.08)
                    .stroke(.white.opacity(0.7), style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .padding(17)
                    .rotationEffect(.degrees(spin ? 360 : 0))
                    .onAppear {
                        withAnimation(.linear(duration: 1.2).repeatForever(autoreverses: false)) { spin = true }
                    }
            }

            center
        }
    }

    @ViewBuilder
    private var center: some View {
        switch state {
        case .running:
            Text("\(Int(progress * 100))%")
                .font(.system(size: 24, weight: .heavy, design: .rounded))
                .monospacedDigit()
                .contentTransition(.numericText(value: progress))
                .animation(.snappy, value: progress)
        case .succeeded:
            Image(systemName: "checkmark")
                .font(.system(size: 38, weight: .heavy))
                .foregroundStyle(Theme.success)
                .symbolEffect(.bounce, value: state)
                .transition(.scale.combined(with: .opacity))
        case .failed:
            Image(systemName: "xmark")
                .font(.system(size: 34, weight: .heavy))
                .foregroundStyle(Theme.danger)
        case .cancelled:
            Image(systemName: "stop.fill")
                .font(.system(size: 28, weight: .heavy))
                .foregroundStyle(.secondary)
        }
    }

    private var ringStyle: AnyShapeStyle {
        switch state {
        case .running: return AnyShapeStyle(Theme.ring)
        case .succeeded: return AnyShapeStyle(Theme.success)
        case .failed: return AnyShapeStyle(Theme.danger)
        case .cancelled: return AnyShapeStyle(Color.secondary)
        }
    }

    private var shadowColor: Color {
        switch state {
        case .running: return Theme.indigo
        case .succeeded: return Theme.success
        case .failed: return Theme.danger
        case .cancelled: return .clear
        }
    }
}

// MARK: - Steps

private struct StepRow: View {
    let step: InstallJob.Step
    let state: InstallJob.StepState

    var body: some View {
        HStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(background)
                    .frame(width: 22, height: 22)
                icon
            }
            Text(step.title)
                .font(.system(size: 13, weight: state == .running ? .semibold : .regular))
                .foregroundStyle(state == .pending || state == .skipped ? .secondary : .primary)
                .strikethrough(state == .skipped, color: .secondary)
        }
        .animation(.snappy, value: state)
    }

    @ViewBuilder
    private var icon: some View {
        switch state {
        case .pending:
            Image(systemName: step.symbol)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
        case .running:
            ProgressView().controlSize(.mini)
        case .done:
            Image(systemName: "checkmark")
                .font(.system(size: 10, weight: .heavy))
                .foregroundStyle(.white)
        case .skipped:
            Image(systemName: "minus")
                .font(.system(size: 10, weight: .heavy))
                .foregroundStyle(.secondary)
        case .failed:
            Image(systemName: "xmark")
                .font(.system(size: 10, weight: .heavy))
                .foregroundStyle(.white)
        }
    }

    private var background: Color {
        switch state {
        case .pending, .skipped: return Color.primary.opacity(0.08)
        case .running: return Theme.indigo.opacity(0.25)
        case .done: return Theme.success
        case .failed: return Theme.danger
        }
    }
}

// MARK: - Log

struct LogView: View {
    let lines: [LogLine]

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 3) {
                    ForEach(lines) { line in
                        Text(line.text)
                            .font(.system(size: 11, weight: line.kind == .step ? .bold : .regular, design: .monospaced))
                            .foregroundStyle(color(for: line.kind))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                            .id(line.id)
                    }
                }
                .padding(12)
            }
            .background(Color.black.opacity(0.35), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .onChange(of: lines.count) { _, _ in
                if let last = lines.last {
                    proxy.scrollTo(last.id, anchor: .bottom)
                }
            }
            .onAppear {
                if let last = lines.last { proxy.scrollTo(last.id, anchor: .bottom) }
            }
        }
    }

    private func color(for kind: LogLine.Kind) -> Color {
        switch kind {
        case .info: return Color.white.opacity(0.78)
        case .step: return Theme.cyan
        case .success: return Theme.success
        case .error: return Theme.danger
        }
    }
}
