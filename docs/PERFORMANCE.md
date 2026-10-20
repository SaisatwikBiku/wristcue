# Performance and quality measurements

Every number here comes from a command run against this repository, with the command, the environment and the raw output next to it. Measurements that can't be taken in the Simulator are marked as such instead of estimated.

## Environment

| Item | Value | Source |
|---|---|---|
| Xcode | 27.1 (build 27A9275) | `xcodebuild -version` |
| macOS SDK | MacOSX27.0 | `swift test` compiler command line |
| iOS Simulator runtimes | 27.0 (24A434), 27.1 (24A94425) | `xcodebuild -downloadPlatform iOS` |
| watchOS Simulator runtime | 27.0 (24R362) | `xcodebuild -downloadPlatform watchOS` |
| Machine | Apple silicon Mac (arm64) | runtime architecture reported by `xcodebuild -downloadPlatform` |

## WristCueKit test coverage

Measured 2026-10-19 at commit `d0e27f4` (M1).

Method, run from `Packages/WristCueKit`:

```sh
xcodebuild test -scheme WristCueKit -destination 'platform=macOS' \
  -enableCodeCoverage YES -resultBundlePath ../../build/WristCueKit.xcresult
xcrun xccov view --report --only-targets ../../build/WristCueKit.xcresult
```

Raw output:

```
Test Suite 'WristCueKitTests.xctest' passed at 2026-10-19 15:58:52.418.
	 Executed 61 tests, with 0 failures (0 unexpected) in 0.026 (0.036) seconds

** TEST SUCCEEDED **

ID Name             # Source Files Coverage
-- ---------------- -------------- ----------------
0  WristCueKit      11             99.66% (294/295)
1  WristCueKitTests 18             99.80% (989/991)
```

Result: 61 tests, 0 failures. Line coverage of the `WristCueKit` library target is 99.66% (294 of 295 executable lines). The `WristCueKitTests` row is the test code itself and isn't counted toward the 80% target.

### After M2

Measured 2026-10-19. The kit source is unchanged from commit `0b6a898` through `517f88e`. M2 added `TimeFormat` and its tests.

Same method as above, with `-resultBundlePath ../../build/WristCueKit-m2.xcresult`. Raw output:

```
	 Executed 64 tests, with 0 failures (0 unexpected) in 0.030 (0.041) seconds
** TEST SUCCEEDED **
ID Name             # Source Files Coverage
-- ---------------- -------------- ------------------
0  WristCueKit      12             99.67% (303/304)
1  WristCueKitTests 20             99.81% (1028/1030)
```

Result: 64 tests, 0 failures. Line coverage of `WristCueKit` is 99.67% (303 of 304 executable lines).

### After M3

Measured 2026-10-19 on the code at commit `8185c44`. M3 added `PhoneSync`, `WatchSync` and `SyncTests`.

Same method as above, with `-resultBundlePath ../../build/WristCueKit-m3.xcresult`. Raw output:

```
	 Executed 76 tests, with 0 failures (0 unexpected) in 0.261 (0.274) seconds
** TEST SUCCEEDED **
ID Name             # Source Files Coverage
-- ---------------- -------------- ------------------
0  WristCueKit      14             99.28% (414/417)
1  WristCueKitTests 23             99.71% (1375/1379)
```

Result: 76 tests, 0 failures. Line coverage of `WristCueKit` is 99.28% (414 of 417 executable lines).

### After M5

Measured 2026-10-19 on the code at commit `3b083c7`. M4 added `JSONFileStore`, `BookmarkStore`, the offline queue in `WatchSync` and `StorageTests`. M5 added `SyncMode`, `TrafficCounter`, `LatencySummary`, round-trip measurement and `MeasurementTests`. No separate run was made at M4, so this one covers both.

Same method as above, with `-resultBundlePath ../../build/m5.xcresult`. Raw output (per-suite lines trimmed):

```
	 Executed 110 tests, with 0 failures (0 unexpected) in 0.315 (0.339) seconds
** TEST SUCCEEDED **
ID Name             # Source Files Coverage
-- ---------------- -------------- ------------------
0  WristCueKit      19             98.70% (684/693)
1  WristCueKitTests 30             99.20% (2227/2245)
```

Result: 110 tests, 0 failures. Line coverage of `WristCueKit` is 98.70% (684 of 693 executable lines).

## iPhone app build

Measured 2026-10-19 on the M2 code. Method:

```sh
xcodebuild -project WristCue.xcodeproj -scheme WristCue \
  -destination 'platform=iOS Simulator,name=iPhone 17,OS=27.0' build 2>&1 | grep -E "warning:|error:|BUILD" | sort -u
```

Raw output:

```
** BUILD SUCCEEDED **
2026-10-19 17:56:10.572 appintentsmetadataprocessor[85476:13319985] warning: Metadata extraction skipped, no AppIntents.framework dependency found
```

Result: the app builds in the Swift 6 language mode with no compiler warnings from project code. The single warning comes from Xcode's App Intents metadata tool, and the app doesn't use App Intents.

### After the M5 sync fixes

Measured 2026-10-20 after adding live `request` messages and the reply hook (commit titled "Watch requests state on connect; optimized mode acknowledges in the reply"). Same method as above, with `-resultBundlePath ../../build/m5c.xcresult`. Raw output:

```
	 Executed 115 tests, with 0 failures (0 unexpected) in 0.321 (0.348) seconds
** TEST SUCCEEDED **
ID Name             # Source Files Coverage
-- ---------------- -------------- ------------------
0  WristCueKit      19             98.78% (727/736)
1  WristCueKitTests 30             99.20% (2349/2368)
```

Result: 115 tests, 0 failures. Line coverage of `WristCueKit` is 98.78% (727 of 736 executable lines).

## iPhone UI tests

Measured 2026-10-20 on the code after the accessibility fixes (the commit after `7b3a3c9` titled "Fix the two accessibility audit findings"). Method, from the repository root, with an iPhone Simulator booted:

```sh
xcodebuild test -project WristCue.xcodeproj -scheme WristCue \
  -destination "platform=iOS Simulator,id=$PHONE" -derivedDataPath ~/Library/Developer/WristCueBuild
```

Raw output (filtered to test results):

```
Test Case '-[WristCueUITests.WristCueUITests testBookmarkFromPlayerIsListed]' passed (8.818 seconds).
Test Case '-[WristCueUITests.WristCueUITests testBookmarksScreenPassesAccessibilityAudit]' passed (8.723 seconds).
Test Case '-[WristCueUITests.WristCueUITests testBookmarksStartEmpty]' passed (6.852 seconds).
Test Case '-[WristCueUITests.WristCueUITests testEpisodeListPassesAccessibilityAudit]' passed (8.110 seconds).
Test Case '-[WristCueUITests.WristCueUITests testListShowsEveryEpisode]' passed (9.421 seconds).
Test Case '-[WristCueUITests.WristCueUITests testOpeningAnEpisodeShowsThePlayer]' passed (6.944 seconds).
** TEST SUCCEEDED **
```

Result: 6 of 6 pass, including Xcode's accessibility audit on the episode list and the Bookmarks screen. The first run failed both audits, one issue each (Dynamic Type on the empty-state title, contrast on the episode summary). docs/LEARNING.md, M6, has the audit output and the fixes.

## Bundled episode audio

Measured 2026-10-19 at commit `0b6a898` (M2), with the macOS voice Samantha.

Method, run from the repository root: `scripts/make-audio.sh`. For each text file in `scripts/episodes/`, the script runs `say -v Samantha -f <text> -o <file>.m4a --data-format=aac`, then reads the duration with `afinfo`, the size with `wc -c` and the word count with `wc -w`.

Raw output:

```
ep1-glance.m4a: 87.442449 s, 388433 bytes, 302 words
ep2-crown.m4a: 93.110113 s, 411844 bytes, 297 words
ep3-remote.m4a: 91.134240 s, 404483 bytes, 293 words
ep4-codec.m4a: 93.291247 s, 412179 bytes, 276 words
```

| Episode | Duration (s) | Size (bytes) | Words |
|---|---|---|---|
| ep1-glance | 87.44 | 388,433 | 302 |
| ep2-crown | 93.11 | 411,844 | 297 |
| ep3-remote | 91.13 | 404,483 | 293 |
| ep4-codec | 93.29 | 412,179 | 276 |
| Total | 364.98 | 1,616,939 | 1,168 |

All four are inside the 1 to 3 minute target. The total is the sum of the four rows above.

## Sync: naive vs. optimized (M5)

`SyncMode` (in the kit) picks one of three sync designs at launch, with `-WristCueSyncMode optimized` (the default), `contextAck` or `naive`:

| | Optimized | Context ack | Naive |
|---|---|---|---|
| iPhone state while playing | only on change, `updateApplicationContext` | same | every second and on change, `sendMessage` |
| Acknowledging a Watch command | new state in the `sendMessage` reply, plus the context update | context update only | the next live state |
| Watch progress bar | interpolated locally, at most 1 redraw/s | same | shows the last position received |
| Crown volume | one command after 300 ms of rest | same | one command per detent |
| Commands from the Watch | `sendMessage`, offline queue | same | same |

`contextAck` was the first M5 design. A manual run measured its round trip at a median of 1739.7 ms and a p95 of 1749.8 ms over 40 commands (0 timeouts, min 1316.2 ms, max 1753.0 ms), read from the Watch Diagnostics screen; the raw samples of that run were lost to stdout buffering (docs/LEARNING.md, M5). `optimized` replaced it, and the scripted run below measures both.

Results are added below only from runs. Each method says what is counted.

### Payload sizes

Encoded size of each `WireMessage` JSON, from the kit test `testReportPayloadSizes`, which prints `WRISTCUE_PAYLOAD <name> <bytes>`. Run from `Packages/WristCueKit`:

```sh
xcodebuild test -scheme WristCueKit -destination 'platform=macOS' \
  -only-testing:WristCueKitTests/MeasurementTests/testReportPayloadSizes 2>&1 | grep WRISTCUE_PAYLOAD
```

WatchConnectivity adds its own framing on top, which apps can't see, so this is the app's share of each message.

Measured 2026-10-19 at commit `3b083c7`. Raw output:

```
WRISTCUE_PAYLOAD state 246
WRISTCUE_PAYLOAD command.play 158
WRISTCUE_PAYLOAD command.skip 170
WRISTCUE_PAYLOAD command.setVolume 175
WRISTCUE_PAYLOAD command.addBookmark 309
WRISTCUE_PAYLOAD bookmarks.0 103
WRISTCUE_PAYLOAD bookmarks.1 236
WRISTCUE_PAYLOAD bookmarks.10 1442
```

| Message | Bytes |
|---|---|
| Playback state | 246 |
| Command: play | 158 |
| Command: skip | 170 |
| Command: set volume | 175 |
| Command: add bookmark | 309 |
| Bookmark list, empty | 103 |
| Bookmark list, 1 bookmark | 236 |
| Bookmark list, 10 bookmarks | 1,442 |

One bookmark adds 133 bytes to the list (236 minus 103). Ten add 1,339 bytes, 133.9 each on average.

### Traffic model

`testReportTrafficForOneScriptedMinute` runs the same scripted minute in both modes over the in-memory transport: play, 60 seconds of playback, one crown turn of 10 detents. It prints `WRISTCUE_TRAFFIC` lines with messages and bytes per channel. This counts what the sync logic hands to the transport. It's a model of the protocol, not a Simulator measurement.

```sh
xcodebuild test -scheme WristCueKit -destination 'platform=macOS' \
  -only-testing:WristCueKitTests/MeasurementTests/testReportTrafficForOneScriptedMinute 2>&1 | grep WRISTCUE_TRAFFIC
```

Measured 2026-10-19 at commit `3b083c7`, before replies existed; at that commit "optimized" behaved like today's `contextAck`. Raw output:

```
WRISTCUE_TRAFFIC mode=optimized channel=interactive messages=2 bytes=302
WRISTCUE_TRAFFIC mode=optimized channel=latest messages=3 bytes=610
WRISTCUE_TRAFFIC mode=optimized channel=guaranteed messages=0 bytes=0
WRISTCUE_TRAFFIC mode=naive channel=interactive messages=83 bytes=17708
WRISTCUE_TRAFFIC mode=naive channel=latest messages=0 bytes=0
WRISTCUE_TRAFFIC mode=naive channel=guaranteed messages=0 bytes=0
```

| Mode | Messages | Bytes |
|---|---|---|
| Optimized | 5 | 912 |
| Naive | 83 | 17,708 |

For the scripted minute, naive mode sends 16.6 times as many messages and 19.4 times as many bytes (83 / 5 and 17,708 / 912). The 83 break down as the iPhone's initial state, 1 acknowledgement for play, 60 one-second states and 10 acknowledgements for the 10 crown detents (72 from the iPhone), plus play and 10 volume commands from the Watch (11). In optimized mode the crown turn costs one command and one acknowledgement, and steady playback costs nothing.

### Automated Simulator run

`scripts/measure-sync.sh` runs the Simulator measurements below in all three modes without input and saves the raw lines to `docs/measurements/sync-<mode>-iphone.log`, `-watch.log` and `-cpu.log`. The iPhone app is launched with `-WristCueAutoplay glance -WristCueAutoMeasure YES` and starts the episode itself. The Watch app is launched with `-WristCueAutoMeasure YES` and runs three phases, resetting its counters before each:

1. Steady playback, 60 seconds untouched. The iPhone resets its own counters 3 seconds after playback starts, so the play state itself isn't counted, and reports 60 seconds later. Watch CPU is measured with `cpu-seconds.sh` over 55 seconds inside this window.
2. A scripted crown turn: 10 volume steps 50 ms apart through `WatchSync.setVolume`, the same entry point the Digital Crown uses, then 3 seconds for the result to settle. It isn't real crown input.
3. The 40-command round-trip benchmark described under "Command round trip".

The manual methods below remain for checking a single number by hand.

#### Results

Measured 2026-10-20 with `WATCH=683301EF-40F3-4D03-9B1D-876987BE1006 scripts/measure-sync.sh`: iPhone 17 Simulator (iOS 27.0) paired with an Apple Watch Series 12 (46mm) Simulator (watchOS 27.0), one run per mode. The raw lines are in `docs/measurements/sync-<mode>-*.log`. Summary lines from the script's output:

```
WRISTCUE_STEADY side=iphone mode=optimized seconds=60.1 interactive_sent=5/1350 interactive_received=5/359 latest_sent=0/0 latest_received=0/0 guaranteed_sent=0/0 guaranteed_received=0/0 total_sent=5/1350 total_received=5/359
WRISTCUE_STEADY side=watch mode=optimized seconds=64.0 interactive_sent=1/75 interactive_received=2/579 latest_sent=0/0 latest_received=0/0 guaranteed_sent=0/0 guaranteed_received=0/0 total_sent=1/75 total_received=2/579
WRISTCUE_CROWN side=watch mode=optimized seconds=3.5 interactive_sent=1/174 interactive_received=1/279 latest_sent=0/0 latest_received=1/666 guaranteed_sent=0/0 guaranteed_received=0/0 total_sent=1/174 total_received=2/945
WRISTCUE_RTT_END mode=optimized n=40 timeouts=0 median_ms=1239.8 p95_ms=1788.6 min_ms=511.8 max_ms=1815.1
WRISTCUE_RTT_TRAFFIC side=watch mode=optimized seconds=59.9 interactive_sent=40/7527 interactive_received=40/10327 latest_sent=0/0 latest_received=41/26457 guaranteed_sent=0/0 guaranteed_received=0/0 total_sent=40/7527 total_received=81/36784
WristCueWatch (pid 79593): 0.29 CPU seconds in 55 s, 0.53% of one core

WRISTCUE_STEADY side=iphone mode=contextAck seconds=60.0 interactive_sent=4/1156 interactive_received=4/291 latest_sent=0/0 latest_received=0/0 guaranteed_sent=0/0 guaranteed_received=0/0 total_sent=4/1156 total_received=4/291
WRISTCUE_STEADY side=watch mode=contextAck seconds=63.5 interactive_sent=1/75 interactive_received=2/578 latest_sent=0/0 latest_received=0/0 guaranteed_sent=0/0 guaranteed_received=0/0 total_sent=1/75 total_received=2/578
WRISTCUE_CROWN side=watch mode=contextAck seconds=3.6 interactive_sent=1/174 interactive_received=0/0 latest_sent=0/0 latest_received=1/666 guaranteed_sent=0/0 guaranteed_received=0/0 total_sent=1/174 total_received=1/666
WRISTCUE_RTT_END mode=contextAck n=40 timeouts=0 median_ms=920.8 p95_ms=1787.8 min_ms=679.6 max_ms=1788.1
WRISTCUE_RTT_TRAFFIC side=watch mode=contextAck seconds=59.4 interactive_sent=40/7534 interactive_received=0/0 latest_sent=0/0 latest_received=41/26452 guaranteed_sent=0/0 guaranteed_received=0/0 total_sent=40/7534 total_received=41/26452
WristCueWatch (pid 82358): 0.27 CPU seconds in 55 s, 0.49% of one core

WRISTCUE_STEADY side=iphone mode=naive seconds=60.0 interactive_sent=56/12012 interactive_received=4/292 latest_sent=0/0 latest_received=0/0 guaranteed_sent=0/0 guaranteed_received=0/0 total_sent=56/12012 total_received=4/292
WRISTCUE_STEADY side=watch mode=naive seconds=63.4 interactive_sent=0/0 interactive_received=63/13281 latest_sent=0/0 latest_received=0/0 guaranteed_sent=0/0 guaranteed_received=0/0 total_sent=0/0 total_received=63/13281
WRISTCUE_CROWN side=watch mode=naive seconds=3.6 interactive_sent=10/1760 interactive_received=5/1324 latest_sent=0/0 latest_received=0/0 guaranteed_sent=0/0 guaranteed_received=0/0 total_sent=10/1760 total_received=5/1324
WRISTCUE_RTT_END mode=naive n=38 timeouts=2 median_ms=2731.8 p95_ms=2747.5 min_ms=2729.1 max_ms=2793.8
WRISTCUE_RTT_TRAFFIC side=watch mode=naive seconds=120.8 interactive_sent=40/7550 interactive_received=51/13655 latest_sent=0/0 latest_received=0/0 guaranteed_sent=0/0 guaranteed_received=0/0 total_sent=40/7550 total_received=51/13655
WristCueWatch (pid 85120): 0.34 CPU seconds in 55 s, 0.62% of one core
```

Steady playback (messages/bytes in the window):

| | Optimized | Context ack | Naive |
|---|---|---|---|
| iPhone sent, 60 s | 5 / 1,350 B | 4 / 1,156 B | 56 / 12,012 B |
| Watch received, 63 to 64 s | 2 / 579 B | 2 / 578 B | 63 / 13,281 B |

In optimized and context-ack mode, every message in these windows belongs to the Watch app connecting (its state and bookmark requests, their replies, and the run's own probe request), because the iPhone's window opens 3 seconds after playback starts and the Watch app launches at about the same time. Neither mode sent anything periodic. In naive mode the iPhone sent a state every second.

Scripted crown turn (10 volume steps 50 ms apart): the Watch sent 1 command in optimized and context-ack mode and 10 in naive mode. In naive mode 5 states came back within the 3.5-second window.

Command round trip, 40 commands:

| Mode | Median | p95 | Min | Max | Timeouts |
|---|---|---|---|---|---|
| Optimized (state in the reply) | 1239.8 ms | 1788.6 ms | 511.8 ms | 1815.1 ms | 0 |
| Context ack | 920.8 ms | 1787.8 ms | 679.6 ms | 1788.1 ms | 0 |
| Naive | 2731.8 ms | 2747.5 ms | 2729.1 ms | 2793.8 ms | 2 |

Returning the state in the reply did not lower the round trip in the Simulator: the median was higher than context ack and the p95 the same. The earlier probe measured 775 to 954 ms for a `sendMessage` round trip whose reply was empty, so most of each round trip is the Simulator's own transport. A manual context-ack run earlier the same day measured a 1739.7 ms median, against 920.8 ms here, so run-to-run variation is larger than the difference between the two acknowledgement designs, and one run each can't rank them. Naive mode was 2.2 times slower than optimized and 3.0 times slower than context ack at the median (2731.8 / 1239.8 and 2731.8 / 920.8), with 2 of 40 commands timing out.

Watch CPU over 55 seconds of steady playback: 0.29 s optimized, 0.27 s context ack, 0.34 s naive. One run each, Mac CPU time; the differences are small enough that more runs would be needed before reading anything into them.

### Simulator traffic per minute

Debug builds show WatchConnectivity counters: on the iPhone under the player, on the Watch in Diagnostics (gauge icon, top left). They count messages handed to WatchConnectivity and messages received from it, with the encoded bytes of each. Method, once per mode: launch both apps in that mode, start Glance on the iPhone, tap Reset on both, leave both screens untouched for 60 seconds, then read both panels. The episodes are 87 to 93 seconds long, so a window longer than a minute would run into the end of the episode.

### Crown turn

Method, once per mode: tap Reset in Watch Diagnostics, go back to Now Playing, turn the crown from 50% to 100% in one motion (in the Simulator, scroll over the Watch screen), then read the Watch's interactive "out" count.

### Command round trip

Watch Diagnostics, "Run 40 commands": 40 volume commands, one at a time with a 250 ms gap, each timed from the send to the iPhone state that acknowledges it, on the Watch's clock. A command with no acknowledgement within 3 seconds counts as a timeout. The screen shows the median (middle sample, or mean of the middle two) and the 95th percentile (nearest rank: sample number ceil(0.95 n) in ascending order). Every sample is printed as `WRISTCUE_RTT_MS`, so launching the Watch app with `xcrun simctl launch --console` captures the raw data.

Both Simulators run on the same Mac and talk over local IPC, not Bluetooth, so these numbers compare the two modes and don't predict latency between a real iPhone and Watch.

### Watch app CPU

`scripts/cpu-seconds.sh WristCueWatch 60` reads the Watch app process's CPU time with `ps` before and after a 60-second window. Method, once per mode: Glance playing, Watch on Now Playing with the screen awake, run the script. This is Mac CPU time spent by the Simulator process. It compares the modes. It is not the energy a real Watch would use.

### Not measurable in the Simulator

- Battery and energy use on a real Apple Watch. The Simulator has no battery and no energy gauge for watchOS.
- Bluetooth latency between real devices.
- Always-on display redraws. The once-a-minute redraw while `isLuminanceReduced` is true isn't measured in this project. It's only checked by reading the code.
