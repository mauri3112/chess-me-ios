# Walnut board sounds

Original ChessMe audio, synthesized on 22 October 2026. The editable generator,
recordings and audition player are covered by the client GPLv3 licence.

The set uses damped, inharmonic wood resonances and filtered contact noise for
the piece landing. A capture adds a second, lower impact 14 ms later. Check
adds a short, muted harmonic fifth after the landing. Capture with check has
its own combined cue so it remains one event. Three slightly varied move
recordings and two capture recordings avoid identical taps in long sequences.

All seven assets are mono 48 kHz, 16-bit PCM WAV, with approximately 9.5 dB
of peak headroom, no clipping, tapered endings and no added leading silence.
Move files last 160 ms, captures 194 ms, checks 248 ms and capture-check 252 ms.
Most of each tap's energy ends much sooner. The app preloads the small files
and plays near the end of its 220 ms piece animation. Reduced motion plays
immediately. Settings > Sound > Board sounds is saved on this device.
Ambient audio respects silent mode and mixes with the user's music.

## Reproduce and review

Run `python3 docs/design/sounds/generate.py` from the repository root.
Only the Python standard library is required. It regenerates the seven native
assets, `manifest.json`, `walnut-preview.wav` and `walnut-player.html`.
`player.template.html` is the editable conversation player source.

The WAV review reel plays three moves, two captures, check, capture with check,
then five mixed moves. The player can audition each event or a mixed sequence.
The player uses the actual bundled recordings, with no loudness boost.

## Reference inspection

The following public reference assets were fetched and inspected on
22 October 2026. They were kept outside Git and are not synthesis inputs.
No competitor recording, waveform or sample is included in ChessMe.

- [Chess.com default move](https://images.chesscomfiles.com/chess-themes/sounds/_MP3_/default/move-self.mp3),
  [capture](https://images.chesscomfiles.com/chess-themes/sounds/_MP3_/default/capture.mp3)
  and [check](https://images.chesscomfiles.com/chess-themes/sounds/_MP3_/default/move-check.mp3).
  The available default files have compact contact transients and distinct
  event cues. This is the public default set, not an audit of every selectable
  or account-specific Chess.com theme.
- [Lichess standard set](https://github.com/lichess-org/lila/tree/master/public/sound/standard)
  and [woodland set](https://github.com/lichess-org/lila/tree/master/public/sound/woodland).
  Standard move/capture files have brief, low-pitched impact energy. Its check
  asset links to `../Silence.mp3`. Woodland provides a separate brighter
  check sound. This informed the choice to make ChessMe's check distinct but
  restrained.

Reference comparison used decoded duration, amplitude envelopes and spectra.
Subjective listening on the owner's phone is pending. The new set is wired
into the source app; no TestFlight upload is part of this change.

## Local validation

On 22 October 2026:

- `swift test`: 88 tests passed.
- `uv run --project server pytest server/tests`: 125 passed, 4 skipped because
  the host Stockfish executable is unavailable.
- Unsigned simulator app build passed. The native unit target completed 96
  tests with zero failures, including all seven sound tests and AVFoundation
  decoding of every bundled cue.
- Four focused simulator UI tests passed: game variations, settings/design
  persistence, pending practice moves and review line playback. The complete
  UI suite was not run to completion.
- The conversation player's sequence, individual playback and Stop controls
  worked in the in-app browser at 360 px width with no console errors.
- All WAVs have zero endpoints, no clipping and approximately 9.5 dB peak
  headroom. Embedded audition data exactly matches the seven native files.
- A review subagent checked the change. Its test isolation and audio-context
  lifecycle findings were fixed before the final focused checks.

Physical-device sound quality, silent-switch behavior and mixing with music
still need listening on an iPhone. The code uses Apple's ambient audio
category for silent-switch and music behavior.
