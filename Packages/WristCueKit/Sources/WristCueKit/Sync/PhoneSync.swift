import Foundation

/// The iPhone side of sync: publishes playback state and bookmarks, and hands
/// commands from the Watch to the app.
///
/// It knows nothing about AVFoundation or WatchConnectivity. The app gives it a
/// transport and sets `onCommand`, which is what makes it testable with
/// `InMemoryTransport`.
@MainActor
public final class PhoneSync {
    /// How many publishes the transport rejected (for example, Watch app not installed).
    public private(set) var publishFailures = 0
    /// Runs each command from the Watch once, however many times it arrives.
    public var onCommand: (@MainActor (Command) -> Void)?
    public let mode: SyncMode

    private let transport: any ConnectivityTransport
    /// A command can arrive twice (an interactive send whose reply was lost, then
    /// the queued copy). Remembering recent IDs makes running a command idempotent.
    private var handledCommands = RecentIDs<Command.ID>(capacity: 256)
    /// The newest state and bookmark list, for replies to the Watch.
    private var latestState: PlaybackState?
    private var latestBookmarks: BookmarkList?

    public init(transport: any ConnectivityTransport, mode: SyncMode = .optimized) {
        self.transport = transport
        self.mode = mode
        transport.onReceive = { [weak self] message in
            self?.receive(message)
        }
        transport.replyProvider = { [weak self] message in
            self?.reply(to: message)
        }
    }

    /// The answer to a live message from the Watch: the newest value for a
    /// request, and in optimized mode the state that results from a command, so
    /// the Watch's acknowledgement comes back on the live channel.
    func reply(to message: WireMessage) -> WireMessage? {
        switch message.payload {
        case .request(.state):
            return latestState.map { WireMessage(payload: .state($0)) }
        case .request(.bookmarks):
            return latestBookmarks.map { WireMessage(payload: .bookmarks($0)) }
        case .command:
            guard mode == .optimized else { return nil }
            return latestState.map { WireMessage(payload: .state($0)) }
        case .request, .state, .bookmarks:
            return nil
        }
    }

    /// Optimized mode: publishes the newest state on the latest-value channel. The
    /// system keeps only the newest value, so a burst of publishes costs the Watch
    /// nothing extra.
    ///
    /// Naive mode: sends the state as a live message. The returned task finishes
    /// when that send does (tests await it); it's nil in optimized mode.
    @discardableResult
    public func publish(_ state: PlaybackState, sentAt: Date = .now) -> Task<Void, Never>? {
        latestState = state
        switch mode {
        case .optimized, .contextAck:
            publishLatest(.state(state), sentAt: sentAt)
            return nil
        case .naive:
            let message = WireMessage(payload: .state(state), sentAt: sentAt)
            return Task {
                do {
                    try await transport.sendInteractive(message)
                } catch {
                    publishFailures += 1
                }
            }
        }
    }

    /// Publishes the current episode's bookmarks in their own latest-value slot, so
    /// a state update never overwrites them.
    public func publishBookmarks(_ list: BookmarkList, sentAt: Date = .now) {
        latestBookmarks = list
        publishLatest(.bookmarks(list), sentAt: sentAt)
    }

    private func publishLatest(_ payload: WireMessage.Payload, sentAt: Date) {
        do {
            try transport.publishLatest(WireMessage(payload: payload, sentAt: sentAt))
        } catch {
            publishFailures += 1
        }
    }

    func receive(_ message: WireMessage) {
        guard case .command(let command) = message.payload else { return }
        guard handledCommands.insert(command.id) else { return }
        onCommand?(command)
    }
}
