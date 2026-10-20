# Resume notes

Bullets for a resume or cover letter. Each number below was measured in this repository, and the line under each bullet says where. Nothing here is estimated.

## Bullets

- Built WristCue, an iPhone podcast player with an Apple Watch remote, in Swift 6 and SwiftUI with strict concurrency, choosing a WatchConnectivity channel per data type: `sendMessage` for taps, `updateApplicationContext` for playback state and bookmarks, `transferUserInfo` for commands made offline.
  Source: README architecture section, `Shared/WCSessionTransport.swift`.

- Put all sync logic in a UI-free Swift package behind a transport protocol and tested it over an in-memory transport with a fake clock: 115 unit tests, 98.78% line coverage (727 of 736 lines), measured with `xcodebuild test` and `xccov`.
  Source: docs/PERFORMANCE.md, "After the M5 sync fixes".

- Built a naive and an optimized sync mode in the same app to measure the design: in a scripted minute of playback with one crown turn, the optimized protocol sends 5 messages and 912 bytes against 83 messages and 17,708 bytes for the naive one (16.6 times fewer messages, 19.4 times fewer bytes), measured in a deterministic model test.
  Source: docs/PERFORMANCE.md, "Traffic model". Say "model test" if asked: it counts what the sync logic hands to the transport, not Simulator traffic.

- Made Watch bookmarks work offline: a disk-backed queue that coalesces repeated controls, expires playback commands after 30 seconds, never drops bookmarks, and delivers each command once by UUID. Verified in paired Simulators with the iPhone app stopped and the Watch app relaunched (10 of 10 checks passed).
  Source: docs/LEARNING.md, M4; README status.

- Diagnosed a Swift 6 runtime crash (`_dispatch_assert_queue_fail`) from the crash report: a WatchConnectivity reply handler written in main-actor code was inferred as main-actor isolated and called on a background queue. Fixed it by marking the handlers `@Sendable`.
  Source: docs/LEARNING.md, "A Swift 6 crash found in the Simulator".

- Kept the wire format small and versioned: a playback state is 246 bytes of JSON and commands are 158 to 309 bytes, with the version decoded before the body so mismatched app versions fail cleanly.
  Source: docs/PERFORMANCE.md, "Payload sizes"; `WireMessage.swift`.

- Added XCUITest coverage of the iPhone app with Xcode's accessibility audit: 6 of 6 tests pass after fixing the 2 issues the audit found (a title that didn't scale with Dynamic Type, and low-contrast secondary text).
  Source: docs/PERFORMANCE.md, "iPhone UI tests"; docs/LEARNING.md, M6.

- Measured three sync designs in paired Simulators with an unattended script: during 60 seconds of playback the iPhone sent 56 messages (12,012 bytes) with per-second streaming and 5 (1,350 bytes) with publish-on-change, all 5 from the Watch connecting; a 10-step crown turn sent 10 commands against 1 with a 300 ms debounce.
  Source: docs/PERFORMANCE.md, "Automated Simulator run", Results.

- Showed that per-second streaming slows the remote: median command round trip 2731.8 ms with 2 of 40 timeouts, against 920.8 to 1239.8 ms for the publish-on-change designs (40 commands each, Simulator).
  Source: same section. If asked: the two publish-on-change designs couldn't be ranked from one run each, and the Simulator's transport alone took 775 to 954 ms per round trip.

- Found and fixed a stale-state bug with the measurement script's own diagnostics: a Watch app opened after playback started showed an old state, and the script was talking to an unpaired iPhone Simulator. The Watch now requests the current state when it connects.
  Source: docs/LEARNING.md, "What the scripted run found".

## Talking points

- Why the Watch interpolates progress instead of receiving it: the iPhone sends a state only when something changes, and the Watch computes the position from that state's timestamp and rate. Steady playback costs no messages.
- Why the offline queue holds commands itself instead of handing them to `transferUserInfo` at once: once handed over, an item can't be coalesced or expired.
- What the Simulator can't tell you: battery, Bluetooth latency and real Watch CPU. The project says so instead of estimating.
