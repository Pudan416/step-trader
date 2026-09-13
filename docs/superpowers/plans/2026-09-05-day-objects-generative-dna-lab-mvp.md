# Day Objects Generative DNA Lab MVP Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [x]`) syntax for tracking.

**Goal:** Replace the Lab's default eclectic Mixed atlas with a deterministic daily art direction that generates coherent but visibly different Day Objects scenes from circle-derived shapes and genuinely distinct material mechanisms.

**Architecture:** A pure Swift `DayObjectGenerativeDNA` layer schedules one scene-level fingerprint for each date, then resolves stable actor-local geometry and material mutations inside that envelope. The existing `DayObjectSceneRecipeV1` remains the renderer boundary and preserves the approved Editorial Field composition, motion, palette, and background work; Metal receives only resolved shape/material parameters and makes no random aesthetic decisions.

**Tech Stack:** Swift 6, SwiftUI, XCTest, existing `SceneRecipeV1`, Metal Shading Language, existing instanced Day Objects renderer.

**Spec:** `DesignReferences/DayObjects/system/01-generative-dna.md`

**Status (2026-09-05): COMPLETE.** Tasks 1–6 are implemented and committed. The final real-app Metal handoff is in `artifacts/day-objects-generative-dna-lab/final/`. The complete targeted suite was executed once; its only failures are three legacy perceptual signatures reproduced unchanged on baseline `5d7e1fee`, so the prohibited golden refresh was not performed.

## Global Constraints

- Day Objects remains available only inside Day Objects Lab; the main canvas and main Gallery are unchanged.
- Build on commit `d004f7e` and preserve the approved Editorial Field composition, background palettes, grain, slow motion, Reduce Motion, and stable insertion/removal identity.
- Maximum actor count remains exactly 10 and the renderer remains one instanced actor draw.
- One day has one primary family, one primary geometry region, one primary material mechanism, at most one supporting geometry region, and at most one compatible accent material.
- Roughly `70...90%` of actors use primary geometry and at least `75%` use the primary material; accent material never exceeds `25%`.
- Actor geometry, material, color role, and motion phase are deterministic functions of date plus stable event identity, never actor iteration order or current happening count.
- Shapes remain continuously circle-derived: circle, rounded superellipse, restrained soft star/lobes, and smooth compound circular body.
- Initial rendered material mechanisms are solid field, smooth radial field, layered membrane, boundary field, radial fiber field, and harmonic path field.
- Tensioned multi-actor contour networks and full constellation topology remain a later family because they require relationship-aware geometry rather than an actor-local fragment effect.
- One-color actors are spatially one hue. Multicolor surfaces use only broad smooth radial fields without hard central spots, linear/angular wedges, or muddy mixing.
- Visible point clouds, literal flowers, sharp stars, targets, pupils, and rapid local rotation remain forbidden.
- Preserve the existing `Mixed`/single-material modes only as explicit comparison tools; the default user-facing Lab mode is `Generative DNA`.
- Do not update perceptual goldens in this MVP.
- Run only one build or test command at a time. Use targeted tests during development and one complete Day Objects test pass plus one simulator build before handoff.
- Do not stage the existing untracked visual artifact directories unless a task explicitly names a newly produced final screenshot or recording.
- No new agents or critics are used for this Lab MVP.

## File Map

- Create `StepsTrader/Experiments/DayObjects/DayObjectGenerativeDNA.swift`: daily fingerprint, deterministic fourteen-day scheduler, compatibility catalog, and actor-local mutation resolution.
- Modify `Steps4.xcodeproj/project.pbxproj`: add `DayObjectGenerativeDNA.swift` to the existing Day Objects source group and Steps4 Sources phase.
- Modify `StepsTrader/Experiments/DayObjects/DayObjectEditorialPreview.swift`: add the default `Generative DNA` Lab mode while retaining the comparison atlas and focused material modes.
- Modify `StepsTrader/Experiments/DayObjects/DayObjectSceneRecipeV1.swift`: store the resolved art direction and actor shape, generate coherent actor materials, and keep approved composition/motion semantics.
- Modify `StepsTrader/Experiments/DayObjects/DayObjectComposition.swift`: extend the circle-derived renderer shape ABI from four to seven continuous carriers.
- Modify `StepsTrader/Experiments/DayObjects/DayObjectRenderFrame.swift`: upload the shape resolved in the recipe rather than forcing every Editorial actor to a sphere.
- Modify `StepsTrader/Experiments/DayObjects/DayObjectsLabView.swift`: select Generative DNA by default and expose its compact fingerprint in Lab diagnostics.
- Modify `StepsTrader/Experiments/DayObjects/DayObjectVisualLanguage.swift`: add stable GPU material raw values for radial fibers and harmonic paths without changing existing values `0...8`.
- Modify `StepsTrader/Metal/DayObjectsActorShader.metal`: render superellipse, soft-star, compound, radial-fiber, and harmonic-path phenotypes analytically.
- Modify `Steps4Tests/DayObjectSceneTests.swift`: scheduler, coherence budget, compatibility, stable identity, recipe integration, and shape ABI tests.
- Modify `Steps4Tests/DayObjectRenderFrameTests.swift`: resolved-shape upload and Metal pixel-behavior tests.
- Modify `Steps4UITests/DayObjectsLabUITests.swift`: default mode, next-day fingerprint, comparison-mode reachability, full-screen/tile, and Reduce Motion checks.

---

### Task 1: Deterministic daily art-direction scheduler

**Files:**
- Create: `StepsTrader/Experiments/DayObjects/DayObjectGenerativeDNA.swift`
- Modify: `Steps4.xcodeproj/project.pbxproj`
- Test: `Steps4Tests/DayObjectSceneTests.swift`

**Interfaces:**
- Produces `DayObjectGeometryRegion: UInt32` with `circle`, `superellipse`, `softStar`, and `compound`.
- Produces `DayObjectMaterialMechanism: UInt32` with `solid`, `smoothRadial`, `layeredMembrane`, `boundary`, `radialFibers`, and `harmonicPath`.
- Produces `DayObjectArtDirectionFingerprint` containing family, composition, geometry, material, palette/depth/edge/motion moods.
- Produces `DayObjectArtDirectionScheduler.make(dayKey:identity:) -> DayObjectArtDirection`.
- Produces `DayObjectArtDirection.resolution(eventID:) -> DayObjectActorDNAResolution`.

- [x] **Step 1: Write failing scheduler tests**

Add focused tests with these assertions:

```swift
func testGenerativeDNASchedulesCoherentVariedReproducibleDays() {
    let days = (1...28).map {
        DayObjectArtDirectionScheduler.make(
            dayKey: String(format: "2026-09-%02d", $0),
            identity: "day-objects-lab"
        )
    }
    XCTAssertEqual(days, (1...28).map {
        DayObjectArtDirectionScheduler.make(
            dayKey: String(format: "2026-09-%02d", $0),
            identity: "day-objects-lab"
        )
    })
    for pair in zip(days, days.dropFirst()) {
        XCTAssertNotEqual(pair.0.fingerprint.primaryFamily, pair.1.fingerprint.primaryFamily)
        XCTAssertGreaterThanOrEqual(pair.0.fingerprint.distance(to: pair.1.fingerprint), 2)
    }
    for index in 0..<(days.count - 7) {
        XCTAssertNotEqual(
            days[index].fingerprint.coreCombination,
            days[index + 7].fingerprint.coreCombination
        )
    }
}

func testActorDNAResolutionIsIndependentOfCountAndOrder() {
    let direction = DayObjectArtDirectionScheduler.make(
        dayKey: "2026-09-05",
        identity: "day-objects-lab"
    )
    let ids = (0..<10).map { "lab-event-\($0)" }
    let forward = Dictionary(uniqueKeysWithValues: ids.map { ($0, direction.resolution(eventID: $0)) })
    let reverse = Dictionary(uniqueKeysWithValues: ids.reversed().map { ($0, direction.resolution(eventID: $0)) })
    XCTAssertEqual(forward, reverse)
}
```

- [x] **Step 2: Run the scheduler tests and verify RED**

Run one command:

```bash
xcodebuild test -project Steps4.xcodeproj -scheme Steps4 \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=latest' \
  -only-testing:Steps4Tests/DayObjectSceneTests/testGenerativeDNASchedulesCoherentVariedReproducibleDays \
  -only-testing:Steps4Tests/DayObjectSceneTests/testActorDNAResolutionIsIndependentOfCountAndOrder \
  CODE_SIGNING_ALLOWED=NO
```

Expected: compilation fails because the DNA types do not exist.

- [x] **Step 3: Implement the immutable DNA types and compatibility table**

Create the following public-to-module shape, keeping stored values concrete and `Equatable`:

```swift
enum DayObjectGeometryRegion: UInt32, CaseIterable, Equatable {
    case circle, superellipse, softStar, compound
}

enum DayObjectMaterialMechanism: UInt32, CaseIterable, Equatable {
    case solid, smoothRadial, layeredMembrane, boundary, radialFibers, harmonicPath
}

struct DayObjectActorDNAResolution: Equatable {
    let geometry: DayObjectGeometryRegion
    let material: DayObjectMaterialMechanism
    let isGeometryAccent: Bool
    let isMaterialAccent: Bool
}

struct DayObjectArtDirection: Equatable {
    let fingerprint: DayObjectArtDirectionFingerprint
    let primaryGeometry: DayObjectGeometryRegion
    let supportingGeometry: DayObjectGeometryRegion?
    let primaryMaterial: DayObjectMaterialMechanism
    let accentMaterial: DayObjectMaterialMechanism?
    let geometryAccentThreshold: Double
    let materialAccentThreshold: Double

    func resolution(eventID: String) -> DayObjectActorDNAResolution
}
```

Compatibility is an allowlist. `smoothRadial`, `solid`, `layeredMembrane`, and `boundary` support all four carriers. `radialFibers` supports circle, superellipse, and softStar. `harmonicPath` supports circle and softStar. A rejected pairing resamples only the supporting geometry or accent material using its own deterministic domain and falls back to the primary pairing after eight attempts.

- [x] **Step 4: Implement fourteen-day deterministic scheduling**

For ISO dates, derive a UTC day ordinal. Resolve complete fourteen-day epochs sequentially from the epoch boundary. Seed each candidate with the stable FNV-1a hash of `identity`, epoch index, day slot, attempt, and an explicit domain string. Enforce:

```swift
candidate.primaryFamily != previous.primaryFamily
candidate.fingerprint.distance(to: previous.fingerprint) >= 2
recentSeven.allSatisfy { $0.coreCombination != candidate.coreCombination }
```

For non-ISO fixture keys, derive a deterministic ordinal from the full key instead of returning a constant. Include the previous epoch's final seven fingerprints while resolving a boundary. Do not read or persist mutable history.

- [x] **Step 5: Run scheduler tests and verify GREEN**

Run the command from Step 2. Expected: both tests pass and no other test target runs.

- [x] **Step 6: Commit scheduler only**

```bash
git add -- StepsTrader/Experiments/DayObjects/DayObjectGenerativeDNA.swift \
  Steps4Tests/DayObjectSceneTests.swift Steps4.xcodeproj/project.pbxproj
git commit -m "feat: schedule Day Objects art direction"
```

### Task 2: Coherent recipe generation and stable actor identity

**Files:**
- Modify: `StepsTrader/Experiments/DayObjects/DayObjectEditorialPreview.swift`
- Modify: `StepsTrader/Experiments/DayObjects/DayObjectSceneRecipeV1.swift`
- Modify: `StepsTrader/Experiments/DayObjects/DayObjectsLabView.swift`
- Test: `Steps4Tests/DayObjectSceneTests.swift`

**Interfaces:**
- Consumes `DayObjectArtDirectionScheduler.make(dayKey:identity:)` from Task 1.
- Adds `DayObjectEditorialLabMaterialMode.generativeDNA` and keeps `.mixed` as an explicitly named comparison atlas.
- Adds `artDirection: DayObjectArtDirection?` to `DayObjectSceneRecipeV1`.
- Adds `shape: DayObjectShape` to `DayObjectSceneRecipeActorV1`.
- Produces `DayObjectSceneRecipeV1.artDirectionSummary: String` for Lab diagnostics.

- [x] **Step 1: Replace the eclectic default expectation with failing coherence tests**

Keep the existing test proving `.mixed` exposes the six comparison formats, but rename it to state that it is an atlas. Add:

```swift
func testGenerativeDNALabModeUsesOneDailyEnvelope() throws {
    let scene = DayObjectScene.make(input: editorialLabInput(
        dayKey: "2026-09-05",
        eventIDs: (0..<10).map { "lab-event-\($0)" },
        materialMode: .generativeDNA
    ))
    let recipe = try XCTUnwrap(scene.sceneRecipeV1)
    let direction = try XCTUnwrap(recipe.artDirection)
    let materialCounts = Dictionary(grouping: recipe.actors, by: { $0.material.mechanism })
        .mapValues(\.count)
    XCTAssertGreaterThanOrEqual(materialCounts[direction.primaryMaterial, default: 0], 8)
    XCTAssertLessThanOrEqual(recipe.actors.filter { $0.material.mechanism != direction.primaryMaterial }.count, 2)
    XCTAssertTrue(recipe.actors.allSatisfy {
        direction.supports(geometry: $0.geometryRegion, material: $0.material.mechanism)
    })
}
```

Add an insertion/removal test comparing `shape`, `geometryRegion`, material mechanism, colors, fields, and motion for retained event IDs at counts `3`, `7`, and `10`.

- [x] **Step 2: Run the new recipe tests and verify RED**

Run only the two new `DayObjectSceneTests`. Expected: missing `.generativeDNA`, recipe art direction, and material mechanism.

- [x] **Step 3: Add Generative DNA as the Lab default without deleting comparison tools**

Add `.generativeDNA` before `.mixed`, title them `Generative DNA` and `All formats (comparison)`, and initialize:

```swift
@State private var editorialMaterialMode: DayObjectEditorialLabMaterialMode = .generativeDNA
```

The material menu keeps solid, translucent solid, mist, wide gradient, soft outline, and hairline outline for focused inspection.

- [x] **Step 4: Resolve recipe actors from the daily envelope**

Extend `DayObjectEditorialMaterialV1` with `mechanism: DayObjectMaterialMechanism`. Existing constructors assign the corresponding mechanism without changing their pixels. In Generative DNA mode:

1. schedule one art direction from the input `dayKey` and `identity`;
2. resolve each event ID independently;
3. reuse the approved `CompositionPlanner` output and depth-dependent blur;
4. assign the resolved carrier and compatible material builder;
5. keep colors inside the already selected object palettes;
6. store the complete art direction on the recipe.

The accent thresholds are deterministic in `0.10...0.25`; at ten actors no more than two receive the accent material. At one actor always use primary geometry and material. At two or three actors use an accent only if its stable threshold selects one.

- [x] **Step 5: Expose the fingerprint in Lab diagnostics**

For a generative recipe, show:

```text
DNA <family> · <primary geometry> · <primary material> [+ <accent>] · <composition>
```

Keep existing palette and motion diagnostics after this line. Do not add this UI outside `DayObjectsLabView`.

- [x] **Step 6: Run recipe tests and the existing Editorial Lab scene tests**

```bash
xcodebuild test -project Steps4.xcodeproj -scheme Steps4 \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=latest' \
  -only-testing:Steps4Tests/DayObjectSceneTests \
  CODE_SIGNING_ALLOWED=NO
```

Expected: all `DayObjectSceneTests` pass; Mixed remains reachable but is no longer the default.

- [x] **Step 7: Commit recipe integration**

```bash
git add -- StepsTrader/Experiments/DayObjects/DayObjectEditorialPreview.swift \
  StepsTrader/Experiments/DayObjects/DayObjectSceneRecipeV1.swift \
  StepsTrader/Experiments/DayObjects/DayObjectsLabView.swift \
  Steps4Tests/DayObjectSceneTests.swift
git commit -m "feat: generate coherent daily Day Objects recipes"
```

### Task 3: Circle-derived carrier geometry in Metal

**Files:**
- Modify: `StepsTrader/Experiments/DayObjects/DayObjectComposition.swift`
- Modify: `StepsTrader/Experiments/DayObjects/DayObjectSceneRecipeV1.swift`
- Modify: `StepsTrader/Experiments/DayObjects/DayObjectRenderFrame.swift`
- Modify: `StepsTrader/Metal/DayObjectsActorShader.metal`
- Test: `Steps4Tests/DayObjectSceneTests.swift`
- Test: `Steps4Tests/DayObjectRenderFrameTests.swift`

**Interfaces:**
- Adds `DayObjectShape.superellipse = 4`, `.softStar = 5`, and `.compound = 6` while preserving existing raw GPU values `0...3`.
- Adds `DayObjectGeometryRegion.shape(actorSeed:) -> DayObjectShape`.
- Makes Editorial frame upload use `recipeActor.shape.numericValue`.

- [x] **Step 1: Write failing ABI and recipe-upload tests**

```swift
func testExpandedCircleDerivedShapeNumericValuesAreStable() {
    XCTAssertEqual(DayObjectShape.sphere.numericValue, 0)
    XCTAssertEqual(DayObjectShape.ellipse.numericValue, 1)
    XCTAssertEqual(DayObjectShape.lens.numericValue, 2)
    XCTAssertEqual(DayObjectShape.softBlob.numericValue, 3)
    XCTAssertEqual(DayObjectShape.superellipse.numericValue, 4)
    XCTAssertEqual(DayObjectShape.softStar.numericValue, 5)
    XCTAssertEqual(DayObjectShape.compound.numericValue, 6)
}
```

Build one generative recipe for each resolved geometry region and assert the corresponding `DayObjectGPUActor.shape` survives `DayObjectRenderFrame.make`.

- [x] **Step 2: Run the two focused tests and verify RED**

Expected: the three new shape cases do not exist and Editorial upload still forces `.sphere`.

- [x] **Step 3: Add analytic circle-derived signed-distance carriers**

Preserve shader cases `0...3`. Add:

```metal
case 4: { // rounded superellipse
    const float exponent = 3.2;
    const float superRadius = pow(
        pow(abs(ellipsePoint.x), exponent) + pow(abs(ellipsePoint.y), exponent),
        1.0 / exponent
    );
    return superRadius - 1.0;
}
case 5: { // restrained soft radial star
    const float starRadius = 1.0 + 0.105 * cos(5.0 * angle + radialVariation * 0.7);
    return radius - starRadius;
}
case 6: { // smooth compound circular body
    const float lobeRadius = 1.0
        + 0.075 * cos(2.0 * angle + 0.45)
        + 0.045 * cos(4.0 * angle - 0.30);
    return radius - lobeRadius;
}
```

Use bounded amplitudes so the star remains rounded and abstract. Increase the vertex-quad radial reach for cases `5` and `6` so no lobe is clipped.

- [x] **Step 4: Add Metal pixel tests for carrier distinction and safe bounds**

Render all seven shape values at `192 × 160`. Assert each has a readable center, no corner leakage, at least `2,500` nonzero pixels, and a silhouette-area difference from the circle for cases `4...6`. For soft star, sample the five valleys and tips to verify rounded continuous lobes instead of sharp spikes.

- [x] **Step 5: Run focused scene and Metal shape tests**

Run only the new ABI/upload tests and `testActorShaderRendersOnlyCircleDerivedOrbFamilies`, expanded to `0...6`. Expected: PASS.

- [x] **Step 6: Commit carrier geometry**

```bash
git add -- StepsTrader/Experiments/DayObjects/DayObjectComposition.swift \
  StepsTrader/Experiments/DayObjects/DayObjectSceneRecipeV1.swift \
  StepsTrader/Experiments/DayObjects/DayObjectRenderFrame.swift \
  StepsTrader/Metal/DayObjectsActorShader.metal \
  Steps4Tests/DayObjectSceneTests.swift Steps4Tests/DayObjectRenderFrameTests.swift
git commit -m "feat: render circle-derived Day Objects carriers"
```

### Task 4: Distinct surface, membrane, boundary, fiber, and path materials

**Files:**
- Modify: `StepsTrader/Experiments/DayObjects/DayObjectVisualLanguage.swift`
- Modify: `StepsTrader/Experiments/DayObjects/DayObjectSceneRecipeV1.swift`
- Modify: `StepsTrader/Experiments/DayObjects/DayObjectRenderFrame.swift`
- Modify: `StepsTrader/Metal/DayObjectsActorShader.metal`
- Test: `Steps4Tests/DayObjectSceneTests.swift`
- Test: `Steps4Tests/DayObjectRenderFrameTests.swift`

**Interfaces:**
- Adds stable GPU material cases `radialFibers = 9` and `harmonicPath = 10`; values `0...8` stay unchanged.
- Maps DNA mechanisms to GPU constructions: `solid -> solid`, `smoothRadial -> gradient`, `layeredMembrane -> glass`, `boundary -> outline`, `radialFibers -> radialFibers`, `harmonicPath -> harmonicPath`.
- Uses existing `recipe1` parameters for structural density, line width, phase/eccentricity, and opening; GPU struct stride remains 208 bytes.

- [x] **Step 1: Write failing material reachability and integrity tests**

Across 56 scheduled dates, require every `DayObjectMaterialMechanism` to appear as a primary mechanism. For each ten-actor recipe require one or two material mechanisms total, primary share at least eight actors, and every geometry/material pair accepted by the compatibility table. Assert a solid material has one color and no radial fields.

- [x] **Step 2: Write failing Metal behavior tests**

Render the same circle carrier with each mechanism and assert:

- solid interior has near-constant chroma and no hidden central brightness ramp;
- smooth radial has broad regional color difference without a small high-contrast core;
- layered membrane transmits sampled background and retains a chromatic boundary;
- boundary has transparent center and continuous perimeter;
- radial fibers contain connected center-to-boundary line coverage with visible gaps between fibers;
- harmonic path has continuous line coverage, an intentional broad opening, and no disconnected points.

- [x] **Step 3: Generate material parameters from actor identity**

For broad radial fields use two or three centers at or beyond `0.55` normalized distance, radius `1.20...1.75`, softness `0.78...1.0`, and clean palette-role colors. For membrane use base opacity `0.50...0.72`, thin chromatic edge, and two broad fields. Boundary width is `0.004...0.065` depending on scene edge mood. Fiber count is `56...104` with screen-derivative antialiasing and per-line opacity coupled inversely to density. Harmonic path uses lobe frequency `2...7`, amplitude `0.04...0.16`, opening `0.08...0.28`, and at most three phase-related passes.

- [x] **Step 4: Implement radial-fiber and harmonic-path fragment coverage**

Compute analytic line distance with `fwidth` rather than discrete points. Multiply structural coverage by the resolved carrier coverage, preserve premultiplied alpha, and suppress trail/merge haze for structural materials. Keep internal phase fixed under Reduce Motion; normal motion may translate the complete actor but must not rotate the local pattern rapidly.

- [x] **Step 5: Run focused material tests**

Run the new scene material tests and new Metal pixel tests only. Expected: all six mechanisms are reachable and visibly non-equivalent.

- [x] **Step 6: Commit material mechanisms**

```bash
git add -- StepsTrader/Experiments/DayObjects/DayObjectVisualLanguage.swift \
  StepsTrader/Experiments/DayObjects/DayObjectSceneRecipeV1.swift \
  StepsTrader/Experiments/DayObjects/DayObjectRenderFrame.swift \
  StepsTrader/Metal/DayObjectsActorShader.metal \
  Steps4Tests/DayObjectSceneTests.swift Steps4Tests/DayObjectRenderFrameTests.swift
git commit -m "feat: render generative Day Objects materials"
```

### Task 5: Lab controls and behavioral verification

**Files:**
- Modify: `StepsTrader/Experiments/DayObjects/DayObjectsLabView.swift`
- Modify: `Steps4UITests/DayObjectsLabUITests.swift`
- Test: `Steps4Tests/DayObjectSceneTests.swift`
- Test: `Steps4Tests/DayObjectRenderFrameTests.swift`

**Interfaces:**
- Consumes the Generative DNA recipe and diagnostic summary from Tasks 1–4.
- Keeps full-screen, calendar-tile, grid, happening count, motion, focus, low-sleep, and Reduce Motion controls.
- Keeps All Formats comparison and focused material modes accessible only in Lab.

- [x] **Step 1: Add failing UI tests**

Launch Day Objects Lab and assert the material picker defaults to `Generative DNA`. Record the `dayObjects.language` value, tap `dayObjects.nextDay`, and assert the fingerprint changes while still beginning with `DNA`. Switch to `All formats (comparison)` and assert it remains reachable. Toggle tile and Reduce Motion and assert their accessibility values change without changing the fingerprint.

- [x] **Step 2: Run only the new UI test and verify RED**

Expected: default mode or fingerprint assertions fail before final Lab wiring.

- [x] **Step 3: Complete Lab-only wiring**

Ensure the grid renders fifteen different scheduled art directions, the single view advances one date, and manual comparison mode never becomes the default. Changing happening count, low sleep, focus, motion, Reduce Motion, or full/tile presentation must not change the art-direction fingerprint for the same day.

- [x] **Step 4: Run the complete Day Objects targeted suite once**

```bash
xcodebuild test -project Steps4.xcodeproj -scheme Steps4 \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=latest' \
  -only-testing:Steps4Tests/DayObjectSceneTests \
  -only-testing:Steps4Tests/DayObjectPaletteTests \
  -only-testing:Steps4Tests/DayObjectChoreographyTests \
  -only-testing:Steps4Tests/DayObjectRenderFrameTests \
  -only-testing:Steps4UITests/DayObjectsLabUITests \
  CODE_SIGNING_ALLOWED=NO
```

Expected: PASS with no perceptual golden changes.

- [x] **Step 5: Commit Lab behavior**

```bash
git add -- StepsTrader/Experiments/DayObjects/DayObjectsLabView.swift \
  Steps4UITests/DayObjectsLabUITests.swift \
  Steps4Tests/DayObjectSceneTests.swift Steps4Tests/DayObjectRenderFrameTests.swift
git commit -m "feat: expose generative DNA in Day Objects Lab"
```

### Task 6: Simulator visual handoff

**Files:**
- Create: `artifacts/day-objects-generative-dna-lab/final/contact-sheet.png`
- Create: `artifacts/day-objects-generative-dna-lab/final/reduce-motion.png`
- Create: `artifacts/day-objects-generative-dna-lab/final/motion.mp4`
- Create: `artifacts/day-objects-generative-dna-lab/final/README.md`

**Interfaces:**
- Produces one user-reviewable package from the real app renderer, not a separate HTML or CoreGraphics approximation.

- [x] **Step 1: Build the Simulator app once**

```bash
xcodebuild build -project Steps4.xcodeproj -scheme Steps4 \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=latest' \
  CODE_SIGNING_ALLOWED=NO
```

Expected: `** BUILD SUCCEEDED **`.

- [x] **Step 2: Capture representative real-app scenes**

Capture at least six different dates in Generative DNA mode, all with ten happenings. The contact sheet must include all four carrier regions across the set, all six material mechanisms across the set, at least one full-screen view, one calendar tile, one light background, one dark background, and one low-sleep state. Do not tune seeds after seeing output; advance dates sequentially from the deterministic Lab control.

- [x] **Step 3: Capture motion and Reduce Motion**

Record one `8...12` second normal-motion clip showing slow whole-object drift and depth parallax. Capture the same date with Reduce Motion at two elapsed times and verify identical actor position, depth, shape, material, and local phase.

- [x] **Step 4: Inspect the visual package**

Reject and fix only implementation defects: clipped carrier lobes, hard gradient cores, dirty mixing, disconnected fiber dots, moire, invisible outlines, incorrect alpha, identity changes, or fast local rotation. Do not change the approved composition merely to improve one sampled date.

- [x] **Step 5: Document and commit the final handoff artifacts**

`README.md` records source commit, simulator/device, OS, dates, happening count, background, sleep, motion, Reduce Motion, and exact capture commands.

```bash
git add -- artifacts/day-objects-generative-dna-lab/final
git commit -m "docs: capture generative DNA Lab MVP"
```

## Release-hardening backlog

The following remain explicitly outside this Lab MVP and require separate approval: 24-fixture held-out corpus, repeated blind critics, exhaustive state combinations, sandbox/Metal blind parity certification, physical-device performance gate, production Gallery integration, and perceptual golden updates.
