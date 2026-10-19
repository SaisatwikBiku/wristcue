/// The three WatchConnectivity channels, as `ConnectivityTransport` names them.
public enum TransportChannel: String, Sendable, CaseIterable, Codable {
    /// `sendMessage`
    case interactive
    /// `updateApplicationContext`
    case latest
    /// `transferUserInfo`
    case guaranteed
}
