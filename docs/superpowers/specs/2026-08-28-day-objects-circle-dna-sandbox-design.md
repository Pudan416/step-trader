# Day Objects Circle DNA Sandbox Design

Date: 2026-08-28
Status: Proposed for review
Branch: `codex/current-integration`

## 1. Purpose

Rebuild the Day Objects laboratory as a deterministic sandbox for living,
circle-derived objects. The system adapts the layered radial-circle generator
from `/Users/kosta/Downloads/random-gradient-circle.html` to the existing Metal
renderer, while preserving one coherent visual universe per day.

The sandbox is the proving ground for the generator. Production screens may
adopt it only after the generated families, motion, composition, and performance
have been reviewed in the laboratory.

## 2. Core visual rule

One day has one dominant material family. A minority of objects may use a
related accent mutation, but the accent must be produced by the same underlying
formula and remain recognizably related.

Within one day the system must not mix unrelated genres such as:

- a filled body and a graphic stroked ring;
- a clean glass sphere and an unrelated blurred cloud;
- a closed orb and a radically different cut-out counterform;
- a soft radial fill and an angular/conic color wheel.

Family resemblance is established by a shared silhouette grammar, radial field
construction, edge behavior, lighting model, surface texture, and bounded
optical ranges. Individuality comes from color, size, depth, focal placement,
opacity, glow, layering, and small geometric mutations.

## 3. Source-generator adaptation

The HTML generator supplies a useful parameter vocabulary:

- layered radial gradients with independently shifted focal centers;
- per-layer radius, stops, opacity, blur, and blend behavior;
- edge softness;
- bounded noise displacement;
- glass, luminous, mist, halo, membrane, and dense-volume expressions;
- grain, frost, cloud, and chromatic surface treatments;
- internal highlight and corona behavior.

The Metal implementation will adapt these ideas rather than reproduce SVG
filters literally. Analytic shader functions replace SVG blur and turbulence.
The renderer keeps premultiplied alpha, one instanced actor draw, no bitmap
materials, and no per-object render targets.

Linear or angular gradients may be used only as a subtle lighting contribution.
The visible body color remains radial and continuous. Color order must never
flip discontinuously as an animation phase crosses a threshold.

## 4. Hierarchical seed model

### 4.1 Day DNA

The existing 64-bit root seed selects a stable daily DNA containing:

- one material family;
- one compatible accent mutation recipe;
- the two existing object palettes;
- shared radial-field topology;
- global light direction and softness;
- edge and surface behavior;
- bounded opacity, glow, distortion, and focal-offset ranges;
- base roundness and maximum elongation;
- size/depth hierarchy;
- choreography family and tempo;
- composition archetype.

Reopening the same day recreates the same DNA.

### 4.2 Event appearance seed

Each happening identifier derives a stable appearance seed. It selects values
inside the daily ranges rather than selecting an unrelated material:

- base, soft-mutation, or accent-mutation role;
- one to three colors from exactly one object palette;
- color order through the radial layers;
- size class;
- elongation up to approximately five percent from the daily base shape;
- focal angle and distance;
- radial-layer radius and mixing;
- body, center, and rim opacity;
- inner or outer glow intensity;
- one to three related internal layers;
- local distortion phase and amplitude;
- depth band and local focus offset.

Adding a happening must not reroll an existing object's appearance.

### 4.3 Motion seed

A separate event motion seed supplies route, direction, phase, period, depth
cycle, and encounter timing. No randomness is sampled per frame. All evolving
values come from continuous periodic functions or smooth curve evaluation.

## 5. Material-family catalog

The initial sandbox exposes five curated families:

1. **Soft Volume**: dense satin/radial body with a broad internal highlight.
2. **Living Glass**: translucent radial layers, background refraction, restrained rim.
3. **Inner Light**: luminous center fading through a soft body edge.
4. **Atmospheric Orb**: the same closed radial body with increased internal and edge softness.
5. **Layered Membrane**: two or three overlapping translucent radial fields inside one related silhouette.

Each family owns a base recipe, soft mutation, and accent mutation. Accent
mutations adjust one or two parameters toward a curated limit; they do not
switch shader genre. Approximately 70...85% of actors use the base or soft
mutation and at most 15...30% use the accent mutation.

Graphic outline and central cut-out families are excluded from the first
sandbox because they break the approved inheritance rule. Spectral angular
mixing is removed; a spectral look may later return only through multiple
shifted radial fields.

## 6. Full-canvas composition

The laboratory scene uses the whole canvas. Its control panel is an overlay and
does not reserve the lower 42% of the procedural scene. A small physical edge
margin prevents accidental clipping, while deliberate near-depth cropping is
allowed.

Placement is deterministic but not displayed as a visible grid:

- candidate anchors cover top, middle, and bottom regions;
- anchors receive seeded jitter and may cross their initial region over time;
- actors may overlap by approximately 10...45% of their visible diameter;
- actors are not required to remain separated;
- no permanent center cluster or upper strip is allowed;
- with six or more actors, representative frames must contain centers in the
  upper, middle, and lower thirds;
- with eight or more actors, at least six of nine occupancy sectors must be
  represented across a short route sample.

Daily composition archetypes vary the hierarchy without reducing coverage:

- distributed field;
- diagonal current;
- edge-to-edge migration;
- asymmetric focal pair with satellites;
- depth constellation;
- soft crossing currents.

The archetype controls probabilities and route families, not fixed object
positions.

## 7. Motion and depth

Objects remain continuously animated unless Reduce Motion is enabled. Motion is
slow, smooth, and independently phased while sharing one daily choreography.

Allowed movement includes broad loops, bezier-like drift, shallow spirals,
Lissajous paths, and crossing currents. Direction, speed ratio, amplitude, and
phase vary per object. Rotation is minimal and never reads as spinning in place.

Each object has a continuous depth value. Depth controls several properties as
one perceptual system:

- moving closer increases apparent size;
- moving closer generally increases definition and contrast;
- moving farther reduces size, definition, opacity, and high-frequency detail;
- global sleep clarity is applied after local depth focus, so low sleep softens
  the whole canvas without destroying relative depth;
- small independent breathing may add approximately 2...5% scale variation,
  but it must not contradict the primary depth signal.

Depth and scale cycles take tens of seconds. No property may pop, flicker, or
switch direction at a phase boundary.

Steps continue to map to motion energy. At minimum energy, objects remain alive
through extremely slow drift and breathing rather than becoming a frozen image.
At maximum laboratory energy, movement remains calm enough to follow individual
objects.

## 8. Count growth

The scene supports one through ten happenings. Increasing the count makes the
composition richer through new scale classes, depth layers, crossings, and
overlaps.

Existing objects retain appearance identity when a new happening is added.
Routes may undergo a continuous bounded transition to admit the new object, but
there is no instant global rearrangement. Later objects may draw from a slightly
wider mutation envelope, including elongation expanding gradually from about
one percent to at most five percent. They remain inside the same daily family.

## 9. Sandbox controls and inspection

The existing Day Objects laboratory remains the entry point. Its count, motion,
and focus controls continue to work. Development-only inspection should make it
possible to review:

- family and mutation assignment;
- one, four, seven, and ten actors;
- frozen deterministic frames;
- full motion and Reduce Motion;
- local depth focus against global clarity;
- multiple consecutive day seeds;
- single view and contact-sheet view.

The contact sheet must use the same production scene construction as the single
view; it must not substitute a simplified preview generator.

## 10. Architecture changes

- Replace the broad `enabledMaterials` daily set with one `family` and one
  compatible `accentRecipe`.
- Model family-wide ranges separately from per-event sampled appearance values.
- Consume the existing size-band metadata in choreography instead of using the
  current narrow hard-coded diameter formula.
- Replace the laboratory lower exclusion rectangle with full-canvas placement.
- Replace discontinuous radial direction switching and angular spectral mixing
  with continuous layered radial fields.
- Couple depth, size, focus, opacity, and definition in choreography and shader
  inputs.
- Preserve stable per-event seeds and the existing two object palettes.

## 11. Performance constraints

- Maximum ten actors.
- One instanced actor pass.
- No per-frame allocation.
- No per-object textures or blur passes.
- Background sampling only where a family needs refraction.
- Analytic soft edges, halos, and layered radial fields inside the actor quad.
- Stable 60 Hz target on the supported physical iPhone profile.

## 12. Validation

Automated tests must verify:

- same day and event identifiers reproduce identical DNA and appearances;
- adding an event preserves retained appearances;
- every actor uses the day's family or its declared related accent mutation;
- elongation stays within the approved daily bound;
- size bands produce materially different diameters;
- six or more actors cover all vertical thirds;
- eight or more actors cover at least six occupancy sectors across sampled time;
- adjacent pose, scale, focus, opacity, and focal-field samples are continuous;
- scale and definition respond consistently to depth;
- Reduce Motion freezes routes and depth at deterministic poses;
- no angular/conic main fill is emitted;
- renderer layouts and Metal strides remain synchronized.

Visual acceptance requires multi-day captures at counts 1, 4, 7, and 10. The
captures must show coherent but different families, obvious scale hierarchy,
shifted radial centers, full-canvas distribution, slow independent motion,
stable color gradients, related accent mutations, overlaps, and readable depth.

## 13. Non-goals

- No production-screen rollout before sandbox review.
- No unrelated material mixture within a day.
- No image-based object textures.
- No particle confetti, rapid spin, hard color switching, or permanent flock.
- No redesign of the background gradient or palette catalog in this task.
- No final HealthKit wiring beyond preserving motion-energy and clarity inputs.

## 14. Acceptance summary

The sandbox is accepted when consecutive day seeds clearly differ, while every
object within one day looks inherited from one visual organism. One to ten
actors occupy and traverse the whole canvas, including its lower region. They
overlap and cross continuously, vary in color, size, depth, focal placement,
opacity, glow, and up-to-five-percent elongation, and become larger and clearer
when moving nearer and smaller and softer when moving farther. No object flickers,
flips its gradient, or becomes an unrelated visual genre.
