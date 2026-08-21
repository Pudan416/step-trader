# Day Objects Choreography Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the independent Day Objects particle field with a deterministic daily choreography whose stable event-derived actors share one palette and timeline over a Warp-like gradient, sleep-controlled focus, and sharp grain.

**Architecture:** Pure Swift models derive a daily palette, score, and stable actors from domain-separated seeds. A frame evaluator converts the score and environment inputs into sorted GPU actor states once per frame. A MetalKit renderer executes four bounded stages: half-resolution Warp background, full-resolution instanced actors, separable focus blur, and full-resolution grain/display.

**Tech Stack:** Swift 6, SwiftUI, MetalKit, Metal Shading Language, XCTest, XCUITest.

**Spec:** `docs/superpowers/specs/2026-08-20-day-objects-choreography-design.md`

## Global Constraints

- The first implementation remains behind the existing debug-only Day Objects lab route.
- `motionEnergy` and `visualClarity` are clamped to `0...1`; HealthKit integration is out of scope.
- The actor seed is derived from `identity + dayKey + eventID + memberIndex` and never from total count or array index.
- Adding an event must preserve every existing actor and its evaluated frame state.
- A scene may render at most 40 actors.
- Actor speed ratios are limited to `0.5`, `0.75`, `1`, `1.5`, and `2`.
- The daily palette is the only color source for the Warp background, figures, accents, and trails.
- The Warp background remains slowly animated independently of `motionEnergy`.
- Sleep blur applies before grain; grain remains sharp.
- Reduce Motion fixes choreography tempo to `0.02`, disables trails, and freezes grain phase.
- GPU performance is validated on a physical supported iPhone; simulator timing is not performance evidence.
- Do not stage, overwrite, or commit unrelated changes already present in the working tree.

---

## File Structure

### Create

- `StepsTrader/Experiments/DayObjects/DayObjectTypes.swift` — shared numeric types, input, actor roles, chapters, and GPU-safe enums.
- `StepsTrader/Experiments/DayObjects/DayObjectPalette.swift` — coherent palette selection, role derivation, contrast checks, and Warp parameters.
- `StepsTrader/Experiments/DayObjects/DayObjectChoreography.swift` — score generation and continuous chapter evaluation.
- `StepsTrader/Experiments/DayObjects/DayObjectScene.swift` — stable event-to-actor allocation and immutable daily scene.
- `StepsTrader/Experiments/DayObjects/DayObjectRenderFrame.swift` — environment mapping, insertion envelopes, depth sorting, and GPU actor packing.
- `StepsTrader/Experiments/DayObjects/DayObjectsRenderer.swift` — Metal resources, resize handling, render passes, and frame submission.
- `StepsTrader/Experiments/DayObjects/DayObjectsMetalView.swift` — `UIViewRepresentable` bridge for the renderer.
- `StepsTrader/Metal/DayObjectsWarpShader.metal` — half-resolution Warp background.
- `StepsTrader/Metal/DayObjectsActorShader.metal` — instanced actor bodies and trails.
- `StepsTrader/Metal/DayObjectsPostShader.metal` — separable blur and final grain/display pass.
- `Steps4Tests/DayObjectSceneTests.swift` — stable identity/allocation tests.
- `Steps4Tests/DayObjectPaletteTests.swift` — palette and Warp-range tests.
- `Steps4Tests/DayObjectChoreographyTests.swift` — score continuity and path-bound tests.
- `Steps4Tests/DayObjectRenderFrameTests.swift` — motion, focus, insertion, sorting, and packing tests.
- `Steps4UITests/DayObjectsLabUITests.swift` — lab smoke and control tests.

### Modify

- `StepsTrader/Experiments/DayObjects/DayObjectComposition.swift` — retain shape geometry enums, remove independent field generation, and provide a temporary compatibility summary.
- `StepsTrader/Experiments/DayObjects/DayObjectsView.swift` — replace the SwiftUI `colorEffect` loop with scene/environment inputs and `DayObjectsMetalView`.
- `StepsTrader/Experiments/DayObjects/DayObjectsLabView.swift` — use stable fixture event IDs and expose motion/focus sliders.
- `StepsTrader/Metal/DayObjectsShader.metal` — remove the obsolete all-objects-per-fragment entry point after the new renderer is green.
- `Steps4Tests/DayObjectCompositionTests.swift` — retain shape reachability checks and remove assertions for the superseded count-seeded field.
- `Steps4.xcodeproj/project.pbxproj` — add the new Swift, Metal, unit-test, and UI-test sources to their existing targets without disturbing current project changes.

---

### Task 1: Stable scene input and actor allocation

**Files:**
- Create: `StepsTrader/Experiments/DayObjects/DayObjectTypes.swift`
- Create: `StepsTrader/Experiments/DayObjects/DayObjectScene.swift`
- Create: `Steps4Tests/DayObjectSceneTests.swift`
- Modify: `StepsTrader/Experiments/DayObjects/DayObjectComposition.swift`
- Modify: `Steps4.xcodeproj/project.pbxproj`

**Interfaces:**
- Produces: `DayObjectSceneInput`, `DayObjectActorID`, `DayObjectActor`, `DayObjectScene.make(input:)`, and `DayObjectScene.maxActors`.
- Consumes: `CanvasElement.makeSeed`, `SeededRNG`, and existing shape/scale enums.

- [ ] **Step 1: Write failing actor-stability tests**

```swift
final class DayObjectSceneTests: XCTestCase {
    private func input(_ ids: [String]) -> DayObjectSceneInput {
        .init(dayKey: "2026-08-20", identity: "tester", eventIDs: ids,
              motionEnergy: 0.55, visualClarity: 0.55, reduceMotion: false)
    }

    func testAddingEventPreservesExistingActors() {
        let before = DayObjectScene.make(input: input(["walk", "sleep"]))
        let after = DayObjectScene.make(input: input(["walk", "sleep", "read"]))
        let retained = after.actors.filter { before.actorIDs.contains($0.id) }
        XCTAssertEqual(retained, before.actors)
    }

    func testEventOrderDoesNotChangeActors() {
        let a = DayObjectScene.make(input: input(["walk", "sleep"]))
        let b = DayObjectScene.make(input: input(["sleep", "walk"]))
        XCTAssertEqual(
            Dictionary(uniqueKeysWithValues: a.actors.map { ($0.id, $0) }),
            Dictionary(uniqueKeysWithValues: b.actors.map { ($0.id, $0) })
        )
    }

    func testDuplicateEventsAreDeduplicatedAndBudgeted() {
        let ids = (0..<80).flatMap { ["event-\($0)", "event-\($0)"] }
        let scene = DayObjectScene.make(input: input(ids))
        XCTAssertLessThanOrEqual(scene.actors.count, 40)
        XCTAssertEqual(Set(scene.actorIDs).count, scene.actors.count)
    }
}
```

- [ ] **Step 2: Run the focused tests and verify RED**

Run:

```bash
xcodebuild test -project Steps4.xcodeproj -scheme Steps4 -destination 'platform=iOS Simulator,id=00349825-3076-4659-80E4-50B9CFF9090F' -only-testing:Steps4Tests/DayObjectSceneTests CODE_SIGNING_ALLOWED=NO
```

Expected: compilation fails because `DayObjectSceneInput` and `DayObjectScene` do not exist.

- [ ] **Step 3: Implement the minimal stable model**

Define the public shape of the input and actor identity:

```swift
struct DayObjectSceneInput: Equatable {
    let dayKey: String
    let identity: String
    let eventIDs: [String]
    let motionEnergy: Double
    let visualClarity: Double
    let reduceMotion: Bool
}

struct DayObjectActorID: Hashable, Comparable {
    let eventID: String
    let memberIndex: Int
    static func < (lhs: Self, rhs: Self) -> Bool {
        (lhs.eventID, lhs.memberIndex) < (rhs.eventID, rhs.memberIndex)
    }
}
```

In `DayObjectScene.make(input:)`, normalize empty identity to `"anonymous"`, de-duplicate event IDs while preserving their first chronological position, derive the daily root from identity/day, and derive each actor only from the event domain. Allocate stable event groups in input order and stop before 40 so a later event never displaces an existing actor. Never include `eventIDs.count` in a seed. Sort only evaluated render states by depth and actor ID.

- [ ] **Step 4: Run focused tests and the legacy Day Object suite**

Run the Task 1 command plus:

```bash
xcodebuild test -project Steps4.xcodeproj -scheme Steps4 -destination 'platform=iOS Simulator,id=00349825-3076-4659-80E4-50B9CFF9090F' -only-testing:Steps4Tests/DayObjectCompositionTests CODE_SIGNING_ALLOWED=NO
```

Expected: both suites pass.

- [ ] **Step 5: Commit only Task 1 files**

```bash
git add -- StepsTrader/Experiments/DayObjects/DayObjectTypes.swift StepsTrader/Experiments/DayObjects/DayObjectScene.swift StepsTrader/Experiments/DayObjects/DayObjectComposition.swift Steps4Tests/DayObjectSceneTests.swift Steps4.xcodeproj/project.pbxproj
git commit -m 'feat: add stable day object actors'
```

---

### Task 2: Unified daily palette and Warp style

**Files:**
- Create: `StepsTrader/Experiments/DayObjects/DayObjectPalette.swift`
- Create: `Steps4Tests/DayObjectPaletteTests.swift`
- Modify: `StepsTrader/Experiments/DayObjects/DayObjectScene.swift`
- Modify: `Steps4.xcodeproj/project.pbxproj`

**Interfaces:**
- Produces: `DayObjectRGB`, `DayObjectPalette.make(seed:)`, `DayObjectWarpStyle.make(seed:palette:)`, and `relativeLuminance`/contrast helpers.
- Consumes: `CanvasColorPalette.paletteHex` and the scene root seed from Task 1.

- [ ] **Step 1: Write failing palette tests**

```swift
final class DayObjectPaletteTests: XCTestCase {
    func testPaletteAndWarpStyleAreDeterministicAndInRange() {
        let palette = DayObjectPalette.make(seed: 42)
        let style = DayObjectWarpStyle.make(seed: 42, palette: palette)
        XCTAssertEqual(palette, DayObjectPalette.make(seed: 42))
        XCTAssertTrue((3...5).contains(style.colors.count))
        XCTAssertTrue((0.02...0.18).contains(style.proportion))
        XCTAssertTrue((0.75...1.0).contains(style.softness))
        XCTAssertTrue((0.15...0.40).contains(style.distortion))
        XCTAssertTrue((0.45...0.90).contains(style.swirl))
        XCTAssertTrue((6...12).contains(style.swirlIterations))
        XCTAssertTrue((0.05...0.18).contains(style.speed))
    }

    func testFigureRolesContrastWithBackgroundBase() {
        for seed in UInt64(0)..<400 {
            let palette = DayObjectPalette.make(seed: seed)
            XCTAssertGreaterThanOrEqual(palette.minimumFigureContrast, 1.35)
        }
    }
}
```

- [ ] **Step 2: Run tests and verify RED**

Run the focused test command with `-only-testing:Steps4Tests/DayObjectPaletteTests`.

Expected: compilation fails because palette types do not exist.

- [ ] **Step 3: Implement palette roles and Warp ranges**

Use a seeded 3–5-color selection from one contiguous `CanvasColorPalette.paletteHex` window. Convert hex to sRGB, derive darker background roles without changing hue family, choose figure roles by maximum contrast, and expose linear-RGB values for Metal. Define Warp pattern as a stable numeric enum (`edge = 0`, `stripes = 1`, `checks = 2`) with edge weighted 70%.

- [ ] **Step 4: Run palette and scene suites**

Expected: both suites pass with no non-finite numeric values.

- [ ] **Step 5: Commit Task 2**

```bash
git add -- StepsTrader/Experiments/DayObjects/DayObjectPalette.swift StepsTrader/Experiments/DayObjects/DayObjectScene.swift Steps4Tests/DayObjectPaletteTests.swift Steps4.xcodeproj/project.pbxproj
git commit -m 'feat: derive unified day object palettes'
```

---

### Task 3: Daily choreography score and continuous evaluator

**Files:**
- Create: `StepsTrader/Experiments/DayObjects/DayObjectChoreography.swift`
- Create: `Steps4Tests/DayObjectChoreographyTests.swift`
- Modify: `StepsTrader/Experiments/DayObjects/DayObjectScene.swift`
- Modify: `Steps4.xcodeproj/project.pbxproj`

**Interfaces:**
- Produces: `DayObjectChapter`, `DayObjectChoreographyScore.make(seed:)`, `DayObjectPose`, and `score.pose(for:at:canvasAspect:)`.
- Consumes: stable `DayObjectActor` values and palette-independent short-side coordinates.

- [ ] **Step 1: Write failing continuity and synchronization tests**

```swift
final class DayObjectChoreographyTests: XCTestCase {
    private func fixtureInput(seed: UInt64, count: Int) -> DayObjectSceneInput {
        DayObjectSceneInput(
            dayKey: "fixture-\(seed)", identity: "tester",
            eventIDs: (0..<count).map { "event-\($0)" },
            motionEnergy: 0.55, visualClarity: 0.55, reduceMotion: false
        )
    }

    func testEveryScoreUsesCuratedSpeedRatios() {
        let allowed: Set<Double> = [0.5, 0.75, 1, 1.5, 2]
        for seed in UInt64(0)..<300 {
            let scene = DayObjectScene.make(input: fixtureInput(seed: seed, count: 12))
            XCTAssertTrue(scene.actors.allSatisfy { allowed.contains($0.speedRatio) })
        }
    }

    func testLoopAndChapterBoundariesAreContinuous() {
        let scene = DayObjectScene.make(input: fixtureInput(seed: 7, count: 10))
        let score = scene.score
        for actor in scene.actors {
            for boundary in score.boundaryTimes + [score.duration] {
                let a = score.pose(for: actor, at: boundary - 0.0001, canvasAspect: 0.46)
                let b = score.pose(for: actor, at: boundary + 0.0001, canvasAspect: 0.46)
                XCTAssertLessThan(simd_distance(a.position, b.position), 0.002)
                XCTAssertLessThan(abs(a.opacity - b.opacity), 0.01)
            }
        }
    }

    func testPathsRemainInsideShortSideBounds() {
        let scene = DayObjectScene.make(input: fixtureInput(seed: 11, count: 40))
        for aspect in [0.46, 0.75, 1.0, 1.5, 2.16] {
            for sample in 0..<240 {
                let time = scene.score.duration * Double(sample) / 240
                for actor in scene.actors {
                    XCTAssertTrue(scene.score.pose(for: actor, at: time, canvasAspect: aspect).isInsideSafeBounds)
                }
            }
        }
    }
}
```

- [ ] **Step 2: Run the choreography suite and verify RED**

Expected: compilation fails because score/evaluator types are missing.

- [ ] **Step 3: Implement score generation and chapter evaluators**

Generate 3–5 chapters and a 36–72 second duration. Implement `orbit`, `spiral`, `crossing`, `stack`, `bloom`, and `drift` as pure functions returning position, tangent, rotation, scale, opacity, and depth band. Interpolate the last 12% of each chapter with quintic smoothstep and evaluate the final-to-first boundary through the same code path. Use finite differences in time, not parameter direction, for heading.

- [ ] **Step 4: Run choreography, scene, and palette suites**

Expected: all pass across the seed and aspect samples.

- [ ] **Step 5: Commit Task 3**

```bash
git add -- StepsTrader/Experiments/DayObjects/DayObjectChoreography.swift StepsTrader/Experiments/DayObjects/DayObjectScene.swift Steps4Tests/DayObjectChoreographyTests.swift Steps4.xcodeproj/project.pbxproj
git commit -m 'feat: generate synchronized daily choreography'
```

---

### Task 4: Environment mapping, insertion envelopes, and GPU frame ABI

**Files:**
- Create: `StepsTrader/Experiments/DayObjects/DayObjectRenderFrame.swift`
- Create: `Steps4Tests/DayObjectRenderFrameTests.swift`
- Modify: `Steps4.xcodeproj/project.pbxproj`

**Interfaces:**
- Produces: `DayObjectEnvironment`, `DayObjectInsertionState`, `DayObjectGPUActor`, `DayObjectRenderFrame.make(...)`, `DayObjectPostProcess`.
- Consumes: `DayObjectScene`, score poses, master elapsed time, and actor insertion timestamps.

- [ ] **Step 1: Write failing environment and insertion tests**

```swift
final class DayObjectRenderFrameTests: XCTestCase {
    private func fixtureScene(ids: [String]) -> DayObjectScene {
        DayObjectScene.make(input: .init(
            dayKey: "2026-08-20", identity: "tester", eventIDs: ids,
            motionEnergy: 0.55, visualClarity: 0.55, reduceMotion: false
        ))
    }

    func testMotionEnergyMapsToSpecifiedTempo() {
        XCTAssertEqual(DayObjectEnvironment(motionEnergy: 0, visualClarity: 1, reduceMotion: false).tempoScale, 0.035, accuracy: 0.0001)
        XCTAssertEqual(DayObjectEnvironment(motionEnergy: 1, visualClarity: 1, reduceMotion: false).tempoScale, 1.25, accuracy: 0.0001)
        XCTAssertEqual(DayObjectEnvironment(motionEnergy: 1, visualClarity: 1, reduceMotion: true).tempoScale, 0.02, accuracy: 0.0001)
    }

    func testSleepFocusIsMonotonicAndLeavesGrainIndependent() {
        let clear = DayObjectPostProcess(visualClarity: 1, reduceMotion: false, grainSeed: 9)
        let tired = DayObjectPostProcess(visualClarity: 0, reduceMotion: false, grainSeed: 9)
        XCTAssertEqual(clear.blurRadius, 0, accuracy: 0.0001)
        XCTAssertEqual(tired.blurRadius, 18, accuracy: 0.0001)
        XCTAssertEqual(clear.grainIntensity, tired.grainIntensity)
    }

    func testAddingActorDoesNotChangeExistingFrameStates() {
        let before = fixtureScene(ids: ["a", "b"])
        let after = fixtureScene(ids: ["a", "b", "c"])
        let environment = DayObjectEnvironment(motionEnergy: 0.55, visualClarity: 0.55, reduceMotion: false)
        let frameA = DayObjectRenderFrame.make(scene: before, environment: environment, elapsed: 12, insertions: [:])
        let frameB = DayObjectRenderFrame.make(scene: after, environment: environment, elapsed: 12, insertions: ["c": 11.5])
        XCTAssertEqual(frameA.actors, frameB.actors.filter { $0.eventID != "c" })
        XCTAssertTrue(frameB.actors.filter { $0.eventID == "c" }.allSatisfy { $0.opacity > 0 && $0.opacity < 1 })
    }
}
```

- [ ] **Step 2: Run the focused suite and verify RED**

Expected: missing environment, post-process, and frame types.

- [ ] **Step 3: Implement the CPU frame evaluator and explicit ABI**

Clamp inputs, apply the exact tempo/blur/contrast/saturation equations from the spec, evaluate actor poses once, apply 0.8–1.4 second actor-local entrance envelopes, disable trails under Reduce Motion, sort by depth/ID, and pack an aligned `DayObjectGPUActor` containing position, direction, half-size, color, opacity, trail length, shape, fill, and depth.

- [ ] **Step 4: Run all four Day Object unit suites**

Expected: all pass; packed values and strides are finite and stable.

- [ ] **Step 5: Commit Task 4**

```bash
git add -- StepsTrader/Experiments/DayObjects/DayObjectRenderFrame.swift Steps4Tests/DayObjectRenderFrameTests.swift Steps4.xcodeproj/project.pbxproj
git commit -m 'feat: evaluate day object render frames'
```

---

### Task 5: MetalKit renderer scaffold and render-target lifecycle

**Files:**
- Create: `StepsTrader/Experiments/DayObjects/DayObjectsRenderer.swift`
- Create: `StepsTrader/Experiments/DayObjects/DayObjectsMetalView.swift`
- Modify: `StepsTrader/Experiments/DayObjects/DayObjectsView.swift`
- Modify: `Steps4Tests/DayObjectRenderFrameTests.swift`
- Modify: `Steps4.xcodeproj/project.pbxproj`

**Interfaces:**
- Produces: `DayObjectsRenderer`, `DayObjectsMetalView(scene:environment:isAnimating:)`, render-target descriptors, and injectable `DayObjectsClock`.
- Consumes: `DayObjectRenderFrame`, `MTKView`, and the shader entry points created in Tasks 6–8.

- [ ] **Step 1: Add failing render-target and clock tests**

Add assertions that a `1179×2556` drawable produces a Warp target no larger than half linear resolution and one million pixels, a full-size scene target, two full-size blur targets, and a monotonic elapsed time that does not wrap hourly.

- [ ] **Step 2: Run tests and verify RED**

Expected: renderer resource planner and clock do not exist.

- [ ] **Step 3: Implement the renderer shell**

Create a 30 FPS `MTKView`, command queue, immutable quad geometry, resize-aware private textures, actor buffer capacity 40, and a coordinator that updates scene/environment without recreating the view. Use seconds since a renderer-local origin; pause by retaining elapsed time rather than resetting it. Add temporary clear-only Metal functions in the existing shader so the scaffold builds before feature passes are introduced.

- [ ] **Step 4: Run unit suites and build the app**

Run:

```bash
xcodebuild build -project Steps4.xcodeproj -scheme Steps4 -destination 'platform=iOS Simulator,id=00349825-3076-4659-80E4-50B9CFF9090F' CODE_SIGNING_ALLOWED=NO
```

Expected: build succeeds and no shader entry point is missing.

- [ ] **Step 5: Commit Task 5**

```bash
git add -- StepsTrader/Experiments/DayObjects/DayObjectsRenderer.swift StepsTrader/Experiments/DayObjects/DayObjectsMetalView.swift StepsTrader/Experiments/DayObjects/DayObjectsView.swift Steps4Tests/DayObjectRenderFrameTests.swift Steps4.xcodeproj/project.pbxproj StepsTrader/Metal/DayObjectsShader.metal
git commit -m 'feat: scaffold day objects metal renderer'
```

---

### Task 6: Warp background pass

**Files:**
- Create: `StepsTrader/Metal/DayObjectsWarpShader.metal`
- Modify: `StepsTrader/Experiments/DayObjects/DayObjectsRenderer.swift`
- Modify: `Steps4Tests/DayObjectPaletteTests.swift`
- Modify: `Steps4.xcodeproj/project.pbxproj`

**Interfaces:**
- Produces: Metal entry points `dayObjectsFullscreenVertex` and `dayObjectsWarpFragment`, and `DayObjectsWarpUniforms` mirrored in Swift.
- Consumes: half-resolution target, daily palette roles, Warp style, and independent ambient time.

- [ ] **Step 1: Add a failing Warp uniform-layout test**

Assert exact `MemoryLayout<DayObjectsWarpUniforms>.stride`, color count clamping to `3...5`, swirl iterations to `6...12`, and that background time changes while `motionEnergy == 0`.

- [ ] **Step 2: Run the focused test and verify RED**

Expected: Warp uniforms do not exist.

- [ ] **Step 3: Implement original Warp-like field rendering**

Render a full-screen triangle into the half-resolution texture. Build an edge/stripe/check base coordinate, apply seeded rotation/scale/offset, distort with smooth value noise, perform the bounded swirl loop, and blend the 3–5 linear-RGB daily colors with `proportion` and `softness`. The loop bound is the uniform iteration count capped at 12.

- [ ] **Step 4: Build and launch the Day Objects lab fixture**

Run the app with `-uiLab dayObjects`, verify the drawable is not black at zero actors, and capture one fixed-day screenshot for later comparison.

- [ ] **Step 5: Commit Task 6**

```bash
git add -- StepsTrader/Metal/DayObjectsWarpShader.metal StepsTrader/Experiments/DayObjects/DayObjectsRenderer.swift Steps4Tests/DayObjectPaletteTests.swift Steps4.xcodeproj/project.pbxproj
git commit -m 'feat: render daily warp background'
```

---

### Task 7: Instanced choreographed figures and trails

**Files:**
- Create: `StepsTrader/Metal/DayObjectsActorShader.metal`
- Modify: `StepsTrader/Experiments/DayObjects/DayObjectsRenderer.swift`
- Modify: `Steps4Tests/DayObjectChoreographyTests.swift`
- Modify: `Steps4Tests/DayObjectRenderFrameTests.swift`
- Modify: `Steps4.xcodeproj/project.pbxproj`

**Interfaces:**
- Produces: `dayObjectsActorVertex`, `dayObjectsActorFragment`, premultiplied-alpha actor pipeline, and per-frame actor buffer upload.
- Consumes: depth-sorted `DayObjectGPUActor` states and the upscaled Warp scene target.

- [ ] **Step 1: Add failing direction and energy-normalization tests**

Assert that forward and reversed actors have trail vectors opposite their actual time derivative, body antialias width is expressed in screen pixels, and total actor energy uses `1 / sqrt(visibleCount)` with finite results for zero actors.

- [ ] **Step 2: Run tests and verify RED**

Expected: direction/energy helpers are absent or return the old behavior.

- [ ] **Step 3: Implement instanced actor rendering**

Draw one expanded quad per actor in sorted order. The vertex shader bounds each quad by body plus trail reach. The fragment shader evaluates the seven existing SDF bodies, `fwidth` antialiasing, an exponential trail behind actual velocity, Gaussian lateral falloff, palette-role color, and density-normalized premultiplied alpha. It never loops over other actors.

- [ ] **Step 4: Run tests, build, and inspect 1/10/24/40 actor fixtures**

Expected: no clipping caused by aspect conversion, no blank frame, and visible complexity grows without global reroll.

- [ ] **Step 5: Commit Task 7**

```bash
git add -- StepsTrader/Metal/DayObjectsActorShader.metal StepsTrader/Experiments/DayObjects/DayObjectsRenderer.swift Steps4Tests/DayObjectChoreographyTests.swift Steps4Tests/DayObjectRenderFrameTests.swift Steps4.xcodeproj/project.pbxproj
git commit -m 'feat: render instanced choreographed figures'
```

---

### Task 8: Sleep focus and sharp grain post-processing

**Files:**
- Create: `StepsTrader/Metal/DayObjectsPostShader.metal`
- Modify: `StepsTrader/Experiments/DayObjects/DayObjectsRenderer.swift`
- Modify: `Steps4Tests/DayObjectRenderFrameTests.swift`
- Modify: `Steps4.xcodeproj/project.pbxproj`

**Interfaces:**
- Produces: `dayObjectsBlurHorizontal`, `dayObjectsBlurVertical`, `dayObjectsDisplayFragment`, and `DayObjectsPostUniforms`.
- Consumes: scene texture, ping-pong blur textures, blur radius/contrast/saturation, grain seed/intensity/phase.

- [ ] **Step 1: Add failing post-process tests**

Assert blur sample radius becomes zero at clarity 1, reaches the bounded kernel at clarity 0, grain intensity remains `0.035...0.075`, light palettes reduce grain, and Reduce Motion produces a constant grain phase.

- [ ] **Step 2: Run tests and verify RED**

Expected: light-palette grain reduction and frozen phase are not implemented.

- [ ] **Step 3: Implement separable blur and final grain**

Skip blur passes when radius is below `0.01`. Otherwise run horizontal and vertical Gaussian kernels over the full-size scene texture, with radius scaled from points to pixels and capped to the shader kernel. In the final display pass apply contrast/saturation, then sharp monochrome grain at no more than 12 Hz using soft-light-like luminance modulation. Sample grain after the blurred texture.

- [ ] **Step 4: Build and capture clarity 0/0.5/1 screenshots**

Expected: the complete gradient-and-figure scene defocuses monotonically while grain frequency stays sharp.

- [ ] **Step 5: Remove the obsolete fragment-loop shader and commit**

Delete `dayObjects(...)` from `DayObjectsShader.metal` once no renderer references it. Retain shared SDF helpers only if they are included without duplicate symbols; otherwise move them into `DayObjectsActorShader.metal`.

```bash
git add -- StepsTrader/Metal/DayObjectsPostShader.metal StepsTrader/Metal/DayObjectsShader.metal StepsTrader/Experiments/DayObjects/DayObjectsRenderer.swift Steps4Tests/DayObjectRenderFrameTests.swift Steps4.xcodeproj/project.pbxproj
git commit -m 'feat: add sleep focus and grain passes'
```

---

### Task 9: Lab controls and stable live insertion

**Files:**
- Modify: `StepsTrader/Experiments/DayObjects/DayObjectsLabView.swift`
- Modify: `StepsTrader/Experiments/DayObjects/DayObjectsView.swift`
- Create: `Steps4UITests/DayObjectsLabUITests.swift`
- Modify: `Steps4.xcodeproj/project.pbxproj`

**Interfaces:**
- Produces: stable fixture IDs `lab-event-0...39`, motion/focus controls, deterministic day switching, and accessibility identifiers.
- Consumes: `DayObjectsView(sceneInput:isAnimating:)` and renderer insertion tracking.

- [ ] **Step 1: Write a failing lab UI test**

```swift
final class DayObjectsLabUITests: XCTestCase {
    func testLabExposesChoreographyControlsAndAddsEventsInPlace() {
        let app = XCUIApplication()
        app.launchArguments = ["-uiLab", "dayObjects"]
        app.launch()
        XCTAssertTrue(app.sliders["dayObjects.happenings"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.sliders["dayObjects.motionEnergy"].exists)
        XCTAssertTrue(app.sliders["dayObjects.visualClarity"].exists)
        app.sliders["dayObjects.happenings"].adjust(toNormalizedSliderPosition: 0.5)
        XCTAssertTrue(app.otherElements["dayObjects.canvas"].exists)
    }
}
```

- [ ] **Step 2: Run the UI test and verify RED**

Expected: motion/focus identifiers do not exist.

- [ ] **Step 3: Implement the controls and stable fixture IDs**

Replace integer-only generation with `Array(0..<count).map { "lab-event-\($0)" }`. Add Motion and Focus sliders, preserve actor insertion timestamps in the renderer coordinator, keep the 3×5 grid static, and set toolbar color scheme from palette luminance so the lab title remains legible.

- [ ] **Step 4: Run UI and unit suites**

Expected: controls exist, adding events leaves the canvas alive, and all unit suites remain green.

- [ ] **Step 5: Commit Task 9**

```bash
git add -- StepsTrader/Experiments/DayObjects/DayObjectsLabView.swift StepsTrader/Experiments/DayObjects/DayObjectsView.swift Steps4UITests/DayObjectsLabUITests.swift Steps4.xcodeproj/project.pbxproj
git commit -m 'feat: expose day object choreography controls'
```

---

### Task 10: Visual regression, full verification, and physical-device profile

**Files:**
- Modify: `Steps4Tests/DayObjectCompositionTests.swift`
- Modify: `Steps4Tests/DayObjectSceneTests.swift`
- Modify: `Steps4Tests/DayObjectPaletteTests.swift`
- Modify: `Steps4Tests/DayObjectChoreographyTests.swift`
- Modify: `Steps4Tests/DayObjectRenderFrameTests.swift`
- Modify: `Steps4UITests/DayObjectsLabUITests.swift`

**Interfaces:**
- Consumes: all production interfaces from Tasks 1–9.
- Produces: final regression coverage and recorded performance evidence.

- [ ] **Step 1: Remove obsolete count-seeded tests and add final invariants**

Retain shape-family reachability. Replace `objects(happeningCount:)` tests with scene-ID stability, zero-actor background behavior, all-chapter reachability, minimum-visible-share sampling, and non-finite input clamping.

- [ ] **Step 2: Run the complete Day Object unit and UI test set**

```bash
xcodebuild test -project Steps4.xcodeproj -scheme Steps4 -destination 'platform=iOS Simulator,id=00349825-3076-4659-80E4-50B9CFF9090F' -only-testing:Steps4Tests/DayObjectCompositionTests -only-testing:Steps4Tests/DayObjectSceneTests -only-testing:Steps4Tests/DayObjectPaletteTests -only-testing:Steps4Tests/DayObjectChoreographyTests -only-testing:Steps4Tests/DayObjectRenderFrameTests -only-testing:Steps4UITests/DayObjectsLabUITests CODE_SIGNING_ALLOWED=NO
```

Expected: zero failures.

- [ ] **Step 3: Run the full project test suite**

```bash
xcodebuild test -project Steps4.xcodeproj -scheme Steps4 -destination 'platform=iOS Simulator,id=00349825-3076-4659-80E4-50B9CFF9090F' CODE_SIGNING_ALLOWED=NO
```

Expected: zero unexpected failures. Report entitlement warnings separately; do not describe warnings as test failures.

- [ ] **Step 4: Capture the visual acceptance matrix**

Capture fixed-day frames at 1, 10, 24, and 40 actors; clarity 0, 0.5, and 1; motion 0 and 1; phone portrait and tablet landscape. Compare for clipping, safe-zone intrusion, blank phases, palette coherence, stable insertion, and visible sharp grain.

- [ ] **Step 5: Profile on a physical supported iPhone**

Use Metal System Trace for a five-minute 40-actor run at 30 FPS. Record p95 GPU frame time, dropped frames, memory, and thermal state. Acceptance requires p95 below 25 ms and no sustained thermal escalation. If no physical device is available, mark production performance validation as pending and do not claim that criterion complete.

- [ ] **Step 6: Commit final test cleanup**

```bash
git add -- Steps4Tests/DayObjectCompositionTests.swift Steps4Tests/DayObjectSceneTests.swift Steps4Tests/DayObjectPaletteTests.swift Steps4Tests/DayObjectChoreographyTests.swift Steps4Tests/DayObjectRenderFrameTests.swift Steps4UITests/DayObjectsLabUITests.swift
git commit -m 'test: verify day object choreography'
```

---

## Final Review Checklist

- [ ] Re-read `docs/superpowers/specs/2026-08-20-day-objects-choreography-design.md` and map every acceptance criterion to a passing test or recorded manual check.
- [ ] Confirm `git diff --check` is clean for all files touched by the implementation.
- [ ] Confirm no unrelated pre-existing working-tree change was staged or committed.
- [ ] Confirm the old `total`-dependent field seed and one-fragment/all-actors loop are gone.
- [ ] Confirm shader enum values and Swift enum raw values match through explicit ABI tests.
- [ ] Confirm Reduce Motion and zero-event rendering remain functional.
- [ ] Report simulator tests and physical-device performance as separate evidence.
