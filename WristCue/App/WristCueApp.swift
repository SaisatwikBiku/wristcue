import SwiftUI

@main
struct WristCueApp: App {
    // @State owns the model for the app's lifetime. Views read it from the
    // environment instead of having it passed down by hand.
    @State private var player = PlayerModel()

    var body: some Scene {
        WindowGroup {
            EpisodeListView()
                .environment(player)
        }
    }
}
