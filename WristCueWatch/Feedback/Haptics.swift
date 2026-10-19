import WatchKit
import WristCueKit

/// One haptic per kind of action. Every haptic has a visible counterpart on screen
/// (the play icon flips, the time jumps, a status line appears), so the haptic is
/// never the only feedback. The Simulator doesn't play haptics at all.
enum Haptics {
    @MainActor
    static func play(for action: Command.Action) {
        let type: WKHapticType = switch action {
        case .play: .start
        case .pause: .stop
        case .skip, .seek, .setVolume: .click
        case .addBookmark: .success
        }
        WKInterfaceDevice.current().play(type)
    }

    @MainActor
    static func failure() {
        WKInterfaceDevice.current().play(.failure)
    }
}
