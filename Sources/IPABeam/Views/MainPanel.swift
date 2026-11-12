import SwiftUI

struct MainPanel: View {
    @Environment(AppModel.self) private var model
    @State private var isDropTargeted = false

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                HeaderView()
                AppSection(isDropTargeted: isDropTargeted)
                HStack(alignment: .top, spacing: 20) {
                    TargetCard()
                    SigningCard()
                }
                .fixedSize(horizontal: false, vertical: true)
                InstallSection()
            }
            .padding(.horizontal, 36)
            .padding(.vertical, 28)
            .frame(maxWidth: 860)
            .frame(maxWidth: .infinity)
        }
        .scrollContentBackground(.hidden)
        .dropDestination(for: URL.self) { urls, _ in
            model.handleDrop(urls)
        } isTargeted: { targeted in
            withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                isDropTargeted = targeted
            }
        }
    }
}

// MARK: - Header

private struct HeaderView: View {
    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Theme.accent)
                    .frame(width: 52, height: 52)
                    .shadow(color: Theme.indigo.opacity(0.5), radius: 14, y: 6)
                Image(systemName: "arrow.down.app.fill")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundStyle(.white)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text("IPA Beam")
                    .font(.system(size: 30, weight: .heavy, design: .rounded))
                Text("Apps per USB‑C oder WLAN direkt auf dein iPhone bringen.")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.bottom, 4)
    }
}

// MARK: - App (IPA)

private struct AppSection: View {
    @Environment(AppModel.self) private var model
    let isDropTargeted: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ZStack {
                if let ipa = model.currentIPA {
                    AppCard(ipa: ipa, isDropTargeted: isDropTargeted)
                        .transition(.asymmetric(
                            insertion: .scale(scale: 0.96).combined(with: .opacity),
                            removal: .opacity
                        ))
                } else {
                    DropZone(isTargeted: isDropTargeted, isLoading: model.isInspecting) {
                        model.presentImporter = true
                    }
                    .transition(.opacity)
                }
            }
            if let error = model.inspectError {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Theme.danger)
                    .transition(.opacity)
            }
        }
    }
}

private struct DropZone: View {
    let isTargeted: Bool
    let isLoading: Bool
    let choose: () -> Void
    @State private var hue = 0.0

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 28, style: .continuous)
        VStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(Theme.accent.opacity(isTargeted ? 0.35 : 0.18))
                    .frame(width: 92, height: 92)
                    .blur(radius: isTargeted ? 6 : 0)
                if isLoading {
                    ProgressView().controlSize(.large)
                } else {
                    Image(systemName: isTargeted ? "tray.and.arrow.down.fill" : "arrow.down.app.fill")
                        .font(.system(size: 40, weight: .semibold))
                        .foregroundStyle(Theme.accent)
                        .symbolEffect(.bounce, value: isTargeted)
                        .contentTransition(.symbolEffect(.replace))
                }
            }
            Text(isLoading ? "IPA wird analysiert …" : (isTargeted ? "Loslassen zum Laden" : "IPA hierher ziehen"))
                .font(.system(size: 22, weight: .bold, design: .rounded))
            Text("Ziehe eine .ipa-Datei in dieses Fenster – oder")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
            Button("Datei auswählen …", action: choose)
                .buttonStyle(GradientButtonStyle(large: false))
                .disabled(isLoading)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 46)
        .background(.ultraThinMaterial, in: shape)
        .overlay(
            shape
                .strokeBorder(
                    Theme.ring,
                    style: StrokeStyle(lineWidth: isTargeted ? 3 : 1.5, dash: isTargeted ? [] : [9, 7])
                )
                .hueRotation(.degrees(hue))
                .opacity(isTargeted ? 1 : 0.7)
        )
        .shadow(color: Theme.indigo.opacity(isTargeted ? 0.45 : 0.12), radius: isTargeted ? 30 : 18, y: 10)
        .scaleEffect(isTargeted ? 1.015 : 1)
        .onAppear {
            withAnimation(.linear(duration: 6).repeatForever(autoreverses: false)) { hue = 360 }
        }
    }
}

private struct AppCard: View {
    @Environment(AppModel.self) private var model
    let ipa: IPAInfo
    let isDropTargeted: Bool

    var body: some View {
        HStack(spacing: 20) {
            AppIconView(data: ipa.iconData, size: 84)
            VStack(alignment: .leading, spacing: 7) {
                SectionLabel(title: "App", symbol: "app.badge")
                Text(ipa.displayName)
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .lineLimit(1)
                Text(ipa.bundleID)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                HStack(spacing: 6) {
                    Pill(text: ipa.versionLabel, symbol: "tag.fill", tint: Theme.indigo)
                    Pill(text: ipa.formattedSize, symbol: "shippingbox.fill", tint: Theme.cyan)
                    if let minimum = ipa.minimumOSVersion {
                        Pill(text: "ab iOS \(minimum)", symbol: "iphone", tint: Theme.magenta)
                    }
                    if ipa.hasExtensions {
                        Pill(text: "Erweiterungen", symbol: "puzzlepiece.extension.fill", tint: Theme.warning)
                    }
                }
            }
            Spacer(minLength: 0)
            VStack(spacing: 10) {
                Button {
                    model.presentImporter = true
                } label: {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.system(size: 14, weight: .semibold))
                        .frame(width: 32, height: 32)
                        .background(.thinMaterial, in: Circle())
                }
                .buttonStyle(.plain)
                .help("Andere IPA wählen")
                .disabled(model.isInstalling)

                Button {
                    model.clearIPA()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 13, weight: .bold))
                        .frame(width: 32, height: 32)
                        .background(.thinMaterial, in: Circle())
                }
                .buttonStyle(.plain)
                .help("Entfernen")
                .disabled(model.isInstalling)
            }
        }
        .glassCard()
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(Theme.ring, lineWidth: isDropTargeted ? 2.5 : 0)
        )
    }
}

// MARK: - Target device

private struct TargetCard: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionLabel(title: "Zielgerät", symbol: "iphone.gen3")

            if let device = model.selectedDevice {
                HStack(spacing: 14) {
                    ZStack {
                        Circle()
                            .fill(Theme.accent.opacity(device.isAvailable ? 0.22 : 0.08))
                            .frame(width: 56, height: 56)
                        Image(systemName: device.symbol)
                            .font(.system(size: 26, weight: .medium))
                            .foregroundStyle(device.isAvailable ? AnyShapeStyle(Theme.accent) : AnyShapeStyle(.secondary))
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Text(device.name)
                            .font(.system(size: 17, weight: .bold, design: .rounded))
                            .lineLimit(1)
                        if !device.subtitle.isEmpty {
                            Text(device.subtitle)
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                        }
                        HStack(spacing: 6) {
                            StatusDot(color: device.isAvailable ? Theme.success : .gray, pulsing: device.isAvailable)
                            Label(device.connectionDescription, systemImage: device.connection.symbol)
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                if device.needsTrust {
                    TrustHint(device: device)
                } else if device.developerModeEnabled == false {
                    Label("Entwicklermodus ist aus: Einstellungen → Datenschutz & Sicherheit → Entwicklermodus.",
                          systemImage: "hammer.fill")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Theme.warning)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 10) {
                        Image(systemName: "cable.connector")
                            .symbolEffect(.pulse, options: .repeating)
                        Image(systemName: "wifi")
                            .symbolEffect(.variableColor.iterative, options: .repeating)
                    }
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(Theme.accent)
                    Text("Kein iPhone gefunden")
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                    Text("Verbinde dein iPhone per USB‑C‑Kabel oder entsperre es im selben WLAN.")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    if let error = model.deviceError {
                        Text(error)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(.tertiary)
                            .lineLimit(3)
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .glassCard()
    }
}

private struct TrustHint: View {
    @Environment(AppModel.self) private var model
    let device: Device

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Entsperre das iPhone und tippe auf „Vertrauen“.", systemImage: "lock.open.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.warning)
            if device.backend == .libimobiledevice, device.connection == .usb, model.tools.idevicePair != nil {
                Button("Jetzt koppeln") {
                    Task { await model.pair(device) }
                }
                .controlSize(.small)
            }
            if let message = model.pairingMessage {
                Text(message)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - Signing

private struct SigningCard: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model

        VStack(alignment: .leading, spacing: 12) {
            HStack {
                SectionLabel(title: "Signierung", symbol: "signature")
                Spacer()
                Toggle("Neu signieren", isOn: $model.signingEnabled.animation(.snappy))
                    .toggleStyle(.switch)
                    .labelsHidden()
                    .controlSize(.small)
                    .disabled(model.isInstalling)
            }

            if model.signingEnabled {
                Picker("Zertifikat", selection: $model.selectedIdentityID) {
                    if model.identities.isEmpty {
                        Text("Keins gefunden").tag(String?.none)
                    }
                    ForEach(model.identities) { identity in
                        Text(identity.name).tag(Optional(identity.id))
                    }
                }
                Picker("Profil", selection: $model.selectedProfileID) {
                    if model.profiles.isEmpty {
                        Text("Keins gefunden").tag(String?.none)
                    }
                    ForEach(model.profiles) { profile in
                        Text("\(profile.name) · \(profile.bundleIDPattern)").tag(Optional(profile.id))
                    }
                }
                if let warning = model.signingWarning {
                    Label(warning, systemImage: "exclamationmark.triangle.fill")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Theme.warning)
                        .fixedSize(horizontal: false, vertical: true)
                } else if let profile = model.selectedProfile {
                    Label("Gültig bis \(profile.expirationDate.formatted(date: .abbreviated, time: .omitted)) · \(profile.teamName)",
                          systemImage: "checkmark.seal.fill")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Theme.success)
                }
            } else {
                Text("Die IPA wird mit ihrer vorhandenen Signatur installiert. Aktiviere „Neu signieren“, um sie mit deiner eigenen Apple‑ID bzw. deinem Entwicklerzertifikat zu signieren.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .glassCard()
        .disabled(model.isInstalling)
    }
}

// MARK: - Install

private struct InstallSection: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Group {
            if let job = model.job {
                InstallProgressCard(job: job)
                    .transition(.asymmetric(
                        insertion: .move(edge: .bottom).combined(with: .opacity),
                        removal: .opacity
                    ))
            } else {
                VStack(spacing: 10) {
                    Button {
                        model.install()
                    } label: {
                        Label(installTitle, systemImage: "arrow.down.to.line.circle.fill")
                    }
                    .buttonStyle(GradientButtonStyle())
                    .disabled(model.installBlocker != nil)
                    .keyboardShortcut(.return, modifiers: .command)

                    Text(model.installBlocker ?? "Bereit – ⌘↩ zum Installieren")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                        .contentTransition(.opacity)
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 6)
                .transition(.opacity)
            }
        }
    }

    private var installTitle: String {
        if let device = model.selectedDevice {
            return "Auf \(device.name) installieren"
        }
        return "Auf iPhone installieren"
    }
}
