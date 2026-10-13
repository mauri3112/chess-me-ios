# Chess Me Clay

An original rounded family with capsule plinths, a globular king, a
three-pearl queen crown, a softer horse profile and generous round pawn
heads. Cream and espresso pieces sit on a linen and clay board.

- Light square: `#F2E4D2`.
- Dark square: `#BA9078`.
- `pieces/`: twelve SVGs, twelve vector PDFs and twelve transparent PNGs.
- `board-and-set.png`: the exact assets on their matching board.
- `phone-scale.png`: a visual check with approximately 41-pixel squares.
- `design-tokens.json`: all colors, sizing and placement values.
- `geometry-validation.json`: measured export bounds.

Every canvas is 100 × 100. Heights are 82, 80, 79, 78, 72 and 68 percent of
the square for king, queen, bishop, knight, rook and pawn. The visible
baseline is y = 91, and outlines are 2.4 units. White and black alpha masks
match exactly. This retains the first family's reference sizing while
changing the contours.

Keep the full square canvas and transparent padding when integrating.
Use the PDFs as original-color image assets with vector representation
preserved, or use the PNGs as raster alternatives.

Regenerate independently:

```sh
python3 generate.py
python3 export.py
```

The generator uses the Python standard library. The export script requires
CairoSVG and Pillow. The new artwork was authored directly as editable
vectors. `reference-measurements.json` preserves the sizing study from the
first family; no reference artwork is included.
