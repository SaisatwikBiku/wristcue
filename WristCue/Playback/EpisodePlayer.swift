import AVFoundation
import WristCueKit

/// A thin wrapper around AVAudioPlayer for one local file at a time.
///
/// AVAudioPlayer instead of AVPlayer: the episodes are small files in the app
/// bundle, and AVAudioPlayer gives a synchronous `currentTime`, `duration` and
/// `isPlaying` with no key-value observing. AVPlayer is the right choice for
/// streaming, playlists or video, none of which this app needs.
@MainActor
final class EpisodePlayer: NSObject {
    /// Called when an episode plays to the end.
    var onFinish: (@MainActor () -> Void)?

    private var player: AVAudioPlayer?

    func load(_ url: URL) throws {
        player?.stop()
        let newPlayer = try AVAudioPlayer(contentsOf: url)
        newPlayer.enableRate = true
        newPlayer.delegate = self
        newPlayer.prepareToPlay()
        player = newPlayer
    }

    func play() {
        player?.play()
    }

    func pause() {
        player?.pause()
    }

    func seek(to position: TimeInterval) {
        player?.currentTime = position
    }

    func setVolume(_ level: Double) {
        player?.volume = Float(level)
    }

    /// Reads the player's real values into the shared state type.
    func snapshot(episodeID: Episode.ID?, at now: Date, lastCommandID: Command.ID?) -> PlaybackState {
        guard let player else {
            return PlaybackState(timestamp: now, lastCommandID: lastCommandID)
        }
        return PlaybackState(
            episodeID: episodeID,
            position: player.currentTime,
            duration: player.duration,
            rate: Double(player.rate),
            isPlaying: player.isPlaying,
            volume: Double(player.volume),
            timestamp: now,
            lastCommandID: lastCommandID
        )
    }
}

extension EpisodePlayer: AVAudioPlayerDelegate {
    // AVFoundation doesn't promise which thread calls the delegate, so the method is
    // `nonisolated` and hops to the main actor itself.
    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in
            self.onFinish?()
        }
    }
}
