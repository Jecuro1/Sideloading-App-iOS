import SwiftUI

struct ContentView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model

        NavigationSplitView {
            SidebarView()
                .navigationSplitViewColumnWidth(min: 250, ideal: 280, max: 360)
        } detail: {
            ZStack {
                AuroraBackground()
                MainPanel()
            }
            .toolbar {
                ToolbarItemGroup(placement: .primaryAction) {
                    Button {
                        Task { await model.refreshDevices() }
                    } label: {
                        Label("Geräte aktualisieren", systemImage: "arrow.clockwise")
                    }
                    .help("Geräte aktualisieren (⌘R)")

                    Button {
                        model.presentImporter = true
                    } label: {
                        Label("IPA öffnen", systemImage: "plus.app")
                    }
                    .help("IPA öffnen (⌘O)")

                    Button {
                        model.showOnboarding = true
                    } label: {
                        Label("Hilfe", systemImage: "questionmark.circle")
                    }
                    .help("Einrichtungshilfe")

                    SettingsLink {
                        Label("Einstellungen", systemImage: "gearshape")
                    }
                    .help("Einstellungen (⌘,)")
                }
            }
            .toolbarBackground(.hidden, for: .windowToolbar)
        }
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
        }
        .task {
            await model.start()
        }
    }
}
