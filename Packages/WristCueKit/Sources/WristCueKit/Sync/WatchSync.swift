import Foundation
import Observation

/// A bookmark as the Watch lists it: confirmed by the iPhone, or still pending.
public struct BookmarkItem: Identifiable, Hashable, Sendable {
    public let bookmark: Bookmark
    /// True until the iPhone's bookmark list includes it.
    public let isPending: Bool
    public var id: Bookmark.ID { bookmark.id }
}

/// The Watch's view of playback and bookmarks, kept in step with the iPhone.
///
/// Two playback states are kept:
/// - `confirmedState` is the newest state the iPhone published.
/// - `displayState` is what the screen shows. After a tap it's an optimistic guess
///   (the kit's `applying(_:at:)`), so the screen reacts instantly. When the
///   iPhone's state echoes that command's ID, the guess is replaced.
///
/// While the iPhone is unreachable, commands and bookmarks wait in an
/// `OfflineQueue`, saved to disk, and are sent with the guaranteed channel when the
/// iPhone comes back.
@MainActor
@Observable
public final class WatchSync {
    /// How long the screen keeps an unconfirmed guess before trusting the iPhone's
    /// state again. A design choice, not a measurement.
    public static let acknowledgementTimeout: TimeInterval = 2

    public private(set) var displayState = PlaybackState.idle
    public private(set) var confirmedState = PlaybackState.idle
    public private(set) var isReachable: Bool
    /// Commands and bookmarks waiting for the iPhone.
    public private(set) var queuedCount = 0
    /// The iPhone's bookmarks for its current episode.
    public private(set) var bookmarkList: BookmarkList?
    /// Seconds from the tap to the iPhone's acknowledging state, on the Watch's clock.
    public private(set) var lastRoundTrip: TimeInterval?
    /// How long the crown must rest before a volume change is sent.
    public var volumeDebounce: Duration = .milliseconds(300)

    /// Bookmarks made on this Watch that the iPhone's list doesn't include yet.
    private var localBookmarks: [Bookmark]

    @ObservationIgnored private let transport: any ConnectivityTransport
    @ObservationIgnored private let clock: @MainActor () -> Date
    @ObservationIgnored private var queue: OfflineQueue
    @ObservationIgnored private let queueStore: JSONFileStore<OfflineQueue>?
    @ObservationIgnored private var awaitedCommand: Command?
    @ObservationIgnored private var volumeTask: Task<Void, Never>?

    /// - Parameters:
    ///   - queueStore: where the offline queue is saved, so queued bookmarks survive
    ///     the Watch app being quit. Nil keeps it in memory (tests).
    ///   - clock: injectable so tests can control time.
    public init(
        transport: any ConnectivityTransport,
        queueStore: JSONFileStore<OfflineQueue>? = nil,
        clock: @escaping @MainActor () -> Date = { .now }
    ) {
        let queue = (try? queueStore?.load()) ?? OfflineQueue()
        self.transport = transport
        self.queueStore = queueStore
        self.clock = clock
        self.queue = queue
        isReachable = transport.isReachable
        queuedCount = queue.pending.count
        localBookmarks = queue.pending.compactMap { Self.bookmark(in: $0) }
        transport.onReceive = { [weak self] message in
            self?.receive(message)
        }
        transport.onReachabilityChange = { [weak self] reachable in
            self?.reachabilityChanged(reachable)
        }
        flushQueue()
    }

    // MARK: Bookmarks

    /// The current episode's bookmarks, confirmed and pending, in playback order.
    public var bookmarkItems: [BookmarkItem] {
        guard let episodeID = displayState.episodeID else { return [] }
        let confirmed = bookmarkList?.episodeID == episodeID ? bookmarkList?.bookmarks ?? [] : []
        let confirmedIDs = Set(confirmed.map(\.id))
        let pending = localBookmarks.filter { $0.episodeID == episodeID && !confirmedIDs.contains($0.id) }
        let items = confirmed.map { BookmarkItem(bookmark: $0, isPending: false) }
            + pending.map { BookmarkItem(bookmark: $0, isPending: true) }
        return items.sorted { $0.bookmark.position < $1.bookmark.position }
    }

    /// Saves the moment the listener hears now. Works with the iPhone out of reach:
    /// the bookmark is queued and shown as pending. Returns nil when nothing is loaded.
    @discardableResult
    public func addBookmark() -> Task<Void, Never>? {
        guard let episodeID = displayState.episodeID else { return nil }
        let now = clock()
        let bookmark = Bookmark(
            episodeID: episodeID,
            position: displayState.estimatedPosition(at: now),
            createdAt: now,
            source: .watch
        )
        localBookmarks.append(bookmark)
        return send(.addBookmark(bookmark: bookmark))
    }

    // MARK: Sending

    /// Shows the expected result immediately, then sends the command: interactively
    /// when the iPhone is reachable, otherwise into the offline queue. The returned
    /// task finishes when that's done. The UI ignores it; tests await it.
    @discardableResult
    public func send(_ action: Command.Action) -> Task<Void, Never> {
        let command = Command(issuedAt: clock(), action: action)
        displayState = displayState.applying(command, at: command.issuedAt)
        guard transport.isReachable else {
            enqueue(command)
            return Task {}
        }
        awaitedCommand = command
        return Task {
            await deliver(command)
        }
    }

    /// Called on every crown tick. Updates the screen at once but sends one command
    /// after the crown rests for `volumeDebounce`.
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

    /// Sends a pending volume change now. Returns nil when nothing is pending.
    @discardableResult
    public func flushVolume() -> Task<Void, Never>? {
        guard let pending = volumeTask else { return nil }
        pending.cancel()
        volumeTask = nil
        return send(.setVolume(level: displayState.volume))
    }

    /// Hands queued commands to the guaranteed channel, oldest first. Stale playback
    /// commands are dropped first; bookmarks never are.
    public func flushQueue() {
        guard transport.isReachable, !queue.isEmpty else { return }
        queue.removeExpired(now: clock())
        var handedOver: [Command.ID] = []
        for command in queue.pending {
            do {
                try transport.transferGuaranteed(WireMessage(payload: .command(command), sentAt: clock()))
                handedOver.append(command.id)
            } catch {
                break
            }
        }
        queue.markDelivered(handedOver)
        saveQueue()
    }

    private func deliver(_ command: Command) async {
        do {
            try await transport.sendInteractive(WireMessage(payload: .command(command), sentAt: clock()))
        } catch {
            // The live send failed, so the command waits in the queue instead. The
            // iPhone drops it if the live send did arrive after all (same ID).
            if awaitedCommand?.id == command.id {
                awaitedCommand = nil
            }
            enqueue(command)
        }
    }

    private func enqueue(_ command: Command) {
        queue.enqueue(command)
        saveQueue()
    }

    private func saveQueue() {
        queuedCount = queue.pending.count
        try? queueStore?.save(queue)
    }

    private func reachabilityChanged(_ reachable: Bool) {
        isReachable = reachable
        if reachable {
            flushQueue()
        }
    }

    private static func bookmark(in command: Command) -> Bookmark? {
        switch command.action {
        case .addBookmark(let bookmark): return bookmark
        case .play, .pause, .skip, .seek, .setVolume: return nil
        }
    }

    // MARK: Receiving

    func receive(_ message: WireMessage) {
        switch message.payload {
        case .state(let state):
            receive(state)
        case .bookmarks(let list):
            bookmarkList = list
            let confirmedIDs = Set(list.bookmarks.map(\.id))
            localBookmarks.removeAll { confirmedIDs.contains($0.id) }
        case .command:
            break
        }
    }

    private func receive(_ state: PlaybackState) {
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
