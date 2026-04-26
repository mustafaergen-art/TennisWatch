import SwiftUI

@main
struct TennisWatchApp: App {
    // Initialize WatchConnectivity early
    private let connector = WatchConnector.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
