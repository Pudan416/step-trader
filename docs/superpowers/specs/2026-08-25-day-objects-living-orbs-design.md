# Day Objects Living Orbs Design

Date: 2026-08-25
Status: Approved
Branch: `codex/day-objects-living-orbs`

## 1. Purpose

Replace the current Day Objects presentation of similarly colored actors gathered around one cluster with a calm, living field of at most ten individually colored procedural objects.

The new system must preserve a coherent daily visual language while making individual happenings visibly distinct. Objects drift across the whole canvas, occasionally overlap, move through depth and focus, and use varied radial, luminous, translucent, glass, membrane, and satin materials. The daily mesh background remains procedural but no longer shares its palette with every object.

## 2. Approved visual direction

The approved direction combines:

- **Drift Field** as the default full-canvas composition;
- **Depth Constellation** for near, mid, far, crisp, and defocused objects;
- **Glass Bloom** for restrained translucent, luminous, and layered accents;
- **Soft Encounters** as occasional pair or small-group interactions, never as the permanent scene layout.

The attached references and the approved comparison board establish the target qualities: varied scale, independent colors, soft internal gradients, shallow depth of field, translucency, restrained glow, and slow movement. The result must avoid a single central pile, identical actor materials, spinning in place, confetti, hard outlines, and rapid trails.

## 3. Dependency on modern palette catalog

This feature depends on PR #20, `selectable modern palette catalog`, commit `10457421` on `codex/modern-palette-catalog`.

PR #20 is currently based on the earlier remote `codex/day-objects-clean` at `badd56d5`; it does not contain the later orb implementation ending at `c91ba9f`. Implementation must first integrate `10457421` into the living-orbs branch and resolve overlaps without removing the current orb renderer, deterministic scene model, or the category-selection and persistence behavior from PR #20.

The feature must reuse `ModernPaletteCatalog`, `ModernPaletteCategory`, and the persisted category selection from PR #20. It must not introduce another palette catalog or make runtime Color Hunt requests.

## 4. Daily color system

### 4.1 Exactly three palettes

Each day deterministically selects exactly three distinct four-color palettes from the user's allowed `ModernPaletteCatalog` category union:

1. `backgroundPalette` for the animated mesh gradient;
2. `primaryObjectPalette` for roughly 60% of objects;
3. `secondaryObjectPalette` for roughly 40% of objects.

All three palette codes must differ whenever the allowed catalog contains at least three entries. The catalog currently guarantees a much larger pool for every selectable category. A defensive fallback may relax distinctness only if an invalid or externally modified catalog supplies fewer than three entries.

### 4.2 Compatibility and independence

The background palette is selected in an independent seed domain. The two object palettes are selected as a compatible pair from the remaining allowed entries:

- they must not be perceptually near-duplicates;
- they should share a compatible temperature or at least one nearby linking hue;
- together they must provide sufficient hue and luminance range for distinct actors;
- both must remain readable against the background palette;
- contrast correction may change luminance but must not replace the catalog's base hues.

Thus background and objects respect the same user-selected taste categories without appearing as one continuous gradient.

### 4.3 Allocation for at most ten objects

One unique happening creates one object. Duplicate event identifiers do not create duplicates. The rendered scene caps active objects at ten.

For `N` active objects:

- `N = 1`: use the primary object palette;
- `N = 2...3`: use both object palettes;
- `N >= 4`: allocate approximately 60% to the primary and 40% to the secondary palette, deterministically.

Every object uses one, two, or three colors from exactly one object palette. A four-color palette provides `C(4,1) + C(4,2) + C(4,3) = 14` unordered subsets, so six primary and four secondary assignments can all be unique without mixing the two palettes inside one object.

Exact base-color subsets must not repeat within one day. Color order, focal direction, material response, and lightness may add further variation but do not substitute for subset uniqueness.

## 5. Seed model and stability

The scene root remains derived from day key and user identity. Separate named seed domains must be used for:

- background palette;
- primary object palette;
- secondary object palette;
- daily visual language;
- daily choreography family;
- per-event appearance;
- per-event route;
- encounter schedule;
- depth schedule.

Per-event seeds are derived from the stable event identifier, not insertion index. Adding or removing another happening must not reroll an existing object's colors, material, size, route, or phase. Reopening the same day reconstructs the same scene.

## 6. Daily visual language

`DayObjectVisualLanguage` describes the shared DNA of one day:

- the three selected palette codes;
- three or four enabled material families;
- one dominant material family used by approximately 50...70% of actors when at least four are active;
- global light direction and softness;
- allowable circle-derived shape variation;
- choreography family and tempo range;
- encounter density;
- depth distribution;
- stable procedural grain intensity `0.05`.

The language creates family resemblance but must not store one shared radial fill for every actor.

## 7. Per-object appearance

`DayObjectAppearance` is derived independently for every event and contains:

- assigned object palette and unique 1...3 color subset;
- material family;
- circle-derived silhouette: sphere, ellipse, softly pinched lens, or soft organic blob;
- focal distance and angle;
- radius, falloff, mixing, distortion, distortion shift, and distortion frequency;
- internal and external glow strength;
- body, center, and rim opacity;
- refraction strength and direction;
- membrane layer count and offsets;
- local depth softness;
- light response and radial phase.

Organic deformation remains bounded so the body still reads as an orb. No silhouette may regress to triangles, petals, slabs, thin shards, or confetti.

## 8. Material families

Each day enables three or four of these six procedural families:

1. **Satin** — dense soft body, one to three blended colors, restrained highlight.
2. **Inner Glow** — luminous center with a darker or more transparent edge.
3. **Rim Glow** — subdued center with an outward luminous rim and analytic halo.
4. **Glass** — transparent body that softly refracts the immutable background texture and adds a controlled rim highlight.
5. **Membrane** — two or three offset translucent radial layers that create living overlap without separate bitmap assets.
6. **Spectral** — two or three colors with an asymmetric focal point and soft internal color migration.

The system selects parameters from curated ranges per family rather than from every legal shader extreme. It must allow shifted centers, internal glow, external glow, translucency, multiple colors, and controlled distortion while excluding harsh cartoon cross-sections and shapeless overexposed blobs.

At eight or more objects, at least three enabled material families must be visibly represented. The dominant-family rule preserves coherence; accent families supply glass, glow, and membrane moments.

## 9. Choreography

### 9.1 Long paths, not local spinning

Actors travel along smooth, deterministic, looping paths that cover a meaningful part of the canvas. A typical traversal of 20...70% of the canvas takes approximately 45...120 seconds at full lab motion.

Object geometry does not spin rapidly in place. Circular bodies need no visible rotation; focal direction, internal light, and tangent-aligned orientation may evolve slowly. Adjacent sampled positions and tangents must remain continuous.

### 9.2 Daily choreography families

The day selects one primary choreography family:

- **Drift Field** — independently directed full-canvas paths;
- **Cross Current** — two slow counterflows;
- **Tidal Sweep** — broad seeded waves through the canvas;
- **Depth Migration** — restrained planar travel with stronger near/far evolution;
- **Soft Encounters** — a higher, but still bounded, frequency of pair interactions.

Shared flow establishes choreography; per-event routes, phases, amplitudes, and directions prevent synchronized duplication.

### 9.3 Spatial distribution

The canvas is evaluated as a 3x3 occupancy grid for acceptance, not as nine visible layout cells. At eight or more actors, at least five sectors must contain actor centers in a representative frame, and route sampling over time must reach the full usable canvas.

The existing UI exclusion region remains protected. Composition constraints preserve deliberate negative space without forcing actors onto one focal anchor. No permanent central cluster is allowed.

### 9.4 Encounters

Seeded pairs or groups of at most four actors may approach, overlap by approximately 15...40% of their visible bodies, remain together for a bounded interval, and separate continuously. Most actors continue along independent routes while an encounter occurs. The entire scene must never converge into one pile.

### 9.5 Depth and focus

Every actor has a slowly evolving near, middle, or far depth state:

- near actors may be larger, softly defocused, and intentionally cross a non-UI canvas edge by at most 22% of their visible diameter;
- middle actors provide the crisp visual reference;
- far actors are smaller, quieter, and may carry additional blur.

Depth changes take tens of seconds and never pop. Per-object depth softness combines with the existing global `visualClarity`: sleep controls the whole-canvas focus, while depth supplies local relative focus. `motionEnergy` continues to scale the daily tempo and is the future integration point for steps.

Intentional near-depth edge cropping is part of the composition plan, deterministic, and never permitted to enter the UI exclusion region. Middle and far actors remain fully inside safe bounds. Accidental quad clipping, trail clipping, or crop beyond the planned 22% envelope is a failure.

Reduce Motion freezes route, depth, and material phase changes while preserving a stable composition and opacity-only insertion/removal behavior.

## 10. Rendering architecture

### 10.1 Separation of pose and appearance

Keep a compact per-frame pose buffer and add a one-to-one per-actor appearance buffer. The appearance buffer contains material identifier, three colors, radial parameters, opacity/refraction/glow parameters, and depth softness. Both Swift and Metal layouts must have explicit tested offsets, stride, and alignment.

Daily uniforms contain only genuinely shared values such as viewport, light direction, global time, and material-safe limits. They must no longer contain the only colors used by every body.

### 10.2 Pass order

1. Render the daily mesh gradient into an immutable background texture.
2. Composite the background into the scene target.
3. Render all bodies with one instanced actor pass, sampling the background texture only for glass refraction.
4. Produce glow and rim halos analytically inside the actor quad; do not allocate a blur texture per actor.
5. Apply the existing global sleep-driven post blur and display adjustments.
6. Add sharp stable procedural grain at intensity `0.05` as the final layer.

All actor output uses premultiplied alpha and deterministic depth ordering. Transparent overlaps must remain stable and must not read as opaque stickers.

### 10.3 Performance constraints

- Maximum ten active actors.
- No per-frame texture or buffer allocation.
- No bitmap material assets.
- One instanced body draw for all material families.
- Background sampling is bounded to the glass actor fragments.
- Renderer retains the existing in-flight buffer fencing.

A signed physical-device profile on the available iPhone 15 Pro must verify a stable 60 Hz presentation target, bounded memory, and no sustained thermal escalation during a five-minute ten-object lab run. If signing or device state blocks profiling, the result must be reported as unmeasured rather than inferred from simulator timings.

## 11. Transitions and count changes

Insertion and removal retain the current deterministic envelopes and capacity-aware scheduling, adjusted to a ten-object cap. A newly admitted actor begins its envelope only when it is first renderable. Adding an event does not restart or reroll retained actors.

Appearances and routes are stable across count changes. The composition may open a route for the new actor, but existing actors may only undergo continuous bounded avoidance, never a global instant re-layout.

## 12. Validation

### 12.1 Deterministic and model tests

- Three palette codes are distinct and come only from the selected PR #20 categories.
- The background and object palette seed domains are independent.
- Primary/secondary allocation follows the approved approximately 60/40 rule.
- Color subsets are unique for all counts `1...10`.
- Duplicate event IDs do not create duplicate actors.
- Existing actors retain appearance and route across insertion, removal, and relaunch.
- Daily material-family and dominant-family constraints hold.
- Non-finite inputs clamp to safe values.

### 12.2 Choreography tests

- Counts `1`, `4`, `7`, and `10` exercise every choreography family.
- At least five of nine sectors are occupied at representative frames for eight or more actors.
- Long-path travel, speed, tangent continuity, edge safety, and UI exclusion satisfy numeric bounds.
- Encounters overlap and separate without involving the whole scene.
- Depth and focus change continuously.
- Reduce Motion freezes geometry and depth.

### 12.3 GPU and visual acceptance

- GPU fixtures cover all six materials, all silhouettes, glass background sampling, premultiplied overlaps, glow, depth softness, and grain.
- A multi-day contact sheet demonstrates different palettes, materials, spatial layouts, and choreography families.
- Phone and tablet captures cover `1/4/7/10` actors, clarity `0/0.5/1`, motion `0/0.55/1`, light and dark palette categories, and Reduce Motion.
- Manual inspection rejects central piles, repeated color subsets, identical materials, hard cartoon banding, accidental clipping outside the intentional near-depth envelope, blank output, unreadable controls, and rapid visual jitter.
- Perceptual baselines are updated only after regenerated captures are explicitly reviewed.

### 12.4 Regression gates

- Exact Day Objects unit and UI suites.
- Full project unit and UI suites.
- Exact simulator app build.
- Signed physical-device build and install when the device is available.
- `git diff --check`, project-file lint, shader entry-point checks, and localization validation.

## 13. Failure handling

- Empty or invalid category selection falls back to all PR #20 categories, matching its existing behavior.
- Missing compatible palette candidates use the next deterministic distinct entries before relaxing compatibility.
- A device without the required Metal path uses the existing static-gradient fallback.
- Unsupported material values clamp to Satin.
- Failed background sampling disables refraction for that frame without hiding the actor.

## 14. Non-goals

- No new online palette service or second color catalog.
- No arbitrary ten-color gradient inside one actor.
- No raster texture overlays for materials or grain.
- No particle-system trails, fast local spinning, or permanent central flock.
- No redesign of application navigation, settings architecture, or non-Day-Objects canvases.
- No direct HealthKit mapping beyond preserving `motionEnergy` and `visualClarity` as the established integration inputs.

## 15. Acceptance summary

The design is accepted when a ten-happening day clearly contains ten stable, individually recognizable living objects: colors come from two coordinated PR #20 object palettes, exact color subsets do not repeat, at least three procedural material families are visible, actors occupy the canvas rather than one cluster, motion is slow and continuous, depth is legible, encounters are occasional, the independent mesh background remains animated, and the same day reconstructs identically.
