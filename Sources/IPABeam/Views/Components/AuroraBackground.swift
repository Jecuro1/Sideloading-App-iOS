import SwiftUI

/// Slowly drifting, blurred colour blobs behind the content.
struct AuroraBackground: View {
    @Environment(\.colorScheme) private var colorScheme
    @State private var phase = false

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            ZStack {
                blob(Theme.indigo, diameter: size.width * 0.75)
                    .offset(x: phase ? -size.width * 0.25 : -size.width * 0.05,
                            y: phase ? -size.height * 0.30 : -size.height * 0.10)
                blob(Theme.magenta, diameter: size.width * 0.55)
                    .offset(x: phase ? size.width * 0.30 : size.width * 0.12,
                            y: phase ? size.height * 0.05 : -size.height * 0.25)
                blob(Theme.cyan, diameter: size.width * 0.50)
                    .offset(x: phase ? -size.width * 0.05 : size.width * 0.20,
                            y: phase ? size.height * 0.35 : size.height * 0.25)
            }
            .frame(width: size.width, height: size.height)
            .blur(radius: 110)
            .opacity(colorScheme == .dark ? 0.55 : 0.35)
        }
        .background(colorScheme == .dark
                     ? Color(red: 0.05, green: 0.06, blue: 0.10)
                     : Color(red: 0.95, green: 0.96, blue: 0.99))
        .drawingGroup()
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .onAppear {
            withAnimation(.easeInOut(duration: 16).repeatForever(autoreverses: true)) {
                phase = true
            }
        }
    }

    private func blob(_ color: Color, diameter: CGFloat) -> some View {
        Circle()
            .fill(color)
            .frame(width: diameter, height: diameter)
    }
}
