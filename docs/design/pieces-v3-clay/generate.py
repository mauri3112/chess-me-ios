#!/usr/bin/env python3
"""Generate the original Clay family and exact board preview."""

from pathlib import Path
import json
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parent
PALETTE = {'paper': '#FBF4EB',
 'lightSquare': '#F2E4D2',
 'darkSquare': '#BA9078',
 'whitePiece': '#FFF8EB',
 'whiteOutline': '#4D3931',
 'blackPiece': '#503B32',
 'blackOutline': '#352820',
 'blackDetail': '#DFC4A8'}
BASE_STYLE = 'capsule'
SHAPES = {'king': {'code': 'K',
          'height': 82,
          'width': 68,
          'baseWidth': 68,
          'body': '<path d="M34 78 C38 71 42 64 41 56 H59 C58 64 62 71 66 78 Z"/><ellipse cx="50" cy="42.5" '
                  'rx="28" ry="18.5"/><path d="M47 10.2 H53 V17 H59 V23 H53 V29 H47 V23 H41 V17 H47 Z"/>',
          'detail': '<path d="M40 61 H60"/>'},
 'queen': {'code': 'Q',
           'height': 80,
           'width': 72,
           'baseWidth': 64,
           'body': '<path d="M33 78 C34 70 33 64 30 57 L21 31 C31 39 37 49 39 49 C41 49 44 29 50 19 C56 29 59 49 '
                   '61 49 C63 49 69 39 79 31 L70 57 C67 64 66 70 67 78 Z"/><circle cx="19.2" cy="30" '
                   'r="4"/><circle cx="50" cy="17.2" r="5"/><circle cx="80.8" cy="30" r="4"/>',
           'detail': '<path d="M32 61 H68 M36 69 H64"/>'},
 'bishop': {'code': 'B',
            'height': 79,
            'width': 60,
            'baseWidth': 60,
            'body': '<path d="M35 78 C36 70 40 67 41 62 C29 57 27 51 31 42 C35 33 44 27 50 25 C56 27 65 33 69 42 '
                    'C73 51 71 57 59 62 C60 67 64 70 65 78 Z"/><circle cx="50" cy="19.2" r="6"/>',
            'detail': '<path d="M55 34 L45 48 M40 65 H60"/>'},
 'knight': {'code': 'N',
            'height': 78,
            'width': 64,
            'baseWidth': 64,
            'body': '<path d="M33 78 C37 70 43 65 48 57 C43 58 38 61 34 60 L25 56 Q19.2 53 22 47 L37 29 Q38 25 40 '
                    '25 L41 17 Q41 14.2 44 14.2 Q46 14.2 49 22 L53 19 Q55 17 58 22 C75 31 78 44 76 61 L75 78 Z"/>',
            'detail': '<path d="M60 34 C68 39 69 48 68 59"/><circle cx="40" cy="36" r="1.8" fill="DETAIL" '
                      'stroke="none"/>'},
 'rook': {'code': 'R',
          'height': 72,
          'width': 60,
          'baseWidth': 60,
          'body': '<path d="M24.2 20.2 H35 Q37 20.2 37 22.2 V30 H44 V22.2 Q44 20.2 46 20.2 H54 Q56 20.2 56 22.2 '
                  'V30 H63 V22.2 Q63 20.2 65 20.2 H75.8 Q78.8 20.2 78.8 23.2 V38 Q78.8 42 74 44 L67 47 C64 58 65 '
                  '68 68 78 H32 C35 68 36 58 33 47 L26 44 Q21.2 42 21.2 38 V23.2 Q21.2 20.2 24.2 20.2 Z"/>',
          'detail': '<path d="M30 43 H70 M34 68 H66"/>'},
 'pawn': {'code': 'P',
          'height': 68,
          'width': 52,
          'baseWidth': 52,
          'body': '<path d="M28 80 C34 72 40 66 41 56 H59 C60 66 66 72 72 80 Z"/><circle cx="50" cy="37.7" '
                  'r="13.5"/><rect x="36" y="50" width="28" height="8" rx="4"/>',
          'detail': '<path d="M37 70 H63"/>'}}


def piece_group(kind, side):
    shape = SHAPES[kind]
    fill = PALETTE["whitePiece" if side == "white" else "blackPiece"]
    outline = PALETTE["whiteOutline" if side == "white" else "blackOutline"]
    detail = PALETTE["whiteOutline" if side == "white" else "blackDetail"]
    left = 50 - shape["baseWidth"] / 2 + 1.2
    right = 100 - left
    if BASE_STYLE == "chamfer":
        base = f'<path d="M {left + 5},77 H {right - 5} L {right},82 V 89.8 H {left} V 82 Z"/>'
        inset = f'<path d="M {left + 6},82 H {right - 6}"/>'
    else:
        base = f'<rect x="{left}" y="77" width="{right - left}" height="12.8" rx="6.4"/>'
        inset = f'<path d="M {left + 8},83 H {right - 8}"/>'
    return (
        f'<g fill="{fill}" stroke="{outline}" stroke-width="2.4" '
        f'stroke-linejoin="round" stroke-linecap="round">'
        + shape["body"] + base
        + f'<g fill="none" stroke="{detail}" stroke-width="2.4">'
        + shape["detail"].replace("DETAIL", detail) + inset
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
        parts.append(f'<text x="{x}" y="1644" text-anchor="middle" font-family="{font}" font-size="19" fill="#8A7264">{SHAPES[kind]["height"]}% of square</text>')
    for x, token, label in ((390, "lightSquare", "Linen · #F2E4D2"), (790, "darkSquare", "Clay · #BA9078")):
        parts.append(f'<rect x="{x}" y="1695" width="30" height="30" rx="5" fill="{PALETTE[token]}" stroke="#87968B" stroke-width="1"/>')
        parts.append(f'<text x="{x + 44}" y="1718" font-family="{font}" font-size="23" fill="{PALETTE["whiteOutline"]}">{label}</text>')
    preview = svg_document(1440, 1780, ''.join(parts))
    ET.fromstring(preview)
    (ROOT / "board-and-set.svg").write_text(preview)
    tokens = {
        "name": "Chess Me Clay v1",
        "canvas": {"width": 100, "height": 100, "baseline": 91, "stroke": 2.4},
        "colors": PALETTE,
        "pieces": {kind: {key: value for key, value in shape.items() if key not in ("body", "detail")} for kind, shape in SHAPES.items()},
        "usage": "Render the entire square canvas at square size. Do not trim transparent padding or fit each silhouette separately.",
    }
    (ROOT / "design-tokens.json").write_text(json.dumps(tokens, indent=2) + '\n')
    print(f"Generated 12 original SVG pieces and board preview in {ROOT}")


if __name__ == "__main__":
    generate()
