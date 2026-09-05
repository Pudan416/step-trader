# Day Objects Harmonic Weave Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a deterministic Harmonic Weave construction mode to Day Objects Lab while preserving existing Editorial Field composition, palettes, motion, and actor identity.

**Architecture:** Extend the existing daily visual language with one scene-level weave dialect and deterministic actor-local weave parameters. Pack those parameters into the existing appearance recipe vector and render an antialiased polar interference weave inside circle-derived carrier envelopes in the existing instanced Metal draw.

**Tech Stack:** Swift, XCTest, SwiftUI, Metal Shading Language, existing Day Objects deterministic seed system.

**Spec:** `DesignReferences/DayObjects/composition/08-harmonic-weave-construction-reference.md`

## Global Constraints

- Day Objects remains available only in the existing Lab.
- Do not change the main canvas or main Gallery.
- Preserve Editorial Field placement, scale, depth, overlap, cropping, and negative space.
- Preserve actor identity when happenings are inserted, removed, or reordered.
- One-color actors remain one-color; multicolor actors use only broad smooth radial fields.
- No rapid local rotation, per-frame rerolling, visible points, hard angular gradients, or unstable hairlines.
- Keep the existing one instanced actor draw and existing appearance-buffer stride.
- Do not update perceptual goldens during this visual experiment.

---

### Task 1: Deterministic Harmonic Weave DNA

**Files:**
- Modify: `StepsTrader/Experiments/DayObjects/DayObjectComposition.swift`
- Modify: `StepsTrader/Experiments/DayObjects/DayObjectVisualLanguage.swift`
- Modify: `StepsTrader/Experiments/DayObjects/DayObjectChoreographyPreset.swift`
- Test: `Steps4Tests/DayObjectPaletteTests.swift`
- Test: `Steps4Tests/DayObjectSceneTests.swift`

**Interfaces:**
- Produces: `DayObjectMaterialFamily.harmonicWeave`
- Produces: `DayObjectHarmonicWeaveDialect`
- Produces: `DayObjectHarmonicWeaveStyle`
- Produces: `DayObjectAppearance.harmonicWeaveStyle: DayObjectHarmonicWeaveStyle?`
- Produces: `DayObjectShape.softStar`, `.roundedPolygon`, and `.roundedSquare`

- [ ] **Step 1: Write failing deterministic DNA tests**

```swift
func testHarmonicWeaveDayUsesOneDialectWithCircleDerivedCarrierVariety()
func testHarmonicWeaveActorStyleSurvivesInsertionRemovalAndReorder()
func testHarmonicWeaveParametersRemainInsideApprovedRanges()
```

- [ ] **Step 2: Run the focused tests and verify RED**

Run:

```bash
xcodebuild test -project Steps4.xcodeproj -scheme Steps4 \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro' \
  -only-testing:Steps4Tests/DayObjectPaletteTests \
  -only-testing:Steps4Tests/DayObjectCompositionTests
```

Expected: compile failure because the harmonic weave material, dialect, style,
and carrier cases do not exist.

- [ ] **Step 3: Add the minimal deterministic model**

Implement one day-level dialect chosen from the root seed. Generate actor-local
carrier, phase, density, aperture, and line width from the event seed. Restrict
carrier variety to the new weave material and keep one or two conspicuous
low-lobe actors at most through stable mutation roles.

- [ ] **Step 4: Run the focused tests and verify GREEN**

Run the command from Step 2. Expected: PASS.

- [ ] **Step 5: Commit the DNA model**

```bash
git add StepsTrader/Experiments/DayObjects/DayObjectComposition.swift \
  StepsTrader/Experiments/DayObjects/DayObjectVisualLanguage.swift \
  StepsTrader/Experiments/DayObjects/DayObjectChoreographyPreset.swift \
  Steps4Tests/DayObjectPaletteTests.swift Steps4Tests/DayObjectSceneTests.swift
git commit -m "feat: add harmonic weave day object DNA"
```

### Task 2: Existing-ABI Metal Rendering

**Files:**
- Modify: `StepsTrader/Experiments/DayObjects/DayObjectRenderFrame.swift`
- Modify: `StepsTrader/Metal/DayObjectsActorShader.metal`
- Test: `Steps4Tests/DayObjectRenderFrameTests.swift`

**Interfaces:**
- Consumes: `DayObjectAppearance.harmonicWeaveStyle`
- Produces: harmonic recipe packing in `DayObjectGPUAppearance.recipe1`
- Produces: material raw value `9` in `dayObjectsActorFragment`

- [ ] **Step 1: Write failing ABI and render-sensitivity tests**

```swift
func testHarmonicWeaveRecipePacksWithoutChangingAppearanceStride()
func testHarmonicWeaveCarrierAndDialectChangeRenderedPixels()
func testReduceMotionKeepsIdenticalHarmonicWeaveIdentityAtRest()
```

- [ ] **Step 2: Run the focused tests and verify RED**

Run:

```bash
xcodebuild test -project Steps4.xcodeproj -scheme Steps4 \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro' \
  -only-testing:Steps4Tests/DayObjectRenderFrameTests
```

Expected: failures because no harmonic recipe is packed or rendered.

- [ ] **Step 3: Pack four bounded parameters in the existing recipe vector**

Pack primary frequency, secondary frequency/density, aperture, and line width.
Keep `DayObjectGPUAppearance.metalStride == 208`.

- [ ] **Step 4: Render the weave in the existing actor fragment**

Add rounded circle-derived carrier envelopes and an antialiased, phase-related
polar weave. Use the existing broad radial color field for line color. Freeze
local phase under Reduce Motion and retain whole-actor motion otherwise.

- [ ] **Step 5: Run the focused tests and verify GREEN**

Run the command from Step 2. Expected: PASS.

- [ ] **Step 6: Commit the renderer**

```bash
git add StepsTrader/Experiments/DayObjects/DayObjectRenderFrame.swift \
  StepsTrader/Metal/DayObjectsActorShader.metal \
  Steps4Tests/DayObjectRenderFrameTests.swift
git commit -m "feat: render harmonic weave day objects"
```

### Task 3: Lab Visual Checkpoint

**Files:**
- Modify only if required for discoverability: `StepsTrader/Experiments/DayObjects/DayObjectsLabView.swift`
- Create: `artifacts/day-objects-harmonic-weave/preview.png`

**Interfaces:**
- Consumes: the real `DayObjectScene` and instanced Metal renderer.
- Produces: one representative ten-happening Lab screenshot for user review.

- [ ] **Step 1: Identify a deterministic day key selecting Harmonic Weave**

Use a small read-only seed scan or a focused test helper. Do not add a fixed
production preset.

- [ ] **Step 2: Build and run the Lab once in Simulator**

Use the available simulator and one build at a time. Do not run a full suite in
parallel.

- [ ] **Step 3: Capture the real Metal output**

Capture one ten-happening full-screen frame showing at least three carrier
phenotypes and readable line accumulation.

- [ ] **Step 4: Review observable acceptance points**

Confirm the frame keeps Editorial Field hierarchy and negative space; does not
look like a centered specimen sheet; has no sharp star points, pupils, broken
paths, moire, or dirty color accumulation.

- [ ] **Step 5: Run the final targeted regression set**

```bash
xcodebuild test -project Steps4.xcodeproj -scheme Steps4 \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro' \
  -only-testing:Steps4Tests/DayObjectSceneTests \
  -only-testing:Steps4Tests/DayObjectPaletteTests \
  -only-testing:Steps4Tests/DayObjectRenderFrameTests
```

- [ ] **Step 6: Commit Lab-only discoverability if it was needed**

```bash
git add StepsTrader/Experiments/DayObjects/DayObjectsLabView.swift
git commit -m "feat: expose harmonic weave in Day Objects Lab"
```

