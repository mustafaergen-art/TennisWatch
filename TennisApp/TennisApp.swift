import SwiftUI

@main
struct TennisApp: App {
    var body: some Scene {
        WindowGroup {
            TabView {
                MatchHistoryView()
                    .tabItem {
                        Label(L.myMatches, systemImage: "trophy")
                    }

                WatchMatchesView()
                    .tabItem {
                        Label(L.watchMatches, systemImage: "person.3")
                    }

                TodaysMatchesView()
                    .tabItem {
                        Label(L.todaysMatches, systemImage: "sportscourt")
                    }
            }
            .tint(.green)
        }
    }
}
