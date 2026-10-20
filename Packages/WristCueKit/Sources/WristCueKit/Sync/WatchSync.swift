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
    public let mode: SyncMode
    /// Optimized mode moves the progress bar locally between states. Naive mode
    /// shows the position of the last state that arrived.
    public var interpolatesProgress: Bool { mode != .naive }

    /// Bookmarks made on this Watch that the iPhone's list doesn't include yet.
    private var localBookmarks: [Bookmark]

    @ObservationIgnored private let transport: any ConnectivityTransport
    @ObservationIgnored private let clock: @MainActor () -> Date
    @ObservationIgnored private var queue: OfflineQueue
    @ObservationIgnored private let queueStore: JSONFileStore<OfflineQueue>?
    @ObservationIgnored private var awaitedCommand: Command?
    @ObservationIgnored private var volumeTask: Task<Void, Never>?
    /// The latest connect-time request, so tests can wait for it.
    @ObservationIgnored private(set) var requestTask: Task<Void, Never>?
    /// Callers of `sendAndMeasure` waiting for their command's acknowledgement.
    @ObservationIgnored private var waiters: [Command.ID: Waiter] = [:]

    private struct Waiter {
        let issuedAt: Date
        let continuation: CheckedContinuation<TimeInterval?, Never>
    }

    /// - Parameters:
    ///   - queueStore: where the offline queue is saved, so queued bookmarks survive
    ///     the Watch app being quit. Nil keeps it in memory (tests).
    ///   - clock: injectable so tests can control time.
    public init(
        transport: any ConnectivityTransport,
        queueStore: JSONFileStore<OfflineQueue>? = nil,
        mode: SyncMode = .optimized,
        clock: @escaping @MainActor () -> Date = { .now }
    ) {
        let queue = (try? queueStore?.load()) ?? OfflineQueue()
        self.transport = transport
        self.mode = mode
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
        send(Command(issuedAt: clock(), action: action))
    }

    @discardableResult
    private func send(_ command: Command) -> Task<Void, Never> {
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
    /// after the crown rests for `volumeDebounce`. Naive mode sends every tick and
    /// returns that send's task (tests await it); optimized mode returns nil.
    @discardableResult
    public func setVolume(_ level: Double) -> Task<Void, Never>? {
        guard level.isFinite else { return nil }
        displayState.volume = min(max(level, 0), 1)
        if mode == .naive {
            return send(.setVolume(level: displayState.volume))
        }
        volumeTask?.cancel()
        let delay = volumeDebounce
        volumeTask = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard let self, !Task.isCancelled else { return }
            volumeTask = nil
            send(.setVolume(level: displayState.volume))
        }
        return nil
    }

    /// Sends a pending volume change now. Returns nil when nothing is pending.
    @discardableResult
    public func flushVolume() -> Task<Void, Never>? {
        guard let pending = volumeTask else { return nil }
        pending.cancel()
        volumeTask = nil
        return send(.setVolume(level: displayState.volume))
    }

    // MARK: Measuring

    /// Sends a command and waits for the iPhone state that acknowledges it. Returns
    /// the round trip on this Watch's clock, or nil when no acknowledgement arrives
    /// within `timeout` (for example, the command went into the offline queue).
    public func sendAndMeasure(_ action: Command.Action, timeout: Duration = .seconds(3)) async -> TimeInterval? {
        let command = Command(issuedAt: clock(), action: action)
        return await withCheckedContinuation { continuation in
            waiters[command.id] = Waiter(issuedAt: command.issuedAt, continuation: continuation)
            send(command)
            Task { [weak self] in
                try? await Task.sleep(for: timeout)
                self?.resolveWaiter(command.id, roundTrip: nil)
            }
        }
    }

    /// Runs `count` measured volume commands one after another, alternating
    /// between the current volume and 5 points below it, so the listener barely
    /// hears it. Returns one entry per command, nil for a timeout.
    public func measureRoundTrips(count: Int, gap: Duration = .milliseconds(250)) async -> [TimeInterval?] {
        let base = displayState.volume
        var results: [TimeInterval?] = []
        for index in 0..<count {
            let level = index.isMultiple(of: 2) ? max(base - 0.05, 0) : base
            results.append(await sendAndMeasure(.setVolume(level: level)))
            if gap > .zero {
                try? await Task.sleep(for: gap)
            }
        }
        return results
    }

    private func resolveWaiter(_ id: Command.ID, roundTrip: TimeInterval?) {
        guard let waiter = waiters.removeValue(forKey: id) else { return }
        waiter.continuation.resume(returning: roundTrip)
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
            requestLatest()
        }
    }

    /// Asks the iPhone for its newest state and bookmark list, answered in the
    /// replies. Sent on every connect, so a Watch app opened after playback
    /// started shows the current state at once instead of waiting for the next
    /// change or for application context to arrive (docs/LEARNING.md, M5).
    private func requestLatest() {
        requestTask = Task {
            for kind in [WireMessage.Kind.state, .bookmarks] {
                try? await transport.sendInteractive(WireMessage(payload: .request(kind), sentAt: clock()))
            }
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
        case .command, .request:
            break
        }
    }

    private func receive(_ state: PlaybackState) {
        // Interactive replies and application context can arrive out of order.
        // An older snapshot never replaces a newer one.
        guard state.timestamp >= confirmedState.timestamp else { return }
        confirmedState = state

        if let id = state.lastCommandID, let waiter = waiters[id] {
            resolveWaiter(id, roundTrip: clock().timeIntervalSince(waiter.issuedAt))
        }

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
