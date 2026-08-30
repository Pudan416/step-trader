# Day Objects Editorial Field Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build and visually approve a deterministic Editorial Field sandbox for one to ten Day Objects, then transfer the frozen `SceneRecipe` semantics into the existing single-pass Metal Lab renderer without changing the application's main canvas.

**Architecture:** A zero-dependency macOS Swift Package generates seed manifests, immutable `SceneRecipe` JSON, neutral/material/motion PNG and GIF evidence, contact sheets, metrics, and SHA-256 package manifests without importing application or Metal code. A Visual Director coordinates isolated composition artists and fresh critics through composition, material, motion, held-out, Metal-parity, and integration gates. Only after the sandbox gates pass does the app model decode the same bounded recipe semantics and upload them to the existing instanced Metal renderer.

**Tech Stack:** Swift 6, Swift Package Manager, Foundation, CryptoKit, CoreGraphics, ImageIO, XCTest/Swift Testing, existing SwiftUI Lab, XCTest/UI XCTest, Metal Shading Language.

**Spec:** `docs/superpowers/specs/2026-08-30-day-objects-editorial-field-design.md`

## Global Constraints

- Day Objects remains Lab-only and must not replace or modify the restored main application canvas.
- Maximum actor count is exactly 10; one instanced actor draw remains the production target.
- Visible seeds derive from immutable spec commit `8a8539a77ce704fcc688ebe8cb98d78e2a0f80dd`, public nonce `day-objects-editorial-field-visible-v1`, suite name, and zero-based fixture index using SHA-256; the first 64 bits are interpreted as an unsigned big-endian day seed.
- The visible breadth corpus has exactly 12 fixtures: two each for 1, 2, 3, 5, 7, and 10 happenings; stress has at least 48 additional seeds; continuity uses `1 -> 2 -> 3 -> 5 -> 7 -> 10 -> 5` with retained canonical identities.
- Evidence covers full screen at `393 x 852` points at `3x` and the production calendar-tile crop, plus light, dark, warm, cool, saturated, and low-contrast backgrounds; normal and low sleep; low and normal steps; Reduce Motion; insertion and removal.
- Static composition uses neutral distinguishable materials until composition receives two independent PASS verdicts on the same evidence-package hash.
- Material work uses only frozen approved layouts. A solid actor is spatially constant. Multicolor actors use no more than three broad overlapping analytic radial fields and no linear, angular, conic, pyramidal, Voronoi-like, or hard ownership boundary.
- Motion begins only after composition and materials separately receive two independent PASS verdicts. It is slow, continuous, individually phased, depth-aware, and free of dominant local spinning or orbiting.
- A very large foreground actor is more locally defocused than the sharpest middle-plane actor; the global sleep post-process preserves that relative hierarchy.
- No piece passes on builder confidence, automated metrics, a hand-picked seed, or a majority vote. Every revision gets a fresh critic, and both blind critics must PASS the same frozen package.
- Critics receive only the contract, tagged references, applicable seed manifest, artifact package, and render instructions, and return exactly `VERDICT`, `EVIDENCE`, `LARGEST GAP`, and `NEXT ACCEPTANCE TEST`.
- Only the critic's single largest gap and next observable test return to an artist. Three repetitions of the same gap require a strategy change, never a waiver.
- No Metal transfer occurs before composition, material, motion, and a fresh hidden held-out corpus have separately passed.
- No perceptual golden is changed unless its replacement render was visually inspected and accepted through the required gate.
- Preserve all pre-existing dirty files. Each task stages only the paths named in that task and ends in a thematic commit.

## File Map

- Create `Tools/DayObjectsEditorialField/Package.swift`: sandbox package and CLI products.
- Create `Tools/DayObjectsEditorialField/Sources/EditorialFieldCore/SeedDerivation.swift`: SHA-256 seed derivation, canonical UUIDs, collision resolution, and fixed condition tables.
- Create `Tools/DayObjectsEditorialField/Sources/EditorialFieldCore/CorpusManifest.swift`: Codable visible/held-out manifest schema and deterministic fixture construction.
- Create `Tools/DayObjectsEditorialField/Sources/EditorialFieldCore/SceneRecipe.swift`: renderer-independent grammar, actor, material, radial-field, and motion recipe types.
- Create `Tools/DayObjectsEditorialField/Sources/EditorialFieldCore/EditorialGrammar.swift`: six grammar catalog and deterministic weights.
- Create `Tools/DayObjectsEditorialField/Sources/EditorialFieldCore/CompositionPlanner.swift`: persistent actor-local candidate streams and incremental scoring.
- Create `Tools/DayObjectsEditorialField/Sources/EditorialFieldCore/MaterialDNA.swift`: one daily family, related mutations, one-to-three colors, and radial descriptors.
- Create `Tools/DayObjectsEditorialField/Sources/EditorialFieldCore/MotionField.swift`: shared low-frequency flow, stable per-actor phase/parallax, and continuous depth/breathing.
- Create `Tools/DayObjectsEditorialField/Sources/EditorialFieldRender/NeutralRenderer.swift`: neutral composition PNG plus geometry/debug overlays.
- Create `Tools/DayObjectsEditorialField/Sources/EditorialFieldRender/MaterialRenderer.swift`: CoreGraphics radial/material rendering and color sampling.
- Create `Tools/DayObjectsEditorialField/Sources/EditorialFieldRender/MotionRenderer.swift`: four phase stills, path/depth traces, and 8–12 second GIF evidence.
- Create `Tools/DayObjectsEditorialField/Sources/EditorialFieldEvidence/EvidencePackage.swift`: artifact hashing, contact sheets, toolchain metadata, and immutable package hash.
- Create `Tools/DayObjectsEditorialField/Sources/editorial-field-corpus/main.swift`: visible and held-out corpus CLI.
- Create `Tools/DayObjectsEditorialField/Sources/editorial-field-render/main.swift`: composition/material/motion evidence CLI.
- Create `Tools/DayObjectsEditorialField/Tests/EditorialFieldCoreTests/*.swift`: deterministic, continuity, distribution, material, and motion tests.
- Create `Tools/DayObjectsEditorialField/Tests/EditorialFieldRenderTests/*.swift`: pixel-sampling and artifact-integrity tests.
- Create `Tools/DayObjectsEditorialField/Manifests/visible-v1.json`: committed generated visible corpus.
- Create `Tools/DayObjectsEditorialField/README.md`: exact generation, render, review, and package-verification commands.
- Create `artifacts/day-objects-editorial-field/director/decision-ledger.md`: director-owned package hashes and gate state.
- Create `artifacts/day-objects-editorial-field/<piece>/<round>/`: immutable manifests, renders, contact sheets, metrics, critic verdicts, and package hashes.
- Create `StepsTrader/Experiments/DayObjects/DayObjectSceneRecipe.swift`: production mirror/adapter for the frozen sandbox recipe.
- Modify `StepsTrader/Experiments/DayObjects/DayObjectComposition.swift`: replace rigid preset placement with grammar/planner semantics after sandbox PASS.
- Modify `StepsTrader/Experiments/DayObjects/DayObjectTypes.swift`: store stable recipe fields required by frame generation.
- Modify `StepsTrader/Experiments/DayObjects/DayObjectScene.swift`: canonical admission and immutable recipe assembly.
- Modify `StepsTrader/Experiments/DayObjects/DayObjectVisualLanguage.swift`: frozen material DNA and radial blend descriptors.
- Modify `StepsTrader/Experiments/DayObjects/DayObjectMotionPlan.swift`: shared flow plus per-actor phase/parallax from the recipe.
- Modify `StepsTrader/Experiments/DayObjects/DayObjectRenderFrame.swift`: bounded Metal upload for recipe fields and local focus.
- Modify `StepsTrader/Metal/DayObjectsActorShader.metal`: flat solid path and up to three analytic radial color fields.
- Modify `StepsTrader/Experiments/DayObjects/DayObjectsLabView.swift`: Lab diagnostics/fixture controls only.
- Modify `Steps4Tests/DayObjectSceneTests.swift`, `DayObjectChoreographyTests.swift`, `DayObjectPaletteTests.swift`, and `DayObjectRenderFrameTests.swift`: transfer and regression gates.
- Modify `Steps4UITests/DayObjectsLabUITests.swift`: Lab-only reachability, count, insertion/removal, Reduce Motion, and relaunch coverage.

---

### Task 1: Reproducible visible seed corpus

**Files:**
- Create: `Tools/DayObjectsEditorialField/Package.swift`
- Create: `Tools/DayObjectsEditorialField/Sources/EditorialFieldCore/SeedDerivation.swift`
- Create: `Tools/DayObjectsEditorialField/Sources/EditorialFieldCore/CorpusManifest.swift`
- Create: `Tools/DayObjectsEditorialField/Sources/editorial-field-corpus/main.swift`
- Create: `Tools/DayObjectsEditorialField/Tests/EditorialFieldCoreTests/CorpusManifestTests.swift`
- Create: `Tools/DayObjectsEditorialField/Manifests/visible-v1.json`
- Create: `Tools/DayObjectsEditorialField/README.md`

**Interfaces:**
- Produces: `SeedDerivation.daySeed(commit:nonce:suite:index:collision:) -> UInt64`.
- Produces: `CorpusManifest.visibleV1() -> CorpusManifest` and canonical JSON encoding with sorted keys.
- Produces CLI: `swift run editorial-field-corpus visible --output Manifests/visible-v1.json` and `verify --manifest <path>`.
- Consumes: fixed spec commit and public nonce from Global Constraints.

- [ ] **Step 1: Write failing seed and table tests**

Create tests that independently build the digest input with unit-separator delimiters, validate the first 64-bit big-endian extraction, require exact actor-count order, require four phases, and assert byte-for-byte regeneration:

```swift
@Test func visibleManifestIsByteReproducible() throws {
    let first = try CorpusManifest.visibleV1().canonicalJSON()
    let second = try CorpusManifest.visibleV1().canonicalJSON()
    #expect(first == second)
    #expect(CorpusManifest.visibleV1().breadth.map(\.actorCount) ==
        [1, 1, 2, 2, 3, 3, 5, 5, 7, 7, 10, 10])
    #expect(CorpusManifest.visibleV1().phases == [0, 0.25, 0.5, 0.75])
    #expect(Set(CorpusManifest.visibleV1().breadth.map(\.background)) ==
        Set(BackgroundCondition.allCases))
}
```

- [ ] **Step 2: Run the tests and verify RED**

Run:

```bash
swift test --package-path Tools/DayObjectsEditorialField --filter CorpusManifestTests
```

Expected: compilation fails because `SeedDerivation` and `CorpusManifest` do not exist.

- [ ] **Step 3: Implement exact seed derivation and fixed fixture tables**

Use the canonical input bytes:

```swift
let input = [commit, nonce, suite, String(index), String(collision)]
    .joined(separator: "\u{001F}")
let digest = SHA256.hash(data: Data(input.utf8))
let seed = digest.prefix(8).reduce(UInt64.zero) { ($0 << 8) | UInt64($1) }
```

Define ten immutable UUID strings, two breadth fixtures per required actor count, six background cases (`light`, `dark`, `warm`, `cool`, `saturated`, `lowContrast`), normal/low sleep, low/normal steps, Reduce Motion assignments, the seven-stage continuity count sequence, and exactly 48 stress fixtures. Resolve a duplicate seed by incrementing `collision` and rehashing the same tuple.

- [ ] **Step 4: Generate, verify, and inspect the committed manifest**

Run:

```bash
swift run --package-path Tools/DayObjectsEditorialField editorial-field-corpus visible --output Tools/DayObjectsEditorialField/Manifests/visible-v1.json
swift run --package-path Tools/DayObjectsEditorialField editorial-field-corpus verify --manifest Tools/DayObjectsEditorialField/Manifests/visible-v1.json
git diff --check -- Tools/DayObjectsEditorialField
```

Expected: verification prints the manifest SHA-256, 12 breadth fixtures, 7 continuity stages, 48 stress fixtures, and zero duplicate seeds.

- [ ] **Step 5: Commit only corpus infrastructure**

```bash
git add -- Tools/DayObjectsEditorialField
git commit -m "test: add editorial field seed corpus"
```

### Task 2: Renderer-independent `SceneRecipe` and neutral composition planner

**Files:**
- Create: `Tools/DayObjectsEditorialField/Sources/EditorialFieldCore/SceneRecipe.swift`
- Create: `Tools/DayObjectsEditorialField/Sources/EditorialFieldCore/EditorialGrammar.swift`
- Create: `Tools/DayObjectsEditorialField/Sources/EditorialFieldCore/CompositionPlanner.swift`
- Create: `Tools/DayObjectsEditorialField/Tests/EditorialFieldCoreTests/CompositionPlannerTests.swift`

**Interfaces:**
- Produces: `EditorialGrammar` with `layeredOverlap`, `openField`, `croppedForeground`, `depthScatter`, `transparentPrint`, and `equalScaleStudy`.
- Produces: `ActorCompositionRecipe(eventID:position:diameter:depth:localBlur:cropAllowance:drawOrder:)`.
- Produces: `CompositionPlanner.make(daySeed:eventIDs:viewport:) -> CompositionRecipe` with actor-local persistent candidate streams.
- Consumes: canonical IDs and day seed from `CorpusManifest`.

- [ ] **Step 1: Write failing deterministic and visual-guardrail tests**

Add tests for reorder/insertion/removal stability, `3:1` scale ratio at four or more actors outside equal scale, all vertical thirds at six or more actors for distributed grammars, cropped foreground plus readable counterweight, and bounded ring/grid/row/cluster penalties:

```swift
@Test func retainedActorsDoNotReroll() {
    let ids = CorpusManifest.canonicalEventIDs
    let full = CompositionPlanner.make(daySeed: 77, eventIDs: ids, viewport: .phone)
    let subset = CompositionPlanner.make(daySeed: 77, eventIDs: Array(ids.prefix(5)), viewport: .phone)
    for id in ids.prefix(5) {
        #expect(full.actor(id) == subset.actor(id))
    }
}

@Test func broadScaleIsContinuousAndNotEqualSized() {
    for seed in UInt64(0)..<2_048 {
        let recipe = CompositionPlanner.make(daySeed: seed,
            eventIDs: Array(CorpusManifest.canonicalEventIDs.prefix(10)), viewport: .phone)
        guard recipe.grammar != .equalScaleStudy else { continue }
        #expect(recipe.maximumDiameter / recipe.minimumDiameter >= 3)
    }
}
```

- [ ] **Step 2: Run the tests and verify RED**

Run the focused `CompositionPlannerTests`; expected failure is missing recipe/planner types.

- [ ] **Step 3: Implement grammar weights, actor-local candidates, and incremental scoring**

Use continuous diameter ranges `0.06...0.16`, `0.16...0.38`, and `0.38...0.75`, with `equalScaleStudy <= 10%`. Each event ID owns at least 32 deterministic candidates. Admit actors by stable identity priority, score coverage, vertical thirds, seeded asymmetric balance, grammar overlap target, negative space, scale/depth separation, edge crop, and penalties for angular regularity, row/grid alignment, equal spacing, common focal point, and compact clustering. Never mutate an already admitted actor while adding a later identity.

- [ ] **Step 4: Run deterministic and 2,048-seed distribution tests**

Expected: all tests pass; the test log prints grammar shares and worst-case guardrail scores.

- [ ] **Step 5: Commit the neutral planner**

```bash
git add -- Tools/DayObjectsEditorialField/Sources/EditorialFieldCore Tools/DayObjectsEditorialField/Tests/EditorialFieldCoreTests
git commit -m "feat: add editorial field composition planner"
```

### Task 3: Neutral composition evidence and isolated artist round

**Files:**
- Create: `Tools/DayObjectsEditorialField/Sources/EditorialFieldRender/NeutralRenderer.swift`
- Create: `Tools/DayObjectsEditorialField/Sources/EditorialFieldEvidence/EvidencePackage.swift`
- Create: `Tools/DayObjectsEditorialField/Sources/editorial-field-render/main.swift`
- Create: `Tools/DayObjectsEditorialField/Tests/EditorialFieldRenderTests/NeutralRendererTests.swift`
- Create: `artifacts/day-objects-editorial-field/director/decision-ledger.md`
- Create: round-specific composition artifacts only under `artifacts/day-objects-editorial-field/composition/`.

**Interfaces:**
- Produces CLI: `editorial-field-render composition --manifest <path> --output <round-dir>`.
- Produces: `manifest.json`, one `@3x` PNG per fixture/phase/view, neutral contact sheets, debug overlays, `metrics.json`, `SHA256SUMS`, and `package-hash.txt`.
- Consumes: composition recipe only; no material family or production renderer.

- [ ] **Step 1: Write failing pixel-size and package-integrity tests**

Require `1179 x 2556` full-screen PNGs, tile crops derived from the same scene, distinct neutral actor labels, debug overlay toggles, complete breadth/continuity coverage, and artifact hashes that fail verification after one byte changes.

- [ ] **Step 2: Run render tests and verify RED**

Expected: missing renderer/evidence package types.

- [ ] **Step 3: Implement neutral CoreGraphics renderer and immutable evidence packaging**

Render actors as neutral grayscale discs with depth-coded luminance and actor labels. Apply composition-local blur before compositing, draw larger foreground actors later, expose crop/overlap/center-of-mass/occupied-bounds overlays in separate images, and derive the tile as an explicit crop of the same canvas recipe.

- [ ] **Step 4: Commission two or three isolated composition artists through the Visual Director**

Each artist starts from the same plan/manifest commit in a separate worktree, receives only the contract and references, does not read sibling worktrees, and returns artifact paths, commands, metrics, source commit, and limitations without a verdict. Artists may modify only sandbox composition/scoring files and their own round directory.

- [ ] **Step 5: Run fresh critic gauntlets to a double blind PASS**

For each revision, create a fresh critic with only the contract, tagged references, manifest, artifact package, and render command. Store its exact four-line verdict. Return only the largest gap and acceptance test to the responsible artist. Freeze `composition-approved.json` and the evidence-package hash only after two independent blind PASS verdicts on the identical package.

- [ ] **Step 6: Commit the selected composition sandbox and director ledger**

Stage only selected sandbox sources, tests, approved recipe/evidence manifests, and the director ledger; do not commit losing artist implementation branches.

### Task 4: Material DNA on frozen layouts

**Files:**
- Create: `Tools/DayObjectsEditorialField/Sources/EditorialFieldCore/MaterialDNA.swift`
- Create: `Tools/DayObjectsEditorialField/Sources/EditorialFieldRender/MaterialRenderer.swift`
- Create: `Tools/DayObjectsEditorialField/Tests/EditorialFieldCoreTests/MaterialDNATests.swift`
- Create: `Tools/DayObjectsEditorialField/Tests/EditorialFieldRenderTests/MaterialRendererTests.swift`
- Create: round-specific material artifacts under `artifacts/day-objects-editorial-field/material/`.

**Interfaces:**
- Produces: `RadialField(focus:radius:softness:opacity:colorIndex:blend:)` where blend is `normal`, `screen`, `softLight`, or `multiply`.
- Produces: one daily `MaterialFamily`, optional compatible mutation, one-to-three actor colors, and no more than three fields.
- Consumes: the frozen composition recipe byte-for-byte.

- [ ] **Step 1: Write failing model tests for family coherence and true solids**

Require all nine families to be reachable, first-three outline/counterform visibility, one related daily family, stable actor-local mutations, exactly one color and zero hidden brightness fields for `.solid`, and only supported radial blends.

- [ ] **Step 2: Write failing pixel tests**

Require spatially constant solid interiors before edge antialiasing, measurable hue/chroma difference across multicolor regions, secondary fields that change chroma rather than luminance alone, no angular seam in radial fixtures, readable transparent silhouettes on light/dark/low-contrast backgrounds, and distinct outline/counterform alpha topology.

- [ ] **Step 3: Implement radial-only material generation and CoreGraphics rendering**

Port the HTML behavior—not its 4–7 layer count or linear fields—using broad shifted radial centers, overlapping influence, saturated palette colors, supported blends, visibility floors, and related mutations. Keep material generation independent from composition geometry.

- [ ] **Step 4: Render the full material atlas on approved layouts**

Render every family, one/two/three-color fixtures, required backgrounds, full screen and tile, and a dedicated outline/counterform sheet. Include radial descriptors and color samples in `metrics.json`.

- [ ] **Step 5: Run fresh critics until two blind PASS verdicts freeze the same package**

Critics judge smooth radial fields, real secondary color, shifted centers, saturation, transparency, flat solids, and structural families. Only one gap/test returns to the material artist per revision.

- [ ] **Step 6: Commit the approved material sandbox**

Commit selected source/tests, `material-approved.json`, the frozen composition hash it consumes, material package hash, and exact critic verdicts.

### Task 5: Motion, depth, insertion, and removal on frozen static recipes

**Files:**
- Create: `Tools/DayObjectsEditorialField/Sources/EditorialFieldCore/MotionField.swift`
- Create: `Tools/DayObjectsEditorialField/Sources/EditorialFieldRender/MotionRenderer.swift`
- Create: `Tools/DayObjectsEditorialField/Tests/EditorialFieldCoreTests/MotionFieldTests.swift`
- Create: `Tools/DayObjectsEditorialField/Tests/EditorialFieldRenderTests/MotionRendererTests.swift`
- Create: round-specific motion artifacts under `artifacts/day-objects-editorial-field/motion/`.

**Interfaces:**
- Produces: shared daily low-frequency flow plus stable per-actor phase, direction bias, amplitude, speed ratio, breathing, depth parallax, insertion envelope, and removal envelope.
- Produces four still phases, path/depth traces, low/normal-step GIFs, Reduce Motion stills, and insertion/removal GIFs.
- Consumes unchanged approved composition and material recipe hashes.

- [ ] **Step 1: Write failing motion invariants**

Test exact loop closure for position/depth/breathing, actor-local phase stability through reorder/insertion/removal, almost-still low-step tempo, no Reduce Motion change across time, continuous depth without focus jumps, and foreground blur greater than the sharpest middle actor.

- [ ] **Step 2: Run motion tests and verify RED**

Expected: missing motion field and evidence renderer.

- [ ] **Step 3: Implement shared flow with actor-local sampling**

Use low-frequency closed curves with periods long enough for slow meaningful travel, stable phase/direction/amplitude/speed ratios, depth-scaled parallax, bounded breathing, and restrained rotation. Keep route/depth/breathing frozen when Reduce Motion is true.

- [ ] **Step 4: Render required 8–12 second evidence**

Include normal/low steps, normal/low sleep, all four phases, Reduce Motion, insertion, and removal. Store traces beside GIFs and hash every frame-derived artifact.

- [ ] **Step 5: Run fresh critics until two blind PASS verdicts freeze one package**

Critics reject orbiting, fast local spin, flicker, loop discontinuity, shared phase, identity loss, flat depth, or material degradation in motion.

- [ ] **Step 6: Commit the approved motion sandbox**

Commit source/tests, frozen recipe hashes, motion package hash, and exact verdicts.

### Task 6: Hidden held-out corpus and versioned sandbox freeze

**Files:**
- Modify: `Tools/DayObjectsEditorialField/Sources/EditorialFieldCore/CorpusManifest.swift`
- Modify: `Tools/DayObjectsEditorialField/Sources/editorial-field-corpus/main.swift`
- Create: `Tools/DayObjectsEditorialField/Tests/EditorialFieldCoreTests/HeldOutCorpusTests.swift`
- Create: `artifacts/day-objects-editorial-field/held-out/<candidate-commit>/`.

**Interfaces:**
- Produces CLI: `editorial-field-corpus held-out --candidate <commit> --nonce <128-bit-hex> --output <path>`.
- Produces exactly 24 balanced hidden fixtures and a manifest hash before rendering.
- Produces `SceneRecipe.schemaVersion == 1` freeze only after held-out PASS.

- [ ] **Step 1: Write failing held-out derivation tests**

Require 24 fixtures, four per actor count, fixed condition tables, candidate commit and critic-provided nonce in the manifest, no visible-seed reuse, no omission/substitution, and byte-stable re-derivation.

- [ ] **Step 2: Freeze a candidate source commit before nonce generation**

Record the commit in the director ledger. A fresh critic generates an unpredictable 128-bit nonce; write nonce, commit, manifest, and manifest hash before any held-out render.

- [ ] **Step 3: Render the complete held-out corpus without code changes**

Verify `git rev-parse HEAD` still equals the frozen candidate and the output manifest contains all 24 fixtures.

- [ ] **Step 4: Obtain two independent blind PASS verdicts**

Each fresh critic receives separately randomized labels and the same frozen contact sheet. Any failure makes those seeds visible training evidence and requires a new candidate commit plus a new critic nonce.

- [ ] **Step 5: Freeze versioned `SceneRecipe` semantics**

Write the schema version, exact enum raw values, numeric ranges, blend operations, and coordinate conventions into the sandbox README and canonical JSON fixtures; commit the held-out package hashes and verdicts.

### Task 7: Production `SceneRecipe` model and stable scene assembly

**Precondition:** Tasks 3–6 each have two PASS verdicts on frozen package hashes.

**Files:**
- Create: `StepsTrader/Experiments/DayObjects/DayObjectSceneRecipe.swift`
- Modify: `StepsTrader/Experiments/DayObjects/DayObjectComposition.swift`
- Modify: `StepsTrader/Experiments/DayObjects/DayObjectTypes.swift`
- Modify: `StepsTrader/Experiments/DayObjects/DayObjectScene.swift`
- Modify: `Steps4.xcodeproj/project.pbxproj` only if the project does not use synchronized source groups.
- Modify: `Steps4Tests/DayObjectSceneTests.swift`
- Modify: `Steps4Tests/DayObjectChoreographyTests.swift`

**Interfaces:**
- Produces: production `DayObjectSceneRecipe` with exact sandbox schema semantics.
- Produces canonical actor admission independent from input order and stable retained actor recipes.
- Consumes only frozen sandbox recipe values; Metal does not choose a second aesthetic.

- [ ] **Step 1: Write failing golden-recipe decoding and stability tests**

Load committed sandbox JSON fixtures and assert production types reproduce grammar, positions, diameter, depth, crop, draw order, and canonical identities. Add reorder/insertion/removal equality tests and distribution guardrails.

- [ ] **Step 2: Run focused scene/choreography tests and verify RED**

Expected: missing production recipe types and old preset/topology mismatches.

- [ ] **Step 3: Implement the minimal production mirror and adapter**

Mirror the schema without new random choices. Replace chronological admission with stable identity priority and keep the current maximum-ten constraint. Preserve main Gallery selection and all non-Lab canvas paths.

- [ ] **Step 4: Run sandbox parity fixtures and full model tests**

Require exact numeric equality within documented floating-point tolerance for every visible seed and actor.

- [ ] **Step 5: Commit model transfer only**

Stage the new recipe/model/tests and any necessary project entry; exclude existing unrelated palette/performance/localization WIP.

### Task 8: Production material, motion, focus, and Metal transfer

**Files:**
- Modify: `StepsTrader/Experiments/DayObjects/DayObjectVisualLanguage.swift`
- Modify: `StepsTrader/Experiments/DayObjects/DayObjectMotionPlan.swift`
- Modify: `StepsTrader/Experiments/DayObjects/DayObjectRenderFrame.swift`
- Modify: `StepsTrader/Metal/DayObjectsActorShader.metal`
- Modify: `Steps4Tests/DayObjectPaletteTests.swift`
- Modify: `Steps4Tests/DayObjectRenderFrameTests.swift`

**Interfaces:**
- Consumes frozen production `DayObjectSceneRecipe` from Task 7.
- Produces no more than three radial fields, three colors, one flat-solid branch, local depth blur, continuous motion, and unchanged instanced draw count.

- [ ] **Step 1: Write failing upload/ABI and pixel tests**

Test sandbox descriptor parity, supported blend raw values, true flat solid pixels, multicolor chroma differences, no angular seams, transparency floors, outline/counterform topology, foreground softness, loop continuity, and Reduce Motion freezing.

- [ ] **Step 2: Run focused render tests and verify RED**

Expected: old GPU appearance/route semantics fail the new fixture assertions.

- [ ] **Step 3: Pack the frozen bounded recipe without adding a draw or texture**

Keep at most three fields/colors, clamp only to schema ranges, preserve the existing background/post/grain passes, and apply local focus before global sleep blur.

- [ ] **Step 4: Implement radial-only shader color and material branches**

The `.solid` branch outputs its one constant palette color before edge antialiasing. Multicolor branches evaluate shifted radial distances and supported blends only; sphere/glass/halo/luminous optics may add light after base color but may not replace chroma with gray.

- [ ] **Step 5: Run full render/model suites and verify one instanced draw**

Run focused Day Object tests, complete `Steps4Tests`, simulator build, and physical-device performance scheme when hardware is available. Require no new Metal warnings and no extra actor draw calls or per-object allocations.

- [ ] **Step 6: Commit Metal transfer separately**

Stage only the production material/motion/upload/shader files and their tests.

### Task 9: Blind sandbox-to-Metal parity and Lab-only integration

**Files:**
- Modify: `StepsTrader/Experiments/DayObjects/DayObjectsLabView.swift`
- Modify: `Steps4UITests/DayObjectsLabUITests.swift`
- Create: `artifacts/day-objects-editorial-field/metal-parity/<commit>/`.
- Create: `artifacts/day-objects-editorial-field/integration/<commit>/`.

**Interfaces:**
- Produces matched sandbox/Metal core-seed renders, randomized A/B sheets, composition/color metrics, motion clips, relaunch proof, and exact package hashes.
- Consumes the same visible manifest and frozen recipe semantics on both renderers.

- [ ] **Step 1: Capture matched sandbox and Metal evidence**

Use identical seed, actor count, phase, viewport, tile crop, background, sleep, steps, and Reduce Motion settings. Include one, two, three, five, seven, and ten actors plus insertion/removal.

- [ ] **Step 2: Obtain two independent blind Metal-parity PASS verdicts**

Reject any loss of scale hierarchy, placement, crop, depth, radial richness, contour identity, transparency, or motion character. Pixel equality is not required.

- [ ] **Step 3: Run Lab-only UI and deterministic relaunch tests**

Assert Day Objects remains reachable through the laboratory, is absent from the main Gallery, preserves count across insertion/removal, freezes under Reduce Motion, and reproduces the same recipe after relaunch.

- [ ] **Step 4: Freeze final integration evidence and obtain two blind PASS verdicts**

Cover full screen and tile, all background conditions, normal/low sleep, low/normal steps, Reduce Motion, insertion/removal, and required actor counts on one package hash.

- [ ] **Step 5: Verify before any golden update**

Run:

```bash
swift test --package-path Tools/DayObjectsEditorialField
xcodebuild test -project Steps4.xcodeproj -scheme Steps4 -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17,OS=latest' CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO
xcodebuild build -project Steps4.xcodeproj -scheme Steps4 -configuration Debug -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO
git diff --check
git status --short
```

Only after the exact candidate render receives the required visual PASS may a separate commit update inspected perceptual signatures. If no accepted replacement render exists, leave all goldens unchanged.

- [ ] **Step 6: Commit integration evidence and any approved goldens separately**

Do not stage `StepsTrader/Localizable.xcstrings`, physical-performance WIP, or any pre-existing dirty file unless its exact hunk belongs to this plan and has been reviewed independently.

## Plan Self-Review

- Spec coverage: seed derivation, 12/7/48 visible suites, 24 held-out fixtures, all required counts/conditions/views, neutral composition, material isolation, motion isolation, critic protocol, double PASS, Metal parity, Lab-only integration, performance, and golden policy each map to a task.
- Placeholder scan: this plan contains no TBD/TODO/"implement later" step; every conditional gate names its precondition and evidence.
- Type consistency: `CorpusManifest` feeds `CompositionPlanner`; composition freezes into `SceneRecipe`; material and motion extend that same recipe; production `DayObjectSceneRecipe` mirrors the frozen schema; Metal consumes the production mirror without new aesthetic decisions.
- Dirty-tree safety: every commit step names staged paths and explicitly excludes existing palette/render/performance/localization WIP.
