# ChessMe client licensing

Copyright 2026 ChessMe contributors.

The original ChessMe iOS app, its native tests, the shared Swift core and its tests are licensed under GNU General Public License version 3 only, SPDX GPL-3.0-only. This grant covers `ios/`, `Sources/ChessMeCore/`, `Tests/ChessMeCoreTests/`, the client build configuration in `Package.swift`, and the native build and source-export scripts. Full licence text is in `ios/LICENSE` and `Sources/ChessMeCore/LICENSE` and is available inside the app in Settings > Open Source Licenses.

Third-party works retain their original notices and compatible licences. Stockfish 19 is GPL-3.0-or-later; its exact pinned upstream source, native adapter and provenance are in `Vendor/Stockfish/`. Arasan 26 and its neural network are MIT licensed; see `Vendor/Arasan/LICENSE`. Lichess puzzle data is CC0. Exact engine networks are included in the shared core resources.

Corresponding source for each distributed client build is published at https://github.com/mauri3112/chess-me-ios with an immutable build tag. The source export includes all client code, engine sources and adapters, assets, networks, tests, project files and native build scripts. The source link for the exact build is available in the app.

The cloud backend is separately operated and is excluded from this client licence grant and from the public source export. Files under `server/` and server-only deployment, data, runtime credentials and databases retain their existing terms. This change does not publish or relicense the backend.

This software is distributed without warranty. See the GPLv3 text for full terms. Signing keys and account credentials are not needed to build the simulator version and are not included. For a personal device build, select your own Apple development team and a unique bundle identifier in Xcode.
