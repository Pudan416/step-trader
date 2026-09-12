# Canvas components

This map describes the current native atlas path. This organization pass changes source boundaries, not artwork, audio behavior, saved data, or rendering architecture.

All paths below are relative to `StepsTrader/`.

## Saved artwork and composition

| Responsibility | File |
| --- | --- |
| Daily record and legacy defaults | `Models/DayCanvas.swift` |
| Frozen, versioned artwork payload | `Experiments/ShapeGenome/NativeAtlasRecipe.swift` |
| Root seed, initial choices, Remix locks | `Experiments/ShapeGenome/NativeAtlasRecipe+Generation.swift` |
| Event reconciliation, stable slots, paths and size rhythms | `Experiments/ShapeGenome/NativeAtlasRecipe+Composition.swift` |
| Catalog compatibility and editorial scene planning | `Experiments/ShapeGenome/MetalShapeGenomeCatalog.swift`, `MetalShapeScenePlanner.swift` |

The daily canvas remains driven by events, capped at ten. Removing or adding an event must retain the frozen actors belonging to other events. Random-number consumption order is part of `atlas-1`: changing it requires a deliberate version/compatibility decision, not an incidental cleanup.

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
