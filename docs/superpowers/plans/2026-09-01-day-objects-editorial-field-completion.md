# Day Objects Editorial Field Completion Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Finish the approved Day Objects Editorial Field through material, motion, held-out, Metal-parity, and final Lab-only integration gates without changing the application's main canvas.

**Architecture:** Continue from the frozen composition and accepted Material F lineage, close the one remaining outline defect in an isolated sandbox, then freeze a versioned `SceneRecipe` only after static material and motion packages each receive two blind PASS verdicts. Production code mirrors the frozen recipe into the existing single instanced Metal renderer; it does not make a second aesthetic decision.

**Tech Stack:** Swift 6, Swift Package Manager, Foundation, CryptoKit, CoreGraphics, ImageIO, Swift Testing/XCTest, SwiftUI, Metal Shading Language, Xcode simulator and physical-device verification.

**Spec:** `docs/superpowers/specs/2026-08-30-day-objects-editorial-field-design.md`

## Global Constraints

- Day Objects remains Lab-only and must not replace or modify the restored main application canvas.
- Composition is frozen. Do not change actor position, diameter, depth, crop, draw order, overlap, or negative space.
- Maximum actor count is exactly 10; production retains one instanced actor draw and no per-object textures or offscreen passes.
- Visible evidence covers 1, 2, 3, 5, 7, and 10 happenings; full screen and production tile crop; light, dark, saturated, and low-contrast backgrounds; normal and low sleep; low and normal steps; Reduce Motion; insertion and removal.
- A solid actor is spatially constant. Multicolor actors use at most three broad overlapping radial fields and never use linear, angular, conic, pyramidal, Voronoi-like, or hard ownership boundaries.
- Very large foreground actors remain more defocused than the sharpest middle-plane actor.
- Motion starts only after the complete material package receives two blind PASS verdicts on one package hash.
- Metal transfer starts only after composition, material, motion, and a fresh 24-fixture held-out corpus each pass independently.
- Every visual revision receives a fresh critic. Two critics must independently PASS the same immutable package; disagreement is ITERATE.
- A critic receives only the contract, tagged references, applicable manifest, render instructions, and artifacts, and responds with exactly `VERDICT`, `EVIDENCE`, `LARGEST GAP`, and `NEXT ACCEPTANCE TEST`.
- The Visual Director owns references, manifests, artifacts, package hashes, critic isolation, and the decision ledger. The director does not draw or write renderer code.
- An artist receives only one largest visual gap and one observable acceptance test. Three repeats require a representation or architecture change, not weaker thresholds.
- Preserve the dirty outline experiments in `.worktrees/editorial-material-f`; do not reset, delete, clean, or overwrite them.
- Preserve all unrelated dirty files. Every commit stages only the paths explicitly named in its task.
- Perceptual goldens remain unchanged until a replacement Metal render has been visually inspected and accepted.

## Verified Starting Point

- [x] Visible manifest is reproducible from specification commit `8a8539a77ce704fcc688ebe8cb98d78e2a0f80dd`.
- [x] Composition received two PASS verdicts and is frozen by `composition-approved.json` and `composition-recipes-approved.json`.
- [x] Material F base, halo 1x identity, and mist 1x grain are committed through `6f4e656cfebf2a8ead1730ba68c0015b72826e52`.
- [x] Halo soft-core is committed as `622b7b50e0a4594ab47889a2265748e51e94e523`, passes 99 sandbox tests, has byte-identical 1x/3x rerenders, and received two blind PASS verdicts.
- [ ] The complete material gate is still closed because outline actors become broad toruses or ripple-filled discs at native scene scale.
- [ ] Motion, held-out, sandbox freeze, Metal parity, final integration, and any new perceptual goldens have not started.

## File Map

### Sandbox material completion

- Modify `Tools/DayObjectsEditorialField/Sources/EditorialFieldRender/MaterialRenderer.swift`: preserve outline structural alpha through scene compositing and native downsampling.
- Modify `Tools/DayObjectsEditorialField/Tests/EditorialFieldRenderTests/MaterialRendererTests.swift`: black-box native full/tile outline acceptance tests and negative controls.
- Modify `Tools/DayObjectsEditorialField/Sources/EditorialFieldEvidence/MaterialEvidencePackage.swift` only if the frozen package must expose an outline authority trace already produced by the renderer.
- Modify `artifacts/day-objects-editorial-field/director/decision-ledger.md`: exact material source commit, package hashes, critic verdicts, and gate state.
- Create `artifacts/day-objects-editorial-field/material/approved-$OUTLINE_SHORT_COMMIT/`: one immutable approved material package, rerender proof, contact sheets, and exact critic verdicts.
- Create `artifacts/day-objects-editorial-field/material/material-approved.json`: composition hashes, source commit, scale-1 and scale-3 package hashes, and both PASS verdict digests.

### Sandbox motion and held-out freeze

- Create `Tools/DayObjectsEditorialField/Sources/EditorialFieldCore/MotionField.swift`: shared closed flow plus stable actor-local phase, parallax, breathing, and insertion/removal envelopes.
- Create `Tools/DayObjectsEditorialField/Sources/EditorialFieldRender/MotionRenderer.swift`: still phases, GIFs, path/depth traces, and Reduce Motion evidence.
- Create `Tools/DayObjectsEditorialField/Sources/EditorialFieldEvidence/MotionEvidencePackage.swift`: immutable motion artifact manifest and verification.
- Modify `Tools/DayObjectsEditorialField/Sources/editorial-field-render/main.swift`: `motion` and `verify-motion` commands.
- Create `Tools/DayObjectsEditorialField/Tests/EditorialFieldCoreTests/MotionFieldTests.swift`.
- Create `Tools/DayObjectsEditorialField/Tests/EditorialFieldRenderTests/MotionRendererTests.swift`.
- Create `artifacts/day-objects-editorial-field/motion/motion-approved.json`: frozen composition/material hashes, motion package hash, and exact critic verdict digests.
- Modify `Tools/DayObjectsEditorialField/Sources/EditorialFieldCore/CorpusManifest.swift`: deterministic held-out derivation after candidate freeze.
- Modify `Tools/DayObjectsEditorialField/Sources/editorial-field-corpus/main.swift`: `held-out` and held-out verification commands.
- Create `Tools/DayObjectsEditorialField/Tests/EditorialFieldCoreTests/HeldOutCorpusTests.swift`.
- Modify `Tools/DayObjectsEditorialField/Sources/EditorialFieldCore/SceneRecipe.swift`: replace the composition-only alias with versioned frozen recipe semantics.
- Modify `Tools/DayObjectsEditorialField/README.md`: exact schema, ranges, blend operations, coordinate conventions, and reproduction commands.

### Lab-only production transfer

- Create `StepsTrader/Experiments/DayObjects/DayObjectSceneRecipe.swift`: Codable production mirror of frozen sandbox schema version 1.
- Modify `StepsTrader/Experiments/DayObjects/DayObjectComposition.swift`: map frozen composition values without rerolling.
- Modify `StepsTrader/Experiments/DayObjects/DayObjectTypes.swift`: store bounded recipe fields.
- Modify `StepsTrader/Experiments/DayObjects/DayObjectScene.swift`: canonical admission and immutable recipe assembly.
- Modify `StepsTrader/Experiments/DayObjects/DayObjectVisualLanguage.swift`: frozen material family, color, field, topology, and mutation semantics.
- Modify `StepsTrader/Experiments/DayObjects/DayObjectMotionPlan.swift`: frozen flow and per-actor motion semantics.
- Modify `StepsTrader/Experiments/DayObjects/DayObjectRenderFrame.swift`: upload recipe fields and local focus.
- Modify `StepsTrader/Metal/DayObjectsActorShader.metal`: flat solid and radial-only material branches.
- Modify `StepsTrader/Experiments/DayObjects/DayObjectsLabView.swift`: Lab diagnostics and fixture capture controls only.
- Modify `Steps4Tests/DayObjectSceneTests.swift`, `Steps4Tests/DayObjectChoreographyTests.swift`, `Steps4Tests/DayObjectPaletteTests.swift`, and `Steps4Tests/DayObjectRenderFrameTests.swift`: schema, stability, ABI, pixel, focus, motion, and Reduce Motion parity.
- Modify `Steps4UITests/DayObjectsLabUITests.swift`: Lab-only reachability, actor counts, insertion/removal, Reduce Motion, and deterministic relaunch.

---

### Task 1: Close the outline gap and freeze the complete material package

**Precondition:** Use `622b7b50e0a4594ab47889a2265748e51e94e523` as the clean base. The dirty `.worktrees/editorial-material-f` worktree is read-only research evidence, not an implementation base.

**Files:**
- Modify: `Tools/DayObjectsEditorialField/Sources/EditorialFieldRender/MaterialRenderer.swift`
- Modify: `Tools/DayObjectsEditorialField/Tests/EditorialFieldRenderTests/MaterialRendererTests.swift`
- Modify only if required by an already-rendered trace: `Tools/DayObjectsEditorialField/Sources/EditorialFieldEvidence/MaterialEvidencePackage.swift`
- Modify after double PASS: `artifacts/day-objects-editorial-field/director/decision-ledger.md`
- Create after double PASS: `artifacts/day-objects-editorial-field/material/material-approved.json`

**Interfaces:**
- Consumes: frozen `CompositionRecipe`, `MaterialDNA`, `MaterialRenderConfiguration`, and accepted halo/mist behavior at commit `622b7b5`.
- Produces: native-1x outline pixels whose open center and one-to-three thin contours survive whole-scene downsampling without changing actor alpha ownership.
- Produces: one approved material package hash consumed unchanged by motion.

- [ ] **Step 1: Create a clean isolated outline worktree**

Run from the repository root:

```bash
git check-ignore -q .worktrees
git worktree add .worktrees/editorial-outline-alpha-authority \
  -b codex/editorial-outline-alpha-authority \
  622b7b50e0a4594ab47889a2265748e51e94e523
git -C .worktrees/editorial-outline-alpha-authority status --short --branch
```

Expected: the new worktree is clean on `codex/editorial-outline-alpha-authority`; neither existing material worktree changes.

- [ ] **Step 2: Have the Visual Director issue one outline contract**

The directive is exactly:

```text
LARGEST GAP: At native 1x full and tile scale, outline actors become filled toruses or ripple-filled discs instead of one-to-three thin open contours.
NEXT ACCEPTANCE TEST: Rerender c1/c2/c3 outline on light/dark/lowContrast in native 1x full and tile views; every eligible actor must retain an unmistakably open center and one-to-three continuous thin contours, with no filled torus, ripple disc, missing contour, or broken arc.
```

The director commissions one fresh artist and does not reveal the three earlier implementations.

- [ ] **Step 3: Add a black-box failing scene-scale test before changing the renderer**

Add a Swift Testing case named:

```swift
@Test("native outline presentation keeps thin open contours in every core condition")
func outlineSceneScaleKeepsOpenCenterAcrossNativePresentations() throws {
    // Render c1/c2/c3 x light/dark/lowContrast at scale 1.
    // Inspect both full-screen and the renderer-owned tile crop.
    // Require an open-center alpha floor, bounded contour thickness,
    // one-to-three owned radial bands, and continuous angular support.
}
```

Include synthetic controls for a thin open contour, a filled torus, a ripple-filled disc, a vanished contour, and a broken arc. The positive control must pass; every negative control must fail before production pixels are evaluated.

- [ ] **Step 4: Run the new test and record the RED evidence**

```bash
swift test --package-path Tools/DayObjectsEditorialField \
  --filter outlineSceneScaleKeepsOpenCenterAcrossNativePresentations
```

Expected: the frozen `622b7b5` renderer fails on at least one native full or tile fixture by reporting a filled center, excessive contour thickness, or excessive radial-band density. Save exact failing fixture labels and metrics in the artist report; do not weaken thresholds after seeing the candidate.

- [ ] **Step 5: Implement alpha-authority compositing without a fourth visibility overlay**

Use one structural alpha authority plane derived from the authored outline before RGB visibility adjustment. Apply actor-local blur once, then use source-atop color projection so contrast changes RGB inside the existing authority but cannot add or square alpha.

The implementation invariant is:

```swift
finalAlpha == blurredStructuralAuthorityAlpha
```

and never:

```swift
finalAlpha = authorityAlpha + accentAlpha * (1 - authorityAlpha)
```

Do not paint a new contour after whole-scene downsampling. Do not change outline radii, composition geometry, halo, mist, counterform, or material palette allocation.

- [ ] **Step 6: Prove the focused test GREEN with robust margins**

```bash
swift test --package-path Tools/DayObjectsEditorialField \
  --filter outlineSceneScaleKeepsOpenCenterAcrossNativePresentations
swift test --package-path Tools/DayObjectsEditorialField --filter outline
git diff --check
```

Expected: both commands pass; negative controls still fail their acceptance predicate; no fixture sits within measurement noise of a threshold.

- [ ] **Step 7: Run the full sandbox suite and commit only the accepted implementation**

```bash
swift test --package-path Tools/DayObjectsEditorialField
git add -- \
  Tools/DayObjectsEditorialField/Sources/EditorialFieldRender/MaterialRenderer.swift \
  Tools/DayObjectsEditorialField/Tests/EditorialFieldRenderTests/MaterialRendererTests.swift
git diff --cached --check
git commit -m "fix(editorial-field): preserve outline identity at scene scale"
```

If `MaterialEvidencePackage.swift` changed, stage it only after confirming the change exposes an existing renderer trace and does not create a second rendering path.

- [ ] **Step 8: Render candidate and rerender packages at 1x and 3x**

Set the task-specific paths, then run `editorial-field-render material` and `verify-material` from the exact new commit for scale 1 and scale 3:

```bash
OUTLINE_COMMIT="$(git rev-parse HEAD)"
OUTLINE_SHORT_COMMIT="$(git rev-parse --short=7 HEAD)"
VISIBLE_MANIFEST="Tools/DayObjectsEditorialField/Manifests/visible-v1.json"
COMPOSITION_APPROVAL="artifacts/day-objects-editorial-field/composition/composition-approved.json"
COMPOSITION_RECIPES="artifacts/day-objects-editorial-field/composition/composition-recipes-approved.json"
MATERIAL_ROOT="artifacts/day-objects-editorial-field/material/approved-$OUTLINE_SHORT_COMMIT"
```

Generate `scale1-candidate`, `scale1-rerender`, `scale3-candidate`, and `scale3-rerender` below `MATERIAL_ROOT`, passing `--source-commit "$OUTLINE_COMMIT"` and the corresponding `--scale`. Verify all four with `verify-material`. Require candidate/rerender relative file lists and all 261 corresponding SHA-256 values to be identical at each scale.

Required review sheets include:

```text
outline c1/c2/c3 actor crops at 1x and 3x
outline c1/c2/c3 x light/dark/lowContrast full at native 1x
outline c1/c2/c3 x light/dark/lowContrast tile at native 1x
outline/counterform family comparison
complete nine-family material atlas
same-seed baseline/candidate blind A/B
```

- [ ] **Step 9: Obtain two fresh blind material PASS verdicts on one hash**

Each critic sees the complete material package, not only outline crops. Both must independently confirm solids, radial color, transparency, mist, halo, luminous, outline, and counterform. Any `ITERATE` returns only its single largest gap and next test to a fresh artist.

- [ ] **Step 10: Freeze and commit the material gate**

Create `material-approved.json` containing the source commit, composition approval SHA-256, composition recipe SHA-256, scale-1 package hash, scale-3 package hash, and digests of both exact verdict files. Update the decision ledger and commit only approved sandbox source/tests plus approval metadata:

```bash
git add -- \
  artifacts/day-objects-editorial-field/director/decision-ledger.md \
  artifacts/day-objects-editorial-field/material/material-approved.json \
  "artifacts/day-objects-editorial-field/material/approved-$OUTLINE_SHORT_COMMIT"
git diff --cached --check
git commit -m "feat(editorial-field): freeze approved material package"
```

Do not stage UUID test directories, losing rounds, comparison scratch files, or unrelated artifacts.

### Task 2: Build and visually freeze slow depth-aware motion

**Precondition:** Task 1 has two material PASS verdicts on the same package hash.

**Files:**
- Create: `Tools/DayObjectsEditorialField/Sources/EditorialFieldCore/MotionField.swift`
- Create: `Tools/DayObjectsEditorialField/Sources/EditorialFieldRender/MotionRenderer.swift`
- Create: `Tools/DayObjectsEditorialField/Sources/EditorialFieldEvidence/MotionEvidencePackage.swift`
- Modify: `Tools/DayObjectsEditorialField/Sources/editorial-field-render/main.swift`
- Create: `Tools/DayObjectsEditorialField/Tests/EditorialFieldCoreTests/MotionFieldTests.swift`
- Create: `Tools/DayObjectsEditorialField/Tests/EditorialFieldRenderTests/MotionRendererTests.swift`
- Modify after double PASS: `artifacts/day-objects-editorial-field/director/decision-ledger.md`
- Create after double PASS: `artifacts/day-objects-editorial-field/motion/motion-approved.json`

**Interfaces:**
- Produces: `ActorMotionRecipe(eventID:period:phase:directionBias:amplitude:speedRatio:breathingAmplitude:depthParallax:)`.
- Produces: `MotionField.make(daySeed:eventIDs:) -> [String: ActorMotionRecipe]`.
- Produces: `MotionField.pose(recipe:phase:steps:reduceMotion:) -> ActorMotionPose` with position offset, depth offset, scale, and restrained rotation.
- Consumes: unchanged approved composition and material hashes.

- [ ] **Step 1: Write failing deterministic motion tests**

Test exact loop closure at normalized phases `0` and `1`, stable retained actor recipes across reorder/insertion/removal, independent phase distribution, bounded rotation, low-step travel below normal-step travel, continuous depth, foreground parallax greater than distant parallax, and exact Reduce Motion equality across time.

The core loop test is:

```swift
@Test func motionLoopClosesAndReduceMotionFreezes() throws {
    let recipe = try #require(MotionField.make(daySeed: 77, eventIDs: ["A"])["A"])
    #expect(MotionField.pose(recipe: recipe, phase: 0, steps: .normal, reduceMotion: false)
        == MotionField.pose(recipe: recipe, phase: 1, steps: .normal, reduceMotion: false))
    #expect(MotionField.pose(recipe: recipe, phase: 0.25, steps: .normal, reduceMotion: true)
        == MotionField.pose(recipe: recipe, phase: 0.75, steps: .normal, reduceMotion: true))
}
```

- [ ] **Step 2: Run focused motion tests and verify RED**

```bash
swift test --package-path Tools/DayObjectsEditorialField --filter MotionFieldTests
```

Expected: compilation fails because sandbox motion types do not exist.

- [ ] **Step 3: Implement one closed low-frequency daily flow**

Use paired sine/cosine harmonics whose normalized phase is periodic, with actor-local stable phase, direction bias, amplitude, speed ratio, breathing, and depth parallax. Periods are slow enough for 8–12 second excerpts to show drift without exposing a short orbit. Rotation remains subordinate to translation and never becomes a local spinner.

- [ ] **Step 4: Implement insertion, removal, and Reduce Motion envelopes**

Insertion and removal change only the entering or leaving actor's opacity/scale envelope. Retained actors keep identical base recipe and phase. When `reduceMotion == true`, route, depth migration, breathing, and rotation return the phase-zero composed frame.

- [ ] **Step 5: Add motion evidence generation and verification**

Extend the CLI with:

```text
editorial-field-render motion --manifest $VISIBLE_MANIFEST --material-approval $MATERIAL_APPROVAL --output $MOTION_ROUND --source-commit $MOTION_COMMIT
editorial-field-render verify-motion --package $MOTION_ROUND --expected-source-commit $MOTION_COMMIT --material-approval $MATERIAL_APPROVAL
```

Before running those commands, set `VISIBLE_MANIFEST` to `Tools/DayObjectsEditorialField/Manifests/visible-v1.json`, `MATERIAL_APPROVAL` to `artifacts/day-objects-editorial-field/material/material-approved.json`, `MOTION_COMMIT` to the full output of `git rev-parse HEAD`, and `MOTION_ROUND` to `artifacts/day-objects-editorial-field/motion/approved-${MOTION_COMMIT:0:7}`.

The package contains four phase stills, 8–12 second clips, per-actor path/depth traces, low/normal steps, normal/low sleep, Reduce Motion, insertion, removal, full screen, and tile evidence.

- [ ] **Step 6: Run focused and full tests**

```bash
swift test --package-path Tools/DayObjectsEditorialField --filter Motion
swift test --package-path Tools/DayObjectsEditorialField
git diff --check
```

- [ ] **Step 7: Run the director-led motion gauntlet to double PASS**

Fresh critics reject orbiting, fast local spin, flicker, loop seams, common phase, flat depth, identity changes, abrupt insertion/removal, Reduce Motion drift, or material degradation. Freeze one byte-reproducible package only after two PASS verdicts.

- [ ] **Step 8: Commit the approved motion sandbox**

Create `motion-approved.json` with the exact composition approval hash, material approval hash, motion source commit, package hash, and both verdict digests. Then commit:

```bash
git add -- \
  Tools/DayObjectsEditorialField/Sources/EditorialFieldCore/MotionField.swift \
  Tools/DayObjectsEditorialField/Sources/EditorialFieldRender/MotionRenderer.swift \
  Tools/DayObjectsEditorialField/Sources/EditorialFieldEvidence/MotionEvidencePackage.swift \
  Tools/DayObjectsEditorialField/Sources/editorial-field-render/main.swift \
  Tools/DayObjectsEditorialField/Tests/EditorialFieldCoreTests/MotionFieldTests.swift \
  Tools/DayObjectsEditorialField/Tests/EditorialFieldRenderTests/MotionRendererTests.swift \
  artifacts/day-objects-editorial-field/director/decision-ledger.md \
  artifacts/day-objects-editorial-field/motion/motion-approved.json \
  "$MOTION_ROUND"
git diff --cached --check
git commit -m "feat(editorial-field): freeze approved motion package"
```

### Task 3: Pass a fresh 24-fixture held-out corpus and freeze schema version 1

**Precondition:** Composition, material, and motion each have two PASS verdicts.

**Files:**
- Modify: `Tools/DayObjectsEditorialField/Sources/EditorialFieldCore/CorpusManifest.swift`
- Modify: `Tools/DayObjectsEditorialField/Sources/editorial-field-corpus/main.swift`
- Create: `Tools/DayObjectsEditorialField/Tests/EditorialFieldCoreTests/HeldOutCorpusTests.swift`
- Modify: `Tools/DayObjectsEditorialField/Sources/EditorialFieldCore/SceneRecipe.swift`
- Modify: `Tools/DayObjectsEditorialField/README.md`
- Create: `artifacts/day-objects-editorial-field/held-out/$FROZEN_COMMIT/`

**Interfaces:**
- Produces: `CorpusManifest.heldOut(candidateCommit:nonce:) -> CorpusManifest` with exactly 24 fixtures.
- Produces: `EditorialSceneRecipeV1` with `schemaVersion == 1` and immutable composition, material, and motion fields.
- Consumes: a frozen candidate commit and a critic-generated 128-bit nonce recorded before rendering.

- [ ] **Step 1: Write failing held-out derivation tests**

Require four fixtures per actor count in `[1, 2, 3, 5, 7, 10]`, no visible-seed reuse, fixed condition tables, byte-stable regeneration, candidate commit and nonce in canonical JSON, and rejection of omitted, reordered, or substituted fixtures.

- [ ] **Step 2: Implement and verify the held-out CLI**

```bash
FROZEN_COMMIT="$(git rev-parse HEAD)"
HELDOUT_NONCE="$(tr -d '\n' < /tmp/editorial-field-held-out-nonce.txt)"
HELDOUT_MANIFEST="artifacts/day-objects-editorial-field/held-out/$FROZEN_COMMIT/manifest.json"
swift test --package-path Tools/DayObjectsEditorialField --filter HeldOutCorpusTests
swift run --package-path Tools/DayObjectsEditorialField editorial-field-corpus \
  held-out --candidate "$FROZEN_COMMIT" --nonce "$HELDOUT_NONCE" --output "$HELDOUT_MANIFEST"
swift run --package-path Tools/DayObjectsEditorialField editorial-field-corpus \
  verify --manifest "$HELDOUT_MANIFEST"
```

The Visual Director writes the fresh critic-provided 32-character lowercase hexadecimal nonce to `/tmp/editorial-field-held-out-nonce.txt` before this command and records its SHA-256 in the ledger. The implementation rejects a nonce that is not exactly 128 bits and rejects a candidate commit that is not a full Git object ID.

- [ ] **Step 3: Freeze candidate, nonce, and manifest before any render**

The director records `git rev-parse HEAD`. A fresh critic generates the nonce. Record the full commit, nonce, manifest SHA-256, and timestamp in the decision ledger before starting the renderer.

- [ ] **Step 4: Render all 24 fixtures without a code change**

After rendering, assert:

```bash
test "$(git rev-parse HEAD)" = "$FROZEN_COMMIT"
git diff --exit-code
git diff --cached --exit-code
```

The evidence package must contain every fixture, required full/tile views, assigned background/sleep/steps/Reduce Motion conditions, and insertion/removal evidence where assigned.

- [ ] **Step 5: Obtain two independent blind held-out PASS verdicts**

Each critic receives a separately randomized label order. Any failure reveals the corpus: record it as training evidence, make a new candidate commit, obtain a new nonce from a different critic, and derive all 24 seeds again.

- [ ] **Step 6: Replace the composition-only alias with `EditorialSceneRecipeV1`**

Define version 1 with explicit composition, material, and motion members and canonical enum raw values. Document normalized coordinates, diameter/depth ranges, blend operations, alpha semantics, motion phase, and insertion/removal envelopes in the README. Add canonical JSON round-trip fixtures.

- [ ] **Step 7: Run the full sandbox verification and commit the freeze**

```bash
swift test --package-path Tools/DayObjectsEditorialField
git diff --check
git add -- \
  Tools/DayObjectsEditorialField/Sources/EditorialFieldCore/CorpusManifest.swift \
  Tools/DayObjectsEditorialField/Sources/EditorialFieldCore/SceneRecipe.swift \
  Tools/DayObjectsEditorialField/Sources/editorial-field-corpus/main.swift \
  Tools/DayObjectsEditorialField/Tests/EditorialFieldCoreTests/HeldOutCorpusTests.swift \
  Tools/DayObjectsEditorialField/README.md \
  artifacts/day-objects-editorial-field/director/decision-ledger.md \
  "artifacts/day-objects-editorial-field/held-out/$FROZEN_COMMIT"
git diff --cached --check
git commit -m "feat(editorial-field): freeze held-out scene recipe v1"
```

### Task 4: Mirror the frozen recipe into the existing Lab scene model

**Precondition:** Task 3 held-out package has two PASS verdicts. Production and Metal files remain untouched before this point.

**Files:**
- Create: `StepsTrader/Experiments/DayObjects/DayObjectSceneRecipe.swift`
- Modify: `StepsTrader/Experiments/DayObjects/DayObjectComposition.swift`
- Modify: `StepsTrader/Experiments/DayObjects/DayObjectTypes.swift`
- Modify: `StepsTrader/Experiments/DayObjects/DayObjectScene.swift`
- Test: `Steps4Tests/DayObjectSceneTests.swift`
- Test: `Steps4Tests/DayObjectChoreographyTests.swift`

**Interfaces:**
- Produces: `DayObjectSceneRecipe` decoding the exact sandbox version-1 JSON schema.
- Produces: canonical stable actor admission independent of input order.
- Consumes: only committed frozen JSON fixtures; no production-side aesthetic randomization.

- [ ] **Step 1: Add failing sandbox-fixture decoding tests**

For every committed visible recipe, assert exact grammar, event identity, normalized position, diameter, depth, local blur, crop allowance, draw order, material family, colors, radial fields, blend values, and motion recipe. Require retained actor equality across reorder, insertion, and removal.

- [ ] **Step 2: Run focused tests and record RED**

```bash
xcodebuild test -project Steps4.xcodeproj -scheme Steps4 -configuration Debug \
  -destination 'platform=iOS Simulator,name=iPhone 17,OS=latest' \
  -only-testing:Steps4Tests/DayObjectSceneTests \
  -only-testing:Steps4Tests/DayObjectChoreographyTests \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO
```

Expected: the production mirror is missing and legacy preset semantics do not match frozen fixtures.

- [ ] **Step 3: Implement the minimal Codable mirror and adapter**

Decode schema version 1, reject unknown versions and unsupported enum values, map canonical identities without chronological rerolls, and preserve the maximum-ten limit. Keep existing main Gallery selection and every non-Lab canvas path unchanged.

- [ ] **Step 4: Run sandbox parity and full model tests**

Require exact integer/string equality and documented floating-point tolerance for every visible fixture. Run all Day Object model tests and `git diff --check`.

- [ ] **Step 5: Commit only the model transfer**

```bash
git add -- \
  StepsTrader/Experiments/DayObjects/DayObjectSceneRecipe.swift \
  StepsTrader/Experiments/DayObjects/DayObjectComposition.swift \
  StepsTrader/Experiments/DayObjects/DayObjectTypes.swift \
  StepsTrader/Experiments/DayObjects/DayObjectScene.swift \
  Steps4Tests/DayObjectSceneTests.swift \
  Steps4Tests/DayObjectChoreographyTests.swift
git diff --cached --check
git commit -m "feat(day-objects-lab): mirror editorial scene recipe"
```

### Task 5: Transfer accepted materials and motion into the instanced Metal renderer

**Precondition:** Task 4 production model tests pass against the frozen sandbox fixtures.

**Files:**
- Modify: `StepsTrader/Experiments/DayObjects/DayObjectVisualLanguage.swift`
- Modify: `StepsTrader/Experiments/DayObjects/DayObjectMotionPlan.swift`
- Modify: `StepsTrader/Experiments/DayObjects/DayObjectRenderFrame.swift`
- Modify: `StepsTrader/Metal/DayObjectsActorShader.metal`
- Test: `Steps4Tests/DayObjectPaletteTests.swift`
- Test: `Steps4Tests/DayObjectRenderFrameTests.swift`

**Interfaces:**
- Consumes: frozen `DayObjectSceneRecipe` from Task 4.
- Produces: no more than three colors and three radial fields, exact supported blend raw values, one flat-solid path, outline/counterform alpha topology, local depth blur, and continuous motion in the existing actor instance buffer.
- Preserves: one instanced actor draw, existing background/post/grain passes, and no per-object allocation.

- [ ] **Step 1: Add failing ABI, descriptor, and pixel parity tests**

Load the sandbox fixtures and assert buffer offsets, color/field counts, blend values, flat solid pixels, smooth radial multicolor samples, transparent silhouette floors, outline/counterform topology, halo continuity, mist grain, foreground softness, loop closure, and Reduce Motion freezing.

- [ ] **Step 2: Run the focused GPU/model tests and record RED**

```bash
xcodebuild test -project Steps4.xcodeproj -scheme Steps4 -configuration Debug \
  -destination 'platform=iOS Simulator,name=iPhone 17,OS=latest' \
  -only-testing:Steps4Tests/DayObjectPaletteTests \
  -only-testing:Steps4Tests/DayObjectRenderFrameTests \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO
```

- [ ] **Step 3: Pack the frozen recipe without changing draw architecture**

Map exactly three bounded field/color slots into the existing instance buffer. Clamp only to documented schema ranges. Apply local actor focus before global sleep blur. Do not add a texture, render target, actor pass, or frame-time random choice.

- [ ] **Step 4: Implement radial-only shader branches**

The `.solid` branch returns its constant palette color before edge antialiasing. Multicolor branches evaluate shifted radial distances and the supported `normal`, `screen`, `softLight`, and `multiply` blends. Sphere, glass, halo, luminous, outline, counterform, and mist interpret the frozen descriptors without retuning composition or palette selection.

- [ ] **Step 5: Run complete tests and build**

```bash
swift test --package-path Tools/DayObjectsEditorialField
xcodebuild test -project Steps4.xcodeproj -scheme Steps4 -configuration Debug \
  -destination 'platform=iOS Simulator,name=iPhone 17,OS=latest' \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO
xcodebuild build -project Steps4.xcodeproj -scheme Steps4 -configuration Debug \
  -destination 'generic/platform=iOS Simulator' \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO
git diff --check
```

Require no new Metal warnings, unchanged draw count, and no per-object texture/offscreen allocation.

- [ ] **Step 6: Commit Metal transfer separately**

```bash
git add -- \
  StepsTrader/Experiments/DayObjects/DayObjectVisualLanguage.swift \
  StepsTrader/Experiments/DayObjects/DayObjectMotionPlan.swift \
  StepsTrader/Experiments/DayObjects/DayObjectRenderFrame.swift \
  StepsTrader/Metal/DayObjectsActorShader.metal \
  Steps4Tests/DayObjectPaletteTests.swift \
  Steps4Tests/DayObjectRenderFrameTests.swift
git diff --cached --check
git commit -m "feat(day-objects-lab): transfer editorial field to Metal"
```

### Task 6: Pass blind sandbox-to-Metal parity and final Lab integration

**Precondition:** Task 5 tests and simulator build pass. No perceptual golden has changed.

**Files:**
- Modify: `StepsTrader/Experiments/DayObjects/DayObjectsLabView.swift`
- Modify: `Steps4UITests/DayObjectsLabUITests.swift`
- Create: `artifacts/day-objects-editorial-field/metal-parity/$PARITY_COMMIT/`
- Create: `artifacts/day-objects-editorial-field/integration/$INTEGRATION_COMMIT/`
- Modify only after accepted replacement render: `Steps4Tests/DayObjectRenderFrameTests.swift`, which owns `DayObjectsPerceptualBaselines` and transition signatures.

**Interfaces:**
- Produces: matched sandbox/Metal evidence with randomized blind A/B labels.
- Produces: final Lab-only package covering the complete user-required matrix.
- Preserves: the application's main canvas and Gallery selection byte-for-byte unless an existing test fixture records Lab navigation metadata only.

- [ ] **Step 1: Capture matched sandbox and Metal evidence**

For identical seed, actor count, viewport, tile crop, phase, background, sleep, steps, and Reduce Motion, capture 1, 2, 3, 5, 7, and 10 happenings plus insertion/removal. Record renderer versions and every artifact SHA-256.

- [ ] **Step 2: Obtain two independent blind Metal-parity PASS verdicts**

Reject loss of scale hierarchy, position, crop, depth, radial richness, contour identity, transparency, mist texture, halo continuity, or motion character. Pixel equality is not required; semantic and perceptual parity is.

- [ ] **Step 3: Add and run Lab-only UI integration tests**

Assert Day Objects is reachable through Lab, absent from the main Gallery, preserves actor identity during insertion/removal, freezes under Reduce Motion, reproduces the same recipe after relaunch, and exposes full-screen and tile fixture captures.

```bash
xcodebuild test -project Steps4.xcodeproj -scheme Steps4 -configuration Debug \
  -destination 'platform=iOS Simulator,name=iPhone 17,OS=latest' \
  -only-testing:Steps4UITests/DayObjectsLabUITests \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO
```

- [ ] **Step 4: Run the physical-device performance gate**

On a signed physical iPhone build, capture actor draw count, frame time, GPU memory, insertion/removal, normal/low sleep, normal/low steps, and Reduce Motion. Require one instanced actor draw, no per-object texture/offscreen allocation, and no regression beyond the repository's existing Day Objects performance limits.

- [ ] **Step 5: Freeze final integration evidence and obtain two blind PASS verdicts**

The immutable package contains full/tile captures for 1, 2, 3, 5, 7, and 10 happenings; light/dark/saturated/lowContrast; normal/low sleep; low/normal steps; Reduce Motion; insertion/removal; and relaunch proof. Both fresh critics must PASS the same package hash.

- [ ] **Step 6: Update perceptual goldens only if the accepted render requires it**

Before changing any signature, link it to the accepted package artifact and record that mapping in the decision ledger. Stage the exact signature files in a separate commit:

```bash
git diff --check
git add -- Steps4Tests/DayObjectRenderFrameTests.swift
git diff --cached --check
git commit -m "test(day-objects-lab): update approved editorial goldens"
```

If existing goldens still pass or no accepted replacement render exists, skip this commit and leave all goldens unchanged.

- [ ] **Step 7: Commit final Lab integration and evidence**

```bash
PARITY_COMMIT="$(git rev-parse HEAD)"
INTEGRATION_COMMIT="$PARITY_COMMIT"
git add -- \
  StepsTrader/Experiments/DayObjects/DayObjectsLabView.swift \
  Steps4UITests/DayObjectsLabUITests.swift \
  artifacts/day-objects-editorial-field/director/decision-ledger.md \
  "artifacts/day-objects-editorial-field/metal-parity/$PARITY_COMMIT" \
  "artifacts/day-objects-editorial-field/integration/$INTEGRATION_COMMIT"
git diff --cached --check
git commit -m "test(day-objects-lab): freeze editorial field integration"
```

- [ ] **Step 8: Integrate thematic commits into `codex/current-integration` and publish**

Resolve the exact ordered commit list from the accepted branches, apply only those commits to `codex/current-integration`, rerun sandbox tests, the full simulator suite, and `git diff --check`, then push:

```bash
git push origin codex/current-integration
```

Do not include the dirty outline experiment directories, unrelated root checkout changes, losing artist branches, UUID temporary test output, or unapproved artifacts.

## Gate Summary

| Gate | Current status | Opens when |
|---|---|---|
| Visible manifest | PASS | Already frozen |
| Composition | DOUBLE PASS | Already frozen |
| Materials | IN PROGRESS | Outline fixed and two critics PASS the complete material package |
| Motion | BLOCKED BY MATERIAL | Two critics PASS one motion package |
| Held-out | BLOCKED BY MOTION | Two critics PASS all 24 unrevealed fixtures |
| Metal transfer | BLOCKED BY HELD-OUT | Model/GPU tests pass and two critics PASS parity |
| Final integration | BLOCKED BY METAL | UI/performance tests and two critics PASS one final package |

## Effort Forecast

This is a planning range, not a deadline waiver. Visual gates cannot be skipped to meet the range.

| Remaining work | Expected active/runtime range |
|---|---:|
| Outline architecture, render, double critique, material freeze | 3–6 hours |
| Motion implementation, clips, critique loop | 5–9 hours |
| Held-out derivation, 24-fixture render, two critics, schema freeze | 3–5 hours |
| Production model and Metal transfer | 5–9 hours |
| Parity, device/UI integration, final critics, publishing | 4–8 hours |
| **Total remaining** | **20–37 hours** |

With uninterrupted agent work and no critic iteration, the optimistic path is about three long work sessions. A failed motion, held-out, or Metal-parity gate adds a new render-and-critique cycle rather than being waived.

## Plan Self-Review

- Spec coverage: remaining material, all required actor counts and conditions, motion, Reduce Motion, insertion/removal, held-out derivation, schema freeze, model transfer, Metal parity, Lab isolation, performance, goldens, and publishing each map to an explicit task.
- Placeholder scan: implementation steps name concrete files, commands, acceptance behavior, commit boundaries, and task-specific runtime variables produced by prior explicit commands.
- Type consistency: `CompositionRecipe` plus `MaterialDNA` and `ActorMotionRecipe` freeze into `EditorialSceneRecipeV1`; production `DayObjectSceneRecipe` mirrors that schema; the existing Metal instance buffer consumes the production mirror without new randomness.
- Dirty-tree safety: both existing material worktrees and all UUID temporary directories remain untouched; every commit command lists its intended paths and excludes unrelated files.
