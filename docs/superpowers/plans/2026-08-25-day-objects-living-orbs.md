# Day Objects Living Orbs Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace clustered, same-colored Day Objects with at most ten stable living procedural orbs whose colors, materials, depth, and slow full-canvas motion vary by happening while the day retains a coherent three-palette visual language.

**Architecture:** First integrate PR #20's persisted modern palette catalog into the current orb branch. Build deterministic daily palette, visual-language, appearance, route, encounter, and depth models above the existing scene root; then upload per-frame pose data and stable per-actor appearance data through two completion-fenced Metal buffers. Render the mesh background once per frame into its own texture, render all six orb materials in one instanced pass (sampling that immutable texture only for glass), then apply sleep-driven global focus and a fixed sharp grain layer.

**Tech Stack:** Swift 6, SwiftUI, Metal/MetalKit, XCTest/XCUITest, Xcode project file source registration, deterministic `SeededRNG`, PR #20 `ModernPaletteCatalog`.

**Spec:** `docs/superpowers/specs/2026-08-25-day-objects-living-orbs-design.md`

## Global Constraints

- One unique happening produces one object; duplicate identifiers do not duplicate objects; maximum active/rendered objects is exactly `10`.
- Every day selects exactly three distinct four-color palettes from the persisted PR #20 category selection: one background palette and two object palettes.
- Object allocation is deterministic and approximately 60/40 between the two object palettes; each actor uses a unique unordered subset of one to three colors from only one object palette.
- Scene, palette, appearance, route, encounter, and depth choices reconstruct identically from the day key, user identity, and stable event identifier.
- Adding or removing an event does not reroll retained actors or restart their insertion envelopes.
- Daily visual language enables three or four of six materials; for four or more actors one material occupies 50...70%, and for eight or more actors at least three materials are represented.
- Orb silhouettes remain circle-derived: sphere, ellipse, softly pinched lens, or soft organic blob; no triangle, petal, slab, shard, or confetti silhouette is permitted.
- At full motion, travel across 20...70% of the usable canvas takes 45...120 seconds; rapid local spinning and permanent central clustering are prohibited.
- At eight or more actors, at least five sectors of the 3x3 occupancy grid are populated in representative frames; UI exclusion and planned negative space remain protected.
- Encounters involve at most four actors, target 15...40% body overlap, remain bounded in time, and separate continuously.
- Sleep controls global `visualClarity`; steps continue to enter only through `motionEnergy`; per-object depth adds local relative softness.
- Reduce Motion freezes route, depth, and material phase while retaining opacity-only insertion/removal.
- Procedural grain is fixed at `0.05`, is applied after blur, and uses no bitmap texture.
- No runtime Color Hunt request, second palette catalog, bitmap material asset, per-actor texture allocation, or per-frame GPU buffer allocation.
- One instanced actor draw covers every material family and uses premultiplied alpha.
- Preserve the existing sRGB drawable configuration and the existing three-slot command-buffer completion fencing.
- A physical iPhone 15 Pro profile is reported only from a signed five-minute device run; if signing/device state blocks it, report the metrics as unmeasured.

---

## File Structure

### New production files

- `StepsTrader/Experiments/DayObjects/DayObjectPaletteSet.swift` — selects and scores the three modern palettes, performs 60/40 palette allocation, and assigns unique 1...3-color subsets.
- `StepsTrader/Experiments/DayObjects/DayObjectVisualLanguage.swift` — declares the six material families, curated material parameter ranges, daily dominant-family distribution, and stable per-event `DayObjectAppearance`.
- `StepsTrader/Experiments/DayObjects/DayObjectMotionPlan.swift` — declares five choreography families, closed long routes, encounter channels, and continuous depth schedules.

### Existing production files to modify

- `StepsTrader/Experiments/DayObjects/ModernPaletteCatalog.swift` — imported from PR #20; remains the only palette catalog.
- `StepsTrader/Experiments/DayObjects/DayObjectTypes.swift` — carries PR #20 category input and adds appearance/route/depth references to each actor.
- `StepsTrader/Experiments/DayObjects/DayObjectScene.swift` — composes the daily palette set, visual language, motion plan, and at most ten actors.
- `StepsTrader/Experiments/DayObjects/DayObjectPalette.swift` — converts selected modern palettes to linear render colors and constructs the background mesh style; removes shared actor radial fill ownership.
- `StepsTrader/Experiments/DayObjects/DayObjectComposition.swift` — replaces central role anchors with distributed sector-safe composition and intentional near-depth crop constraints.
- `StepsTrader/Experiments/DayObjects/DayObjectChoreography.swift` — evaluates long routes, bounded encounters, evolving depth, and exact tangents.
- `StepsTrader/Experiments/DayObjects/DayObjectRenderFrame.swift` — creates compact pose uploads plus stable appearance uploads and separates global from local focus.
- `StepsTrader/Experiments/DayObjects/DayObjectsRenderer.swift` — owns paired pose/appearance buffer rings, binds the immutable background to glass, and preserves one instanced actor pass.
- `StepsTrader/Metal/DayObjectsActorShader.metal` — evaluates all six materials with analytic glow/rim/membrane effects and glass refraction.
- `StepsTrader/Experiments/DayObjects/DayObjectsLabView.swift` — exposes 0...10 happenings and reports the selected palettes/material/choreography language.
- `StepsTrader/AppModel+DailyEnergy.swift`, settings/store/sync files, and `supabase/migrations/20260824220026_add_modern_palette_categories.sql` — imported from PR #20 and retained as the category-selection data path.
- `Steps4.xcodeproj/project.pbxproj` and `Scripts/verify-experiment-scope.sh` — register all imported/new sources exactly once and keep the experiment-scope gate current.

### Test files to modify

- `Steps4Tests/DayObjectPaletteTests.swift` — catalog filtering, three-palette selection, compatibility, 60/40 allocation, unique subsets, material distributions.
- `Steps4Tests/DayObjectSceneTests.swift` — ten-object cap, deduplication, seed stability, relaunch/insertion stability.
- `Steps4Tests/DayObjectChoreographyTests.swift` — full-canvas occupancy, route speed/continuity, encounters, depth, crop, exclusion, Reduce Motion.
- `Steps4Tests/DayObjectRenderFrameTests.swift` — Swift/Metal ABI, pose/appearance upload, all material GPU fixtures, glass/background sampling, blur/grain, transitions, visual matrix.
- `Steps4Tests/PreferencesStoreTests.swift` — PR #20 category persistence, migration, and fallback behavior.
- `Steps4UITests/DayObjectsLabUITests.swift` — 0/1/4/7/10 counts, category-aware lab, Reduce Motion and reviewed captures.

---

### Task 1: Integrate PR #20 Without Regressing the Orb Branch

**Files:**
- Create: `StepsTrader/Experiments/DayObjects/ModernPaletteCatalog.swift`
- Create: `supabase/migrations/20260824220026_add_modern_palette_categories.sql`
- Modify: `Steps4.xcodeproj/project.pbxproj`
- Modify: `Scripts/verify-experiment-scope.sh`
- Modify: `StepsTrader/AppModel+DailyEnergy.swift`
- Modify: `StepsTrader/Experiments/DayObjects/DayObjectPalette.swift`
- Modify: `StepsTrader/Experiments/DayObjects/DayObjectScene.swift`
- Modify: `StepsTrader/Experiments/DayObjects/DayObjectTypes.swift`
- Modify: `StepsTrader/Experiments/DayObjects/DayObjectsLabView.swift`
- Modify: `StepsTrader/Services/SupabaseSyncDTOs.swift`
- Modify: `StepsTrader/Services/SupabaseSyncService+Preferences.swift`
- Modify: `StepsTrader/Services/SupabaseSyncService.swift`
- Modify: `StepsTrader/Stores/PreferencesStore.swift`
- Modify: `StepsTrader/Utilities/SharedKeys.swift`
- Modify: `StepsTrader/Views/Settings/SettingsAppearancePage.swift`
- Test: `Steps4Tests/DayObjectPaletteTests.swift`
- Test: `Steps4Tests/DayObjectRenderFrameTests.swift`
- Test: `Steps4Tests/PreferencesStoreTests.swift`

**Interfaces:**
- Consumes: living-orbs HEAD `a48228a`; PR #20 commit `10457421`.
- Produces: `ModernPaletteCategory`, `ModernPalette`, `ModernPaletteSelection`, `ModernPaletteCatalog`, `DayObjectSceneInput.paletteCategories: Set<ModernPaletteCategory>`, and persisted/synced category selection available from `AppModel`.

- [ ] **Step 1: Record the clean pre-integration baseline**

Run:

```bash
git status --short --branch
xcodebuild -quiet -project Steps4.xcodeproj -scheme Steps4 \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:Steps4Tests test
```

Expected: clean `codex/day-objects-living-orbs`; unit target exits `0`.

- [ ] **Step 2: Cherry-pick PR #20 and stop at conflicts**

Run:

```bash
git cherry-pick 10457421
git status --short
```

Expected: conflicts only in files changed by both the modern-catalog and later orb work; no unrelated file conflict.

- [ ] **Step 3: Resolve overlaps by preserving both contracts**

For `DayObjectTypes.swift`, keep the orb exclusion region and add the category argument exactly as follows:

```swift
struct DayObjectSceneInput: Equatable {
    let dayKey: String
    let identity: String
    let eventIDs: [String]
    let motionEnergy: Double
    let visualClarity: Double
    let reduceMotion: Bool
    let paletteCategories: Set<ModernPaletteCategory>
    let uiExclusionRegion: DayObjectNormalizedRect

    init(
        dayKey: String,
        identity: String,
        eventIDs: [String],
        motionEnergy: Double,
        visualClarity: Double,
        reduceMotion: Bool,
        paletteCategories: Set<ModernPaletteCategory> = ModernPaletteSelection.all,
        uiExclusionRegion: DayObjectNormalizedRect = .dayObjectsLabControls
    )
}
```

For `DayObjectScene.swift`, preserve the orb scene/composition/renderer fields and pass `paletteCategories` through normalization. For `DayObjectPalette.swift`, keep linear-sRGB conversion and mesh-gradient types, but route selection to `ModernPaletteCatalog`. Keep PR #20 settings, store, sync DTO/service, shared key, migration, and localization behavior unchanged.

- [ ] **Step 4: Finish the cherry-pick and verify source registration**

Run:

```bash
git add Scripts Steps4.xcodeproj Steps4Tests StepsTrader supabase
git cherry-pick --continue
python3 - <<'PY'
from pathlib import Path
p = Path('Steps4.xcodeproj/project.pbxproj').read_text()
assert p.count('ModernPaletteCatalog.swift') == 4
PY
bash Scripts/verify-experiment-scope.sh
```

Expected: cherry-pick completes; catalog has one file reference/build-file/source membership tuple; scope script passes.

- [ ] **Step 5: Run focused catalog and persistence tests**

Run:

```bash
xcodebuild -quiet -project Steps4.xcodeproj -scheme Steps4 \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:Steps4Tests/DayObjectPaletteTests \
  -only-testing:Steps4Tests/PreferencesStoreTests test
```

Expected: all selected tests pass; no shared-radial or legacy `GradientPalette` expectation is reintroduced.

- [ ] **Step 6: Verify the cherry-pick produced the integration commit**

```bash
git log -3 --oneline
git status --short --branch
```

Expected: working tree clean; HEAD is the resolved `feat: add selectable modern palette catalog` cherry-pick on top of the living-orbs spec commit.

---

### Task 2: Select Three Daily Palettes and Unique Actor Color Subsets

**Files:**
- Create: `StepsTrader/Experiments/DayObjects/DayObjectPaletteSet.swift`
- Modify: `StepsTrader/Experiments/DayObjects/DayObjectPalette.swift`
- Modify: `Steps4.xcodeproj/project.pbxproj`
- Test: `Steps4Tests/DayObjectPaletteTests.swift`

**Interfaces:**
- Consumes: `ModernPaletteCatalog.all`, `ModernPalette.code`, `ModernPalette.categories`, `DayObjectRGB`, `SeededRNG`.
- Produces:

```swift
enum DayObjectObjectPaletteSlot: UInt32, Equatable { case primary, secondary }

struct DayObjectPaletteSet: Equatable {
    let background: ModernPalette
    let primaryObjects: ModernPalette
    let secondaryObjects: ModernPalette

    static func make(
        rootSeed: UInt64,
        categories: Set<ModernPaletteCategory>
    ) -> DayObjectPaletteSet
}

struct DayObjectColorAssignment: Equatable {
    let paletteSlot: DayObjectObjectPaletteSlot
    let sourceIndices: [Int]
    let colors: [DayObjectRGB]
}

enum DayObjectColorAllocator {
    static func assignments(
        eventIDs: [String],
        rootSeed: UInt64,
        paletteSet: DayObjectPaletteSet
    ) -> [String: DayObjectColorAssignment]
}
```

- [ ] **Step 1: Write failing three-palette and category tests**

Add tests that iterate 128 roots and selected category sets and assert:

```swift
func testDailyPaletteSetUsesThreeDistinctAllowedCatalogEntries() {
    for seed in UInt64(0)..<128 {
        let allowed: Set<ModernPaletteCategory> = [.pastel, .cold]
        let set = DayObjectPaletteSet.make(rootSeed: seed, categories: allowed)
        XCTAssertEqual(Set([set.background.code, set.primaryObjects.code, set.secondaryObjects.code]).count, 3)
        for palette in [set.background, set.primaryObjects, set.secondaryObjects] {
            XCTAssertFalse(palette.categories.isDisjoint(with: allowed))
            XCTAssertEqual(palette.hexes.count, 4)
        }
    }
}

func testEmptyCategorySelectionFallsBackToAllCategories() {
    XCTAssertEqual(
        DayObjectPaletteSet.make(rootSeed: 91, categories: []),
        DayObjectPaletteSet.make(rootSeed: 91, categories: ModernPaletteSelection.all)
    )
}
```

- [ ] **Step 2: Run the tests to verify RED**

Run the focused palette command from Task 1.

Expected: compile failure because `DayObjectPaletteSet` does not exist.

- [ ] **Step 3: Implement independent palette seed domains and compatibility scoring**

In `DayObjectPaletteSet.swift`, filter the catalog by intersection with the normalized allowed categories. Select the background from `"backgroundPalette"`; score every distinct object pair from `"primaryObjectPalette"` and `"secondaryObjectPalette"` using hue-distance, temperature agreement, combined luminance range, and minimum contrast against the background. Sort by `(score descending, primary.code, secondary.code)` so tie-breaking is deterministic. If fewer than three catalog entries survive, take deterministic entries from the full catalog before allowing duplicate codes.

Use these exact internal functions:

```swift
private static func candidates(
    categories: Set<ModernPaletteCategory>
) -> [ModernPalette]

private static func compatibilityScore(
    primary: ModernPalette,
    secondary: ModernPalette,
    background: ModernPalette
) -> Double
```

- [ ] **Step 4: Write failing allocation and unique-subset tests**

```swift
func testObjectPaletteAllocationAndSubsetsAreUniqueForEveryCount() throws {
    let set = DayObjectPaletteSet.make(rootSeed: 44, categories: [.pastel, .cold, .warm])
    for count in 1...10 {
        let ids = (0..<count).map { "event-\($0)" }
        let result = DayObjectColorAllocator.assignments(eventIDs: ids, rootSeed: 44, paletteSet: set)
        XCTAssertEqual(result.count, count)
        XCTAssertEqual(Set(result.values.map { "\($0.paletteSlot.rawValue):\($0.sourceIndices.sorted())" }).count, count)
        XCTAssertTrue(result.values.allSatisfy { (1...3).contains($0.colors.count) })
        let primary = result.values.filter { $0.paletteSlot == .primary }.count
        let secondary = result.values.filter { $0.paletteSlot == .secondary }.count
        XCTAssertEqual([primary, secondary], expectedAllocation(for: count))
    }
}
```

Define the expected allocation table in the test as `[[1,0], [1,1], [2,1], [2,2], [3,2], [4,2], [4,3], [5,3], [5,4], [6,4]]` for counts `1...10`.

- [ ] **Step 5: Run the allocation test to verify RED**

Expected: compile failure because `DayObjectColorAllocator` does not exist.

- [ ] **Step 6: Implement stable palette allocation and the 14 subsets**

Generate subsets in this fixed order, then deterministically permute each palette's list in its own seed domain:

```swift
private static let sourceSubsets: [[Int]] = [
    [0], [1], [2], [3],
    [0,1], [0,2], [0,3], [1,2], [1,3], [2,3],
    [0,1,2], [0,1,3], [0,2,3], [1,2,3],
]
```

Choose each event's slot from a stable ranked event hash while enforcing the count table, then choose an unused subset from that slot using the event seed. When count changes, retained event assignments must be recovered from the same full ten-event deterministic ordering instead of array insertion position.

- [ ] **Step 7: Run focused tests and commit**

```bash
xcodebuild -quiet -project Steps4.xcodeproj -scheme Steps4 \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:Steps4Tests/DayObjectPaletteTests test
git add StepsTrader/Experiments/DayObjects/DayObjectPaletteSet.swift \
  StepsTrader/Experiments/DayObjects/DayObjectPalette.swift \
  Steps4Tests/DayObjectPaletteTests.swift Steps4.xcodeproj/project.pbxproj
git commit -m "feat: assign three daily Day Object palettes"
```

Expected: focused palette suite passes; project source appears once.

---

### Task 3: Build the Daily Visual Language and Per-Event Appearances

**Files:**
- Create: `StepsTrader/Experiments/DayObjects/DayObjectVisualLanguage.swift`
- Modify: `StepsTrader/Experiments/DayObjects/DayObjectTypes.swift`
- Modify: `Steps4.xcodeproj/project.pbxproj`
- Test: `Steps4Tests/DayObjectPaletteTests.swift`
- Test: `Steps4Tests/DayObjectSceneTests.swift`

**Interfaces:**
- Consumes: `DayObjectPaletteSet`, `DayObjectColorAssignment`, `DayObjectShape`, root/event seeds.
- Produces:

```swift
enum DayObjectMaterialFamily: UInt32, CaseIterable, Equatable {
    case satin, innerGlow, rimGlow, glass, membrane, spectral
}

struct DayObjectAppearance: Equatable {
    let colorAssignment: DayObjectColorAssignment
    let material: DayObjectMaterialFamily
    let shape: DayObjectShape
    let focalDistance: Double
    let focalAngle: Double
    let radius: Double
    let falloff: Double
    let mixing: Double
    let distortion: Double
    let distortionShift: Double
    let distortionFrequency: Double
    let innerGlow: Double
    let outerGlow: Double
    let bodyOpacity: Double
    let centerOpacity: Double
    let rimOpacity: Double
    let refractionStrength: Double
    let refractionAngle: Double
    let membraneLayerCount: Int
    let membraneOffsets: SIMD2<Double>
    let localDepthSoftness: Double
    let radialPhase: Double
}

struct DayObjectVisualLanguage: Equatable {
    let paletteSet: DayObjectPaletteSet
    let enabledMaterials: [DayObjectMaterialFamily]
    let dominantMaterial: DayObjectMaterialFamily
    let lightDirection: SIMD2<Double>
    let lightSoftness: Double
    let grainIntensity: Double

    static func make(rootSeed: UInt64, paletteSet: DayObjectPaletteSet) -> Self
    func appearances(eventIDs: [String], rootSeed: UInt64) -> [String: DayObjectAppearance]
}
```

- [ ] **Step 1: Write failing material-family distribution tests**

Test 128 daily roots at counts `1...10`. Assert enabled count is `3...4`, all materials come from the enabled set, the dominant count is within `ceil(0.5*N)...floor(0.7*N)` for `N >= 4`, and at `N >= 8` at least three families appear. Assert `grainIntensity == 0.05` exactly.

- [ ] **Step 2: Run tests to verify RED**

Expected: compile failure for missing `DayObjectVisualLanguage` and `DayObjectAppearance`.

- [ ] **Step 3: Implement curated daily material selection**

Pick enabled families from `"dailyVisualLanguage"`; choose three families for most roots and four for every third root. Assign a deterministic dominant family. Use an event-seed ranking to fill the dominant quota, then round-robin the remaining enabled families so eight actors expose at least three. Do not choose a material from actor count or insertion index.

- [ ] **Step 4: Implement curated per-material appearance ranges**

Use these bounded ranges as the source of truth:

| Family | body alpha | center/rim behavior | distortion | special range |
|---|---:|---|---:|---|
| Satin | 0.78...0.96 | center 0.72...0.95, rim 0.08...0.22 | 0.04...0.18 | mixing 0.55...0.90 |
| Inner Glow | 0.62...0.88 | inner 0.35...0.75, rim 0.04...0.16 | 0.05...0.22 | focal 0.05...0.55 |
| Rim Glow | 0.48...0.78 | center 0.30...0.60, rim 0.35...0.70 | 0.04...0.18 | outer glow 0.10...0.32 |
| Glass | 0.18...0.48 | center 0.12...0.35, rim 0.25...0.55 | 0.02...0.14 | refraction 0.006...0.028 |
| Membrane | 0.32...0.64 | 2...3 layers, rim 0.18...0.45 | 0.06...0.24 | offsets 0.03...0.12 |
| Spectral | 0.50...0.82 | asymmetric center/rim | 0.08...0.30 | mixing 0.65...1.00 |

Clamp non-finite values to the family midpoint. Keep distortion frequency in `2...8`; exclude hard cross-section quantization and banding. Shapes come only from `DayObjectShape.allCases`.

- [ ] **Step 5: Write and run stability/range tests**

Assert the same event's full `DayObjectAppearance` is equal across relaunch, insertion of another ID, and removal of another ID. Assert at least four material families, all four silhouettes, 1/2/3-color objects, transparent objects, inward glow, outward glow, and shifted focal centers appear over a 128-day sample. Run the two focused test files; expected PASS.

- [ ] **Step 6: Commit**

```bash
git add StepsTrader/Experiments/DayObjects/DayObjectVisualLanguage.swift \
  StepsTrader/Experiments/DayObjects/DayObjectTypes.swift \
  Steps4Tests/DayObjectPaletteTests.swift Steps4Tests/DayObjectSceneTests.swift \
  Steps4.xcodeproj/project.pbxproj
git commit -m "feat: generate varied living orb appearances"
```

---

### Task 4: Enforce One Stable Object per Happening and a Ten-Object Scene

**Files:**
- Modify: `StepsTrader/Experiments/DayObjects/DayObjectScene.swift`
- Modify: `StepsTrader/Experiments/DayObjects/DayObjectComposition.swift`
- Modify: `StepsTrader/Experiments/DayObjects/DayObjectTypes.swift`
- Test: `Steps4Tests/DayObjectSceneTests.swift`
- Test: `Steps4Tests/DayObjectRenderFrameTests.swift`

**Interfaces:**
- Consumes: `DayObjectPaletteSet.make`, `DayObjectVisualLanguage.make`, `DayObjectVisualLanguage.appearances`.
- Produces the revised scene and actor ownership:

```swift
struct DayObjectScene: Equatable {
    static let maxActors = 10
    let paletteSet: DayObjectPaletteSet
    let visualLanguage: DayObjectVisualLanguage
    let meshGradientStyle: DayObjectMeshGradientStyle
    let compositionPlan: DayObjectCompositionPlan
    let score: DayObjectChoreographyScore
    let actors: [DayObjectActor]
}

struct DayObjectActor: Equatable {
    let id: DayObjectActorID
    let seed: UInt64
    let appearance: DayObjectAppearance
    let role: DayObjectActorRole
    let sizeBand: DayObjectSizeBand
    let trajectory: DayObjectTrajectory
    let speedRatio: Double
    let phaseOffset: Double
    let zIndex: Double
}
```

- [ ] **Step 1: Replace old 40/flock assumptions with failing ten-object tests**

Add tests for zero, one, ten, eleven, and duplicated IDs. For eleven unique IDs assert only the first ten chronological unique IDs render. Search every test for literal 40-cap fixtures and rename/rewrite capacity scenarios to ten actors plus `event-10` replacements.

Run:

```bash
rg -n "count: 40|event-40|event-41|event-42|maxActors = 40|40-actor" \
  StepsTrader/Experiments/DayObjects Steps4Tests
xcodebuild -quiet -project Steps4.xcodeproj -scheme Steps4 \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:Steps4Tests/DayObjectSceneTests \
  -only-testing:Steps4Tests/DayObjectRenderFrameTests test
```

Expected: RED because production still admits 40 and uses flock-era scene fields.

- [ ] **Step 2: Recompose `DayObjectScene.make` around the new daily models**

Normalize categories, deduplicate chronologically, prefix to ten, then build in this order: root seed, `DayObjectPaletteSet`, background `DayObjectPalette`, `DayObjectMeshGradientStyle`, `DayObjectVisualLanguage`, current composition plan/score, appearances, actors. Delete scene-level `radialFillStyle`; set every `DayObjectActorID.memberIndex` to `0`. Task 5 replaces the temporary legacy trajectory fields with final `DayObjectRoute` and `DayObjectDepthSchedule` values.

- [ ] **Step 3: Preserve capacity-aware transition admission at ten**

Keep `DayObjectInsertionTimeline`'s actor-level FIFO behavior. Change capacity assertions and buffer lengths through `DayObjectScene.maxActors`, then prove a `10 -> 10` replacement remains pending while the departing actor fades and begins its insertion envelope only on its first renderable frame.

- [ ] **Step 4: Run scene and transition groups**

Expected: scene tests and all insertion/removal/re-add/root-reset tests pass; `rg` finds no 40-cap fixture in Day Objects production/tests.

- [ ] **Step 5: Commit**

```bash
git add StepsTrader/Experiments/DayObjects/DayObjectScene.swift \
  StepsTrader/Experiments/DayObjects/DayObjectComposition.swift \
  StepsTrader/Experiments/DayObjects/DayObjectTypes.swift \
  Steps4Tests/DayObjectSceneTests.swift Steps4Tests/DayObjectRenderFrameTests.swift
git commit -m "feat: cap Day Objects at ten stable happenings"
```

---

### Task 5: Replace the Central Cluster with Slow Distributed Motion Plans

**Files:**
- Create: `StepsTrader/Experiments/DayObjects/DayObjectMotionPlan.swift`
- Modify: `StepsTrader/Experiments/DayObjects/DayObjectComposition.swift`
- Modify: `StepsTrader/Experiments/DayObjects/DayObjectChoreography.swift`
- Modify: `StepsTrader/Experiments/DayObjects/DayObjectTypes.swift`
- Modify: `Steps4.xcodeproj/project.pbxproj`
- Test: `Steps4Tests/DayObjectChoreographyTests.swift`

**Interfaces:**
- Consumes: root/event seeds, `DayObjectCompositionPlan.uiExclusionRegion`, circle-derived shader footprint.
- Produces:

```swift
enum DayObjectChoreographyFamily: UInt32, CaseIterable, Equatable {
    case driftField, crossCurrent, tidalSweep, depthMigration, softEncounters
}

struct DayObjectRoute: Equatable {
    let controlPoints: [SIMD2<Double>]
    let period: Double
    let phase: Double
    let direction: Double
    let sector: Int
}

struct DayObjectDepthSchedule: Equatable {
    let baseDepth: Double
    let amplitude: Double
    let period: Double
    let phase: Double
}

struct DayObjectEncounter: Equatable {
    let channel: Int
    let phase: Double
    let durationFraction: Double
    let overlapFraction: Double
}

struct DayObjectMotionPlan: Equatable {
    let family: DayObjectChoreographyFamily
    let routes: [String: DayObjectRoute]
    let depths: [String: DayObjectDepthSchedule]
    let encounters: [String: DayObjectEncounter]

    static func make(rootSeed: UInt64, eventIDs: [String]) -> Self
}

struct DayObjectActor: Equatable {
    let id: DayObjectActorID
    let seed: UInt64
    let appearance: DayObjectAppearance
    let route: DayObjectRoute
    let depthSchedule: DayObjectDepthSchedule
    let encounter: DayObjectEncounter
    let zIndex: Double
}
```

- [ ] **Step 1: Write failing family, route, and occupancy tests**

Replace the dense-overlapping-cluster acceptance with tests over every family and counts `1/4/7/10`. Assert route period `45...120`, sampled travel extent `0.20...0.70` of the usable canvas, both positive and negative travel directions across a ten-actor scene, and at least five occupied 3x3 sectors at representative frames for counts `8...10` over 64 roots.

- [ ] **Step 2: Run choreography tests to verify RED**

Expected: missing `DayObjectMotionPlan` or failures from current central route anchors.

- [ ] **Step 3: Build deterministic closed routes**

Create 4...6 control points from event-local seed domains and evaluate a closed centripetal Catmull-Rom spline. Generate sector choices through a stable nine-sector low-discrepancy permutation derived from the event seed. Apply family transforms:

- `driftField`: independent diagonal/broad curves;
- `crossCurrent`: alternate two counterflow directions;
- `tidalSweep`: broad horizontal or vertical wave with per-event phase;
- `depthMigration`: smaller planar route and larger depth amplitude;
- `softEncounters`: broad routes plus stronger bounded encounter influence.

Do not derive route points, period, phase, or direction from actor array index.

- [ ] **Step 4: Replace chapter/local-spin evaluation**

Make `DayObjectChoreographyScore.pose` evaluate the route spline at `time / period`, compute tangent by a centered finite difference of the final constrained path, align ellipse/lens orientation to tangent, and leave circular bodies unrotated. Remove orbit/spiral/stack chapter movement and old `DayObjectSpin` behavior from the actor model.

- [ ] **Step 5: Preserve safe regions without reintroducing teleports**

Choose the route's safe sector and clearance once per actor/aspect. Continuously scale the route into that clearance; do not pick a nearest projection candidate independently per sample. Allow only near-depth actors to cross a non-UI edge and cap the planned crop at `0.22 * visibleDiameter`; middle/far footprints remain in bounds.

- [ ] **Step 6: Run dense continuity and geometry matrices**

Keep the existing dense derivative checks and add numeric acceptance:

```swift
XCTAssertLessThanOrEqual(maximumAdjacentPositionStep, 0.035)
XCTAssertLessThanOrEqual(maximumAdjacentTangentDelta, 0.65)
XCTAssertGreaterThanOrEqual(occupiedSectors.count, 5)
XCTAssertLessThanOrEqual(intentionalCropFraction, 0.22)
XCTAssertFalse(pose.intersectsUIExclusion)
```

Expected: full `DayObjectChoreographyTests` passes on phone/tablet aspects `0.46, 1, 4/3, 2.16`.

- [ ] **Step 7: Commit**

```bash
git add StepsTrader/Experiments/DayObjects/DayObjectMotionPlan.swift \
  StepsTrader/Experiments/DayObjects/DayObjectComposition.swift \
  StepsTrader/Experiments/DayObjects/DayObjectChoreography.swift \
  StepsTrader/Experiments/DayObjects/DayObjectTypes.swift \
  Steps4Tests/DayObjectChoreographyTests.swift Steps4.xcodeproj/project.pbxproj
git commit -m "feat: choreograph slow full-canvas orb routes"
```

---

### Task 6: Add Bounded Encounters and Continuous Depth

**Files:**
- Modify: `StepsTrader/Experiments/DayObjects/DayObjectMotionPlan.swift`
- Modify: `StepsTrader/Experiments/DayObjects/DayObjectChoreography.swift`
- Modify: `StepsTrader/Experiments/DayObjects/DayObjectRenderFrame.swift`
- Test: `Steps4Tests/DayObjectChoreographyTests.swift`
- Test: `Steps4Tests/DayObjectRenderFrameTests.swift`

**Interfaces:**
- Consumes: `DayObjectEncounter`, `DayObjectDepthSchedule`, route pose.
- Produces revised pose values:

```swift
struct DayObjectPose: Equatable {
    let position: SIMD2<Double>
    let tangent: SIMD2<Double>
    let rotation: Double
    let scale: Double
    let opacity: Double
    let depth: Double
    let depthBand: Int
    let localDepthSoftness: Double
    let materialPhase: Double
    let intentionalCropFraction: Double
    let bodyRadius: Double
    let trailReach: Double
    let footprintHalfExtents: SIMD2<Double>
    let isInsideSafeBounds: Bool
    let intersectsUIExclusion: Bool
    let intersectsNegativeSpace: Bool
}
```

- [ ] **Step 1: Write failing encounter tests**

For deterministic roots that select `softEncounters`, sample full cycles and assert at least one pair reaches `0.15...0.40` normalized overlap, stays together for `0.05...0.18` of the route cycle, then separates; no encounter channel contains more than four actors and no frame has all actors inside one body's diameter.

- [ ] **Step 2: Implement smooth encounter influence**

Use a symmetric smoothstep-in/hold/smoothstep-out envelope. Apply equal and opposite offsets toward a shared meeting point, limited to 18% of each route's local clearance. The base route remains unchanged and event-local; encounter influence is zero outside its window.

- [ ] **Step 3: Write failing depth/focus and Reduce Motion tests**

Assert depth derivative continuity, depth periods `60...140` seconds, near/mid/far representation across ten actors, larger/softer near bodies, smaller/quieter far bodies, and no change in `position`, `depth`, or `materialPhase` between elapsed times when Reduce Motion is enabled.

- [ ] **Step 4: Implement continuous depth mapping**

Evaluate a cosine depth schedule, map it continuously to scale and `localDepthSoftness`, and combine opacity conservatively. In `DayObjectRenderFrame.make`, set `choreographyTime = 0` and material phase `0` under Reduce Motion while still applying insertion/removal opacity envelopes. Do not multiply local depth softness into the global post blur.

- [ ] **Step 5: Run both focused suites and commit**

```bash
xcodebuild -quiet -project Steps4.xcodeproj -scheme Steps4 \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:Steps4Tests/DayObjectChoreographyTests \
  -only-testing:Steps4Tests/DayObjectRenderFrameTests test
git add StepsTrader/Experiments/DayObjects/DayObjectMotionPlan.swift \
  StepsTrader/Experiments/DayObjects/DayObjectChoreography.swift \
  StepsTrader/Experiments/DayObjects/DayObjectRenderFrame.swift \
  Steps4Tests/DayObjectChoreographyTests.swift Steps4Tests/DayObjectRenderFrameTests.swift
git commit -m "feat: add living orb encounters and depth"
```

---

### Task 7: Separate GPU Pose and Appearance ABIs

**Files:**
- Modify: `StepsTrader/Experiments/DayObjects/DayObjectRenderFrame.swift`
- Modify: `StepsTrader/Experiments/DayObjects/DayObjectsRenderer.swift`
- Modify: `StepsTrader/Metal/DayObjectsActorShader.metal`
- Test: `Steps4Tests/DayObjectRenderFrameTests.swift`

**Interfaces:**
- Consumes: `DayObjectAppearance`, `DayObjectPose`.
- Produces exact Swift/Metal layouts:

```swift
struct DayObjectGPUActor: Equatable {
    static let metalAlignment = 16
    static let metalStride = 64
    let position: SIMD2<Float>          // 0...7
    let direction: SIMD2<Float>         // 8...15
    let halfSize: SIMD2<Float>          // 16...23
    private let quadPadding: SIMD2<Float> // 24...31
    let opacity: Float                  // 32...35
    let trailLength: Float              // 36...39
    let shape: UInt32                   // 40...43
    let appearanceIndex: UInt32         // 44...47
    let depth: Float                    // 48...51
    let materialPhase: Float            // 52...55
    let localDepthSoftness: Float       // 56...59
    private let tailPadding: Float      // 60...63
}

struct DayObjectGPUAppearance: Equatable {
    static let metalAlignment = 16
    static let metalStride = 160
    let color0: SIMD4<Float>             // 0...15
    let color1: SIMD4<Float>             // 16...31
    let color2: SIMD4<Float>             // 32...47
    let radial0: SIMD4<Float>             // 48...63
    let radial1: SIMD4<Float>             // 64...79
    let optical0: SIMD4<Float>            // 80...95
    let optical1: SIMD4<Float>            // 96...111
    let membrane: SIMD4<Float>            // 112...127
    let light: SIMD4<Float>               // 128...143
    let metadata: SIMD4<UInt32>           // 144...159
}
```

`metadata` stores material, color count, membrane layer count, and flags. `DayObjectsActorUniforms` shrinks to shared `resolution`, energy normalization, short-side pixels, light direction/softness, and global time; it contains no actor colors or radial preset.

- [ ] **Step 1: Write failing ABI and non-finite tests**

Use `MemoryLayout.offset(of:)`, stride/alignment assertions, and a matching Metal `static_assert`. Construct NaN/infinite pose and appearance values and assert finite bounded GPU fields plus unsupported material fallback to Satin.

- [ ] **Step 2: Run the ABI tests to verify RED**

Expected: old 80-byte actor/shared-radial uniforms fail the new layout.

- [ ] **Step 3: Implement CPU uploads and one-to-one indexing**

Change `DayObjectRenderActor` to carry both `gpuActor` and `gpuAppearance`. Sort the paired records once by depth, then assign `appearanceIndex` after sorting so `actors[index].appearanceIndex == index`. Duplicate an appearance record for a departing actor rather than looking it up by mutable scene index.

- [ ] **Step 4: Mirror structs in Metal and compile**

Define the same 64/160-byte structs in `DayObjectsActorShader.metal`, add static assertions, pass flat `appearanceIndex` through the vertex output, and look up `appearances[appearanceIndex]` in the fragment stage at buffer index `2`. Move shared uniforms to buffer index `3`.

- [ ] **Step 5: Run the ABI/GPU compile tests and commit**

```bash
xcodebuild -quiet -project Steps4.xcodeproj -scheme Steps4 \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:Steps4Tests/DayObjectRenderFrameTests test
git add StepsTrader/Experiments/DayObjects/DayObjectRenderFrame.swift \
  StepsTrader/Experiments/DayObjects/DayObjectsRenderer.swift \
  StepsTrader/Metal/DayObjectsActorShader.metal \
  Steps4Tests/DayObjectRenderFrameTests.swift
git commit -m "feat: upload independent orb appearances"
```

---

### Task 8: Render Six Procedural Orb Materials in One Pass

**Files:**
- Modify: `StepsTrader/Metal/DayObjectsActorShader.metal`
- Modify: `StepsTrader/Experiments/DayObjects/DayObjectsRenderer.swift`
- Test: `Steps4Tests/DayObjectRenderFrameTests.swift`

**Interfaces:**
- Consumes: `DayObjectGPUAppearance`, immutable background texture at fragment texture index `0`, linear sampler at index `0`.
- Produces: one `dayObjectsActorFragment` dispatch covering Satin, Inner Glow, Rim Glow, Glass, Membrane, and Spectral with premultiplied output.

- [ ] **Step 1: Add failing deterministic GPU fixtures for every material**

Render one actor per material against the same non-flat background. Read back center, rim, outside-halo, and overlap samples. Assert:

- Satin is opaque and softly shaded;
- Inner Glow center luminance exceeds its rim;
- Rim Glow rim/halo exceeds its center;
- Glass output changes when only the background changes;
- Membrane produces two or three offset alpha lobes;
- Spectral exposes at least two assigned color regions;
- every output channel is finite and premultiplied (`rgb <= alpha + tolerance` for normalized test colors).

- [ ] **Step 2: Run selected GPU tests to verify RED**

Expected: missing material branches, no background binding, or mismatched readback signatures.

- [ ] **Step 3: Implement shared radial coordinate and bounded distortion**

Create one helper returning radius, angle, focal coordinate, and signed body distance. Use `radial0/radial1` parameters and smooth analytic noise; do not quantize bands. Broaden edge antialiasing by `localDepthSoftness` and attenuate high-frequency distortion as softness increases.

- [ ] **Step 4: Implement the six material branches**

Use a `switch` on the clamped material identifier. Satin blends assigned colors with a broad directional highlight. Inner/Rim Glow use smooth radial masks and an analytic outer halo inside the existing expanded quad. Glass samples `backgroundTexture` at `screenUV + normal * refractionStrength`, mixes the refracted color with assigned tint, and adds a restrained rim. Membrane evaluates up to three shifted radial layers in one fragment. Spectral migrates color stops using focal angle and frozen/stable material phase.

- [ ] **Step 5: Preserve body overlap and remove fast trails**

Keep premultiplied blending. Reduce trail reach/alpha to a soft motion echo and scale it with motion energy; circular objects do not rotate. Ensure glow reach is included in CPU and vertex footprint calculations so analytic halos cannot clip.

- [ ] **Step 6: Bind the immutable background only to the actor fragment stage**

In the existing scene pass:

```swift
sceneEncoder.setFragmentTexture(renderTargets.background, index: 0)
sceneEncoder.setFragmentSamplerState(linearSampler, index: 0)
```

If background creation/sampling is unavailable, set a shared flag that makes Glass execute the Satin fallback without hiding the actor.

- [ ] **Step 7: Run material GPU tests twice and commit**

Expected: both runs produce identical numeric summaries; all six branches are reachable; no Metal warning for unused shape/material constants.

```bash
git add StepsTrader/Metal/DayObjectsActorShader.metal \
  StepsTrader/Experiments/DayObjects/DayObjectsRenderer.swift \
  Steps4Tests/DayObjectRenderFrameTests.swift
git commit -m "feat: render six living orb materials"
```

---

### Task 9: Fence Paired Pose and Appearance Buffers

**Files:**
- Modify: `StepsTrader/Experiments/DayObjects/DayObjectsRenderer.swift`
- Test: `Steps4Tests/DayObjectRenderFrameTests.swift`

**Interfaces:**
- Consumes: `[DayObjectGPUActor]`, `[DayObjectGPUAppearance]`, `DayObjectsInFlightScheduler`.
- Produces:

```swift
final class DayObjectsActorBufferRing {
    struct Lease {
        let slot: Int
        let poseBuffer: MTLBuffer
        let appearanceBuffer: MTLBuffer
    }

    init?(device: MTLDevice, slotCount: Int = 3, actorCapacity: Int)
    func acquire() -> Lease?
    func abandon(_ lease: Lease)
    func submit(_ lease: Lease, on commandBuffer: MTLCommandBuffer)
}
```

- [ ] **Step 1: Write failing paired-buffer ownership tests**

Assert at least three leases expose distinct pose and appearance buffers; a fourth acquire fails while three command buffers are pending; completion releases the whole pair; every pre-submit renderer early return abandons the pair.

- [ ] **Step 2: Run ownership tests to verify RED**

Expected: current lease exposes only `buffer`.

- [ ] **Step 3: Allocate both buffers per slot once**

Allocate `DayObjectGPUActor.metalStride * 10` and `DayObjectGPUAppearance.metalStride * 10` for every slot during renderer creation. Upload both arrays into the acquired lease, bind pose at vertex buffer `1`, appearance at fragment buffer `2`, and shared uniforms at buffer `3`.

- [ ] **Step 4: Run ownership plus real command-buffer integration tests**

Expected: buffers remain occupied until successful/error completion; no render path leaks a slot; repeated frames allocate no additional actor buffers.

- [ ] **Step 5: Commit**

```bash
git add StepsTrader/Experiments/DayObjects/DayObjectsRenderer.swift \
  Steps4Tests/DayObjectRenderFrameTests.swift
git commit -m "fix: fence paired orb upload buffers"
```

---

### Task 10: Preserve Sleep Focus and Fixed Procedural Grain

**Files:**
- Modify: `StepsTrader/Experiments/DayObjects/DayObjectRenderFrame.swift`
- Modify: `StepsTrader/Experiments/DayObjects/DayObjectsRenderer.swift`
- Modify: `StepsTrader/Metal/DayObjectsPostShader.metal`
- Test: `Steps4Tests/DayObjectRenderFrameTests.swift`

**Interfaces:**
- Consumes: global `visualClarity`, pose `localDepthSoftness`, `DayObjectVisualLanguage.grainIntensity`.
- Produces: global post blur unchanged in responsibility; final grain exactly `0.05`; local actor softness already evaluated in the actor shader.

- [ ] **Step 1: Write failing separation tests**

Render the same near/mid/far fixtures at clarity `0`, `0.5`, and `1`. Assert global sharpness increases monotonically with clarity, relative near/far softness remains visible at clarity `1`, and changing motion energy does not change blur. Assert post uniform grain intensity is bitwise `0.05` for every real modern palette luminance.

- [ ] **Step 2: Run tests to verify RED or expose existing behavior**

Expected: any remaining palette-luminance grain attenuation or actor-local blur omission fails.

- [ ] **Step 3: Keep the post order explicit**

Retain scene -> horizontal blur -> vertical blur -> display adjustments -> grain. Remove palette-luminance attenuation from grain. Keep procedural pixel hash stable from root seed plus frozen 12 Hz phase; under Reduce Motion keep phase zero.

- [ ] **Step 4: Run integrated Warp/actors/post readback tests**

Expected: nonblank background at zero actors, monotonic focus at all counts, pixel-sharp grain after maximum blur, and deterministic checksums for repeated fixed-time renders.

- [ ] **Step 5: Commit**

```bash
git add StepsTrader/Experiments/DayObjects/DayObjectRenderFrame.swift \
  StepsTrader/Experiments/DayObjects/DayObjectsRenderer.swift \
  StepsTrader/Metal/DayObjectsPostShader.metal \
  Steps4Tests/DayObjectRenderFrameTests.swift
git commit -m "fix: preserve sleep focus and stable procedural grain"
```

---

### Task 11: Update the Lab, Settings Path, and UI Acceptance

**Files:**
- Modify: `StepsTrader/Experiments/DayObjects/DayObjectsLabView.swift`
- Modify: `StepsTrader/AppModel+DailyEnergy.swift`
- Modify: `StepsTrader/Views/Settings/SettingsAppearancePage.swift`
- Modify: `Steps4UITests/DayObjectsLabUITests.swift`
- Test: `Steps4Tests/PreferencesStoreTests.swift`

**Interfaces:**
- Consumes: persisted `AppModel` modern palette categories, `DayObjectScene.maxActors == 10`, scene `paletteSet`, `visualLanguage`, and `motionPlan`.
- Produces: lab counts `0...10`, category-aware inputs, accessibility diagnostics, and reviewed single/grid captures.

- [ ] **Step 1: Write failing UI assertions for the ten-object contract**

Launch the lab and assert default `8 · 8 figures`, slider maximum produces `10 · 10 figures`, zero produces `0 · 0 figures`, and count changes preserve the canvas element. Add accessibility values for three palette codes, enabled material names, and choreography family so UI tests can prove day changes vary the language without parsing pixels.

- [ ] **Step 2: Run the focused UI test to verify RED**

```bash
xcodebuild -quiet -project Steps4.xcodeproj -scheme Steps4 \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:Steps4UITests/DayObjectsLabUITests test
```

Expected: failure because the current lab has no language diagnostics and still reflects old count assumptions.

- [ ] **Step 3: Pass persisted categories to every production and lab scene input**

Use the same `preferences.modernPaletteCategories` value exposed by PR #20. In previews/tests without a store, use `ModernPaletteSelection.all`. Keep empty selection behavior delegated to `ModernPaletteSelection.decode`.

- [ ] **Step 4: Update lab readouts without redesigning navigation**

Keep the existing controls. Set happenings range to `0...10`. Replace the old composition summary with:

```swift
"\(scene.motionPlan.family) · \(scene.visualLanguage.enabledMaterials.map(\.rawValue).joined(separator: ",")) · \(scene.paletteSet.background.code)/\(scene.paletteSet.primaryObjects.code)/\(scene.paletteSet.secondaryObjects.code)"
```

Expose the same value under `dayObjects.language`.

- [ ] **Step 5: Run store and UI tests, inspect screenshots, and commit**

Inspect zero, single, ten-object, and 3x5 multi-day captures. Reject unreadable controls, central clumps, repeated same-color actors, tiny confetti-like bodies, and rapid blur streaks before accepting the UI test.

```bash
git add StepsTrader/Experiments/DayObjects/DayObjectsLabView.swift \
  StepsTrader/AppModel+DailyEnergy.swift \
  StepsTrader/Views/Settings/SettingsAppearancePage.swift \
  Steps4UITests/DayObjectsLabUITests.swift Steps4Tests/PreferencesStoreTests.swift
git commit -m "feat: expose living orbs in the Day Objects lab"
```

---

### Task 12: Establish the GPU and Perceptual Acceptance Matrix

**Files:**
- Modify: `Steps4Tests/DayObjectRenderFrameTests.swift`
- Modify: `Steps4Tests/DayObjectChoreographyTests.swift`
- Modify: `Steps4UITests/DayObjectsLabUITests.swift`
- Modify only after visual approval: committed perceptual baseline literals inside `Steps4Tests/DayObjectRenderFrameTests.swift`

**Interfaces:**
- Consumes: completed renderer and lab.
- Produces: deterministic numeric summaries and PNG attachments for counts, focus, motion, categories, material families, layouts, and transitions.

- [ ] **Step 1: Replace obsolete 1/10/24/40 matrix fixtures**

Use actor counts `1/4/7/10`, clarity `0/0.5/1`, motion `0/0.55/1`, phone/tablet aspect, Reduce Motion on/off, and light/dark category selections. Cache matching zero-actor background baselines. Verify the painted no-grain frame is nonblank before adding grain and verify every nonzero scene differs from its matching empty baseline.

- [ ] **Step 2: Add material and composition metrics**

For every capture record mean RGB, luminance percentiles/stddev, edge energy, actor ink versus empty background, border peak, UI-exclusion peak, occupied sectors, material counts, palette-slot counts, and unique color-subset count. Fail when any ten-object frame has fewer than five sectors, fewer than three materials, a repeated subset, exclusion intrusion, unintended clipping, or a full-scene pile.

- [ ] **Step 3: Add transition triptychs**

Emit before/during/after PNGs and numeric signatures for insertion, removal, and capped `10 -> 10` replacement. Assert retained actors keep appearance/route hashes; capped replacement stays at ten visible/admitted actors and begins at opacity zero when admitted.

- [ ] **Step 4: Capture RED against intentionally absent new baselines**

Run the focused perceptual tests before adding new signatures.

Expected: failures list the new multi-day/material/motion signatures as unapproved; production transfer and sRGB drawable parity still pass.

- [ ] **Step 5: Export and visually inspect captures**

Export attachments from the `.xcresult`, create contact sheets for phone, tablet, multi-day grid, six materials, and transition triptychs, then inspect full-resolution representatives. Confirm varied sizes/colors/materials, slow distributed motion, readable depth, restrained glow/glass, intentional overlaps, safe crop, and sharp grain.

- [ ] **Step 6: Commit only reviewed perceptual summaries**

Copy the reviewed bounded summary literals into the test file; do not commit raw platform-specific GPU byte hashes or generated PNG artifacts. Re-run the perceptual tests twice from clean DerivedData and require identical summaries within existing tolerances.

- [ ] **Step 7: Commit**

```bash
git add Steps4Tests/DayObjectRenderFrameTests.swift \
  Steps4Tests/DayObjectChoreographyTests.swift \
  Steps4UITests/DayObjectsLabUITests.swift
git commit -m "test: approve living orb visual acceptance"
```

---

### Task 13: Final Verification, Device Installation, and Handoff

**Files:**
- Create: `docs/superpowers/reports/2026-08-25-day-objects-living-orbs-verification.md`
- Modify only if verification exposes a scoped defect: the responsible production/test file from Tasks 1...12, with a fresh RED/GREEN cycle and separate fix commit.

**Interfaces:**
- Consumes: all completed tasks and their focused evidence.
- Produces: clean branch, simulator/full-suite evidence, build/install result, physical profile or an explicit unmeasured status, and exact installation instructions.

- [ ] **Step 1: Run static scope checks**

```bash
git diff --check
bash Scripts/verify-experiment-scope.sh
plutil -lint Steps4.xcodeproj/project.pbxproj
rg -n "GradientPalette|radialFillStyle|maxActors = 40|event-40|count: 40" \
  StepsTrader/Experiments/DayObjects StepsTrader/Metal Steps4Tests Steps4UITests
```

Expected: diff/scope/project checks pass; search returns no placeholder, legacy shared palette/radial owner, or 40-cap fixture in Day Objects scope.

- [ ] **Step 2: Run exact Day Objects suites**

```bash
xcodebuild -quiet -project Steps4.xcodeproj -scheme Steps4 \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:Steps4Tests/DayObjectSceneTests \
  -only-testing:Steps4Tests/DayObjectPaletteTests \
  -only-testing:Steps4Tests/DayObjectChoreographyTests \
  -only-testing:Steps4Tests/DayObjectRenderFrameTests \
  -only-testing:Steps4UITests/DayObjectsLabUITests test
```

Expected: all scoped unit/UI tests pass with zero failures.

- [ ] **Step 3: Run full project tests**

```bash
xcodebuild -quiet -project Steps4.xcodeproj -scheme Steps4 \
  -destination 'platform=iOS Simulator,name=iPhone 17' test
```

Expected: all unit and UI bundles pass; only documented pre-existing skips are allowed.

- [ ] **Step 4: Build the installable app**

```bash
xcodebuild -quiet -project Steps4.xcodeproj -scheme Steps4 \
  -configuration Debug \
  -destination 'platform=iOS Simulator,name=iPhone 17' build
```

Expected: `BUILD SUCCEEDED`, including all Metal shaders.

- [ ] **Step 5: Attempt signed physical-device build, install, and five-minute profile**

Resolve the currently attached iPhone 15 Pro destination with `xcrun devicectl list devices`. Build with that destination, install the resulting `.app` with `xcrun devicectl device install app`, launch the Day Objects lab with ten happenings, and record five minutes with Xcode's available Metal System Trace template. Record presentation rate, frame drops, peak memory, and thermal state. If credentials, provisioning, lock state, or device availability blocks any step, capture the exact command/error and mark all four performance metrics `unmeasured`.

- [ ] **Step 6: Write the verification report**

Include commit list, focused/full counts, build result, capture/contact-sheet locations, manual visual verdict, device identifier/iOS version, install result, physical metrics or unmeasured reason, and any remaining external action required from the user.

- [ ] **Step 7: Request final code review and resolve findings with evidence**

Use `superpowers:requesting-code-review`. For each valid finding, add a focused failing regression, implement the smallest scoped fix, rerun its focused suite, and commit separately. Re-run Steps 1...4 after the final fix.

- [ ] **Step 8: Commit the report and verify clean status**

```bash
git add docs/superpowers/reports/2026-08-25-day-objects-living-orbs-verification.md
git commit -m "docs: report living orb verification"
git status --short --branch
```

Expected: clean `codex/day-objects-living-orbs`; final response includes the exact branch/commit and the Xcode/device installation path.
