# Smooth Day Object Backgrounds Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Keep the five deterministic moving four-color backgrounds while replacing hard color boundaries, rings, and folds with broad continuous fields.

**Architecture:** Retain `DayObjectMeshGradientStyle`, its 128-byte Metal ABI, and the existing half-resolution render pass. Tighten the seeded deformation ranges in Swift, then replace sharp inverse-distance ownership in Metal with broad normalized radial-basis weights plus a small global support floor. GPU tests measure spatial smoothness, family distinction, palette presence, and bounded temporal motion.

**Tech Stack:** Swift, Metal Shading Language, XCTest GPU offscreen rendering, existing Day Objects renderer.

**Spec:** `docs/superpowers/specs/2026-08-29-day-object-choreography-presets-design.md`

## Global Constraints

- Keep exactly five reachable families: `drift`, `orbit`, `tide`, `islands`, and `bloom`.
- Keep one complete four-color application palette per day and do not couple it to actor palettes.
- The same date and identity must return the same topology, parameters, colors, and direction.
- Motion remains continuous and visible over several seconds, with no frame-to-frame flashing.
- Remove visible seams, narrow stripes, concentric rings, and abrupt color ownership changes.
- Preserve `DayObjectsMeshGradientUniforms` alignment 16, size 128, and stride 128.
- Keep the existing half-resolution background target and add no render passes or textures.
- Grain remains a separate stable overlay and is not used to hide seams.
- Preserve unrelated dirty files and stage only files named in each task.

## File map

- Modify `StepsTrader/Experiments/DayObjects/DayObjectPalette.swift`: curated low-frequency range table for five gradient families.
- Modify `StepsTrader/Metal/DayObjectsMeshGradientShader.metal`: softened domain warps and radial-basis color blending.
- Modify `Steps4Tests/DayObjectPaletteTests.swift`: deterministic range tests and GPU spatial/temporal quality metrics.
- Read-only verification in `StepsTrader/Experiments/DayObjects/DayObjectsRenderer.swift`: confirm unchanged uniform upload and half-resolution pass.

---

### Task 1: Curate smooth daily parameter ranges

**Files:**
- Modify: `StepsTrader/Experiments/DayObjects/DayObjectPalette.swift`
- Modify: `Steps4Tests/DayObjectPaletteTests.swift`

**Interfaces:**
- Produces: unchanged `DayObjectMeshGradientStyle.make(seed:palette:)` with bounded smooth ranges.
- Consumes: existing `SeededRNG`, four-color `DayObjectPalette`, and five-case archetype enum.

- [ ] **Step 1: Tighten the style-range tests first**

Replace the broad aggregate bounds with per-family assertions:

```swift
let bounds: [DayObjectMeshGradientArchetype:
    (ClosedRange<Double>, ClosedRange<Double>, ClosedRange<Double>, ClosedRange<Double>)] = [
    .drift: (0.08...0.24, -0.04...0.04, 0.045...0.085, 0.90...1.24),
    .orbit: (0.20...0.48, -0.42...0.42, 0.045...0.090, 0.92...1.26),
    .tide: (0.20...0.50, -0.08...0.08, 0.040...0.080, 0.88...1.22),
    .islands: (0.08...0.30, -0.12...0.12, 0.050...0.100, 0.96...1.34),
    .bloom: (0.14...0.38, -0.16...0.16, 0.035...0.070, 0.86...1.18),
]
```

For 2,048 seeds, assert deterministic equality, all five cases, both directions, offsets inside `-0.18...0.18`, four colors, and membership in that case's four ranges.

- [ ] **Step 2: Run the palette suite and verify range failures**

```bash
xcodebuild test -project Steps4.xcodeproj -scheme Steps4 -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17,OS=latest' -only-testing:Steps4Tests/DayObjectPaletteTests CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO
```

Expected: current orbit, tide, and bloom distortion/swirl values exceed the new limits.

- [ ] **Step 3: Update only the seeded family range table**

Change the five switch branches in `DayObjectMeshGradientStyle.make` to the exact test ranges. Continue sampling phase from `0..<(2π)`, direction from `[-1, 1]`, and offset from `-0.18...0.18`. Do not add uniform fields or change initialization.

- [ ] **Step 4: Run the palette suite**

Run the Step 2 command. Expected: deterministic and range tests pass; existing GPU tests remain green or expose shader smoothness work for Task 2.

- [ ] **Step 5: Commit the range curation**

```bash
git add -- StepsTrader/Experiments/DayObjects/DayObjectPalette.swift Steps4Tests/DayObjectPaletteTests.swift
git commit -m "fix: soften daily gradient parameter ranges"
```

### Task 2: Broad radial-basis color fields

**Files:**
- Modify: `StepsTrader/Metal/DayObjectsMeshGradientShader.metal`
- Modify: `Steps4Tests/DayObjectPaletteTests.swift`

**Interfaces:**
- Consumes: unchanged `DayObjectsMeshGradientUniforms` and `dayObjectsMeshPosition` node positions.
- Produces: `dayObjectsMeshGradientFragment` output with broad normalized fields and low-frequency deformation.

- [ ] **Step 1: Add stricter spatial GPU assertions**

Extend `broadFieldMetrics` to accept the four palette colors, track maximum
adjacent luminance delta, and count the nearest palette color for each pixel:

```swift
private func paletteCoverage(
    pixels: [UInt16],
    palette: [SIMD3<Float>]
) -> [Double] {
    var counts = Array(repeating: 0, count: palette.count)
    for index in stride(from: 0, to: pixels.count, by: 4) {
        let sample = SIMD3(
            Float(Float16(bitPattern: pixels[index])),
            Float(Float16(bitPattern: pixels[index + 1])),
            Float(Float16(bitPattern: pixels[index + 2]))
        )
        let nearest = palette.indices.min {
            simd_distance_squared(sample, palette[$0])
                < simd_distance_squared(sample, palette[$1])
        }!
        counts[nearest] += 1
    }
    let total = Double(max(counts.reduce(0, +), 1))
    return counts.map { Double($0) / total }
}
```

In the existing nested pixel scan, update the maximum before applying the
strong-adjacent threshold:

```swift
let adjacentDelta = abs(value - luminance(x: x - 1, y: y))
maximumAdjacentLuminanceDelta = max(maximumAdjacentLuminanceDelta, adjacentDelta)
if adjacentDelta > 0.04 { strongAdjacent += 1 }
```

Return that value beside the existing three metrics, call `paletteCoverage`
with the style's four colors, then require for every archetype:

```swift
XCTAssertLessThanOrEqual(metrics.centralRowReversals, 6, "\(archetype): \(metrics)")
XCTAssertLessThan(metrics.strongAdjacentRatio, 0.015, "\(archetype): \(metrics)")
XCTAssertLessThan(metrics.maximumAdjacentLuminanceDelta, 0.18, "\(archetype): \(metrics)")
XCTAssertGreaterThan(metrics.luminanceRange, 0.055, "\(archetype): \(metrics)")
XCTAssertTrue(metrics.paletteCoverage.allSatisfy { $0 > 0.02 })
```

Keep the pairwise family difference assertion above `0.012`, so smoothing cannot collapse all five topologies into the same image.

- [ ] **Step 2: Run the GPU palette test and confirm the current `pow(distance, 3.5)` field fails**

Run the Task 1 palette command. Expected: one or more smoothness metrics fail while family distinction and motion still pass.

- [ ] **Step 3: Replace inverse-distance ownership with normalized broad support**

Add this helper and use it for every active node:

```metal
static float dayObjectsBroadFieldWeight(float distance, float radius) {
    float normalized = distance / max(radius, 0.001);
    float gaussian = exp(-1.65 * normalized * normalized);
    return 0.035 + gaussian;
}
```

Use seeded-independent family radii selected from the archetype (`0.72` drift, `0.68` orbit, `0.74` tide, `0.62` islands, `0.70` bloom), multiply by a gentle per-node factor `0.94 + 0.06 * sin(index * 2.17 + phase)`, sum all colors, and normalize once. Remove `1 / (pow(distance, 3.5) + 0.001)` entirely.

Reduce high-frequency deformation in the same fragment: make orbit one warp iteration with multipliers no greater than `1.6`; keep tide spatial frequency at or below `2.4`; keep islands at or below `3.0`; limit the final radial rotation coefficient from `3.0` to `1.35`. Do not add post-blur—the output itself must be smooth.

- [ ] **Step 4: Run the GPU palette suite**

Run the Task 1 command. Expected: spatial smoothness, palette coverage, family distinction, ABI, and movement tests all pass.

- [ ] **Step 5: Commit field blending**

```bash
git add -- StepsTrader/Metal/DayObjectsMeshGradientShader.metal Steps4Tests/DayObjectPaletteTests.swift
git commit -m "fix: blend Day Object backgrounds as broad color fields"
```

### Task 3: Bounded temporal motion and complete verification

**Files:**
- Modify: `Steps4Tests/DayObjectPaletteTests.swift`

**Interfaces:**
- Consumes: final five-family shader and seeded styles.
- Produces: regression tests for slow continuous movement, no flashing, deterministic topology, palette independence, and unchanged renderer ABI.

- [ ] **Step 1: Add short-step and long-step motion tests**

Render every family at `t = 0`, `t = 1/30`, and `t = 12` using the same style. Assert:

```swift
let shortDelta = meanAbsoluteRGBDifference(first, nextFrame)
let longDelta = meanAbsoluteRGBDifference(first, later)
XCTAssertLessThan(shortDelta, 0.0025, "\(archetype) flashes between frames")
XCTAssertGreaterThan(longDelta, 0.004, "\(archetype) appears static")
XCTAssertLessThan(longDelta, 0.20, "\(archetype) changes too abruptly")
```

Also retain the opposite-direction test: frames at `t = 0` are identical and later frames differ, proving direction changes motion without rerolling topology.

- [ ] **Step 2: Run palette, scene, and render suites**

```bash
xcodebuild test -project Steps4.xcodeproj -scheme Steps4 -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17,OS=latest' -only-testing:Steps4Tests/DayObjectPaletteTests -only-testing:Steps4Tests/DayObjectSceneTests -only-testing:Steps4Tests/DayObjectRenderFrameTests CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO
```

Expected: all selected tests pass and the uniform ABI remains 128 bytes.

- [ ] **Step 3: Run the complete unit-test target**

```bash
xcodebuild test -project Steps4.xcodeproj -scheme Steps4 -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17,OS=latest' -only-testing:Steps4Tests CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO
```

Expected: `TEST SUCCEEDED`.

- [ ] **Step 4: Build the simulator application**

```bash
xcodebuild build -project Steps4.xcodeproj -scheme Steps4 -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17,OS=latest' CODE_SIGNING_ALLOWED=NO
```

Expected: `BUILD SUCCEEDED` and no Metal warnings.

- [ ] **Step 5: Commit temporal regression coverage**

```bash
git add -- Steps4Tests/DayObjectPaletteTests.swift
git commit -m "test: lock smooth moving Day Object backgrounds"
```

### Task 4: Confirm and update intentional perceptual signatures

**Files:**
- Modify only after visual confirmation: `Steps4Tests/DayObjectRenderFrameTests.swift`

**Interfaces:**
- Consumes: final choreography, broad background shader, existing `PostRenderHarness`, PNG attachments, `DayObjectsPerceptualSignature`, and `DayObjectsTransitionPerceptualSignature`.
- Produces: committed signatures that describe the verified new render without widening tolerances or hiding actor/safety regressions.

- [ ] **Step 1: Reproduce only the two published signature failures**

  Run the two named tests independently at the current HEAD and save their `.xcresult` bundles:

  ```bash
  xcodebuild test -project Steps4.xcodeproj -scheme Steps4 -configuration Debug \
    -destination 'platform=iOS Simulator,name=iPhone 17,OS=latest' \
    -only-testing:Steps4Tests/DayObjectRenderFrameTests/testCommittedPerceptualSignaturesCoverProductionTransferCompositionAndPalette \
    -only-testing:Steps4Tests/DayObjectRenderFrameTests/testInsertionAndRemovalTriptychsMatchCommittedPerceptualSignatures \
    CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO
  ```

  Confirm failures are baseline mismatches, not crashes, missing actors, unsafe placement, ABI errors, or non-finite output. Record every actual mismatch value.

- [ ] **Step 2: Export and inspect the actual new renders before editing baselines**

  Export the kept PNG attachments for every fixture or transition phase that fails at the current HEAD. The published `4e1ac4d7` evidence named `light-phone-portrait`, while the completed broad-field branch run reported all four light/dark phone/tablet fixtures plus insertion/removal triptychs; trust the current targeted reproduction and export every failing current attachment. Provide absolute artifact paths and contact sheets. Stop with `NEEDS_CONTEXT` before changing golden values so the controller can inspect the images and authorize the update.

  The visual gate requires broad continuous background fields, visible actors, expected actor counts, no hard rings/stripes/seams, no UI-exclusion intrusion, and transitions whose changed area corresponds to the inserted/removed actor.

- [ ] **Step 3: Update only confirmed signature values**

  After controller authorization, replace only the stale literal baseline fields with the actual verified measurements. Do not change tolerances, comparison logic, fixtures, render time, canvas size, or expected actor counts. Do not regenerate unrelated fixtures.

- [ ] **Step 4: Verify the signature tests and full render path**

  Run the two named tests, the complete `DayObjectRenderFrameTests`, the full `Steps4Tests` target, and the simulator build. Expected: both signature tests pass, all render assertions remain active, `TEST SUCCEEDED`, and `BUILD SUCCEEDED`.

- [ ] **Step 5: Commit the verified golden update**

  ```bash
  git add -- Steps4Tests/DayObjectRenderFrameTests.swift
  git commit -m "test: approve updated Day Object perceptual signatures"
  ```
