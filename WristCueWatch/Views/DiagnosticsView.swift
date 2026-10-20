#if DEBUG
import SwiftUI
import WristCueKit

/// Debug builds only: traffic counters and the round-trip benchmark behind the M5
/// numbers in docs/PERFORMANCE.md.
///
/// The benchmark sends `sampleCount` volume commands one at a time and times each
/// from the send to the iPhone state that acknowledges it, on the Watch's clock.
/// Every sample is printed to the console as `WRISTCUE_RTT_MS <value>`, so the raw
/// data can be captured with `xcrun simctl launch --console`.
struct DiagnosticsView: View {
    static let sampleCount = 40

    @Environment(WatchSync.self) private var sync
    @Environment(\.trafficProbe) private var probe
    @State private var isRunning = false
    @State private var summary: LatencySummary?
    @State private var timeouts = 0

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                Button(isRunning ? "Running..." : "Run \(Self.sampleCount) commands") {
                    Task { await runBenchmark() }
                }
                .disabled(isRunning || sync.displayState.episodeID == nil)

                if let summary {
                    Text("n \(summary.count), timeouts \(timeouts)")
                    Text("median \(milliseconds(summary.median)) ms")
                    Text("p95 \(milliseconds(summary.p95)) ms")
                    Text("min \(milliseconds(summary.min)), max \(milliseconds(summary.max)) ms")
                } else if timeouts > 0 {
                    Text("All \(timeouts) timed out")
                }

                if let probe {
                    Divider()
                    Button("Reset counters") {
                        probe.reset()
                    }
                    TrafficTable(probe: probe)
                }
            }
            .font(.footnote.monospacedDigit())
        }
        .navigationTitle("Diagnostics")
    }

    private func runBenchmark() async {
        isRunning = true
        defer { isRunning = false }
        let mode = probe?.mode.rawValue ?? "unknown"
        emit("WRISTCUE_RTT_BEGIN mode=\(mode) count=\(Self.sampleCount)")
        let results = await sync.measureRoundTrips(count: Self.sampleCount)
        for result in results {
            emit("WRISTCUE_RTT_MS \(result.map { milliseconds($0) } ?? "timeout")")
        }
        let samples = results.compactMap { $0 }
        summary = LatencySummary(samples: samples)
        timeouts = results.count - samples.count
        if let summary {
            emit("WRISTCUE_RTT_END n=\(summary.count) timeouts=\(timeouts) median_ms=\(milliseconds(summary.median)) p95_ms=\(milliseconds(summary.p95))")
        }
    }

    /// Writes one line straight to stdout. `print` buffers when stdout is a pipe
    /// (as in `simctl launch --console ... | grep`), and the samples never appeared.
    private func emit(_ line: String) {
        FileHandle.standardOutput.write(Data((line + "\n").utf8))
    }

    private func milliseconds(_ seconds: TimeInterval) -> String {
        (seconds * 1000).formatted(.number.precision(.fractionLength(1)).grouping(.never))
    }
}
#endif
