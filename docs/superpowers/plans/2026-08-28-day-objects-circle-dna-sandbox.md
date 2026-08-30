# Day Objects Circle DNA Sandbox Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a deterministic Day Objects Lab generator in which one related circle-material family fills and traverses the whole canvas, while individual happenings vary through bounded inherited mutations, color, size, depth, focus, and motion.

**Architecture:** Keep the existing `DayObjectScene` → `DayObjectRenderFrame` → instanced Metal actor pass. Replace the broad daily material set with a single `DayObjectVisualLanguage` family and related mutation roles, pack up to three analytic radial layers per actor, and make the laboratory opt into full-canvas composition. Couple depth to scale, local softness, opacity, and shader definition through continuous seeded functions.

**Tech Stack:** Swift 6, SwiftUI, XCTest, Metal Shading Language, deterministic `SeededRNG`, Xcode 26 / iOS 26 simulator.

**Spec:** `docs/superpowers/specs/2026-08-28-day-objects-circle-dna-sandbox-design.md`

## Global Constraints

- One dominant material family per day; related base, soft, and accent mutations only.
- Maximum ten actors and one instanced actor pass.
- Every actor uses one to three colors from exactly one of the two object palettes.
- Elongation stays within five percent of the daily base shape.
- The laboratory control panel does not reserve the lower 42% of the scene.
- Six or more actors cover upper, middle, and lower canvas thirds.
- Eight or more actors cover at least six of nine occupancy sectors across sampled time.
- Depth increases size and definition; distance decreases size, opacity, and high-frequency detail.
- No frame-random sampling, abrupt gradient reversal, conic main fill, bitmap material, or per-object render target.
- Existing event appearances remain stable when another happening is inserted or removed.
- Procedural grain remains stable at intensity `0.05`.
- Do not modify the independent feed/localization changes already present in the worktree.

## File Structure

- `StepsTrader/Experiments/DayObjects/DayObjectVisualLanguage.swift`: daily family DNA, mutation recipes, radial layers, and stable per-event appearance sampling.
- `StepsTrader/Experiments/DayObjects/DayObjectComposition.swift`: full-canvas policy, daily composition archetypes, placement constraints, and size-band ranges.
- `StepsTrader/Experiments/DayObjects/DayObjectTypes.swift`: scene input coverage policy and actor metadata.
- `StepsTrader/Experiments/DayObjects/DayObjectScene.swift`: binds daily DNA, event appearance, role, and size band into actors.
- `StepsTrader/Experiments/DayObjects/DayObjectChoreography.swift`: full-canvas pose, depth/size/focus coupling, breathing, and actor geometry.
- `StepsTrader/Experiments/DayObjects/DayObjectMotionPlan.swift`: slower broad routes, independent direction, and continuous phases.
- `StepsTrader/Experiments/DayObjects/DayObjectRenderFrame.swift`: Swift/Metal appearance packing and ABI validation.
- `StepsTrader/Metal/DayObjectsActorShader.metal`: layered radial field, family response, refraction, glow, and continuous focal animation.
- `StepsTrader/Experiments/DayObjects/DayObjectsLabView.swift`: full-canvas sandbox input and readable family summary.
- `Steps4Tests/DayObjectPaletteTests.swift`: day-family inheritance, mutation bounds, and color stability.
- `Steps4Tests/DayObjectSceneTests.swift`: coverage policy, shape inheritance, size-band assignment, and insertion stability.
- `Steps4Tests/DayObjectChoreographyTests.swift`: full-canvas occupancy, slow movement, depth coupling, continuity, and Reduce Motion.
- `Steps4Tests/DayObjectRenderFrameTests.swift`: GPU ABI, layered radial output, material-family rendering, and deterministic visual matrix.
- `Steps4UITests/DayObjectsLabUITests.swift`: laboratory controls, family summary, and 1/4/7/10 actor inspection states.

---

### Task 1: Replace unrelated materials with one daily circle DNA

**Files:**
- Modify: `StepsTrader/Experiments/DayObjects/DayObjectVisualLanguage.swift`
- Modify: `StepsTrader/Experiments/DayObjects/DayObjectTypes.swift`
- Modify: `StepsTrader/Experiments/DayObjects/DayObjectScene.swift`
- Test: `Steps4Tests/DayObjectPaletteTests.swift`
- Test: `Steps4Tests/DayObjectSceneTests.swift`

**Interfaces:**
- Produces: `DayObjectMaterialFamily`, `DayObjectMutationRole`, `DayObjectRadialLayer`, `DayObjectVisualLanguage.family`, `DayObjectVisualLanguage.baseShape`, `DayObjectVisualLanguage.maximumElongation`, and bounded `DayObjectAppearance` values.
- Preserves: `DayObjectVisualLanguage.make(rootSeed:paletteSet:)` and `appearances(eventIDs:rootSeed:)` entry points.
- Consumed by: Tasks 2–4 through `DayObjectActor.appearance` and `scene.visualLanguage`.

- [ ] **Step 1: Replace the broad-material tests with failing inheritance tests**

Add these assertions to `DayObjectPaletteTests` and remove assertions that require three material families in one day:

```swift
func testDailyVisualLanguageUsesOneFamilyAndOnlyRelatedMutations() {
    for seed in UInt64(0)..<256 {
        let paletteSet = DayObjectPaletteSet.make(
            rootSeed: seed,
            categories: ModernPaletteSelection.all
        )
        let language = DayObjectVisualLanguage.make(
            rootSeed: seed,
            paletteSet: paletteSet
        )
        let appearances = language.appearances(
            eventIDs: (0..<10).map { "event-\($0)" },
            rootSeed: seed
        ).values

        XCTAssertTrue(appearances.allSatisfy { $0.material == language.family })
        XCTAssertTrue(appearances.allSatisfy {
            DayObjectMutationRole.allCases.contains($0.mutationRole)
        })
        XCTAssertLessThanOrEqual(
            appearances.filter { $0.mutationRole == .accent }.count,
            3
        )
        XCTAssertTrue(appearances.allSatisfy {
            abs($0.elongation - language.baseElongation)
                <= language.maximumElongation + 0.000_001
        })
    }
}

func testExistingAppearanceDoesNotChangeWhenLaterHappeningWidensMutationEnvelope() throws {
    let paletteSet = DayObjectPaletteSet.make(rootSeed: 71, categories: [.pastel, .cold])
    let language = DayObjectVisualLanguage.make(rootSeed: 71, paletteSet: paletteSet)
    let one = language.appearances(eventIDs: ["walk"], rootSeed: 71)
    let ten = language.appearances(
        eventIDs: ["walk"] + (1..<10).map { "event-\($0)" },
        rootSeed: 71
    )
    XCTAssertEqual(try XCTUnwrap(one["walk"]), try XCTUnwrap(ten["walk"]))
}
```

- [ ] **Step 2: Run the focused tests and verify the old API fails**

Run:

```bash
xcodebuild test -project Steps4.xcodeproj -scheme Steps4 \
  -destination 'platform=iOS Simulator,id=A55C6AF8-3836-4E40-BA57-2C18A9DC81EF' \
  -only-testing:Steps4Tests/DayObjectPaletteTests \
  -only-testing:Steps4Tests/DayObjectSceneTests
```

Expected: FAIL because `family`, `mutationRole`, `baseElongation`, and `maximumElongation` do not exist and old tests still expect `enabledMaterials`.

- [ ] **Step 3: Add the exact DNA and layer types**

Replace the material enum and extend appearance with these public-to-module types:

```swift
enum DayObjectMaterialFamily: UInt32, CaseIterable, Equatable {
    case softVolume
    case livingGlass
    case innerLight
    case atmosphericOrb
    case layeredMembrane
}

enum DayObjectMutationRole: UInt32, CaseIterable, Equatable {
    case base
    case soft
    case accent
}

struct DayObjectRadialLayer: Equatable {
    let focalOffset: SIMD2<Double>
    let radius: Double
    let softness: Double
    let opacity: Double
}

struct DayObjectAppearance: Equatable {
    let colorAssignment: DayObjectColorAssignment
    let material: DayObjectMaterialFamily
    let mutationRole: DayObjectMutationRole
    let shape: DayObjectShape
    let elongation: Double
    let layers: [DayObjectRadialLayer]
    let distortion: Double
    let distortionFrequency: Double
    let distortionPhase: Double
    let innerGlow: Double
    let outerGlow: Double
    let bodyOpacity: Double
    let centerOpacity: Double
    let rimOpacity: Double
    let refractionStrength: Double
    let refractionAngle: Double
    let localDepthSoftness: Double
    let lightResponse: Double
    let radialPhase: Double
}
```

Make `DayObjectVisualLanguage` contain:

```swift
let family: DayObjectMaterialFamily
let baseShape: DayObjectShape
let baseElongation: Double
let maximumElongation: Double // always 0.05
let accentShare: Double       // 0.15...0.30
```

Use one family seed domain and map mutation roles deterministically by stable event priority. Base and soft roles must occupy at least 70% of ten actors; accent must never exceed three actors. Use one to three radial layers and these family ranges:

| Family | Layers | Body opacity | Inner glow | Outer glow | Refraction |
|---|---:|---:|---:|---:|---:|
| Soft Volume | 2...3 | 0.78...0.96 | 0.06...0.20 | 0.01...0.08 | 0 |
| Living Glass | 2...3 | 0.22...0.52 | 0.03...0.16 | 0.04...0.16 | 0.006...0.028 |
| Inner Light | 2...3 | 0.58...0.86 | 0.34...0.72 | 0.03...0.14 | 0 |
| Atmospheric Orb | 2...3 | 0.38...0.72 | 0.10...0.30 | 0.06...0.22 | 0 |
| Layered Membrane | 2...3 | 0.34...0.66 | 0.08...0.26 | 0.04...0.18 | 0 |

Every layer uses focal offsets bounded to length `0.68`, radius `0.42...1.18`, softness `0.12...0.48`, and opacity `0.18...1`. Derive all values from the stable event ID, never insertion index.

- [ ] **Step 4: Bind one daily shape grammar into actor creation**

In `DayObjectScene.makeActor`, remove independent random `composition.shape`/`composition.elongation` selection. Store `appearance.shape` and let `appearance.elongation` drive geometry. Keep actor role, depth, route, and stable event identity unchanged.

- [ ] **Step 5: Run the focused tests and make them pass**

Run the command from Step 2. Expected: PASS, including existing color allocation and insertion-stability tests.

- [ ] **Step 6: Commit the daily DNA model**

```bash
git add StepsTrader/Experiments/DayObjects/DayObjectVisualLanguage.swift \
  StepsTrader/Experiments/DayObjects/DayObjectTypes.swift \
  StepsTrader/Experiments/DayObjects/DayObjectScene.swift \
  Steps4Tests/DayObjectPaletteTests.swift Steps4Tests/DayObjectSceneTests.swift
git commit -m "feat: define inherited Day Objects circle DNA"
```

---

### Task 2: Use the complete laboratory canvas and real size bands

**Files:**
- Modify: `StepsTrader/Experiments/DayObjects/DayObjectTypes.swift`
- Modify: `StepsTrader/Experiments/DayObjects/DayObjectComposition.swift`
- Modify: `StepsTrader/Experiments/DayObjects/DayObjectScene.swift`
- Modify: `StepsTrader/Experiments/DayObjects/DayObjectsLabView.swift`
- Test: `Steps4Tests/DayObjectSceneTests.swift`
- Test: `Steps4Tests/DayObjectChoreographyTests.swift`

**Interfaces:**
- Consumes: Task 1 `appearance.elongation` and stable actor roles.
- Produces: `DayObjectCanvasCoverage`, `DayObjectCompositionArchetype`, full-canvas `DayObjectCompositionPlan`, and three meaningful `DayObjectSizeBand` ranges.
- Consumed by: Task 3 pose sampling and Task 5 lab inspection.

- [ ] **Step 1: Add failing tests for full-canvas policy and visible size hierarchy**

```swift
func testLabUsesFullCanvasCoverageInsteadOfBottomControlExclusion() {
    XCTAssertEqual(DayObjectsLabView.canvasCoverage, .fullCanvas)
    let scene = DayObjectScene.make(input: fixtureInput(seed: 19, count: 10))
    XCTAssertEqual(scene.input.canvasCoverage, .fullCanvas)
    XCTAssertEqual(scene.compositionPlan.uiExclusionRegion.area, 0)
}

func testSixOrMoreActorsReachEveryVerticalThird() {
    for seed in UInt64(0)..<64 {
        for count in 6...10 {
            let scene = DayObjectScene.make(input: fixtureInput(seed: seed, count: count))
            var thirds = Set<Int>()
            for time in stride(from: 0.0, through: 90.0, by: 15.0) {
                for actor in scene.actors {
                    let pose = scene.score.pose(
                        for: actor, at: time, canvasAspect: 1,
                        compositionPlan: scene.compositionPlan
                    )
                    thirds.insert(min(max(Int((0.5 - pose.position.y) * 3), 0), 2))
                }
            }
            XCTAssertEqual(thirds, Set([0, 1, 2]), "seed=\(seed) count=\(count)")
        }
    }
}

func testSizeBandsProduceFocalSupportAndSatelliteDiameters() {
    XCTAssertEqual(DayObjectSizeBand.focal.diameterRange, 0.24...0.34)
    XCTAssertEqual(DayObjectSizeBand.support.diameterRange, 0.15...0.23)
    XCTAssertEqual(DayObjectSizeBand.satellite.diameterRange, 0.08...0.14)
}
```

- [ ] **Step 2: Run the scene and choreography tests to verify failure**

Run:

```bash
xcodebuild test -project Steps4.xcodeproj -scheme Steps4 \
  -destination 'platform=iOS Simulator,id=A55C6AF8-3836-4E40-BA57-2C18A9DC81EF' \
  -only-testing:Steps4Tests/DayObjectSceneTests \
  -only-testing:Steps4Tests/DayObjectChoreographyTests
```

Expected: FAIL because the lab still supplies `.dayObjectsLabControls`, the lower rows are removed, and `.focal` does not exist.

- [ ] **Step 3: Introduce explicit canvas coverage**

Add:

```swift
enum DayObjectCanvasCoverage: Equatable {
    case fullCanvas
    case excluding(DayObjectNormalizedRect)
}
```

Store it on `DayObjectSceneInput`, preserving `.excluding(.dayObjectsLabControls)` as the default for non-lab callers. Add `DayObjectsLabView.canvasCoverage = .fullCanvas` and pass it from `sceneInput(for:)` in both single and contact-sheet modes.

In `DayObjectCompositionPlan.make`, resolve `.fullCanvas` to an empty exclusion rectangle and generate route candidates over all three rows. Remove the `usableBottom < 0.78 ? 2 : 3` branch from `distributedRoutePosition`.

- [ ] **Step 4: Add deterministic full-canvas archetypes**

Add:

```swift
enum DayObjectCompositionArchetype: UInt32, CaseIterable, Equatable {
    case distributedField
    case diagonalCurrent
    case edgeMigration
    case focalPair
    case depthConstellation
    case crossingCurrents
}
```

Select one archetype from the root seed. Use it to bias candidate order and route direction, but retain candidates in all nine sectors. Keep seeded jitter within `±0.08` normalized canvas units and permit approved overlaps; do not reject candidates solely because another actor occupies the same sector.

- [ ] **Step 5: Replace the two unused size bands with three consumed ranges**

Define:

```swift
enum DayObjectSizeBand: String, CaseIterable, Hashable {
    case focal
    case support
    case satellite

    var diameterRange: ClosedRange<Double> {
        switch self {
        case .focal: 0.24...0.34
        case .support: 0.15...0.23
        case .satellite: 0.08...0.14
        }
    }
}
```

Map roles deterministically: `.focal` actor role → `.focal`; `.support`/`.bridge` → `.support`; `.satellite`/`.accent` → `.satellite`, while ensuring a ten-actor scene contains at least one focal and two satellite actors.

- [ ] **Step 6: Run the focused tests and commit**

Run the command from Step 2. Expected: PASS.

```bash
git add StepsTrader/Experiments/DayObjects/DayObjectTypes.swift \
  StepsTrader/Experiments/DayObjects/DayObjectComposition.swift \
  StepsTrader/Experiments/DayObjects/DayObjectScene.swift \
  StepsTrader/Experiments/DayObjects/DayObjectsLabView.swift \
  Steps4Tests/DayObjectSceneTests.swift Steps4Tests/DayObjectChoreographyTests.swift
git commit -m "feat: distribute Day Objects across the full lab canvas"
```

---

### Task 3: Couple continuous motion, size, depth, and focus

**Files:**
- Modify: `StepsTrader/Experiments/DayObjects/DayObjectMotionPlan.swift`
- Modify: `StepsTrader/Experiments/DayObjects/DayObjectChoreography.swift`
- Modify: `StepsTrader/Experiments/DayObjects/DayObjectRenderFrame.swift`
- Test: `Steps4Tests/DayObjectChoreographyTests.swift`
- Test: `Steps4Tests/DayObjectRenderFrameTests.swift`

**Interfaces:**
- Consumes: Task 1 appearance elongation and radial phase; Task 2 size bands and full-canvas plan.
- Produces: continuous `DayObjectPose.scale`, `depth`, `localDepthSoftness`, `opacity`, and `materialPhase` with slower full-canvas routes.
- Consumed by: Task 4 GPU actor upload.

- [ ] **Step 1: Add failing depth-coupling and tempo tests**

```swift
func testSizeBandsAndDepthCreateAVisibleHierarchy() {
    let scene = DayObjectScene.make(input: fixtureInput(seed: 27, count: 10))
    let poses = scene.actors.map {
        ($0, scene.score.pose(for: $0, at: 31, canvasAspect: 1,
                              compositionPlan: scene.compositionPlan))
    }
    let near = poses.max { $0.1.depth < $1.1.depth }!
    let far = poses.min { $0.1.depth < $1.1.depth }!
    XCTAssertGreaterThan(near.1.scale, far.1.scale)
    XCTAssertLessThan(near.1.localDepthSoftness, far.1.localDepthSoftness)
    XCTAssertGreaterThan(near.1.opacity, far.1.opacity)
    XCTAssertGreaterThan(
        poses.map(\.1.scale).max()! / poses.map(\.1.scale).min()!,
        1.8
    )
}

func testMotionAndBreathingRemainContinuousAtEveryLoopBoundary() {
    let scene = DayObjectScene.make(input: fixtureInput(seed: 33, count: 10))
    for actor in scene.actors {
        let before = scene.score.pose(
            for: actor, at: actor.route.period - 0.001, canvasAspect: 1,
            compositionPlan: scene.compositionPlan
        )
        let after = scene.score.pose(
            for: actor, at: 0.001, canvasAspect: 1,
            compositionPlan: scene.compositionPlan
        )
        XCTAssertLessThan(simd_distance(before.position, after.position), 0.003)
        XCTAssertLessThan(abs(before.scale - after.scale), 0.003)
        XCTAssertLessThan(abs(before.localDepthSoftness - after.localDepthSoftness), 0.003)
    }
}
```

Also change the route-period assertion from `45...120` to `70...180` seconds.

- [ ] **Step 2: Run focused tests and verify the size ratio or period assertion fails**

```bash
xcodebuild test -project Steps4.xcodeproj -scheme Steps4 \
  -destination 'platform=iOS Simulator,id=A55C6AF8-3836-4E40-BA57-2C18A9DC81EF' \
  -only-testing:Steps4Tests/DayObjectChoreographyTests \
  -only-testing:Steps4Tests/DayObjectRenderFrameTests/testRepresentativeSceneUsesApprovedOrbScaleHierarchy \
  -only-testing:Steps4Tests/DayObjectRenderFrameTests/testReduceMotionFreezesPositionDepthAndMaterialPhase
```

Expected: FAIL because `baseDiameter` ignores the size band and current periods begin at 45 seconds.

- [ ] **Step 3: Consume size bands and appearance elongation**

Change `DayObjectActorGeometry.aspectRatio(for:)` to:

```swift
static func aspectRatio(for actor: DayObjectActor) -> Double {
    min(max(actor.appearance.elongation, 0.95), 1.05)
}
```

Change `baseDiameter(for:)` to sample the actor's `sizeBand.diameterRange` using the existing stable-unit function. Remove the branch that clamps non-lab canvases to `0.13`.

- [ ] **Step 4: Apply one continuous depth system**

Use these formulas in `pose(for:at:canvasAspect:compositionPlan:)`:

```swift
let depthScale = 0.62 + 0.76 * depth
let breathing = 1 + 0.035 * sin(
    2 * .pi * (time / actor.depthSchedule.period + actor.phaseOffset / (2 * .pi))
)
let scale = baseScale * depthScale * breathing
let localDepthSoftness = 0.018 + 0.24 * pow(1 - depth, 1.25)
let opacity = 0.48 + 0.52 * depth
let materialPhase = normalizedPhase(
    actor.appearance.radialPhase + time / 150
)
```

Make route periods `70...180` seconds and preserve both motion directions. Motion energy continues to scale elapsed choreography time; its minimum must remain nonzero through the existing ambient drift floor. Reduce Motion must freeze route, depth, breathing, and material phase.

- [ ] **Step 5: Run focused tests and commit**

Run the command from Step 2 plus all `DayObjectChoreographyTests`. Expected: PASS.

```bash
git add StepsTrader/Experiments/DayObjects/DayObjectMotionPlan.swift \
  StepsTrader/Experiments/DayObjects/DayObjectChoreography.swift \
  StepsTrader/Experiments/DayObjects/DayObjectRenderFrame.swift \
  Steps4Tests/DayObjectChoreographyTests.swift Steps4Tests/DayObjectRenderFrameTests.swift
git commit -m "feat: connect Day Objects depth size and focus"
```

---

### Task 4: Render continuous layered radial materials in Metal

**Files:**
- Modify: `StepsTrader/Experiments/DayObjects/DayObjectRenderFrame.swift`
- Modify: `StepsTrader/Metal/DayObjectsActorShader.metal`
- Test: `Steps4Tests/DayObjectRenderFrameTests.swift`

**Interfaces:**
- Consumes: Task 1 `DayObjectAppearance.layers`, family, mutation role, optical values; Task 3 continuous material phase and local softness.
- Produces: 176-byte `DayObjectGPUAppearance` and `dayObjectsLayeredRadialColor` Metal function.
- Preserves: one-to-one pose/appearance sorting and one instanced draw.

- [ ] **Step 1: Add failing GPU ABI and visual continuity tests**

Update the layout test to require this exact packing:

```swift
XCTAssertEqual(MemoryLayout<DayObjectGPUAppearance>.stride, 176)
XCTAssertEqual(MemoryLayout<DayObjectGPUAppearance>.offset(of: \.radial0), 48)
XCTAssertEqual(MemoryLayout<DayObjectGPUAppearance>.offset(of: \.radial1), 64)
XCTAssertEqual(MemoryLayout<DayObjectGPUAppearance>.offset(of: \.radial2), 80)
XCTAssertEqual(MemoryLayout<DayObjectGPUAppearance>.offset(of: \.field), 96)
XCTAssertEqual(MemoryLayout<DayObjectGPUAppearance>.offset(of: \.metadata), 160)
```

Add a GPU test that renders the same actor at material phases `0.499`, `0.500`, and `0.501`, then asserts mean absolute RGB difference between adjacent captures is below `0.015`. Add another fixture with an offset focal point and assert its brightest-region centroid is at least `8%` of the body diameter away from center.

- [ ] **Step 2: Run the ABI and actor GPU tests to verify failure**

```bash
xcodebuild test -project Steps4.xcodeproj -scheme Steps4 \
  -destination 'platform=iOS Simulator,id=A55C6AF8-3836-4E40-BA57-2C18A9DC81EF' \
  -only-testing:Steps4Tests/DayObjectRenderFrameTests/testGPUAppearanceHasStableExplicitMetalLayout \
  -only-testing:Steps4Tests/DayObjectRenderFrameTests/testLayeredRadialColorIsContinuousAcrossHalfPhase \
  -only-testing:Steps4Tests/DayObjectRenderFrameTests/testShiftedRadialFocusMovesTheRenderedHighlight
```

Expected: FAIL because the appearance is still 160 bytes and the old shader flips `directedT` at half phase.

- [ ] **Step 3: Pack three radial layers and one field descriptor**

Use this Swift layout in `DayObjectRenderFrame.swift` and mirror it exactly in Metal:

```swift
struct DayObjectGPUAppearance {
    let color0: SIMD4<Float>
    let color1: SIMD4<Float>
    let color2: SIMD4<Float>
    let radial0: SIMD4<Float> // focal x, focal y, radius, softness
    let radial1: SIMD4<Float>
    let radial2: SIMD4<Float>
    let field: SIMD4<Float>   // distortion, frequency, phase, edge softness
    let optical0: SIMD4<Float>// inner glow, outer glow, body opacity, center opacity
    let optical1: SIMD4<Float>// rim opacity, refraction, refraction angle, depth softness
    let light: SIMD4<Float>   // response, layer opacity 0, 1, 2
    let metadata: SIMD4<UInt32>// family, color count, layer count, mutation role
}
```

Pad absent layers with a zero-opacity descriptor. Clamp focal length to `0.68`, radius to `0.42...1.18`, softness to `0.12...0.72`, distortion to `0...0.18`, and frequency to `0.8...4.0` before upload.

- [ ] **Step 4: Replace direction-flipping and conic color with analytic radial layers**

Implement `dayObjectsLayeredRadialColor` without `atan2` in its color path:

```metal
static float radialLayerWeight(
    float2 point,
    float4 layer,
    float phase,
    float2 phaseDirection
) {
    float2 animatedFocus = layer.xy
        + phaseDirection * (0.018 * sin(phase * 2.0 * M_PI_F));
    float distanceFromFocus = length(point - animatedFocus);
    float softness = max(layer.w, 0.02);
    return 1.0 - smoothstep(
        max(layer.z - softness, 0.0),
        layer.z + softness,
        distanceFromFocus
    );
}
```

Compute a bounded Cartesian deformation from `sin(point.x * frequency + phase)` and `cos(point.y * frequency - phase)`; do not derive body color from polar angle. Blend the three weights in stable order with continuous normalization. Apply family-specific optical response after the shared radial color:

- Soft Volume: broad light and restrained center highlight.
- Living Glass: background refraction plus tint and soft rim.
- Inner Light: center-weighted luminance and gentle halo.
- Atmospheric Orb: increased local softness without changing silhouette genre.
- Layered Membrane: composite the same radial layers with translucent overlap.

Remove the `variation < 0 ? 1 - radialT : radialT` branch and the spectral angular migration case.

- [ ] **Step 5: Run all actor GPU tests and commit**

```bash
xcodebuild test -project Steps4.xcodeproj -scheme Steps4 \
  -destination 'platform=iOS Simulator,id=A55C6AF8-3836-4E40-BA57-2C18A9DC81EF' \
  -only-testing:Steps4Tests/DayObjectRenderFrameTests
```

Expected: PASS for ABI, all five families, refraction, premultiplied alpha, depth softness, actor counts, and new radial continuity fixtures.

```bash
git add StepsTrader/Experiments/DayObjects/DayObjectRenderFrame.swift \
  StepsTrader/Metal/DayObjectsActorShader.metal \
  Steps4Tests/DayObjectRenderFrameTests.swift
git commit -m "feat: render inherited layered radial Day Objects"
```

---

### Task 5: Expose and visually validate the sandbox states

**Files:**
- Modify: `StepsTrader/Experiments/DayObjects/DayObjectsLabView.swift`
- Modify: `Steps4UITests/DayObjectsLabUITests.swift`
- Modify: `Steps4Tests/DayObjectRenderFrameTests.swift`

**Interfaces:**
- Consumes: complete scene, choreography, and renderer from Tasks 1–4.
- Produces: readable lab family summary, deterministic inspection states, and updated visual acceptance captures.

- [ ] **Step 1: Add failing UI assertions for the new family summary and full actor counts**

Update `DayObjectsLabUITests` to inspect `dayObjects.language` after setting happenings to 1, 4, 7, and 10. Its accessibility value must contain the selected family, `base/soft/accent` counts, choreography family, and three palette codes. Keep the existing count, motion, focus, grid, and spent-color controls.

Example assertion:

```swift
let summary = app.staticTexts["dayObjects.language"]
XCTAssertTrue(summary.waitForExistence(timeout: 3))
XCTAssertTrue(summary.value.debugDescription.contains("family="))
XCTAssertTrue(summary.value.debugDescription.contains("mutations="))
```

- [ ] **Step 2: Run the lab UI test and verify the old summary fails**

```bash
xcodebuild test -project Steps4.xcodeproj -scheme Steps4 \
  -destination 'platform=iOS Simulator,id=A55C6AF8-3836-4E40-BA57-2C18A9DC81EF' \
  -only-testing:Steps4UITests/DayObjectsLabUITests
```

Expected: FAIL because the summary still prints a comma-separated `enabledMaterials` list.

- [ ] **Step 3: Update the laboratory summary without changing production navigation**

Format the summary as:

```swift
"family=\(scene.visualLanguage.family) "
    + "mutations=\(baseCount)/\(softCount)/\(accentCount) "
    + "motion=\(scene.motionPlan.family) "
    + "palettes=\(background)/\(primary)/\(secondary)"
```

Single and grid modes must both construct `.fullCanvas` inputs. Keep the controls as an overlay above the Metal view and do not clip actor routes to the panel bounds.

- [ ] **Step 4: Regenerate deterministic visual acceptance captures**

Extend `testDeterministicVisualAcceptanceMatrix` to save 1/4/7/10 actor captures for at least five consecutive day keys at motion `0.55`, clarity `0.95`, and times `0`, `31`, and `73` seconds. Record metrics for:

- occupied upper/middle/lower thirds;
- occupied 3x3 sectors;
- minimum and maximum actor diameter;
- focal-centroid displacement;
- frame-to-frame mean RGB difference;
- lower-third non-background actor coverage.

Require every 6+ actor capture group to reach all three vertical thirds and every 8+ actor group to reach six sectors across its three time samples. Do not update committed perceptual signatures until the new PNG attachments have been reviewed.

- [ ] **Step 5: Run UI and visual tests, then commit**

Run:

```bash
xcodebuild test -project Steps4.xcodeproj -scheme Steps4 \
  -destination 'platform=iOS Simulator,id=A55C6AF8-3836-4E40-BA57-2C18A9DC81EF' \
  -only-testing:Steps4UITests/DayObjectsLabUITests \
  -only-testing:Steps4Tests/DayObjectRenderFrameTests/testDeterministicVisualAcceptanceMatrix
```

Expected: PASS and produce reviewable test attachments.

```bash
git add StepsTrader/Experiments/DayObjects/DayObjectsLabView.swift \
  Steps4UITests/DayObjectsLabUITests.swift Steps4Tests/DayObjectRenderFrameTests.swift
git commit -m "test: expose Day Objects circle DNA sandbox states"
```

---

### Task 6: Run regression and physical rendering checks

**Files:**
- Modify only if a verified regression requires an in-scope correction.
- Verify: all files changed in Tasks 1–5.

**Interfaces:**
- Consumes: completed sandbox.
- Produces: verified simulator build/test result and an explicit physical-device status.

- [ ] **Step 1: Run exact Day Objects unit and UI suites**

```bash
xcodebuild test -project Steps4.xcodeproj -scheme Steps4 \
  -destination 'platform=iOS Simulator,id=A55C6AF8-3836-4E40-BA57-2C18A9DC81EF' \
  -only-testing:Steps4Tests/DayObjectSceneTests \
  -only-testing:Steps4Tests/DayObjectPaletteTests \
  -only-testing:Steps4Tests/DayObjectChoreographyTests \
  -only-testing:Steps4Tests/DayObjectRenderFrameTests \
  -only-testing:Steps4UITests/DayObjectsLabUITests
```

Expected: PASS.

- [ ] **Step 2: Build the complete simulator application**

```bash
xcodebuild build -project Steps4.xcodeproj -scheme Steps4 \
  -destination 'generic/platform=iOS Simulator'
```

Expected: `** BUILD SUCCEEDED **` with no new Metal warnings.

- [ ] **Step 3: Run repository integrity checks**

```bash
git diff --check
git status --short
```

Expected: no whitespace errors; only intended Day Objects files plus the pre-existing unrelated feed/localization changes are reported.

- [ ] **Step 4: Inspect the laboratory on the booted iPhone 17 Pro simulator**

Launch the Steps4 scheme, open Day Objects Lab, and inspect:

- five consecutive day seeds;
- counts 1, 4, 7, and 10;
- motion 0, 0.55, and 1;
- focus 0, 0.5, and 1;
- single and grid views;
- controls shown and hidden.

Reject any upper-only grouping, same-size row, hard gradient flip, conic fill, unrelated accent genre, rapid local spin, clipped quad, or frozen low-motion scene.

- [ ] **Step 5: Profile a ten-object physical-device run when a signed device is available**

Use Xcode's Metal System Trace for five minutes with ten actors, motion `1`, focus `1`, and controls hidden. Acceptance is stable 60 Hz presentation, no repeated allocation growth, and no sustained thermal escalation. If signing or device availability prevents this step, record the result as `unmeasured` rather than inferring it from simulator timing.

- [ ] **Step 6: Commit any final in-scope verification fixes**

If Steps 1–5 required no fixes, do not create an empty commit. If a verified Day Objects regression required a correction, stage only its exact files and use:

```bash
git commit -m "fix: complete Day Objects sandbox verification"
```
