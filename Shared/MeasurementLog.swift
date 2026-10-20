import Foundation
import WristCueKit

/// Machine-readable measurement lines, `WRISTCUE_<KIND> key=value ...`, written to
/// stdout for `xcrun simctl launch --console` and scripts/measure-sync.sh.
enum MeasurementLog {
    /// Writes straight to the file descriptor. `print` buffers when stdout is a
    /// pipe or a file, and buffered lines are lost when the app is terminated.
    static func emit(_ line: String) {
        FileHandle.standardOutput.write(Data((line + "\n").utf8))
    }

    /// One line with every channel's counts in both directions, as messages/bytes.
    static func traffic(_ kind: String, side: String, mode: SyncMode, counter: TrafficCounter, now: Date = .now) -> String {
        let seconds = now.timeIntervalSince(counter.startedAt)
        var fields = [
            "WRISTCUE_\(kind)",
            "side=\(side)",
            "mode=\(mode.rawValue)",
            "seconds=\(String(format: "%.1f", seconds))",
        ]
        for channel in TransportChannel.allCases {
            for direction in TrafficCounter.Direction.allCases {
                let tally = counter.tally(channel, direction)
                fields.append("\(channel.rawValue)_\(direction.rawValue)=\(tally.messages)/\(tally.bytes)")
            }
        }
        let sent = counter.total(.sent)
        let received = counter.total(.received)
        fields.append("total_sent=\(sent.messages)/\(sent.bytes)")
        fields.append("total_received=\(received.messages)/\(received.bytes)")
        return fields.joined(separator: " ")
    }

    /// Prints every round-trip sample, then the summary. Returns the summary.
    @discardableResult
    static func roundTrips(_ results: [TimeInterval?], mode: SyncMode) -> LatencySummary? {
        emit("WRISTCUE_RTT_BEGIN mode=\(mode.rawValue) count=\(results.count)")
        for result in results {
            emit("WRISTCUE_RTT_MS \(result.map(milliseconds) ?? "timeout")")
        }
        let samples = results.compactMap { $0 }
        let summary = LatencySummary(samples: samples)
        let timeouts = results.count - samples.count
        if let summary {
            emit("WRISTCUE_RTT_END mode=\(mode.rawValue) n=\(summary.count) timeouts=\(timeouts) median_ms=\(milliseconds(summary.median)) p95_ms=\(milliseconds(summary.p95)) min_ms=\(milliseconds(summary.min)) max_ms=\(milliseconds(summary.max))")
        } else {
            emit("WRISTCUE_RTT_END mode=\(mode.rawValue) n=0 timeouts=\(timeouts)")
        }
        return summary
    }

    static func milliseconds(_ seconds: TimeInterval) -> String {
        String(format: "%.1f", seconds * 1000)
    }
}
