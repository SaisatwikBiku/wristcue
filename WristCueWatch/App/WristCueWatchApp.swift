import SwiftUI
import WristCueKit

@main
struct WristCueWatchApp: App {
    // WatchSync owns the transport, which owns the WCSession.
    @State private var sync = WatchSync(transport: WCSessionTransport())

    var body: some Scene {
        WindowGroup {
            NowPlayingView()
                .environment(sync)
        }
    }
}
