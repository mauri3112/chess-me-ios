#!/usr/bin/env python3
"""Export complete client source without the separately operated backend."""
import argparse
import hashlib
import json
import re
import shutil
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
INCLUDE = [
    "Package.swift", "CLIENT-LICENSE.md", "Sources/ChessMeCore",
    "Tests/ChessMeCoreTests", "Vendor/Stockfish", "Vendor/Arasan", "Vendor/LichessOpenings",
    "ios/LICENSE", "ios/ChessMe", "ios/ChessMeTests", "ios/ChessMeUITests",
    "ios/ChessMe.xcodeproj/project.pbxproj", "ios/ChessMe.xcodeproj/xcshareddata",
    "ios/Configuration", "docs/design", "docs/opening-book.md", "scripts/check-core.sh",
    "scripts/check-ios.sh", "scripts/typecheck-ios.sh", "scripts/export-ios-source.py", "scripts/generate-opening-book.py",
]
FORBIDDEN_PARTS = {".git", ".build", ".tools", "xcuserdata", "private", "secrets", "__pycache__"}
FORBIDDEN_SUFFIXES = {".p8", ".ipa", ".xcuserstate", ".sqlite", ".sqlite3", ".pyc"}


def allowed(path):
    return not (set(path.parts) & FORBIDDEN_PARTS or path.suffix in FORBIDDEN_SUFFIXES
                or path.name in {".env", ".DS_Store", "library.json"}
                or path.name.startswith(".env."))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--destination", type=Path, required=True)
    parser.add_argument("--release-tag", required=True)
    args = parser.parse_args()
    project = (ROOT / "ios/ChessMe.xcodeproj/project.pbxproj").read_text()
    versions = set(re.findall(r"MARKETING_VERSION = ([^;]+);", project))
    builds = set(re.findall(r"CURRENT_PROJECT_VERSION = ([^;]+);", project))
    if len(versions) != 1 or len(builds) != 1:
        raise SystemExit("Every native target must use the same version and build number.")
    version, build = versions.pop(), builds.pop()
    if args.release_tag != f"ios-{version}-build{build}":
        raise SystemExit("The source tag must match the native project version and build.")
    destination = args.destination.resolve()
    if destination.exists():
        raise SystemExit("The export destination must be new; an existing export is never overwritten.")
    destination.mkdir(parents=True)
    for item in INCLUDE:
        source = ROOT / item
        files = sorted(source.rglob("*")) if source.is_dir() else [source]
        for file in files:
            relative = file.relative_to(ROOT)
            if file.is_symlink():
                raise SystemExit(f"Symlinks are not allowed in the source export: {relative}")
            if not file.is_file() or not allowed(relative):
                continue
            target = destination / relative
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(file, target)
    shutil.copy2(ROOT / "ios/LICENSE", destination / "LICENSE")
    (destination / ".gitignore").write_text(".DS_Store\n.build/\n.swiftpm/\nDerivedData/\n*.xcuserstate\nxcuserdata/\n.env\n*.p8\n")
    (destination / "README.md").write_text(f"""# ChessMe iOS source

Corresponding client source for ChessMe {version} build {build}, tag `{args.release_tag}`.
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

The full CC0 Lichess opening catalogue is pinned in Vendor/LichessOpenings.
Its offline position/move index is Sources/ChessMeCore/Resources/OpeningBook.json.
To reproduce the index, run `uv run --with python-chess python
scripts/generate-opening-book.py` (one command on one line). Source checksums
are verified before generation. Book labels preserve engine scores and exclude
opening theory from mistake cards, counts and recommendations. Verified mate
errors in named traps remain visible. Recognition follows each recorded line's
length and supports transpositions without restarting theory after repetitions.

Settings > On-device analysis offers depth targets 24, 28 and 32 on supported
iPhones and iPads, including the base iPhone 15. Memory use adapts to app
headroom. Estimated games per night use recent game lengths and complete
measured reviews from this device. Estimates are capacity planning, not a
promise that iOS grants uninterrupted background time. Reviews report
achieved depth and save completed decisions. User-started work requests continued
processing on iOS 26 or later; overnight jobs run while charging between 22:00
and 07:00 when iOS grants processing time. System interruption, force quitting,
Low Power Mode, thermal state and memory pressure can delay completion.

Games > Add for analysis lets users choose night or immediate device analysis,
select individual games and save the selection. Explicit night selections remain
queued when automatic overnight queuing is disabled. Row icons distinguish
unreviewed games, night jobs, waiting jobs, active progress and completed reviews.
Today lists active and queued games with individual progress and links to their
reviews. Longer queues expand to every game. Games can be filtered by Saved and
Reviewed together; partial reviews remain outside the Reviewed filter.
Recorded results determine win/loss colors; engine evaluations never infer a
winner. Practice browsing and trial branches keep the original game intact.

The public repository publishes source only. The requested binary distribution
is internal TestFlight. There is no warranty. The source-manifest.json file
records SHA-256 for every included file and network.
""")
    files = sorted(file for file in destination.rglob("*") if file.is_file())
    manifest = {"release_tag": args.release_tag, "client_version": version, "client_build": build,
                "client_licence": "GPL-3.0-only", "backend_included": False,
                "files": {str(file.relative_to(destination)): hashlib.sha256(file.read_bytes()).hexdigest() for file in files}}
    (destination / "source-manifest.json").write_text(json.dumps(manifest, indent=2, sort_keys=True) + "\n")
    print(json.dumps({"destination": str(destination), "files": len(files), "backend_included": False}))


if __name__ == "__main__":
    main()
