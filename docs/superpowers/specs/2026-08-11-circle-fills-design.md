# Circle fills — design

## Problem

The procedural fill system shipped in `feat/canvas-composition` reaches exactly
one renderer. `ProceduralTexture.draw` is called only from
`OrganicBlobShapeRenderer.swift:142`. Circle, snowflake and rays draw through
their own untouched code.

`CanvasElement.spawn` picks a shape from `CanvasShapeType.allowedByUser`, which
by default holds all four selectable shapes. So roughly three of every four new
elements show no fill variety at all, and a user who has not narrowed their
shape set sees essentially the same canvas they saw before.

Circle is the cheapest and highest-yield fix: it is a plain disc, so its contour
needs no deformation profile, and `CircleShapeRenderer` is also what
`.spirograph` renders through — two of the six shape cases for one change.

## Non-goals

- **Snowflake.** Its arms are too thin for hatch or stipple to read, and it
  carries twenty trailing ghosts that must never be textured. Two of five fills
  would work. Revisit after looking at circles on device.
- **Rays.** A ray is a cone of light, not a filled form; hatching inside it means
  nothing. It also renders through a Metal `layerEffect` with a separate CPU port
  for export. Deliberate permanent exception.
- Any change to placement, size, colour or opacity. Those already work for every
  shape — they are decided in `spawn`, before rendering.

## Design

### 1. Circle joins the existing texture system

`CircleShapeRenderer.draw` gains the same two parameters
`OrganicBlobShapeRenderer.draw` already takes:

- `spec: TextureSpec` — which fill and its parameters
- `cache: RenderCache` — so texture geometry is looked up, never regenerated per
  frame

Both call sites in `GenerativeCanvasView` (`.circle` at :446 and `.spirograph`
at :453) pass them, sourced exactly as the organic case does:
`CanvasElement.textureSpec(rank:dayKey:composition:)` and the view's
`renderCache`.

A circle's contour in the texture system's unit space is a uniform array of
`1.0` — a perfect circle. That is the whole reason this is cheap: the hatch
chord maths, the ring nesting and the point-in-contour test all already handle
it as the degenerate case of a lobed profile.

### 2. `.gradient` preserves today's appearance exactly

`CircleShapeRenderer` currently picks between two looks from a seed bit
(`FillStyle.isSolid`): a near-flat disc and a multi-stop hue transition with an
offset centre. That logic moves behind the `.gradient` case of the fill switch
and is otherwise untouched.

This matters because a circle's appearance is regenerated on every render rather
than persisted. Without this, every past day containing circles would repaint.
With it, a day whose texture policy gives circles `.gradient` looks exactly as it
looks today.

The other four fills — `flat`, `rings`, `hatch`, `stipple` — are new behaviour
that only appears where the day's policy calls for them.

### 3. `textureStrength` — one constant, chosen by eye

Circles draw far denser than organic blobs: a single layer at roughly 0.9 alpha
with no blur, against organic's four soft layers at 0.6 with halos. The same
fill therefore reads as a bold graphic mark on a circle and as a ghost on a blob.

Which is correct is a taste question that is faster to settle by looking than by
arguing. So fill opacity on circles is governed by a single named constant,
`CircleShapeRenderer.textureStrength`.

The comparison is two sequential installs of the same commit, not a runtime
toggle and not two branches: build with the low value, install, look; change the
one constant, rebuild, install, look; keep the winner. A debug toggle would be
shipped code written to be deleted.

Low value matches organic's restraint; high value matches the circle's own
density. Once chosen, the value is committed and the constant's comment records
which two were compared and why this one won — so the next person does not
re-litigate it blind.

### 4. `hatchAngle` moves up to the day

`TextureSpec.angle` is currently drawn per element. On circles this would
compound with the element's own rotation (`phaseOffset * 0.3 + userRotation`),
making every circle's hatch point somewhere different — which reads as noise
rather than as composition.

`DayComposition` gains a `hatchAngle`, derived from `dayKey` like everything else
in it. Each element deviates from it by up to 15°, seeded from the element. The
result is hatching that runs one way across a canvas without looking mechanically
ruled.

This applies to organic blobs as well as circles. It is a deliberate change to
already-shipped behaviour: organic hatch angles are currently per element, and
they will become day-anchored. That is the point of the change, not a side
effect.

### 5. Stable seed fallback for legacy elements

Five renderers fall back to `UInt64(bitPattern: Int64(e.id.hashValue))` when an
element has no `shapeSeed` — elements saved before seeds existed. Swift
randomises hash seeds per process, so that fallback already differs on every
launch.

Today it only nudges contour geometry. Once it also drives fill parameters, a
legacy element would change its texture every time the app opens. Replace it with
a stable hash of the UUID's bytes, using the same FNV construction as
`CanvasElement.makeSeed`.

Fix it in both renderers that reach a fill path: `CircleShapeRenderer` and
`OrganicBlobShapeRenderer`. Organic already drives its fills through this
fallback today, so it has the defect now — this is not only a precaution for
circles. The three renderers with no fill path (snowflake, rays, blob) are left
alone; their fallback affects contour only, and touching them is scope creep.

## Data flow

```
dayKey
  └─> DayComposition.forDay
        ├─ archetype, palette, contrastKey        (unchanged)
        ├─ texturePolicy   ──> which fill per rank
        └─ hatchAngle      ──> base hatch direction        [new]

element rank + dayKey + composition
  └─> CanvasElement.textureSpec  ──> TextureSpec

TextureSpec + contour radii + seed
  └─> RenderCache.textureGeometry  ──> cached TextureGeometry

TextureGeometry + textureStrength
  └─> ProceduralTexture.draw  ──> CircleShapeRenderer / OrganicBlobShapeRenderer
```

Circle supplies a uniform-`1.0` radii array where organic supplies its lobed
profile. Everything downstream is shared.

## Testing

- Fill geometry on a circle is reproducible from its seed, and differs between
  seeds.
- `.gradient` on a circle behaves exactly as the current renderer does — the
  regression guard for section 2. A drawn `GraphicsContext` cannot be snapshotted
  from a unit test, so guard the inputs instead: assert `FillStyle(seed:)` still
  returns the same `isSolid` and `opacityMul` for a fixed set of seeds, and
  verify by diff that the two gradient constructions moved unchanged. Anything
  stronger than that belongs to the on-device look, not to the suite.
- Every element of a day hatches within 15° of that day's `hatchAngle`, and two
  different days differ in `hatchAngle`.
- `hatchAngle` is reproducible from `dayKey`.
- The legacy seed fallback returns the same value for the same UUID across
  processes — a golden test, since a `hashValue`-based implementation would fail
  it on almost every run.
- Draw cost at 15 circles for each fill stays inside the frame budget, measured
  the way the organic fills were: contour generation already costs ~11 ms of the
  50 ms available at 20 fps.

## Risks

**Circles are the common case.** Organic elements are roughly a quarter of a
canvas; circles carry `.spirograph` too. A fill that costs 2 ms on organic can
cost more here simply because there are more of them. The draw-cost measurement
is the gate, not an afterthought.

**Rings on small circles may moiré.** Up to eight concentric strokes inside a
disc that may be only a few dozen points across. If it shimmers, the fix is to
scale ring count with rendered radius rather than to drop the fill.

**Two builds cost an extra cycle.** Accepted deliberately: the alternative is
guessing at a value that determines how the whole canvas reads.
