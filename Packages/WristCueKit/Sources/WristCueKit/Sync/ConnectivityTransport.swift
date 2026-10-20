import Foundation

/// The three ways WristCue moves data between devices.
///
/// The app talks to this protocol, never to WCSession directly. The real
/// implementation wraps WatchConnectivity. `InMemoryTransport` is a fake with the
/// same delivery rules, so every piece of sync logic can be tested on a Mac with no
/// devices or simulators.
///
/// The protocol is `@MainActor`: every call and callback happens on the main thread.
/// WCSession calls its delegate on a background queue, so the real transport hops to
/// the main actor once, at the boundary, and nothing above it has to think about
/// threads.
@MainActor
public protocol ConnectivityTransport: AnyObject {
    /// True when the counterpart app is running and can take a live message right
    /// now. Maps to `WCSession.isReachable`.
    var isReachable: Bool { get }

    /// Called for every message that arrives, on any channel.
    var onReceive: (@MainActor (WireMessage) -> Void)? { get set }

    /// Called when `isReachable` changes.
    var onReachabilityChange: (@MainActor (Bool) -> Void)? { get set }

    /// Answers a live message. After `onReceive` has handled an interactive
    /// message, the transport asks this for a reply and sends it back in
    /// `sendMessage`'s reply handler. The sender's transport delivers the reply to
    /// its own `onReceive` before `sendInteractive` returns.
    var replyProvider: (@MainActor (WireMessage) -> WireMessage?)? { get set }

    /// Interactive channel, `WCSession.sendMessage`. Fastest path, only works while
    /// the counterpart is reachable, and throws otherwise. Used for taps on the Watch
    /// (play, skip) when someone is waiting to hear the result.
    func sendInteractive(_ message: WireMessage) async throws

    /// Latest-value channel, `WCSession.updateApplicationContext`. Each new value per
    /// `WireMessage.Kind` replaces the previous one, and the system delivers only the
    /// newest when it gets a chance. Used for playback state and the bookmark list,
    /// where an old value is worthless once a newer one exists.
    func publishLatest(_ message: WireMessage) throws

    /// Guaranteed channel, `WCSession.transferUserInfo`. Queued by the system,
    /// delivered in order, and survives the sender's app quitting. Used for commands
    /// and bookmarks made while the counterpart was unreachable.
    func transferGuaranteed(_ message: WireMessage) throws
}

public enum TransportError: Error, Equatable, Sendable {
    case notReachable
}
