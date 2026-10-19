import SwiftUI
import WristCueKit

@main
struct WristCueWatchApp: App {
    // WatchSync owns the transport, which owns the WCSession. The offline queue is
    // saved next to the app's data, so bookmarks made away from the iPhone survive
    // the app being quit.
    @State private var sync = WatchSync(
        transport: WCSessionTransport(),
        queueStore: JSONFileStore(url: .applicationSupportDirectory.appending(path: "offline-queue.json"))
    )

    var body: some Scene {
        WindowGroup {
            NavigationStack {
                NowPlayingView()
            }
            .environment(sync)
        }
    }
}
