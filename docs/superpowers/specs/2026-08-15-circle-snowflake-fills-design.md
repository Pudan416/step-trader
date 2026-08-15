# Circle and Snowflake Procedural Fills — Design

## Problem

The procedural fill system on `feat/canvas-composition` reaches only
`OrganicBlobShapeRenderer`. The four selectable families are circle,
snowflake, rays, and organic blob, so most elements still use their former
renderer and the new day-level texture policy is often invisible.

This delivery extends the existing five procedural fills to circle and the
main snowflake body. It deliberately does not add new shape families. New
families will be designed separately after this delivery is evaluated on a
device.

## Goals

- Apply `flat`, `gradient`, `rings`, `hatch`, and `stipple` to circles and the
  current snowflake body through the existing `ProceduralTexture` engine.
- Apply the change to both new and previously saved canvases without changing
  persisted models or JSON.
- Keep live rendering, thumbnails, wallpaper export, and history rendering
  deterministic and visually consistent.
- Preserve the current glow, motion, outlines, and snowflake trail ghosts.
- Keep a 15-element canvas at or above 18 fps on the target device class.

## Non-goals

- New shape families. Ribbon/arc and shard/cell families are a later project.
- Procedural fills for rays. Rays are directional light rendered by a Metal
  effect with a separate CPU export path; surface hatching is not part of that
  visual grammar.
- Procedural fills for legacy `.blob` or `.spirograph`. `.spirograph` currently
  delegates to the circle renderer, but it remains hidden and is not an
  acceptance target.
- Texturing snowflake trail ghosts. Twenty textured ghosts would multiply both
  visual noise and geometry cost.
- Changes to placement, size, palette, opacity, blend mode, or persistence.
- Metal-based texture generation. The existing CPU/vector path is required for
  deterministic thumbnails and export.

## Chosen Approach

Use one texture engine with shape-specific radial adapters.

`ProceduralTexture` already represents a star-shaped contour as radii sampled
around a centre. A circle supplies a constant profile. The snowflake generator
already creates exactly such a radial profile internally, but currently throws
it away when it returns `RectMorphFrame`. Expose that profile directly rather
than reconstructing geometry from `Path` commands.

This keeps generation, caching, drawing, determinism, and export behaviour in
one place. Separate fill implementations inside each renderer are rejected
because they would immediately create three versions of rings, hatch, and
stipple. A universal raster or Metal shader is rejected because it would split
the live and export paths.

## Shared Geometry Contract

Introduce a render-only value type:

```swift
struct RadialTextureProfile: Hashable {
    let center: CGPoint
    let outerRadius: Double
    let radii: [Double]       // normalised against outerRadius
}
```

Invariants:

- `radii.count >= 3`.
- Every radius is finite and strictly positive.
- `radii.max()` is `1.0` within floating-point tolerance.
- Samples run clockwise in screen coordinates from angle zero.
- The profile centre is the same centre used to construct the corresponding
  contour `Path`.
- The profile is render-only and never `Codable`.

`ProceduralShapeGenerator.RectMorphFrame` gains `textureProfile`. The private
snowflake morph shape remains private; `rectMorphFrame` normalises its lerped
radii and exposes only the stable rendering contract.

The snowflake's internal rotation must be reflected in the returned samples.
The profile is resampled in world-angle order after rotation, so callers do not
need a snowflake-specific transform and rings align with the visible arms.
Linear interpolation between adjacent radial samples is required; integer
array shifting would make the texture jump while the snowflake rotates.

## Circle Rendering

`CircleShapeRenderer.draw` gains:

- `spec: TextureSpec`
- `cache: RenderCache`

The circle adapter supplies 48 radii equal to `1.0`, centred on the animated
circle centre, with `outerRadius` equal to the rendered radius.

Only the visible body fill changes. Existing element transform, blend mode,
colour selection, pulse, and compositing remain unchanged.

The `.gradient` case preserves the current circle renderer exactly, including
its seeded solid/gradient choice, offset centre, opacity multiplier, and colour
stops. This is the compatibility case: days whose texture policy chooses
gradient should not repaint circles merely because the routing changed.

The other four cases use `ProceduralTexture.draw`. A named
`textureStrength` constant controls their opacity relative to the circle's
dense existing body. It is calibrated on device by comparing two sequential
builds; no temporary runtime toggle ships.

## Snowflake Rendering

`SnowflakeShapeRenderer.draw` gains:

- `spec: TextureSpec`

It already receives `renderCache`.

The twenty trail ghosts remain byte-for-byte on their current conic-gradient
fill and stroke path. They neither request texture geometry nor enter the
texture cache.

For the current body only:

1. Generate the existing `RectMorphFrame`.
2. Use its `textureProfile` for cached procedural geometry.
3. Draw the selected fill clipped to `currentFrame.path`.
4. Draw the existing conic-gradient outline unchanged on top.

`.gradient` preserves the current conic body fill exactly. `flat`, `rings`,
`hatch`, and `stipple` use `ProceduralTexture` with a snowflake-specific
`textureStrength` because thin arms need a different opacity balance from
circles and organic blobs.

The outline is always retained. It protects readability for sparse hatch and
stipple fills and preserves the current snowflake identity.

## Texture Orientation

`DayComposition` gains a deterministic `hatchAngle`, derived from `dayKey`.
`CanvasElement.textureSpec` uses it as the base and adds at most ±15 degrees
of stable, element-seeded deviation.

This applies to organic blobs, circles, and snowflakes. Hatching therefore
shares a direction across a daily composition instead of becoming unrelated
per-element noise. Existing persisted data is unaffected because the angle is
derived at render time.

Circle element rotation continues to rotate the whole rendered layer, so the
effective hatch angle remains day-coherent plus the circle's intentional
transform. Snowflake radial samples are returned in world-angle order, so no
additional snowflake rotation is applied by the texture engine.

## Cache Contract

`RenderCache.TextureCacheKey` gains a geometry-family discriminator:

```swift
enum TextureGeometryFamily: UInt8, Hashable {
    case organicBlob
    case circle
    case snowflake
}
```

The cache key continues to include seed, quantised `TextureSpec`, quantised
complexity/profile identity, and time bucket. Family discrimination prevents a
circle and snowflake with matching seed/spec values from receiving geometry
created for another radial profile.

For snowflakes, the profile changes with the existing morph. Its cache identity
uses the same 1.5-second staggered time bucket already used by organic texture
geometry. Generation uses the frame corresponding to the bucket's canonical
time, not an arbitrary render instant, so all calls inside one bucket agree on
the geometry key and value. The contour clip remains the current frame path;
sparse texture geometry can drift slightly within it, but cannot spill out.

No texture generation occurs inside the twenty-ghost loop.

## Legacy Determinism

Circle, organic blob, and snowflake currently fall back to `e.id.hashValue`
when `shapeSeed` is absent. Swift randomises `hashValue` per process, so legacy
elements can change between launches.

Add one stable UUID-byte FNV helper to `CanvasElement` and use it in all three
renderers that now reach procedural fills. This is required for identical live,
thumbnail, and export output. Other renderers are outside this delivery.

## Data Flow

```text
dayKey
  -> DayComposition.forDay
       -> texturePolicy
       -> hatchAngle

rank + dayKey + composition
  -> CanvasElement.textureSpec

shape renderer
  -> RadialTextureProfile + contour Path
  -> RenderCache.textureGeometry(family, seed, spec, profile, time)
  -> ProceduralTexture.draw
  -> existing outline / glow / trail compositing
```

No value in this path is persisted.

## Testing

Unit tests must cover:

- Circle profile contains 48 unit radii and is seed-independent.
- Snowflake profile is finite, positive, normalised, deterministic, and aligned
  with the visible contour at representative angles.
- Rotating/morphing a snowflake changes the profile continuously rather than in
  integer-sample jumps.
- All five texture kinds generate valid geometry for circle and snowflake
  profiles.
- Cache keys separate organic, circle, and snowflake families.
- Repeated calls in one bucket hit the cache; a new snowflake bucket misses.
- No texture cache entry is created while rendering only trail ghosts.
- `hatchAngle` is stable for a day, differs across a representative day set,
  and every element stays within ±15 degrees.
- Stable UUID fallback has golden outputs and contains no `hashValue` path in
  the three participating renderers.
- Existing circle gradient style inputs remain unchanged for fixed seeds.

Performance and visual gates:

- Measure 15 circles for each fill kind.
- Measure 15 snowflakes including twenty existing ghosts each, for every fill
  kind on the main body.
- Worst measured frame remains below 55 ms in Debug on the iPhone 17 simulator
  and at or above 18 fps on the physical target device.
- Compare historical and live render/export for the same day and rank.
- Verify snowflake trails look unchanged and no texture appears in ghosts.
- Calibrate separate circle and snowflake `textureStrength` constants on device.
- Inspect small forms for ring moiré, hatch crowding, and stipple disappearance.

## Risks and Mitigations

**Snowflake arms are narrow.** Hatch and stipple may disappear at small sizes.
Keep the outline, clip all fields, and scale density down with rendered radius
only if device inspection proves necessary.

**Rings may shimmer.** Up to eight paths inside a small circle or arm can
moiré. If observed, reduce ring count by rendered radius; do not disable the
family globally.

**Snowflake morph and cache buckets can detach.** Canonical bucket-time geometry
plus current-frame clipping bounds the mismatch. If motion is still visible,
shorten only the snowflake bucket or quantise profile identity more finely.

**Gradient compatibility can regress invisibly.** Keep current gradient code in
renderer-owned compatibility branches instead of approximating it through the
generic radial gradient.

**History changes intentionally.** Existing Circle and Snowflake elements gain
derived textures. Persistence remains compatible, but thumbnails must bump
their cache version so old and detail renders cannot disagree.

## Delivery Boundary

This delivery is complete when Circle and the main Snowflake body visibly obey
the day's texture policy in live canvas, history, thumbnails, and export;
Snowflake ghosts and Rays remain unchanged; deterministic and performance gates
pass; and no persistence migration is introduced.

Only after evaluating this build on device should a separate design begin for
new ribbon/arc and shard/cell shape families.
