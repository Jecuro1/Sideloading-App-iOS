import SwiftUI

/// What the central iPhone currently shows.
enum StageState: Equatable {
    case noDevice
    case waiting
    case ready
    case installing(Double)
    case success
    case failed

    var isInstalling: Bool {
        if case .installing = self { return true }
        return false
    }
}

// MARK: - Stage

/// Hero area: floating app icon, light beam and a tilting 3D iPhone.
struct BeamStage: View {
    @Environment(AppModel.self) private var model
    @State private var tilt = CGSize.zero

    private var state: StageState {
        if let job = model.job { return stageState(for: job) }
        guard let device = model.selectedDevice, device.isAvailable else { return .noDevice }
        return model.currentIPA == nil ? .waiting : .ready
    }

    private func stageState(for job: InstallJob) -> StageState {
        switch job.state {
        case .running: return .installing(job.overallProgress)
        case .succeeded: return .success
        case .failed, .cancelled: return .failed
        }
    }

    var body: some View {
        GeometryReader { proxy in
            let phoneWidth = min(250, max(170, (proxy.size.height - 250) / 2.05))
            VStack(spacing: 0) {
                ZStack(alignment: .top) {
                    // Beam + floating icon
                    FloatingPayload(
                        icon: model.currentIPA?.iconData,
                        hasIPA: model.currentIPA != nil,
                        state: state,
                        phoneWidth: phoneWidth
                    )
                    .frame(height: 140)
                    .zIndex(2)

                    // Phone
                    ZStack {
                        Ellipse()
                            .fill(RadialGradient(
                                colors: [glowColor.opacity(0.55), .clear],
                                center: .center, startRadius: 4, endRadius: phoneWidth * 0.9
                            ))
                            .frame(width: phoneWidth * 2.2, height: phoneWidth * 0.5)
                            .offset(y: phoneWidth * 1.08)
                            .blur(radius: 18)

                        PhoneMockup(
                            state: state,
                            icon: model.currentIPA?.iconData,
                            appName: model.currentIPA?.displayName ?? model.job?.appName,
                            width: phoneWidth
                        )
                        .rotation3DEffect(.degrees(Double(-tilt.width) * 14), axis: (x: 0, y: 1, z: 0), perspective: 0.6)
                        .rotation3DEffect(.degrees(Double(tilt.height) * 10), axis: (x: 1, y: 0, z: 0), perspective: 0.6)
                        .shadow(color: glowColor.opacity(0.45), radius: 40, y: 20)
                    }
                    .padding(.top, 108)
                }
                .frame(maxWidth: .infinity)

                Spacer(minLength: 18)

                StageFooter(state: state)
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .contentShape(Rectangle())
            .onContinuousHover { phase in
                switch phase {
                case .active(let location):
                    let x = (location.x / max(proxy.size.width, 1) - 0.5) * 2
                    let y = (location.y / max(proxy.size.height, 1) - 0.5) * 2
                    withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
                        tilt = CGSize(width: x, height: y)
                    }
                case .ended:
                    withAnimation(.spring(response: 0.8, dampingFraction: 0.7)) { tilt = .zero }
                }
            }
        }
    }

    private var glowColor: Color {
        switch state {
        case .success: return Theme.success
        case .failed: return Theme.danger
        case .noDevice: return Theme.indigo.opacity(0.5)
        default: return Theme.indigo
        }
    }
}

// MARK: - Footer (device line + big button)

private struct StageFooter: View {
    @Environment(AppModel.self) private var model
    let state: StageState

    var body: some View {
        VStack(spacing: 14) {
            headline
            actionButton
            Text(subline)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white.opacity(0.5))
                .lineLimit(2)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: 520)
        .padding(.bottom, 8)
    }

    @ViewBuilder
    private var headline: some View {
        HStack(spacing: 10) {
            if let device = model.selectedDevice {
                StatusDot(color: device.isAvailable ? Theme.success : .gray, pulsing: device.isAvailable)
                Text(device.name)
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                Pill(text: device.connection.title, symbol: device.connection.symbol,
                     tint: device.connection == .wifi ? Theme.success : Theme.cyan)
            } else {
                Image(systemName: "antenna.radiowaves.left.and.right")
                    .symbolEffect(.variableColor.iterative, options: .repeating)
                    .foregroundStyle(Theme.cyan)
                Text("Suche iPhone über USB‑C & WLAN …")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
            }
        }
        .foregroundStyle(.white)
    }

    @ViewBuilder
    private var actionButton: some View {
        if let job = model.job, job.state == .running {
            Button {
                model.cancelInstall()
            } label: {
                Label("Abbrechen", systemImage: "stop.fill")
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .padding(.horizontal, 26)
                    .frame(height: 46)
                    .background(.ultraThinMaterial, in: Capsule())
                    .overlay(Capsule().strokeBorder(.white.opacity(0.2), lineWidth: 1))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.white)
        } else {
            Button {
                model.install()
            } label: {
                Label(buttonTitle, systemImage: "bolt.fill")
            }
            .buttonStyle(BeamButtonStyle())
            .disabled(model.installBlocker != nil)
            .keyboardShortcut(.return, modifiers: .command)
        }
    }

    private var buttonTitle: String {
        switch model.job?.state {
        case .succeeded: return "Nochmal beamen"
        case .failed, .cancelled: return "Erneut versuchen"
        default: return "Jetzt aufs iPhone beamen"
        }
    }

    private var subline: String {
        if let job = model.job {
            switch job.state {
            case .running:
                return "\(job.currentStep?.title ?? "Läuft") · \(Int(job.overallProgress * 100)) %"
            case .succeeded:
                return "\(job.appName) ist jetzt auf \(job.deviceName). Viel Spaß!"
            case .failed:
                return "Fehlgeschlagen – Details rechts im Protokoll."
            case .cancelled:
                return "Abgebrochen."
            }
        }
        return model.installBlocker ?? "Bereit · ⌘↩ zum Installieren"
    }
}

// MARK: - Floating icon + beam

private struct FloatingPayload: View {
    let icon: Data?
    let hasIPA: Bool
    let state: StageState
    let phoneWidth: CGFloat

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60.0)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            let bob = sin(t * 2.0) * 6
            ZStack(alignment: .top) {
                if state.isInstalling {
                    BeamRay(time: t)
                        .frame(width: 120, height: 260)
                        .offset(y: 40)
                        .transition(.opacity)
                }

                if hasIPA && state != .success {
                    ZStack {
                        Circle()
                            .fill(RadialGradient(colors: [Theme.cyan.opacity(0.55), .clear],
                                                 center: .center, startRadius: 2, endRadius: 70))
                            .frame(width: 150, height: 150)
                            .blur(radius: 6)
                        AppIconView(data: icon, size: 74)
                            .shadow(color: Theme.cyan.opacity(0.7), radius: 18)
                            .scaleEffect(state.isInstalling ? 0.9 + 0.05 * sin(t * 6) : 1)
                            .neonBorder(cornerRadius: 74 * 0.225, lineWidth: 1.5, active: state.isInstalling)
                    }
                    .offset(y: -32 + bob)
                    .transition(.asymmetric(insertion: .scale(scale: 0.4).combined(with: .opacity),
                                            removal: .move(edge: .bottom).combined(with: .opacity)))
                }
            }
            .frame(maxWidth: .infinity)
        }
        .animation(.spring(response: 0.6, dampingFraction: 0.7), value: hasIPA)
        .animation(.spring(response: 0.6, dampingFraction: 0.7), value: state)
    }
}

/// Vertical light beam with particles streaming down into the phone.
private struct BeamRay: View {
    let time: Double

    var body: some View {
        ZStack {
            LinearGradient(colors: [Theme.cyan.opacity(0.0), Theme.cyan.opacity(0.55), Theme.indigo.opacity(0.0)],
                           startPoint: .top, endPoint: .bottom)
                .frame(width: 70)
                .blur(radius: 16)
            LinearGradient(colors: [.white.opacity(0.0), .white.opacity(0.85), .white.opacity(0.0)],
                           startPoint: .top, endPoint: .bottom)
                .frame(width: 3)
                .blur(radius: 1)
            Canvas { context, size in
                for index in 0..<46 {
                    let seed = Double(index) * 7.31
                    let speed = 0.55 + fract(sin(seed) * 913.7) * 0.9
                    let progress = fract(time * speed + fract(sin(seed * 1.3) * 471.3))
                    let spread = (fract(sin(seed * 2.1) * 311.9) - 0.5) * size.width * 0.7 * (1 - progress * 0.8)
                    let y = progress * size.height
                    let x = size.width / 2 + spread
                    let radius = 1 + fract(sin(seed * 3.7) * 91.1) * 2
                    let alpha = sin(progress * .pi)
                    let color = index % 3 == 0 ? Theme.magenta : (index % 2 == 0 ? Theme.cyan : Color.white)
                    context.fill(
                        Path(ellipseIn: CGRect(x: x, y: y, width: radius, height: radius * 3.5)),
                        with: .color(color.opacity(alpha))
                    )
                }
            }
        }
        .blendMode(.plusLighter)
        .allowsHitTesting(false)
    }
}

// MARK: - iPhone mockup

struct PhoneMockup: View {
    let state: StageState
    let icon: Data?
    let appName: String?
    var width: CGFloat = 240

    var body: some View {
        let height = width * 2.05
        let corner = width * 0.19
        ZStack(alignment: .top) {
            // Side buttons
            Group {
                RoundedRectangle(cornerRadius: 2).fill(Theme.titanium)
                    .frame(width: 4, height: height * 0.07)
                    .offset(x: -width / 2 - 1.5, y: height * 0.18)
                RoundedRectangle(cornerRadius: 2).fill(Theme.titanium)
                    .frame(width: 4, height: height * 0.11)
                    .offset(x: -width / 2 - 1.5, y: height * 0.28)
                RoundedRectangle(cornerRadius: 2).fill(Theme.titanium)
                    .frame(width: 4, height: height * 0.11)
                    .offset(x: -width / 2 - 1.5, y: height * 0.41)
                RoundedRectangle(cornerRadius: 2).fill(Theme.titanium)
                    .frame(width: 4, height: height * 0.15)
                    .offset(x: width / 2 + 1.5, y: height * 0.30)
            }
            .frame(width: width, alignment: .center)

            // Frame
            RoundedRectangle(cornerRadius: corner, style: .continuous)
                .fill(Theme.titanium)
                .frame(width: width, height: height)
            RoundedRectangle(cornerRadius: corner - 2, style: .continuous)
                .fill(Color.black)
                .frame(width: width - 6, height: height - 6)
                .offset(y: 3)

            // Screen
            PhoneScreen(state: state, icon: icon, appName: appName, width: width - 18)
                .frame(width: width - 18, height: height - 18)
                .clipShape(RoundedRectangle(cornerRadius: corner - 8, style: .continuous))
                .offset(y: 9)

            // Dynamic Island
            Capsule()
                .fill(Color.black)
                .frame(width: width * 0.30, height: width * 0.088)
                .overlay(alignment: .trailing) {
                    Circle().fill(Color(white: 0.12)).frame(width: width * 0.04).padding(.trailing, width * 0.03)
                }
                .offset(y: width * 0.065)

            // Glass reflection
            RoundedRectangle(cornerRadius: corner, style: .continuous)
                .fill(LinearGradient(
                    colors: [.white.opacity(0.10), .clear, .clear, .white.opacity(0.04)],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                ))
                .frame(width: width, height: height)
                .allowsHitTesting(false)
        }
        .frame(width: width, height: height)
    }
}

private struct PhoneScreen: View {
    let state: StageState
    let icon: Data?
    let appName: String?
    let width: CGFloat

    private var iconSize: CGFloat { width * 0.165 }
    private var gap: CGFloat { (width - iconSize * 4) / 5 }
    private let targetSlot = 6

    var body: some View {
        ZStack(alignment: .top) {
            wallpaper
            if state == .noDevice {
                offlineScreen
            } else {
                VStack(spacing: 0) {
                    statusBar
                    homeGrid
                        .padding(.top, width * 0.12)
                    Spacer()
                    dock
                        .padding(.bottom, width * 0.05)
                }
                overlay
            }
        }
    }

    private var wallpaper: some View {
        ZStack {
            LinearGradient(colors: [Color(red: 0.10, green: 0.06, blue: 0.30), Color(red: 0.32, green: 0.07, blue: 0.40),
                                    Color(red: 0.03, green: 0.20, blue: 0.38)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            Circle().fill(Theme.magenta.opacity(0.55)).frame(width: width * 0.9).blur(radius: 40)
                .offset(x: width * 0.3, y: -width * 0.4)
            Circle().fill(Theme.cyan.opacity(0.45)).frame(width: width * 0.8).blur(radius: 40)
                .offset(x: -width * 0.35, y: width * 0.6)
        }
        .saturation(state == .noDevice ? 0.2 : 1)
        .brightness(state == .noDevice ? -0.35 : 0)
    }

    private var statusBar: some View {
        HStack {
            Text("9:41")
                .font(.system(size: width * 0.058, weight: .semibold))
            Spacer()
            HStack(spacing: 3) {
                Image(systemName: "cellularbars")
                Image(systemName: "wifi")
                Image(systemName: "battery.100")
            }
            .font(.system(size: width * 0.045, weight: .semibold))
        }
        .foregroundStyle(.white)
        .padding(.horizontal, width * 0.09)
        .padding(.top, width * 0.06)
    }

    private var homeGrid: some View {
        VStack(spacing: gap * 1.25) {
            ForEach(0..<4, id: \.self) { row in
                HStack(spacing: gap) {
                    ForEach(0..<4, id: \.self) { column in
                        let index = row * 4 + column
                        if index == targetSlot {
                            targetIcon
                        } else {
                            placeholderIcon(index)
                        }
                    }
                }
            }
        }
    }

    private var dock: some View {
        HStack(spacing: gap) {
            ForEach(20..<24, id: \.self) { placeholderIcon($0) }
        }
        .padding(.vertical, gap * 0.6)
        .padding(.horizontal, gap * 0.6)
        .background(.white.opacity(0.12), in: RoundedRectangle(cornerRadius: width * 0.09, style: .continuous))
    }

    private func placeholderIcon(_ index: Int) -> some View {
        let hue = fract(Double(index) * 0.137 + 0.55)
        return RoundedRectangle(cornerRadius: iconSize * 0.225, style: .continuous)
            .fill(LinearGradient(
                colors: [Color(hue: hue, saturation: 0.55, brightness: 0.95),
                         Color(hue: fract(hue + 0.08), saturation: 0.7, brightness: 0.6)],
                startPoint: .topLeading, endPoint: .bottomTrailing
            ))
            .frame(width: iconSize, height: iconSize)
            .opacity(isActive ? 0.28 : 0.55)
    }

    private var isActive: Bool {
        switch state {
        case .ready, .installing, .success: return true
        default: return false
        }
    }

    @ViewBuilder
    private var targetIcon: some View {
        let shape = RoundedRectangle(cornerRadius: iconSize * 0.225, style: .continuous)
        switch state {
        case .waiting, .noDevice, .failed:
            placeholderIcon(targetSlot)
        case .ready:
            TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
                let pulse = 0.5 + 0.5 * sin(timeline.date.timeIntervalSinceReferenceDate * 3)
                shape
                    .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                    .foregroundStyle(.white.opacity(0.5 + pulse * 0.5))
                    .frame(width: iconSize, height: iconSize)
                    .shadow(color: Theme.cyan.opacity(pulse), radius: 8)
            }
        case .installing(let progress):
            ZStack {
                AppIconView(data: icon, size: iconSize)
                    .saturation(0.2)
                    .brightness(-0.25)
                Circle()
                    .stroke(.white.opacity(0.35), lineWidth: 2)
                    .frame(width: iconSize * 0.55, height: iconSize * 0.55)
                PieSlice(progress: progress)
                    .fill(.white.opacity(0.9))
                    .frame(width: iconSize * 0.42, height: iconSize * 0.42)
            }
            .shadow(color: Theme.cyan.opacity(0.9), radius: 10)
        case .success:
            TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
                let phase = fract(timeline.date.timeIntervalSinceReferenceDate / 2.2)
                ZStack {
                    shape
                        .stroke(Theme.success.opacity(1 - phase), lineWidth: 2)
                        .frame(width: iconSize, height: iconSize)
                        .scaleEffect(1 + phase * 0.9)
                    AppIconView(data: icon, size: iconSize)
                        .shadow(color: Theme.success.opacity(0.9), radius: 12)
                }
            }
        }
    }

    @ViewBuilder
    private var overlay: some View {
        switch state {
        case .waiting:
            VStack(spacing: 8) {
                Image(systemName: "arrow.down.app.fill")
                    .font(.system(size: width * 0.16, weight: .semibold))
                    .symbolEffect(.pulse, options: .repeating)
                Text("IPA hier ablegen")
                    .font(.system(size: width * 0.065, weight: .bold, design: .rounded))
            }
            .foregroundStyle(.white)
            .padding(width * 0.08)
            .frame(width: width * 0.78)
            .background(.black.opacity(0.35), in: RoundedRectangle(cornerRadius: width * 0.08, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: width * 0.08, style: .continuous)
                    .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [6, 5]))
                    .foregroundStyle(.white.opacity(0.6))
            )
            .frame(maxHeight: .infinity)
        case .installing(let progress):
            VStack {
                Spacer()
                Text("\(Int(progress * 100)) %")
                    .font(.system(size: width * 0.16, weight: .heavy, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.white)
                    .shadow(color: Theme.cyan, radius: 12)
                    .contentTransition(.numericText(value: progress))
                Text("Wird installiert …")
                    .font(.system(size: width * 0.055, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.75))
                Spacer().frame(height: width * 0.42)
            }
        case .success:
            banner(symbol: "checkmark.circle.fill", tint: Theme.success,
                   title: "Installiert", text: appName.map { "\($0) ist bereit." } ?? "App ist bereit.")
        case .failed:
            banner(symbol: "xmark.octagon.fill", tint: Theme.danger,
                   title: "Fehlgeschlagen", text: "Siehe Protokoll am Mac.")
        default:
            EmptyView()
        }
    }

    private func banner(symbol: String, tint: Color, title: String, text: String) -> some View {
        HStack(spacing: width * 0.04) {
            Image(systemName: symbol)
                .font(.system(size: width * 0.09))
                .foregroundStyle(tint)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.system(size: width * 0.055, weight: .bold))
                Text(text).font(.system(size: width * 0.046)).opacity(0.8).lineLimit(1)
            }
            .foregroundStyle(.white)
            Spacer(minLength: 0)
        }
        .padding(width * 0.045)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: width * 0.07, style: .continuous))
        .padding(.horizontal, width * 0.04)
        .padding(.top, width * 0.17)
        .shadow(color: tint.opacity(0.4), radius: 12)
        .transition(.move(edge: .top).combined(with: .opacity))
    }

    private var offlineScreen: some View {
        VStack(spacing: width * 0.05) {
            Spacer()
            HStack(spacing: width * 0.06) {
                Image(systemName: "cable.connector")
                Image(systemName: "wifi")
                    .symbolEffect(.variableColor.iterative, options: .repeating)
            }
            .font(.system(size: width * 0.11, weight: .semibold))
            .foregroundStyle(Theme.cyan)
            Text("Kein iPhone verbunden")
                .font(.system(size: width * 0.068, weight: .bold, design: .rounded))
            Text("USB‑C anstecken oder\nim selben WLAN entsperren")
                .font(.system(size: width * 0.05))
                .multilineTextAlignment(.center)
                .opacity(0.7)
            Spacer()
        }
        .foregroundStyle(.white)
    }
}

/// iOS-style download pie.
private struct PieSlice: Shape {
    var progress: Double

    var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let center = CGPoint(x: rect.midX, y: rect.midY)
        path.move(to: center)
        path.addArc(
            center: center,
            radius: rect.width / 2,
            startAngle: .degrees(-90),
            endAngle: .degrees(-90 + 360 * max(0.001, progress)),
            clockwise: false
        )
        path.closeSubpath()
        return path
    }
}
