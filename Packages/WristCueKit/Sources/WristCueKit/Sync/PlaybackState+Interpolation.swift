import Foundation

extension PlaybackState {
    /// The position the player has most likely reached at `now`.
    ///
    /// position(now) = position + (now - timestamp) * rate, clamped to the episode.
    ///
    /// This is how the Watch shows a moving progress bar without the iPhone sending a
    /// message every second. The iPhone only sends a new state when something
    /// changes (play, pause, seek, rate) plus a coarse heartbeat to correct drift.
    ///
    /// `timestamp` comes from the iPhone's clock and `now` from the Watch's. Paired
    /// devices both sync to network time, and in the Simulator they share the Mac's
    /// clock. A negative elapsed time (Watch clock behind) is treated as zero so the
    /// bar never moves backwards.
    public func estimatedPosition(at now: Date) -> TimeInterval {
        guard isPlaying, rate > 0 else { return clampedPosition(position) }
        let elapsed = max(0, now.timeIntervalSince(timestamp))
        return clampedPosition(position + elapsed * rate)
    }

    /// Fraction of the episode played at `now`, from 0 to 1. Returns 0 when the
    /// duration is unknown.
    public func progress(at now: Date) -> Double {
        guard duration > 0 else { return 0 }
        return estimatedPosition(at: now) / duration
    }
}
