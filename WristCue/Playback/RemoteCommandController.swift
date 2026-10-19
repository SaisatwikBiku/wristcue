import MediaPlayer
import WristCueKit

/// Connects the system's play, pause, skip and scrub controls to the app.
///
/// Every system control is turned into a `Command.Action` and handed to the same
/// `perform` function the app's own buttons and the Watch use, so there is one code
/// path for "pause" no matter where the tap came from.
@MainActor
final class RemoteCommandController {
    // `nonisolated` so the @Sendable handlers below can read them off the main thread.
    nonisolated static let skipBackSeconds: TimeInterval = 15
    nonisolated static let skipForwardSeconds: TimeInterval = 30

    typealias Perform = @MainActor @Sendable (Command.Action) -> Void
    typealias IsPlaying = @MainActor @Sendable () -> Bool

    /// `isPlaying` lets the toggle command decide between play and pause using the
    /// model's state at the moment it runs.
    init(isPlaying: @escaping IsPlaying, perform: @escaping Perform) {
        let center = MPRemoteCommandCenter.shared()
        let toggle: Perform = { _ in perform(isPlaying() ? .pause : .play) }

        Self.register(center.playCommand, perform: perform) { _ in .play }
        Self.register(center.pauseCommand, perform: perform) { _ in .pause }
        // The action passed here is a placeholder; `toggle` ignores it.
        Self.register(center.togglePlayPauseCommand, perform: toggle) { _ in .play }

        center.skipBackwardCommand.preferredIntervals = [NSNumber(value: Self.skipBackSeconds)]
        Self.register(center.skipBackwardCommand, perform: perform) { _ in .skip(seconds: -Self.skipBackSeconds) }

        center.skipForwardCommand.preferredIntervals = [NSNumber(value: Self.skipForwardSeconds)]
        Self.register(center.skipForwardCommand, perform: perform) { _ in .skip(seconds: Self.skipForwardSeconds) }

        Self.register(center.changePlaybackPositionCommand, perform: perform) { event in
            (event as? MPChangePlaybackPositionCommandEvent).map { Command.Action.seek(to: $0.positionTime) }
        }

        // An episode list with no queue: next and previous have nothing to do.
        center.nextTrackCommand.isEnabled = false
        center.previousTrackCommand.isEnabled = false
    }

    /// The handler is marked `@Sendable` so Swift doesn't assume it runs on the main
    /// thread (MediaPlayer doesn't document which thread calls it). It reads what it
    /// needs from the event right away, then hops to the main actor to act.
    private static func register(
        _ command: MPRemoteCommand,
        perform: @escaping Perform,
        action: @escaping @Sendable (MPRemoteCommandEvent) -> Command.Action?
    ) {
        command.isEnabled = true
        // The returned token is only needed to remove the target, which never happens.
        _ = command.addTarget { @Sendable event in
            guard let resolved = action(event) else { return .commandFailed }
            Task { @MainActor in
                perform(resolved)
            }
            return .success
        }
    }
}
