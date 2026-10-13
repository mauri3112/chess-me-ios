# ChessMe iOS source

Corresponding client source for ChessMe 0.2.0 build 17, tag `ios-0.2.0-build17`.
The original iOS app and shared core use GNU GPL version 3 only. See LICENSE and
CLIENT-LICENSE.md. Third-party notices and compatible licences remain intact.
The cloud backend is separately operated and is not included here.

## Build and run

Use Xcode 26 or later, with its iOS SDK and simulator installed. Open
`ios/ChessMe.xcodeproj`, select the ChessMe scheme, and run on an iPhone simulator.
The minimum runtime is iOS 17. For a personal device build, select your own
development team and a unique bundle identifier; update the URL scheme if needed.
For offline sample games, add `--demo` in the scheme's launch arguments.
No private signing keys or cloud credentials are needed for a simulator build.

Run `swift test`, `scripts/check-ios.sh --build`, and `scripts/check-ios.sh --test`
from this repository's root. Debug StoreKit fixtures are optional and cannot
authorize production cloud compute. Provider connection requires its own OAuth
registration when you change the registered client and callback configuration.

## Engine and analysis

Stockfish 19 source, the native bridge and platform build flags are in
Vendor/Stockfish. Exact NNUE networks and licence resources are included in
Sources/ChessMeCore/Resources. Stockfish's network checksum and pinned upstream
commit are in Vendor/Stockfish/provenance.json. Arasan 26 remains an alternative.
Asset-generation sources are included under docs/design.

Settings > On-device analysis offers depth targets 24, 28 and 32 on supported
iPhones and iPads, including the base iPhone 15. Memory use adapts to app
headroom. Estimated games per night use recent game lengths and complete
measured reviews from this device. Estimates are capacity planning, not a
promise that iOS grants uninterrupted background time. Reviews report
achieved depth and save completed decisions. User-started work requests continued
processing on iOS 26 or later; overnight jobs run while charging between 22:00
and 07:00 when iOS grants processing time. System interruption, force quitting,
Low Power Mode, thermal state and memory pressure can delay completion.

The public repository publishes source only. The requested binary distribution
is internal TestFlight. There is no warranty. The source-manifest.json file
records SHA-256 for every included file and network.
