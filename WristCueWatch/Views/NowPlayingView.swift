import SwiftUI
import WristCueKit

/// The Watch's main screen: what's playing, where it is, and the controls.
struct NowPlayingView: View {
    @Environment(WatchSync.self) private var sync
    @Environment(\.isLuminanceReduced) private var isLuminanceReduced
    @Environment(\.scenePhase) private var scenePhase
    /// The crown's value. Kept in step with the iPhone's volume in both directions.
    @State private var crownVolume = 1.0

    var body: some View {
        let state = sync.displayState
        VStack(spacing: 6) {
            Text(title)
                .font(.headline)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .accessibilityAddTraits(.isHeader)

            ProgressRow(
                state: state,
                interpolates: sync.interpolatesProgress,
                isLuminanceReduced: isLuminanceReduced,
                isInBackground: scenePhase == .background
            )

            TransportButtons()

            BookmarkButton()

            HStack {
                VolumeLabel(volume: state.volume)
                Spacer(minLength: 4)
                StatusLine(isReachable: sync.isReachable, queuedCount: sync.queuedCount)
            }
        }
        .padding(.horizontal, 4)
        // The crown needs a focused view to send rotation to.
        .focusable()
        .digitalCrownRotation(
            $crownVolume,
            from: 0,
            through: 1,
            by: 0.05,
            sensitivity: .low,
            isContinuous: false,
            isHapticFeedbackEnabled: true
        )
        .onChange(of: crownVolume) { _, newValue in
            // Ignore the echo when the iPhone's volume moved the crown value.
            if abs(newValue - sync.displayState.volume) > 0.001 {
                sync.setVolume(newValue)
            }
        }
        .onChange(of: sync.displayState.volume) { _, newValue in
            crownVolume = newValue
        }
        .onChange(of: sync.queuedCount) { old, new in
            // Something couldn't go live and is waiting for the iPhone.
            if new > old {
                Haptics.queued()
            }
        }
        .toolbar {
            #if DEBUG
            ToolbarItem(placement: .topBarLeading) {
                NavigationLink {
                    DiagnosticsView()
                } label: {
                    Image(systemName: "gauge.with.dots.needle.33percent")
                }
                .accessibilityLabel("Diagnostics")
            }
            #endif
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink {
                    WatchBookmarksView()
                } label: {
                    Image(systemName: "list.bullet")
                }
                .accessibilityLabel("Bookmarks")
            }
        }
    }

    private var title: String {
        sync.displayState.episodeID.flatMap(Episode.withID)?.title ?? "Nothing playing"
    }
}

/// Shows why a control might not work. Text, not only a haptic, so the state is
/// visible with the sound off and readable by VoiceOver.
private struct StatusLine: View {
    let isReachable: Bool
    let queuedCount: Int

    var body: some View {
        if queuedCount > 0 {
            Label("\(queuedCount) waiting", systemImage: "clock.arrow.circlepath")
                .font(.footnote)
                .foregroundStyle(.orange)
                .accessibilityLabel("\(queuedCount) waiting for iPhone")
        } else if !isReachable {
            Label("No iPhone", systemImage: "iphone.slash")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .accessibilityLabel("iPhone not reachable")
        }
    }
}

private struct VolumeLabel: View {
    let volume: Double

    var body: some View {
        Label(volume.formatted(.percent.precision(.fractionLength(0))), systemImage: "speaker.wave.2.fill")
            .font(.footnote.monospacedDigit())
            .foregroundStyle(.secondary)
            .accessibilityLabel("Volume")
            .accessibilityValue(volume.formatted(.percent.precision(.fractionLength(0))))
            .accessibilityHint("Turn the Digital Crown to change")
    }
}
