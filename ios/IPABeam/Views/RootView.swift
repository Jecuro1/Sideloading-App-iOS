import SwiftUI
import UniformTypeIdentifiers

extension UTType {
    static let ipa = UTType(filenameExtension: "ipa") ?? .data
    static let mobileProvision = UTType(filenameExtension: "mobileprovision") ?? .data
    static let p12 = UTType(filenameExtension: "p12") ?? .pkcs12
}

struct RootView: View {
    @Environment(AppState.self) private var state
    @State private var showImporter = false

    var body: some View {
        @Bindable var state = state

        ZStack(alignment: .bottom) {
            BeamBackground()

            Group {
                switch state.tab {
                case .beam: BeamView(showImporter: $showImporter)
                case .library: LibraryView(showImporter: $showImporter)
                case .certificates: CertificatesView()
                case .settings: MoreView()
                }
            }
            .transition(.opacity)
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            TabBar(selection: $state.tab)
                .padding(.horizontal, 22)
                .padding(.bottom, 6)

            if let toast = state.toast {
                Text(toast)
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .padding(.horizontal, 18)
                    .padding(.vertical, 11)
                    .background(.ultraThinMaterial, in: Capsule())
                    .overlay(Capsule().strokeBorder(Theme.success.opacity(0.5), lineWidth: 1))
                    .shadow(color: Theme.success.opacity(0.4), radius: 12)
                    .frame(maxHeight: .infinity, alignment: .top)
                    .padding(.top, 8)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.85), value: state.tab)
        .fileImporter(isPresented: $showImporter, allowedContentTypes: [.ipa], allowsMultipleSelection: false) { result in
            if case .success(let urls) = result, let url = urls.first {
                state.importIPA(from: url)
            }
        }
        .alert("Import fehlgeschlagen", isPresented: Binding(
            get: { state.importError != nil },
            set: { if !$0 { state.importError = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(state.importError ?? "")
        }
    }
}

// MARK: - Floating glass tab bar

private struct TabBar: View {
    @Binding var selection: Tab
    @Namespace private var namespace

    var body: some View {
        HStack(spacing: 4) {
            ForEach(Tab.allCases) { tab in
                Button {
                    selection = tab
                } label: {
                    VStack(spacing: 3) {
                        Image(systemName: tab.symbol)
                            .font(.system(size: 18, weight: .semibold))
                            .symbolEffect(.bounce, value: selection == tab)
                        Text(tab.title)
                            .font(.system(size: 10, weight: .bold, design: .rounded))
                    }
                    .foregroundStyle(selection == tab ? Color.white : Color.white.opacity(0.5))
                    .frame(maxWidth: .infinity)
                    .frame(height: 54)
                    .background {
                        if selection == tab {
                            Capsule()
                                .fill(Theme.accent.opacity(0.35))
                                .overlay(Capsule().strokeBorder(.white.opacity(0.25), lineWidth: 1))
                                .shadow(color: Theme.indigo.opacity(0.7), radius: 10)
                                .matchedGeometryEffect(id: "tab", in: namespace)
                        }
                    }
                }
                .buttonStyle(PressableStyle())
            }
        }
        .padding(6)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(.white.opacity(0.14), lineWidth: 1))
        .shadow(color: .black.opacity(0.4), radius: 20, y: 10)
    }
}

/// Shared page scaffold with a large title.
struct Page<Content: View>: View {
    let title: String
    var subtitle: String?
    @ViewBuilder var content: Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.system(size: 32, weight: .black, design: .rounded))
                    if let subtitle {
                        Text(subtitle)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(.white.opacity(0.55))
                    }
                }
                .padding(.top, 8)
                content
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 110)
        }
        .scrollIndicators(.hidden)
    }
}
