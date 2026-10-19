import SwiftUI
import WidgetKit

/// A watch face complication that opens WristCue.
///
/// It shows no playback data on purpose. The complication runs in its own
/// extension process, and the only way to hand it the Watch app's state is a
/// shared App Group container. App Groups weren't verified to work with free
/// signing here, so the complication is a launcher: one tap from the watch face
/// to the remote. Tapping any WidgetKit complication opens its app.
@main
struct WristCueComplication: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "WristCueLauncher", provider: LauncherProvider()) { _ in
            LauncherView()
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("WristCue")
        .description("Opens the WristCue remote.")
        .supportedFamilies([.accessoryCircular, .accessoryCorner, .accessoryRectangular, .accessoryInline])
    }
}

struct LauncherEntry: TimelineEntry {
    let date: Date
}

/// One entry that never changes, so the system never wakes the extension to
/// refresh it.
struct LauncherProvider: TimelineProvider {
    func placeholder(in context: Context) -> LauncherEntry {
        LauncherEntry(date: .now)
    }

    func getSnapshot(in context: Context, completion: @escaping (LauncherEntry) -> Void) {
        completion(LauncherEntry(date: .now))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<LauncherEntry>) -> Void) {
        completion(Timeline(entries: [LauncherEntry(date: .now)], policy: .never))
    }
}

struct LauncherView: View {
    @Environment(\.widgetFamily) private var family

    var body: some View {
        switch family {
        case .accessoryInline:
            Label("WristCue", systemImage: "headphones")
        case .accessoryRectangular:
            VStack(alignment: .leading) {
                Label("WristCue", systemImage: "headphones")
                    .font(.headline)
                Text("Open the remote")
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        case .accessoryCorner:
            Image(systemName: "headphones")
                .font(.title3)
                .widgetLabel("WristCue")
                .accessibilityLabel("WristCue")
        default:
            ZStack {
                AccessoryWidgetBackground()
                Image(systemName: "headphones")
                    .font(.title3)
            }
            .accessibilityLabel("WristCue")
        }
    }
}
