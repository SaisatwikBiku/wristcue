import Foundation

extension PlaybackState {
    /// The state that should result from running `command` at `now`.
    ///
    /// One pure function serves both devices. The iPhone uses it to work out the
    /// target (clamped seek position, clamped volume) before driving AVFoundation.
    /// The Watch uses it to update its screen the moment you tap, then replaces that
    /// guess when the iPhone's real state arrives. Being pure (no I/O, no clock reads)
    /// is what makes it testable without devices.
    public func applying(_ command: Command, at now: Date) -> PlaybackState {
        var next = self
        // Fold elapsed playback into the position first, so "skip 30" means 30
        // seconds from where the listener hears it now, not from the last snapshot.
        next.position = estimatedPosition(at: now)
        next.timestamp = now
        next.lastCommandID = command.id

        switch command.action {
        case .play:
            guard episodeID != nil else { break }
            if duration > 0, next.position >= duration {
                next.position = 0
            }
            next.isPlaying = true
        case .pause:
            next.isPlaying = false
        case .skip(let seconds):
            next.position = next.clampedPosition(next.position + seconds)
        case .seek(let target):
            next.position = next.clampedPosition(target)
        case .setVolume(let level):
            if level.isFinite {
                next.volume = min(max(level, 0), 1)
            }
        case .addBookmark:
            // Saving a moment never changes playback.
            break
        }
        return next
    }
}
