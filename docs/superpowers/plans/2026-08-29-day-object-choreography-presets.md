# Day Object Choreography Presets Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the single clustered motion system with ten deterministic daily choreographies that distribute up to ten circles across the full canvas, support flat and spatial size systems, and strongly defocus extreme foreground actors.

**Architecture:** Add a seeded preset catalog that owns stable actor slots, formation geometry, size profile, depth profile, and group direction. `DayObjectMotionPlan` turns those slots into continuous routes, while `DayObjectChoreographyScore` evaluates size, depth, focus, and position without changing the Metal actor ABI. The scene selects one preset before choosing its compatible daily material.

**Tech Stack:** Swift, SIMD, XCTest, SwiftUI scene model, existing Metal instanced actor renderer.

**Spec:** `docs/superpowers/specs/2026-08-29-day-object-choreography-presets-design.md`

## Global Constraints

- Maximum actor count remains exactly 10.
- A day seed selects exactly one deterministic preset and one coherent material family.
- Existing actors keep their slot, appearance, direction, and phase when other events are added or removed.
- Steps only multiply tempo; sleep clarity still controls whole-canvas focus; Reduce Motion freezes all animation phases.
- Flat presets keep actors close to the middle focus plane; only spatial presets routinely use extreme foreground scale.
- Objects may overlap and crop deliberately, but six or more objects must reach all three vertical thirds in distributed presets.
- Keep the existing instanced actor pass; add no per-object textures, render targets, or draw calls.
- Preserve unrelated dirty files and stage only files named in each task.

## File map

- Create `StepsTrader/Experiments/DayObjects/DayObjectChoreographyPreset.swift`: preset catalog, daily configuration, stable ten-slot vocabulary, size/depth profiles, and material compatibility weights.
- Modify `StepsTrader/Experiments/DayObjects/DayObjectMotionPlan.swift`: generate preset-specific closed routes, group directions, and depth schedules from stable slots.
- Modify `StepsTrader/Experiments/DayObjects/DayObjectChoreography.swift`: evaluate preset routes, flat/spatial scale, breathing, opacity, and foreground softness.
- Modify `StepsTrader/Experiments/DayObjects/DayObjectScene.swift`: select one daily configuration and pass it into motion, material, and actor construction.
- Modify `StepsTrader/Experiments/DayObjects/DayObjectTypes.swift`: store slot metadata on each actor.
- Modify `StepsTrader/Experiments/DayObjects/DayObjectVisualLanguage.swift`: weight the one daily material by preset without mixing material families inside a day.
- Modify `StepsTrader/Experiments/DayObjects/DayObjectsLabView.swift`: show the new preset name in the existing diagnostics string.
- Modify `Steps4.xcodeproj/project.pbxproj`: include the new Swift source in the application target.
- Modify `Steps4Tests/DayObjectChoreographyTests.swift`: deterministic catalog, stability, geometry, depth, focus, and continuity tests.
- Modify `Steps4Tests/DayObjectSceneTests.swift`: scene wiring and one-material-per-day tests.
- Modify `Steps4Tests/DayObjectRenderFrameTests.swift`: actor capacity and unchanged render-path assertions.

---

### Task 1: Daily preset catalog and stable slots

**Files:**
- Create: `StepsTrader/Experiments/DayObjects/DayObjectChoreographyPreset.swift`
- Modify: `Steps4.xcodeproj/project.pbxproj`
- Modify: `Steps4Tests/DayObjectChoreographyTests.swift`

**Interfaces:**
- Produces: `DayObjectChoreographyPreset`, `DayObjectSizeProfile`, `DayObjectDepthProfile`, `DayObjectChoreographySlot`, and `DayObjectChoreographyConfiguration.make(seed:)`.
- Consumes: `DayObjectMaterialFamily` for compatibility weights and the existing deterministic `SeededRNG`.

- [ ] **Step 1: Write failing catalog tests**

Add tests that sample at least 2,048 seeds and require all ten cases, deterministic configuration, ten slots, and stable lookup:

```swift
func testDailyPresetCatalogIsDeterministicAndReachesAllTenPresets() {
    var reached = Set<DayObjectChoreographyPreset>()
    for seed in UInt64(0)..<2_048 {
        let first = DayObjectChoreographyConfiguration.make(seed: seed)
        XCTAssertEqual(first, DayObjectChoreographyConfiguration.make(seed: seed))
        XCTAssertEqual(first.slots.map(\.ordinal), Array(0..<10))
        XCTAssertEqual(Set(first.slots.map(\.ordinal)).count, 10)
        reached.insert(first.preset)
    }
    XCTAssertEqual(reached, Set(DayObjectChoreographyPreset.allCases))
}

func testEventSeedAlwaysReturnsTheSameStableSlot() {
    let configuration = DayObjectChoreographyConfiguration.make(seed: 77)
    let ids = (0..<10).map { "event-\($0)" }
    let before = Dictionary(uniqueKeysWithValues: ids.map {
        ($0, configuration.slot(eventID: $0, rootSeed: 77))
    })
    for retained in ids.dropFirst().dropLast() {
        XCTAssertEqual(
            before[retained],
            configuration.slot(eventID: retained, rootSeed: 77)
        )
    }
}
```

- [ ] **Step 2: Run the focused tests and verify the new types are missing**

Run:

```bash
xcodebuild test -project Steps4.xcodeproj -scheme Steps4 -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17,OS=latest' -only-testing:Steps4Tests/DayObjectChoreographyTests CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO
```

Expected: compilation fails because `DayObjectChoreographyPreset` and `DayObjectChoreographyConfiguration` do not exist.

- [ ] **Step 3: Add the exact preset and slot model**

Create the source with these public-to-module shapes and all ten cases:

```swift
enum DayObjectChoreographyPreset: UInt32, CaseIterable, Equatable {
    case circularChoir, doubleOrbit, radialBloom, breathingGrid, waveRibbon
    case spiralProcession, eclipseStack, crossCurrents, constellation, depthField
}

enum DayObjectSizeProfile: Equatable { case uniform, grouped, spatial }
enum DayObjectDepthProfile: Equatable { case flat, layered, migrating }

struct DayObjectChoreographySlot: Equatable {
    let ordinal: Int
    let group: Int
    let anchor: SIMD2<Double>
    let phase: Double
    let direction: Double
    let sizeMultiplier: Double
    let baseDepth: Double
}

struct DayObjectChoreographyConfiguration: Equatable {
    let preset: DayObjectChoreographyPreset
    let sizeProfile: DayObjectSizeProfile
    let depthProfile: DayObjectDepthProfile
    let center: SIMD2<Double>
    let orientation: Double
    let eccentricity: Double
    let slots: [DayObjectChoreographySlot]

    static func make(seed: UInt64) -> Self
    func slot(eventID: String, rootSeed: UInt64) -> DayObjectChoreographySlot
    func materialWeight(for family: DayObjectMaterialFamily) -> Int
}
```

Use one preset configuration RNG domain, clamp centers to `0.18...0.82`, clamp eccentricity to `0.72...1.28`, generate exactly ten priority-ordered slots, and map numeric `event-N` IDs to `N % 10`. For arbitrary IDs, use the existing stable FNV-style event hash modulo ten; collisions retain deterministic actor-local phase offsets rather than triggering a scene-wide remap. Encode these fixed profiles:

```swift
let profiles: [DayObjectChoreographyPreset: (DayObjectSizeProfile, DayObjectDepthProfile)] = [
    .circularChoir: (.uniform, .flat), .doubleOrbit: (.grouped, .flat),
    .radialBloom: (.uniform, .flat), .breathingGrid: (.uniform, .flat),
    .waveRibbon: (.uniform, .flat), .spiralProcession: (.grouped, .flat),
    .eclipseStack: (.grouped, .layered), .crossCurrents: (.grouped, .layered),
    .constellation: (.grouped, .layered), .depthField: (.spatial, .migrating),
]
```

Add the new source to the Day Objects group and the Steps4 Sources build phase in `project.pbxproj`.

- [ ] **Step 4: Run the catalog tests**

Run the focused command from Step 2. Expected: the two new tests pass and existing choreography tests may still fail because motion has not yet migrated.

- [ ] **Step 5: Commit the catalog**

```bash
git add -- StepsTrader/Experiments/DayObjects/DayObjectChoreographyPreset.swift Steps4Tests/DayObjectChoreographyTests.swift Steps4.xcodeproj/project.pbxproj
git commit -m "feat: add daily choreography preset catalog"
```

### Task 2: Preset-specific route and depth generation

**Files:**
- Modify: `StepsTrader/Experiments/DayObjects/DayObjectMotionPlan.swift`
- Modify: `Steps4Tests/DayObjectChoreographyTests.swift`

**Interfaces:**
- Consumes: `DayObjectChoreographyConfiguration` and its stable slots from Task 1.
- Produces: `DayObjectMotionPlan.make(configuration:rootSeed:eventIDs:)`, with `preset`, `routes`, `depths`, and `encounters`.

- [ ] **Step 1: Replace family tests with formation invariants**

Add this helper, which constructs a real scene for a requested preset without
adding a test-only production initializer:

```swift
private func scene(
    for preset: DayObjectChoreographyPreset,
    count: Int
) throws -> DayObjectScene {
    try XCTUnwrap((UInt64(0)..<4_096).lazy.map {
        DayObjectScene.make(input: fixtureInput(seed: $0, count: count))
    }.first { $0.motionPlan.preset == preset })
}
```

Then test exact behavioral groups:

```swift
func testFlatPresetRoutesCloseContinuouslyAndUseOneFocusPlane() throws {
    for preset in [DayObjectChoreographyPreset.circularChoir, .radialBloom,
                   .breathingGrid, .waveRibbon] {
        let scene = try scene(for: preset, count: 10)
        XCTAssertTrue(scene.actors.allSatisfy { abs($0.depthSchedule.amplitude) <= 0.04 })
        for actor in scene.actors {
            let start = actor.route.position(at: 0)
            let end = actor.route.position(at: actor.route.period)
            XCTAssertLessThan(simd_distance(start, end), 0.000_001)
        }
    }
}

func testDoubleOrbitAndCrossCurrentsUseOpposingGroups() throws {
    for preset in [DayObjectChoreographyPreset.doubleOrbit, .crossCurrents] {
        let scene = try scene(for: preset, count: 10)
        XCTAssertEqual(Set(scene.actors.map { $0.route.direction }), [-1, 1])
    }
}
```

Add concrete spatial coverage and depth-field assertions:

```swift
func testEveryDistributedPresetUsesAllVerticalThirdsWithSixActors() throws {
    let presets = DayObjectChoreographyPreset.allCases.filter { $0 != .eclipseStack }
    for preset in presets {
        let scene = try scene(for: preset, count: 6)
        var thirds = Set<Int>()
        for time in stride(from: 0.0, through: scene.score.duration, by: 12.0) {
            for actor in scene.actors {
                let pose = scene.score.pose(
                    for: actor, at: time, canvasAspect: 1,
                    compositionPlan: scene.compositionPlan
                )
                thirds.insert(min(max(Int((0.5 - pose.position.y) * 3), 0), 2))
            }
        }
        XCTAssertEqual(thirds, [0, 1, 2], "preset=\(preset)")
    }
}

func testDepthFieldTraversesFarMiddleAndNearPlanes() throws {
    let scene = try scene(for: .depthField, count: 10)
    let depths = stride(from: 0.0, through: scene.score.duration, by: 2.0)
        .flatMap { time in
            scene.actors.map {
                scene.score.pose(for: $0, at: time, canvasAspect: 1,
                                 compositionPlan: scene.compositionPlan).depth
            }
        }
    XCTAssertLessThan(depths.min()!, 0.20)
    XCTAssertGreaterThan(depths.max()!, 0.85)
    XCTAssertTrue(depths.contains { (0.48...0.62).contains($0) })
}
```

Keep separate named tests for ring-radius variance below `0.04`, grid
row/column order, wave actor order, spiral angular order, and eclipse overlap
followed by separation; each samples the real `pose` API at 12-second
intervals over `score.duration` and reports the preset and sample time on
failure.

- [ ] **Step 2: Run the choreography suite and verify it fails against the five old families**

Run the Task 1 focused command. Expected: failures identify missing preset-specific routing and flat depth schedules.

- [ ] **Step 3: Migrate `DayObjectMotionPlan` to the configuration interface**

Change its stored selection and constructor:

```swift
struct DayObjectMotionPlan: Equatable {
    let configuration: DayObjectChoreographyConfiguration
    let routes: [String: DayObjectRoute]
    let depths: [String: DayObjectDepthSchedule]
    let encounters: [String: DayObjectEncounter]

    var preset: DayObjectChoreographyPreset { configuration.preset }

    static func make(
        configuration: DayObjectChoreographyConfiguration,
        rootSeed: UInt64,
        eventIDs: [String]
    ) -> DayObjectMotionPlan
}
```

Build every route around its slot anchor and produce closed control points for the preset formula: angular ring, paired rings, radial spoke, staggered grid loop, sine ribbon, logarithmic spiral, overlap loop, opposing current, local constellation loop, or depth-field drift. Periods remain `90...220` seconds. Flat schedules use `baseDepth 0.55` and `amplitude 0...0.04`; layered schedules use bounded `0.10...0.22`; migrating schedules use `0.36...0.47`. Preserve the existing `DayObjectRoute.position(at:)` Catmull-Rom evaluator and encounter envelope.

- [ ] **Step 4: Run the focused choreography suite**

Run the command from Task 1. Expected: preset routing, continuity, direction, order, and depth assertions pass.

- [ ] **Step 5: Commit routes**

```bash
git add -- StepsTrader/Experiments/DayObjects/DayObjectMotionPlan.swift Steps4Tests/DayObjectChoreographyTests.swift
git commit -m "feat: generate preset-specific Day Object routes"
```

### Task 3: Size profiles, two-times scale, and camera focus

**Files:**
- Modify: `StepsTrader/Experiments/DayObjects/DayObjectTypes.swift`
- Modify: `StepsTrader/Experiments/DayObjects/DayObjectChoreography.swift`
- Modify: `Steps4Tests/DayObjectChoreographyTests.swift`

**Interfaces:**
- Consumes: `DayObjectChoreographySlot`, `DayObjectSizeProfile`, and `DayObjectDepthProfile`.
- Produces: preset-aware `DayObjectPose` scale and `localDepthSoftness` without changing GPU uniforms.

- [ ] **Step 1: Write failing size and focus tests**

```swift
func testUniformDaysKeepMediumActorsWithinFivePercent() throws {
    let scene = try scene(for: .circularChoir, count: 10)
    let scales = scene.actors.map {
        scene.score.pose(for: $0, at: 0, canvasAspect: 1,
                         compositionPlan: scene.compositionPlan).scale
    }
    XCTAssertLessThanOrEqual(scales.max()! / scales.min()!, 1.05)
    XCTAssertTrue(scales.allSatisfy { (0.22...0.38).contains($0) })
}

func testDepthFieldUsesVeryDifferentSizesAndBlursNearestActorMost() throws {
    let scene = try scene(for: .depthField, count: 10)
    let poses = scene.actors.map {
        scene.score.pose(for: $0, at: 0, canvasAspect: 1,
                         compositionPlan: scene.compositionPlan)
    }
    XCTAssertGreaterThan(poses.map(\.scale).max()! / poses.map(\.scale).min()!, 3.0)
    let nearest = poses.max { $0.depth < $1.depth }!
    let middle = poses.min { abs($0.depth - 0.55) < abs($1.depth - 0.55) }!
    XCTAssertGreaterThan(nearest.localDepthSoftness, middle.localDepthSoftness * 2)
}
```

- [ ] **Step 2: Run the focused suite and confirm failures**

Run the Task 1 command. Expected: current size-band selection violates uniform profiles and near softness is below the new ratio.

- [ ] **Step 3: Store slots and evaluate profile-aware scale**

Add `let choreographySlot: DayObjectChoreographySlot` to `DayObjectActor`. In `DayObjectChoreographyScore.pose`, replace unconditional depth scaling with:

```swift
let profile = actor.choreographyConfiguration.sizeProfile
let depthScale = profile == .spatial ? 0.56 + 1.04 * depth : 1
let breathingAmplitude = profile == .uniform ? 0.018 : 0.035
let breathing = 1 + breathingAmplitude * sin(actorBreathingPhase)
let scale = presetDiameter(for: actor) * depthScale * breathing
```

Use full-canvas diameters `0.22...0.36` for uniform, two or three values in `0.16...0.46` for grouped, and `0.12...0.74` for spatial. These ranges are approximately twice the small legacy on-screen cap while allowing depth-field foreground circles to crop beyond the canvas. Flat profiles ignore depth-derived opacity and use `0.86...1.0`; layered/spatial profiles keep depth response with a floor of `0.72`.

Increase near-field softness without softening the middle plane:

```swift
return 0.018
    + 0.30 * pow(farDistance, 1.35)
    + 0.62 * pow(nearDistance, 1.35)
```

Update footprint planning to use the evaluated preset diameter; allow intentional crop only for `.depthField` and `.eclipseStack`.

- [ ] **Step 4: Run choreography tests**

Run the focused command. Expected: size-profile, focus, route-safety, and continuity tests pass.

- [ ] **Step 5: Commit scale and focus behavior**

```bash
git add -- StepsTrader/Experiments/DayObjects/DayObjectTypes.swift StepsTrader/Experiments/DayObjects/DayObjectChoreography.swift Steps4Tests/DayObjectChoreographyTests.swift
git commit -m "feat: add preset size and focus profiles"
```

### Task 4: Scene wiring and preset-material compatibility

**Files:**
- Modify: `StepsTrader/Experiments/DayObjects/DayObjectScene.swift`
- Modify: `StepsTrader/Experiments/DayObjects/DayObjectVisualLanguage.swift`
- Modify: `StepsTrader/Experiments/DayObjects/DayObjectsLabView.swift`
- Modify: `Steps4Tests/DayObjectSceneTests.swift`
- Modify: `Steps4Tests/DayObjectChoreographyTests.swift`

**Interfaces:**
- Consumes: `DayObjectChoreographyConfiguration.make(seed:)` and `materialWeight(for:)`.
- Produces: `DayObjectScene.choreographyConfiguration` and preset-compatible `DayObjectVisualLanguage.make(rootSeed:paletteSet:choreography:)`.

- [ ] **Step 1: Write failing scene integration tests**

```swift
func testSceneUsesOnePresetAndOneMaterialForTheWholeDay() {
    let scene = DayObjectScene.make(input: input((0..<10).map { "event-\($0)" }))
    XCTAssertEqual(scene.motionPlan.configuration, scene.choreographyConfiguration)
    XCTAssertEqual(Set(scene.actors.map { $0.appearance.material }), [scene.visualLanguage.family])
    XCTAssertEqual(Set(scene.actors.map { $0.choreographySlot.ordinal }).count,
                   Set(scene.actors.map { $0.id }).count)
}

func testAddingAnEventDoesNotRerollRetainedActors() {
    let five = DayObjectScene.make(input: input((0..<5).map { "event-\($0)" }))
    let six = DayObjectScene.make(input: input((0..<6).map { "event-\($0)" }))
    for actor in five.actors {
        let retained = six.actors.first { $0.id == actor.id }!
        XCTAssertEqual(retained.appearance, actor.appearance)
        XCTAssertEqual(retained.route, actor.route)
        XCTAssertEqual(retained.choreographySlot, actor.choreographySlot)
    }
}
```

- [ ] **Step 2: Run scene and choreography tests and verify constructor failures**

```bash
xcodebuild test -project Steps4.xcodeproj -scheme Steps4 -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17,OS=latest' -only-testing:Steps4Tests/DayObjectSceneTests -only-testing:Steps4Tests/DayObjectChoreographyTests CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO
```

Expected: compilation fails until scene and visual-language signatures are migrated.

- [ ] **Step 3: Wire selection in one order**

In `DayObjectScene.make`, use this order and store the configuration:

```swift
let choreography = DayObjectChoreographyConfiguration.make(seed: rootSeed)
let visualLanguage = DayObjectVisualLanguage.make(
    rootSeed: rootSeed,
    paletteSet: paletteSet,
    choreography: choreography
)
let motionPlan = DayObjectMotionPlan.make(
    configuration: choreography,
    rootSeed: rootSeed,
    eventIDs: eventIDs
)
```

Pass each stable slot into `makeActor`. Select the one family from a repeated weighted array derived from `choreography.materialWeight(for:)`; do not select a second per-actor material. Update the lab diagnostic text from `motionPlan.family` to `motionPlan.preset`.

- [ ] **Step 4: Run scene and choreography tests**

Run the command from Step 2. Expected: all selected suites pass.

- [ ] **Step 5: Commit scene wiring**

```bash
git add -- StepsTrader/Experiments/DayObjects/DayObjectScene.swift StepsTrader/Experiments/DayObjects/DayObjectVisualLanguage.swift StepsTrader/Experiments/DayObjects/DayObjectsLabView.swift Steps4Tests/DayObjectSceneTests.swift Steps4Tests/DayObjectChoreographyTests.swift
git commit -m "feat: wire daily choreography through Day Objects"
```

### Task 5: Render-path and regression verification

**Files:**
- Modify: `Steps4Tests/DayObjectRenderFrameTests.swift`
- Modify: `Steps4Tests/DayObjectChoreographyTests.swift`

**Interfaces:**
- Consumes: completed preset-aware scenes.
- Produces: regression evidence that all ten actors stay in the existing render path and animation controls keep their responsibilities.

- [ ] **Step 1: Add render and control regressions**

Add a test that renders representative uniform, overlap, and depth-field seeds
at 1, 5, and 10 actors and verifies no actor is dropped and all compact pose
values remain finite:

```swift
func testPresetFramesKeepEveryActorFiniteWithinCapacity() throws {
    for preset in [DayObjectChoreographyPreset.circularChoir,
                   .eclipseStack, .depthField] {
        for count in [1, 5, 10] {
            let scene = try scene(for: preset, count: count)
            let frame = DayObjectRenderFrame.make(
                scene: scene,
                environment: .init(motionEnergy: 0.55,
                                   visualClarity: 0.55,
                                   reduceMotion: false),
                elapsed: 42,
                insertions: [:]
            )
            XCTAssertEqual(frame.actors.count, scene.actors.count)
            XCTAssertLessThanOrEqual(frame.actors.count, DayObjectScene.maxActors)
            XCTAssertTrue(frame.actors.allSatisfy {
                $0.halfSize.x.isFinite && $0.halfSize.y.isFinite
                    && $0.opacity.isFinite && $0.depth.isFinite
                    && $0.halfSize.x >= 0 && $0.halfSize.y >= 0
            })
        }
    }
}

func testMotionEnergyChangesTimeButNotDailyConfiguration() throws {
    let scene = try scene(for: .waveRibbon, count: 10)
    let slow = DayObjectRenderFrame.make(
        scene: scene,
        environment: .init(motionEnergy: 0, visualClarity: 1, reduceMotion: false),
        elapsed: 30,
        insertions: [:]
    )
    let fast = DayObjectRenderFrame.make(
        scene: scene,
        environment: .init(motionEnergy: 1, visualClarity: 1, reduceMotion: false),
        elapsed: 30,
        insertions: [:]
    )
    XCTAssertLessThan(slow.choreographyTime, fast.choreographyTime)
    let rebuilt = DayObjectScene.make(input: scene.input)
    XCTAssertEqual(scene.motionPlan.preset, .waveRibbon)
    XCTAssertEqual(scene.actors.map(\.choreographySlot),
                   rebuilt.actors.map(\.choreographySlot))
}
```

Retain and run the existing
`testReduceMotionFreezesPositionDepthAndMaterialPhase`, which already compares
complete early and late frames.

- [ ] **Step 2: Run targeted model and renderer suites**

```bash
xcodebuild test -project Steps4.xcodeproj -scheme Steps4 -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17,OS=latest' -only-testing:Steps4Tests/DayObjectSceneTests -only-testing:Steps4Tests/DayObjectChoreographyTests -only-testing:Steps4Tests/DayObjectRenderFrameTests CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO
```

Expected: all selected suites pass.

- [ ] **Step 3: Run the full unit-test target**

```bash
xcodebuild test -project Steps4.xcodeproj -scheme Steps4 -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17,OS=latest' -only-testing:Steps4Tests CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO
```

Expected: `TEST SUCCEEDED` with no Day Objects regression.

- [ ] **Step 4: Build the simulator application**

```bash
xcodebuild build -project Steps4.xcodeproj -scheme Steps4 -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17,OS=latest' CODE_SIGNING_ALLOWED=NO
```

Expected: `BUILD SUCCEEDED`.

- [ ] **Step 5: Commit verification changes**

```bash
git add -- Steps4Tests/DayObjectRenderFrameTests.swift Steps4Tests/DayObjectChoreographyTests.swift
git commit -m "test: verify daily choreography render integration"
```
