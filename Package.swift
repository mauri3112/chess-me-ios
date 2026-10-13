// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ChessMe",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [.library(name: "ChessMeCore", targets: ["ChessMeCore"])],
    targets: [
        .target(name: "CStockfish", path: "Vendor/Stockfish",
                exclude: ["Copying.txt", "AUTHORS", "README.md", "provenance.json", "src/Makefile", "src/main.cpp", "src/universal"],
                sources: ["bridge.cpp", "src/attacks.cpp", "src/benchmark.cpp", "src/bitboard.cpp", "src/evaluate.cpp",
                          "src/misc.cpp", "src/movegen.cpp", "src/movepick.cpp", "src/position.cpp", "src/search.cpp",
                          "src/thread.cpp", "src/timeman.cpp", "src/tt.cpp", "src/uci.cpp", "src/ucioption.cpp", "src/tune.cpp",
                          "src/syzygy/tbprobe.cpp", "src/nnue/nnue_accumulator.cpp", "src/nnue/nnue_misc.cpp", "src/nnue/network.cpp",
                          "src/nnue/features/half_ka_v2_hm.cpp", "src/nnue/features/full_threats.cpp", "src/nnue/features/pp_3wide.cpp",
                          "src/engine.cpp", "src/score.cpp", "src/memory.cpp"],
                publicHeadersPath: "include",
                cxxSettings: [.headerSearchPath("src"), .define("NDEBUG"),
                              .unsafeFlags(["-include", "StockfishPlatform.h", "-O3"])]),
        .target(
            name: "CArasan", path: "Vendor/Arasan",
            exclude: ["LICENSE", "README.md"],
            sources: ["bridge.cpp", "src/attacks.cpp", "src/bhash.cpp", "src/bitutil.cpp", "src/bitprobe.cpp",
                      "src/board.cpp", "src/boardio.cpp", "src/bookread.cpp", "src/bookwrit.cpp",
                      "src/calctime.cpp", "src/chess.cpp", "src/chessio.cpp", "src/eco.cpp", "src/epdrec.cpp",
                      "src/globals.cpp", "src/hash.cpp", "src/learn.cpp", "src/legal.cpp", "src/material.cpp",
                      "src/movearr.cpp", "src/movegen.cpp", "src/notation.cpp", "src/options.cpp",
                      "src/scoring.cpp", "src/searchc.cpp", "src/search.cpp", "src/see.cpp", "src/stats.cpp",
                      "src/threadc.cpp", "src/threadp.cpp", "src/evaluate.cpp"],
            publicHeadersPath: "include",
            cxxSettings: [.headerSearchPath("src"), .headerSearchPath("src/nnue"),
                          .define("ARASAN_VERSION", to: "26.0"), .define("NETWORK", to: "arasanv8-20260622.nnue"),
                          .define("_64BIT"), .define("USE_INTRINSICS"),
                          .unsafeFlags(["-include", "ArasanPlatform.h", "-O3"]) ]
        ),
        .target(name: "ChessMeCore", dependencies: ["CArasan", "CStockfish"], exclude: ["LICENSE"], resources: [.copy("Resources")]),
        .testTarget(name: "ChessMeCoreTests", dependencies: ["ChessMeCore"], exclude: ["LICENSE"])
    ],
    swiftLanguageModes: [.v5],
    cxxLanguageStandard: .cxx17
)
