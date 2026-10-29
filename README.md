# ChessMe iOS source

Corresponding client source for ChessMe 0.2.0 build 33, tag `ios-0.2.0-build33`.
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

Native builds use Arasan 26 and its MIT-licensed neural network. Arasan source,
adapter and provenance are in Vendor/Arasan. Package.swift excludes Stockfish
code and its NNUE from iOS builds. Stockfish 19 remains available for macOS/Linux
reference tools; its source, adapter and platform flags are in Vendor/Stockfish.
Exact NNUE networks and licence resources are in Sources/ChessMeCore/Resources.
Stockfish's network checksum and pinned upstream commit are in
Vendor/Stockfish/provenance.json. Saved reviews retain their actual engine labels.
Asset-generation sources are included under docs/design.

The full CC0 Lichess opening catalogue is pinned in Vendor/LichessOpenings.
Its offline position/move index is Sources/ChessMeCore/Resources/OpeningBook.json.
To reproduce the index, run `uv run --with python-chess python
scripts/generate-opening-book.py` (one command on one line). Source checksums
are verified before generation. Book labels preserve engine scores and exclude
opening theory from mistake cards, counts and recommendations. Through move 12,
only practical blunders become lessons. Blunder grading uses winning-chance loss
and practical losing-position gates. OpeningEvaluations.json caches exact
engine/history/configuration matches; its builder and provenance are included.
Unmatched positions use the selected available device engine. Recognition follows each recorded line's
length and supports transpositions without restarting theory after repetitions.

Settings > On-device analysis offers depth targets 24, 28 and 32 on supported
iPhones and iPads, including the base iPhone 15. Memory use adapts to app
headroom. Estimated games per night use recent game lengths and complete
measured reviews from this device. Estimates are capacity planning, not a
promise that iOS grants uninterrupted background time. Reviews report
achieved depth and save completed decisions. User-started work requests continued
processing with regular measured search-time progress, including long iterations.
Background grants and expiration callbacks are matched to their own batch;
completed foreground work also handles delayed grants safely. Interrupted jobs
retain the reason for waiting and their saved decisions.
Continued processing uses iOS 26 or later; overnight jobs run while charging between 22:00
and 07:00 when iOS grants processing time. System interruption, force quitting,
Low Power Mode, thermal state and memory pressure can delay completion.

Games > Add for analysis lets users choose night or immediate device analysis,
select individual games and save the selection. Explicit night selections remain
queued when automatic overnight queuing is disabled. Row icons distinguish
unreviewed games, night jobs, waiting jobs, active progress and completed reviews.
Today offers Puzzles and Opening practice alongside the next lesson. It lists
active and remaining queued games with links to their reviews. The review filter
defaults to All games, with Reviewed, Local reviewed and Cloud reviewed options.
Time-control filters apply to imports, games and manual analysis selection.
Automatic bullet and blitz reviews use a quick budget unless deeper analysis is
requested manually or enabled in settings. Saved combines with the other filters.
Night and immediate scheduling choices open beside Add for analysis. Period labels
keep their full text, and long opponent names truncate without squeezing Explore.
Recorded results determine win/loss colors; engine evaluations never infer a
winner. Practice browsing and trial branches keep the original game intact.
Game review starts with an overview and a main takeaway, then follows selected
moments in game order. Supported plans include multiple decisions. Ideas and
playable key lines stay together, with deeper branches in Explore and explanations
on request. Save line explicitly retains a variation with its game context.
Games > Saved lines groups these by opening and supports search and side filters.

Practice is optional and returns to the same review step or recap. Exercises
adapt to supported alternatives, ask for critical follow-ups, and play opponent
replies automatically. Mistakes preserve the accepted prefix and offer Try again,
Hint and Show why. Assistance and unassessed moves remain in attempt history.
Related puzzles require a verified shared board mechanism and remain optional.
Their outcomes are separate from the core session count.

Short suggested follow-up sets adapt their timing to help, mistakes and later
clean attempts. Keep, Defer, Dismiss and Restore preserve manual control. Later
recall, fresh related-position results and board-backed observations in later
games have separate dated evidence. Saved context and exact active-exercise state
remain local. These features do not establish a comparative learning advantage.
After solving or revealing, Explore supports legal trial moves, live device
evaluation, optional engine replies and analysis settings. Trial branches do not
rewrite the recorded attempt or game.

The public repository publishes source only. The requested binary distribution
is internal TestFlight. There is no warranty. The source-manifest.json file
records SHA-256 for every included file and network.
