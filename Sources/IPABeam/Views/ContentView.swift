import AppKit
import SwiftUI

struct ContentView: View {
    @Environment(AppModel.self) private var model
    @State private var isDropTargeted = false

    var body: some View {
        @Bindable var model = model

        ZStack {
            BeamBackground()

            VStack(spacing: 14) {
                TopBar()
                HStack(alignment: .top, spacing: 18) {
                    DevicePanel()
                        .frame(width: 300)
                    BeamStage()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    InspectorPanel()
                        .frame(width: 330)
                }
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 18)

            if isDropTargeted || model.forceDropTargeted {
                DropOverlay()
                    .transition(.opacity.combined(with: .scale(scale: 1.03)))
            }
        }
        .preferredColorScheme(.dark)
        .dropDestination(for: URL.self) { urls, _ in
            model.handleDrop(urls)
        } isTargeted: { targeted in
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                isDropTargeted = targeted
            }
        }
        .background(WindowConfigurator { window in
            model.configure(window: window)
        })
        .fileImporter(
            isPresented: $model.presentImporter,
            allowedContentTypes: [.ipa],
            allowsMultipleSelection: false
        ) { result in
            if case .success(let urls) = result, let url = urls.first {
                Task { await model.loadIPA(at: url) }
            }
        }
        .sheet(isPresented: $model.showOnboarding) {
            OnboardingView()
                .environment(model)
                .preferredColorScheme(.dark)
        }
        .task {
            await model.start()
        }
    }
}

// MARK: - Top bar

private struct TopBar: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        HStack(spacing: 14) {
            // Room for the window traffic lights.
            Color.clear.frame(width: 64, height: 1)

            ZStack {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(Theme.accent)
                    .frame(width: 30, height: 30)
                    .shadow(color: Theme.indigo.opacity(0.8), radius: 10)
                Image(systemName: "arrow.down.app.fill")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.white)
            }
            HStack(spacing: 6) {
                Text("IPA")
                    .foregroundStyle(.white)
                Text("Beam")
                    .foregroundStyle(Theme.accent)
            }
            .font(.system(size: 20, weight: .black, design: .rounded))

            Spacer()

            ConnectionSummary()

            Spacer()

            HStack(spacing: 8) {
                Button {
                    model.presentImporter = true
                } label: {
                    Image(systemName: "plus")
                }
                .help("IPA öffnen (⌘O)")

                Button {
                    Task { await model.refreshDevices() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .help("Geräte aktualisieren (⌘R)")

                Button {
                    model.showOnboarding = true
                } label: {
                    Image(systemName: "questionmark")
                }
                .help("Einrichtungshilfe")

                SettingsLink {
                    Image(systemName: "gearshape.fill")
                }
                .help("Einstellungen (⌘,)")
            }
            .buttonStyle(GlassIconButtonStyle())
        }
        .frame(height: 52)
    }
}

private struct ConnectionSummary: View {
    @Environment(AppModel.self) private var model

    private var usbCount: Int { model.devices.filter { $0.connection == .usb && $0.isAvailable }.count }
    private var wifiCount: Int { model.devices.filter { $0.connection == .wifi && $0.isAvailable }.count }

    var body: some View {
        HStack(spacing: 14) {
            item(symbol: "cable.connector", title: "USB‑C", count: usbCount, tint: Theme.cyan)
            Rectangle().fill(.white.opacity(0.12)).frame(width: 1, height: 16)
            item(symbol: "wifi", title: "WLAN", count: wifiCount, tint: Theme.success)
        }
        .padding(.horizontal, 16)
        .frame(height: 34)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(.white.opacity(0.12), lineWidth: 1))
    }

    private func item(symbol: String, title: String, count: Int, tint: Color) -> some View {
        HStack(spacing: 7) {
            StatusDot(color: count > 0 ? tint : .gray, pulsing: count > 0)
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(count > 0 ? tint : .gray)
            Text(count > 0 ? "\(title) · \(count)" : title)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(count > 0 ? 0.9 : 0.45))
        }
    }
}

// MARK: - Drop overlay

private struct DropOverlay: View {
    var body: some View {
        ZStack {
            Color.black.opacity(0.55)
            RoundedRectangle(cornerRadius: 36, style: .continuous)
                .fill(Theme.indigo.opacity(0.12))
                .padding(24)
                .neonBorder(cornerRadius: 36, lineWidth: 3)
                .padding(24)

            TimelineView(.animation(minimumInterval: 1.0 / 60.0)) { timeline in
                let t = timeline.date.timeIntervalSinceReferenceDate
                VStack(spacing: 22) {
                    ZStack {
                        ForEach(0..<3, id: \.self) { ring in
                            let phase = fract(t / 1.8 + Double(ring) / 3)
                            Circle()
                                .stroke(Theme.cyan.opacity(1 - phase), lineWidth: 2)
                                .frame(width: 120 + phase * 160, height: 120 + phase * 160)
                        }
                        Circle()
                            .fill(Theme.accent)
                            .frame(width: 120, height: 120)
                            .shadow(color: Theme.indigo, radius: 40)
                        Image(systemName: "arrow.down")
                            .font(.system(size: 54, weight: .heavy))
                            .foregroundStyle(.white)
                            .offset(y: sin(t * 5) * 6)
                    }
                    .frame(height: 280)
                    Text("Loslassen zum Beamen")
                        .font(.system(size: 34, weight: .black, design: .rounded))
                        .foregroundStyle(.white)
                    Text(".ipa wird sofort analysiert")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(.white.opacity(0.6))
                }
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }
}
