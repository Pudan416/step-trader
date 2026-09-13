# Task 1B Attempt 5 — Critic B Blind Lock

Phase: blind A/B observation lock, before identity reveal. This document contains no candidate/baseline identity inference and no final PASS/ITERATE verdict.

## Inspection record

- Inspected the corrected allowlisted design specification, Task 1 visual directive, visible seed manifest, packet manifest/list/checksums, both hash-identical copies of `random-gradient-circle.html`, and every image on the Day Objects reference board.
- Inspected all nine blind conditions and all 36 PNGs at native detail: A/B full `393 × 852` and A/B tile `393 × 393`, with the tile defined as the exact full-frame crop at `x=0, y=229`.
- Judged only material presentation. Layout 11 composition and its frozen seeds were not scored.

## Locked reference reading

- The decisive outline identity is an empty center bounded by one to three thin, continuous, displaced circular strokes. The HTML source explicitly uses `fill: none`, related gradient strokes, small spacing and wobble, and `0.6...1` stroke opacity. Softness may modulate the stroke but must not create a broad filled body.
- Outline must stay visibly different from counterform: a thin contour is not a thick body with a cut-out center. A concentric glossy tube, target, bullseye, ripple disc, or secondary sharp inner ring is therefore a material failure even if its center is technically transparent.
- The broader reference board asks for shifted, smoothly overlapping radial color influence, readable transparency, atmospheric depth, and soft continuity without angular seams, isolated stickers, or noisy bands.

## Per-condition A/B observations

### c1-light — blind preference: A

- **A full/tile:** Unmistakably open, thin yellow-green contours. Centers stay fully empty, the contour path remains continuous through both native views, and there is no sharp inner halo circle. The one-color ownership reads consistently, with restrained brightness variation rather than extra color blobs. The very small top actor and pale upper-right actor are faint, but the family still reads as outline rather than counterform. No torus, ripple, target, sticker, or angular seam is visible.
- **B full/tile:** Large actors become broad glossy toruses or ripple-filled discs. The upper-right actor is a bullseye/target with a tiny central dot or hole and numerous concentric bands; the left and lower-right actors are inflated tubes with hard inner rims. Thin colored edge chatter and sharp inner rings compound the wrong material identity. Greater volume and visibility do not compensate for the loss of outline identity.

### c1-dark — blind preference: A

- **A full/tile:** Open centers and single continuous olive/yellow-green contours survive the dark background and exact tile crop. There is no erroneous inner halo circle or filled body. Transparency and slight softness provide a modest depth hierarchy, but contrast is low: the top, upper-right, and small far actors approach disappearance at native scale.
- **B full/tile:** More visible, but again dominated by inflated toruses, a large ripple/target disc, hard inner rims, central dark dots/holes, and concentric banding. It reads as luminous rubber tubing and cut-out bodies, not thin outline. The repeated inner rings are especially conspicuous on dark.

### c1-lowContrast — blind preference: B

- **A full/tile:** Broad yellow-green toruses and a filled target disc dominate. Magenta/yellow fringe, granular edge ringing, a sharp inner halo, and concentric ripples make the actors read as noisy counterforms or targets. Several centers are open only because a thick body has been cut away.
- **B full/tile:** Thin open yellow-green contours remain continuous and clean across the gray field and tile crop. One-color ownership is coherent, the center remains genuinely empty, and no sharp secondary inner circle is present. Some upper and far actors are faint, but there are no torus, ripple, sticker, or angular-seam artifacts.

### c2-light — blind preference: A

- **A full/tile:** Clean open contours with smoothly shifting mint/cyan, green, and chartreuse emphasis along the stroke. The two-color construction is more legible than c1 without becoming banded or angular. Centers are empty, edges are continuous, the large cropped contour remains thin relative to its radius, and no secondary inner ring appears. Pale far actors are subdued but still structurally outline.
- **B full/tile:** Thick glossy rings and filled ripple discs replace the contour family. The upper-right actor becomes a bright green target with a central dot, while the large left and lower-right actors carry hard inner rims, broad tube bodies, edge chatter, and layered concentric bands.

### c2-dark — blind preference: B

- **A full/tile:** High-chroma green/blue/yellow depth is present, but almost entirely inside broad toruses, ripple discs, and sharp-rimmed cut-outs. The upper-right disc contains a dark circular inner ring and target center; the lower-right actor is an inflated tube. This is materially closer to counterform/halo than outline.
- **B full/tile:** Thin, open, continuous contours with no inner halo circle or filled body. Subtle green-to-yellow/teal variation is visible on some arcs, but the intended two-color ownership is weaker on dark than on light or lowContrast; several far contours are nearly lost. The structural identity nevertheless remains clean in both full and tile.

### c2-lowContrast — blind preference: A

- **A full/tile:** The strongest native-scale two-color outline evidence in the packet: cyan/green and chartreuse regions shift smoothly along thin continuous contours, without hard ownership boundaries. Centers remain open, the tile retains the same edge continuity, and no sharp inner circle, target, ripple, sticker, or angular seam appears. Faint upper actors remain the main visibility limitation.
- **B full/tile:** Large actors are broad multicolored toruses or a filled target/ripple disc, with hard inner rims, granular fringe, central dot/hole motifs, and many concentric bands. The additional color and depth are trapped in the wrong thick-body topology.

### c3-light — blind preference: B

- **A full/tile:** Visibly multicolored, but the green/blue/yellow fields occupy thick glossy toruses and a filled ripple disc. The upper-right actor has a bullseye center and circular banding; the big rings carry hard inner rims and edge chatter. A sweeping sector in the ripple field also reads less like broad smooth radial ownership than a shaped internal seam.
- **B full/tile:** Open, thin, continuous periwinkle/blue contours with gentle tonal change and no erroneous sharp inner halo. The actors remain unmistakably outline in both views, and there are no torus/ripple/target/sticker/angular artifacts. However, the requested three-color ownership is not clearly proven at native scale: one cool hue dominates and any second/third contribution is extremely subtle.

### c3-dark — blind preference: A

- **A full/tile:** Structurally clean outline: fully open centers, continuous thin contours, no filled body, and no sharp inner circle. It is also the weakest preferred frame for color-count and visibility: most actors collapse to olive/yellow-green on dark, the expected three-color richness is not clearly readable, and the top/right/far actors are close to disappearing.
- **B full/tile:** Stronger green/blue/yellow color and volume, but expressed as thick toruses and a large filled ripple/target disc. The upper-right actor has a dark inner circle and center dot, and the large rings have hard inner rims, concentric banding, and noisy edge fringe. It remains the wrong family despite better chroma.

### c3-lowContrast — blind preference: A

- **A full/tile:** Thin open contours survive with smooth blue-to-yellow/green changes and no hard seams. The center is genuinely empty, contour continuity is stable in the tile, and no sharp inner halo, torus, ripple, or target appears. Two color regions are clear, but a distinct third contribution is not reliably legible; several upper actors are also faint.
- **B full/tile:** Vivid multicolor is present, but inside broad toruses and a filled ripple disc with purple target center, circular banding, hard inner rims, and edge chatter. The upper-right field contains a conspicuous sweeping color sector. It reads as a counterform/target system rather than an outline family.

## Overall blind observation and preference

The open-outline alternative is decisively preferred in every condition:

- **Prefer A:** c1-light, c1-dark, c2-light, c2-lowContrast, c3-dark, c3-lowContrast.
- **Prefer B:** c1-lowContrast, c2-dark, c3-light.

Across those nine preferred full/tile pairs, the principal topology problem is removed: centers are unmistakably open, contours are thin and continuous, the erroneous sharp inner halo circle is absent, and no preferred frame reads as a torus, ripple disc, bullseye, sticker, or angularly segmented body. Full-to-tile behavior is stable and does not expose new breaks.

The remaining blind concern is a tradeoff rather than a topology regression. The preferred material often becomes very faint and optically flat, especially on dark and in the far/top actors; depth is conveyed mostly by opacity/softness rather than rich stroke material. One-color ownership is coherent and two-color ownership is strongest on light/lowContrast, but three-color ownership is not convincingly visible at native scale—particularly c3-light and c3-dark, and only partially c3-lowContrast. Thus outline-versus-counterform family distinction is restored, while c1/c2/c3 color-count distinction and dark-background readability remain uneven.

Blind preference is locked to the per-condition selections above. No candidate/baseline identity claim and no final gate verdict is made in this phase.
