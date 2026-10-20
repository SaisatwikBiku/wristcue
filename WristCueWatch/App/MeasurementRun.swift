#if DEBUG
import Foundation
import WristCueKit

/// Debug builds only: the unattended measurement run, started by launching the
/// Watch app with `-WristCueAutoMeasure YES` (scripts/measure-sync.sh does this).
///
/// Phases, each with its counters reset first and one `WRISTCUE_` line after:
/// 1. Steady playback: 60 seconds with nothing touched.
/// 2. Scripted crown turn: 10 volume steps 50 ms apart, through `setVolume`, the
///    same entry point the Digital Crown uses. It's not real crown input.
/// 3. Round trips: the 40-command benchmark from the Diagnostics screen.
@MainActor
enum MeasurementRun {
    static let defaultsKey = "WristCueAutoMeasure"
    static let steadySeconds = 60
    static let crownSteps = 10

    static func runIfRequested(sync: WatchSync, transport: WCSessionTransport) async {
        guard UserDefaults.standard.bool(forKey: defaultsKey) else { return }
        let mode = sync.mode
        MeasurementLog.emit("WRISTCUE_RUN_BEGIN side=watch mode=\(mode.rawValue)")

        // The iPhone app starts the episode itself (-WristCueAutoplay).
        var waited = 0
        while !(sync.isReachable && sync.confirmedState.isPlaying) {
            if waited.isMultiple(of: 5) {
                let state = sync.confirmedState
                MeasurementLog.emit("WRISTCUE_WAIT side=watch second=\(waited) reachable=\(sync.isReachable) episode=\(state.episodeID ?? "none") playing=\(state.isPlaying) state_age_s=\(String(format: "%.1f", Date.now.timeIntervalSince(state.timestamp)))")
            }
            guard waited < 60 else {
                MeasurementLog.emit("WRISTCUE_ERROR side=watch reason=iphone_not_playing_after_60s")
                MeasurementLog.emit("WRISTCUE_DONE side=watch")
                return
            }
            try? await Task.sleep(for: .seconds(1))
            waited += 1
        }

        transport.resetTraffic()
        MeasurementLog.emit("WRISTCUE_STEADY_BEGIN side=watch")
        try? await Task.sleep(for: .seconds(steadySeconds))
        MeasurementLog.emit(MeasurementLog.traffic("STEADY", side: "watch", mode: mode, counter: transport.traffic))

        transport.resetTraffic()
        let startVolume = sync.displayState.volume
        for step in 1...crownSteps {
            sync.setVolume(max(startVolume - Double(step) * 0.02, 0))
            try? await Task.sleep(for: .milliseconds(50))
        }
        // Long enough for the debounced command and its acknowledgement.
        try? await Task.sleep(for: .seconds(3))
        MeasurementLog.emit(MeasurementLog.traffic("CROWN", side: "watch", mode: mode, counter: transport.traffic))

        transport.resetTraffic()
        let results = await sync.measureRoundTrips(count: 40)
        MeasurementLog.roundTrips(results, mode: mode)
        MeasurementLog.emit(MeasurementLog.traffic("RTT_TRAFFIC", side: "watch", mode: mode, counter: transport.traffic))

        MeasurementLog.emit("WRISTCUE_DONE side=watch")
    }
}
#endif
