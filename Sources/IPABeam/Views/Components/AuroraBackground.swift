import SwiftUI

/// Full-window animated background: mesh gradient (macOS 15) or aurora blobs,
/// a moving synthwave grid floor, drifting particles and a vignette.
struct BeamBackground: View {
    var showsGrid = true

    var body: some View {
        ZStack {
            Theme.background
            MeshLayer()
            if showsGrid {
                GridFloor()
                    .opacity(0.45)
            }
            ParticleField()
            RadialGradient(
                colors: [.clear, .black.opacity(0.65)],
                center: .center,
                startRadius: 250,
                endRadius: 1100
            )
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }
}

/// Kept for the onboarding sheet and as a fallback.
typealias AuroraBackground = BeamBackground

private struct MeshLayer: View {
    var body: some View {
        #if compiler(>=6.0)
        if #available(macOS 15.0, *) {
            AnimatedMesh()
        } else {
            AuroraBlobs()
        }
        #else
        AuroraBlobs()
        #endif
    }
}

#if compiler(>=6.0)
@available(macOS 15.0, *)
private struct AnimatedMesh: View {
    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
            let t = Float(timeline.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 10_000))
            MeshGradient(width: 3, height: 3, points: Self.points(t), colors: Self.colors)
                .opacity(0.9)
        }
    }

    private static func points(_ t: Float) -> [SIMD2<Float>] {
        let leftY: Float = 0.5 + 0.12 * sin(t * 0.45)
        let rightY: Float = 0.5 + 0.12 * cos(t * 0.38)
        let centerX: Float = 0.5 + 0.18 * sin(t * 0.31)
        let centerY: Float = 0.45 + 0.15 * cos(t * 0.27)
        let topX: Float = 0.5 + 0.2 * sin(t * 0.22)
        let bottomX: Float = 0.5 + 0.2 * cos(t * 0.25)
        return [
            SIMD2(0, 0), SIMD2(topX, 0), SIMD2(1, 0),
            SIMD2(0, leftY), SIMD2(centerX, centerY), SIMD2(1, rightY),
            SIMD2(0, 1), SIMD2(bottomX, 1), SIMD2(1, 1)
        ]
    }

    private static let colors: [Color] = [
        Color(red: 0.02, green: 0.03, blue: 0.10),
        Color(red: 0.16, green: 0.08, blue: 0.42),
        Color(red: 0.03, green: 0.04, blue: 0.14),
        Color(red: 0.30, green: 0.06, blue: 0.40),
        Color(red: 0.05, green: 0.30, blue: 0.48),
        Color(red: 0.36, green: 0.07, blue: 0.36),
        Color(red: 0.02, green: 0.03, blue: 0.09),
        Color(red: 0.12, green: 0.08, blue: 0.36),
        Color(red: 0.02, green: 0.02, blue: 0.08)
    ]
}
#endif

private struct AuroraBlobs: View {
    var body: some View {
        GeometryReader { proxy in
            TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
                let t = timeline.date.timeIntervalSinceReferenceDate
                let w = proxy.size.width
                let h = proxy.size.height
                ZStack {
                    Circle().fill(Theme.indigo)
                        .frame(width: w * 0.7, height: w * 0.7)
                        .offset(x: -w * 0.2 + sin(t * 0.2) * w * 0.1, y: -h * 0.25 + cos(t * 0.17) * h * 0.1)
                    Circle().fill(Theme.magenta)
                        .frame(width: w * 0.5, height: w * 0.5)
                        .offset(x: w * 0.28 + cos(t * 0.23) * w * 0.08, y: -h * 0.1 + sin(t * 0.19) * h * 0.12)
                    Circle().fill(Theme.cyan)
                        .frame(width: w * 0.45, height: w * 0.45)
                        .offset(x: sin(t * 0.15) * w * 0.15, y: h * 0.3)
                }
                .frame(width: w, height: h)
                .blur(radius: 120)
                .opacity(0.45)
            }
        }
    }
}

/// Perspective grid that scrolls towards the viewer.
struct GridFloor: View {
    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            Canvas { context, size in
                let horizon = size.height * 0.62
                let vanishing = CGPoint(x: size.width / 2, y: horizon)
                var path = Path()

                let rays = 36
                for index in 0...rays {
                    let x = CGFloat(index) / CGFloat(rays) * size.width * 4 - size.width * 1.5
                    path.move(to: vanishing)
                    path.addLine(to: CGPoint(x: x, y: size.height))
                }

                let phase = CGFloat(fract(t / 1.8))
                let lines = 16
                for index in 0..<lines {
                    let progress = (CGFloat(index) + phase) / CGFloat(lines)
                    let y = horizon + (size.height - horizon) * progress * progress
                    path.move(to: CGPoint(x: 0, y: y))
                    path.addLine(to: CGPoint(x: size.width, y: y))
                }

                var clipped = context
                clipped.clip(to: Path(CGRect(x: 0, y: horizon, width: size.width, height: size.height - horizon)))
                clipped.stroke(
                    path,
                    with: .linearGradient(
                        Gradient(colors: [Theme.cyan.opacity(0), Theme.indigo.opacity(0.7), Theme.magenta.opacity(0.9)]),
                        startPoint: CGPoint(x: 0, y: horizon),
                        endPoint: CGPoint(x: 0, y: size.height)
                    ),
                    lineWidth: 1
                )

                // Horizon glow
                let glowRect = CGRect(x: 0, y: horizon - 60, width: size.width, height: 120)
                context.fill(
                    Path(glowRect),
                    with: .linearGradient(
                        Gradient(colors: [.clear, Theme.magenta.opacity(0.18), .clear]),
                        startPoint: CGPoint(x: 0, y: glowRect.minY),
                        endPoint: CGPoint(x: 0, y: glowRect.maxY)
                    )
                )
            }
        }
    }
}

/// Slowly rising, twinkling star dust.
struct ParticleField: View {
    var count = 90

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 100_000)
            Canvas { context, size in
                for index in 0..<count {
                    let seed = Double(index) * 12.9898
                    let rx = fract(sin(seed) * 43_758.5453)
                    let ry = fract(sin(seed * 1.7) * 24_634.6345)
                    let speed = 0.004 + fract(sin(seed * 2.3) * 9_631.1) * 0.012
                    let y = fract(ry - t * speed)
                    let x = rx + sin(t * 0.3 + seed) * 0.008
                    let radius = 0.5 + fract(sin(seed * 3.1) * 1_234.5) * 1.5
                    let twinkle = 0.5 + 0.5 * sin(t * (1 + rx * 2) + seed)
                    let rect = CGRect(
                        x: x * size.width,
                        y: y * size.height,
                        width: radius * 2,
                        height: radius * 2
                    )
                    let color = index % 5 == 0 ? Theme.cyan : (index % 7 == 0 ? Theme.magenta : Color.white)
                    context.fill(Path(ellipseIn: rect), with: .color(color.opacity(0.15 + twinkle * 0.45)))
                }
            }
        }
    }
}
