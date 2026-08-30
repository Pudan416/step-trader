# Day Objects Editorial Field

Date: 2026-08-30
Status: Approved in conversation; awaiting written-spec review
Branch: `codex/current-integration`

## Goal

Replace the rigid Day Objects formations with deterministic editorial
compositions that retain randomness, depth, color richness, and visual value
from one to ten happenings. A day must feel composed rather than diagrammed:
objects may overlap, cross canvas edges, sit at radically different depths,
and use vivid circle-derived materials without becoming unrelated styles.

Day Objects remains a laboratory-only experience. This work must not replace
or modify the restored main application canvas.

## Decisions superseded

This specification supersedes two earlier decisions:

- the placement, size, and depth rules in
  `2026-08-29-day-object-choreography-presets-design.md` that made regular
  rings, grids, ribbons, and uniformly sized formations common;
- the single-color-owning radial field in
  `2026-08-28-day-objects-html-circle-recipes-design.md` that reduced the
  layered HTML material to one color axis and used secondary fields only for
  light.

The prior deterministic identity, daily material inheritance, palette
allocation, insertion and removal envelopes, maximum actor count, instanced
Metal pass, procedural grain, step tempo, sleep clarity, and Reduce Motion
behavior remain valid unless this document explicitly changes them.

## Visual principles

1. **Editorial asymmetry.** The scene has visual balance, not geometric
   symmetry. Regular rings, rows, grids, flowers, and evenly spaced symbols are
   not default placement systems.
2. **Continuous scale.** Size is sampled from a broad continuous range rather
   than a few narrow bands.
3. **Visible depth.** Size, softness, parallax, overlap, and draw order jointly
   communicate foreground, focus plane, and distance.
4. **Controlled randomness.** A deterministic candidate scorer preserves
   variety while rejecting weak compositions.
5. **Coherent material DNA.** One primary material family and, where useful,
   one closely related accent mutation govern the day. Actors vary without
   looking imported from different visual systems.
6. **Color has presence.** Multicolor actors keep perceptible chroma and local
   contrast. Transparent materials remain visible against their background.

## Daily editorial grammar

The day seed selects one editorial grammar. A grammar supplies composition
constraints, not ten fixed slots. Actor identities remain stable, but each
actor receives an independently seeded position, scale, depth, material
mutation, and route inside those constraints.

The initial catalog contains six grammars:

### Layered overlap

- Several independently sized discs form an asymmetric mass.
- Intersections are encouraged, but no single point may contain every actor.
- The mass may be vertical, diagonal, or loosely curved.

### Open field

- Objects occupy the full canvas with deliberate negative space.
- Distances are irregular; the result must not read as a grid or constellation
  of equal dots.
- At six or more actors, occupied bounds reach all vertical thirds.

### Cropped foreground

- One or two large near objects cross a canvas edge and may be substantially
  cropped.
- Medium and small objects provide counterweight elsewhere.
- The foreground object is never the only visually readable actor.

### Depth scatter

- Near, middle, and far planes are all represented.
- Position is loosely distributed rather than centered on a common anchor.
- Cross-plane overlap is preferred because it makes depth immediately legible.

### Transparent print

- Related translucent discs create new colors where they overlap.
- Size remains varied and the composition is asymmetric.
- Opacity is high enough that individual silhouettes remain readable.

### Equal-scale study

- A rare exception in which actors use related medium sizes and a common focus
  plane.
- Placement is still irregular and editorial; the grammar may not become a
  ring, grid, flower, or evenly spaced row.
- This grammar represents no more than ten percent of sampled days.

The first five grammars share the remaining probability, with `layeredOverlap`,
`openField`, and `depthScatter` favored. Exact weights are deterministic
catalog data and are covered by distribution tests.

## Composition generation and scoring

Each actor receives several deterministic placement candidates derived from
the day seed and stable event identity. The composition planner chooses the
best candidate incrementally using a score with these terms:

- canvas coverage and use of all vertical thirds;
- asymmetric balance around a seeded visual center of mass;
- a grammar-specific target amount of overlap;
- minimum negative space;
- distance from regular angular, row, grid, and equal-spacing patterns;
- separation of scale and depth from already admitted actors;
- allowance for intentional edge cropping;
- penalties for all actors sharing one small cluster or one focal point.

The scorer may reject and deterministically resample a candidate, but it may
not reroll existing actors when a happening is added or removed. Actors are
admitted in a canonical stable-identity priority independent from input order,
and the first ten admitted identities each own a persistent candidate
sequence. Event order does not affect retained actors.

## Size hierarchy

Actor diameter is expressed relative to the canvas short side:

- far: `0.06...0.16`;
- middle: `0.16...0.38`;
- near: `0.38...0.75`.

These are overlapping artistic ranges, not three fixed sizes. The final scale
is continuous within a range and may breathe slowly around its base value.

For four or more actors, the largest-to-smallest base-diameter ratio is at
least `3:1`. Grammars other than `equalScaleStudy` may reach `6:1` or more.
For one and two happenings, a deterministic distinctness resolver prevents
consecutive days from repeatedly selecting the same apparent size, depth,
position region, and material mutation.

Large actors may extend beyond the canvas by 15 to 45 percent of their radius.
Cropping is a compositional tool, not a positioning error.

## Depth and focus

Depth is an independent continuous value that influences scale, local blur,
parallax, and draw order:

- foreground actors are normally large and receive the strongest local
  defocus;
- middle-plane actors are the sharpest and carry the primary visual detail;
- distant actors are small and receive restrained softness and slower apparent
  movement.

Depth is not inferred from size alone, allowing occasional large middle-plane
actors or small sharp accents. However, a very large foreground actor must be
more defocused than the scene's sharpest middle actor.

Local actor focus is rendered before the global sleep post-process. Sleep then
affects the entire finished canvas: less sleep increases global blur without
destroying the relative depth hierarchy.

## Shape inheritance

All bodies remain circle-derived. A day selects one base silhouette and a
bounded mutation range:

- circle;
- ellipse;
- softly pinched lens;
- low-amplitude organic orb.

Per-actor elongation or deformation may vary enough to be visible but remains
related to the base silhouette. Filled, transparent, outlined, and cut-out
objects are material variants, not unrelated shapes.

Outline and counterform remain full daily families. On a day that selects one
of these families, at least one of the first three admitted actors must clearly
render as a thin circular contour or a circle with a cut center. Other actors
in that day use close variations of the same construction rather than switching
to a radically unrelated filled sphere.

## Daily material DNA

The day seed selects one primary family from the existing HTML-derived catalog:

- gradient;
- solid;
- sphere;
- glass;
- mist;
- halo;
- luminous;
- outline;
- counterform.

It may additionally select one compatible accent mutation. An accent can
change intensity, softness, center displacement, transparency, contour width,
or counterform scale, but it cannot change to an unrelated family. Examples of
valid relationships are gradient to soft gradient, sphere to luminous sphere,
glass to frosted glass, and outline to multi-outline.

## Color construction

Actor colors come from the day's two object palettes and remain independent
from the background palette.

### One-color actor

A one-color actor is a true constant-color fill. The fragment shader must not
apply a hidden radial brightness ramp, directional light, or secondary color
blob unless the selected family explicitly adds sphere, glass, halo, or
luminous optics. A `solid` actor is visually flat.

### Two- and three-color actor

Multicolor actors use two or three palette colors and up to three analytic
radial fields. Every field has its own shifted focus, radius, softness, opacity,
and blend operation. All fields are radial; no linear, angular, conic,
pyramidal, or Voronoi-like ownership boundary is allowed inside an actor.

The first field supplies broad coverage. Secondary fields contribute real
color through a small supported blend catalog—normal interpolation, screen,
soft-light, and multiply—rather than merely changing luminance. Broad
softness and overlapping influence create the fluid richness of
`random-gradient-circle.html` while preserving smooth transitions.

The renderer keeps the current one-to-three-color limit and at most three
analytic fields so all actors remain in the single instanced Metal pass.

### Color quality guardrails

- A multicolor actor must retain measurable hue or chroma difference between
  at least two sampled regions.
- The palette conversion must not wash every color toward the background.
- Transparent families use a minimum direct tint and silhouette-alpha floor.
- Additional light and depth effects may shape color but may not replace it
  with neutral gray.
- Stop transitions remain broad enough to avoid hard bands or isolated round
  stickers floating over an otherwise flat fill.

## Motion

The grammar produces a shared low-frequency vector field for the day. Each
actor samples that field with its own stable phase, direction bias, amplitude,
speed ratio, and depth parallax. This creates related choreography without
locking actors into a visible ring, row, or rotating icon.

Motion rules:

- actors drift slowly across meaningful distances;
- overlapping paths allow actors to pass above and below one another;
- depth and breathing vary continuously without abrupt focus switches;
- local spinning is restrained and never becomes the dominant motion;
- all loops are continuous at their period boundary;
- step count controls the common tempo multiplier, with low steps making the
  scene almost still;
- Reduce Motion freezes route, depth migration, and breathing while preserving
  the composed frame.

## Background and grain

The existing smooth procedural background and stable grain overlay remain
separate from actor construction. Background colors do not limit actor colors.
This specification does not move Day Objects into the main canvas and does not
change the main canvas selection.

The proposed Classic background catalog is a separate follow-up because it
changes background-family selection rather than the editorial actor system.

## Architecture

The implementation separates four responsibilities:

1. **Editorial grammar catalog** — weights and high-level constraints.
2. **Composition planner** — persistent candidate generation and scoring for
   position, scale, depth, cropping, and overlap.
3. **Material DNA generator** — daily family plus bounded per-actor mutations,
   color allocation, and radial-field descriptors.
4. **Motion field** — shared daily flow plus per-actor phase and parallax.

The scene owns immutable base composition data. Frame generation applies
motion and focus without regenerating identities or material descriptors.
Metal consumes bounded actor and appearance buffers and retains one instanced
actor draw.

## Performance constraints

- Maximum ten actors.
- No per-object textures or offscreen passes.
- At most three analytic radial fields and three colors per appearance.
- One instanced actor draw plus existing background, post-process, and grain
  passes.
- No frame-time random generation or composition rescoring.
- Existing renderer memory limits and physical-device performance gate remain
  mandatory.

## Verification

### Deterministic model tests

- A date and event identity always produce the same grammar, placement,
  appearance, and route.
- Adding, removing, or reordering events does not reroll retained actors.
- Every grammar and material family is reachable across a representative seed
  corpus.
- `equalScaleStudy` remains at or below its approved ten-percent share.

### Composition tests

- Four or more actors meet the required `3:1` scale ratio outside the explicit
  equal-scale grammar.
- Six or more actors use all vertical thirds in open and distributed grammars.
- Cropped-foreground scenes contain a genuinely cropped near actor and a
  readable counterweight.
- Regular spacing, common-radius rings, grid alignment, and single-cluster
  collapse stay below bounded scores.
- One- and two-happening fixtures differ across day seeds in size, depth,
  region, and material mutation.

### Material and render tests

- Solid fixtures have spatially constant fill color before edge
  antialiasing.
- Two- and three-color fixtures show smooth radial transitions and measurable
  regional color diversity without angular seams.
- Secondary radial fields change sampled color, not only luminance.
- Outline and counterform fixtures remain clearly distinct from filled actors.
- Transparent materials retain a readable silhouette on both light and dark
  representative backgrounds.
- Near large actors are softer than sharp middle actors while still remaining
  visible.

### Visual fixtures

A committed set of representative Lab captures covers:

- one, two, five, and ten happenings;
- every editorial grammar;
- the full material catalog;
- light, dark, warm, cool, and multicolor backgrounds;
- sharp sleep and low-sleep states;
- insertion, steady state, and removal.

Perceptual signatures are updated only from inspected renders produced by the
new implementation. Existing goldens are not changed merely to make tests
pass.

### Integration and performance

- Day Objects remains reachable in Lab and absent from the main Gallery.
- Full model, rendering, UI, and simulator suites pass.
- The physical-device GPU and memory check passes before the change is called
  production-ready.
- Unrelated dirty localization and project files are neither modified nor
  staged by this work.
