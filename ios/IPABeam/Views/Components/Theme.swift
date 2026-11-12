import SwiftUI
import UIKit

enum Theme {
    static let cyan = Color(red: 0.25, green: 0.86, blue: 1.00)
    static let indigo = Color(red: 0.43, green: 0.38, blue: 1.00)
    static let magenta = Color(red: 0.93, green: 0.33, blue: 0.95)
    static let success = Color(red: 0.20, green: 0.92, blue: 0.62)
    static let warning = Color(red: 1.00, green: 0.72, blue: 0.25)
    static let danger = Color(red: 1.00, green: 0.33, blue: 0.42)
    static let background = Color(red: 0.020, green: 0.022, blue: 0.055)

    static let accent = LinearGradient(colors: [cyan, indigo, magenta], startPoint: .topLeading, endPoint: .bottomTrailing)
}

func fract(_ value: Double) -> Double { value - floor(value) }

// MARK: - Background

struct BeamBackground: View {
    var body: some View {
        ZStack {
            Theme.background
            TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
                let t = timeline.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 100_000)
                Canvas { context, size in
                    let blobs: [(Color, Double, Double, Double)] = [
                        (Theme.indigo, 0.2, 0.15, 0.9), (Theme.magenta, 0.85, 0.35, 0.7),
                        (Theme.cyan, 0.3, 0.85, 0.75)
                    ]
                    for (index, blob) in blobs.enumerated() {
                        let x = (blob.1 + sin(t * 0.17 + Double(index)) * 0.12) * size.width
                        let y = (blob.2 + cos(t * 0.13 + Double(index) * 2) * 0.08) * size.height
                        let r = blob.3 * size.width
                        context.fill(
                            Path(ellipseIn: CGRect(x: x - r / 2, y: y - r / 2, width: r, height: r)),
                            with: .radialGradient(
                                Gradient(colors: [blob.0.opacity(0.45), blob.0.opacity(0)]),
                                center: CGPoint(x: x, y: y), startRadius: 0, endRadius: r / 2
                            )
                        )
                    }
                    // star dust
                    for index in 0..<60 {
                        let seed = Double(index) * 12.9898
                        let px = fract(sin(seed) * 43_758.5453) * size.width
                        let py = fract(fract(sin(seed * 1.7) * 24_634.6345) - t * (0.004 + fract(sin(seed * 2.3) * 9_631.1) * 0.01)) * size.height
                        let radius = 0.5 + fract(sin(seed * 3.1) * 1_234.5) * 1.3
                        let alpha = 0.15 + 0.4 * (0.5 + 0.5 * sin(t * 1.3 + seed))
                        context.fill(Path(ellipseIn: CGRect(x: px, y: py, width: radius * 2, height: radius * 2)),
                                     with: .color(.white.opacity(alpha)))
                    }
                }
            }
            LinearGradient(colors: [.clear, .black.opacity(0.5)], startPoint: .center, endPoint: .bottom)
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }
}

// MARK: - Glass & neon

struct GlassCard: ViewModifier {
    var padding: CGFloat = 18
    var cornerRadius: CGFloat = 24

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(LinearGradient(colors: [.white.opacity(0.22), .white.opacity(0.04)],
                                                 startPoint: .top, endPoint: .bottom), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.3), radius: 20, y: 10)
    }
}

struct NeonBorder: ViewModifier {
    var cornerRadius: CGFloat
    var lineWidth: CGFloat = 1.5
    var active = true

    func body(content: Content) -> some View {
        content.overlay {
            if active {
                TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
                    let angle = fract(timeline.date.timeIntervalSinceReferenceDate / 5) * 360
                    let gradient = AngularGradient(colors: [Theme.cyan, Theme.indigo, Theme.magenta, Theme.cyan],
                                                   center: .center, angle: .degrees(angle))
                    ZStack {
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .strokeBorder(gradient, lineWidth: lineWidth * 3).blur(radius: 8).opacity(0.6)
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .strokeBorder(gradient, lineWidth: lineWidth)
                    }
                }
                .allowsHitTesting(false)
            }
        }
    }
}

extension View {
    func glassCard(padding: CGFloat = 18, cornerRadius: CGFloat = 24) -> some View {
        modifier(GlassCard(padding: padding, cornerRadius: cornerRadius))
    }

    func neonBorder(cornerRadius: CGFloat, lineWidth: CGFloat = 1.5, active: Bool = true) -> some View {
        modifier(NeonBorder(cornerRadius: cornerRadius, lineWidth: lineWidth, active: active))
    }
}

// MARK: - Buttons

struct BeamButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        BeamBody(configuration: configuration)
    }

    private struct BeamBody: View {
        let configuration: ButtonStyleConfiguration
        @Environment(\.isEnabled) private var isEnabled

        var body: some View {
            TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: !isEnabled)) { timeline in
                let t = timeline.date.timeIntervalSinceReferenceDate
                configuration.label
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 58)
                    .background {
                        GeometryReader { proxy in
                            ZStack {
                                Capsule().fill(LinearGradient(
                                    colors: [Theme.cyan, Theme.indigo, Theme.magenta, Theme.cyan],
                                    startPoint: UnitPoint(x: -1 + fract(t / 6) * 2, y: 0),
                                    endPoint: UnitPoint(x: 1 + fract(t / 6) * 2, y: 1)
                                ))
                                LinearGradient(colors: [.clear, .white.opacity(0.5), .clear], startPoint: .leading, endPoint: .trailing)
                                    .frame(width: 70)
                                    .rotationEffect(.degrees(18))
                                    .offset(x: -proxy.size.width / 2 - 70 + (proxy.size.width + 140) * fract(t / 2.6))
                                    .blendMode(.plusLighter)
                            }
                            .clipShape(Capsule())
                        }
                    }
                    .overlay(Capsule().strokeBorder(.white.opacity(0.35), lineWidth: 1))
                    .saturation(isEnabled ? 1 : 0)
                    .opacity(isEnabled ? 1 : 0.45)
                    .shadow(color: Theme.indigo.opacity(isEnabled ? 0.8 : 0), radius: 22, y: 8)
            }
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.6), value: configuration.isPressed)
        }
    }
}

struct PressableStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.6), value: configuration.isPressed)
    }
}

// MARK: - Small views

struct Pill: View {
    let text: String
    var symbol: String?
    var tint: Color = .secondary

    var body: some View {
        HStack(spacing: 5) {
            if let symbol { Image(systemName: symbol).font(.system(size: 10, weight: .bold)) }
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
            if let data, let image = UIImage(data: data) {
                Image(uiImage: image).resizable().aspectRatio(contentMode: .fill)
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
