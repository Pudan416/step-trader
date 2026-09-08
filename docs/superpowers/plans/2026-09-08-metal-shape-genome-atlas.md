# Metal Shape Genome Atlas Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a new Metal-rendered shape-and-material study above the existing website matrix, combining twelve new closed-contour genome presets with eight curated legacy Metal shapes, plus a deterministic mini scene laboratory that demonstrates compatible combinations.

**Architecture:** Implement a debug-only, isolated `ShapeGenome` experiment beside `DayObjects`, with a CPU reference contour model, a dedicated Metal shader/renderer, a compatibility manifest, and a simulator export route. Exported PNGs and one JSON manifest are the only inputs to a small site module; the browser never reimplements shape, material, or compatibility rules. Insert the new section immediately before `#matrix` and protect the existing matrix block with a byte-level hash check.

**Tech Stack:** Swift 6, SwiftUI, Metal/MetalKit, XCTest, Node.js ES modules, static HTML/CSS/JavaScript, OpenAI Sites hosting.

**Spec:** `docs/superpowers/specs/2026-09-08-metal-shape-genome-atlas-design.md`

## Global Constraints

- Execute app work from `.worktrees/current-integration`, which contains the current Day Objects Metal implementation. It is already dirty: inspect the exact diff before every edit, preserve unrelated changes, and stage only task-owned files and task-owned hunks.
- The site is a nested repository at `.worktrees/current-integration/.sites/nowhere-compositions`. Preserve its existing untracked duplicate PNGs; never bulk-clean, rename, or add them.
- Do not alter the production `DayObjectScene`, daily scheduler, or existing `DayObjectsActorShader.metal` behavior. New code is debug/internal laboratory code until a separate product decision promotes it.
- The existing `<section id="matrix">…</section>` block has SHA-256 `25899d2cd11dbd0789a7b5a8ed8a21ee5d56e5eac23bf03e22d75ea583249021` when sliced from `<section id="matrix"` up to `<div class="notes">`. Keep that byte sequence unchanged.
- Every visible shape/material image in the new section must be a Metal-exported PNG. Browser canvas/SVG/CSS may be used for interface only, never to imitate the art.
- All randomness must be deterministic from an explicit `UInt64`/integer seed.
- Use the available simulator `iPhone 17` with id `00349825-3076-4659-80E4-50B9CFF9090F` for repeatable commands.
- Commit app changes in the outer repository and site changes in the nested site repository separately. Never stage the outer worktree's unrelated modified files.

---

### Task 1: Lock the preservation boundary and add site test plumbing

**Files:**
- Create: `.worktrees/current-integration/.sites/nowhere-compositions/test/legacy-matrix.test.mjs`
- Create: `.worktrees/current-integration/.sites/nowhere-compositions/test/helpers.mjs`
- Modify: `.worktrees/current-integration/.sites/nowhere-compositions/package.json`

- [ ] Record the current nested-site status and diff before editing:

```bash
git -C .worktrees/current-integration/.sites/nowhere-compositions status --short
git -C .worktrees/current-integration/.sites/nowhere-compositions diff -- index.html build.mjs package.json
```

- [ ] Write the failing preservation test. `helpers.mjs` must export `sliceLegacyMatrix(html)` using the two fixed delimiters from Global Constraints. The test must hash that exact slice and compare it to the approved digest.

```js
import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { readFileSync } from 'node:fs';
import { sliceLegacyMatrix } from './helpers.mjs';

const html = readFileSync(new URL('../index.html', import.meta.url), 'utf8');
const digest = createHash('sha256').update(sliceLegacyMatrix(html)).digest('hex');
assert.equal(digest, '25899d2cd11dbd0789a7b5a8ed8a21ee5d56e5eac23bf03e22d75ea583249021');
```

- [ ] Add `"test": "node --test test/*.test.mjs"` to `package.json` and run `npm test`. Expected: failure because `helpers.mjs` has not yet implemented the delimiter extraction.

- [ ] Implement `sliceLegacyMatrix`, including explicit errors when either delimiter is missing or reversed. Run `npm test`. Expected: pass.

- [ ] Commit only the three site test-plumbing files:

```bash
git -C .worktrees/current-integration/.sites/nowhere-compositions add package.json test/helpers.mjs test/legacy-matrix.test.mjs
git -C .worktrees/current-integration/.sites/nowhere-compositions commit -m "test: protect the legacy composition matrix"
```

### Task 2: Define the shape genome, materials, roles, and exact catalog

**Files:**
- Create: `.worktrees/current-integration/StepsTrader/Experiments/ShapeGenome/MetalShapeGenome.swift`
- Create: `.worktrees/current-integration/StepsTrader/Experiments/ShapeGenome/MetalShapeGenomeCatalog.swift`
- Create: `.worktrees/current-integration/Steps4Tests/MetalShapeGenomeCatalogTests.swift`
- Modify: `.worktrees/current-integration/Steps4.xcodeproj/project.pbxproj`

- [ ] Add tests for stable IDs, catalog counts, group counts, closed-contour parameter bounds, and exact legacy selection. The catalog must contain these twelve new IDs:

```swift
[
  "genome.soft-orbit", "genome.soft-drift", "genome.soft-cell",
  "genome.lobed-triad", "genome.lobed-quartet", "genome.lobed-penta",
  "genome.folded-rosette-5", "genome.folded-rosette-7", "genome.folded-rosette-9",
  "genome.crystal-4", "genome.crystal-6", "genome.crystal-8",
]
```

The exact eight legacy IDs and old matrix coordinates are:

```swift
[
  ("legacy.circle", shape: 0, variant: 1),
  ("legacy.soft-square", shape: 6, variant: 17),
  ("legacy.rounded-triangle", shape: 5, variant: 5),
  ("legacy.rounded-pentagon", shape: 5, variant: 7),
  ("legacy.rounded-hexagon", shape: 5, variant: 8),
  ("legacy.star-3-shallow", shape: 4, variant: 1),
  ("legacy.star-4-moderate", shape: 4, variant: 6),
  ("legacy.star-5-restrained", shape: 4, variant: 3),
]
```

- [ ] Run the focused test and confirm a compile failure for missing symbols:

```bash
cd .worktrees/current-integration
xcodebuild test -project Steps4.xcodeproj -scheme Steps4 -configuration Debug \
  -destination 'platform=iOS Simulator,id=00349825-3076-4659-80E4-50B9CFF9090F' \
  -only-testing:Steps4Tests/MetalShapeGenomeCatalogTests \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO
```

- [ ] Implement the domain model without importing SwiftUI or Metal:

```swift
struct MetalShapeGenome: Codable, Equatable, Sendable {
    let superformula: SIMD4<Float>   // m, n1, n2, n3
    let harmonics: [MetalShapeHarmonic] // maximum 3, frequencies 2...12
    let anisotropy: SIMD2<Float>
    let centerOffset: SIMD2<Float>
    let rotation: Float
}

enum MetalShapeMaterial: String, Codable, CaseIterable, Sendable {
    case solid, sideLight, contour, directionalBlur, radialTwo, radialThree
    case proceduralLight, proceduralFlow, proceduralContour, eclipseGlow
}

enum MetalShapeRole: String, Codable, CaseIterable, Sendable {
    case primary, supporting, accent
}
```

`MetalShapePreset` must include `id`, Russian `title`, `source` (`genome` or `legacy`), morphology group, genome or legacy descriptor, and compatibility policy. Use fixed numeric parameters in source, not generated-at-runtime catalog entries.

- [ ] Register the two app files and test file in `project.pbxproj`, using unique 24-character uppercase hex IDs and the existing Day Objects group/target patterns.

- [ ] Run the focused test again. Expected: pass with 20 presets, 12 new + 8 legacy, and 10 material cases.

- [ ] Commit only the new model/catalog/test files and the necessary project-file hunks:

```bash
git add StepsTrader/Experiments/ShapeGenome/MetalShapeGenome.swift \
  StepsTrader/Experiments/ShapeGenome/MetalShapeGenomeCatalog.swift \
  Steps4Tests/MetalShapeGenomeCatalogTests.swift Steps4.xcodeproj/project.pbxproj
git commit -m "feat: define the Metal shape genome catalog"
```

### Task 3: Implement and test the closed-contour reference evaluator

**Files:**
- Create: `.worktrees/current-integration/StepsTrader/Experiments/ShapeGenome/MetalShapeContour.swift`
- Create: `.worktrees/current-integration/Steps4Tests/MetalShapeContourTests.swift`
- Modify: `.worktrees/current-integration/Steps4.xcodeproj/project.pbxproj`

- [ ] Write tests that sample every genome at 2,048 evenly spaced angles and assert: finite points, seam error below `1e-4`, positive radius, normalized reach in `0.72...1.28`, no adjacent radius jump over `0.16`, and deterministic equality for the same preset/seed.

- [ ] Add a rejection test for self-intersection using non-adjacent segment pairs after sampling 512 points. All twelve curated genomes must pass.

- [ ] Run `MetalShapeContourTests`. Expected: compile failure because the evaluator is absent.

- [ ] Implement the CPU reference formula used to validate the shader:

```swift
static func radius(angle theta: Float, genome: MetalShapeGenome) -> Float {
    let m = genome.superformula.x
    let n1 = genome.superformula.y
    let n2 = genome.superformula.z
    let n3 = genome.superformula.w
    let a = pow(abs(cos(m * theta / 4)), n2)
    let b = pow(abs(sin(m * theta / 4)), n3)
    let base = pow(max(a + b, 1e-5), -1 / n1)
    let modulation = genome.harmonics.reduce(Float(1)) {
        $0 + $1.amplitude * cos(Float($1.frequency) * theta + $1.phase)
    }
    return base * modulation
}
```

Apply anisotropy, center offset, rotation, and catalog normalization after radius evaluation. Clamp unsafe imported values, but curated presets must pass without clamping.

- [ ] Run the focused tests. Expected: pass.

- [ ] Commit the evaluator and tests with the project registration:

```bash
git add StepsTrader/Experiments/ShapeGenome/MetalShapeContour.swift \
  Steps4Tests/MetalShapeContourTests.swift Steps4.xcodeproj/project.pbxproj
git commit -m "feat: evaluate deterministic closed shape contours"
```

### Task 4: Add the isolated Metal renderer and ten material programs

**Files:**
- Create: `.worktrees/current-integration/StepsTrader/Experiments/ShapeGenome/MetalShapeGenomeRenderer.swift`
- Create: `.worktrees/current-integration/StepsTrader/Experiments/ShapeGenome/MetalShapeGenomeFrame.swift`
- Create: `.worktrees/current-integration/StepsTrader/Metal/MetalShapeGenomeShader.metal`
- Create: `.worktrees/current-integration/Steps4Tests/MetalShapeGenomeFrameTests.swift`
- Modify: `.worktrees/current-integration/Steps4.xcodeproj/project.pbxproj`

- [ ] Write ABI/layout tests for `MetalShapeGenomeUniforms` and `MetalShapeMaterialUniforms`, plus material sanitization tests. Keep each struct 16-byte aligned and assert exact `MemoryLayout.stride` values in both Swift constants and tests.

- [ ] Write frame tests proving the same `(shapeID, material, seed)` yields equal uniforms, different seeds stay inside declared bounds, and legacy descriptors are converted into the same normalized contour payload used by genome presets.

- [ ] Run `MetalShapeGenomeFrameTests`. Expected: missing-type failure.

- [ ] Implement a dedicated renderer with `MTLCreateSystemDefaultDevice`, an offscreen BGRA8-sRGB texture, one fullscreen quad, and two passes: body/material and separable halo/blur composite. Do not modify `DayObjectsRenderer`.

```swift
enum MetalShapeGenomeRenderer {
    static func image(
        preset: MetalShapePreset,
        material: MetalShapeMaterial,
        seed: UInt64,
        size: CGSize,
        scale: CGFloat
    ) async throws -> UIImage
}
```

- [ ] In the shader, implement one signed boundary function for all new genomes and a legacy adapter for the eight curated old forms. Feed both into the same anti-aliasing, palette, scale, and material pipeline.

- [ ] Implement the ten materials with these invariants:

  - `solid`: dense but not clipped flat color;
  - `sideLight`: directional edge-to-edge lighting, preserved as a core signature;
  - `contour`: hollow center and crisp non-glowing line;
  - `directionalBlur`: one sharp edge and one continuous dissolving wake;
  - `radialTwo` / `radialThree`: two/three controlled radial color stops;
  - `proceduralLight`: two or three broad low-frequency light fields;
  - `proceduralFlow`: wide warped ribbons with negative space, with selected seeds using translucent overlapping shells rather than a dense fill;
  - `proceduralContour`: nested distance bands or one seed-driven continuous line following the boundary, always leaving visible negative space;
  - `eclipseGlow`: restrained dark core with a strong external halo composited behind it.

- [ ] Implement focused directional-blur modes as an internal shader enum: `smoothWake`, `ribbedWake`, `chromaticSplit`, `curvedWake`. The main table always exports `smoothWake`; the other three export only for the focused study.

- [ ] Run the focused tests and build the app. Expected: all pass/compile.

```bash
xcodebuild test -project Steps4.xcodeproj -scheme Steps4 -configuration Debug \
  -destination 'platform=iOS Simulator,id=00349825-3076-4659-80E4-50B9CFF9090F' \
  -only-testing:Steps4Tests/MetalShapeGenomeFrameTests \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO
```

- [ ] Commit the isolated renderer, shader, tests, and project registration.

### Task 5: Encode compatibility and deterministic scene grammar

**Files:**
- Create: `.worktrees/current-integration/StepsTrader/Experiments/ShapeGenome/MetalShapeCompatibility.swift`
- Create: `.worktrees/current-integration/StepsTrader/Experiments/ShapeGenome/MetalShapeScenePlanner.swift`
- Create: `.worktrees/current-integration/Steps4Tests/MetalShapeCompatibilityTests.swift`
- Create: `.worktrees/current-integration/Steps4Tests/MetalShapeScenePlannerTests.swift`
- Modify: `.worktrees/current-integration/Steps4.xcodeproj/project.pbxproj`

- [ ] Test that every preset has a non-empty allowed-material set, at least one preferred material, at least one role, a valid size range, positive `maxInstances`, and bounded complexity/mass/footprint values.

- [ ] Test 1,000 seeds for the scene rules: exactly one primary; no more than two shapes from one morphology group; no more than one directional blur; no more than one eclipse; no more than two high-complexity interiors; at least one hollow material for scenes of four or more; no expanded footprints outside the canvas safe area.

- [ ] Run both focused test classes. Expected: missing-type failure.

- [ ] Implement compatibility as the single source of truth:

```swift
struct MetalShapeCompatibility: Codable, Equatable, Sendable {
    let preferred: Set<MetalShapeMaterial>
    let allowed: Set<MetalShapeMaterial>
    let roles: Set<MetalShapeRole>
    let sizeRange: ClosedRange<Float>
    let maxInstances: Int
    let complexity: Float
    let visualMass: Float
    let haloFootprint: Float
    let blurFootprint: Float
}
```

Prohibited materials are derived as `allCases - allowed`; never maintain a second conflicting list.

- [ ] Implement `MetalShapeScenePlanner.make(seed:count:)` for counts 1...6. Use deterministic weighted selection that prefers `preferred`, accounts for role, and rejects candidates whose actual halo/blur-expanded footprint violates spacing.

- [ ] Run the focused tests. Expected: pass.

- [ ] Commit the compatibility and scene grammar slice.

### Task 6: Build the debug-only native laboratory

**Files:**
- Create: `.worktrees/current-integration/StepsTrader/Experiments/ShapeGenome/MetalShapeGenomeView.swift`
- Create: `.worktrees/current-integration/StepsTrader/Experiments/ShapeGenome/MetalShapeGenomeLabView.swift`
- Create: `.worktrees/current-integration/Steps4UITests/MetalShapeGenomeLabUITests.swift`
- Modify: `.worktrees/current-integration/StepsTrader/Experiments/ExperimentalLabRoute.swift`
- Modify: `.worktrees/current-integration/Steps4.xcodeproj/project.pbxproj`

- [ ] Add a UI test launching `-uiLab shapeGenome` and asserting the lab exposes: seed control, scene, morphology/source/role/material filters, shape grid, and material grid with accessibility identifiers.

- [ ] Run the UI test. Expected: failure because `shapeGenome` is not a route.

- [ ] Add `case shapeGenome` to `ExperimentalLabRoute` and map it to `MetalShapeGenomeLabView()` under the existing debug guard.

- [ ] Implement the lab as a compact working surface: mini scene first, shared seed controls, then the 20-row compatibility matrix. Incompatible combinations show a quiet em dash and are not passed to the renderer. A disclosure below the matrix shows the four directional-blur variants.

- [ ] Make all images accessible by shape title + material title; expose selection state and retain usability at Dynamic Type accessibility sizes.

- [ ] Run the focused UI test. Expected: pass.

- [ ] Commit the native laboratory slice.

### Task 7: Add a deterministic simulator export harness and manifest

**Files:**
- Create: `.worktrees/current-integration/StepsTrader/Experiments/ShapeGenome/MetalShapeAtlasExport.swift`
- Create: `.worktrees/current-integration/StepsTrader/Experiments/ShapeGenome/MetalShapeAtlasExportView.swift`
- Create: `.worktrees/current-integration/scripts/export-metal-shape-atlas.sh`
- Create: `.worktrees/current-integration/Steps4Tests/MetalShapeAtlasManifestTests.swift`
- Modify: `.worktrees/current-integration/StepsTrader/Experiments/ExperimentalLabRoute.swift`
- Modify: `.worktrees/current-integration/Steps4.xcodeproj/project.pbxproj`

- [ ] Test the Codable manifest schema and exact inventory. It must contain catalog version `1`, the exact shared seed bank `[42, 314, 2718]`, 20 shapes, 10 materials, compatibility/role metadata, one path per allowed table cell and seed, four scene PNG paths per seed, and the four focused blur paths for seed 42.

```swift
struct MetalShapeAtlasManifest: Codable, Equatable, Sendable {
    let version: Int
    let seeds: [UInt64]
    let shapes: [MetalShapeAtlasShapeRecord]
    let materials: [MetalShapeAtlasMaterialRecord]
    let scenes: [MetalShapeAtlasSceneRecord]
    let blurStudy: [MetalShapeAtlasImageRecord]
}
```

- [ ] Run `MetalShapeAtlasManifestTests`. Expected: missing-type failure.

- [ ] Implement `-uiLab shapeGenomeExport`. It renders every allowed matrix cell for shared seeds 42, 314, and 2718 at 768×768 pixels, four 1200×900 scene images per seed, and four 1200×900 blur images for seed 42 into the app Documents directory `MetalShapeAtlasExport/`, then writes `manifest.json` last as the completion marker. Use atomic file replacement and delete only that exact export subdirectory before a run.

- [ ] Implement the host script to: build for the fixed simulator; boot it if needed; install `Nowhere.app`; launch `personal-project.StepsTrader` with export arguments; poll no longer than 60 seconds for `manifest.json`; resolve the app data container with `simctl get_app_container`; validate expected files; copy only `MetalShapeAtlasExport` to a caller-supplied destination.

- [ ] Run the focused test, then the exporter to a temporary directory. Expected: test passes and two identical seed-42 runs produce identical manifest bytes and PNG SHA-256 lists.

```bash
tmp_one=$(mktemp -d)
tmp_two=$(mktemp -d)
scripts/export-metal-shape-atlas.sh "$tmp_one"
scripts/export-metal-shape-atlas.sh "$tmp_two"
diff -r "$tmp_one" "$tmp_two"
```

- [ ] Visually inspect a contact sheet made from the exports: all contours closed; no clipping; hollow materials remain hollow; side light reads directionally; eclipse halo is outside/behind the core; blur wake has one sharp edge.

- [ ] Commit the export harness, tests, route changes, and project registration.

### Task 8: Import generated assets into the site without duplicating rules

**Files:**
- Create: `.worktrees/current-integration/.sites/nowhere-compositions/assets/metal-shape-atlas/manifest.json`
- Create: `.worktrees/current-integration/.sites/nowhere-compositions/assets/metal-shape-atlas/**/*.png`
- Create: `.worktrees/current-integration/.sites/nowhere-compositions/scripts/import-metal-shape-atlas.mjs`
- Create: `.worktrees/current-integration/.sites/nowhere-compositions/test/manifest.test.mjs`
- Modify: `.worktrees/current-integration/.sites/nowhere-compositions/package.json`

- [ ] Write the failing Node manifest test: version 1; exact seeds 42/314/2718; 20 unique shape IDs; 12 genome + 8 legacy; 10 material IDs; every referenced PNG exists; prohibited cells have no image for any seed; all image paths stay inside `assets/metal-shape-atlas/`; four scenes per seed and four blur variants exist.

- [ ] Run `npm test`. Expected: failure because the manifest/assets are absent.

- [ ] Implement the import script. It must accept one explicit export directory, validate before changing the site, stage into a temporary sibling directory, then atomically replace only `assets/metal-shape-atlas`. It must not scan or modify existing `expanded-*` assets.

- [ ] Export the approved three-seed bank from Task 7 and import it:

```bash
cd .worktrees/current-integration
export_dir=$(mktemp -d)
scripts/export-metal-shape-atlas.sh "$export_dir"
node .sites/nowhere-compositions/scripts/import-metal-shape-atlas.mjs "$export_dir"
```

- [ ] Run `npm test`. Expected: pass.

- [ ] Commit only `assets/metal-shape-atlas`, the import script, test, and package script. Verify no duplicate legacy assets were accidentally staged with `git diff --cached --name-only`.

### Task 9: Add the new website laboratory above the old matrix

**Files:**
- Create: `.worktrees/current-integration/.sites/nowhere-compositions/metal-shape-atlas.mjs`
- Create: `.worktrees/current-integration/.sites/nowhere-compositions/metal-shape-atlas.css`
- Create: `.worktrees/current-integration/.sites/nowhere-compositions/test/atlas-ui.test.mjs`
- Modify: `.worktrees/current-integration/.sites/nowhere-compositions/index.html`
- Modify: `.worktrees/current-integration/.sites/nowhere-compositions/build.mjs`

- [ ] Write pure-function tests for filtering, compatible-cell projection, deterministic scene selection from manifest data, and graceful error state. Test that generated markup contains no `<canvas>` or inline SVG artwork.

- [ ] Add a structural test asserting `indexOf('id="metal-shape-atlas"') < indexOf('id="matrix"')` and exactly one occurrence of each ID.

- [ ] Run `npm test`. Expected: failure because the module/section do not exist.

- [ ] Insert one new section immediately before the existing `<section id="matrix"...>` without reformatting that line or anything through `<div class="notes">`:

```html
<section id="metal-shape-atlas" class="matrix-section shape-genome-atlas" aria-labelledby="shape-genome-heading">
  <h2 id="shape-genome-heading">Геном форм × материалы</h2>
  <div id="shape-genome-app" aria-live="polite">Загружаются Metal-рендеры…</div>
</section>
```

Add only a stylesheet link in `<head>` and one `type="module"` script after the main content.

- [ ] Implement the site module to fetch `assets/metal-shape-atlas/manifest.json`, render the mini scene laboratory, and render the filtered table. Filters: morphology, source, role, material, shared seed. Use only compatibility records from JSON; incompatible cells render an em dash. Clicking any thumbnail opens the full PNG.

- [ ] Preserve the current site's paper/ink/accent design language. Make the matrix header/first column sticky within its own horizontal scroll region, keep touch targets at least 44px, and show the mini scene in the first viewport of this new section. On narrow screens, filters wrap and the table scrolls horizontally.

- [ ] Render the focused directional-blur variants in a collapsed `<details>` block and explain them with short Russian labels only. Do not expose the internal compatibility algorithm as explanatory prose.

- [ ] Handle manifest/image failure locally: show a concise retryable error inside the new section while the old page remains functional.

- [ ] Update `build.mjs` to copy `metal-shape-atlas.mjs`, `metal-shape-atlas.css`, and the entire validated `assets/metal-shape-atlas` directory. Keep the existing legacy asset filter unchanged for all other assets.

- [ ] Run `npm test && npm run build`. Expected: pass; `dist/` contains the module, CSS, manifest, and all referenced PNGs.

- [ ] Re-run the preservation test and manually compute the legacy matrix digest. Expected: exact approved hash.

- [ ] Commit the website UI slice in the nested repository.

### Task 10: End-to-end validation and visual QA

**Files:**
- Modify only if a verified defect is found in task-owned files from Tasks 2–9.

- [ ] Run all focused app tests together:

```bash
cd .worktrees/current-integration
xcodebuild test -project Steps4.xcodeproj -scheme Steps4 -configuration Debug \
  -destination 'platform=iOS Simulator,id=00349825-3076-4659-80E4-50B9CFF9090F' \
  -only-testing:Steps4Tests/MetalShapeGenomeCatalogTests \
  -only-testing:Steps4Tests/MetalShapeContourTests \
  -only-testing:Steps4Tests/MetalShapeGenomeFrameTests \
  -only-testing:Steps4Tests/MetalShapeCompatibilityTests \
  -only-testing:Steps4Tests/MetalShapeScenePlannerTests \
  -only-testing:Steps4Tests/MetalShapeAtlasManifestTests \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO
```

- [ ] Run the existing Day Objects regression tests most likely to catch ABI/render contamination:

```bash
xcodebuild test -project Steps4.xcodeproj -scheme Steps4 -configuration Debug \
  -destination 'platform=iOS Simulator,id=00349825-3076-4659-80E4-50B9CFF9090F' \
  -only-testing:Steps4Tests/DayObjectRenderFrameTests \
  -only-testing:Steps4Tests/DayObjectSceneTests \
  -only-testing:Steps4Tests/DayObjectPaletteTests \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO
```

- [ ] In the site directory, run `npm test && npm run build`, then start the retained dev server with `npm run dev`.

- [ ] Make one lightweight request to the printed local URL to confirm a 2xx response, then open that URL in the Codex browser panel. Because the user explicitly asked to inspect the site, use browser testing on this existing tab: verify filters, a full-PNG link, narrow layout, error-free console, and keyboard navigation.

- [ ] Compare seed 42 between the native lab and the website: same scene membership, roles, materials, and PNGs. Confirm all 20 shapes appear under “all”; source filters yield 12/8; no prohibited cell contains an image.

- [ ] Confirm the old `#matrix` controls and its 444-cell status still work exactly as before. Re-run its hash test after any QA fix.

- [ ] Inspect repository status in both repos and confirm only task-owned changes are committed; leave all pre-existing unrelated modifications/untracked files untouched.

### Task 11: Publish the updated existing Site

**Files:**
- Read: `.worktrees/current-integration/.sites/nowhere-compositions/.openai/hosting.json`
- Use existing project ID: `appgprj_6a9e95e35b54819198d3b6dc3c215756`

- [ ] Before deployment, load and follow the `sites:sites-hosting` skill in full. Reuse the existing Sites project; do not create a new site or change the public URL.

- [ ] Package the verified `dist` output using the hosting skill's prescribed script/tool flow. Save a new version and deploy it to the existing project.

- [ ] Verify terminal deployment status is successful and open `https://nowhere-composition-atlas.kostill.chatgpt.site/#metal-shape-atlas` in the existing browser tab.

- [ ] Perform a final production smoke check: new study precedes `#matrix`; Metal PNGs load; filters work; legacy matrix hash/content is unchanged; old controls still work.

- [ ] Stop the retained local dev server. Report the unchanged public URL and summarize the new study as “12 new + 8 selected legacy shapes, compatible materials only, Metal-rendered scenes.”

## Completion Criteria

- The public site contains the new Metal Shape Genome section before the old matrix.
- The new catalog includes exactly 12 new and 8 selected legacy forms.
- All ten approved materials exist, while each shape renders only allowed combinations.
- Side light remains prominent; eclipse glow reads as light behind a restrained core; directional blur includes the smooth main version and three focused variants.
- The scene lab obeys every deterministic composition constraint across the test seed sweep.
- The browser consumes exported Metal PNGs and manifest metadata, with no procedural art imitation.
- The legacy matrix byte hash remains `25899d2cd11dbd0789a7b5a8ed8a21ee5d56e5eac23bf03e22d75ea583249021`.
- Focused app tests, Day Objects regressions, site tests, production build, browser QA, and deployment smoke test all pass.
