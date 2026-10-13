# Bundled Arasan 26.0

Engine source is pinned to upstream commit `d8613aca11b3db15ce7f5c6d54da4dc4b31f63f8` from https://github.com/jdart1/arasan-chess.
The unmodified upstream `src` files are compiled as a static Swift Package target. The desktop entry point, protocol loop, tools and Syzygy integration are excluded from the build. No subprocess, executable download, opening book or external tablebase is used.

`bridge.cpp` and `include` are ChessMe's integration. The bridge serializes access to Arasan's globals, selects ARM NEON on Apple Silicon, loads the bundled network, bounds search and forwards completed principal variations to Swift. It avoids the desktop initialization routine that changes process stack limits and may call `exit`.

The bundled `arasanv8-20260622.nnue` is in `Sources/ChessMeCore/Resources`, is 25,024,576 bytes and has SHA-256 `b42f9e13a37debb4af425d2ca74b5edff1d8034a616806bccdb67b79530201ac`.
The upstream MIT license explicitly includes source and network. The full license is retained here and in the package resources for the app's Open Source Licenses screen.
