#!/usr/bin/env python3
"""Generate the original Slate family and exact board preview."""

from pathlib import Path
import json
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parent
PALETTE = {'paper': '#F4F6F9',
 'lightSquare': '#E5E9EF',
 'darkSquare': '#8196AE',
 'whitePiece': '#FCFCFD',
 'whiteOutline': '#263549',
 'blackPiece': '#27364D',
 'blackOutline': '#192637',
 'blackDetail': '#B9CBDD'}
BASE_STYLE = 'chamfer'
SHAPES = {'king': {'code': 'K',
          'height': 82,
          'width': 68,
          'baseWidth': 64,
          'body': '<path d="M32 77 L38 59 L25 47 L17.2 32 H39 L46.5 42 V27 H39 V20 H46.5 V10.2 H53.5 V20 H61 V27 '
                  'H53.5 V42 L61 32 H82.8 L75 47 L62 59 L68 77 Z"/>',
          'detail': '<path d="M50 43 V53 M38 59 H62 M34 71 H66"/>'},
 'queen': {'code': 'Q',
           'height': 80,
           'width': 72,
           'baseWidth': 64,
           'body': '<path d="M32 77 L35 64 L29 58 L15.2 26 L33 35 L29 17 L43 34 L50 12.2 L57 34 L71 17 L67 35 '
                   'L84.8 26 L71 58 L65 64 L68 77 Z"/>',
           'detail': '<path d="M30 59 H70 M35 68 H65"/>'},
 'bishop': {'code': 'B',
            'height': 79,
            'width': 60,
            'baseWidth': 60,
            'body': '<path d="M34 77 L42 63 L31 54 L28 43 L50 13.2 L72 43 L69 54 L58 63 L66 77 Z"/>',
            'detail': '<path d="M55 29 L44 44 M42 63 H58 M38 70 H62"/>'},
 'knight': {'code': 'N',
            'height': 78,
            'width': 64,
            'baseWidth': 64,
            'body': '<path d="M32 77 L44 63 L51 50 L34 57 L20 51 V45 L37 25 L40 14.2 L49 22 L53 16 L64 26 L74 43 '
                    'L78 60 L75 77 Z"/>',
            'detail': '<path d="M62 34 L69 49 V65 M27 48 L29 47"/><circle cx="40" cy="34" r="1.65" fill="DETAIL" '
                      'stroke="none"/>'},
 'rook': {'code': 'R',
          'height': 72,
          'width': 60,
          'baseWidth': 60,
          'body': '<path d="M24 20.2 H36 V29 H44 V20.2 H56 V29 H64 V20.2 H76 V38 L70 44 H67 V68 L73 77 H27 L33 68 '
                  'V44 H30 L24 38 Z"/>',
          'detail': '<path d="M25 38 H75 M33 45 H67 M33 68 H67"/>'},
 'pawn': {'code': 'P',
          'height': 68,
          'width': 52,
          'baseWidth': 52,
          'body': '<path d="M28 79 L42 58 H58 L72 79 Z"/><path d="M45 24.2 H55 L62 31.2 V41.2 L55 48.2 H45 L38 '
                  '41.2 V31.2 Z"/><path d="M38 48 H62 L65 53 L62 58 H38 L35 53 Z"/>',
          'detail': '<path d="M34 72 H66"/>'}}


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
        parts.append(f'<text x="{x}" y="1644" text-anchor="middle" font-family="{font}" font-size="19" fill="#69788A">{SHAPES[kind]["height"]}% of square</text>')
    for x, token, label in ((390, "lightSquare", "Cloud · #E5E9EF"), (790, "darkSquare", "Slate · #8196AE")):
        parts.append(f'<rect x="{x}" y="1695" width="30" height="30" rx="5" fill="{PALETTE[token]}" stroke="#87968B" stroke-width="1"/>')
        parts.append(f'<text x="{x + 44}" y="1718" font-family="{font}" font-size="23" fill="{PALETTE["whiteOutline"]}">{label}</text>')
    preview = svg_document(1440, 1780, ''.join(parts))
    ET.fromstring(preview)
    (ROOT / "board-and-set.svg").write_text(preview)
    tokens = {
        "name": "Chess Me Slate v1",
        "canvas": {"width": 100, "height": 100, "baseline": 91, "stroke": 2.4},
        "colors": PALETTE,
        "pieces": {kind: {key: value for key, value in shape.items() if key not in ("body", "detail")} for kind, shape in SHAPES.items()},
        "usage": "Render the entire square canvas at square size. Do not trim transparent padding or fit each silhouette separately.",
    }
    (ROOT / "design-tokens.json").write_text(json.dumps(tokens, indent=2) + '\n')
    print(f"Generated 12 original SVG pieces and board preview in {ROOT}")


if __name__ == "__main__":
    generate()
