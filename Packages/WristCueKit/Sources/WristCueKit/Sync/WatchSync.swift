import Foundation
import Observation

/// The Watch's view of playback, kept in step with the iPhone.
///
/// Two states are kept:
/// - `confirmedState` is the newest state the iPhone published.
/// - `displayState` is what the screen shows. After a tap it is an optimistic guess
///   (the kit's `applying(_:at:)`), so the screen reacts instantly. When the iPhone's
///   state echoes that command's ID, the guess is replaced by the real thing.
///
/// `@Observable` lets the Watch's SwiftUI views read these properties directly.
@MainActor
@Observable
public final class WatchSync {
    /// How long the screen keeps an unconfirmed guess before trusting the iPhone's
    /// state again. A design choice, not a measurement: long enough for a normal
    /// round trip, short enough that a lost command doesn't leave a wrong screen.
    public static let acknowledgementTimeout: TimeInterval = 2

    public private(set) var displayState = PlaybackState.idle
    public private(set) var confirmedState = PlaybackState.idle
    public private(set) var isReachable: Bool
    /// True when the most recent command couldn't be delivered.
    public private(set) var lastSendFailed = false
    /// Seconds from the tap to the iPhone's acknowledging state, on the Watch's clock.
    public private(set) var lastRoundTrip: TimeInterval?
    /// How long the crown must rest before a volume change is sent.
    public var volumeDebounce: Duration = .milliseconds(300)

    @ObservationIgnored private let transport: any ConnectivityTransport
    @ObservationIgnored private let clock: @MainActor () -> Date
    @ObservationIgnored private var awaitedCommand: Command?
    @ObservationIgnored private var volumeTask: Task<Void, Never>?

    /// `clock` is injectable so tests can control time.
    public init(transport: any ConnectivityTransport, clock: @escaping @MainActor () -> Date = { .now }) {
        self.transport = transport
        self.clock = clock
        isReachable = transport.isReachable
        transport.onReceive = { [weak self] message in
            self?.receive(message)
        }
        transport.onReachabilityChange = { [weak self] reachable in
            self?.isReachable = reachable
        }
    }

    // MARK: Sending

    /// Shows the expected result immediately, then sends the command. The returned
    /// task finishes when delivery succeeds or fails; the UI ignores it, tests await it.
    @discardableResult
    public func send(_ action: Command.Action) -> Task<Void, Never> {
        let command = Command(issuedAt: clock(), action: action)
        displayState = displayState.applying(command, at: command.issuedAt)
        awaitedCommand = command
        lastSendFailed = false
        return Task {
            await deliver(command)
        }
    }

    /// Called on every crown tick. Updates the screen at once but sends a single
    /// command after the crown rests for `volumeDebounce`, so one turn of the crown
    /// is one message instead of dozens.
    public func setVolume(_ level: Double) {
        guard level.isFinite else { return }
        displayState.volume = min(max(level, 0), 1)
        volumeTask?.cancel()
        let delay = volumeDebounce
        volumeTask = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard let self, !Task.isCancelled else { return }
            volumeTask = nil
            send(.setVolume(level: displayState.volume))
        }
    }

    /// Sends a pending volume change now instead of waiting for the debounce.
    /// Returns nil when nothing is pending.
    @discardableResult
    public func flushVolume() -> Task<Void, Never>? {
        guard let pending = volumeTask else { return nil }
        pending.cancel()
        volumeTask = nil
        return send(.setVolume(level: displayState.volume))
    }

    private func deliver(_ command: Command) async {
        do {
            try await transport.sendInteractive(WireMessage(payload: .command(command), sentAt: clock()))
        } catch {
            // Only the newest command decides what the screen shows.
            guard awaitedCommand?.id == command.id else { return }
            awaitedCommand = nil
            lastSendFailed = true
            displayState = confirmedState
        }
    }

    // MARK: Receiving

    func receive(_ message: WireMessage) {
        guard case .state(let state) = message.payload else { return }
        // Interactive replies and application context can arrive out of order.
        // An older snapshot never replaces a newer one.
        guard state.timestamp >= confirmedState.timestamp else { return }
        confirmedState = state

        if let awaited = awaitedCommand {
            if state.lastCommandID == awaited.id {
                lastRoundTrip = clock().timeIntervalSince(awaited.issuedAt)
                awaitedCommand = nil
            } else if clock().timeIntervalSince(awaited.issuedAt) < Self.acknowledgementTimeout {
                // This state predates the tap. Keep showing the guess.
                return
            } else {
                awaitedCommand = nil
            }
        }
        displayState = state
    }
}
