# WristCue

A podcast player for iPhone with an Apple Watch remote. The iPhone plays episodes. The Watch shows Now Playing, controls playback, and saves moment bookmarks with one tap, including while the iPhone is out of reach.

Work in progress. The full README (architecture diagram, run instructions, screenshots) arrives with milestone M7.

## Status

- [x] M1: `WristCueKit` models, versioned wire protocol, progress interpolation, offline queue, tests (76 tests at M3, 99.28% line coverage; see [docs/PERFORMANCE.md](docs/PERFORMANCE.md))
- [x] M2: iPhone playback and Now Playing (Lock Screen panel not drawn by the iOS 27.0 Simulator; app side verified, see docs/LEARNING.md)
- [x] M3: Watch Now Playing and WatchConnectivity (8 Simulator checks passed after a Swift 6 crash fix; see docs/LEARNING.md)
- [ ] M4: Bookmarks and offline queue on both devices
- [ ] M5: Naive vs. optimized sync, measurements
- [ ] M6: Accessibility, haptics, complication
- [ ] M7: Docs and CI

## Run the iPhone app

Needs Xcode 27 and [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`). The episode audio is synthetic, generated with the macOS `say` command.

```sh
scripts/make-audio.sh   # writes WristCue/Resources/Audio/*.m4a
xcodegen generate       # writes WristCue.xcodeproj from project.yml
open WristCue.xcodeproj
```

Pick the WristCue scheme and an iPhone simulator, then Run. No Apple Developer account is needed.

No sound from the Simulator? Choose your Mac's speakers in the Simulator's **I/O > Audio Output** menu. The Simulator can lose its output after AirPods connect or disconnect.

## Run the kit tests

```sh
cd Packages/WristCueKit
xcodebuild test -scheme WristCueKit -destination 'platform=macOS' -enableCodeCoverage YES -resultBundlePath ../../build/WristCueKit.xcresult
xcrun xccov view --report --only-targets ../../build/WristCueKit.xcresult
```

`swift test` from the same directory also works.

## License

MIT. See [LICENSE](LICENSE).
