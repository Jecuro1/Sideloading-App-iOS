import AppKit
import SwiftUI
import UniformTypeIdentifiers

enum Theme {
    static let cyan = Color(red: 0.25, green: 0.86, blue: 1.00)
    static let indigo = Color(red: 0.43, green: 0.38, blue: 1.00)
    static let magenta = Color(red: 0.93, green: 0.33, blue: 0.95)
    static let success = Color(red: 0.20, green: 0.92, blue: 0.62)
    static let warning = Color(red: 1.00, green: 0.72, blue: 0.25)
    static let danger = Color(red: 1.00, green: 0.33, blue: 0.42)
    static let background = Color(red: 0.020, green: 0.022, blue: 0.055)
    static let panel = Color(red: 0.07, green: 0.07, blue: 0.13)

    static let accent = LinearGradient(
        colors: [cyan, indigo, magenta],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let ring = AngularGradient(
        colors: [cyan, indigo, magenta, cyan],
        center: .center
    )

    static let titanium = LinearGradient(
        colors: [Color(white: 0.55), Color(white: 0.16), Color(white: 0.40), Color(white: 0.12)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
}

extension UTType {
    static let ipa = UTType(filenameExtension: "ipa", conformingTo: .zip) ?? .zip
}

func fract(_ value: Double) -> Double { value - floor(value) }

// MARK: - Glass surfaces

struct GlassCard: ViewModifier {
    var padding: CGFloat = 20
    var cornerRadius: CGFloat = 22

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .fill(LinearGradient(
                                colors: [Color.white.opacity(0.07), Color.white.opacity(0.01)],
                                startPoint: .top, endPoint: .bottom
                            ))
                    )
            }
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            colors: [.white.opacity(0.20), .white.opacity(0.03), .white.opacity(0.08)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            )
            .shadow(color: .black.opacity(0.35), radius: 24, y: 12)
    }
}

extension View {
    func glassCard(padding: CGFloat = 20, cornerRadius: CGFloat = 22) -> some View {
        modifier(GlassCard(padding: padding, cornerRadius: cornerRadius))
    }

    func neonBorder(cornerRadius: CGFloat, lineWidth: CGFloat = 1.5, active: Bool = true) -> some View {
        modifier(NeonBorder(cornerRadius: cornerRadius, lineWidth: lineWidth, active: active))
    }
}

/// Rotating cyan → indigo → magenta border.
struct NeonBorder: ViewModifier {
    var cornerRadius: CGFloat
    var lineWidth: CGFloat
    var active: Bool

    func body(content: Content) -> some View {
        content.overlay {
            if active {
                TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
                    let angle = fract(timeline.date.timeIntervalSinceReferenceDate / 5) * 360
                    let gradient = AngularGradient(
                        colors: [Theme.cyan, Theme.indigo, Theme.magenta, Theme.cyan],
                        center: .center,
                        angle: .degrees(angle)
                    )
                    ZStack {
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .strokeBorder(gradient, lineWidth: lineWidth * 3)
                            .blur(radius: 8)
                            .opacity(0.55)
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .strokeBorder(gradient, lineWidth: lineWidth)
                    }
                }
                .allowsHitTesting(false)
            }
        }
    }
}

// MARK: - Buttons

struct GradientButtonStyle: ButtonStyle {
    var large = true

    func makeBody(configuration: Configuration) -> some View {
        GradientButtonBody(configuration: configuration, large: large)
    }

    private struct GradientButtonBody: View {
        let configuration: ButtonStyleConfiguration
        let large: Bool
        @Environment(\.isEnabled) private var isEnabled
        @State private var hovering = false

        var body: some View {
            configuration.label
                .font(.system(size: large ? 16 : 13, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
                .padding(.horizontal, large ? 30 : 16)
                .padding(.vertical, large ? 14 : 8)
                .background(
                    Capsule()
                        .fill(Theme.accent)
                        .saturation(isEnabled ? 1 : 0.1)
                        .opacity(isEnabled ? 1 : 0.45)
                )
                .overlay(Capsule().strokeBorder(.white.opacity(0.25), lineWidth: 1))
                .shadow(
                    color: Theme.indigo.opacity(isEnabled ? (hovering ? 0.7 : 0.45) : 0),
                    radius: configuration.isPressed ? 6 : (hovering ? 22 : 14),
                    y: 6
                )
                .scaleEffect(configuration.isPressed ? 0.97 : (hovering && isEnabled ? 1.03 : 1))
                .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
                .animation(.easeOut(duration: 0.18), value: hovering)
                .onHover { hovering = $0 }
        }
    }
}

/// The big hero call-to-action: flowing gradient, shimmer sweep and glow.
struct BeamButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        BeamButtonBody(configuration: configuration)
    }

    private struct BeamButtonBody: View {
        let configuration: ButtonStyleConfiguration
        @Environment(\.isEnabled) private var isEnabled
        @State private var hovering = false

        var body: some View {
            TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: !isEnabled)) { timeline in
                let t = timeline.date.timeIntervalSinceReferenceDate
                let shimmer = fract(t / 2.6)
                configuration.label
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 36)
                    .frame(height: 58)
                    .background {
                        GeometryReader { proxy in
                            ZStack {
                                Capsule()
                                    .fill(LinearGradient(
                                        colors: [Theme.cyan, Theme.indigo, Theme.magenta, Theme.cyan],
                                        startPoint: UnitPoint(x: -1 + fract(t / 6) * 2, y: 0),
                                        endPoint: UnitPoint(x: 1 + fract(t / 6) * 2, y: 1)
                                    ))
                                LinearGradient(
                                    colors: [.clear, .white.opacity(0.55), .clear],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                                .frame(width: 70)
                                .rotationEffect(.degrees(18))
                                .offset(x: -proxy.size.width / 2 - 70 + (proxy.size.width + 140) * shimmer)
                                .blendMode(.plusLighter)
                            }
                            .clipShape(Capsule())
                        }
                    }
                    .overlay(Capsule().strokeBorder(.white.opacity(0.35), lineWidth: 1))
                    .saturation(isEnabled ? 1 : 0)
                    .opacity(isEnabled ? 1 : 0.4)
                    .shadow(color: Theme.indigo.opacity(isEnabled ? 0.8 : 0), radius: hovering ? 34 : 24, y: 8)
                    .shadow(color: Theme.magenta.opacity(isEnabled ? 0.35 : 0), radius: 40, y: 14)
            }
            .scaleEffect(configuration.isPressed ? 0.96 : (hovering && isEnabled ? 1.04 : 1))
            .animation(.spring(response: 0.3, dampingFraction: 0.6), value: hovering)
            .animation(.spring(response: 0.2, dampingFraction: 0.7), value: configuration.isPressed)
            .onHover { hovering = $0 }
        }
    }
}

struct GlassIconButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(.white.opacity(0.9))
            .frame(width: 36, height: 36)
            .background(.ultraThinMaterial, in: Circle())
            .overlay(Circle().strokeBorder(.white.opacity(0.14), lineWidth: 1))
            .scaleEffect(configuration.isPressed ? 0.9 : 1)
            .animation(.spring(response: 0.2, dampingFraction: 0.6), value: configuration.isPressed)
    }
}

// MARK: - Small building blocks

struct Pill: View {
    let text: String
    var symbol: String?
    var tint: Color = .secondary

    var body: some View {
        HStack(spacing: 5) {
            if let symbol {
                Image(systemName: symbol).font(.system(size: 10, weight: .bold))
            }
            Text(text).font(.system(size: 11, weight: .semibold, design: .rounded))
        }
        .foregroundStyle(tint)
        .padding(.horizontal, 9)
        .padding(.vertical, 4)
        .background(tint.opacity(0.14), in: Capsule())
        .overlay(Capsule().strokeBorder(tint.opacity(0.25), lineWidth: 0.5))
    }
}

struct SectionLabel: View {
    let title: String
    let symbol: String

    var body: some View {
        Label(title, systemImage: symbol)
            .font(.system(size: 11, weight: .heavy, design: .rounded))
            .textCase(.uppercase)
            .tracking(1.2)
            .foregroundStyle(.white.opacity(0.5))
    }
}

struct AppIconView: View {
    let data: Data?
    var size: CGFloat = 64

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: size * 0.225, style: .continuous)
        Group {
            if let data, let image = NSImage(data: data) {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fill)
            } else {
                ZStack {
                    Theme.accent
                    Image(systemName: "app.dashed")
                        .font(.system(size: size * 0.42, weight: .medium))
                        .foregroundStyle(.white.opacity(0.9))
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(shape)
        .overlay(shape.strokeBorder(.white.opacity(0.18), lineWidth: 0.5))
    }
}

struct StatusDot: View {
    let color: Color
    var pulsing = false

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: !pulsing)) { timeline in
            let phase = fract(timeline.date.timeIntervalSinceReferenceDate / 1.6)
            ZStack {
                if pulsing {
                    Circle()
                        .fill(color.opacity(0.45))
                        .scaleEffect(1 + phase * 1.6)
                        .opacity(1 - phase)
                }
                Circle().fill(color)
                    .shadow(color: color, radius: 4)
            }
        }
        .frame(width: 8, height: 8)
    }
}

/// Gives SwiftUI access to the hosting NSWindow.
struct WindowConfigurator: NSViewRepresentable {
    let configure: (NSWindow) -> Void

    func makeNSView(context: Context) -> ProbeView {
        let view = ProbeView()
        view.onWindow = configure
        return view
    }

    func updateNSView(_ nsView: ProbeView, context: Context) {}

    final class ProbeView: NSView {
        var onWindow: ((NSWindow) -> Void)?
        private var configured = false

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard let window, !configured else { return }
            configured = true
            DispatchQueue.main.async { [weak self] in
                self?.onWindow?(window)
            }
        }
    }
}
