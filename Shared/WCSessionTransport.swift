import Foundation
import os
import WatchConnectivity
import WristCueKit

/// `ConnectivityTransport` on top of WCSession. Compiled into both apps.
///
/// It only moves bytes. Every decision about what to send and when lives in the
/// kit's `PhoneSync` and `WatchSync`, which are tested without devices. This file
/// is kept small because the Simulator is the only place it can be exercised.
///
/// Threading: WCSession calls its delegate on a background queue. Each delegate
/// method decodes there (the codec is Sendable), then hops to the main queue with
/// `DispatchQueue.main.async`. A serial queue keeps arrival order, which matters
/// for user info transfers. `Task { @MainActor in }` doesn't promise ordering.
@MainActor
final class WCSessionTransport: NSObject, ConnectivityTransport {
    private(set) var isReachable = false
    var onReceive: (@MainActor (WireMessage) -> Void)?
    var onReachabilityChange: (@MainActor (Bool) -> Void)?

    private let session: WCSession?
    /// One application-context slot per message kind. updateApplicationContext
    /// replaces the whole dictionary, so every slot is sent each time.
    private var latestContext: [String: Data] = [:]
    /// Transfers requested before activation finished.
    private var pendingTransfers: [[String: Any]] = []
    nonisolated private let codec = MessageCodec()
    nonisolated private let log = Logger(subsystem: "info.satwik.wristcue", category: "connectivity")

    /// `nil` session on devices without WatchConnectivity (iPad), where every send
    /// reports the counterpart as unreachable.
    init(session: WCSession? = WCSession.isSupported() ? WCSession.default : nil) {
        self.session = session
        super.init()
        session?.delegate = self
        session?.activate()
    }

    // MARK: ConnectivityTransport

    /// `sendMessage` with a reply handler: the await finishes when the other side's
    /// delegate has received it, or throws when delivery fails.
    func sendInteractive(_ message: WireMessage) async throws {
        guard let session, session.activationState == .activated, session.isReachable else {
            throw TransportError.notReachable
        }
        let payload = try codec.dictionary(for: message)
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
            session.sendMessage(payload, replyHandler: { _ in
                continuation.resume()
            }, errorHandler: { error in
                continuation.resume(throwing: error)
            })
        }
    }

    func publishLatest(_ message: WireMessage) throws {
        latestContext[message.kind.rawValue] = try codec.encode(message)
        try pushContext()
    }

    func transferGuaranteed(_ message: WireMessage) throws {
        pendingTransfers.append(try codec.dictionary(for: message))
        flushTransfers()
    }

    // MARK: Main-actor helpers

    private func pushContext() throws {
        guard let session, session.activationState == .activated, !latestContext.isEmpty else { return }
        try session.updateApplicationContext(latestContext)
    }

    private func flushTransfers() {
        guard let session, session.activationState == .activated else { return }
        for userInfo in pendingTransfers {
            _ = session.transferUserInfo(userInfo)
        }
        pendingTransfers.removeAll()
    }

    private func setReachable(_ reachable: Bool) {
        guard reachable != isReachable else { return }
        isReachable = reachable
        onReachabilityChange?(reachable)
    }

    private func didActivate(reachable: Bool, received: [WireMessage]) {
        setReachable(reachable)
        for message in received {
            onReceive?(message)
        }
        do {
            try pushContext()
        } catch {
            log.error("Couldn't publish application context after activation: \(error.localizedDescription)")
        }
        flushTransfers()
    }

    // MARK: Decoding, off the main thread

    nonisolated private func decode(_ dictionary: [String: Any]) -> [WireMessage] {
        do {
            return [try codec.message(from: dictionary)]
        } catch {
            log.error("Dropped a message that didn't decode: \(error.localizedDescription)")
            return []
        }
    }

    nonisolated private func decodeContext(_ context: [String: Any]) -> [WireMessage] {
        context.values
            .compactMap { value in (value as? Data).flatMap { try? codec.decode($0) } }
            .sorted { $0.sentAt < $1.sentAt }
    }

    nonisolated private func deliver(_ messages: [WireMessage]) {
        guard !messages.isEmpty else { return }
        DispatchQueue.main.async {
            MainActor.assumeIsolated {
                for message in messages {
                    self.onReceive?(message)
                }
            }
        }
    }
}

extension WCSessionTransport: WCSessionDelegate {
    nonisolated func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: (any Error)?
    ) {
        if let error {
            log.error("WCSession activation failed: \(error.localizedDescription)")
        }
        let reachable = session.isReachable
        // Whatever the counterpart published while this app wasn't running.
        let received = decodeContext(session.receivedApplicationContext)
        DispatchQueue.main.async {
            MainActor.assumeIsolated {
                self.didActivate(reachable: reachable, received: received)
            }
        }
    }

    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        let reachable = session.isReachable
        DispatchQueue.main.async {
            MainActor.assumeIsolated {
                self.setReachable(reachable)
            }
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        deliver(decode(message))
    }

    nonisolated func session(
        _ session: WCSession,
        didReceiveMessage message: [String: Any],
        replyHandler: @escaping ([String: Any]) -> Void
    ) {
        // An empty reply is the acknowledgement that completes the sender's await.
        replyHandler([:])
        deliver(decode(message))
    }

    nonisolated func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        deliver(decodeContext(applicationContext))
    }

    nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any]) {
        deliver(decode(userInfo))
    }

    #if os(iOS)
    // Required on iOS, where a user can switch between paired watches.
    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}

    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        session.activate()
    }
    #endif
}
