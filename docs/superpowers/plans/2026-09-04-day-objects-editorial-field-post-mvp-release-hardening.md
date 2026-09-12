# Day Objects Editorial Field Post-MVP Release Hardening Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Turn the user-approved, Lab-only Editorial Field MVP into a release-ready implementation without repeating accepted visual exploration or rebuilding expensive evidence that does not reduce a concrete release risk.

**Architecture:** Treat the visually approved MVP commit as the single aesthetic baseline. Harden it in four layers: unseen-seed reliability, exact sandbox-to-app recipe semantics, bounded Metal/device behavior, and final product regression coverage. User-visible checkpoints replace per-stage double-blind critic loops; heavyweight evidence runs happen once per release candidate and stop on the first actionable failure.

**Tech Stack:** Swift 6, Swift Package Manager, Foundation, CryptoKit, Swift Testing/XCTest, SwiftUI, Metal Shading Language, Xcode simulator, XCTest UI tests, and a signed physical iPhone build.

**Spec:** `docs/superpowers/specs/2026-08-30-day-objects-editorial-field-design.md`

## Global Constraints

- This plan starts only after the user has inspected the MVP contact sheet, motion sample, Reduce Motion sample, and Simulator build and has explicitly approved continuing toward release.
- Day Objects remains Lab-only. The restored main canvas and main Gallery selection must not change.
- The approved composition and material packages remain frozen. Do not rerender their 1×/3× candidate/rerender matrices.
- Maximum actor count remains exactly 10.
- Production retains one instanced actor draw and adds no per-object textures, offscreen passes, or frame-time aesthetic randomness.
- A solid actor remains spatially constant. Multicolor actors use at most three broad radial fields and no linear, angular, conic, pyramidal, Voronoi-like, or hard ownership boundaries.
- Very large foreground actors remain more defocused than the sharpest middle-plane actor.
- Reduce Motion freezes route, depth migration, breathing, and local rotation while preserving the composed frame.
- Retained event identities and their composition, material, and motion recipes remain unchanged across reorder, insertion, and removal.
- Heavy artifact generation runs at most once for a frozen release-candidate commit. A failed run stops for diagnosis and user-visible reporting; it does not automatically start another visual iteration.
- Derived PNGs, clips, and profiler traces stay outside Git unless a task explicitly names a compact release artifact. Git stores manifests, hashes, reports, and only the final user-approved representative images.
- Preserve unrelated dirty files and existing worktrees. Every commit stages only the paths listed in its task.
- Do not update perceptual goldens before the user accepts the corresponding Metal render.
- Double-blind critics, duplicate 1×/3× evidence rerenders, and an exhaustive Cartesian product of all conditions are optional certification work, not release blockers.

## Starting Contract

The implementing agent must resolve the actual MVP commit rather than assuming the historical hashes below are still HEAD. Known pre-MVP anchors are:

- frozen material approval commit lineage: `660f9777`;
- deterministic motion core: `8d166728`;
- motion render adapter: `0632ac14`;
- material approval: `artifacts/day-objects-editorial-field/material/material-approved.json`.

Before Task 1, the MVP is expected to provide:

- an `EditorialSceneRecipeV1` sandbox representation;
- a Lab-only production decoder/mirror;
- the approved Editorial Field materials and motion in the existing instanced Metal renderer;
- a runnable Simulator build;
- a contact sheet, motion sample, and Reduce Motion sample accepted by the user and copied byte-for-byte to:
  - `artifacts/day-objects-editorial-field/mvp/approved/contact-sheet.png`;
  - `artifacts/day-objects-editorial-field/mvp/approved/motion-sample.mp4`;
  - `artifacts/day-objects-editorial-field/mvp/approved/reduce-motion-sample.png`.

If any expected MVP item is absent, stop and return to the MVP prompt. Do not silently expand this release plan to finish the MVP.

## Release Definition

Release hardening is complete when all of the following are true:

1. One frozen release candidate passes a freshly derived 24-fixture held-out corpus without seed substitution.
2. Sandbox JSON and the production model agree on every recipe field for visible and held-out fixtures.
3. A cost-bounded pairwise matrix covers every required actor count and condition in sandbox and Metal.
4. Lab navigation, relaunch determinism, insertion/removal identity, and Reduce Motion pass in UI tests.
5. A signed physical iPhone run sustains the existing 30 FPS target with one instanced actor draw and no new per-object allocation.
6. The user accepts the final Metal contact sheet and motion sample.
7. The full sandbox suite, full Simulator test suite, and Simulator build pass once on the final candidate.

---

### Task 1: Freeze the User-Approved MVP Baseline

**Files:**
- Create: `artifacts/day-objects-editorial-field/release/mvp-approved.json`
- Modify: `artifacts/day-objects-editorial-field/director/decision-ledger.md`

**Interfaces:**
- Consumes: the exact user-approved MVP commit, representative artifact paths, material approval hash, and motion recipe hash.
- Produces: `mvp-approved.json`, the immutable input to every later task.

- [ ] **Step 1: Verify the approved checkout and record its exact commit**

Run from the MVP worktree:

```bash
git status --short
git rev-parse HEAD
git branch --show-current
git diff --check
```

Expected: no unreviewed change under `Tools/DayObjectsEditorialField`, `StepsTrader/Experiments/DayObjects`, `StepsTrader/Metal`, `Steps4Tests`, or `Steps4UITests`. Unrelated dirty paths may remain untouched.

- [ ] **Step 2: Compute the frozen input and preview hashes**

Run:

```bash
MVP_PREVIEW_ROOT="artifacts/day-objects-editorial-field/mvp/approved"
test -f "$MVP_PREVIEW_ROOT/contact-sheet.png"
test -f "$MVP_PREVIEW_ROOT/motion-sample.mp4"
test -f "$MVP_PREVIEW_ROOT/reduce-motion-sample.png"
shasum -a 256 artifacts/day-objects-editorial-field/material/material-approved.json
shasum -a 256 "$MVP_PREVIEW_ROOT/contact-sheet.png"
shasum -a 256 "$MVP_PREVIEW_ROOT/motion-sample.mp4"
shasum -a 256 "$MVP_PREVIEW_ROOT/reduce-motion-sample.png"
```

Expected: every file exists and every command prints one 64-character lowercase SHA-256. Do not create new previews in this step.

- [ ] **Step 3: Write the approval record**

Create `mvp-approved.json` from the inspected checkout and canonical preview paths:

```bash
MVP_COMMIT="$(git rev-parse HEAD)"
MVP_APPROVAL_TIMESTAMP="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
MATERIAL_APPROVAL_PATH="artifacts/day-objects-editorial-field/material/material-approved.json"
MATERIAL_APPROVAL_SHA="$(shasum -a 256 "$MATERIAL_APPROVAL_PATH" | awk '{print $1}')"
CONTACT_SHEET_PATH="artifacts/day-objects-editorial-field/mvp/approved/contact-sheet.png"
CONTACT_SHEET_SHA="$(shasum -a 256 "$CONTACT_SHEET_PATH" | awk '{print $1}')"
MOTION_SAMPLE_PATH="artifacts/day-objects-editorial-field/mvp/approved/motion-sample.mp4"
MOTION_SAMPLE_SHA="$(shasum -a 256 "$MOTION_SAMPLE_PATH" | awk '{print $1}')"
REDUCE_MOTION_SAMPLE_PATH="artifacts/day-objects-editorial-field/mvp/approved/reduce-motion-sample.png"
REDUCE_MOTION_SAMPLE_SHA="$(shasum -a 256 "$REDUCE_MOTION_SAMPLE_PATH" | awk '{print $1}')"
mkdir -p artifacts/day-objects-editorial-field/release
jq -n -S \
  --arg timestamp "$MVP_APPROVAL_TIMESTAMP" \
  --arg commit "$MVP_COMMIT" \
  --arg materialPath "$MATERIAL_APPROVAL_PATH" \
  --arg materialSHA "$MATERIAL_APPROVAL_SHA" \
  --arg contactPath "$CONTACT_SHEET_PATH" \
  --arg contactSHA "$CONTACT_SHEET_SHA" \
  --arg motionPath "$MOTION_SAMPLE_PATH" \
  --arg motionSHA "$MOTION_SAMPLE_SHA" \
  --arg reducePath "$REDUCE_MOTION_SAMPLE_PATH" \
  --arg reduceSHA "$REDUCE_MOTION_SAMPLE_SHA" \
  '{
    approvalTimestampUTC: $timestamp,
    contactSheet: {path: $contactPath, sha256: $contactSHA},
    materialApproval: {path: $materialPath, sha256: $materialSHA},
    motionSample: {path: $motionPath, sha256: $motionSHA},
    reduceMotionSample: {path: $reducePath, sha256: $reduceSHA},
    schemaVersion: "editorial-field-mvp-approval-v1",
    sourceCommit: $commit,
    userDecision: "approved-for-release-hardening"
  }' > artifacts/day-objects-editorial-field/release/mvp-approved.json
```

Expected: sorted JSON with real hashes and a trailing newline.

- [ ] **Step 4: Validate the record without rerendering**

Run:

```bash
jq -e '
  .schemaVersion == "editorial-field-mvp-approval-v1" and
  (.sourceCommit | test("^[0-9a-f]{40}$")) and
  (.contactSheet.sha256 | test("^[0-9a-f]{64}$")) and
  (.motionSample.sha256 | test("^[0-9a-f]{64}$")) and
  (.reduceMotionSample.sha256 | test("^[0-9a-f]{64}$"))
' artifacts/day-objects-editorial-field/release/mvp-approved.json
```

Expected: exit code `0`.

- [ ] **Step 5: Commit the baseline record**

```bash
git add -- \
  artifacts/day-objects-editorial-field/release/mvp-approved.json \
  artifacts/day-objects-editorial-field/director/decision-ledger.md
git diff --cached --check
git commit -m "docs(editorial-field): freeze user-approved Lab MVP"
```

### Task 2: Run One Fresh 24-Fixture Held-Out Reliability Gate

**Files:**
- Modify: `Tools/DayObjectsEditorialField/Sources/EditorialFieldCore/CorpusManifest.swift`
- Modify: `Tools/DayObjectsEditorialField/Sources/editorial-field-corpus/main.swift`
- Create: `Tools/DayObjectsEditorialField/Tests/EditorialFieldCoreTests/HeldOutCorpusTests.swift`
- Create: `artifacts/day-objects-editorial-field/held-out/$RELEASE_COMMIT/manifest.json`
- Create: `artifacts/day-objects-editorial-field/held-out/$RELEASE_COMMIT/report.md`
- Modify: `artifacts/day-objects-editorial-field/director/decision-ledger.md`

**Interfaces:**
- Consumes: the commit and recipe schema recorded by `mvp-approved.json`.
- Produces: `CorpusManifest.heldOut(candidateCommit:nonce:) -> CorpusManifest` with exactly 24 immutable fixtures and no overlap with visible seeds.
- Produces: one compact held-out report and contact sheet for user inspection when an automated guardrail fails.

- [ ] **Step 1: Write the held-out derivation tests**

Add tests that assert:

```swift
@Test("held-out corpus is balanced, disjoint, and byte-stable")
func heldOutCorpusContract() throws {
    let candidate = String(repeating: "a", count: 40)
    let nonce = "00112233445566778899aabbccddeeff"
    let first = try CorpusManifest.heldOut(candidateCommit: candidate, nonce: nonce)
    let second = try CorpusManifest.heldOut(candidateCommit: candidate, nonce: nonce)

    #expect(first == second)
    #expect(first.breadth.count == 24)
    #expect(Dictionary(grouping: first.breadth, by: \.actorCount).mapValues(\.count)
        == [1: 4, 2: 4, 3: 4, 5: 4, 7: 4, 10: 4])
    #expect(Set(first.breadth.map(\.seed)).isDisjoint(with: Set(CorpusManifest.visibleV1().breadth.map(\.seed))))
}
```

Also require rejection of a non-40-character commit, a nonce that is not exactly 32 lowercase hexadecimal characters, omitted fixtures, reordered fixtures, and duplicate seeds.

- [ ] **Step 2: Run the focused test and verify RED**

```bash
swift test --package-path Tools/DayObjectsEditorialField --filter HeldOutCorpusTests
```

Expected: compilation or assertion failure because the held-out API and CLI contract are not fully implemented.

- [ ] **Step 3: Implement deterministic held-out derivation and CLI validation**

Implement:

```swift
public static func heldOut(
    candidateCommit: String,
    nonce: String
) throws -> CorpusManifest
```

Use the existing `SeedDerivation.uniqueSeed` rule. Assign actor counts by the fixed sequence `[1, 2, 3, 5, 7, 10]` repeated four times and assign background, sleep, steps, Reduce Motion, and capture phase by fixed index tables before rendering.

Add CLI forms:

```text
editorial-field-corpus held-out --candidate COMMIT --nonce NONCE --output PATH
editorial-field-corpus verify --manifest PATH
```

- [ ] **Step 4: Prove the focused tests GREEN**

```bash
swift test --package-path Tools/DayObjectsEditorialField --filter HeldOutCorpusTests
swift test --package-path Tools/DayObjectsEditorialField --filter CorpusManifestTests
git diff --check
```

Expected: all commands exit `0`.

- [ ] **Step 5: Commit the held-out derivation implementation**

```bash
git add -- \
  Tools/DayObjectsEditorialField/Sources/EditorialFieldCore/CorpusManifest.swift \
  Tools/DayObjectsEditorialField/Sources/editorial-field-corpus/main.swift \
  Tools/DayObjectsEditorialField/Tests/EditorialFieldCoreTests/HeldOutCorpusTests.swift
git diff --cached --check
git commit -m "test(editorial-field): add release held-out derivation"
```

Expected: `git status --short` contains no uncommitted sandbox source or test change.

- [ ] **Step 6: Freeze the candidate and derive the manifest before rendering**

Run:

```bash
RELEASE_COMMIT="$(git rev-parse HEAD)"
HELDOUT_NONCE="$(openssl rand -hex 16)"
HELDOUT_ROOT="artifacts/day-objects-editorial-field/held-out/$RELEASE_COMMIT"
mkdir -p "$HELDOUT_ROOT"
swift run --package-path Tools/DayObjectsEditorialField editorial-field-corpus \
  held-out --candidate "$RELEASE_COMMIT" --nonce "$HELDOUT_NONCE" \
  --output "$HELDOUT_ROOT/manifest.json"
swift run --package-path Tools/DayObjectsEditorialField editorial-field-corpus \
  verify --manifest "$HELDOUT_ROOT/manifest.json"
shasum -a 256 "$HELDOUT_ROOT/manifest.json"
```

Record the commit, nonce, manifest hash, and timestamp in the decision ledger before any render starts.

- [ ] **Step 7: Render the 24 fixtures exactly once**

Run:

```bash
RELEASE_COMMIT="$(git rev-parse HEAD)"
HELDOUT_ROOT="artifacts/day-objects-editorial-field/held-out/$RELEASE_COMMIT"
MATERIAL_APPROVAL="artifacts/day-objects-editorial-field/material/material-approved.json"
HELDOUT_RENDER_ROOT="/tmp/editorial-field-held-out-$RELEASE_COMMIT"
swift run --package-path Tools/DayObjectsEditorialField editorial-field-render \
  motion --manifest "$HELDOUT_ROOT/manifest.json" \
  --material-approval "$MATERIAL_APPROVAL" \
  --output "$HELDOUT_RENDER_ROOT" \
  --source-commit "$RELEASE_COMMIT"
swift run --package-path Tools/DayObjectsEditorialField editorial-field-render \
  verify-motion --package "$HELDOUT_RENDER_ROOT" \
  --expected-source-commit "$RELEASE_COMMIT" \
  --material-approval "$MATERIAL_APPROVAL"
```

Produce full and production-tile images plus four normalized motion phases for each fixture. Do not create a candidate/rerender duplicate and do not render scale 3 separately.

Expected: 24 fixture records, with no omissions, substitutions, or code changes between manifest freeze and the last render.

- [ ] **Step 8: Evaluate and stop on the first release-relevant failure**

Require the existing automated composition, material, visibility, motion-continuity, and Reduce Motion predicates to pass. If a predicate fails, create `report.md` containing the exact fixture, metric, threshold, contact-sheet path, and one proposed correction; then stop for user direction.

If all predicates pass, record `HELD_OUT_PASS` and the package hash in `report.md`. No independent critic is required.

- [ ] **Step 9: Commit the held-out gate**

```bash
RELEASE_COMMIT="$(git rev-parse HEAD)"
HELDOUT_ROOT="artifacts/day-objects-editorial-field/held-out/$RELEASE_COMMIT"
git add -- \
  artifacts/day-objects-editorial-field/director/decision-ledger.md \
  "$HELDOUT_ROOT/manifest.json" \
  "$HELDOUT_ROOT/report.md"
git diff --cached --check
git commit -m "docs(editorial-field): record release held-out pass"
```

### Task 3: Harden SceneRecipeV1 and Exact Production Decoding

**Files:**
- Modify: `Tools/DayObjectsEditorialField/Sources/EditorialFieldCore/SceneRecipe.swift`
- Modify: `Tools/DayObjectsEditorialField/README.md`
- Modify: `StepsTrader/Experiments/DayObjects/DayObjectSceneRecipe.swift`
- Modify: `StepsTrader/Experiments/DayObjects/DayObjectScene.swift`
- Modify: `Steps4Tests/DayObjectSceneTests.swift`
- Modify: `Steps4Tests/DayObjectChoreographyTests.swift`

**Interfaces:**
- Consumes: the MVP `EditorialSceneRecipeV1` and all visible/held-out fixture recipes.
- Produces: strict schema-version-1 decoding with exact enum raw values, stable actor admission, and no production-side aesthetic reroll.

- [ ] **Step 1: Add canonical sandbox round-trip fixtures**

Add a test that encodes each visible and held-out scene recipe with sorted keys and a trailing newline, decodes it, and requires equality:

```swift
@Test("scene recipe v1 round-trips canonically")
func sceneRecipeV1RoundTrip() throws {
    for recipe in try releaseFixtureRecipes() {
        let bytes = try recipe.canonicalJSON()
        let decoded = try JSONDecoder().decode(EditorialSceneRecipeV1.self, from: bytes)
        #expect(decoded == recipe)
        #expect(decoded.schemaVersion == 1)
    }
}
```

- [ ] **Step 2: Add production decoder rejection and equality tests**

In `DayObjectSceneTests.swift`, decode the same committed JSON fixtures and assert exact event identity, grammar, position, diameter, depth, local blur, crop allowance, draw order, material family, colors, radial fields, blend values, and motion parameters. Require explicit failure for schema versions `0` and `2` and unsupported enum raw values.

- [ ] **Step 3: Run the focused tests and verify RED**

```bash
swift test --package-path Tools/DayObjectsEditorialField --filter SceneRecipe
xcodebuild test -project Steps4.xcodeproj -scheme Steps4 -configuration Debug \
  -destination 'platform=iOS Simulator,name=iPhone 17,OS=latest' \
  -only-testing:Steps4Tests/DayObjectSceneTests \
  -only-testing:Steps4Tests/DayObjectChoreographyTests \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO
```

Expected: at least one strict decoding, unknown-version, or exact-field assertion fails against the MVP implementation.

- [ ] **Step 4: Remove production-side aesthetic fallback**

Make `DayObjectSceneRecipe` the sole source for composition, material, and motion values when the Editorial Field Lab mode is selected. Unsupported schema versions and enum values return a typed decoding error; they must not fall back to legacy random composition or material generation.

Keep the legacy path intact for non-Editorial Lab modes and the main canvas.

- [ ] **Step 5: Prove exact decoding and retained identity GREEN**

Run the focused commands from Step 3 again. Add reorder, insertion, and removal assertions that retained event IDs decode to identical recipe bytes and identical production actor records.

Expected: all focused tests pass and `git diff --check` exits `0`.

- [ ] **Step 6: Commit schema hardening**

```bash
git add -- \
  Tools/DayObjectsEditorialField/Sources/EditorialFieldCore/SceneRecipe.swift \
  Tools/DayObjectsEditorialField/README.md \
  StepsTrader/Experiments/DayObjects/DayObjectSceneRecipe.swift \
  StepsTrader/Experiments/DayObjects/DayObjectScene.swift \
  Steps4Tests/DayObjectSceneTests.swift \
  Steps4Tests/DayObjectChoreographyTests.swift
git diff --cached --check
git commit -m "fix(day-objects-lab): harden editorial recipe decoding"
```

### Task 4: Pass a Cost-Bounded Sandbox-to-Metal Parity Matrix

**Files:**
- Modify: `StepsTrader/Experiments/DayObjects/DayObjectVisualLanguage.swift`
- Modify: `StepsTrader/Experiments/DayObjects/DayObjectMotionPlan.swift`
- Modify: `StepsTrader/Experiments/DayObjects/DayObjectRenderFrame.swift`
- Modify: `StepsTrader/Metal/DayObjectsActorShader.metal`
- Modify: `Steps4Tests/DayObjectPaletteTests.swift`
- Modify: `Steps4Tests/DayObjectRenderFrameTests.swift`
- Create: `artifacts/day-objects-editorial-field/metal-parity/$PARITY_COMMIT/matrix.json`
- Create: `artifacts/day-objects-editorial-field/metal-parity/$PARITY_COMMIT/report.md`

**Interfaces:**
- Consumes: strict `EditorialSceneRecipeV1` fixtures from Task 3.
- Produces: exact CPU/GPU descriptor parity and perceptual sandbox/Metal parity across a 12-case pairwise matrix.

- [ ] **Step 1: Freeze a 12-case pairwise matrix**

Create `matrix.json` from six visible and six held-out fixtures. Across the 12 rows, cover every actor count in `[1, 2, 3, 5, 7, 10]` twice; every background condition; both sleep conditions; both step conditions; Reduce Motion on and off; full and tile viewports; insertion and removal at least once each; and phases `0`, `0.25`, `0.5`, and `0.75`.

The matrix is pairwise coverage, not a Cartesian product. Freeze its SHA-256 before capture.

- [ ] **Step 2: Add CPU/GPU descriptor tests**

For every matrix row, assert:

```swift
XCTAssertLessThanOrEqual(frame.actors.count, 10)
XCTAssertEqual(frame.drawPlan.actorDrawCount, 1)
XCTAssertTrue(frame.actors.allSatisfy { $0.radialFieldCount <= 3 })
XCTAssertEqual(reducedFrame(at: 0), reducedFrame(at: 0.75))
```

Also assert documented Metal offsets and strides, exact supported blend raw values, constant solid color before edge antialiasing, stable event identity, loop closure, local depth blur ordering, and no per-object texture or offscreen target descriptors.

- [ ] **Step 3: Run focused Metal/model tests and verify failures are actionable**

```bash
xcodebuild test -project Steps4.xcodeproj -scheme Steps4 -configuration Debug \
  -destination 'platform=iOS Simulator,name=iPhone 17,OS=latest' \
  -only-testing:Steps4Tests/DayObjectPaletteTests \
  -only-testing:Steps4Tests/DayObjectRenderFrameTests \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO
```

Expected before corrections: any failure names an exact recipe field, ABI offset, fixture, or pixel predicate. Do not tune unrelated visual parameters.

- [ ] **Step 4: Correct only recipe-transfer and Metal-parity defects**

Permit changes only to field packing, raw-value mapping, radial blend implementation, focus ordering, motion parameter transfer, and transition envelopes. Do not retune frozen composition, palette selection, or material DNA.

- [ ] **Step 5: Commit the parity candidate before capture**

```bash
git add -- \
  StepsTrader/Experiments/DayObjects/DayObjectVisualLanguage.swift \
  StepsTrader/Experiments/DayObjects/DayObjectMotionPlan.swift \
  StepsTrader/Experiments/DayObjects/DayObjectRenderFrame.swift \
  StepsTrader/Metal/DayObjectsActorShader.metal \
  Steps4Tests/DayObjectPaletteTests.swift \
  Steps4Tests/DayObjectRenderFrameTests.swift
git diff --cached --check
git commit -m "fix(day-objects-lab): align editorial Metal transfer"
```

Expected: the exact code that will be captured is committed and the relevant source/test paths are clean.

- [ ] **Step 6: Capture matched sandbox and Metal frames once**

Set:

```bash
PARITY_COMMIT="$(git rev-parse HEAD)"
PARITY_ROOT="artifacts/day-objects-editorial-field/metal-parity/$PARITY_COMMIT"
```

Capture each matrix row with identical seed, recipe, viewport, phase, background, sleep, steps, Reduce Motion, and transition state. Store the large PNGs outside Git. Write their paths and SHA-256 values to `report.md` and keep one compact final contact sheet in the release artifacts.

- [ ] **Step 7: Obtain one user-visible parity decision**

Show the paired contact sheet to the user. The decision is one of:

```text
ACCEPT — Metal preserves the approved MVP character.
FIX — one named mismatch must be corrected before release.
```

On `FIX`, perform one scoped correction, rerun the focused tests, and commit it as `fix(day-objects-lab): correct accepted parity mismatch`. Recompute `PARITY_COMMIT` and `PARITY_ROOT`, then recapture only the affected matrix rows into the new commit-named root. A second failure requires a new user decision before more work.

- [ ] **Step 8: Commit accepted parity**

```bash
PARITY_COMMIT="$(git rev-parse HEAD)"
PARITY_ROOT="artifacts/day-objects-editorial-field/metal-parity/$PARITY_COMMIT"
git add -- \
  "$PARITY_ROOT/matrix.json" \
  "$PARITY_ROOT/report.md"
git diff --cached --check
git commit -m "docs(day-objects-lab): accept editorial Metal parity"
```

### Task 5: Verify Lab Isolation, Accessibility, Relaunch, and Device Performance

**Files:**
- Modify: `StepsTrader/Experiments/DayObjects/DayObjectsLabView.swift`
- Modify: `Steps4UITests/DayObjectsLabUITests.swift`
- Modify: `Steps4Tests/RichCanvasLabIsolationTests.swift`
- Create: `artifacts/day-objects-editorial-field/performance/$DEVICE_COMMIT/report.md`

**Interfaces:**
- Consumes: the accepted Metal candidate from Task 4.
- Produces: UI regression proof and one physical-device performance report.

- [ ] **Step 1: Add Lab-only UI tests**

Extend `DayObjectsLabUITests` to assert:

```swift
XCTAssertTrue(app.otherElements["dayObjects.canvas"].waitForExistence(timeout: 5))
XCTAssertFalse(app.otherElements["mainCanvas.editorialField"].exists)
```

Cover actor counts `1`, `3`, `5`, and `10`; full/grid switching; retained identity during insertion/removal; exact Reduce Motion stability; deterministic relaunch; and accessibility labels for the canvas, happenings control, motion control, focus control, grid toggle, and next-day action.

- [ ] **Step 2: Add a main-canvas isolation regression**

In `RichCanvasLabIsolationTests.swift`, assert that the Editorial Field renderer is selected only by the Day Objects Lab launch route and is absent from the main Gallery/catalog selection.

- [ ] **Step 3: Run targeted UI and isolation tests**

```bash
xcodebuild test -project Steps4.xcodeproj -scheme Steps4 -configuration Debug \
  -destination 'platform=iOS Simulator,name=iPhone 17,OS=latest' \
  -only-testing:Steps4UITests/DayObjectsLabUITests \
  -only-testing:Steps4Tests/RichCanvasLabIsolationTests \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO
```

Expected: all tests pass without changing main-canvas snapshots or Gallery selection fixtures.

- [ ] **Step 4: Commit the UI/device candidate before profiling**

```bash
git add -- \
  StepsTrader/Experiments/DayObjects/DayObjectsLabView.swift \
  Steps4UITests/DayObjectsLabUITests.swift \
  Steps4Tests/RichCanvasLabIsolationTests.swift
git diff --cached --check
git commit -m "test(day-objects-lab): harden release UI behavior"
DEVICE_COMMIT="$(git rev-parse HEAD)"
DEVICE_ROOT="artifacts/day-objects-editorial-field/performance/$DEVICE_COMMIT"
mkdir -p "$DEVICE_ROOT"
```

Expected: the profiled product and its UI tests are committed and the relevant paths are clean.

- [ ] **Step 5: Build and profile one signed physical-device candidate**

Use a connected supported iPhone and the project's signed Debug or Release configuration. Exercise 10 actors for 60 seconds in normal motion, low sleep, insertion/removal, and Reduce Motion.

Before profiling, resolve the committed candidate and report root again:

```bash
DEVICE_COMMIT="$(git rev-parse HEAD)"
DEVICE_ROOT="artifacts/day-objects-editorial-field/performance/$DEVICE_COMMIT"
mkdir -p "$DEVICE_ROOT"
```

Record in `$DEVICE_ROOT/report.md`:

- device model and OS;
- source commit;
- actor draw count, required to equal `1`;
- target frame rate, required to equal `30 FPS`;
- p95 frame time, required to be at most `33.3 ms`;
- GPU memory before and during the 10-actor scene;
- confirmation that no per-object texture or offscreen allocation appears;
- insertion/removal and Reduce Motion observations.

If p95 exceeds `33.3 ms` or memory grows continuously during the 60-second run, stop and report the profiler hotspot before changing code.

- [ ] **Step 6: Apply only measured performance corrections**

Allowed corrections are render-activity pausing, buffer reuse, bounded sample counts, and removal of confirmed redundant work. Do not simplify the accepted material or composition unless the user explicitly approves the visible change.

When a correction is necessary, add a focused regression test, commit the correction as `fix(day-objects-lab): remove measured render bottleneck`, recompute `DEVICE_COMMIT` and `DEVICE_ROOT`, and run one final 60-second profile. If the second profile still fails, stop for a new scope and budget decision.

- [ ] **Step 7: Commit the device report**

```bash
DEVICE_COMMIT="$(git rev-parse HEAD)"
DEVICE_ROOT="artifacts/day-objects-editorial-field/performance/$DEVICE_COMMIT"
git add -- \
  "$DEVICE_ROOT/report.md"
git diff --cached --check
git commit -m "docs(day-objects-lab): record device performance"
```

### Task 6: Final User Sign-Off, Regression Run, and Controlled Integration

**Files:**
- Modify only after user acceptance: `Steps4Tests/DayObjectRenderFrameTests.swift`
- Create: `artifacts/day-objects-editorial-field/release/$FINAL_COMMIT/release-report.md`
- Modify: `artifacts/day-objects-editorial-field/director/decision-ledger.md`

**Interfaces:**
- Consumes: held-out PASS, exact schema parity, accepted Metal parity, UI tests, and physical-device report.
- Produces: one final release decision and an ordered integration commit list.

- [ ] **Step 1: Produce one compact final review package**

Create a contact sheet containing the 12 pairwise matrix rows, plus one normal-motion clip and one Reduce Motion frame from the accepted Metal build. Include direct links to the held-out, parity, UI, and performance reports.

Do not regenerate composition/material atlases or duplicate scale packages.

- [ ] **Step 2: Obtain explicit final user sign-off**

Record one of:

```text
RELEASE ACCEPTED — integrate the exact candidate.
RELEASE FIX — correct the single named release blocker.
HOLD — preserve the candidate without integration.
```

Only `RELEASE ACCEPTED` opens the remaining steps.

- [ ] **Step 3: Update perceptual baselines only when they describe the accepted Metal output**

Run the existing perceptual tests first. If they pass, leave `DayObjectsPerceptualBaselines` unchanged. If they fail solely because the accepted Editorial Field output intentionally replaces the previous baseline, update only the affected fixture signatures and record the accepted artifact SHA-256 beside each change in `release-report.md`.

- [ ] **Step 4: Run the complete release verification once**

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

Expected: all commands exit `0`; no new Metal warning; the main canvas and Gallery regressions remain green.

- [ ] **Step 5: Write the release report and exact commit list**

Set `FINAL_COMMIT` to `git rev-parse HEAD`. Record every thematic commit in application order, all gate report hashes, final artifact hashes, test commands, toolchain version, and the user's `RELEASE ACCEPTED` decision in `release-report.md` and the decision ledger.

- [ ] **Step 6: Commit final release metadata**

```bash
FINAL_COMMIT="$(git rev-parse HEAD)"
git add -- \
  artifacts/day-objects-editorial-field/director/decision-ledger.md \
  "artifacts/day-objects-editorial-field/release/$FINAL_COMMIT/release-report.md"
git diff --cached --check
git commit -m "docs(day-objects-lab): record editorial release acceptance"
```

Stage `Steps4Tests/DayObjectRenderFrameTests.swift` in a separate commit only when Step 3 changed approved perceptual signatures.

- [ ] **Step 7: Integrate and publish only with explicit authorization**

Apply the ordered thematic commits to `codex/current-integration`, preserving unrelated dirty files. Re-run the commands from Step 4 in the integration worktree. Push only when the user explicitly authorizes publishing.

## Optional Certification Appendix — Not a Release Blocker

Run these only when the user explicitly asks for the original research-grade evidence standard:

1. Duplicate byte-identical candidate/rerender packages at 1× and 3×.
2. Two fresh blind critics for motion, held-out, Metal parity, and final integration.
3. A complete Cartesian product of actor counts, backgrounds, sleep, steps, phases, viewports, transitions, and Reduce Motion.
4. Archival full-resolution evidence packages with complete per-file cryptographic inventories.

These activities improve auditability and confidence in rare cases, but they do not change the user-approved core design and are deliberately excluded from the default release path.

## Cost-Controlled Effort Forecast

| Stage | Expected active/runtime range |
|---|---:|
| Freeze approved MVP | 0.5–1 hour |
| One held-out run and report | 2–4 hours |
| Schema and production decoding hardening | 2–4 hours |
| Pairwise sandbox/Metal parity | 3–6 hours |
| UI, accessibility, and one device profile | 2–4 hours |
| Final sign-off, full verification, integration | 2–4 hours |
| **Default post-MVP total** | **11.5–23 hours** |

A failed user-visible gate stops the plan instead of automatically consuming another iteration. The optional certification appendix is estimated separately and must not start without a new budget decision.

## Plan Self-Review

- Spec coverage: held-out reliability, versioned recipe semantics, Metal parity, Lab isolation, required actor counts and conditions, Reduce Motion, insertion/removal, device performance, perceptual baselines, and controlled publishing each map to an explicit task.
- Cost control: accepted composition/material work is never rerun; held-out and parity each use one frozen candidate and one bounded matrix; critic loops and duplicate-scale evidence are optional.
- Type consistency: `EditorialSceneRecipeV1` is the sandbox boundary, `DayObjectSceneRecipe` is its strict production mirror, and the Metal frame consumes the production mirror without aesthetic rerolls.
- Dirty-tree safety: every commit lists exact intended paths and excludes unrelated root changes, temporary UUID render directories, and large derived media.
- Placeholder scan: every required task names its files, commands, acceptance result, failure behavior, and commit boundary.
