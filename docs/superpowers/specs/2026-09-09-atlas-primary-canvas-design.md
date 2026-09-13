# Atlas → current primary canvas

Status: implemented locally on 2026-09-09; not distributed or installed on a physical device. See the implementation plan for verification results and remaining validation.

## Approved scope

Update the existing Editorial primary canvas, not a new user-selectable style or a lab. Keep Legacy and historical saved canvases unchanged. Event identity and count remain authoritative (existing renderer capacity: ten active actors). The website's arbitrary count picker is not transferred into daily event data.

Transfer the current atlas, not the earlier September 7 catalog: selected legacy shapes, Snowflake, concave square, clover and their allowed materials. Preserve three Snowflake examples as examples of seeded geometry, not raster assets. Include circle-only sunset, early directional blur for triangle and square, independent blur rotations, restrained one/two-color fills, and transparent eclipse centers.

Transfer independent trajectory (vertical, horizontal, both diagonals, wave, arc, orbit, clusters), size rhythm (equal, random, grow, shrink, center, alternate), spacing, eligible silhouette families, and palette variations. Support homogeneous scenes as well as compatible mixtures. Glitch is static and seeded: stripes, channel separation, blocks, waves, repeated contours. Intersections: transparent mixing, luminous seam, overlay. Both effect strengths use 0–100; zero is a no-op. Exclude contour/glow/blur materials from solid intersection masks.

## Verified current architecture

- `DayCanvas` is Codable JSON with `visualStyleRaw` but no complete composition recipe.
- `EditorialCanvasInputFactory` regenerates scene input from day and element IDs; reads external palette-category preferences and live metrics.
- `DayObjectScene.make` reconstructs actors and `DayObjectSceneRecipeV1` from deterministic generators. Capacity is ten actors.
- `DayObjectsRenderer.encodeFrame` is shared by screen and offscreen export and already has glitch, insertion/removal, sound-response, background capture, and palette presentation paths.
- `MetalShapeGenomeCatalog`, `MetalShapeGenomeFrame`, and `MetalShapeGenomeShader.metal` contain the approved atlas geometry/material implementation, but are not wired into the main actor renderer.
- Website composition/effect implementations are in `.sites/nowhere-compositions/{composition-variation,intersection-effects,digital-trace}.mjs`. They are behavioral references, not runtime dependencies for iOS.
- `DayObjectsImageRenderer` uses the same renderer for export. Preserve this path.
- The existing September 7 deterministic-V2 document is planning only and its 37-shape/12-material catalog must not override the newer approved atlas.

## Persistence and compatibility

Add optional `artworkRecipe` to `DayCanvas`, with explicit schema/generator/catalog versions, stable seed, frozen palette/background parameters, ordered event-bound actor descriptors, composition parameters, glitch selection and intersection settings. Persist numeric data, not GPU objects or PNGs. A missing recipe continues through the old renderer. Do not infer a new recipe while decoding historical data or silently upgrade unknown versions.

New daily canvases receive a recipe once on creation. Existing saved canvases, including a saved current-day canvas, retain their appearance; do not silently migrate them. If the user later requests restyling an existing day, persist the new recipe as an explicit edit. This avoids changing saved images without authorization.

On new/removed events, preserve IDs, colors, seeds and material selections of existing actors. Placement follows stored composition parameters; changes needed to accommodate the new count are deliberate and use the existing transition machinery. Do not invent decorative events. Every actor descriptor must reference a real event ID.

Store material parameters and palette values, not only a seed: later catalog/palette changes must not reinterpret an archived recipe. Preserve optional recipe data in storage merge/restore and JSON sync. No database schema change is required for the existing full-canvas JSON payload, but round-trip and conflict behavior need tests.

## Rendering

Adapt the atlas's actual Metal geometry into the existing actor pipeline. Do not bypass render-frame metadata or replace the main view with a raster/web view: doing so would break interaction alignment, insertion/removal, sound response and backdrop capture. Extend actor frame/uniform data with the persisted descriptor. Historical inputs keep the old shader path.

Order: existing background → native shape/material pass → intersection compositing → selected static glitch → existing output conversion. Preserve render-target budgeting and color-space handling. Generate masks from filled actor coverage, not bounding boxes. The luminous seam must follow actual overlap boundaries, not full silhouettes. Zero effect strength must reproduce the unprocessed image.

The new glitch type replaces the old glitch pass for recipe-enabled artwork; do not stack two damage effects. Feed the existing spent-color damage value into 0–100 intensity, with saved overrides only if exposed by the existing editor. Do not change the app's economy. Preserve existing intentional animation and sound responses; geometry and glitch seed must not change with time.

## UI and rollout

Use existing canvas edit/remix controls. Add effect-type/strength/lock controls only to that existing surface; no new style selector or laboratory. Remix must retain event IDs and count. Respect existing allowed-shape and actor-color choices. Sunset participates in eligible circular compositions, never as a forced single-actor recipe.

## Verification gates

1. Decode historical fixtures with no recipe: old routing and render input remain identical.
2. Encode/decode a new recipe: exact event IDs, seeds, geometry/material values, effect selections and frozen colors survive.
3. Test count 0–10, duplicate events, add/remove, deterministic generation, palette/shape restrictions and unknown versions.
4. Test each layout/size mode and independent locks; same recipe yields same static frame.
5. Run actual Metal render probes for supported shape/material combinations, early blur, eclipse and sunset.
6. Verify nonoverlap is unchanged by intersection modes, seams exclude hollow/blur objects, and both effect strengths at zero are no-ops.
7. Verify preview/export route parity, thumbnails, background capture, event picking, insertion/removal and sound response.
8. Build the iOS target and run focused XCTest suites plus persistence/render regressions. Existing unrelated dirty changes must be preserved and baseline failures reported separately.

## Execution boundary

Implement inline, without subagents. The worktree contains substantial existing modifications; no broad reset, cleanup or blanket commit. Do not publish the website or change remote application data as part of this port.

## Local implementation notes

- Native rendering uses two bounded linear Metal intermediate targets and a final display pass, through the existing `encodeFrame`/offscreen entrypoint. The intermediate longest edge is capped at 1536 pixels; full-size output is upsampled. Device performance and full-resolution export quality still need physical-device validation.
- The native backdrop reuses the original mesh-gradient shader and scene settings. The final pass shares the original medium-scale grain and color finish; grain is applied after native softness and trace. Picker background time is held stable during selection. Geometry and composition are static; insertion/removal opacity, sound pulses, and sleep-driven clarity remain. The old orbital choreography is not applied to the new layouts.
- Approved refinement: the primary native background uses two maximally separated colors from its selected palette, optionally a third, with seeded field topology. Historical background selection stays unchanged. Available picker circles share one neutral tone; selection reveals color as well as geometry. Navigation and energy share a neutral smoked material with a dark backing, no cycling palette tint, and opaque fallback for reduced transparency.
- Dense interior procedural contours are excluded from new primary-canvas recipes; saved descriptors render as a simple outer contour without changing persisted event data. The picker starts with circles, reveals the native shape on selection, and becomes neutral gray after adding.
- The existing picker now resolves native geometry from the prospective element UUID, aliases it only for picker positioning, and retains saturation/removal feedback. Native palette variants rotate frozen colors; the Legacy shape allowlist remains a Legacy preference, while native shapes use atlas compatibility rules.
- No saved canvas, including today, receives an automatic recipe. New daily canvases opt in through `newDailyCanvas`; historical decoding still uses the unchanged initializer. Empty native canvases retain their recipe after the final event is removed.
- Review was performed inline to honor the user's request not to use subagents. No blanket commit or website deployment was made.
