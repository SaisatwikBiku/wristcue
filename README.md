# WristCue

A podcast player for iPhone with an Apple Watch remote. The iPhone plays episodes. The Watch shows Now Playing, controls playback, and saves moment bookmarks with one tap, including while the iPhone is out of reach.

Work in progress. The full README (architecture diagram, run instructions, screenshots) arrives with milestone M7.

## Status

- [x] M1: `WristCueKit` models, versioned wire protocol, progress interpolation, offline queue, tests
- [ ] M2: iPhone playback and Now Playing
- [ ] M3: Watch Now Playing and WatchConnectivity
- [ ] M4: Bookmarks and offline queue on both devices
- [ ] M5: Naive vs. optimized sync, measurements
- [ ] M6: Accessibility, haptics, complication
- [ ] M7: Docs and CI

## Run the kit tests

```sh
cd Packages/WristCueKit
xcodebuild test -scheme WristCueKit -destination 'platform=macOS' -enableCodeCoverage YES -resultBundlePath ../../build/WristCueKit.xcresult
xcrun xccov view --report --only-targets ../../build/WristCueKit.xcresult
```

`swift test` from the same directory also works.

## License

MIT. See [LICENSE](LICENSE).
