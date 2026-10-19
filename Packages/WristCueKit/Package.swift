// swift-tools-version: 6.0
// Tools version 6.0 turns on the Swift 6 language mode, which makes data races
// compile-time errors. See docs/LEARNING.md, "Swift 6 and Sendable".
import PackageDescription

let package = Package(
    name: "WristCueKit",
    // macOS is listed only so `xcodebuild test -destination 'platform=macOS'` can run
    // the kit's tests without booting a simulator. No app ships on macOS.
    platforms: [.iOS(.v17), .watchOS(.v10), .macOS(.v14)],
    products: [
        .library(name: "WristCueKit", targets: ["WristCueKit"]),
    ],
    targets: [
        // Pure Foundation code: models, wire protocol, sync rules. Nothing in this
        // target imports WatchConnectivity, AVFoundation or SwiftUI.
        .target(name: "WristCueKit"),
        .testTarget(name: "WristCueKitTests", dependencies: ["WristCueKit"]),
    ]
)
