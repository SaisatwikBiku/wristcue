import SwiftUI
import WristCueKit

@main
struct WristCueApp: App {
    // @State owns the model for the app's lifetime. Views read it from the
    // environment instead of having it passed down by hand.
    @State private var player: PlayerModel
    /// Owns the WatchConnectivity session. Kept for the app's lifetime.
    private let phoneSync: PhoneSync

    init() {
        let player = PlayerModel()
        // Commands from the Watch take the same path as the app's own buttons.
        let phoneSync = PhoneSync(transport: WCSessionTransport()) { [weak player] command in
            player?.perform(command)
        }
        // Every state change goes to the Watch. PlayerModel only refreshes state
        // when something changed, so this is not a per-second stream.
        player.onStateChange = { [weak phoneSync] state in
            phoneSync?.publish(state)
        }
        phoneSync.publish(player.state)
        _player = State(initialValue: player)
        self.phoneSync = phoneSync
    }

    var body: some Scene {
        WindowGroup {
            EpisodeListView()
                .environment(player)
        }
    }
}
