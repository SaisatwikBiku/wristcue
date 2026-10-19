import AVFoundation
import Observation
import os
import WristCueKit

/// The iPhone's single source of truth for playback.
///
/// Every control goes through `perform(_:)`: the app's buttons, the system Now
/// Playing controls, and (from M3) commands from the Watch. `perform` asks the kit's
/// pure `PlaybackState.applying(_:at:)` for the target state, drives AVFoundation
/// toward it, then reads back what the player actually did.
///
/// `@Observable` (the Observation framework, iOS 17) replaces ObservableObject and
/// @Published: SwiftUI tracks which properties each view reads and only redraws
/// those views when those properties change.
@MainActor
@Observable
final class PlayerModel {
    let episodes = Episode.library
    private(set) var currentEpisode: Episode?
    private(set) var state = PlaybackState.idle
    private(set) var loadError: String?
    /// Called after every state change. The app points this at `PhoneSync.publish`.
    @ObservationIgnored var onStateChange: (@MainActor (PlaybackState) -> Void)?

    @ObservationIgnored private let audio = EpisodePlayer()
    @ObservationIgnored private let nowPlaying = NowPlayingController()
    @ObservationIgnored private var remoteCommands: RemoteCommandController?
    // Notification tokens. The model lives as long as the app, so they're never
    // removed.
    @ObservationIgnored private var sessionObservers: [any NSObjectProtocol] = []
    @ObservationIgnored private let log = Logger(subsystem: "info.satwik.wristcue", category: "playback")

    init() {
        configureAudioSession()
        audio.onFinish = { [weak self] in
            self?.refreshState()
        }
        remoteCommands = RemoteCommandController(
            isPlaying: { [weak self] in self?.state.isPlaying ?? false },
            perform: { [weak self] action in self?.send(action) }
        )
        observeAudioSession()
    }

    // MARK: Controls

    /// Loads an episode and starts playing it. Selecting the current episode again
    /// does nothing, so reopening the player screen doesn't restart it.
    func select(_ episode: Episode) {
        guard episode != currentEpisode else { return }
        guard let url = Bundle.main.url(forResource: episode.audioFileName, withExtension: nil) else {
            loadError = "\(episode.audioFileName) isn't in the app bundle. Run scripts/make-audio.sh, then xcodegen generate."
            return
        }
        do {
            try audio.load(url)
            currentEpisode = episode
            loadError = nil
            startPlayback()
            refreshState()
        } catch {
            loadError = "Couldn't open \(episode.audioFileName): \(error.localizedDescription)"
        }
    }

    func send(_ action: Command.Action) {
        perform(Command(action: action))
    }

    /// Plays from a bookmark, switching episodes first when needed.
    func jump(to bookmark: Bookmark) {
        guard let episode = Episode.withID(bookmark.episodeID) else { return }
        select(episode)
        send(.seek(to: bookmark.position))
        if !state.isPlaying {
            send(.play)
        }
    }

    /// The player's state read now, position included. `state` only refreshes on
    /// changes; naive sync mode sends this once a second instead.
    func liveState() -> PlaybackState {
        audio.snapshot(episodeID: currentEpisode?.id, at: .now, lastCommandID: state.lastCommandID)
    }

    /// The position the listener hears now, for a bookmark made on the iPhone.
    func currentPosition(at date: Date = .now) -> TimeInterval {
        state.estimatedPosition(at: date)
    }

    func togglePlayPause() {
        send(state.isPlaying ? .pause : .play)
    }

    /// Runs one command against the player.
    func perform(_ command: Command) {
        guard let episode = currentEpisode else { return }
        let now = Date.now
        let current = audio.snapshot(episodeID: episode.id, at: now, lastCommandID: state.lastCommandID)
        let target = current.applying(command, at: now)

        if target.position != current.position {
            audio.seek(to: target.position)
        }
        if target.volume != current.volume {
            audio.setVolume(target.volume)
        }
        if target.isPlaying, !current.isPlaying {
            startPlayback()
        } else if !target.isPlaying, current.isPlaying {
            audio.pause()
        }
        refreshState(lastCommandID: command.id)
    }

    // MARK: State

    /// Reads the player into `state` and republishes Now Playing. Called only when
    /// something changed, never on a timer. Views animate progress themselves with
    /// `PlaybackState.estimatedPosition(at:)`.
    private func refreshState(lastCommandID: Command.ID? = nil) {
        state = audio.snapshot(
            episodeID: currentEpisode?.id,
            at: .now,
            lastCommandID: lastCommandID ?? state.lastCommandID
        )
        nowPlaying.update(state: state, episode: currentEpisode)
        onStateChange?(state)
        // Copied to locals: OSLog's interpolation takes autoclosures that aren't
        // main-actor isolated.
        let position = state.position
        let isPlaying = state.isPlaying
        log.debug("state position=\(position, format: .fixed(precision: 2)) playing=\(isPlaying)")
    }

    private func startPlayback() {
        do {
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            log.error("Couldn't activate the audio session: \(error.localizedDescription)")
        }
        audio.play()
    }

    // MARK: Audio session

    /// `.playback` keeps audio going with the silent switch on and in the
    /// background. `.spokenAudio` tells the system this is speech, so it pauses
    /// (rather than ducks) this app when another app speaks, such as navigation.
    private func configureAudioSession() {
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio)
        } catch {
            log.error("Couldn't set the audio session category: \(error.localizedDescription)")
        }
    }

    /// Phone calls, alarms and Siri interrupt playback. Unplugging headphones should
    /// pause, so audio doesn't suddenly come out of the speaker.
    private func observeAudioSession() {
        let center = NotificationCenter.default
        // `queue: .main` makes the closure run on the main thread, which
        // `MainActor.assumeIsolated` asserts before touching the model. Values are
        // pulled out of the Notification first because Notification isn't Sendable.
        sessionObservers.append(center.addObserver(
            forName: AVAudioSession.interruptionNotification, object: nil, queue: .main
        ) { [weak self] note in
            let rawType = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt
            let rawOptions = note.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt
            guard let self, let rawType, let type = AVAudioSession.InterruptionType(rawValue: rawType) else { return }
            let shouldResume = AVAudioSession.InterruptionOptions(rawValue: rawOptions ?? 0).contains(.shouldResume)
            MainActor.assumeIsolated {
                self.handleInterruption(type, shouldResume: shouldResume)
            }
        })
        sessionObservers.append(center.addObserver(
            forName: AVAudioSession.routeChangeNotification, object: nil, queue: .main
        ) { [weak self] note in
            let rawReason = note.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt
            guard let self, let rawReason, AVAudioSession.RouteChangeReason(rawValue: rawReason) == .oldDeviceUnavailable else {
                return
            }
            MainActor.assumeIsolated {
                self.send(.pause)
            }
        })
    }

    private func handleInterruption(_ type: AVAudioSession.InterruptionType, shouldResume: Bool) {
        switch type {
        case .began:
            // The system has already paused the player. Record that.
            refreshState()
        case .ended:
            if shouldResume {
                send(.play)
            }
        @unknown default:
            break
        }
    }
}
