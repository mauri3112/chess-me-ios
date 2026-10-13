# Chess Me piece designs

Three complete original piece families, each with a matching board palette.

| Design | Shape | Board |
| --- | --- | --- |
| Classic | Familiar Staunton silhouettes and shallow rounded plinths | Ivory `#E9E5DA`, sage `#86A391` |
| Slate | Faceted bodies, pointed crowns, octagonal pawn heads and chamfered plinths | Cloud `#E5E9EF`, slate `#8196AE` |
| Clay | Round heads, capsule plinths and a three-pearl queen crown | Linen `#F2E4D2`, clay `#BA9078` |

`two-new-designs.png` compares Slate and Clay. `all-three-designs.png` compares
all three families. Each image shows the exact vector assets on the board and
all twelve pieces in a specimen lineup.

Each set provides twelve SVG masters, vector PDFs and transparent 512 × 512
PNGs. White and black counterparts use the same geometry. All three sets use
the same square canvas, 2.4-unit outlines, baseline and silhouette heights.

| Piece | Height as a percentage of square |
| --- | ---: |
| King | 82% |
| Queen | 80% |
| Bishop | 79% |
| Knight | 78% |
| Rook | 72% |
| Pawn | 68% |

The sizing follows the reference measurements documented in `pieces-v1`.
The new families were drawn directly as vectors. No platform artwork or
chess font glyphs are included.

`piece-sets.json` lists the palettes, asset locations and shared sizing for
future app integration. Use each image's full square canvas; retain the
transparent padding instead of fitting each silhouette independently.

Each family has its own `generate.py` and `export.py` so its assets can be
edited and regenerated independently. The exports check identical white and
black alpha masks, measured height and width, and the shared baseline. The
new variants were also visually inspected with approximately 41-pixel board
squares.

`create-additional-sets.py` holds the original Slate and Clay contours and can
regenerate both new families from the first family's preview layout. Direct
follow-up edits belong in the chosen family's generator; synchronize those
changes into the combined creator before using it again.
