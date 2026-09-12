# Rich Canvas Lab Design

**Date:** 2026-08-16

**Status:** Approved for planning

## Context

Step Trader's production canvas currently renders four selectable procedural shape families and a set of legacy-compatible fills. The proposed rich visual language introduces five more detailed visual families and six interior constructions. Replacing the production renderer immediately would make visual iteration, performance diagnosis, compatibility, and review unnecessarily risky.

Rich Canvas Lab is an internal, read-only preview screen that renders the current day's real canvas as rich generative art. It lets the team shuffle rich families and fills, inspect animation and optical balance with ten real elements, and measure performance without changing production rendering or saved canvas data.

The visual direction is documented in [the shape × fill matrix](../../design/rich-figure-shape-fill-matrix-v1.png).

## Goals

- Preview the current day's elements using five rich figure families.
- Exercise six visibly different rich fill constructions.
- Preserve the current canvas's happenings, labels, colors, positions, and relative size hierarchy.
- Normalize optical size so all families belong to one composition and Crystalline Star is readable at useful sizes.
- Shuffle family and fill assignments without writing to application data.
- Animate ten mixed rich elements without trails.
- Expose lightweight performance information inside the Lab.
- Hold a stable 20 FPS animation cadence on a physical iPhone 13 with ten visible elements.
- Preserve all uncommitted production renderer and fill work.

## Non-goals

- Replacing or modifying the production canvas renderer.
- Persisting a rich style version on `CanvasElement`.
- Changing Codable, Supabase schemas, sync, history, export, thumbnails, or palette previews.
- Exposing rich figures to App Store users.
- Supporting full rich-render export in this phase.
- Implementing trails.
- Guaranteeing that every family/fill pairing will be eligible for production.

## Entry and Availability

`Settings → Appearance` gains a `Rich Canvas` navigation row when an internal-build feature gate is enabled.

Availability is explicit:

- DEBUG builds enable the Lab.
- TestFlight builds enable it only when compiled with `INTERNAL_BUILD`.
- Production App Store builds omit the entry.

The gate should live in a small `ExperimentalFeatures` utility rather than being repeated in views.

## Read-only Data Flow

On presentation, `RichCanvasLabView` loads a snapshot of the current `DayCanvas` through the existing storage service. It never calls save, sync, thumbnail invalidation, or mutation APIs.

For each visible `CanvasElement`, the Lab consumes:

- stable element identity and shape seed;
- happening label;
- primary and optional secondary colors;
- base position;
- effective current size (`userSize ?? size`);
- creation order for stable tie-breaking.

The Lab preserves labels, colors, and positions. It derives rich-only family, fill, layout, detail, and motion parameters in memory.

If the current day has no saved elements, the screen presents an empty state and does not create a canvas implicitly.

## Rich Style Model

### `RichFigureFamily`

The Lab supports exactly five families:

1. `circle`
2. `luminousOrganic`
3. `crystallineStar`
4. `rays`
5. `orbitalSpirograph`

These are Lab-local visual families, not new `CanvasShapeType` cases.

### `RichFillKind`

The Lab supports exactly six interior constructions:

1. `luminousGradient`
2. `nestedContours`
3. `orbitalLines`
4. `filamentField`
5. `outlineWithCore`
6. `layeredTranslucentMass`

These are independent of the production `TextureKind` and the current per-day fill policy. The Lab must not read or mutate the user's allowed legacy fills.

### `RichFigureStyleSpec`

Each preview element receives an immutable, deterministic spec containing:

- family;
- fill;
- primary and optional secondary colors;
- geometry seed;
- animation phase and speed class;
- detail tier;
- glow intensity;
- particle eligibility.

The same current canvas and `shuffleNonce` must always produce the same specs.

## Deterministic Shuffle

`RichCanvasLabView` owns a session-only integer `shuffleNonce`, initially zero. Pressing `Shuffle` increments it. Closing the screen discards it, so reopening the Lab returns to the stable initial arrangement.

Assignment operates on elements in stable creation order, with UUID as a tie-breaker:

1. Build a family deck by repeating all five families until it covers the element count.
2. Shuffle the family deck with a seed derived from the day key and `shuffleNonce` in the `richFamily` domain.
3. Build a fill deck by repeating all six fills until it covers the element count.
4. Shuffle the fill deck independently in the `richFill` domain.
5. Rotate or swap the fill deck deterministically when necessary to reduce identical neighboring pairings in stable element order.
6. Derive remaining style parameters from the element seed plus `shuffleNonce` using separate RNG domains.

With ten elements, every family appears at least once and every fill appears at least once. No randomness may depend on process hash values or mutable global RNG state.

Shuffle changes only rich family, fill, and rich detail/motion personality. It does not change colors, labels, positions, or layout footprints.

## Composition and Optical Normalization

Raw `CanvasElement.size` does not have a consistent visual meaning across existing renderers. Rich Canvas therefore uses a `RichFigureLayoutSpec` instead of passing the raw value directly to every family.

### Stable composition slots

- Every source element owns one stable composition slot.
- The slot's position and target footprint remain unchanged across Shuffle.
- Reassigning Organic to Star or Spirograph must not make the entire composition jump.
- The current elements' effective sizes establish their relative ordering from smallest to largest.
- The single smallest slot may become a deliberate small accent near 19% of canvas width.
- Remaining slots map monotonically into an approximately 22–34% target-diameter range.
- A near-uniform source size set maps to a balanced middle range instead of amplifying tiny numerical differences.

Exact constants are renderer tuning values, but they must remain bounded and covered by layout tests.

### Geometry-aware scaling

Every rich family exposes canonical geometric bounds for a seed and time bucket. The layout layer computes the transform required to fit those bounds into the slot's target footprint.

Family-specific optical compensation is applied after geometric fitting:

- Circle is the baseline.
- Luminous Organic is slightly reduced because its filled mass reads heavier.
- Crystalline Star is enlarged because fine rays read lighter; its seeded bounds must be measured so narrow stars cannot collapse into specks.
- Rays are normalized by the complete fan bounding box rather than radial extent.
- Orbital Spirograph is slightly enlarged so separated orbits remain legible.

Glow and particles do not contribute to geometric bounds. Renderers reserve safe overscan so halos are not clipped.

## Rendering Architecture

The experiment uses separate types and files. Existing production renderers remain untouched.

- `RichCanvasLabView`: navigation screen, snapshot loading, Shuffle state, and controls.
- `RichCanvasView`: TimelineView/Canvas host, labels, animation activity, and performance HUD.
- `RichFigureStyleSpec`: deterministic assignment and style parameters.
- `RichFigureLayoutSpec`: stable footprint and optical normalization.
- `RichRenderBudget`: global detail limits for element count and Low Power mode.
- `RichRenderCache`: cached geometry and phased time buckets.
- One focused renderer per rich family, sharing fill and glow helpers where behavior is genuinely common.

The existing day background should be reused without drawing production elements. Rich figures and their labels render in a separate overlay. The Lab must not add a rich branch to `GenerativeCanvasView` during this phase.

The first implementation uses SwiftUI `Canvas` at a requested 20 FPS. Metal is not introduced preemptively. If device measurements fail, Instruments data determines which individual renderer or operation should move to a shader.

## Family Motion

- **Circle:** slow breathing and offset highlight drift.
- **Luminous Organic:** asynchronous contour deformation with a stable readable silhouette.
- **Crystalline Star:** reuse the current Snowflake Lissajous drift behavior, morph ray lengths, and counter-rotate internal layers. Do not draw Snowflake trail ghosts.
- **Rays:** slowly open and close the fan and move one light impulse from origin to tips.
- **Orbital Spirograph:** rotate orbits at different slow speeds and move a small number of particles along selected paths.

Each element uses one primary family motion and at most one subordinate fill motion. Motion is deterministic from the style spec and continuous across frames.

Reduce Motion freezes translation, rotation, and deformation at a stable canonical time. A very subtle opacity change may remain only if system semantics and visual review permit it.

## Fill Behavior

Fill changes internal construction rather than adding a decorative overlay:

- **Luminous Gradient:** colored core, offset highlight, and localized halo.
- **Nested Contours:** multiple inset copies with varied opacity and phase.
- **Orbital Lines:** intentionally broken rings or offset paths with highlighted arcs.
- **Filament Field:** clipped directional or crossing fibers.
- **Outline + Core:** nearly transparent body, expressive boundary, and compact core.
- **Layered Translucent Mass:** several translucent colored surfaces with optical depth.

All families may receive all fills in the Lab so the team can judge the full exploration space. The eventual production design may introduce a compatibility matrix after visual review.

## Performance Budget

The ten-element normal-mode ceiling is:

- no trails;
- at most two blurred glow passes per element;
- normally 6–8 nested contours, with more detail allowed only in the largest slot when the global budget permits;
- at most 8 orbital rings per element;
- at most 24 filament segments per element;
- a global particle pool rather than an independent large pool per element;
- batched paths for strokes with the same material;
- cached static geometry;
- seed-phased time buckets so expensive geometry updates do not align on one frame.

`RichRenderBudget` reduces contour, filament, glow, and particle counts as visible element count grows. Low Power mode lowers those ceilings further and may reduce the requested update cadence. Detail reduction must preserve silhouette and the primary fill distinction.

The HUD displays:

- observed animation cadence;
- visible element count;
- active detail tier;
- Low Power state;
- a rolling count of slow animation intervals.

The HUD is diagnostic rather than a substitute for Instruments; it does not claim to measure GPU render time directly.

## Error and Lifecycle Behavior

- Leaving the screen pauses animation and releases Lab-local caches.
- Backgrounding the app pauses the TimelineView.
- Memory warnings may clear derived geometry; specs remain reproducible from seeds.
- A malformed or missing secondary color falls back to the primary color.
- Non-finite or degenerate geometry must fall back to a simple canonical family outline in the same slot rather than disappearing.
- Shuffle remains available while animation is paused.

## Test Strategy

### Unit tests

- Identical day, elements, and nonce produce identical `RichFigureStyleSpec` values.
- Different nonces change at least one family and fill assignment for a ten-element canvas.
- Ten elements cover all five families and all six fills.
- Assignments do not use process-dependent hashing.
- Layout footprints remain identical across Shuffle.
- Layout mapping is monotonic and remains inside its configured bounds.
- Seeded geometric fitting keeps each family's canonical bounds inside its target footprint.
- Crystalline Star cannot collapse below its assigned footprint because of seed-specific narrow bounds.
- `RichRenderBudget` respects every normal and Low Power ceiling.
- Production `CanvasElement` encoding is unchanged.

### Visual checks

- Capture the initial arrangement and at least three Shuffles.
- Capture normal, Low Power, and Reduce Motion states.
- Verify ten elements on a dark day background at full screen.
- Check that no glow is clipped and no family becomes a generic luminous circle.
- Check labels remain legible and attached to moving figures.

### Physical-device performance

On an iPhone 13, animate ten mixed rich elements for at least 30 seconds:

- observed cadence remains at or above 20 FPS after warm-up;
- Shuffle does not produce sustained stalls;
- navigation and controls remain responsive;
- normal and Low Power results are recorded separately;
- Instruments captures are taken if the target is missed.

## Acceptance Criteria

- `Rich Canvas` is reachable only in internal builds.
- It renders a read-only snapshot of the current day's real canvas.
- Five rich families and six fills are present across ten elements.
- Shuffle is deterministic, session-only, and does not move or recolor elements.
- Composition footprints remain stable across Shuffle.
- Crystalline Star is optically comparable to other medium elements and is not a speck.
- Rich figures animate without trails.
- Reduce Motion and Low Power behavior are visible and functional.
- The HUD exposes useful cadence and budget information without claiming GPU precision.
- The Lab holds 20 FPS on an iPhone 13 with ten elements.
- Production canvas rendering, persistence, sync, history, export, thumbnails, and palette previews are unchanged.
- Existing tests pass and new deterministic, layout, and budget tests are added.
- Screenshots or a screen recording are provided before the experiment is considered visually approved.

## Implementation Boundary

Implementation should add new Lab-specific files and make only the smallest integration edit necessary to expose the Settings navigation row. In particular, it must not fold rich cases into the currently modified production renderer, fill selection, history thumbnail, or sync code. Any overlap with uncommitted user work must be reviewed before editing.
