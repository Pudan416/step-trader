# Day Objects Orb Hybrid Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace legacy Day Objects silhouettes with large seeded radial-gradient orbs that form a dense synchronized cluster, exchange visual leadership, and softly merge at close contact.

**Architecture:** Preserve the deterministic scene model, chapter score, instanced Metal pass, render-target pipeline, and 40-actor cap. Replace only the actor art-direction domain, actor sizing/placement rules, radial-preset parameters, and local fragment coverage; Hybrid merge is a bounded per-actor outer field accumulated by existing premultiplied blending rather than a global metaball simulation.

**Tech Stack:** Swift 6, SwiftUI, Metal/MetalKit, XCTest, XCUITest, Xcode 26.2.

**Spec:** `docs/superpowers/specs/2026-08-22-day-objects-orb-hybrid-design.md`

## Global Constraints

- Work only in the clean `codex/day-objects-clean` worktree.
- Preserve deterministic day/event seed stability and retained-actor identity.
- Preserve the existing 40-actor cap, render-target planner, sRGB drawable configuration, three-slot fenced upload ring, UI exclusion, negative-space, Reduce Motion, and insertion/removal contracts.
- One unique happening produces exactly one orb.
- Orb colors use 1–3 colors from the existing daily `GradientPalette` selection.
- Grain intensity is exactly `0.05` for every fixture; grain phase refreshes at 12 fps only when Reduce Motion is off.
- Use strict RED → GREEN TDD for every production change.

---

### Task 1: Replace the legacy shape domain with daily orb families and radial presets

**Files:**
- Modify: `StepsTrader/Experiments/DayObjects/DayObjectComposition.swift`
- Modify: `StepsTrader/Experiments/DayObjects/DayObjectPalette.swift`
- Modify: `StepsTrader/Experiments/DayObjects/DayObjectScene.swift`
- Modify: `StepsTrader/Experiments/DayObjects/DayObjectTypes.swift`
- Test: `Steps4Tests/DayObjectSceneTests.swift`
- Test: `Steps4Tests/DayObjectPaletteTests.swift`

**Interfaces:**
- Produces: `DayObjectShape { sphere, ellipse, lens, softBlob }`.
- Produces: `DayObjectRadialPreset { default, radial, loFi, crossSections }`.
- Produces: `DayObjectSizeBand { support, satellite }` with exact resting diameter ranges.
- Produces: `DayObjectRadialFillStyle.preset` and `DayObjectRadialFillStyle.banding`.
- Changes: `DayObjectActor.sizeBand: DayObjectSizeBand`; removes daily `DayObjectComposition.scale`.
- Changes: `DayObjectComposition.flockSize` is always `1`.

- [ ] **Step 1: Write the failing domain and scene tests**

```swift
func testDayObjectsOnlyExposeCircleDerivedShapes() {
    XCTAssertEqual(DayObjectShape.allCases, [.sphere, .ellipse, .lens, .softBlob])
}

func testOneUniqueHappeningProducesOneStableOrb() {
    let scene = DayObjectScene.make(input: input(eventIDs: ["a", "a", "b", "c"]))
    XCTAssertEqual(scene.actors.map(\.eventID), ["a", "b", "c"])
    XCTAssertEqual(scene.composition.flockSize, 1)
}

func testRestingSizeBandsUseApprovedDiameterRanges() {
    XCTAssertEqual(DayObjectSizeBand.support.diameterRange, 0.14...0.21)
    XCTAssertEqual(DayObjectSizeBand.satellite.diameterRange, 0.08...0.13)
}
```

- [ ] **Step 2: Write the failing radial-preset matrix test**

```swift
func testDailyRadialPresetsAreDeterministicBoundedAndReachable() {
    var reached = Set<DayObjectRadialPreset>()
    for index in 0..<512 {
        let first = scene(dayKey: "orb-preset-\(index)")
        let second = scene(dayKey: "orb-preset-\(index)")
        XCTAssertEqual(first.radialFillStyle, second.radialFillStyle)
        XCTAssertTrue((1...3).contains(first.radialFillStyle.colors.count))
        XCTAssertTrue((0...0.65).contains(first.radialFillStyle.distortion))
        XCTAssertTrue((2...10).contains(first.radialFillStyle.distortionFrequency))
        XCTAssertTrue((0...0.55).contains(first.radialFillStyle.banding))
        reached.insert(first.radialFillStyle.preset)
    }
    XCTAssertEqual(reached, Set(DayObjectRadialPreset.allCases))
}
```

- [ ] **Step 3: Run focused tests and verify RED**

Run:

```bash
xcodebuild test -project Steps4.xcodeproj -scheme Steps4 \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.3.1' \
  -only-testing:Steps4Tests/DayObjectSceneTests \
  -only-testing:Steps4Tests/DayObjectPaletteTests
```

Expected: compile failures for the missing orb-only enums/properties and failing actor-count behavior.

- [ ] **Step 4: Implement the minimal orb domain**

```swift
enum DayObjectShape: String, CaseIterable, Hashable {
    case sphere, ellipse, lens, softBlob
}

enum DayObjectSizeBand: String, CaseIterable, Hashable {
    case support, satellite

    var diameterRange: ClosedRange<Double> {
        switch self {
        case .support: 0.14...0.21
        case .satellite: 0.08...0.13
        }
    }
}

enum DayObjectRadialPreset: UInt32, CaseIterable, Equatable {
    case `default`, radial, loFi, crossSections
}
```

Set `DayObjectComposition.flockSize` to `1`; assign each actor a deterministic support/satellite size band, keeping all existing event IDs and seeds stable. Generate preset-specific radial parameters from `SeededRNG.derived(from: seed, domain: "dayObjectRadialFill")`, with Cross Sections frequency capped at 10 and Lo-Fi banding capped at 0.55.

- [ ] **Step 5: Run focused tests and verify GREEN**

Run the Step 3 command. Expected: all selected tests pass, zero warnings.

- [ ] **Step 6: Commit**

```bash
git add StepsTrader/Experiments/DayObjects/DayObjectComposition.swift \
  StepsTrader/Experiments/DayObjects/DayObjectPalette.swift \
  StepsTrader/Experiments/DayObjects/DayObjectScene.swift \
  StepsTrader/Experiments/DayObjects/DayObjectTypes.swift \
  Steps4Tests/DayObjectSceneTests.swift Steps4Tests/DayObjectPaletteTests.swift
git commit -m "feat: define Day Objects orb families"
```

### Task 2: Fix procedural grain at the approved Textured 0.05 level

**Files:**
- Modify: `StepsTrader/Experiments/DayObjects/DayObjectRenderFrame.swift`
- Modify: `StepsTrader/Experiments/DayObjects/DayObjectsRenderer.swift`
- Test: `Steps4Tests/DayObjectRenderFrameTests.swift`

**Interfaces:**
- Produces: `DayObjectPostProcess.grainIntensity == 0.05`.
- Produces: `DayObjectsPostUniforms.grainIntensity == 0.05` without palette attenuation.
- Preserves: `grainPhase == floor(elapsed * 12) / 12`, or `0` under Reduce Motion.

- [ ] **Step 1: Write the failing invariant test**

```swift
func testTexturedGrainIsStableAtPointZeroFive() {
    for clarity in [0.0, 0.5, 1.0] {
        for seed in [UInt64(0), 1, .max] {
            let post = DayObjectPostProcess(
                visualClarity: clarity,
                reduceMotion: false,
                grainSeed: seed,
                elapsed: 2.25
            )
            XCTAssertEqual(post.grainIntensity, 0.05, accuracy: 0.000_001)
            let dark = DayObjectsPostUniforms(
                postProcess: post,
                resolution: SIMD2(390, 844),
                pointToPixelScale: 3,
                grainSeed: seed,
                paletteLuminance: 0.05
            )
            let light = DayObjectsPostUniforms(
                postProcess: post,
                resolution: SIMD2(390, 844),
                pointToPixelScale: 3,
                grainSeed: seed,
                paletteLuminance: 0.95
            )
            XCTAssertEqual(dark.grainIntensity, 0.05, accuracy: 0.000_001)
            XCTAssertEqual(light.grainIntensity, 0.05, accuracy: 0.000_001)
        }
    }
}
```

- [ ] **Step 2: Run the single test and verify RED**

Run the focused `DayObjectRenderFrameTests/testTexturedGrainIsStableAtPointZeroFive` test. Expected: current seeded/attenuated values differ from `0.05`.

- [ ] **Step 3: Implement the fixed grain contract**

Set `DayObjectPostProcess.grainIntensity = 0.05`. In `DayObjectsPostUniforms`, clamp only non-finite input to `0.05` and otherwise forward the fixed value; delete palette-luminance attenuation constants and calculations while retaining the initializer parameter for source compatibility until all call sites are migrated.

- [ ] **Step 4: Run all DayObjectRenderFrameTests and verify GREEN**

Expected: fixed-grain tests and existing blur/sharp-grain GPU tests pass.

- [ ] **Step 5: Commit**

```bash
git add StepsTrader/Experiments/DayObjects/DayObjectRenderFrame.swift \
  StepsTrader/Experiments/DayObjects/DayObjectsRenderer.swift \
  Steps4Tests/DayObjectRenderFrameTests.swift
git commit -m "feat: fix Day Objects grain at textured level"
```

### Task 3: Build clustered choreography with moving visual leadership

**Files:**
- Modify: `StepsTrader/Experiments/DayObjects/DayObjectComposition.swift`
- Modify: `StepsTrader/Experiments/DayObjects/DayObjectChoreography.swift`
- Modify: `StepsTrader/Experiments/DayObjects/DayObjectRenderFrame.swift`
- Test: `Steps4Tests/DayObjectChoreographyTests.swift`
- Test: `Steps4Tests/DayObjectRenderFrameTests.swift`

**Interfaces:**
- Produces: `DayObjectChoreographyScore.restingDiameter(for:)`.
- Produces: `DayObjectChoreographyScore.leadershipEnvelope(for:at:)` in `0...1`.
- Changes: `DayObjectPose.scale` becomes the final orb diameter.
- Preserves: exact tangent parity, safe-bounds, exclusion, and loop/chapter continuity.

- [ ] **Step 1: Write failing size, direction, and leadership tests**

```swift
func testRepresentativeSceneUsesApprovedOrbScaleHierarchy() {
    let scene = makeScene(eventCount: 8)
    let samples = stride(from: 0.0, through: scene.score.duration, by: 0.25)
    for time in samples {
        let diameters = scene.actors.map {
            scene.score.pose(for: $0, at: time, canvasAspect: 390.0 / 844.0,
                             compositionPlan: scene.compositionPlan).scale
        }
        XCTAssertTrue(diameters.contains { (0.26...0.34).contains($0) })
        XCTAssertTrue(diameters.allSatisfy { (0.08...0.34).contains($0) })
    }
}

func testVisualLeadershipMovesBetweenActorsWithoutPositionJump() {
    let scene = makeScene(eventCount: 8)
    var leaders = Set<DayObjectActorID>()
    for time in stride(from: 0.0, to: scene.score.duration, by: 0.25) {
        let leader = scene.actors.max {
            pose(scene, $0, time).scale < pose(scene, $1, time).scale
        }
        leaders.insert(try XCTUnwrap(leader).id)
    }
    XCTAssertGreaterThanOrEqual(leaders.count, 3)
}

func testRepresentativeSceneContainsBothTravelDirections() {
    let scene = makeScene(eventCount: 8)
    let directions = scene.actors.map { actor in
        let start = pose(scene, actor, 1.0).position
        let end = pose(scene, actor, 1.01).position
        return start.x * end.y - start.y * end.x
    }
    XCTAssertTrue(directions.contains(where: { $0 > 0 }))
    XCTAssertTrue(directions.contains(where: { $0 < 0 }))
}
```

- [ ] **Step 2: Write the failing dense-cluster sampling test**

For 24 roots × phone/tablet aspects × 48 phases, assert every actor remains safe and at least 65% of actors have a nearest-neighbor center distance below the sum of their body radii plus the planned merge reach. Keep the expected `0.65` literal in the test.

- [ ] **Step 3: Run focused choreography tests and verify RED**

Expected: legacy size bands, static leader, and dispersed route-anchor selection violate the new assertions.

- [ ] **Step 4: Implement deterministic leadership and cluster routing**

Derive each actor's resting diameter from its `sizeBand.diameterRange`. Derive a leader diameter in `0.26...0.34`. Use a chapter-continuous raised-cosine envelope phase-shifted by actor seed, then mix resting and leader diameters. Normalize leader phases from stable actor/event seed data; do not use mutable actor count in identity generation.

Change composition-plan route scoring to choose safe candidates nearest one daily cluster center, with deterministic small role offsets. Continue using the time-independent route center and continuous raw-path deformation so position/tangent continuity is retained.

- [ ] **Step 5: Run the complete DayObjectChoreographyTests and verify GREEN**

Expected: new cluster/leadership tests plus all existing exclusion, negative-space, visibility, tangent, boundary, and loop tests pass.

- [ ] **Step 6: Run DayObjectRenderFrameTests and verify GREEN**

Expected: GPU upload half-sizes match the final pose diameter and insertion/removal envelopes remain continuous.

- [ ] **Step 7: Commit**

```bash
git add StepsTrader/Experiments/DayObjects/DayObjectComposition.swift \
  StepsTrader/Experiments/DayObjects/DayObjectChoreography.swift \
  StepsTrader/Experiments/DayObjects/DayObjectRenderFrame.swift \
  Steps4Tests/DayObjectChoreographyTests.swift Steps4Tests/DayObjectRenderFrameTests.swift
git commit -m "feat: choreograph a clustered orb field"
```

### Task 4: Render circle-derived bodies and Hybrid merge in Metal

**Files:**
- Modify: `StepsTrader/Experiments/DayObjects/DayObjectChoreography.swift`
- Modify: `StepsTrader/Experiments/DayObjects/DayObjectsRenderer.swift`
- Modify: `StepsTrader/Metal/DayObjectsActorShader.metal`
- Test: `Steps4Tests/DayObjectSceneTests.swift`
- Test: `Steps4Tests/DayObjectRenderFrameTests.swift`

**Interfaces:**
- Changes: `DayObjectsActorUniforms` from 112 to 128 bytes.
- Adds: `radialParameters3 = SIMD4<Float>(presetIndex, banding, mergeReachFactor, mergeAlpha)`.
- Adds: `DayObjectShape.numericValue: UInt32` with explicit `0...3` values.
- Adds: `DayObjectActorGeometry.mergeReachFactor = 0.18` and `softBlobRadialReach = 1.06`.
- Preserves: `DayObjectGPUActor` 80-byte ABI.

- [ ] **Step 1: Write failing ABI and numeric-shape tests**

```swift
func testOrbShapeABIIsStable() {
    XCTAssertEqual(DayObjectShape.sphere.numericValue, 0)
    XCTAssertEqual(DayObjectShape.ellipse.numericValue, 1)
    XCTAssertEqual(DayObjectShape.lens.numericValue, 2)
    XCTAssertEqual(DayObjectShape.softBlob.numericValue, 3)
}

func testActorUniformsCarryRadialPresetAndMergeParameters() {
    let uniforms = DayObjectsActorUniforms(
        resolution: SIMD2(1170, 2532), visibleActorCount: 8,
        radialFillStyle: fixtureStyle
    )
    XCTAssertEqual(MemoryLayout<DayObjectsActorUniforms>.stride, 128)
    XCTAssertEqual(uniforms.radialParameters3,
                   SIMD4(Float(fixtureStyle.preset.rawValue), Float(fixtureStyle.banding), 0.18, 0.16))
}
```

- [ ] **Step 2: Write the failing GPU capture tests**

Render isolated `sphere`, `ellipse`, `lens`, and `softBlob` fixtures and assert each has nonzero body coverage, no legacy polygon corners, finite premultiplied color, and coverage inside the CPU reach. Render two close spheres and two separated spheres; require the close midpoint alpha to exceed the isolated-field midpoint by `0.025`, while the separated midpoint stays below `0.01`.

- [ ] **Step 3: Run focused tests and verify RED**

Expected: missing uniform field/ABI and legacy SDF output failures.

- [ ] **Step 4: Implement orb SDFs and preset-aware radial color**

Use only circle-derived signed distances:

```metal
static float dayObjectsActorBody(
    uint shape,
    float2 point,
    float aspect,
    float radialVariation
) {
switch (shape) {
case 1: return length(float2(point.x, point.y / max(aspect, 1e-4))) - 1.0;
case 2: return pow(pow(abs(point.x), 2.4) + pow(abs(point.y / max(aspect, 1e-4)), 2.4), 1.0 / 2.4) - 1.0;
case 3: {
    const float2 q = float2(point.x, point.y / max(aspect, 1e-4));
    const float angle = atan2(q.y, q.x);
    return length(q) - (1.0 + 0.06 * sin(3.0 * angle + radialVariation));
}
default: return length(point) - 1.0;
}
}
```

Use preset index/banding in the radial field while preserving 1–3 color interpolation. Cross Sections uses bounded directional distortion; Lo-Fi mixes a quantized radial value back into the smooth value so bands remain soft.

- [ ] **Step 5: Implement bounded Hybrid merge coverage**

Expand vertex bounds and CPU footprints by `majorHalfSize * 0.18`. Outside body coverage, fade a merge field to zero across that support and composite it at alpha `0.16`; keep body alpha unchanged. Reuse premultiplied actor blending so overlapping fields form a bridge without a new global pass.

- [ ] **Step 6: Run focused GPU/ABI tests and verify GREEN**

Expected: all four orb families are reachable and nonblank, close-pair bridge assertion passes, separated pair remains distinct, ABI is exact, and no quad/safe-edge clipping occurs.

- [ ] **Step 7: Commit**

```bash
git add StepsTrader/Experiments/DayObjects/DayObjectChoreography.swift \
  StepsTrader/Experiments/DayObjects/DayObjectsRenderer.swift \
  StepsTrader/Metal/DayObjectsActorShader.metal \
  Steps4Tests/DayObjectSceneTests.swift Steps4Tests/DayObjectRenderFrameTests.swift
git commit -m "feat: render hybrid merging radial orbs"
```

### Task 5: Update the lab acceptance gate and verify the complete application

**Files:**
- Modify: `Steps4Tests/DayObjectRenderFrameTests.swift`
- Modify: `Steps4UITests/DayObjectsLabUITests.swift`
- Modify: `StepsTrader/Views/Settings/SettingsAppearancePage.swift`
- Create: `docs/superpowers/reports/2026-08-22-day-objects-orb-hybrid-verification.md`

**Interfaces:**
- Consumes: final orb scene, mesh background, fixed grain, and lab controls.
- Produces: deterministic orb visual signatures and current screenshots for Single, Grid, and transition fixtures.

- [ ] **Step 1: Write failing lab acceptance assertions before updating baselines**

Assert an 8-happening lab scene reports `8 · 8 figures`, all numeric shape IDs are `0...3`, largest painted orb diameter is within `0.26...0.34` of the short side, and the final grain uniform equals `0.05`.

- [ ] **Step 2: Run the focused unit/UI acceptance command and verify RED**

```bash
xcodebuild test -project Steps4.xcodeproj -scheme Steps4 \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.3.1' \
  -only-testing:Steps4Tests/DayObjectSceneTests \
  -only-testing:Steps4Tests/DayObjectPaletteTests \
  -only-testing:Steps4Tests/DayObjectChoreographyTests \
  -only-testing:Steps4Tests/DayObjectRenderFrameTests \
  -only-testing:Steps4UITests/DayObjectsLabUITests
```

- [ ] **Step 3: Regenerate representative perceptual signatures and attachments**

Generate phone/tablet Single fixtures, the 3×5 daily grid, 1/8/24/40 actor matrices, clarity `0/0.5/1`, motion `0/1`, and insertion/removal/capped-replacement triptychs. Change the Settings subtitle to `Large radial-gradient orbs in seeded choreography`. Update committed perceptual literals only for intentional orb-domain changes and record every previous/new value in `docs/superpowers/reports/2026-08-22-day-objects-orb-hybrid-verification.md`.

- [ ] **Step 4: Inspect every contact sheet**

Check visually for: large circular bodies, dense but readable overlap, soft bridges only near contact, daily palette coherence, background motion variety, sharp `0.05` grain, no old polygon silhouettes, no edge/UI-exclusion clipping, and legible controls.

- [ ] **Step 5: Run exact scoped tests**

Run the Step 2 command. Expected: all selected unit and UI tests pass, zero failures.

- [ ] **Step 6: Run the full project suite**

```bash
xcodebuild test -project Steps4.xcodeproj -scheme Steps4 \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.3.1'
```

Expected: all project unit/UI bundles pass except only documented pre-existing skips.

- [ ] **Step 7: Build the simulator and physical-device products**

```bash
xcodebuild -project Steps4.xcodeproj -scheme Steps4 -configuration Debug \
  -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build
xcodebuild -project Steps4.xcodeproj -scheme Steps4 -configuration Debug \
  -destination 'id=00008130-001E3CE622C0001C' build
```

Expected: both commands end with `BUILD SUCCEEDED`; the device product is signed as `personal-project.StepsTrader`.

- [ ] **Step 8: Commit**

```bash
git add Steps4Tests/DayObjectRenderFrameTests.swift \
  Steps4UITests/DayObjectsLabUITests.swift \
  StepsTrader/Views/Settings/SettingsAppearancePage.swift \
  docs/superpowers/reports/2026-08-22-day-objects-orb-hybrid-verification.md
git commit -m "test: verify Day Objects orb choreography"
```
