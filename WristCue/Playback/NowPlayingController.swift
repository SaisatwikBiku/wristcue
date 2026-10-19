import MediaPlayer
import WristCueKit

/// Publishes the current episode to the system Now Playing view (Lock Screen,
/// Control Center, and the Apple Watch's own Now Playing app).
///
/// This uses the same idea as the WristCue Watch app: the system is told the
/// elapsed time and the rate once, and animates the progress bar itself. So this
/// runs only when the state changes, never on a timer.
@MainActor
final class NowPlayingController {
    private let center = MPNowPlayingInfoCenter.default()

    func update(state: PlaybackState, episode: Episode?) {
        guard let episode else {
            center.nowPlayingInfo = nil
            return
        }
        let info: [String: Any] = [
            MPMediaItemPropertyTitle: episode.title,
            MPMediaItemPropertyArtist: "WristCue",
            MPMediaItemPropertyAlbumTitle: "WristCue sample episodes",
            MPMediaItemPropertyPlaybackDuration: state.duration,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: state.position,
            // Rate 0 tells the system the bar should stand still.
            MPNowPlayingInfoPropertyPlaybackRate: state.isPlaying ? state.rate : 0,
            MPNowPlayingInfoPropertyDefaultPlaybackRate: 1.0,
            MPNowPlayingInfoPropertyMediaType: MPNowPlayingInfoMediaType.audio.rawValue,
        ]
        center.nowPlayingInfo = info
    }
}
