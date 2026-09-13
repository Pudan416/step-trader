# Canvas component boundaries implementation plan

> **For agentic workers:** Use superpowers:executing-plans to implement this plan task-by-task. Keep this work in the existing current-integration worktree.

**Goal:** Separate independently editable visual/audio mechanisms without changing saved artwork, rendering passes, or playback.

**Architecture:** Preserve existing type names and entry points. Extract complete definitions into focused Swift files and Metal include modules; catalogs remain explicit ordered registries. Keep runtime resource ownership and random-number consumption unchanged.

**Tech Stack:** Swift, SwiftUI, Metal, AudioKit, XCTest.

**Spec:** User-approved boundaries in this conversation: geometry, materials, composition, audio instruments/worlds and common rendering separated; no wholesale rewrite.

## Global constraints

- Preserve existing uncommitted viewing-menu and rotation changes.
- No changed Codable keys, preset IDs, material indices, seeds or RNG call order.
- No new GPU passes, textures, audio nodes, timers or dependencies.
- Keep saved unsupported/historical recipes intact; disabling generation is not deleting historical render support.
- Do not merge, push, install, or alter unrelated files as part of this organization pass.

## Task 1: Establish regression baseline

- [x] Run MetalShapeGenomeFrameTests, MetalShapeContourTests, MetalShapeGenomeCatalogTests, MetalShapeCompatibilityTests, MetalShapeScenePlannerTests, CanvasPersistenceRegressionTests, CanvasRemixTests, DayObjectsSoundWorldCatalogTests and DayObjectsInstrumentBankTests before moving code.
- [x] Preserve original source text for mechanical comparison. Existing rendering/ABI, seeded generation, persistence, audio graph and lifecycle tests are the behavior contract for this extraction-only refactor.

## Task 2: Separate Swift artwork responsibilities

- [x] Move NativeAtlasRecipe from Models/DayCanvas.swift to Experiments/ShapeGenome/NativeAtlasRecipe.swift; put make/remixed into NativeAtlasRecipe+Generation.swift and reconciled into NativeAtlasRecipe+Composition.swift without changing signatures or statements.
- [x] Move MetalShapeGenomeUniforms and MetalShapeMaterialUniforms to dedicated files; move each shape's parameter type and generator from MetalShapeGenomeFrame.swift to Geometry/MetalShape{Snowflake,Windflower,ConcaveSquare,SoftClover}.swift. Keep shared RNG in MetalShapeAtlasRandom.swift.
- [x] Move geometry packing and material palette helpers into MetalShapeGenomeFrame+Geometry.swift and MetalShapeGenomeFrame+Palette.swift. Remove private only from the helpers used across those extensions.
- [x] Move NativeAtlasMetalRenderer out of the preview renderer file. Preserve pipeline creation and live/export entry points verbatim.

## Task 3: Separate Metal mechanisms

- [x] Keep MetalShapeGenomeShader.metal as the preview entry point; create ShapeAtlas/MetalShapeUniforms.metalh with the existing shared ABI.
- [x] Extract complete geometry functions into ShapeAtlas/Geometry headers, with MetalShapeDistance.metalh composing them.
- [x] Extract material branches into static functions in ShapeAtlas/Materials headers, keeping arithmetic and evaluation order. MetalShapeMaterials.metalh dispatches the stable material IDs.
- [x] Move nativeAtlasComposite and nativeAtlasDisplay unchanged into NativeAtlasComposite.metal and NativeAtlasDisplay.metal. No extra render passes.
- [x] Extract existing grain and digital-impact helpers from DayObjectsPostShader.metal into Post/DayObjectsGrain.metalh and Post/DayObjectsDigitalImpact.metalh. Preserve the existing final display and blur entry points.

## Task 4: Separate audio graph ownership

- [x] Keep DayObjectsInstrumentBank's orchestration class in its original file.
- [x] Move complete pool adapters, bank graph, persistent master graph, engine adapter, and playback pair into correspondingly named Swift files under Sound/Engine. Keep helper types private unless another extracted file needs them; expose only the existing coordination methods as internal.
- [x] Preserve conditional compilation, graph wiring, gains, DSP parameters and startup/stop order. Existing instrument/world catalogs and resource files remain unchanged.

## Task 5: Integrate and verify

- [x] Register new Swift and Metal translation units in the existing application Sources phase. Header modules are includes, not extra translation units.
- [x] Re-run the baseline suites, verify no missing Metal functions and unchanged ABI, then build the iPhone Debug target.
- [x] Add docs/architecture/canvas-components.md with exact entry points, add/disable instructions, historical compatibility rules and remaining large legacy files.
- [x] Review diff for behavior changes and report the result as local changes; do not claim a performance audit or a pushed PR.

## Verification results

- Before extraction: 127 tests passed, 0 failed/0 skipped (2026-09-09 18:32 run).
- After primary extraction: the same 127 tests passed, 0 failed/0 skipped (18:38 run).
- After extracting background style and narrowing header dependencies: 62 material/palette tests passed, 0 failed/0 skipped (18:47 run).
- Generic iOS Debug build completed successfully; signing disabled for this build-only check. No phone installation performed.
- Mechanical comparison confirmed unchanged audio class statements, geometry functions, native overlap/trace fragment bodies and background generation. Visibility/import changes only for extracted Swift types; material branch arithmetic retained in static helper functions.
- Existing compiler warnings remain (including the unused Metal coverage helper and Swift concurrency warnings in test doubles). This is not a warning-cleanup or performance-profiling pass.
- Existing menu/rotation changes remain untouched. All work is local on codex/current-integration; no commit or push.
