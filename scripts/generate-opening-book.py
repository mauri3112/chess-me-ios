#!/usr/bin/env python3
"""Build the offline opening index from the complete, pinned CC0 Lichess catalogue.

Run: uv run --with python-chess python scripts/generate-opening-book.py
No network access is needed. Each source file must match provenance.json.
"""
import csv
import hashlib
import json
from pathlib import Path

import chess

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "Vendor/LichessOpenings"
OUTPUT = ROOT / "Sources/ChessMeCore/Resources/OpeningBook.json"


def main():
    provenance = json.loads((SOURCE / "provenance.json").read_text())
    positions = {}
    count, max_ply = 0, 0
    for volume in "abcde":
        path = SOURCE / f"{volume}.tsv"
        if hashlib.sha256(path.read_bytes()).hexdigest() != provenance["files"][path.name]:
            raise SystemExit(f"Source checksum mismatch: {path.name}")
        with path.open() as stream:
            for row in csv.DictReader(stream, delimiter="\t"):
                board = chess.Board()
                ply = 0
                for token in row["pgn"].split():
                    if token.rstrip(".").isdigit():
                        continue
                    key = board.epd(en_passant="legal")
                    move = board.parse_san(token)
                    # A directed position/move edge, not just a named destination.
                    # Its actual catalogue length limits later repeated positions.
                    record = positions.setdefault(key, {"moves": {}})
                    record["moves"][move.uci()] = max(record["moves"].get(move.uci(), 0), ply)
                    board.push(move)
                    ply += 1
                endpoint = positions.setdefault(board.epd(en_passant="legal"), {"moves": {}})
                variation = {"eco": row["eco"], "name": row["name"], "linePlies": ply}
                old = endpoint.get("opening")
                if old is None or (ply, row["eco"], row["name"]) < (old["linePlies"], old["eco"], old["name"]):
                    endpoint["opening"] = variation
                count += 1
                max_ply = max(max_ply, ply)
    result = {"schema": 1, "sourceCommit": provenance["commit"], "openingCount": count,
              "maximumPly": max_ply, "positions": positions}
    OUTPUT.write_text(json.dumps(result, sort_keys=True, separators=(",", ":"), ensure_ascii=False) + "\n")
    print(f"{count} opening lines; {len(positions)} positions; "
          f"{sum(len(p['moves']) for p in positions.values())} book moves; "
          f"longest line {max_ply} plies; {OUTPUT.stat().st_size:,} bytes")


if __name__ == "__main__":
    main()
