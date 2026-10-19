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

## Not yet measured

The following arrive with M5 and will be filled in from real runs only:

- Messages per minute, naive vs. optimized sync, over 5 minutes of playback
- Average payload size in bytes per message type
- Command round-trip latency on paired simulators (median and 95th percentile over at least 30 commands)
- Watch app CPU profile with Time Profiler
