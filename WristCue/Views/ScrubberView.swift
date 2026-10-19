import SwiftUI
import WristCueKit

/// Progress bar and times. The model publishes state only on changes, so this
/// view computes the moving position itself from the last state.
struct ScrubberView: View {
    @Environment(PlayerModel.self) private var player
    /// Non-nil while the listener drags, so the thumb follows the finger instead
    /// of the playhead.
    @State private var dragPosition: TimeInterval?

    var body: some View {
        let state = player.state
        // An animation schedule paused while nothing moves: no redraws at all
        // when playback is paused or the listener is dragging.
        TimelineView(.animation(minimumInterval: 0.5, paused: !state.isPlaying || dragPosition != nil)) { context in
            let position = dragPosition ?? state.estimatedPosition(at: context.date)
            VStack(spacing: 4) {
                Slider(
                    value: Binding(get: { position }, set: { dragPosition = $0 }),
                    in: 0...max(state.duration, 1),
                    onEditingChanged: { isEditing in
                        if !isEditing, let target = dragPosition {
                            player.send(.seek(to: target))
                            dragPosition = nil
                        }
                    }
                )
                .accessibilityLabel("Playback position")
                .accessibilityValue("\(TimeFormat.spoken(position)) of \(TimeFormat.spoken(state.duration))")

                HStack {
                    Text(TimeFormat.clock(position))
                    Spacer()
                    Text("-\(TimeFormat.clock(state.duration - position))")
                }
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                // The slider's accessibility value already says this.
                .accessibilityHidden(true)
            }
        }
    }
}
