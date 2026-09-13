# Editorial Canvas Promotion

Date: 2026-09-06
Status: Approved in conversation; awaiting written-spec review
Branch: `codex/current-integration`

## Goal

Promote the approved Day Objects Editorial Field renderer from its laboratory
to the primary Canvas experience. Editorial becomes the default visual system
for today and newly created days. The existing production canvas remains fully
available as a `Legacy` appearance option, including its existing shapes,
fills, colors, gradients, textures, and interactive overlays.

Previously saved days must not change appearance retroactively. They continue
to render with Legacy unless they already carry an explicit renderer version.

## Superseded constraint

This specification supersedes only the laboratory-isolation constraint in
`2026-08-30-day-objects-editorial-field-design.md`. The approved Editorial
composition, visual DNA, palettes, Metal rendering, motion, grain, stable actor
identity, and negative visual constraints remain authoritative.

The Day Objects laboratory remains available in internal builds as a tuning
surface, but its controls and diagnostics are not copied into the main Canvas.

## Product behavior

### Canvas styles

The app has two explicit Canvas styles:

- `Editorial`: the Day Objects instanced Metal renderer, its procedural
  gradient background, generated shapes and materials, slow motion, sound
  resonance when a pulse source is present, and built-in procedural grain;
- `Legacy`: the current `GenerativeCanvasView`, current energy-gradient
  background, sleep and steps colors, shape and fill selection, image texture,
  and optional Smudge/Cosmic canvas overlays.

Editorial is the default selection after this feature ships. Legacy is a
compatibility style, not a separate laboratory.

### Settings

Settings > Appearance adds a top-level `Canvas style` picker with `Editorial`
and `Legacy` choices.

When Editorial is selected, Appearance exposes only controls that affect the
Editorial renderer, initially the existing modern palette-category selection.
Legacy-only background palettes, gradient styles, shapes, fills, raster
textures, and animation overlays are grouped under the Legacy selection and
retain their current values. Switching styles never erases either style's
preferences.

Changing the picker updates today's Canvas immediately and becomes the default
for future days. It does not rewrite previously completed days.

## Persistence and migration

Introduce a stable `CanvasVisualStyle` value with raw values `editorial` and
`legacy`. Store the selected style in two places with distinct responsibilities:

1. a shared preference stores the style to use for today and for newly created
   canvases;
2. an optional style field on `DayCanvas` freezes the renderer used by that
   particular day.

Migration rules are deterministic:

- a persisted day from before this feature, whose style field is absent,
  resolves to Legacy;
- on the first launch of this feature, the active current day is explicitly
  promoted to Editorial and saved once;
- a newly created day records the current style preference immediately;
- changing the setting rewrites only the active current day's style and the
  future-day preference;
- completed days never follow later preference changes;
- JSON and Supabase canvas sync carry the optional per-day field through the
  existing whole-canvas payload, requiring no database schema change.

A versioned local migration marker prevents the current-day promotion from
repeating. If a user deliberately chooses Legacy afterward, relaunching the app
must not switch it back.

## Shared rendering boundary

Add one shared artwork router used by the live Gallery canvas, history poster,
calendar thumbnail, and export paths. It accepts `DayCanvas`, health metrics,
palette preferences, render activity, and presentation context, then selects
exactly one renderer.

### Editorial input mapping

Editorial uses the existing `DayObjectSceneInput` boundary:

- `dayKey` supplies deterministic daily variation;
- stable `CanvasElement` identities supply stable event IDs;
- current element order does not redefine retained actor identity;
- steps progress maps to bounded motion energy;
- sleep progress maps to visual clarity and low-sleep treatment;
- spent color/energy state maps to the existing bounded digital impact;
- selected modern palette categories constrain the approved palette catalog;
- the main Canvas uses full-canvas coverage and no laboratory exclusion region;
- `usesEditorialField` is always true.

The renderer may adapt to full-screen and calendar-tile aspect ratios using its
existing normalized scene recipe. It must not substitute a Legacy composition
for small surfaces.

### Legacy input mapping

Legacy continues receiving the same `CanvasElement` models, day key, health
metrics, sleep and steps colors, decay, gradient choices, texture choice, and
overlay choice it receives today. No legacy palette or shape data is converted
to Editorial DNA.

## Grain and overlays

Editorial owns its grain inside the Metal post-process. Therefore:

- `TextureOverlayView` is never placed over an Editorial canvas;
- `EnergyGradientBackground` does not add another grain layer beneath it;
- Smudge and Cosmic overlays are not created for Editorial;
- the existing raster texture and overlays continue unchanged in Legacy.

This routing condition is structural rather than an opacity adjustment: the
unused image layer must not exist in the Editorial hierarchy, avoiding double
grain and unnecessary compositing work.

## Interaction

The primary Canvas controls remain shared:

- adding a happening inserts a stable Editorial actor;
- removing a happening removes the corresponding actor;
- retained actors keep their identity and do not jump to newly seeded roles;
- the existing insertion/removal envelopes remain active;
- slow continuous motion remains active whenever rendering is active;
- sound pulses may produce the already implemented bounded visual resonance,
  but no laboratory music controls are promoted by this work.

Legacy retains direct drag editing. Editorial does not expose direct actor
dragging in this first integration because positions are owned by the approved
composition planner. The editing affordance must not suggest that Editorial
objects can be dragged when that interaction is unavailable. Remix may change
an explicit deterministic variation value, but it may not alter stored
happening identities.

## Historical and static surfaces

Every surface resolves the per-day style rather than the current global
preference:

- existing historical days continue using Legacy live views and snapshots;
- Editorial days use Editorial in full-screen history and calendar tiles;
- share/export output uses the same scene input and deterministic time as the
  corresponding Editorial day;
- widgets or intents that cannot host live Metal use a renderer-produced static
  image, not `ImageRenderer` around an `MTKView`;
- cache keys include the Canvas style so Legacy and Editorial thumbnails cannot
  collide.

The first integration must not silently export a blank or Legacy image for an
Editorial day. If a Metal-backed static render cannot be produced safely, the
feature is not complete for that surface.

## Performance and lifecycle

Only the visible Editorial canvas animates. Grid thumbnails, off-screen pages,
and export renders are static. The existing rendering-activity and scene-phase
gates continue to pause GPU work when the canvas is not visible.

Switching between Editorial and Legacy destroys the inactive renderer instead
of keeping both GPU pipelines alive. No raster grain or legacy animation
overlay is allocated in Editorial mode.

## Accessibility

This promotion does not restore the removed Day Objects Reduce Motion product
mode. System accessibility settings continue to govern surrounding SwiftUI
transitions, but the Editorial renderer uses its current approved slow motion.

The style picker has explicit labels and selected state. Hiding Legacy-only
controls in Editorial must not leave inaccessible or focusable descendants.

## Scope boundaries

This change does not:

- alter the approved Editorial composition or material rules;
- delete the Day Objects laboratory;
- copy laboratory sliders, diagnostics, or instrument controls into Gallery;
- convert old Legacy shape/color settings into Editorial settings;
- update perceptual goldens before a new visual render is inspected;
- delete old canvases, snapshots, or user preferences.

## Verification

Targeted tests cover:

- absent per-day style resolving to Legacy;
- one-time promotion of only the active day;
- new-day inheritance and deliberate Legacy persistence;
- whole-canvas encode/decode and sync compatibility;
- renderer routing for live, history, tile, and export contexts;
- suppression of raster texture and Legacy overlays in Editorial;
- preservation of all Legacy inputs;
- stable Editorial event IDs through insertion and removal;
- cache separation by style.

Visual verification covers one Editorial current-day canvas, one Legacy current
day after switching Settings, one pre-existing Legacy historical day, one new
Editorial calendar tile, and one Editorial export. The Editorial samples must
show the same composition, materials, motion character, and grain as the
approved laboratory renderer.

A full test suite and one Simulator build run after targeted verification. Due
to the prior kernel instability, heavy commands run sequentially.
