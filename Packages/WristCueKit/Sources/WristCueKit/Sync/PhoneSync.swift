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

    private let transport: any ConnectivityTransport
    /// A command can arrive twice (an interactive send whose reply was lost, then
    /// the queued copy). Remembering recent IDs makes running a command idempotent.
    private var handledCommands = RecentIDs<Command.ID>(capacity: 256)

    public init(transport: any ConnectivityTransport) {
        self.transport = transport
        transport.onReceive = { [weak self] message in
            self?.receive(message)
        }
    }

    /// Publishes the newest state on the latest-value channel. The system keeps only
    /// the newest value, so a burst of publishes costs the Watch nothing extra.
    public func publish(_ state: PlaybackState, sentAt: Date = .now) {
        publishLatest(.state(state), sentAt: sentAt)
    }

    /// Publishes the current episode's bookmarks in their own latest-value slot, so
    /// a state update never overwrites them.
    public func publishBookmarks(_ list: BookmarkList, sentAt: Date = .now) {
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
