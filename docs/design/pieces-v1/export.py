#!/usr/bin/env python3
"""Export authored SVGs with CairoSVG; validate their geometry with Pillow."""

from io import BytesIO
from pathlib import Path
import ctypes.util
import json

# Homebrew Cairo can be present but absent from macOS's default lookup paths.
if not ctypes.util.find_library("cairo"):
    for candidate in ("/opt/homebrew/lib/libcairo.2.dylib", "/usr/local/lib/libcairo.2.dylib"):
        if Path(candidate).exists():
            original_find_library = ctypes.util.find_library
            ctypes.util.find_library = lambda name, cairo=candidate: cairo if name == "cairo" else original_find_library(name)
            break

import cairosvg
from PIL import Image

ROOT = Path(__file__).resolve().parent
TOKENS = json.loads((ROOT / "design-tokens.json").read_text())

cairosvg.svg2png(url=str(ROOT / "board-and-set.svg"), write_to=str(ROOT / "board-and-set.png"))
cairosvg.svg2png(url=str(ROOT / "board-and-set.svg"), output_width=420, write_to=str(ROOT / "phone-scale.png"))

measurements = []
alpha_by_piece = {}
for path in sorted((ROOT / "pieces").glob("*.svg")):
    cairosvg.svg2pdf(url=str(path), write_to=str(path.with_suffix(".pdf")))
    png = cairosvg.svg2png(url=str(path), output_width=512, output_height=512)
    path.with_suffix(".png").write_bytes(png)
    image = Image.open(BytesIO(png))
    alpha = image.getchannel("A")
    alpha_by_piece[path.stem] = alpha.tobytes()
    bounds = alpha.point(lambda value: 255 if value >= 128 else 0).getbbox()
    measurements.append({
        "piece": path.stem,
        "widthPercent": round((bounds[2] - bounds[0]) / 512 * 100, 2),
        "heightPercent": round((bounds[3] - bounds[1]) / 512 * 100, 2),
        "boundsAt512": bounds,
    })

for kind, spec in TOKENS["pieces"].items():
    white = next(value for value in measurements if value["piece"] == "white-" + kind)
    black = next(value for value in measurements if value["piece"] == "black-" + kind)
    assert alpha_by_piece["white-" + kind] == alpha_by_piece["black-" + kind], kind
    assert white["boundsAt512"] == black["boundsAt512"], kind
    assert abs(white["heightPercent"] - spec["height"]) < 0.25, white
    assert abs(white["widthPercent"] - spec["width"]) < 0.25, white
    assert abs(white["boundsAt512"][3] / 512 * 100 - 91) < 0.25, white

(ROOT / "geometry-validation.json").write_text(json.dumps(measurements, indent=2) + "\n")
print("Exported 12 transparent PNGs, 12 vector PDFs and board previews.")
print("All six white/black alpha masks match exactly; dimensions and baseline pass.")
