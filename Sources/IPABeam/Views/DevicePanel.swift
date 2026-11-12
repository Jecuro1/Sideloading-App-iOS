import AppKit
import SwiftUI

/// Left column: devices, library of recent IPAs and tool status.
struct DevicePanel: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                SectionLabel(title: "Geräte", symbol: "iphone.gen3.radiowaves.left.and.right")
                Spacer()
                if model.isRefreshingDevices {
                    ProgressView().controlSize(.mini)
                }
                Text("\(model.devices.filter(\.isAvailable).count)")
                    .font(.system(size: 11, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white.opacity(0.6))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(.white.opacity(0.08), in: Capsule())
            }

            if model.devices.isEmpty {
                RadarSearchCard()
            } else {
                VStack(spacing: 8) {
                    ForEach(model.devices) { device in
                        DeviceCard(device: device, selected: device.id == model.selectedDeviceID)
                            .onTapGesture {
                                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                                    model.selectedDeviceID = device.id
                                }
                            }
                    }
                }
            }

            if let device = model.selectedDevice, device.needsTrust {
                TrustHint(device: device)
            }

            HStack {
                SectionLabel(title: "Bibliothek", symbol: "square.stack.3d.up.fill")
                Spacer()
                Button {
                    model.presentImporter = true
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 11, weight: .bold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.white.opacity(0.6))
                .help("IPA öffnen (⌘O)")
            }
            .padding(.top, 10)

            if model.recents.isEmpty {
                Text("Hier erscheinen zuletzt verwendete IPAs.")
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.4))
            } else {
                ScrollView {
                    VStack(spacing: 4) {
                        ForEach(model.recents) { recent in
                            LibraryRow(recent: recent)
                        }
                    }
                }
                .scrollIndicators(.never)
            }

            Spacer(minLength: 0)

            ToolStatusFooter()
        }
        .padding(18)
        .frame(maxHeight: .infinity, alignment: .top)
        .glassCard(padding: 0, cornerRadius: 26)
    }
}

// MARK: - Device card

struct DeviceCard: View {
    let device: Device
    let selected: Bool
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(device.isAvailable ? AnyShapeStyle(Theme.accent) : AnyShapeStyle(Color.white.opacity(0.08)))
                    .shadow(color: device.isAvailable ? Theme.indigo.opacity(0.6) : .clear, radius: 8)
                Image(systemName: device.symbol)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .frame(width: 40, height: 40)

            VStack(alignment: .leading, spacing: 3) {
                Text(device.name)
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Text(device.needsTrust ? "Vertrauen erforderlich" : (device.subtitle.isEmpty ? device.backend.title : device.subtitle))
                    .font(.system(size: 11))
                    .foregroundStyle(device.needsTrust ? AnyShapeStyle(Theme.warning) : AnyShapeStyle(Color.white.opacity(0.5)))
                    .lineLimit(1)
            }

            Spacer(minLength: 4)

            ConnectionBadge(connection: device.connection)
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(selected ? Theme.indigo.opacity(0.22) : Color.white.opacity(hovering ? 0.07 : 0.035))
        )
        .neonBorder(cornerRadius: 16, lineWidth: 1.2, active: selected)
        .opacity(device.isAvailable ? 1 : 0.55)
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.15), value: hovering)
    }
}

struct ConnectionBadge: View {
    let connection: ConnectionType

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: connection.symbol)
                .font(.system(size: 9, weight: .heavy))
            Text(connection.title)
                .font(.system(size: 9, weight: .heavy, design: .rounded))
        }
        .foregroundStyle(tint)
        .padding(.horizontal, 7)
        .padding(.vertical, 4)
        .background(tint.opacity(0.15), in: Capsule())
        .overlay(Capsule().strokeBorder(tint.opacity(0.35), lineWidth: 0.5))
        .shadow(color: tint.opacity(0.4), radius: 4)
    }

    private var tint: Color {
        switch connection {
        case .usb: return Theme.cyan
        case .wifi: return Theme.success
        case .offline: return .gray
        }
    }
}

/// Animated radar shown while no device is found.
private struct RadarSearchCard: View {
    var body: some View {
        VStack(spacing: 12) {
            TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
                let t = timeline.date.timeIntervalSinceReferenceDate
                ZStack {
                    ForEach(0..<3, id: \.self) { ring in
                        let phase = fract(t / 2.4 + Double(ring) / 3)
                        Circle()
                            .stroke(Theme.cyan.opacity(1 - phase), lineWidth: 1.5)
                            .scaleEffect(0.2 + phase * 0.8)
                    }
                    Circle()
                        .trim(from: 0, to: 0.25)
                        .stroke(AngularGradient(colors: [Theme.cyan.opacity(0), Theme.cyan], center: .center),
                                style: StrokeStyle(lineWidth: 40))
                        .rotationEffect(.degrees(fract(t / 2) * 360))
                        .opacity(0.25)
                        .padding(20)
                    Image(systemName: "iphone")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(.white)
                }
            }
            .frame(width: 110, height: 110)

            Text("Suche nach Geräten …")
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
            Text("iPhone per USB‑C anschließen oder im selben WLAN entsperren.")
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.5))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .background(Color.white.opacity(0.03), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

private struct TrustHint: View {
    @Environment(AppModel.self) private var model
    let device: Device

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("iPhone entsperren und „Vertrauen“ tippen.", systemImage: "lock.open.fill")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Theme.warning)
            if device.backend == .libimobiledevice, device.connection == .usb, model.tools.idevicePair != nil {
                Button("Jetzt koppeln") { Task { await model.pair(device) } }
                    .controlSize(.small)
            }
            if let message = model.pairingMessage {
                Text(message).font(.system(size: 10)).foregroundStyle(.white.opacity(0.6))
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.warning.opacity(0.10), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

private struct LibraryRow: View {
    @Environment(AppModel.self) private var model
    let recent: RecentIPA
    @State private var hovering = false

    private var isCurrent: Bool { model.currentIPA?.url.path == recent.path }

    var body: some View {
        Button {
            Task { await model.loadIPA(at: recent.url) }
        } label: {
            HStack(spacing: 10) {
                AppIconView(data: recent.iconData, size: 30)
                VStack(alignment: .leading, spacing: 1) {
                    Text(recent.name)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    Text("v\(recent.version) · \(recent.bundleID)")
                        .font(.system(size: 10))
                        .foregroundStyle(.white.opacity(0.45))
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                if isCurrent {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Theme.success)
                        .font(.system(size: 12))
                }
            }
            .padding(6)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.white.opacity(isCurrent ? 0.08 : (hovering ? 0.05 : 0)))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .opacity(recent.exists || model.isDemo ? 1 : 0.4)
        .disabled(!recent.exists && !model.isDemo)
        .help(recent.exists ? recent.path : "Datei nicht mehr vorhanden")
        .contextMenu {
            Button("Im Finder zeigen") {
                NSWorkspace.shared.activateFileViewerSelecting([recent.url])
            }
            .disabled(!recent.exists)
            Button("Aus Liste entfernen", role: .destructive) {
                model.removeRecent(recent)
            }
        }
    }
}

private struct ToolStatusFooter: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        HStack(spacing: 12) {
            chip("devicectl", ok: model.tools.devicectl)
            chip("libimobiledevice", ok: model.tools.libimobiledeviceReady)
            Spacer()
        }
        .opacity(model.tools.checked ? 1 : 0.4)
    }

    private func chip(_ title: String, ok: Bool) -> some View {
        HStack(spacing: 4) {
            Circle()
                .fill(ok ? Theme.success : Color.gray)
                .frame(width: 6, height: 6)
                .shadow(color: ok ? Theme.success : .clear, radius: 3)
            Text(title)
                .foregroundStyle(.white.opacity(0.5))
        }
        .font(.system(size: 10, weight: .semibold, design: .rounded))
        .help(ok ? "\(title) ist verfügbar" : "\(title) ist nicht installiert")
    }
}
