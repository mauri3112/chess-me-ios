# Offline opening recognition

ChessMe bundles the complete five-volume [Lichess opening catalogue](https://github.com/lichess-org/chess-openings), pinned to `a6189a30dc273ccb21fc2536a9a2fefd5592a67a`. It contains 3,865 lines and variations covering all 500 ECO codes, A00–E99. Original TSVs, CC0 dedication and file checksums are in `Vendor/LichessOpenings/`. The generated offline index is 1,043,498 bytes and contains 7,983 positions and 8,192 directed position/move edges. No service request is needed to recognize an opening.

Each line contributes every move from the standard initial position. Matching uses piece placement, side to move, castling rights and a legally available en-passant capture. Move counters and irrelevant en-passant targets do not break transpositions. The match requires the actual move from the actual position; a game's opening name never exempts the rest of the game.

Recognition follows the catalogue length of each edge. There is no fixed ten-move opening cutoff. The longest included variation has 36 plies, the Marshall Attack's Spassky Variation. This is catalogue coverage, not engine search depth. Repeated positions stop opening recognition so later manoeuvres cannot restart the opening. Nonstandard starting positions do not inherit opening exemptions. Explore uses the imported prefix and the user's trial line while preserving the original moves and recorded clocks.

Recognized moves receive the Book label, opening name and ECO code. This follows the distinction in [Chess.com's Game Review documentation](https://support.chess.com/en/articles/8584089-how-does-game-review-work), which gives conventional opening moves their own classification. Engine evaluation still runs: scores, losses, achieved depth, original engine grades and review provenance remain available. Book moves are excluded from mistake counts, teaching cards, recurring opening mistakes and new tactical recommendations.

The catalogue also names traps and unsound openings. A verified blunder remains visible as an engine error, including an avoidable forced-mate loss. The current cloud protocol encodes mate scores near 10,000; native engines encode them near 100,000. Recognition does not declare a named opening strategically sound.

Existing device and cloud reviews, analysis history and queue checkpoints are corrected on load and when results arrive. Their completion timestamps, configuration, engine identity and progress remain intact. Correcting book labels does not repeat engine searches or mark a partial review complete. Obsolete derived puzzle recommendations are invalidated. Practice records and original bookmarks are retained; false book-mistake bookmarks are hidden from the teaching list.

To reproduce the index without fetching another catalogue version:

```sh
uv run --with python-chess python scripts/generate-opening-book.py
```

The generator checks the pinned source hashes and validates every PGN move. Swift tests separately check all 8,192 generated edges against the shared chess rules, every ECO code, major openings, long variations, transpositions, repetitions, custom positions, saved reviews, forced mate, checkpoint resumption and opening advice. Native tests cover restored and incoming results; simulator tests cover Book labels, corrected counts, trial variations and existing graph/clock interactions.

The complete catalogue, licence, index, generator and these instructions are included in the GPL client source export. The data retains CC0. The separately operated cloud backend is unchanged.


## Precomputed opening evaluations

`Sources/ChessMeCore/Resources/OpeningEvaluations.json` contains public Stockfish 19
search evidence for 161 exact opening positions and search profiles, using 258,493
bytes. The initial seed covers selected public lines through move 12. It includes
144 quick depth-8 entries and 17 standard depth-21 entries. This is a small seed,
not complete opening coverage. Deeper overnight profiles continue to search.

Regenerate with `swift run OpeningCacheBuilder`. The generator in
`Tools/OpeningCacheBuilder` uses the bundled engine, network and public move
sequences. A timed search is retained only if it reaches the requested depth.
The cache matches the pinned engine version, exact search configuration, full
FEN and ordered position history. Every returned continuation is checked for
legality, and the played move must be among the searched candidates. A miss or
stronger request runs Stockfish normally. Hits report the saved achieved depth
and zero newly searched nodes. Cancellation and game progress remain active.
No account names or imported game archives are included. Update the engine
version when changing the engine, network or native bridge, then regenerate.

## Practical errors and lessons

Swift `ReviewMovePolicy` and Python `review_policy` use the sigmoid published by
[Lichess](https://lichess.org/page/accuracy), with 5, 10 and 15 percentage-point
loss bands from its [grading source](https://github.com/lichess-org/lila/blob/master/modules/tree/src/main/Advice.scala).
These are practical estimates, not calibrated human winning probabilities.
ChessMe additionally requires a centipawn blunder to cross from at least -1.0
to at most -1.0 from the mover's perspective. Large losses that remain winning,
or start clearly losing, are capped at mistake. A newly allowed forced mate is
a blunder if an alternative was at least -7.0; an existing forced mate does not
become a new blunder when its distance shortens. Practice excludes positions
whose best alternative was -7.0 or worse. Through move 12, only blunders become
practice lessons. Recognized non-blunder opening moves retain their book label.
Saved reviews are reclassified without repeating searches or resetting progress.
Older device mate records that lack the best score retain their original grade
because it cannot be reconstructed from a fixed mate-loss penalty. Legacy cloud
records preserve a raw score difference, so their best score can be recovered.
