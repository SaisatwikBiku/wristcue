import Foundation

/// The iPhone side of sync: publishes playback state and runs commands from the Watch.
///
/// It knows nothing about AVFoundation or WatchConnectivity. The app hands it a
/// transport and a closure that runs a command, which is what makes it testable
/// with `InMemoryTransport`.
@MainActor
public final class PhoneSync {
    /// How many publishes the transport rejected (for example, Watch app not installed).
    public private(set) var publishFailures = 0

    private let transport: any ConnectivityTransport
    private let onCommand: @MainActor (Command) -> Void
    /// A command can arrive twice (an interactive send that timed out after it was
    /// delivered, then a guaranteed retry). Remembering recent IDs makes running a
    /// command idempotent.
    private var handledCommands = RecentIDs<Command.ID>(capacity: 256)

    public init(transport: any ConnectivityTransport, onCommand: @escaping @MainActor (Command) -> Void) {
        self.transport = transport
        self.onCommand = onCommand
        transport.onReceive = { [weak self] message in
            self?.receive(message)
        }
    }

    /// Publishes the newest state on the latest-value channel. The system keeps only
    /// the newest value, so publishing faster than the Watch reads costs nothing extra
    /// on the Watch side.
    public func publish(_ state: PlaybackState, sentAt: Date = .now) {
        do {
            try transport.publishLatest(WireMessage(payload: .state(state), sentAt: sentAt))
        } catch {
            publishFailures += 1
        }
    }

    func receive(_ message: WireMessage) {
        guard case .command(let command) = message.payload else { return }
        guard handledCommands.insert(command.id) else { return }
        onCommand(command)
    }
}
