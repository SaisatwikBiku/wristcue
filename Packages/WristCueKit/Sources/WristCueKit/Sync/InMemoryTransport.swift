import Foundation

/// A fake `ConnectivityTransport` that connects two endpoints in memory.
///
/// It copies WatchConnectivity's delivery rules closely enough for tests:
/// interactive messages fail when unreachable, latest values coalesce per kind, and
/// guaranteed transfers queue in order. One simplification: real application context
/// and user info transfers can arrive while `isReachable` is false (the system
/// delivers them in the background). Here they are held until the pair becomes
/// reachable, which is the worst case for the app's logic.
///
/// Every message goes through `MessageCodec`, so tests exercise the real encoding and
/// can read the byte size of everything sent.
@MainActor
public final class InMemoryTransport: ConnectivityTransport {
    public typealias Channel = TransportChannel

    /// One message handed to the transport, with its encoded size.
    public struct Record: Equatable, Sendable {
        public let channel: Channel
        public let message: WireMessage
        public let byteCount: Int
    }

    public private(set) var isReachable: Bool
    public var onReceive: (@MainActor (WireMessage) -> Void)?
    public var onReachabilityChange: (@MainActor (Bool) -> Void)?

    /// Everything this endpoint was asked to send, in order.
    public private(set) var sent: [Record] = []

    // Weak so the two endpoints don't keep each other alive forever.
    private weak var peer: InMemoryTransport?
    private var heldLatest: [WireMessage.Kind: Data] = [:]
    private var heldGuaranteed: [Data] = []
    private let codec = MessageCodec()

    private init(isReachable: Bool) {
        self.isReachable = isReachable
    }

    /// Creates two connected endpoints. The caller must keep both alive.
    public static func makePair(reachable: Bool = true) -> (phone: InMemoryTransport, watch: InMemoryTransport) {
        let phone = InMemoryTransport(isReachable: reachable)
        let watch = InMemoryTransport(isReachable: reachable)
        phone.peer = watch
        watch.peer = phone
        return (phone, watch)
    }

    /// Changes reachability for both ends, like walking away from the phone and back.
    public func setReachable(_ reachable: Bool) {
        let ends = [self, peer].compactMap { $0 }
        for end in ends where end.isReachable != reachable {
            end.isReachable = reachable
            end.onReachabilityChange?(reachable)
        }
        if reachable {
            ends.forEach { $0.flush() }
        }
    }

    public func sendInteractive(_ message: WireMessage) async throws {
        guard isReachable, let peer else { throw TransportError.notReachable }
        let data = try record(message, on: .interactive)
        peer.receive(data)
    }

    public func publishLatest(_ message: WireMessage) throws {
        heldLatest[message.kind] = try record(message, on: .latest)
        flush()
    }

    public func transferGuaranteed(_ message: WireMessage) throws {
        heldGuaranteed.append(try record(message, on: .guaranteed))
        flush()
    }

    private func record(_ message: WireMessage, on channel: Channel) throws -> Data {
        let data = try codec.encode(message)
        sent.append(Record(channel: channel, message: message, byteCount: data.count))
        return data
    }

    private func flush() {
        guard isReachable, let peer else { return }
        let latest = heldLatest.sorted { $0.key.rawValue < $1.key.rawValue }
        heldLatest.removeAll()
        let guaranteed = heldGuaranteed
        heldGuaranteed.removeAll()
        for (_, data) in latest {
            peer.receive(data)
        }
        for data in guaranteed {
            peer.receive(data)
        }
    }

    private func receive(_ data: Data) {
        // A message this build can't decode (for example a newer version) is dropped,
        // which is what the real transport does too.
        guard let message = try? codec.decode(data) else { return }
        onReceive?(message)
    }
}
