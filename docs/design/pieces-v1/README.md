# Chess Me Staunton v1

An original, simple piece family with warm porcelain white pieces, evergreen
black pieces, and an ivory and sage board. The shallow rounded bases, tapered
bodies, consistent outlines and compact crowns keep the family coherent.

`board-and-set.png` shows the actual reusable assets, including all twelve pieces.
`generated-concept.png` is the earlier visual exploration made with the built-in
image generation tool. The hand-authored vector assets define the final geometry.
The exact generation prompt is saved in `image-generation-prompt.txt`.

## Deliverables

- `pieces/`: twelve original SVGs, transparent 512 × 512 PNGs and vector PDFs.
- `board-and-set.svg` and `board-and-set.png`: matching board and complete set.
- `design-tokens.json`: palette, canvas, stroke, sizing and placement values.
- `generate.py`: editable source for every contour and the vector preview.
- `export.py`: reproducible PNG and PDF export, with silhouette validation.
- `reference-measurements.json`: measured reference proportions and source URLs.
- `geometry-validation.json`: actual raster bounds of each delivered piece.

All twelve files have a square canvas. The visible baseline is at y = 91 on a
100 × 100 canvas. The outline is 2.4 units. Every white and black counterpart
uses exactly the same path geometry. Only the fills and detail colors change.
Do not trim transparent padding or independently scale pieces to fill their
square. Render each complete canvas at the board square's size.

| Piece | Height / square | Width / square | Height / king |
| --- | ---: | ---: | ---: |
| King | 82% | 68% | 100% |
| Queen | 80% | 72% | 97.6% |
| Bishop | 79% | 60% | 96.3% |
| Knight | 78% | 64% | 95.1% |
| Rook | 72% | 60% | 87.8% |
| Pawn | 68% | 52% | 82.9% |

The king has the tallest silhouette. The queen has the broadest crown. Bishops
and knights stay close to the royal pieces in height. Pawns have distinctly
smaller heads and bases, without becoming tiny on a phone board.

## Matching palette

| Element | Color |
| --- | --- |
| Light square | `#E9E5DA` |
| Dark square | `#86A391` |
| White piece | `#FAF7EF` |
| White outline | `#25352E` |
| Black piece | `#293D33` |
| Black outline | `#1D2B24` |
| Black interior detail | `#BAC8B7` |
| Preview background | `#F5F2EA` |

## Reference proportions

Measured on 2026-10-03 from Lichess's Cburnett SVG files in its official
repository and Chess.com's hosted Neo PNG files. These are observed asset
bounds, not a published platform sizing specification. No reference artwork
is bundled into this set.

- Lichess source: <https://github.com/lichess-org/lila/tree/master/public/piece/cburnett>
- Example Chess.com source: <https://images.chesscomfiles.com/chess-themes/pieces/neo/150/wk.png>

For comparability, SVGs were rasterized at 450 × 450. The Neo assets were
measured at their native 150 × 150. Bounds include pixels with alpha at least
128, excluding faint antialiasing. Percentages describe the visible height
relative to the asset's complete square canvas. White pieces are shown below;
measurements for both colors are in the JSON file.

| Piece | Lichess Cburnett | Chess.com Neo | Chess Me |
| --- | ---: | ---: | ---: |
| King | 78.0% | 82.7% | 82% |
| Queen | 78.4% | 80.0% | 80% |
| Bishop | 77.6% | 82.0% | 79% |
| Knight | 74.4% | 80.0% | 78% |
| Rook | 70.0% | 74.0% | 72% |
| Pawn | 71.1% | 68.0% | 68% |

Chess Me deliberately makes both armies the same size and the king slightly
taller than the queen. Its pawn height is close to Neo; its middle pieces are
between the two measured references.

## Native use

The PDFs are suitable as original-color Xcode image assets with vector
representation preserved. Each PDF retains the full square canvas. Use
original rendering rather than template tinting, and size the image to the
square, without an additional per-piece scale factor.

The SVGs are editable master assets, and the PNGs are transparent raster
alternatives. These files are prepared for review before integration into
the app's asset catalog.

Regenerate the SVGs and design tokens with:

```sh
python3 docs/design/pieces-v1/generate.py
```

Export the PNGs and PDFs with CairoSVG and Pillow installed:

```sh
python3 docs/design/pieces-v1/export.py
```

Regenerate those exports after editing the source. Geometry validation checks
that each white and black alpha mask is identical and that the dimensions and
baseline match the specification. `phone-scale.png` renders the board with
approximately 41-pixel squares for a small-size visual check.
