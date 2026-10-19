# Learning notes

The concepts behind each part of WristCue, written so you can explain them in an interview. Comparisons point at Java, C++, Python and JavaScript where that helps. Sections are added as each milestone lands.

## M1: WristCueKit

### Why a separate package

`WristCueKit` is a Swift package that both apps link. It holds everything that isn't UI or a device API: models, the wire format, and the sync rules. It imports only Foundation, so its tests run on a Mac in seconds with no simulator, and CI can run them on every push. The WatchConnectivity wrapper arrives in M3 as a thin layer on top.

Rejected alternative: putting models in each app target and keeping them in sync by hand. Two copies of the wire format are the classic way for an iPhone and a Watch app to disagree.

### Value types: struct vs. class

`Episode`, `PlaybackState`, `Bookmark`, `Command` and `WireMessage` are structs. A struct is copied on assignment, like a C++ object held by value and unlike a Java object, which is always a reference. Two consequences:

- No one can change a `PlaybackState` you're holding. If the iPhone builds a new state, your copy is untouched.
- A struct whose fields are all value types is automatically safe to share between threads, so it can be marked `Sendable` with no locks.

Swift arrays and dictionaries are also values, with copy-on-write: the copy is cheap until someone mutates it.

`InMemoryTransport` is a class because it has identity: two endpoints point at each other, and callbacks are attached to a specific endpoint.

### Enums with associated values

`Command.Action` is a sum type:

```swift
enum Action {
    case play
    case skip(seconds: TimeInterval)
    case addBookmark(bookmark: Bookmark)
}
```

Each case carries only its own data, and a `switch` that misses a case doesn't compile. In Java you'd write a sealed interface with a record per case. In TypeScript, a discriminated union. The compiler check matters here: when a new command is added, every place that handles commands (the iPhone executor, the queue's coalescing rules, the tests) fails to build until it's handled.

### Codable, and why WireMessage writes its own

`Codable` is a protocol the compiler can implement for you: if every field is Codable, it generates `encode(to:)` and `init(from:)`. That's what `PlaybackState`, `Bookmark` and `Command` use.

`WireMessage` implements it by hand for two reasons:

1. It decodes `version` first and rejects a version it doesn't support before touching the body. The Watch app can update independently of the iPhone app, so for a while one side may be newer. Failing with `WireError.unsupportedVersion(2)` is better than misreading a body whose shape changed.
2. The default encoding of an enum with associated values is nested and noisy. The hand-written version produces a flat `{"version", "kind", "sentAt", "body"}` shape that's easy to read in logs.

Versioning rule: adding an optional field needs no version bump, because `JSONDecoder` ignores unknown keys (there's a test for this). A breaking change bumps `currentVersion`.

Rejected alternatives: Protocol Buffers (a third-party dependency, and the payloads are small enough that JSON's overhead gets measured in M5 rather than assumed), and hand-built `[String: Any]` dictionaries (no compiler checking and easy to mistype a key).

### Why JSON inside a dictionary

WatchConnectivity accepts only property-list dictionaries. `MessageCodec` puts the whole JSON-encoded message under a single key, `"m"`. One encoder handles every message type, and the dictionary layer stays trivial. M5 measures the encoded sizes, and compares against a binary property list, so the choice rests on a number.

### Swift 6 and Sendable

The package uses tools version 6.0, which turns on the Swift 6 language mode. In that mode the compiler rejects code that could race: you can't pass a non-`Sendable` value between concurrency domains, and you can't touch main-actor state from a background thread without an `await`. A Java data race shows up at runtime, if you're lucky. Here it's a build error.

`@MainActor` marks code that must run on the main thread. `ConnectivityTransport` is a `@MainActor` protocol, so every call and callback happens there. WCSession calls its delegate on a background queue. The real transport (M3) hops to the main actor once, at that boundary, and nothing above it has to think about threads.

One quirk shows up in the tests. A `@MainActor` closure type is treated as `Sendable`, and a `Sendable` closure may not mutate a captured local `var`. The tests collect callback values in a small `@MainActor` class (`Recorder`) instead. They also copy main-actor values into locals before calling `XCTAssertEqual`, because XCTest's autoclosures aren't main-actor isolated.

### Progress interpolation

The Watch doesn't receive a position every second. It receives a `PlaybackState`: position, rate, isPlaying, and the time those were sampled. It then computes:

```
position(now) = position + (now - timestamp) * rate      (only while playing)
```

and clamps the result to the episode. This is the same idea as dead reckoning in games, or how `MPNowPlayingInfoCenter` works: the system stores elapsed time and rate, and animates the lock-screen bar itself.

Edge cases, each covered by a test: paused or rate 0 means no movement, a Watch clock behind the iPhone's never moves the bar backwards, the position stops at the duration, and an unknown duration (0) only clamps at zero.

Clock skew trade-off: `timestamp` is on the iPhone's clock and `now` on the Watch's. Paired devices both sync to network time, and paired simulators share the Mac's clock, so the error is small. The alternative is to stamp states with the Watch's receive time, which adds transport delay to every estimate instead. The heartbeat in M5 bounds drift either way.

### One pure function for commands

`PlaybackState.applying(_:at:)` returns the state a command should produce. It has no side effects and reads no clock (time is a parameter), so it's trivial to test. Both devices use it:

- The iPhone uses it to compute clamped targets before driving AVFoundation.
- The Watch uses it for optimistic UI. The screen updates the instant you tap, then the iPhone's real state replaces the guess.

A detail worth defending: it folds elapsed playback into the position before applying the command, so "skip 30" means 30 seconds from what the listener hears now, not from the last snapshot.

### The offline queue

When the iPhone is unreachable, the Watch keeps commands in an `OfflineQueue`, a Codable value type with no I/O. Bookmarks are `addBookmark` commands, so one queue covers both. Its rules:

- First in, first out.
- De-duplication by command ID, across both pending and recently settled IDs. A command can arrive twice when an interactive send times out after it was actually delivered and the Watch falls back to a guaranteed transfer.
- Coalescing: only the newest volume, play/pause or seek is kept. Ten crown turns made offline become one command. Skips aren't coalesced (they add up) and neither are bookmarks (each is a separate moment).
- Expiry: playback commands older than 30 seconds are dropped. Bookmarks never expire. The 30 seconds is a design choice, not a measurement. A skip that lands half a minute after the tap is more confusing than one that never happens.

`RecentIDs` bounds the de-duplication memory to the last 256 IDs, using an array for eviction order and a `Set` for O(1) lookup, the same pairing as a Java `LinkedHashSet`.

The receiving iPhone de-duplicates again by bookmark ID (M4), so a duplicate that slips past the Watch still can't create a second bookmark.

### Choosing the WatchConnectivity channel

`ConnectivityTransport` names the three channels by what they guarantee:

| Method | WCSession API | Guarantee | Used for |
|---|---|---|---|
| `sendInteractive` | `sendMessage` | Immediate, only while reachable, fails otherwise | Taps on the Watch when the iPhone is reachable |
| `publishLatest` | `updateApplicationContext` | Only the newest value is kept and delivered | Playback state, bookmark list |
| `transferGuaranteed` | `transferUserInfo` | Queued, ordered, survives app exit | Commands and bookmarks made while unreachable |

Application context holds one dictionary. `publishLatest` keeps one slot per message kind, so a new state doesn't erase the bookmark list.

`InMemoryTransport` implements the same rules in memory. One deliberate simplification: real context and user-info transfers can arrive in the background while `isReachable` is false. The fake holds them until the pair is reachable, which is the harder case for the app logic.

### Testing approach

XCTest, with `@testable import` so tests can see `internal` members such as `coalescingGroup`. Test data lives in `Fixture`: dates are whole seconds so they survive JSON exactly, and UUIDs are readable (`...000000000007`) so a failing assertion names the command.

## M2: iPhone playback and Now Playing

### Generating the project with XcodeGen

`project.yml` describes the targets, settings and the local package in about 50 lines. `xcodegen generate` writes `WristCue.xcodeproj` from it. A hand-edited `.pbxproj` is thousands of lines of generated IDs that merge badly and break easily in a diff. The generated project is committed anyway, so the repo opens in Xcode without XcodeGen installed.

Rejected alternative: Tuist. It does more (caching, module graphs), but it's a larger tool than a three-target project needs.

Signing is set to `CODE_SIGN_IDENTITY = "-"`, which Xcode shows as "Sign to Run Locally". The Simulator accepts it, and it needs no Apple Developer account.

### Synthetic audio

The four episodes are text in `scripts/episodes/`, spoken by the macOS `say` command with the Samantha voice and saved as AAC in `.m4a` files. `scripts/make-audio.sh` prints each file's duration (from `afinfo`) and size, and those printed values are the only source for audio numbers in the docs.

### AVAudioSession

An iOS app doesn't own the speaker. It asks for a role through `AVAudioSession`:

- Category `.playback`: audio keeps playing with the silent switch on and in the background. Together with `UIBackgroundModes: audio` in Info.plist, this is what keeps playback going when the screen locks.
- Mode `.spokenAudio`: tells the system this is speech. When another app speaks (turn-by-turn directions, for example), the system pauses this app instead of lowering its volume, so you don't miss words.

`PlayerModel` also listens for two notifications. An interruption (phone call, alarm) pauses playback, and playback resumes afterwards only if the system says it should. A route change with reason `.oldDeviceUnavailable` means headphones were unplugged, and the app pauses so audio doesn't suddenly come out of the speaker.

### AVAudioPlayer vs. AVPlayer

`EpisodePlayer` wraps `AVAudioPlayer`. For short local files it's the simpler API: `currentTime`, `duration` and `isPlaying` are plain properties you read synchronously. `AVPlayer` is built for streaming and video. You observe it with key-value observing and periodic time observers, which is more machinery than bundled files need. If WristCue streamed real podcast feeds, `AVPlayer` would be the right choice.

### One entry point for every control

The app's buttons, the Lock Screen controls and (from M3) the Watch all end up in `PlayerModel.perform(_ command:)`:

1. Read the player's real state with `snapshot`.
2. Ask the kit for the target: `current.applying(command, at: now)`.
3. Change only what differs: seek, volume, play or pause.
4. Read the player again and publish that state.

The target computation is the tested pure function from M1. The last step publishes what the player actually did, not what was requested. If AVFoundation refuses to play, the state says so.

### Now Playing and remote commands

`MPNowPlayingInfoCenter` takes a dictionary: title, duration, elapsed time and playback rate. The system then animates the Lock Screen progress bar on its own, from elapsed time and rate. That's the same interpolation the WristCue Watch app does, and it's why `NowPlayingController.update` only runs when the state changes.

`MPRemoteCommandCenter` delivers play, pause, toggle, skip and scrub from the Lock Screen, Control Center, headphones and the Watch's built-in Now Playing app. Each handler converts the system event into a `Command.Action`. Next and previous track are disabled because there's no queue.

A Swift 6 detail: MediaPlayer doesn't say which thread calls the handlers. A closure written inside a `@MainActor` type is assumed to run on the main actor, and Swift 6 inserts a runtime check that crashes if it doesn't. So the handlers are marked `@Sendable` (no isolation assumed). They read the event immediately, then hop to the main actor with `Task { @MainActor in ... }`. `AVAudioPlayerDelegate` gets the same treatment, as a `nonisolated` method that hops to the main actor. The audio session observers use `queue: .main` plus `MainActor.assumeIsolated`, which asserts that the main-thread guarantee holds.

### Observation and the environment

`PlayerModel` is `@Observable` (iOS 17). SwiftUI records which properties each view's `body` reads and redraws only the views that read a property that changed. With the older `ObservableObject`, any `@Published` change redraws every observing view. Views get the model with `@Environment(PlayerModel.self)` instead of being passed it through every initializer. Properties that views never read (the player, loggers) are `@ObservationIgnored`.

### Drawing progress without a timer in the model

`ScrubberView` uses `TimelineView(.animation(minimumInterval: 0.5, paused: ...))`. While playing, it redraws at most twice a second, computing the position from `state.estimatedPosition(at: context.date)`. While paused or while the listener drags, the schedule is paused and nothing redraws. The model never ticks.

### Accessibility from the start

Every button has a VoiceOver label. Icon sizes use `@ScaledMetric`, so they grow with Dynamic Type. The slider's accessibility value is spoken text ("1 minute, 5 seconds of 2 minutes"), produced by `TimeFormat.spoken`, because VoiceOver reads "1:05" as "one colon zero five". The M6 milestone audits this across both apps.

### What the Simulator can't show

On the iOS 27.0 Simulator, the Lock Screen and Control Center didn't display WristCue's Now Playing panel during M2 testing. That's a limit on what can be verified, not proof that the integration works or fails. Debug builds therefore include `NowPlayingDebugView`, which reads `MPNowPlayingInfoCenter.default().nowPlayingInfo` back and shows the title, elapsed time, duration and rate the app last published. It confirms the app's side: the dictionary is set, and it changes on play, pause and seek. It doesn't confirm that the system renders the dictionary or delivers remote commands. That needs a real iPhone, or a Simulator runtime that draws the panel.

## M3: Watch Now Playing and WatchConnectivity

### Three layers

1. `WCSessionTransport` (in `Shared/`, compiled into both apps) only moves bytes over WCSession.
2. `PhoneSync` and `WatchSync` (in the kit) decide what to send and when. They talk to a `ConnectivityTransport`, so the tests in `SyncTests.swift` run them over `InMemoryTransport` with a fake player and a fake clock.
3. The SwiftUI views read `WatchSync` and call `send(_:)`.

The transport is in `Shared/` rather than the kit because WatchConnectivity doesn't exist on macOS, and the kit's tests run on macOS. A second package product would have changed the Xcode scheme names the test commands rely on.

Rejected alternative: letting the views talk to WCSession directly. That's the usual sample-code shape, and it makes the sync logic untestable without two simulators.

### Which channel carries what

| Data | Channel | Why |
|---|---|---|
| Watch tap (play, skip, volume) | `sendMessage` with a reply handler | Someone is waiting for the result, and the counterpart is reachable. The reply is the delivery acknowledgement that ends the sender's `await`. |
| iPhone playback state | `updateApplicationContext` | Only the newest state matters. The system keeps one value and delivers it when the Watch app runs, even if it wasn't running when the state changed. |
| Commands and bookmarks made offline (M4) | `transferUserInfo` | Every item must arrive, in order. |

`WCSessionTransport` keeps one application-context slot per message kind, because `updateApplicationContext` replaces the whole dictionary. On activation it reads `receivedApplicationContext`, so a Watch app that launches cold shows the last state right away instead of a spinner.

### Optimistic UI and acknowledgement

`WatchSync` keeps two states. `confirmedState` is the newest one the iPhone published. `displayState` is what the screen shows. A tap changes `displayState` immediately, using the same `applying(_:at:)` reducer the iPhone uses. Then:

- If the iPhone's next state carries this command's ID in `lastCommandID`, the guess is replaced by the real state. The time between the tap and that state is `lastRoundTrip`, which M5 uses to measure latency on the Watch's own clock.
- If a state arrives that predates the tap (no matching ID) within 2 seconds, the guess stays on screen.
- After 2 seconds without an acknowledgement, the iPhone's state wins again.
- If sending fails, the command goes into the offline queue (M4). Before M4 the screen fell back to `confirmedState` instead.

States are also ordered by timestamp. An older snapshot never replaces a newer one, because interactive replies and application context can arrive out of order.

### Idempotent commands

`PhoneSync` remembers the last 256 command IDs and runs each ID at most once. In M4 the same command can arrive by two routes (an interactive send that timed out after delivery, then a guaranteed retry). De-duplicating on the receiver means a retry never skips 30 seconds twice.

### Threading at the WCSession boundary

WCSession calls delegate methods on a background queue. Each `nonisolated` delegate method decodes the dictionary there (the codec is `Sendable`), then hops with `DispatchQueue.main.async` plus `MainActor.assumeIsolated`. A serial queue keeps the arrival order. `Task { @MainActor in }` doesn't guarantee that two tasks run in the order they were created, which would matter for ordered user info transfers.

`sendMessage` takes callbacks. `withCheckedThrowingContinuation` turns it into `async throws`, so callers can write `try await transport.sendInteractive(...)`.

### Digital Crown volume

`.digitalCrownRotation` binds the crown to a `Double` from 0 to 1 in steps of 0.05, with the system's detent haptics. Each tick updates the screen at once through `WatchSync.setVolume`. The command waits until the crown has rested for 300 ms, and each new tick cancels the previous wait. One turn of the crown is then one message. The 300 ms is a design choice, not a measurement.

Two `onChange` handlers keep the crown and the iPhone's volume in step, and a 0.001 tolerance stops the echo (the iPhone's volume moves the crown, which would otherwise send the same volume back).

### Spending less power when nobody's looking

`ProgressRow` reads `isLuminanceReduced` and `scenePhase`:

- screen awake and playing: redraws at most once a second;
- wrist down (always-on display): once a minute, showing "N min left" instead of seconds that would be stale for most of the minute;
- paused or in the background: the timeline is paused, so nothing redraws.

None of this needs a message from the iPhone. The position comes from interpolating the last state.

### Single-target watchOS app

The Watch app is one target with `WKApplication: true` and `WKCompanionAppBundleIdentifier` pointing at the iPhone app. That's the structure since watchOS 7. There's no separate WatchKit extension. The iPhone app embeds it at `WristCue.app/Watch`. Its bundle ID must start with the iPhone app's ID, and WatchConnectivity only connects an app to its companion.

### A Swift 6 crash found in the Simulator

The first run of M3 crashed the Watch app ("WristCueWatch quit unexpectedly") the first time a command's reply came back. The crash report showed:

```
Thread 1 Crashed:: Dispatch queue: NSOperationQueue 0x103782400 (QOS: UTILITY)
0 libdispatch.dylib          _dispatch_assert_queue_fail
3 libswift_Concurrency.dylib _swift_task_checkIsolatedSwift
5 WristCueWatch.debug.dylib  closure #1 in closure #1 in WCSessionTransport.sendInteractive(_:)
7 WatchConnectivity          -[WCSession onqueue_handleResponseDictionary:record:withPairingID:]_block_invoke
```

The `replyHandler` passed to `WCSession.sendMessage` was written inside a `@MainActor` class, so Swift 6 inferred it as main-actor isolated and inserted a runtime check (`_swift_task_checkIsolatedSwift`, which calls `dispatch_assert_queue`). WatchConnectivity calls the handler on a background `NSOperationQueue`, so the check failed and trapped. Frame 7 also shows the iPhone had received the command and replied: the round trip itself worked.

The fix marks the reply and error handlers `@Sendable`, which drops the inferred isolation. They only resume a continuation, which is safe from any thread.

The rule to remember: any callback handed to an Objective-C framework from main-actor code must be `@Sendable` (or `nonisolated`) unless the framework documents that it calls back on the main thread. The same rule is why the remote-command handlers and the WCSession delegate methods in this project are written that way.

## M4: Bookmarks and the offline queue

### One queue for commands and bookmarks

A bookmark travels as an `addBookmark` command, so the Watch has one `OfflineQueue` instead of two. A command goes into the queue when the iPhone isn't reachable at tap time, or when a live `sendMessage` fails. When `isReachable` turns true, `WatchSync.flushQueue()` drops stale playback commands, then hands the rest to `transferUserInfo` oldest first.

The queue holds items on the Watch until the iPhone is reachable, rather than handing them to `transferUserInfo` at once. `transferUserInfo` would deliver them too, but once an item is handed over the app can't change it. Holding them keeps two rules possible:

- Coalescing: five volume changes made offline become one.
- Expiry: a skip or pause older than 30 seconds is dropped, because one that lands much later is more confusing than one that never happens. Bookmarks never expire. The 30 seconds is a design choice, not a measurement.

The cost is that items wait for the Watch app to run while the iPhone is reachable, instead of the system delivering them in the background.

### Surviving a quit

The queue is saved to `offline-queue.json` in the Watch app's Application Support folder after every change, through `JSONFileStore`. It's a few kilobytes at most, so the whole file is rewritten each time with an atomic write (a temporary file, then a rename). A crash mid-write leaves the previous file. A database would be more code for no gain at this size.

The iPhone stores bookmarks the same way, in `bookmarks.json`. `BookmarkStore` keeps the list in memory and counts failed saves instead of throwing, so a full disk never loses the bookmarks of the current session.

### Idempotent bookmarks

Every bookmark gets its UUID on the device that makes it, before it's sent. The same bookmark can arrive twice: a live send whose reply was lost, then the queued copy. Two layers make that harmless. `PhoneSync` drops a command ID it has already run, and `BookmarkStore.add` ignores an ID it already has.

### Pending and confirmed

The iPhone is the single source of truth for bookmarks. It publishes the current episode's list in its own application-context slot, separate from playback state, and only when the list changes. The Watch shows that list plus its own bookmarks the list doesn't contain yet, marked with a clock icon. When a new list arrives, any local bookmark it includes stops being pending.

A Watch bookmark records `estimatedPosition(at:)`, the interpolated position, not the last published one. The iPhone publishes only on changes, so the last published position can be a minute old during steady playback.

### Feedback when offline

A tap that reaches the iPhone plays its usual haptic. A tap that goes into the queue plays the retry haptic instead, and the status line shows "N waiting" until the queue drains. Each is visible on screen as well, because the Simulator plays no haptics and some people turn them off.

### iCloud and code signing

The first M4 Watch build compiled and then failed at the last step:

```
WristCueWatch.app: resource fork, Finder information, or similar detritus not allowed
Command CodeSign failed with a nonzero exit code
```

The repository lives on the Desktop, which syncs to iCloud. iCloud adds extended attributes to new files, and `codesign` refuses a bundle that carries them. The M3 build in the same folder had signed because iCloud hadn't reached it yet, so the failure looked random. Building into `~/Library/Developer/WristCueBuild`, which iCloud doesn't sync, fixed it. The kit's `swift test` failure in M1 had the same cause.

## M5: Naive vs. optimized sync

### Why build the naive version at all

A claim like "publishing on change saves messages" means little without the thing it saves against. `SyncMode.naive` is the version most first attempts look like: stream the position every second as a live message, draw whatever arrived, send every crown detent. Both modes live in the same build and are picked with a launch argument, so one install measures both and nothing else differs between the runs.

The command path is identical in both modes on purpose. A latency comparison then measures the cost of the extra traffic around a command, not a different command protocol.

### Counting traffic

`TrafficCounter` counts messages and bytes per channel and direction inside `WCSessionTransport`. Bytes are the encoded JSON the app hands over. WatchConnectivity's framing isn't visible to apps, so "bytes" means the app's share, and the docs say so.

One `updateApplicationContext` call sends every slot in the context dictionary, so its byte count is the whole dictionary, not only the slot that changed. That's the real cost of keeping state and bookmarks in one context.

### Measuring round trips

`WatchSync.sendAndMeasure` registers a waiter under the command's ID, sends the command, and resolves the waiter when a state arrives whose `lastCommandID` matches. A separate task resolves it with nil after the timeout, and whichever comes first wins, because a waiter is removed when it's resolved. Both clocks are the Watch's, so the result doesn't depend on the two devices agreeing on the time.

The 95th percentile uses the nearest-rank method, so the reported value is always a sample that was actually measured. With 40 samples, that's the 38th smallest.

### What the Simulator can't tell you

Two Simulators on one Mac talk over local IPC, not Bluetooth, and run on Mac CPUs. The measurements compare the two modes under the same conditions. They don't predict absolute latency, CPU or battery on real hardware, and docs/PERFORMANCE.md lists those as not measured.

