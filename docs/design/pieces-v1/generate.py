#!/usr/bin/env python3
"""Generate the original Chess Me piece family and its exact vector preview.

Only the Python standard library is needed. No platform artwork or fonts are
used to draw the pieces. Run from any directory with `python3 generate.py`.
"""

from pathlib import Path
import json
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parent
PALETTE = {
    "paper": "#F5F2EA",
    "lightSquare": "#E9E5DA",
    "darkSquare": "#86A391",
    "whitePiece": "#FAF7EF",
    "whiteOutline": "#25352E",
    "blackPiece": "#293D33",
    "blackOutline": "#1D2B24",
    "blackDetail": "#BAC8B7",
}

# All paths use the same 100 x 100 canvas, 2.4-unit stroke, x = 50 center,
# and y = 91 visible baseline. Top coordinates include the outer stroke.
# Both sides reference these exact same paths.
SHAPES = {
    "king": {
        "code": "K", "height": 82, "width": 68,
        "baseWidth": 64,
        "body": '''<path d="M 32,77 C 31,70 27,65 23,59 C 19.5,55 17.2,50 17.2,46 C 17.2,34 34,30 46.5,42 L 46.5,27 H 39 V 20 H 46.5 V 10.2 H 53.5 V 20 H 61 V 27 H 53.5 V 42 C 66,30 82.8,34 82.8,46 C 82.8,50 80.5,55 77,59 C 73,65 69,70 68,77 Z"/>''',
        "detail": '''<path d="M 50,43 V 65 M 31,72 H 69"/>''',
    },
    "queen": {
        "code": "Q", "height": 80, "width": 72,
        "baseWidth": 64,
        "body": '''<path d="M 33,77 L 30,59 L 17.8,28.5 L 37.5,45 L 30.5,23 L 45,43 L 50,17.4 L 55,43 L 69.5,23 L 62.5,45 L 82.2,28.5 L 70,59 L 67,77 Z"/>
<circle cx="19.2" cy="26" r="4"/>
<circle cx="31" cy="20.2" r="4"/>
<circle cx="50" cy="16.2" r="4"/>
<circle cx="69" cy="20.2" r="4"/>
<circle cx="80.8" cy="26" r="4"/>''',
        "detail": '''<path d="M 32,62 H 68 M 33,72 H 67"/>''',
    },
    "bishop": {
        "code": "B", "height": 79, "width": 60,
        "baseWidth": 60,
        "body": '''<path d="M 34,77 C 35,70 40,68 41,64 C 30,60 27,54 30,45 C 33,36 42,27 50,23 C 58,27 67,36 70,45 C 73,54 70,60 59,64 C 60,68 65,70 66,77 Z"/>
<circle cx="50" cy="18.2" r="5"/>''',
        "detail": '''<path d="M 54.5,32 L 45,48 M 40,64 H 60 M 35,73 H 65"/>''',
    },
    "knight": {
        "code": "N", "height": 78, "width": 64,
        "baseWidth": 64,
        "body": '''<path d="M 32,77 C 35,70 45,63 49,51 C 43,55 39,58 34,58 L 24,54 C 19.2,52 19.2,48 22,44 L 38,25 L 41,15 L 48,23 L 51,14.2 L 58,23 C 75,31 79,48 76,76 L 75,77 Z"/>''',
        "detail": '''<path d="M 60,31 C 72,39 73,54 70,68 M 29,49 L 27,50"/>
<circle cx="40" cy="34" r="1.65" fill="DETAIL" stroke="none"/>''',
    },
    "rook": {
        "code": "R", "height": 72, "width": 60,
        "baseWidth": 60,
        "body": '''<path d="M 22,20.2 H 35 V 30 H 43.5 V 20.2 H 56.5 V 30 H 65 V 20.2 H 78 V 39 L 69,46 L 66,65 L 69,77 H 31 L 34,65 L 31,46 L 22,39 Z"/>''',
        "detail": '''<path d="M 24,39 H 76 M 32,47 H 68 M 33,69 H 67"/>''',
    },
    "pawn": {
        "code": "P", "height": 68, "width": 52,
        "baseWidth": 52,
        "body": '''<path d="M 27,79 C 33,72 40,64 42,53 H 58 C 60,64 67,72 73,79 Z"/>
<circle cx="50" cy="36.2" r="12"/>
<path d="M 39,48 H 61 C 65,48 65,55 61,55 H 39 C 35,55 35,48 39,48 Z"/>''',
        "detail": '''<path d="M 32,75 H 68"/>''',
    },
}


def piece_group(kind, side):
    shape = SHAPES[kind]
    fill = PALETTE["whitePiece" if side == "white" else "blackPiece"]
    outline = PALETTE["whiteOutline" if side == "white" else "blackOutline"]
    detail = PALETTE["whiteOutline" if side == "white" else "blackDetail"]
    # Every base is the same shallow, rounded shape with a piece-appropriate width.
    left = 50 - shape["baseWidth"] / 2 + 1.2
    right = 100 - left
    base = (
        f'<path d="M {left + 7},77 H {right - 7} '
        f'Q {right},77 {right},84 V 89.8 H {left} V 84 '
        f'Q {left},77 {left + 7},77 Z"/>'
    )
    return (
        f'<g fill="{fill}" stroke="{outline}" stroke-width="2.4" '
        f'stroke-linejoin="round" stroke-linecap="round">'
        + shape["body"] + base
        + f'<g fill="none" stroke="{detail}" stroke-width="2.4">'
        + shape["detail"].replace("DETAIL", detail)
        + f'<path d="M {left + 6},81 H {right - 6}"/>'
        + '</g></g>'
    )


def svg_document(width, height, content):
    return (
        f'<svg xmlns="http://www.w3.org/2000/svg" width="{width}" '
        f'height="{height}" viewBox="0 0 {width} {height}">'
        + content + '</svg>\n'
    )


def generate():
    piece_dir = ROOT / "pieces"
    piece_dir.mkdir(parents=True, exist_ok=True)
    for side in ("white", "black"):
        for kind in SHAPES:
            svg = svg_document(100, 100, piece_group(kind, side))
            ET.fromstring(svg)
            (piece_dir / f"{side}-{kind}.svg").write_text(svg)

    parts = [f'<rect width="1440" height="1780" fill="{PALETTE["paper"]}"/>']
    board_x, board_y, square = 160, 56, 140
    ranks = {
        0: ("black", ["rook", "knight", "bishop", "queen", "king", "bishop", "knight", "rook"]),
        1: ("black", ["pawn"] * 8),
        6: ("white", ["pawn"] * 8),
        7: ("white", ["rook", "knight", "bishop", "queen", "king", "bishop", "knight", "rook"]),
    }
    for row in range(8):
        for column in range(8):
            x, y = board_x + column * square, board_y + row * square
            color = PALETTE["lightSquare" if (row + column) % 2 == 0 else "darkSquare"]
            parts.append(f'<rect x="{x}" y="{y}" width="{square}" height="{square}" fill="{color}"/>')
            if row in ranks:
                side, kinds = ranks[row]
                parts.append(f'<g transform="translate({x} {y}) scale(1.4)">{piece_group(kinds[column], side)}</g>')
    parts.append(f'<rect x="{board_x}" y="{board_y}" width="1120" height="1120" fill="none" stroke="{PALETTE["whiteOutline"]}" stroke-width="3"/>')

    font = "-apple-system, BlinkMacSystemFont, Helvetica Neue, Arial, sans-serif"
    order = list(SHAPES)
    for side, y in (("white", 1230), ("black", 1410)):
        for index, kind in enumerate(order):
            x = 178 + index * 184
            parts.append(f'<g transform="translate({x} {y}) scale(1.64)">{piece_group(kind, side)}</g>')
    for index, kind in enumerate(order):
        x = 260 + index * 184
        parts.append(f'<text x="{x}" y="1612" text-anchor="middle" font-family="{font}" font-size="25" fill="{PALETTE["whiteOutline"]}">{kind.title()}</text>')
        parts.append(f'<text x="{x}" y="1644" text-anchor="middle" font-family="{font}" font-size="19" fill="#69786E">{SHAPES[kind]["height"]}% of square</text>')
    for x, token, label in ((390, "lightSquare", "Ivory · #E9E5DA"), (790, "darkSquare", "Sage · #86A391")):
        parts.append(f'<rect x="{x}" y="1695" width="30" height="30" rx="5" fill="{PALETTE[token]}" stroke="#87968B" stroke-width="1"/>')
        parts.append(f'<text x="{x + 44}" y="1718" font-family="{font}" font-size="23" fill="{PALETTE["whiteOutline"]}">{label}</text>')
    preview = svg_document(1440, 1780, ''.join(parts))
    ET.fromstring(preview)
    (ROOT / "board-and-set.svg").write_text(preview)
    tokens = {
        "name": "Chess Me Staunton v1",
        "canvas": {"width": 100, "height": 100, "baseline": 91, "stroke": 2.4},
        "colors": PALETTE,
        "pieces": {kind: {key: value for key, value in shape.items() if key not in ("body", "detail")} for kind, shape in SHAPES.items()},
        "usage": "Render the entire square canvas at square size. Do not trim transparent padding or fit each silhouette separately.",
    }
    (ROOT / "design-tokens.json").write_text(json.dumps(tokens, indent=2) + '\n')
    print(f"Generated 12 original SVG pieces and board preview in {ROOT}")


if __name__ == "__main__":
    generate()
