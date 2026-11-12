import AppKit
import SwiftUI
import UniformTypeIdentifiers

enum Theme {
    static let cyan = Color(red: 0.30, green: 0.80, blue: 1.00)
    static let indigo = Color(red: 0.42, green: 0.40, blue: 1.00)
    static let magenta = Color(red: 0.86, green: 0.36, blue: 0.96)
    static let success = Color(red: 0.24, green: 0.84, blue: 0.56)
    static let warning = Color(red: 1.00, green: 0.70, blue: 0.25)
    static let danger = Color(red: 1.00, green: 0.38, blue: 0.42)

    static let accent = LinearGradient(
        colors: [cyan, indigo, magenta],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let ring = AngularGradient(
        colors: [cyan, indigo, magenta, cyan],
        center: .center
    )
}

extension UTType {
    static let ipa = UTType(filenameExtension: "ipa", conformingTo: .zip) ?? .zip
}

// MARK: - Glass card

struct GlassCard: ViewModifier {
    var padding: CGFloat = 22
    var cornerRadius: CGFloat = 24

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            colors: [.white.opacity(0.22), .white.opacity(0.04)],
                            startPoint: .top,
                            endPoint: .bottom
                        ),
                        lineWidth: 1
                    )
            )
            .shadow(color: .black.opacity(0.16), radius: 24, y: 10)
    }
}

extension View {
    func glassCard(padding: CGFloat = 22, cornerRadius: CGFloat = 24) -> some View {
        modifier(GlassCard(padding: padding, cornerRadius: cornerRadius))
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
                    color: Theme.indigo.opacity(isEnabled ? (hovering ? 0.65 : 0.45) : 0),
                    radius: configuration.isPressed ? 6 : (hovering ? 22 : 16),
                    y: 6
                )
                .scaleEffect(configuration.isPressed ? 0.97 : (hovering && isEnabled ? 1.02 : 1))
                .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
                .animation(.easeOut(duration: 0.18), value: hovering)
                .onHover { hovering = $0 }
        }
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
        .background(tint.opacity(0.12), in: Capsule())
    }
}

struct SectionLabel: View {
    let title: String
    let symbol: String

    var body: some View {
        Label(title, systemImage: symbol)
            .font(.system(size: 12, weight: .bold, design: .rounded))
            .textCase(.uppercase)
            .tracking(0.8)
            .foregroundStyle(.secondary)
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
        .overlay(shape.strokeBorder(.white.opacity(0.15), lineWidth: 0.5))
        .shadow(color: .black.opacity(0.25), radius: size * 0.12, y: size * 0.05)
    }
}

struct StatusDot: View {
    let color: Color
    var pulsing = false
    @State private var animate = false

    var body: some View {
        ZStack {
            if pulsing {
                Circle()
                    .fill(color.opacity(0.35))
                    .scaleEffect(animate ? 2.2 : 1)
                    .opacity(animate ? 0 : 1)
            }
            Circle().fill(color)
        }
        .frame(width: 8, height: 8)
        .onAppear {
            guard pulsing else { return }
            withAnimation(.easeOut(duration: 1.6).repeatForever(autoreverses: false)) { animate = true }
        }
    }
}
