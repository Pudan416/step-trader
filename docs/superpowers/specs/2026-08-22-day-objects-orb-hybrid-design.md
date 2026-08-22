# Day Objects Orb Hybrid — Design Specification

**Date:** 2026-08-22

## Goal

Replace the current small Figma-like Day Objects silhouettes with large, circle-derived radial-gradient orbs that move as one dense daily choreography, overlap frequently, and create soft temporary bridges at close contact.

## Approved Visual Direction

- All objects are equal in meaning. Visual leadership may move from one orb to another during the day.
- The scene is a dense cluster, not a dispersed particle field. Orbs should overlap and pass above or below one another.
- Motion is continuous. Individual objects may travel in different directions and at different speeds while remaining synchronized by one daily choreography score.
- Overlap behavior is **Hybrid merge**: silhouettes normally remain readable as separate objects, while close overlaps produce a soft color bridge rather than a hard sticker-on-sticker intersection.
- Daily colors come from the app's existing `GradientPalette` system. Each day uses one, two, or three orb colors.
- The moving mesh-gradient background remains generated from the same daily palette.
- Grain is monochrome, procedural, pixel-sharp, and applied after blur. Its stable global intensity is exactly `0.05`; the noise pattern may refresh at 12 fps when Reduce Motion is off.
- `motionEnergy` remains the future steps input: low values nearly stop actor motion, high values restore the full score.
- `visualClarity` remains the sleep input: low values defocus the complete painted scene while the grain stays sharp.

## Orb System

Every daily actor uses one circle-derived silhouette family selected once from the daily seed:

1. `sphere` — circular, balanced, and closest to the approved visual reference.
2. `ellipse` — a gently stretched sphere; never a thin capsule.
3. `lens` — a soft lens-shaped orb with rounded ends and a full body.
4. `softBlob` — a circular body with low-amplitude, low-frequency organic deformation.

No polygon, dart, slab, wedge, scallop, burst, petal, or Figma-derived silhouette remains reachable in Day Objects.

The daily radial fill selects one curated preset:

- `default`: soft displaced focal point and moderate mixing.
- `radial`: centered or near-centered round falloff.
- `loFi`: broad stepped-looking tonal regions softened enough to avoid hard banding.
- `crossSections`: directional distortion with elevated mixing and bounded frequency; it must not produce an extremely bright, sharp amorphous blob.

Every preset retains deterministic bounded variation in radius, focal direction, falloff, mixing, distortion, frequency, rotation, and offset. The preset and parameters stay stable for the day.

## Scale and Density

Actor diameter is measured against the canvas short side:

- current visual leader: `0.26...0.34`;
- supporting orbs: `0.14...0.21`;
- satellites: `0.08...0.13`.

One unique happening contributes one orb. Duplicate happening identifiers do not add duplicates. The maximum remains 40 actors.

Size is not a permanent semantic rank. A deterministic leadership envelope moves through the actors over choreography chapters: the outgoing leader eases down while the incoming leader eases up. Retained actors do not reroll when happenings are added or removed.

## Choreography and Composition

- The existing day-root seed remains the sole source of deterministic daily choices.
- The score continues to use chapter-based motion and smooth chapter transitions.
- Daily chapters are drawn from orbit, spiral, crossing, stack, bloom, and drift.
- Each actor receives a deterministic travel direction and speed ratio. Both clockwise and counter-clockwise movement must be reachable in the same scene.
- Route anchors are clustered around one daily cluster center. The outer anchor spread is bounded so neighboring body envelopes overlap or nearly overlap during sampled phases.
- Actors retain deterministic depth bands; chapter changes may reorder depth without discontinuous position jumps.
- The UI exclusion region, safe bounds, and reserved negative-space contract remain enforced.
- Reduce Motion freezes geometric entrance/exit scaling and trails while allowing opacity-only transitions.

## Hybrid Merge Rendering

The actor fragment shader renders two related coverages:

1. opaque/normal radial body coverage;
2. a low-alpha outer merge field extending a bounded fraction beyond the body edge.

The merge field is invisible or subtle around an isolated orb. Where two nearby fields overlap through the existing premultiplied-alpha actor pass, they accumulate into a soft colored bridge. It must not erase the individual body edges or turn the whole cluster into one flat blob.

Quad reach and CPU geometry footprints must include the merge-field support so the bridge cannot clip at actor bounds or canvas edges.

## Background, Focus, and Grain

- Keep the existing five mesh-gradient archetypes and their per-day bidirectional motion.
- The mesh colors and orb colors are derived from the same selected application palette.
- Background motion advances independently even when actor `motionEnergy` is zero.
- The complete Warp/actor result is blurred according to `visualClarity`.
- Procedural grain is generated from final drawable pixels after blur and display adjustment.
- Grain intensity is fixed at `0.05` for every day, palette, actor count, clarity value, and device size.

## Accessibility and Lifecycle

- App backgrounding pauses animation; foregrounding resumes from the renderer clock without rerolling the day.
- Reduce Motion disables trails and geometry-scale entrance/exit effects while preserving opacity transitions.
- The Day Objects lab retains Single/Grid, Happenings, Motion, Focus, and Next controls.
- Debug and internal builds expose the lab; release exposure remains unchanged.

## Performance Constraints

- Preserve the existing instanced actor pass and 40-actor cap.
- Do not add a per-pixel global optimization, physics solver, or pairwise CPU simulation.
- Hybrid merge uses bounded local shader support, not a separate full-scene metaball simulation.
- Preserve the three-slot completion-fenced actor upload ring and current render-target planner.

## Acceptance Criteria

- A representative 8-happening Single scene visibly contains eight large circle-derived orbs, not 16 tiny legacy shapes.
- Every seeded daily silhouette belongs to `sphere`, `ellipse`, `lens`, or `softBlob`.
- Sampled actor diameters stay within the approved leader/support/satellite bands, except for bounded smooth interpolation during leadership exchange.
- At least two travel directions are present in representative multi-actor fixtures.
- Cluster sampling demonstrates frequent body/merge-field overlap without UI exclusion or edge clipping.
- GPU captures visibly show soft bridges during close contact and distinct bodies outside contact.
- Grain uniforms and rendered output use a stable intensity of `0.05` across palette luminance and clarity fixtures.
- Existing deterministic seed, insertion/removal continuity, sRGB presentation, background nonblank, Reduce Motion, safe-bounds, visual matrix, full unit/UI suite, and simulator build gates remain green.

