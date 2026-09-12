# Day Objects HTML Circle Recipes Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Port the behavioral recipe system from `random-gradient-circle.html` into the Day Objects Metal renderer, including real outline and counterform days, smooth ordered radial color, and reliable visibility.

**Architecture:** Keep `DayObjectScene` and the single instanced actor pass. Replace the five generic material cases with nine HTML-derived daily recipes, derive bounded event mutations from the daily recipe, and interpret packed recipe parameters analytically in Metal. Use ordered radial stops for body color and reserve secondary fields for light, rim, outline, aura, and cutout effects.

**Tech Stack:** Swift 6, XCTest, Metal Shading Language, deterministic `SeededRNG`, Xcode/iOS simulator.

**Spec:** `docs/superpowers/specs/2026-08-28-day-objects-html-circle-recipes-design.md`

## Global Constraints

- One HTML-derived recipe per day and the same recipe for all actors in that day.
- One to three object colors; no angular or conic body fill.
- Maximum ten actors and one instanced draw.
- No per-frame randomness, bitmap material, or per-object render target.
- Steady-state objects remain visible over bright and dark backgrounds.
- Preserve stable retained appearances when events are inserted or removed.
- Do not stage or modify unrelated dirty worktree files.

---

### Task 1: Model daily HTML recipes

**Files:**
- Modify: `StepsTrader/Experiments/DayObjects/DayObjectVisualLanguage.swift`
- Test: `Steps4Tests/DayObjectPaletteTests.swift`

**Interfaces:**
- Produces: `DayObjectMaterialFamily` cases `gradient`, `solid`, `sphere`, `glass`, `mist`, `halo`, `luminous`, `outline`, `counterform`.
- Produces: recipe-derived outline count/width/spacing, counterform radius/softness, edge softness, and stable layer parameters on `DayObjectAppearance`.

- [x] **Step 1: Write failing reachability, inheritance, outline, counterform, ordered-radial, and opacity-floor tests.**
- [x] **Step 2: Run `DayObjectPaletteTests` and verify failures are caused by missing recipe cases and parameters.**
- [x] **Step 3: Implement weighted daily recipe selection and bounded per-event mutation sampled from the HTML ranges, adapted to one-to-three colors and at most three GPU layers.**
- [x] **Step 4: Run `DayObjectPaletteTests` and verify they pass.**

### Task 2: Pack recipe parameters for Metal

**Files:**
- Modify: `StepsTrader/Experiments/DayObjects/DayObjectRenderFrame.swift`
- Test: `Steps4Tests/DayObjectRenderFrameTests.swift`

**Interfaces:**
- Consumes: Task 1 appearance recipe and optical parameters.
- Produces: a 208-byte `DayObjectGPUAppearance`; `metadata.x` stores recipe raw value, `field.w` stores edge softness, and two aligned recipe vectors store ordered stops, visibility, outline, and counterform parameters. The extra vectors keep the recipe ABI explicit instead of overloading unrelated optical lanes.

- [x] **Step 1: Write failing packing tests for outline, counterform, visibility, and recipe identity.**
- [x] **Step 2: Run the focused packing tests and confirm the old five-family metadata fails.**
- [x] **Step 3: Pack and clamp the new recipe parameters in two aligned vectors and update the mirrored Swift/Metal stride to 208 bytes.**
- [x] **Step 4: Run the focused packing tests and verify they pass.**

### Task 3: Render smooth radial and structural recipes

**Files:**
- Modify: `StepsTrader/Metal/DayObjectsActorShader.metal`
- Test: `Steps4Tests/DayObjectRenderFrameTests.swift`

**Interfaces:**
- Consumes: Task 2 packed appearance.
- Produces: ordered scalar radial body color plus recipe-specific sphere, glass, mist, halo, luminous, outline, and counterform coverage.

- [x] **Step 1: Add failing GPU captures proving a smooth shifted radial fill, visible outline rings, a counterform opening/corona, and minimum steady-state coverage.**
- [x] **Step 2: Run those captures and confirm the existing weighted-lobe shader fails.**
- [x] **Step 3: Replace competing color-lobe normalization with ordered `smoothstep` radial stops and add analytic recipe coverage/effects.**
- [x] **Step 4: Run all `DayObjectRenderFrameTests` and verify premultiplied alpha, ABI, continuity, and recipe captures pass.**

### Task 4: Regression and build verification

**Files:**
- Verify all files from Tasks 1–3.

**Interfaces:**
- Produces: a simulator-installable main build containing the new Day Objects generator.

- [x] **Step 1: Run all Day Object palette, scene, choreography, and render tests.**
- [x] **Step 2: Build the complete `Steps4` simulator scheme and require `BUILD SUCCEEDED` with no new Metal warnings.**
- [x] **Step 3: Run `git diff --check` and confirm only Day Objects files, tests, spec, and plan are staged for the feature.**
- [x] **Step 4: Commit the verified implementation on `codex/current-integration`.**
