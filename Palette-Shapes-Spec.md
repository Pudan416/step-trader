# Palette shapes — design

Replaces the liquid metaball palette with a structured field of the actual
shapes a happening will become.

Status: design approved 2026-08-10. Implementation lands on its own branch
**after** PR #13 merges; this document is written against the code as of
`cefdcd0`.

## Why

The current palette draws one implicit surface, not ten objects.
`HappeningLiquidCanvas` sums ten point fields and asks
`ProceduralShapeGenerator.metaballPath` for a single iso-contour, then fills it
with ten blurred radial gradients clipped to that contour. A metaball merges
whatever is close, so there are no per-item silhouettes to see — only the
outline of a merged mass. The two-column, five-row placement underneath is real
but invisible: rows are stepped closer than a diameter and overlap outright,
and the summed field bridges the columns.

This was a deliberate choice earlier in the happenings work — the cluster was
falling apart into separate spots at 1–3.6pt gaps, so the columns were pulled
tighter to make it read as one mass. It succeeded, and the result is the thing
being replaced: an amorphous shape that tells you nothing about what you are
choosing.

Structure cannot be recovered by tuning it. While the picture is a level set,
loosening the sources gives a thinner-necked blob, not a grid. It becomes
structured only by drawing one shape per item — which is what this design does.

## The promise

**A tile shows the figure that will land on the canvas.** Not an icon standing
for it, not an approximation — the same renderer, the same shape type, the same
seed, the same colour.

That promise is what forces the architecture. Today `CanvasElement.spawn` rolls
the shape itself: it picks a type from `allowedShapeTypes`, derives a seed and
takes the colour it is handed. The palette cannot preview a decision that is
made after the tap, so the roll moves one step earlier — into the palette — and
`spawn` accepts the result instead of producing it.

Size, opacity, drift and pulse stay random inside `spawn`. The promise covers
the **figure** — type, seed, colour — not how large it lands or how it moves.
Tiles render at a uniform size so the grid stays even.

## The assignment

Each happening carries an assignment for the current custom day:

```
shapeType: CanvasShapeType   // drawn from CanvasShapeType.allowedByUser
colorHex:  String            // drawn from CanvasColorPalette.paletteHex
```

The seed is **not** stored. `CanvasElement.makeSeed(optionId:dayKey:index:)`
already derives it deterministically from the happening id, the day key and the
element index, so the palette computes the same value the canvas will use. The
only addition is a per-day shuffle nonce mixed into that derivation, so shaking
produces a different silhouette from the same inputs.

Persisted in the app group beside the palette selection:

| key | value |
|---|---|
| `happeningShapeAssignments` | `[happeningId: {shapeType, colorHex}]` |
| `happeningShapeAssignmentsDayKey` | the day the map belongs to |
| `happeningShapeShuffleNonce` | `UInt64`, re-rolled on shake |

A read against a different `dayKey` discards the map and rolls a fresh one, the
same way the palette selection re-ranks on rollover. Nothing goes to Supabase:
the colour already reaches the server on `OptionEntry.colorHex`, and the shape
and seed reach it inside the canvas JSON. No schema change, no migration.

**Colours are distinct within a set.** Ten tiles draw ten different hexes from
the 29 available. Shapes are not: there are four selectable types, so with ten
tiles a type repeats two or three times by necessity. Distinctness comes from
the seed, which gives every tile its own silhouette even within a type.

**Degenerate case, stated rather than hidden.** A user who has narrowed
`allowedCanvasShapes` to a single type gets ten tiles of that type, told apart
only by seed and colour. That is the setting working as configured, not a
defect. The palette honours `allowedByUser` — ignoring it would make the
setting a lie.

## The screen

A full-screen overlay over the canvas, `.ultraThinMaterial`, so the gradient
stays visible and blurred behind it.

Ten tiles in four staggered rows — **3, 2, 3, 2** — the rows of two offset into
the gaps of the rows of three. Each tile is the rendered figure with its label
below it. An eleventh affordance opens free-text creation.

The dock keeps its three buttons, its style, and the height it sits at today.
A fourth control re-rolls the set (see Shake).

Picking a tile spawns the element and removes the tile; the remaining tiles
re-flow into the 3-2-3-2 arrangement for their new count. When the field
empties, the existing completion state stands in.

### Rendering a tile

Tiles reuse the canvas renderers directly — `CircleShapeRenderer.draw`,
`SnowflakeShapeRenderer.draw`, `OrganicBlobShapeRenderer.draw`,
`RayShapeRenderer.draw`. Each takes a `CanvasElement`, a `GraphicsContext` and a
`size`, and computes position and radius relative to that size, so they work at
tile scale. The tile builds a throwaway element carrying the assignment, a
centred `basePosition` and a fixed size, and draws it into a `Canvas`.

Using the real renderer is not an optimisation, it is the mechanism: a
hand-drawn preview would drift from the canvas the first time a renderer
changed.

**Rays** are Metal spotlight cones anchored to the canvas edges — composed for a
tall screen, not a small square. The tile renders them into an offscreen canvas
that keeps the canvas aspect ratio, then scales that result down to fit,
preserving proportions, the way the app icon does. The cones stay recognisable
instead of degrading into a smear.

## Shake

Shaking re-rolls **shape type, seed and colour** for every tile still in the
field. Tiles already picked are untouched: their elements are on the canvas with
`frozenShapeType` set, and that freezing is what makes a saved day render the
same tomorrow as today. History is never rewritten.

Mechanically: `motionEnded(.motionShake)`, re-roll the assignment map, bump the
shuffle nonce, persist, animate the tiles into their new figures.

Shake alone is not enough. It is undiscoverable, and unavailable to anyone who
cannot shake a phone, so the dock carries a visible re-roll control that does
the same thing. Under Reduce Motion the set changes without the transition.

## What goes

| file | lines | fate |
|---|---|---|
| `HappeningLiquidField.swift` | 1193 | deleted |
| `HappeningLiquidLayout.swift` | 420 | deleted |
| `HappeningLiquidLayoutTests.swift` | 1089 | deleted |
| `HappeningPaletteView.swift` | 459 | rewritten around the new field |
| `HappeningChooserView.swift` | 218 | unchanged |
| `HappeningFreeTextField.swift` | 221 | unchanged |

About 2700 lines out, and the chrome/dock layout logic worth keeping is lifted
out of `HappeningPaletteView` before the rest is rewritten.

## Acceptance

- A tile's figure is the figure that lands on the canvas — same type, same
  seed, same colour.
- The assignment is stable across palette opens within one custom day.
- It re-rolls on its own when `dayKey` rolls over at the user's day end.
- Shake re-rolls type, seed and colour for unpicked tiles only.
- Elements already on the canvas are unchanged by shake, and past days are
  unchanged by anything here.
- Ten tiles carry ten distinct colours.
- Tile shape types are drawn only from `CanvasShapeType.allowedByUser`; with one
  allowed type, all ten tiles use it and still differ by seed and colour.
- Rays tiles keep the canvas aspect ratio and read as cones.
- The dock keeps its three buttons at the height the canvas `+` sits at, plus
  the re-roll control.
- The re-roll control does exactly what shake does, and is reachable without
  shaking.
- Picking removes the tile and the rest re-flow to 3-2-3-2 for their count.

## Risks

**Renderers at tile scale are unproven.** They were written for one full-screen
canvas, and nothing has drawn them into a 100pt box before. Rays is the known
hard case and has an answer; the other three are expected to be fine and are not
yet demonstrated. Prove this first — if a renderer cannot be driven at tile
scale, the promise is unreachable and the design needs revisiting before the
rest is built.

**Cost of ten live canvases.** Ten `Canvas` views, some animating, over a
blurred material. Watch it on the oldest supported device before adding motion.

**`spawn`'s signature is load-bearing.** It has one call site today
(`GalleryView.swift:1126`), so moving the roll out is contained — but the
defaults must keep behaving as they do now, because the migration guard test
`testLegacyCanvasDecodesToUnchangedFrozenShapeTypes` asserts old canvases decode
to unchanged shapes.
