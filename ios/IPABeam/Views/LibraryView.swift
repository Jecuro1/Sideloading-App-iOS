import SwiftUI

struct LibraryView: View {
    @Environment(AppState.self) private var state
    @Binding var showImporter: Bool

    private let columns = [GridItem(.adaptive(minimum: 150), spacing: 14)]

    var body: some View {
        Page(title: "Bibliothek", subtitle: "\(state.apps.count) App\(state.apps.count == 1 ? "" : "s") auf diesem iPhone gespeichert") {
            if state.apps.isEmpty {
                VStack(spacing: 14) {
                    Image(systemName: "square.stack.3d.up.slash")
                        .font(.system(size: 40, weight: .semibold))
                        .foregroundStyle(Theme.accent)
                    Text("Noch keine IPAs")
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                    Button {
                        showImporter = true
                    } label: {
                        Label("IPA importieren", systemImage: "plus")
                    }
                    .buttonStyle(BeamButtonStyle())
                }
                .glassCard(padding: 24)
            } else {
                LazyVGrid(columns: columns, spacing: 14) {
                    ForEach(state.apps) { app in
                        LibraryTile(app: app, selected: app.id == state.selectedAppID)
                    }
                }
            }
        }
    }
}

private struct LibraryTile: View {
    @Environment(AppState.self) private var state
    let app: LibraryApp
    let selected: Bool
    @State private var confirmDelete = false

    var body: some View {
        Button {
            withAnimation(.spring(response: 0.45, dampingFraction: 0.8)) {
                state.selectedAppID = app.id
                state.run = nil
                state.tab = .beam
            }
        } label: {
            VStack(spacing: 10) {
                AppIconView(data: app.iconData, size: 70)
                    .shadow(color: (selected ? Theme.cyan : Theme.indigo).opacity(0.6), radius: 14)
                VStack(spacing: 2) {
                    Text(app.name)
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .lineLimit(1)
                    Text(app.versionLabel)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.white.opacity(0.5))
                    Text(app.formattedSize)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.white.opacity(0.35))
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 18)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .neonBorder(cornerRadius: 22, lineWidth: 1.2, active: selected)
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .strokeBorder(.white.opacity(selected ? 0 : 0.1), lineWidth: 1)
            )
        }
        .buttonStyle(PressableStyle())
        .foregroundStyle(.white)
        .contextMenu {
            if !state.isDemo {
                ShareLink(item: state.fileURL(for: app)) {
                    Label("Teilen", systemImage: "square.and.arrow.up")
                }
            }
            Button(role: .destructive) {
                confirmDelete = true
            } label: {
                Label("Löschen", systemImage: "trash")
            }
        }
        .confirmationDialog("\(app.name) löschen?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Löschen", role: .destructive) { withAnimation { state.delete(app) } }
        }
    }
}
