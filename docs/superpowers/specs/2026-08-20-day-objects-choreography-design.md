# Day Objects Choreography Design

**Date:** 2026-08-20

## Goal

Turn Day Objects from a field of independently moving shapes into a deterministic daily choreography. Every added happening enriches the composition without moving or reseeding existing actors. A single daily palette drives both the generative background and the figures. Future step and sleep data enter through normalized controls: steps change motion energy, while sleep changes the focus of the rendered scene.

## Product experience

- Each day has a recognizably different, continuously moving composition.
- All figures share one master timeline, while individual roles may use different paths, speeds, rotations, depths, and visibility envelopes.
- Figures may orbit, spiral, cross, stack, pass above or below one another, bloom, disappear, and return.
- The choreography remains coordinated: differences between actors are ratios and phase offsets inside one score, not unrelated particle motion.
- Adding a happening introduces a new actor group with a soft entrance. Existing actors keep their identity, path, phase, and current position.
- More happenings produce a richer hierarchy and more interactions, not a full reroll or uniform visual noise.
- The background is a slowly animated, Warp-like generative gradient derived from the same daily palette as the figures.
- Sleep blur affects the composed gradient-and-figure scene. A separate grain layer stays sharp above that blur.

## Scope

The first implementation remains in the Day Objects experimental lab and provides stable interfaces for later production-canvas and HealthKit integration.

Included:

- deterministic daily scene, palette, gradient, score, actors, and render parameters;
- stable event-ID-based actor insertion;
- synchronized continuous choreography;
- Warp-inspired generative background;
- whole-scene focus controlled by `visualClarity`;
- motion tempo controlled by `motionEnergy`;
- full-resolution grain above the scene blur;
- lab controls and deterministic tests;
- a bounded renderer budget of 40 actors.

Not included:

- reading steps or sleep directly from HealthKit;
- replacing the production canvas;
- persisting a rendered frame;
- user-authored palettes or choreography editors;
- copying or depending on the Paper Warp package or source code.

## Design principles

1. **One score, many roles.** Actors share a timeline and scene-level transitions.
2. **Stable growth.** Adding an event never changes existing actors.
3. **Daily identity.** Date and identity choose the visual system; event IDs only add actors inside it.
4. **One palette.** Background, figures, trails, and accents use explicit roles from the same color family.
5. **Layered rendering.** Background, figures, sleep blur, and grain remain independently controllable.
6. **Deterministic variety.** The same inputs reproduce the same scene, while domain-separated random streams prevent unrelated parameters from shifting.

## Scene inputs

```swift
struct DayObjectSceneInput: Equatable {
    let dayKey: String
    let identity: String
    let eventIDs: [String]
    let motionEnergy: Double   // clamped to 0...1
    let visualClarity: Double  // clamped to 0...1
    let reduceMotion: Bool
}
```

The lab uses stable fixture event IDs rather than only an integer count. Until health data is connected, it exposes controls for `motionEnergy` and `visualClarity`, both defaulting to `0.55`.

## Deterministic seed model

The scene root seed is derived from `identity + dayKey`. Every subsystem uses a named domain:

```text
sceneRoot
├── palette
├── warpBackground
├── choreographyScore
└── actor(eventID)
    ├── role
    ├── path
    ├── depth
    ├── rotation
    ├── visibility
    └── member(index)
```

The actor seed never includes total actor count or array position. Event IDs are de-duplicated while preserving their first input order, which is the caller's chronological insertion order. The event ID itself remains the actor identity source; per-frame depth sorting is separate from allocation order. Adding or removing one event therefore affects only that event's actor group.

The scene supports at most 40 rendered actors. Stable event-derived groups are appended in chronological insertion order, using as much of the remaining capacity as the group can occupy. When the budget is reached, later additions receive no rendered actor until capacity becomes available; an addition must never displace an existing actor.

## Daily palette

The daily palette is selected from `CanvasColorPalette.paletteHex`. Selection uses a hue-coherent contiguous window and produces three to five colors. The palette builder derives explicit render roles instead of allowing every layer to choose arbitrary colors:

```swift
struct DayObjectPalette: Equatable {
    let backgroundBase: SIMD3<Float>
    let backgroundFields: [SIMD3<Float>] // 2...4 colors
    let figurePrimary: SIMD3<Float>
    let figureSecondary: SIMD3<Float>
    let accent: SIMD3<Float>
}
```

- Background colors may be darkened or desaturated variants of palette colors, but must preserve their hue relationship.
- Figure colors come from the same selected window and must pass a minimum perceptual contrast threshold against the sampled background base.
- Accent use is limited to a deterministic minority of actors and trail highlights.
- Colors are converted to linear RGB before shader blending.
- The light and dark variants are derived roles of the same palette, not unrelated complementary hues.

## Choreography score

Each day chooses three to five chapters from a curated vocabulary:

- `orbit`
- `spiral`
- `crossing`
- `stack`
- `bloom`
- `drift`

A complete score loops in 36 to 72 seconds at `motionEnergy == 1`. Chapter boundaries use a smooth transition window occupying 12% of each chapter. Position, orientation, scale, and opacity interpolate continuously across boundaries, including the final-to-first loop boundary.

The master phase is the sole time source:

```text
masterPhase = elapsedTime × baseTempo × tempoScale
actorPhase  = masterPhase × actorSpeedRatio + actorPhaseOffset
```

Actor speed ratios are selected from a small musical set (`0.5`, `0.75`, `1`, `1.5`, `2`) so actors can move at visibly different speeds while returning to coordinated alignments. Arbitrary unrelated angular speeds are not used.

`motionEnergy` uses a nonlinear mapping:

```text
tempoScale = mix(0.035, 1.25, smoothstep(motionEnergy))
```

At zero activity, figures are almost still but keep a subtle breathing motion. High activity increases tempo without increasing geometric disorder. With Reduce Motion enabled, tempo is fixed to `0.02`, trails are disabled, and visibility changes use opacity only.

## Actor roles and paths

Each stable actor receives:

- one primary role: focal, support, bridge, satellite, or accent;
- one depth band and stable base `zIndex`;
- a path variant for each chapter;
- a speed ratio and phase offset;
- spin direction and spin ratio;
- scale and color role;
- a deterministic visibility schedule.

Paths are defined relative to a shared composition frame normalized by the shorter screen dimension. This removes portrait aspect-ratio amplification. Every path includes its body radius and maximum trail reach when calculating safe bounds.

Daily composition reserves a configurable UI exclusion region and targets 35–55% negative space. Focal actors occupy one dominant region; support and bridge actors create relationships around it. Actor depth may change only at chapter transitions, allowing figures to pass above or below one another without unstable per-frame sorting.

## Appearance, disappearance, and live insertion

Each actor has a deterministic visibility envelope inside the daily loop. Envelopes use smooth scale and opacity ramps rather than binary toggles. At least 55% of allocated actors remain visible at every point in the score, preventing the canvas from becoming unintentionally empty.

When an event is added while the view is running:

1. Existing actors continue evaluating from the same master time.
2. New actors evaluate their correct current choreography positions immediately.
3. A local 0.8–1.4 second insertion envelope brings them from 70% scale and zero opacity to their score-defined state.
4. Existing actor buffers are not regenerated except for render-list bookkeeping.

Removing an event applies the reversed local envelope before releasing its actors.

## Warp-inspired background

The background is an original Metal implementation inspired by the behavior and controls of Paper's Warp shader: animated color fields distorted by noise and layered swirls over a base pattern. It does not import the Paper dependency or reproduce its source.

The daily seed chooses parameters from art-directed ranges:

| Parameter | Range |
| --- | --- |
| color fields | 3...5 daily palette roles |
| proportion | 0.02...0.18 |
| softness | 0.75...1.0 |
| distortion | 0.15...0.40 |
| swirl | 0.45...0.90 |
| swirl iterations | 6...12 |
| shape | predominantly edge; occasional stripes or checks |
| shape scale | 0.12...0.38 |
| overall scale | 2.5...4.0 |
| rotation | 0...360 degrees |
| offset | -0.35...0.35 per axis |

The background uses an independent ambient clock and always moves slowly, even when `motionEnergy` is zero. Its speed is selected in `0.05...0.18` and is not controlled by steps. Parameters stay fixed for the whole day; only the time coordinate changes.

To control cost, the Warp pass renders at half linear resolution with a maximum of one million pixels, then upscales with linear filtering. Swirl iterations are uniform for the frame and capped at 12.

## Render pipeline

```text
Daily palette
    ├── Warp background pass (half resolution)
    └── Figure/trail pass (full resolution, instanced actors)
                 ↓
        scene composite texture
                 ↓
       sleep focus post-process
                 ↓
       grain pass (full resolution)
                 ↓
              display
```

The figure pass computes actor position, direction, scale, opacity, and depth once per actor per frame on the CPU or in a small compute pass. The fragment stage renders bounded actor geometry rather than looping over all actors for every canvas pixel.

Body antialiasing uses screen-space derivatives. Trails use actual time-direction velocity, exponential decay behind the actor, and Gaussian lateral falloff. Trail brightness is normalized by visible actor count so adding events does not blow out the scene.

## Sleep-controlled focus

`visualClarity` affects the composite background-and-figure texture before grain:

```text
blurRadius = pow(1 - visualClarity, 1.4) × 18 points
contrast   = mix(0.84, 1.0, visualClarity)
saturation = mix(0.88, 1.0, visualClarity)
```

At low sleep clarity the entire painted scene feels out of focus. Choreography geometry and timing do not change. Grain remains sharp and therefore reads as a physical display or film texture rather than blurred scene content.

## Grain layer

Grain is a separate full-resolution procedural pass above the sleep blur.

- The daily seed controls grain size and base intensity.
- Spatial noise is stable within a frame and changes at no more than 12 Hz to avoid high-frequency shimmer.
- Opacity stays in `0.035...0.075` and is reduced on very light palettes.
- Grain uses soft-light-like luminance modulation and does not introduce unrelated hue.
- Reduce Motion freezes its temporal phase.

## Architecture boundaries

The implementation introduces focused units:

- `DayObjectScene` — immutable daily scene and stable actor allocation;
- `DayObjectPalette` — palette roles and contrast-safe derivation;
- `DayObjectChoreographyScore` — daily chapters and master-time evaluation;
- `DayObjectActor` — stable event-derived role and path parameters;
- `DayObjectRenderFrame` — per-frame actor states prepared for rendering;
- `DayObjectsWarpShader.metal` — background pass;
- `DayObjectsActorShader.metal` — instanced figure and trail pass;
- `DayObjectsPostShader.metal` — focus and grain passes;
- `DayObjectsView` — timeline, input clamping, and render composition;
- `DayObjectsLabView` — fixture events and interactive motion/focus controls.

Pure scene, palette, score, and actor models use numeric color structures rather than `SwiftUI.Color`. Shader buffer layouts and numeric enum mappings have a single Swift source of truth with explicit stride tests.

## Invalid and empty states

- Inputs outside `0...1` are clamped.
- Empty event IDs render the Warp background and grain without figures.
- Duplicate event IDs are de-duplicated before actor allocation.
- An empty identity falls back to a stable anonymous identity, never a per-launch random value.
- Non-finite time or render inputs evaluate as zero rather than entering shader buffers.
- Renderer allocation failure falls back to the static daily gradient without animation.

## Testing strategy

### Deterministic model tests

- identical inputs reproduce palette, score, actors, and Warp parameters;
- a different day changes the scene;
- adding an event preserves all previous actors byte-for-byte;
- removing and re-adding the same event restores the same actors;
- event ordering does not affect actor identity;
- no more than 40 actors are allocated;
- duplicate IDs do not create duplicate actors;
- all choreography chapters are reachable across a broad seed sample.

### Choreography tests

- positions and opacity are continuous across every chapter boundary and loop boundary;
- negative and positive travel directions produce the correct heading and trail direction;
- speed ratios remain in the curated synchronized set;
- at least 55% of actors are visible at sampled phases;
- evaluated paths respect safe bounds on supported portrait and landscape aspect ratios;
- adding an event at an arbitrary master time does not change existing frame states;
- zero motion energy remains finite and produces only the specified idle tempo.

### Palette and post-process tests

- all figure and gradient colors derive from the same daily palette window;
- figure roles meet the defined contrast threshold;
- Warp parameters remain in art-directed ranges;
- `visualClarity == 1` produces zero blur;
- blur increases monotonically as clarity falls;
- grain settings do not depend on clarity and remain above the blur pass.

### Visual regression tests

- fixed-seed snapshots for each chapter family at 0, 1, 10, 24, and 40 actors;
- a 3×5 daily contact sheet at phone and tablet aspect ratios;
- snapshots at `visualClarity` values 0, 0.5, and 1;
- coverage thresholds for clipping, negative space, and blank frames;
- insertion snapshots before, during, and after the local entrance envelope.

### Performance validation

Measure on a physical supported iPhone at 30 FPS with 1, 10, 24, and 40 actors. At 40 actors, the target is p95 GPU frame time below 25 ms with no sustained thermal escalation during a five-minute run. Simulator results are not accepted as GPU performance evidence.

## Acceptance criteria

1. Every day deterministically produces a new palette, Warp background, and choreography score.
2. Figures visibly participate in one coordinated, continuously changing composition.
3. Actors may use different speeds, rotations, paths, depths, and visibility without reading as unrelated particles.
4. Below the 40-actor budget, adding an event enriches the live scene without moving or reseeding existing actors; at the budget, existing actors are preserved.
5. Low `motionEnergy` makes figures almost still; high energy increases synchronized tempo.
6. Low `visualClarity` visibly defocuses the complete painted scene while grain remains sharp.
7. Gradient and figure colors visibly belong to the same daily palette.
8. The background retains subtle independent motion when figure motion is near zero.
9. The renderer stays inside the actor, swirl-iteration, and pixel budgets.
10. Deterministic, continuity, visual regression, and performance checks described above pass before production-canvas integration.
