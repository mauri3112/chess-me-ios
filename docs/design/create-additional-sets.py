#!/usr/bin/env python3
"""Create two self-contained original piece families alongside the first set."""

from pathlib import Path
import json
import pprint
import shutil
import subprocess

ROOT = Path(__file__).resolve().parent
FIRST = ROOT / "pieces-v1"

SLATE = {
    "king": {
        "code": "K", "height": 82, "width": 68, "baseWidth": 64,
        "body": '<path d="M32 77 L38 59 L25 47 L17.2 32 H39 L46.5 42 V27 H39 V20 H46.5 V10.2 H53.5 V20 H61 V27 H53.5 V42 L61 32 H82.8 L75 47 L62 59 L68 77 Z"/>',
        "detail": '<path d="M50 43 V53 M38 59 H62 M34 71 H66"/>',
    },
    "queen": {
        "code": "Q", "height": 80, "width": 72, "baseWidth": 64,
        "body": '<path d="M32 77 L35 64 L29 58 L15.2 26 L33 35 L29 17 L43 34 L50 12.2 L57 34 L71 17 L67 35 L84.8 26 L71 58 L65 64 L68 77 Z"/>',
        "detail": '<path d="M30 59 H70 M35 68 H65"/>',
    },
    "bishop": {
        "code": "B", "height": 79, "width": 60, "baseWidth": 60,
        "body": '<path d="M34 77 L42 63 L31 54 L28 43 L50 13.2 L72 43 L69 54 L58 63 L66 77 Z"/>',
        "detail": '<path d="M55 29 L44 44 M42 63 H58 M38 70 H62"/>',
    },
    "knight": {
        "code": "N", "height": 78, "width": 64, "baseWidth": 64,
        "body": '<path d="M32 77 L44 63 L51 50 L34 57 L20 51 V45 L37 25 L40 14.2 L49 22 L53 16 L64 26 L74 43 L78 60 L75 77 Z"/>',
        "detail": '<path d="M62 34 L69 49 V65 M27 48 L29 47"/><circle cx="40" cy="34" r="1.65" fill="DETAIL" stroke="none"/>',
    },
    "rook": {
        "code": "R", "height": 72, "width": 60, "baseWidth": 60,
        "body": '<path d="M24 20.2 H36 V29 H44 V20.2 H56 V29 H64 V20.2 H76 V38 L70 44 H67 V68 L73 77 H27 L33 68 V44 H30 L24 38 Z"/>',
        "detail": '<path d="M25 38 H75 M33 45 H67 M33 68 H67"/>',
    },
    "pawn": {
        "code": "P", "height": 68, "width": 52, "baseWidth": 52,
        "body": '<path d="M28 79 L42 58 H58 L72 79 Z"/><path d="M45 24.2 H55 L62 31.2 V41.2 L55 48.2 H45 L38 41.2 V31.2 Z"/><path d="M38 48 H62 L65 53 L62 58 H38 L35 53 Z"/>',
        "detail": '<path d="M34 72 H66"/>',
    },
}

CLAY = {
    "king": {
        "code": "K", "height": 82, "width": 68, "baseWidth": 68,
        "body": '<path d="M34 78 C38 71 42 64 41 56 H59 C58 64 62 71 66 78 Z"/><ellipse cx="50" cy="42.5" rx="28" ry="18.5"/><path d="M47 10.2 H53 V17 H59 V23 H53 V29 H47 V23 H41 V17 H47 Z"/>',
        "detail": '<path d="M40 61 H60"/>',
    },
    "queen": {
        "code": "Q", "height": 80, "width": 72, "baseWidth": 64,
        "body": '<path d="M33 78 C34 70 33 64 30 57 L21 31 C31 39 37 49 39 49 C41 49 44 29 50 19 C56 29 59 49 61 49 C63 49 69 39 79 31 L70 57 C67 64 66 70 67 78 Z"/><circle cx="19.2" cy="30" r="4"/><circle cx="50" cy="17.2" r="5"/><circle cx="80.8" cy="30" r="4"/>',
        "detail": '<path d="M32 61 H68 M36 69 H64"/>',
    },
    "bishop": {
        "code": "B", "height": 79, "width": 60, "baseWidth": 60,
        "body": '<path d="M35 78 C36 70 40 67 41 62 C29 57 27 51 31 42 C35 33 44 27 50 25 C56 27 65 33 69 42 C73 51 71 57 59 62 C60 67 64 70 65 78 Z"/><circle cx="50" cy="19.2" r="6"/>',
        "detail": '<path d="M55 34 L45 48 M40 65 H60"/>',
    },
    "knight": {
        "code": "N", "height": 78, "width": 64, "baseWidth": 64,
        "body": '<path d="M33 78 C37 70 43 65 48 57 C43 58 38 61 34 60 L25 56 Q19.2 53 22 47 L37 29 Q38 25 40 25 L41 17 Q41 14.2 44 14.2 Q46 14.2 49 22 L53 19 Q55 17 58 22 C75 31 78 44 76 61 L75 78 Z"/>',
        "detail": '<path d="M60 34 C68 39 69 48 68 59"/><circle cx="40" cy="36" r="1.8" fill="DETAIL" stroke="none"/>',
    },
    "rook": {
        "code": "R", "height": 72, "width": 60, "baseWidth": 60,
        "body": '<path d="M24.2 20.2 H35 Q37 20.2 37 22.2 V30 H44 V22.2 Q44 20.2 46 20.2 H54 Q56 20.2 56 22.2 V30 H63 V22.2 Q63 20.2 65 20.2 H75.8 Q78.8 20.2 78.8 23.2 V38 Q78.8 42 74 44 L67 47 C64 58 65 68 68 78 H32 C35 68 36 58 33 47 L26 44 Q21.2 42 21.2 38 V23.2 Q21.2 20.2 24.2 20.2 Z"/>',
        "detail": '<path d="M30 43 H70 M34 68 H66"/>',
    },
    "pawn": {
        "code": "P", "height": 68, "width": 52, "baseWidth": 52,
        "body": '<path d="M28 80 C34 72 40 66 41 56 H59 C60 66 66 72 72 80 Z"/><circle cx="50" cy="37.7" r="13.5"/><rect x="36" y="50" width="28" height="8" rx="4"/>',
        "detail": '<path d="M37 70 H63"/>',
    },
}

CONFIGS = [
    {
        "directory": "pieces-v2-slate", "name": "Chess Me Slate v1", "shortName": "Slate",
        "baseStyle": "chamfer", "shapes": SLATE,
        "lightName": "Cloud", "darkName": "Slate",
        "description": "Angular crowns, an octagonal pawn head, a faceted bishop and horse, and chamfered bases. The cool slate board matches porcelain and deep navy pieces.",
        "palette": {
            "paper": "#F4F6F9", "lightSquare": "#E5E9EF", "darkSquare": "#8196AE",
            "whitePiece": "#FCFCFD", "whiteOutline": "#263549", "blackPiece": "#27364D",
            "blackOutline": "#192637", "blackDetail": "#B9CBDD",
        },
        "muted": "#69788A",
    },
    {
        "directory": "pieces-v3-clay", "name": "Chess Me Clay v1", "shortName": "Clay",
        "baseStyle": "capsule", "shapes": CLAY,
        "lightName": "Linen", "darkName": "Clay",
        "description": "Rounded capsule bases, a globular king, a three-pearl queen crown, a softer horse profile and a generous round pawn head. The linen and clay board matches cream and espresso pieces.",
        "palette": {
            "paper": "#FBF4EB", "lightSquare": "#F2E4D2", "darkSquare": "#BA9078",
            "whitePiece": "#FFF8EB", "whiteOutline": "#4D3931", "blackPiece": "#503B32",
            "blackOutline": "#352820", "blackDetail": "#DFC4A8",
        },
        "muted": "#8A7264",
    },
]

PIECE_FUNCTION = '''def piece_group(kind, side):
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


'''


def create():
    template = (FIRST / "generate.py").read_text()
    tail = "def svg_document" + template.split("def svg_document", 1)[1]
    for config in CONFIGS:
        target = ROOT / config["directory"]
        target.mkdir(exist_ok=True)
        header = (
            '#!/usr/bin/env python3\n"""Generate the original ' + config["shortName"] + ' family and exact board preview."""\n\n'
            + 'from pathlib import Path\nimport json\nimport xml.etree.ElementTree as ET\n\n'
            + 'ROOT = Path(__file__).resolve().parent\n'
            + 'PALETTE = ' + pprint.pformat(config["palette"], sort_dicts=False) + '\n'
            + 'BASE_STYLE = ' + repr(config["baseStyle"]) + '\n'
            + 'SHAPES = ' + pprint.pformat(config["shapes"], sort_dicts=False, width=115) + '\n\n\n'
        )
        variant_tail = tail.replace('"Chess Me Staunton v1"', json.dumps(config["name"]))
        variant_tail = variant_tail.replace('#69786E', config["muted"])
        labels = (
            f'((390, "lightSquare", "{config["lightName"]} · {config["palette"]["lightSquare"]}"), '
            f'(790, "darkSquare", "{config["darkName"]} · {config["palette"]["darkSquare"]}"))'
        )
        variant_tail = variant_tail.replace('((390, "lightSquare", "Ivory · #E9E5DA"), (790, "darkSquare", "Sage · #86A391"))', labels)
        (target / "generate.py").write_text(header + PIECE_FUNCTION + variant_tail)
        shutil.copyfile(FIRST / "export.py", target / "export.py")
        shutil.copyfile(FIRST / "reference-measurements.json", target / "reference-measurements.json")
        subprocess.run(["python3", str(target / "generate.py")], check=True)
        subprocess.run(["python3", str(target / "export.py")], check=True)


if __name__ == "__main__":
    create()
