import AppKit
import SwiftUI

struct SidebarView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model

        List(selection: $model.selectedDeviceID) {
            Section {
                if model.devices.isEmpty {
                    EmptyDevicesRow()
                } else {
                    ForEach(model.devices) { device in
                        DeviceRow(device: device)
                            .tag(Optional(device.id))
                    }
                }
            } header: {
                HStack {
                    Text("Geräte")
                    Spacer()
                    if model.isRefreshingDevices {
                        ProgressView().controlSize(.mini)
                    }
                }
            }

            if !model.recents.isEmpty {
                Section("Zuletzt verwendet") {
                    ForEach(model.recents) { recent in
                        RecentRow(recent: recent)
                    }
                }
            }

            if !model.history.isEmpty {
                Section("Verlauf") {
                    ForEach(model.history) { job in
                        HistoryRow(job: job)
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .bottom) {
            ToolStatusFooter()
        }
    }
}

// MARK: - Rows

struct DeviceRow: View {
    let device: Device

    var body: some View {
        HStack(spacing: 11) {
            ZStack {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(device.isAvailable ? AnyShapeStyle(Theme.accent) : AnyShapeStyle(Color.gray.opacity(0.35)))
                Image(systemName: device.symbol)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .frame(width: 32, height: 32)

            VStack(alignment: .leading, spacing: 2) {
                Text(device.name)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .lineLimit(1)
                Text(device.needsTrust ? "Vertrauen erforderlich" : (device.subtitle.isEmpty ? device.backend.title : device.subtitle))
                    .font(.system(size: 11))
                    .foregroundStyle(device.needsTrust ? AnyShapeStyle(Theme.warning) : AnyShapeStyle(.secondary))
                    .lineLimit(1)
            }

            Spacer(minLength: 4)

            Image(systemName: device.connection.symbol)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(connectionColor)
                .help(device.connectionDescription)
        }
        .padding(.vertical, 3)
        .opacity(device.isAvailable ? 1 : 0.6)
    }

    private var connectionColor: Color {
        switch device.connection {
        case .usb: return Theme.cyan
        case .wifi: return Theme.success
        case .offline: return .secondary
        }
    }
}

private struct EmptyDevicesRow: View {
    @State private var pulse = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: "iphone.radiowaves.left.and.right")
                    .symbolEffect(.pulse, options: .repeating)
                    .foregroundStyle(Theme.accent)
                Text("Suche nach Geräten …")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
            }
            Text("iPhone per USB‑C anschließen oder im selben WLAN entsperren.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 6)
    }
}

private struct RecentRow: View {
    @Environment(AppModel.self) private var model
    let recent: RecentIPA

    var body: some View {
        Button {
            Task { await model.loadIPA(at: recent.url) }
        } label: {
            HStack(spacing: 10) {
                AppIconView(data: recent.iconData, size: 26)
                VStack(alignment: .leading, spacing: 1) {
                    Text(recent.name)
                        .font(.system(size: 12, weight: .medium))
                        .lineLimit(1)
                    Text("v\(recent.version)")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if model.currentIPA?.url.path == recent.path {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Theme.success)
                        .font(.system(size: 11))
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .opacity(recent.exists ? 1 : 0.4)
        .disabled(!recent.exists)
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

private struct HistoryRow: View {
    let job: InstallJob

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: symbol)
                .foregroundStyle(color)
                .font(.system(size: 12, weight: .semibold))
            VStack(alignment: .leading, spacing: 1) {
                Text(job.appName)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
                Text("\(job.deviceName) · \(job.startedAt.formatted(date: .omitted, time: .shortened))")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }

    private var symbol: String {
        switch job.state {
        case .succeeded: return "checkmark.circle.fill"
        case .failed: return "xmark.octagon.fill"
        case .cancelled: return "stop.circle.fill"
        case .running: return "arrow.triangle.2.circlepath"
        }
    }

    private var color: Color {
        switch job.state {
        case .succeeded: return Theme.success
        case .failed: return Theme.danger
        case .cancelled, .running: return .secondary
        }
    }
}

private struct ToolStatusFooter: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        HStack(spacing: 10) {
            chip("devicectl", ok: model.tools.devicectl)
            chip("libimobiledevice", ok: model.tools.libimobiledeviceReady)
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .opacity(model.tools.checked ? 1 : 0.4)
    }

    private func chip(_ title: String, ok: Bool) -> some View {
        HStack(spacing: 4) {
            Image(systemName: ok ? "checkmark.circle.fill" : "xmark.circle")
                .foregroundStyle(ok ? Theme.success : .secondary)
            Text(title)
                .foregroundStyle(.secondary)
        }
        .font(.system(size: 10, weight: .medium, design: .rounded))
        .help(ok ? "\(title) ist verfügbar" : "\(title) ist nicht installiert")
    }
}
