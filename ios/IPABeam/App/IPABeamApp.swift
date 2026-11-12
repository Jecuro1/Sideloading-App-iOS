import SwiftUI

@main
struct IPABeamApp: App {
    @State private var state = AppState()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(state)
                .preferredColorScheme(.dark)
                .onOpenURL { url in
                    state.handleIncoming(url)
                }
        }
    }
}
