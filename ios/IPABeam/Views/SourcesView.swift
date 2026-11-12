import SwiftUI

struct SourcesView: View {
    @Environment(AppState.self) private var state
    @State private var newSource = ""
    @State private var isAdding = false
    @State private var addError: String?

    var body: some View {
        Page(title: "Quellen", subtitle: "App-Listen abonnieren – Updates kommen automatisch, ohne neue .ipa.") {
            addCard

            if !state.availableUpdates.isEmpty {
                UpdatesCard()
            }

            if state.sources.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "antenna.radiowaves.left.and.right")
                        .font(.system(size: 36, weight: .semibold))
                        .foregroundStyle(Theme.accent)
                        .symbolEffect(.variableColor.iterative, options: .repeating)
                    Text("Noch keine Quellen")
                        .font(.system(size: 17, weight: .bold, design: .rounded))
                    Text("Füge die Adresse einer App-Quelle (AltStore/SideStore-Format) hinzu – z. B. von Entwicklern deiner Lieblings-Apps.")
                        .font(.system(size: 13))
                        .foregroundStyle(.white.opacity(0.6))
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .glassCard(padding: 22)
            }

            ForEach(state.sources) { source in
                SourceSection(source: source)
            }
        }
        .refreshable {
            await state.refreshSources()
        }
    }

    private var addCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: "link")
                    .foregroundStyle(Theme.cyan)
                TextField("Quelle hinzufügen (URL)", text: $newSource)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
                    .submitLabel(.go)
                    .onSubmit(add)
                if isAdding {
                    ProgressView().tint(.white)
                } else {
                    Button(action: add) {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 24))
                            .foregroundStyle(Theme.accent)
                    }
                    .disabled(newSource.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            if let addError {
                Label(addError, systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Theme.danger)
            }
        }
        .glassCard(padding: 14, cornerRadius: 20)
    }

    private func add() {
        let text = newSource
        guard !text.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        isAdding = true
        addError = nil
        Task {
            do {
                try await state.addSource(text)
                newSource = ""
            } catch {
                addError = error.localizedDescription
            }
            isAdding = false
        }
    }
}

// MARK: - Updates

struct UpdatesCard: View {
    @Environment(AppState.self) private var state

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                SectionLabel(title: "Updates verfügbar", symbol: "arrow.triangle.2.circlepath")
                Spacer()
                if state.availableUpdates.count > 1 {
                    Button("Alle laden") {
                        Task { await state.updateAll() }
                    }
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.cyan)
                }
            }
            ForEach(state.availableUpdates) { update in
                HStack(spacing: 12) {
                    AppIconView(data: update.app.iconData, size: 44)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(update.app.name)
                            .font(.system(size: 15, weight: .bold))
                            .lineLimit(1)
                        HStack(spacing: 5) {
                            Text("v\(update.app.version)")
                                .foregroundStyle(.white.opacity(0.45))
                            Image(systemName: "arrow.right")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(.white.opacity(0.45))
                            Text("v\(update.version.version)")
                                .foregroundStyle(Theme.success)
                        }
                        .font(.system(size: 12, weight: .semibold))
                    }
                    Spacer()
                    DownloadButton(sourceApp: update.source, title: "Update", beam: true)
                }
            }
        }
        .glassCard(padding: 16, cornerRadius: 22)
        .neonBorder(cornerRadius: 22, lineWidth: 1.2)
    }
}

// MARK: - Source section

private struct SourceSection: View {
    @Environment(AppState.self) private var state
    let source: AppSource
    @State private var confirmRemove = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                RemoteIcon(url: source.iconURL, data: nil, size: 40, fallback: "antenna.radiowaves.left.and.right")
                VStack(alignment: .leading, spacing: 2) {
                    Text(source.name)
                        .font(.system(size: 16, weight: .heavy, design: .rounded))
                        .lineLimit(1)
                    Text("\(source.apps.count) Apps · \(source.url.host ?? "")")
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.5))
                        .lineLimit(1)
                }
                Spacer()
                Menu {
                    Button {
                        Task { await state.refreshSources() }
                    } label: {
                        Label("Aktualisieren", systemImage: "arrow.clockwise")
                    }
                    Button(role: .destructive) {
                        confirmRemove = true
                    } label: {
                        Label("Quelle entfernen", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 15, weight: .bold))
                        .frame(width: 32, height: 32)
                        .background(.white.opacity(0.08), in: Circle())
                }
                .foregroundStyle(.white)
            }

            ForEach(source.apps) { app in
                SourceAppRow(app: app)
            }
        }
        .glassCard(padding: 16, cornerRadius: 22)
        .confirmationDialog("„\(source.name)“ entfernen?", isPresented: $confirmRemove, titleVisibility: .visible) {
            Button("Entfernen", role: .destructive) { withAnimation { state.removeSource(source) } }
        }
    }
}

private struct SourceAppRow: View {
    @Environment(AppState.self) private var state
    let app: SourceApp

    var body: some View {
        HStack(spacing: 12) {
            RemoteIcon(url: app.iconURL, data: app.iconData, size: 50, fallback: "app.fill")
            VStack(alignment: .leading, spacing: 3) {
                Text(app.name)
                    .font(.system(size: 15, weight: .bold))
                    .lineLimit(1)
                Text(app.developer.isEmpty ? app.bundleID : app.developer)
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.5))
                    .lineLimit(1)
                if let latest = app.latest {
                    Text("v\(latest.version)\(latest.size.map { " · " + ByteCountFormatter.string(fromByteCount: $0, countStyle: .file) } ?? "")")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Theme.cyan)
                }
            }
            Spacer(minLength: 6)
            DownloadButton(sourceApp: app, title: buttonTitle, beam: state.libraryApp(for: app) != nil)
        }
    }

    private var buttonTitle: String {
        guard let installed = state.libraryApp(for: app), let latest = app.latest else { return "Laden" }
        return SourceLoader.isNewer(latest.version, than: installed.version) ? "Update" : "Aktuell"
    }
}

/// Download / update button with circular progress.
struct DownloadButton: View {
    @Environment(AppState.self) private var state
    let sourceApp: SourceApp
    let title: String
    var beam: Bool

    var body: some View {
        if let progress = state.downloads[sourceApp.bundleID] {
            ZStack {
                Circle().stroke(.white.opacity(0.15), lineWidth: 3)
                Circle()
                    .trim(from: 0, to: max(progress, 0.03))
                    .stroke(Theme.cyan, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.easeOut, value: progress)
                Image(systemName: "stop.fill")
                    .font(.system(size: 9))
                    .foregroundStyle(.white.opacity(0.8))
            }
            .frame(width: 30, height: 30)
        } else if title == "Aktuell" {
            Text("Aktuell")
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundStyle(Theme.success)
        } else {
            Button {
                Task { await state.download(sourceApp, thenBeam: beam) }
            } label: {
                Text(title.uppercased())
                    .font(.system(size: 12, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .frame(height: 30)
                    .background(Capsule().fill(Theme.accent))
                    .shadow(color: Theme.indigo.opacity(0.6), radius: 8)
            }
            .buttonStyle(PressableStyle())
        }
    }
}

/// App icon from a URL (or cached data) with a gradient fallback.
struct RemoteIcon: View {
    let url: URL?
    let data: Data?
    var size: CGFloat
    var fallback: String

    var body: some View {
        if let data {
            AppIconView(data: data, size: size)
        } else {
            AsyncImage(url: url) { phase in
                if let image = phase.image {
                    image.resizable().aspectRatio(contentMode: .fill)
                } else {
                    ZStack {
                        Theme.accent
                        Image(systemName: fallback)
                            .font(.system(size: size * 0.4, weight: .semibold))
                            .foregroundStyle(.white)
                    }
                }
            }
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: size * 0.225, style: .continuous))
        }
    }
}
