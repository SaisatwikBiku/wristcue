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

## Not yet measured

The following arrive with M5 and will be filled in from real runs only:

- Messages per minute, naive vs. optimized sync, over 5 minutes of playback
- Average payload size in bytes per message type
- Command round-trip latency on paired simulators (median and 95th percentile over at least 30 commands)
- Watch app CPU profile with Time Profiler
