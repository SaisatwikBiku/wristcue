import SwiftUI
import WristCueKit

/// What the debug diagnostics screens need from the transport: the sync mode and
/// the traffic counters. Passed through the environment so views don't hold the
/// transport itself.
struct TrafficProbe: Sendable {
    let mode: SyncMode
    let read: @MainActor () -> TrafficCounter
    let reset: @MainActor () -> Void

    @MainActor
    init(mode: SyncMode, transport: WCSessionTransport) {
        self.mode = mode
        read = { [weak transport] in transport?.traffic ?? TrafficCounter() }
        reset = { [weak transport] in transport?.resetTraffic() }
    }
}

extension EnvironmentValues {
    @Entry var trafficProbe: TrafficProbe? = nil
}

/// One row per channel with messages and bytes in each direction, plus totals per
/// minute. Refreshes once a second while visible.
struct TrafficTable: View {
    let probe: TrafficProbe

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let traffic = probe.read()
            let elapsed = max(context.date.timeIntervalSince(traffic.startedAt), 0)
            VStack(alignment: .leading, spacing: 2) {
                Text("Mode: \(probe.mode.rawValue), \(Int(elapsed)) s")
                ForEach(TransportChannel.allCases, id: \.self) { channel in
                    let sent = traffic.tally(channel, .sent)
                    let received = traffic.tally(channel, .received)
                    Text("\(channel.rawValue): out \(sent.messages)/\(sent.bytes) B, in \(received.messages)/\(received.bytes) B")
                }
                Text("Out per min: \(rate(traffic.total(.sent).messages, traffic, context.date)) msgs, \(rate(traffic.total(.sent).bytes, traffic, context.date)) B")
                Text("In per min: \(rate(traffic.total(.received).messages, traffic, context.date)) msgs, \(rate(traffic.total(.received).bytes, traffic, context.date)) B")
            }
            .font(.caption2.monospacedDigit())
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func rate(_ count: Int, _ traffic: TrafficCounter, _ now: Date) -> String {
        traffic.perMinute(count, now: now).map { $0.formatted(.number.precision(.fractionLength(1))) } ?? "-"
    }
}
