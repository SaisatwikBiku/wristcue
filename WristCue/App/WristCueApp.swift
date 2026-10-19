import SwiftUI
import WristCueKit

@main
struct WristCueApp: App {
    // @State keeps the coordinator alive for the app's lifetime. Views read the
    // player and the bookmarks from the environment instead of having them passed
    // down by hand.
    @State private var coordinator = PhoneCoordinator()

    var body: some Scene {
        WindowGroup {
            EpisodeListView()
                .environment(coordinator.player)
                .environment(coordinator.bookmarks)
                .environment(\.trafficProbe, TrafficProbe(mode: coordinator.mode, transport: coordinator.transport))
        }
    }
}
