import SwiftUI
import WristCueKit

@main
struct WristCueWatchApp: App {
    private static let mode = SyncMode.fromDefaults()
    private static let transport = WCSessionTransport()

    // WatchSync owns the sync logic; the transport owns the WCSession. The offline
    // queue is saved next to the app's data, so bookmarks made away from the
    // iPhone survive the app being quit.
    @State private var sync = WatchSync(
        transport: WristCueWatchApp.transport,
        queueStore: JSONFileStore(url: .applicationSupportDirectory.appending(path: "offline-queue.json")),
        mode: WristCueWatchApp.mode
    )

    var body: some Scene {
        WindowGroup {
            NavigationStack {
                NowPlayingView()
            }
            .environment(sync)
            .environment(\.trafficProbe, TrafficProbe(mode: Self.mode, transport: Self.transport))
        }
    }
}
