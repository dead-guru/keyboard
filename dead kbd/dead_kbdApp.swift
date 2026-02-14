import SwiftUI

@main
struct dead_kbdApp: App {
    @State private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            ContentView(appState: appState)
        }
    }
}
