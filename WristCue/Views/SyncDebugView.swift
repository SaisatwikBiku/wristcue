#if DEBUG
import SwiftUI
import WristCueKit

/// Debug builds only: WatchConnectivity traffic since the last reset, for the M5
/// measurements in docs/PERFORMANCE.md.
struct SyncDebugView: View {
    @Environment(\.trafficProbe) private var probe

    var body: some View {
        if let probe {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Sync traffic (debug)")
                        .font(.caption.bold())
                    Spacer()
                    Button("Reset") {
                        probe.reset()
                    }
                    .font(.caption)
                }
                TrafficTable(probe: probe)
            }
            .padding(8)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
        }
    }
}
#endif
