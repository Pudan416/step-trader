# Day Objects Daily Choreography Presets

Date: 2026-08-29
Status: Approved in conversation; awaiting written-spec review
Branch: `codex/current-integration`

## Goal

Make consecutive Day Objects scenes compositionally different, not merely
different in palette, material, object size, and route seed. Each day selects
one coherent choreography preset that jointly defines placement, size policy,
depth policy, focus, overlap, and movement relationships for up to ten actors.

The preset must allow flat days where all actors share one medium size and one
sharp focus plane, as well as spatial days with wide size variation, depth
migration, and deliberately blurred foreground actors.

## Daily selection

The day root seed selects exactly one `DayObjectChoreographyPreset`. The preset
is stable for the day and independent from the number or order of happenings.
It is selected alongside the daily circle material, with a small compatibility
weight table so that especially strong combinations occur more often without
forbidding unusual combinations.

The first production catalog contains ten presets:

1. `circularChoir`
2. `doubleOrbit`
3. `radialBloom`
4. `breathingGrid`
5. `waveRibbon`
6. `spiralProcession`
7. `eclipseStack`
8. `crossCurrents`
9. `constellation`
10. `depthField`

## Stable actor slots

Each preset defines ten stable slots. A slot contains a base anchor, path
phase, direction, size band, and depth role. An event maps to a slot using its
stable event seed. Removing, reordering, or adding another event does not
reroll an existing actor's appearance or slot.

Slot priority is composition-aware. Sparse scenes fill balanced positions
first. For example, an orbit fills top, bottom, left, right, and then diagonal
positions instead of filling adjacent angles sequentially. New actors fade and
scale into their own slots; existing actors do not jump to redistribute the
whole composition.

## Preset definitions

### Circular choir

- Uniform medium diameter with at most five-percent per-actor variation.
- One common depth plane near the camera focus depth.
- Ten balanced angular slots around a seeded circular or elliptical orbit.
- The entire formation rotates slowly; individual actors have restrained
  radial breathing and phase offsets.

### Double orbit

- One or two closely related medium diameters.
- Two concentric or offset rings on one sharp depth plane.
- Inner and outer rings move in opposite directions with a bounded speed ratio.
- Overlap is allowed where the rings intersect.

### Radial bloom

- Uniform or narrowly ranged medium actors.
- Radial spokes around a seeded, possibly off-canvas center.
- The formation opens and closes while rotating slowly.
- All actors remain approximately in focus.

### Breathing grid

- Uniform medium diameter and flat focus.
- A loose 2x5, 3x3, or staggered grid selected by the day seed.
- Positions drift only slightly; a slow scale wave travels through stable slots.
- The layout may be rotated or skewed but must remain recognizably ordered.

### Wave ribbon

- Uniform medium actors on one depth plane.
- One or two horizontal, vertical, or diagonal sine ribbons.
- A travelling wave changes perpendicular displacement and subtle scale.
- Actors preserve their order along the ribbon.

### Spiral procession

- Uniform or monotonically graded small-to-medium diameters.
- Actors occupy balanced positions on an open logarithmic spiral.
- The spiral rotates and slowly opens/closes without collapsing into one pile.
- Depth is flat or changes only slightly along the spiral.

### Eclipse stack

- Two or three closely related size groups.
- One or two deliberately overlapping clusters.
- Actors pass through one another and exchange front/back order slowly.
- Foreground members are larger and softer; middle members remain readable.

### Cross currents

- Uniform size within each of two groups.
- Two diagonal, curved, or orthogonal streams cross the canvas.
- Streams move in opposite directions and overlap briefly at intersections.
- Depth may differ slightly between streams but must not flicker.

### Constellation

- Small and medium actors in several distributed clusters.
- Each cluster drifts around a stable anchor while retaining its local shape.
- Moderate, bounded depth variation creates layering without a dominant giant.
- At six or more actors, the composition reaches all vertical thirds.

### Depth field

- Full size hierarchy, including very small distant and very large near actors.
- Independent continuous depth migration across the full canvas.
- Near actors may extend beyond the canvas and must receive the strongest local
  defocus; the middle focus plane stays crisp.
- This preset retains the current cinematic depth behavior and becomes the only
  preset where extreme foreground scale is routine.

## Size and focus profiles

Presets choose one of three explicit profiles:

- `uniform`: one seeded medium diameter with up to five-percent variation;
- `grouped`: two or three related size values assigned by stable slot;
- `spatial`: the current satellite/support/focal hierarchy, increased to the
  approved larger scale range.

Flat presets keep depth close to 0.55 and disable depth-derived size changes.
They remain globally affected by sleep clarity, so a low-sleep day still blurs
the complete canvas. Spatial presets use camera depth: middle-distance actors
are sharp, distant actors are soft, and very near actors are larger and more
strongly defocused.

## Movement

Every preset produces continuous loops with no discontinuity at the period
boundary. The day seed may vary orientation, center, ellipticity, wave axis,
ring count, direction, phase pattern, and bounded speed ratios. These
parameters are sampled as one preset configuration rather than independently
mixing incompatible movement rules.

Step count continues to control the shared tempo multiplier. Low steps make
the complete choreography nearly still but do not change its geometry.
`Reduce Motion` freezes route, depth, and breathing phase while retaining the
static composition.

## Material compatibility

All nine circle materials remain technically available with every preset. A
weighted compatibility map favors especially legible pairs:

- `outline`: circular choir, double orbit, wave ribbon;
- `glass`: eclipse stack, constellation, depth field;
- `luminous` and `halo`: radial bloom, spiral procession, depth field;
- `solid` and `sphere`: breathing grid, cross currents, circular choir;
- `mist`: constellation, eclipse stack, depth field;
- `gradient` and `counterform`: all presets.

One material recipe is still shared by all actors in a day. Compatibility
changes selection probability, never material inheritance within the day.

## Background gradient

The procedural gradient remains a separate moving layer behind the actors. It
continues to use the day's dedicated four-color background palette and remains
deterministic for that date. The background palette does not constrain the two
related palettes used by the actors.

Every day still selects a distinct gradient composition from the existing
`drift`, `orbit`, `tide`, `islands`, and `bloom` families. The day seed varies
the field center, node positions, scale, rotation, movement direction, phase,
distortion, and swirl. These parameters remain fixed as a coherent daily
configuration; only their continuous animation advances during the day.

Daily difference must come from the layout and motion of broad color fields,
not from narrow folds, stripes, hard ownership boundaries, or abrupt color
switches. Color interpolation therefore uses broad, softened radial influence
with support from neighboring colors throughout transition areas. Deformation
stays low-frequency and bounded, especially for `orbit` and `tide`, so even the
most energetic families retain wide blended transitions.

The five gradient families should remain visibly distinct:

- `drift`: large color clouds crossing the canvas independently;
- `orbit`: broad fields circling an off-center focus without forming rings;
- `tide`: slow directional flow with wide bends rather than bands;
- `islands`: separated soft color masses with blended surrounding water;
- `bloom`: colors expanding and receding from one or more offset centers.

Motion is slow and continuous. Colors, topology, and deformation parameters
never reroll or switch during a day. Frame-to-frame changes must be subtle
enough to avoid flashing while still producing visible movement over several
seconds. The procedural grain remains a stable overlay and must not be used to
hide gradient seams.

## Rendering and performance

The existing instanced Metal actor pass remains. Presets alter CPU-generated
pose data only and do not add per-object textures, render targets, or draw
calls. Maximum actor count remains ten. The existing procedural background pass
is retained, but its color-field interpolation and strongest deformation ranges
are softened. Sleep post-process, grain, palette allocation, insertion, and
removal pipelines stay unchanged.

## Acceptance criteria

- All ten presets are reachable and deterministic across day seeds.
- Every preset uses stable slots and preserves retained actors when the event
  list changes.
- Circular choir, breathing grid, radial bloom, and wave ribbon can produce
  scenes where all actors have nearly equal medium size and focus.
- Double orbit uses opposite directions; cross currents contain two opposing
  groups.
- Spiral procession preserves angular order and never collapses into a pile.
- Constellation distributes six or more actors across all vertical thirds.
- Depth field reaches the largest approved foreground scale and gives its
  nearest actors more local defocus than middle and distant actors.
- All paths and depth schedules remain continuous at their loop boundaries.
- All five background gradient families remain reachable, deterministic, and
  visibly different across a representative day-seed sample.
- Background transitions remain broad and smooth: no visible seams, narrow
  stripes, concentric rings, or sudden color ownership changes are introduced
  by the gradient shader.
- The four daily background colors remain represented without any single color
  taking over the full canvas for the complete animation loop.
- Small time steps produce bounded visual change with no flashing, while a
  several-second interval produces measurable movement.
- Grain remains stable in intensity and independent from gradient smoothing.
- Steps, sleep clarity, and Reduce Motion retain their existing responsibilities.
- Full Day Object model, choreography, Metal render, UI, and simulator build
  verification pass without modifying unrelated dirty files.
