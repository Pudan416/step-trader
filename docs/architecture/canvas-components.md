# Canvas components

This map describes ownership in the current native atlas path and compatibility rules for existing artwork.

All paths below are relative to `Nowhere/`.

## Saved artwork and composition

| Responsibility | File |
| --- | --- |
| Daily record and legacy defaults | `Models/DayCanvas.swift` |
| Frozen, versioned artwork payload | `Experiments/ShapeGenome/NativeAtlasRecipe.swift` |
| Root seed, initial choices, Remix locks | `Experiments/ShapeGenome/NativeAtlasRecipe+Generation.swift` |
| Event reconciliation, stable slots, paths and size rhythms | `Experiments/ShapeGenome/NativeAtlasRecipe+Composition.swift` |
| Frozen daily family, coordinated colors, stable family composition | `Experiments/ShapeGenome/NativeAtlasDailyStyle.swift`, `NativeAtlasRecipe+DailyStyle.swift` |
| Bounded idle offsets and music handoff | `Experiments/ShapeGenome/NativeAtlasAmbientMotion.swift` |
| Catalog compatibility and editorial scene planning | `Experiments/ShapeGenome/MetalShapeGenomeCatalog.swift`, `MetalShapeScenePlanner.swift` |

The daily canvas remains driven by events, capped at ten. Removing or adding an event must retain the frozen actors belonging to other events. Random-number consumption order is part of `atlas-1`: changing it requires a deliberate version/compatibility decision, not an incidental cleanup.

New days use `atlas-2`, with an optional frozen `dailyStyle` payload. A shuffled
six-day calendar cycle chooses circles, blobs, squares, clovers, flowers or rays,
without adjacent repeats. Squares choose one contour for the day; flowers share
their petal count. Rays use the existing directed diffuse-beam branch: stable
`legacy.rounded-triangle` geometry (source kind 1, shape 5, variant 5) plus
`directionalBlur`. The triangle body is replaced by the tapered light cone in
that material; other daily families do not select this fill. Triangle and hexagon outlines remain decodable but are excluded from new
daily families; the beam uses its triangle only as the compatible shader carrier.
Shape and orientation are frozen once; actors inherit the family and occupy
independent stable slots. Explicit palette changes coordinate current and future
actors with the background.

The selected A policy uses optional `appearancePolicyVersion = 1`, frozen
`neighboringPigments` and `neighboringPaletteCategories`. Three nearby catalog
palettes are ranked by their average nearest-anchor OKLab distance. Borrowed
pigments must fit the anchor hue/chroma group and a distance limit of 0.20;
farthest-point ordering gives sparse days distinct leading pigments. Noir uses
only its monochrome anchors. The pool is generated at creation, first current-day
upgrade or an explicit background palette change, never during ordinary rendering.

Saved slots choose one-tone, one-tone, `radialTwo`, then contour roles. A preset
that does not allow solid uses equal-color side light for the one-tone role.
Two-color shading uses one pigment with a lightness difference of 0.08 and no
third contrasting color. Color variants tint the slot's leading pigment by
10–18% toward another frozen member; default picker identity hashes therefore
do not replace the assigned leading hue. Non-beam sizes range from 0.15 to 0.41.
Beams use `directionalBlur` mode 0 or gentle two-color mode 2, sizes multiplied
by 1.8 with a 0.30 floor. Each actor freezes its own material and size, so
additions and removals do not reroll survivors.

Styles without `appearancePolicyVersion` retain the earlier ordered palette,
materials and size policy. The optional
`livingVariation` policy adds a seed-stable tint toward one existing palette member (12–32%), lightness
variation of up to 0.055 and chroma at 68–88%, retaining the stop order and soft
lightness cap. Each stable slot has a large, medium or small size tier, clamped
to 0.65–1.25 of the family baseline with slight event-seeded jitter. Shared
materials have bounded light-direction/position variation. These actor values
are frozen when generated; adding or removing events does not reroll survivors.
The directed beam is a single-color light role: its mode-0 `color0` selects a
seed-stable pigment from the brighter half of the daily palette and fits OKLab
lightness to 0.72–0.82 with chroma at most 75%. Its diffuse alpha is unchanged.
The optional `sharesPaletteOrder` flag preserves the prior color policy when
decoding archived atlas-2 artwork without this flag.
New/current daily styles also opt into `softGradients`: the selected hues retain
their shared order and OKLab lightness spread is capped at 0.19, with hue-preserving
gamut fitting. Styles without `livingVariation` retain their 75% chroma policy.
Procedural light uses broader, normalized overlapping lights and a blended highlight rather than a clipped
terminal-color core. Its opt-in marker uses the high bit of material
`metadata.y`; the 128-byte CPU/GPU layout and unflagged shader path stay exact.
Gallery adopts this policy for today's complete, editable Editorial canvas,
including a saved empty or populated `atlas-1` day, before persisting and syncing
it. Event IDs, saved placements, metrics and music selection survive adoption.
It also normalizes older actor visuals imported during cloud recovery. The
first A adoption rebuilds sizes and mixed materials from each saved slot and
freezes its neighboring pigment pool. The earlier `livingVariation` boundary
also converts radial Snowflake rays into directed beams. Both preserve event
IDs, positions, rotations and slots. Further A adoption retains the frozen
sizes, per-actor materials and pigment pool. Missing optional flags preserve
historical generation and motion. Pending drafts wait for the confirmed merge;
artwork locks and historical days remain frozen. Decoding never upgrades a recipe. An unlocked Remix can explicitly
generate a new daily recipe.

Idle motion applies seeded drift, breathing and bounded turns around those
frozen slots at render time. It never writes positions back to persistence.
With A, drift and bounded turns take 12 seconds; breathing takes six seconds.
Four motion roles have drift half-amplitudes of 0.045, 0.053, 0.025 and 0.038
canvas widths, and breathing half-amplitudes of 3.5%, 9.5%, 5.5% and 2%.
The full saved slot and day seed choose the phase, so later slots do not move
in lockstep with earlier ones. Circles drift and breathe; other families also
sway, and rays glide along their own axis. With the older `livingVariation`,
drift takes 14–24 seconds, breathing 9–15 seconds and
slow bounded turns 50–85 seconds; each actor retains at least 78% of its family
motion strength. Directed beams sweep by at most 0.14 radians. Unflagged styles
retain the previous periods and amplitudes. The native adapter fades offsets
during music handoffs; existing lunar physics still owns playback and its return animation. Reduce Motion disables the idle
offsets. Picker slots never inherit Canvas motion, and the paused Canvas clock
keeps artwork still behind the picker. Active new canvases request 30 FPS even
with music off; visibility and scene lifecycle still gate rendering. Offscreen
renderers default to the saved pose, while capture through the live renderer
uses its current elapsed time.

## Shape geometry

CPU parameter generation lives in `Experiments/ShapeGenome/Geometry/`:

- `MetalShapeSnowflake.swift`: parameters and the legacy folded Snowflake family.
- `MetalShapeWindflower.swift`: variable three/five/seven-petal family.
- `MetalShapeConcaveSquare.swift`: inward-curved square.
- `MetalShapeSoftClover.swift`: rounded four-lobe family.

`MetalShapeGenomeFrame+Geometry.swift` packs these parameters for Metal. `MetalShapeAtlasRandom.swift` is the shared deterministic random source. `MetalShapeGenomeUniforms.swift` and `MetalShapeMaterialUniforms.swift` define the saved CPU/GPU payloads; preserve their 128-byte strides and field order.

Matching GPU geometry is in `Metal/ShapeAtlas/Geometry/`. `MetalShapeBasic.metalh` shares the circle/polygon/rounded-square calculations; simple parameter variations do not need duplicate implementations. `MetalShapeGenome.metalh` contains the superformula family. `MetalShapeDistance.metalh` dispatches the stable geometry IDs and applies transforms.

## Materials, backgrounds and trace

`Metal/ShapeAtlas/Materials/MetalShapeMaterials.metalh` is the material dispatcher. Side light, contour, directional blur, radial color, procedural light/flow/contour, eclipse glow and sunset each have a focused header. Solid color is the default body coverage; there is no extra shader/pass just to return a color. Two- and three-color radial fills share one radial implementation.

- Palette parameter generation: `Experiments/ShapeGenome/MetalShapeGenomeFrame+Palette.swift`.
- Background rendering: existing `Metal/DayObjectsMeshGradientShader.metal`.
- Background style parameters: existing `Experiments/DayObjects/DayObjectMeshGradientStyle.swift`.
- Overlap blending and luminous seams: `Metal/NativeAtlasComposite.metal`.
- Native seeded digital trace: `Metal/NativeAtlasDisplay.metal`.
- Final grain: `Metal/Post/DayObjectsGrain.metalh`.
- Existing non-atlas digital impact: `Metal/Post/DayObjectsDigitalImpact.metalh`.
- Shared blur/final color entry points: `Metal/DayObjectsPostShader.metal`.

Headers compile into their consuming shader translation units. This split does not introduce a render pass per material or per shape.

Smudge uses a static color field in `Views/Components/SmudgeCanvasView.swift`,
drawn by `EnergyGradientRenderer.drawColorField`. This input must retain color
variation in Release: the screen-facing `EnergyGradientBackground` intentionally
returns a neutral surface there and cannot serve as the effect's source.
`SmudgePreparationTests` checks source pixels and a complete gesture-driven Metal
frame in Release; the Release CI job retains those images. The effect keeps its
existing independent color field rather than capturing a second live artwork renderer.
Musical gesture begin/update/end callbacks run immediately, before GPU preparation.
Only visual commands may wait for the renderer and source texture. The Release
controller regression verifies that playing music receives a complete gesture
before Metal is ready and does not replay it when preparation finishes.

## Rendering ownership

`Experiments/ShapeGenome/NativeAtlasMetalRenderer.swift` owns the native live/export pipelines and reusable textures. `MetalShapeGenomeRenderer.swift` is the separate atlas-preview renderer. `Experiments/DayObjects/DayObjectsRenderer.swift` remains the higher-level host for the native and existing editorial paths.

Do not put UI state, event persistence, or recipe generation inside a fragment shader or the GPU resource owner. Do not create per-frame pipelines/engines to make source files independent.

## Audio ownership

Under `Experiments/DayObjects/Sound/Engine/`:

| File | Owns |
| --- | --- |
| `DayObjectsInstrumentBank.swift` | Instrument preparation, orchestration and bank lifecycle |
| `DayObjectsPoolAdapters.swift` | Category validation and adapters for existing voice pools |
| `DayObjectsAudioKitInstrumentBankGraph.swift` | A bank's role buses and graph wiring |
| `DayObjectsPersistentMasterGraph.swift` | Shared master processing, metering and output gain |
| `DayObjectsAudioKitInstrumentBankEngine.swift` | Single-bank engine adapter |
| `DayObjectsPlaybackBankPair.swift` | Shared-engine ownership and two-bank switching |

Instrument implementations (tonal, piano, drums, happening samples) remain in their existing files. Harmony, rhythm, bass, lead, glitch and mixing planners are already separate under `Sound/Director/`. World recipes, groups and licensed samples remain in `Sound/Resources/`, loaded and validated through `Sound/Domain/DayObjectsSoundWorldCatalog.swift`.

Only coordination methods/types needed across the extracted files become internal. DSP values, node allocation, playback leases, start/stop sequencing and conditional build flags are unchanged.

## Adding or retiring a component safely

1. Add geometry parameters and the corresponding GPU function, then register the preset in `MetalShapeGenomeCatalog`. Preserve the ordering of existing presets for existing generator versions.
2. Declare compatible materials in the preset policy. Sunset remains circle-only; dense procedural contour remains excluded from primary-canvas generation.
3. To retire a shape from **new generation**, change the versioned selection policy. Do not delete a decoder, shader branch or enum value still referenced by saved canvases.
4. Material indices come from `MetalShapeMaterial` order. Never reorder/remove old cases as a shortcut; new meanings must not reinterpret old saved uniforms.
5. Audio worlds are validated as a complete compatible catalog. Removing a world is a coordinated change to selection, recipe/group validation and fallback behavior, not just deleting a sample file.
6. Add Swift and `.metal` source files to the application target. `.metalh` files are included headers, not separate compilation units.

## Verification and scope

Regression suites cover geometry/Metal ABI, actual material rendering, deterministic recipes, historical decoding, event reconciliation, Remix, catalog validity, and audio graph/lifecycle behavior. A source split is not a performance improvement claim; device profiling before merge is a separate step.

This is not a wholesale rewrite of the legacy renderer. Large existing files such as `DayObjectsRenderer.swift`, `DayObjectSceneRecipeV1.swift`, `DayObjectPaletteSet.swift` and `DayObjectsTonalVoice.swift` still deserve a separate, targeted review when their behavior is changed. They are not silently replaced here.
