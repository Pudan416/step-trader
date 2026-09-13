# Rich Canvas Lab Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build an internal, read-only Rich Canvas Lab that renders the current day's real ten-element canvas with five rich families, six shuffled fills, stable optical composition, animation diagnostics, and no effect on production rendering or persistence.

**Architecture:** Add a separate `StepsTrader/Experiments/RichCanvas` subsystem containing deterministic assignment, optical layout, budgets, geometry, fills, rendering, and the Lab UI. The Lab reads a `DayCanvas` snapshot and draws it through its own `TimelineView`/`Canvas`; the only production integration is a gated navigation row in Appearance settings. Existing `GenerativeCanvasView`, production renderers, `CanvasElement` Codable, sync, history, export, and palette previews remain unchanged.

**Tech Stack:** Swift 6, SwiftUI `Canvas`, `TimelineView`, Core Graphics paths, existing `SeededRNG`, existing `SimplexNoise2D`, XCTest, Xcode project file with explicit source membership.

**Spec:** `docs/superpowers/specs/2026-08-16-rich-canvas-lab-design.md`

## Global Constraints

- Read the spec and inspect `git status --short` before editing.
- The worktree already contains unrelated uncommitted changes. Preserve them.
- Do not modify `CanvasElement` encoding, `CanvasShapeType`, `TextureKind`, production shape renderers, `GenerativeCanvasView`, sync, history, export, thumbnails, or palette previews.
- Do not modify `StepsTrader/Localizable.xcstrings`; internal Lab copy may remain English.
- `SettingsAppearancePage.swift` already has unrelated changes. Stage only the Rich Canvas navigation hunk with `git add -p`.
- New source and test files require explicit `PBXFileReference`, `PBXBuildFile`, group membership, and Sources build-phase entries in `Steps4.xcodeproj/project.pbxproj`.
- Use deterministic `SeededRNG` domains; never use `String.hashValue`, `UUID.hashValue`, or global random APIs.
- Rich Canvas never calls save, sync, thumbnail invalidation, export, or mutation APIs.
- The Lab uses five families and six fills; with ten elements every family and fill appears at least once.
- Shuffle changes only rich family/fill/detail/motion; source colors, labels, positions, and layout footprints stay stable.
- No trails.
- Normal ten-element ceilings: two glow passes, eight contours, eight orbital rings, 24 filaments, one global particle pool, requested 20 FPS.
- Physical-device acceptance target: stable 20 FPS for 30 seconds on iPhone 13.
- Simulator build command:
  `xcodebuild build -project Steps4.xcodeproj -scheme Steps4 -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17,OS=latest' CODE_SIGNING_ALLOWED=NO`
- Unit-test command:
  `xcodebuild test -project Steps4.xcodeproj -scheme Steps4 -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17,OS=latest' -only-testing:Steps4Tests CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO`
- Before every commit, run `git diff --cached --check` and verify `git diff --cached --name-only` contains only files owned by that task.

---

## File Map

### New app files

- `StepsTrader/Utilities/ExperimentalFeatures.swift` — compile-time internal feature gate.
- `StepsTrader/Experiments/RichCanvas/RichFigureModels.swift` — families, fills, detail tiers, immutable style spec, preview item.
- `StepsTrader/Experiments/RichCanvas/RichFigureAssignment.swift` — deterministic deck assignment and Shuffle behavior.
- `StepsTrader/Experiments/RichCanvas/RichFigureLayout.swift` — stable slots, optical coefficients, geometry fitting.
- `StepsTrader/Experiments/RichCanvas/RichRenderBudget.swift` — normal/Low Power limits and phased update timing.
- `StepsTrader/Experiments/RichCanvas/RichRenderCache.swift` — canonical geometry cache, phased buckets, cadence sampling.
- `StepsTrader/Experiments/RichCanvas/RichFigureGeometry.swift` — pure normalized geometry for five families.
- `StepsTrader/Experiments/RichCanvas/RichFillGeometry.swift` — pure fill subgeometry for six fills.
- `StepsTrader/Experiments/RichCanvas/RichFigureRenderer.swift` — materials, family motion, fill drawing, labels, particles.
- `StepsTrader/Experiments/RichCanvas/RichCanvasView.swift` — background, animation host, Canvas, HUD.
- `StepsTrader/Experiments/RichCanvas/RichCanvasLabView.swift` — read-only loading, empty state, Shuffle UI.

### Modified app files

- `StepsTrader/Views/Settings/SettingsAppearancePage.swift` — one gated Rich Canvas navigation section.
- `Steps4.xcodeproj/project.pbxproj` — explicit membership for new app and test files.

### New tests

- `Steps4Tests/RichFigureAssignmentTests.swift`
- `Steps4Tests/RichFigureLayoutTests.swift`
- `Steps4Tests/RichRenderBudgetTests.swift`
- `Steps4Tests/RichFigureGeometryTests.swift`
- `Steps4Tests/RichCanvasLabIsolationTests.swift`

---

### Task 1: Internal gate and deterministic rich style assignment

**Files:**
- Create: `StepsTrader/Utilities/ExperimentalFeatures.swift`
- Create: `StepsTrader/Experiments/RichCanvas/RichFigureModels.swift`
- Create: `StepsTrader/Experiments/RichCanvas/RichFigureAssignment.swift`
- Create: `Steps4Tests/RichFigureAssignmentTests.swift`
- Modify: `Steps4.xcodeproj/project.pbxproj`

**Interfaces:**
- Consumes: `CanvasElement`, `CanvasElement.makeSeed(optionId:dayKey:index:)`, `CanvasElement.stableSeed(for:)`, `SeededRNG`.
- Produces: `ExperimentalFeatures.richCanvasLab`, `RichFigureFamily`, `RichFillKind`, `RichFigureDetailTier`, `RichFigureStyleSpec`, `RichFigurePreviewItem`, `RichFigureAssignment.make(elements:dayKey:shuffleNonce:)`.

- [ ] **Step 1: Register the first new files with the Xcode targets**

Add explicit file references/build files for the three app files and one test file. Place app model/assignment files under a new `RichCanvas` PBX group nested under `StepsTrader`; place the test under `Steps4Tests`. Add app build files only to the `Steps4` Sources phase and the test build file only to `Steps4Tests` Sources.

Verify project syntax before writing code:

```bash
plutil -lint Steps4.xcodeproj/project.pbxproj
xcodebuild -project Steps4.xcodeproj -list
```

Expected: `OK` from `plutil`; `Steps4` and `Steps4Tests` remain listed.

- [ ] **Step 2: Write failing assignment tests**

Create a fixed fixture using explicit UUIDs, dates, colors, seeds, and sizes. Tests must cover deterministic equality, nonce variation, complete ten-item family/fill coverage, color preservation, and stable element keys.

```swift
import XCTest
@testable import Steps4

final class RichFigureAssignmentTests: XCTestCase {
    func testTenElementsCoverEveryFamilyAndFill() {
        let elements = RichAssignmentFixture.elements(count: 10)
        let specs = RichFigureAssignment.make(
            elements: elements,
            dayKey: "2026-08-16",
            shuffleNonce: 0
        )

        XCTAssertEqual(Set(specs.values.map(\.family)), Set(RichFigureFamily.allCases))
        XCTAssertEqual(Set(specs.values.map(\.fill)), Set(RichFillKind.allCases))
    }

    func testSameNonceProducesIdenticalSpecsAndNewNonceChangesBothDecks() {
        let elements = RichAssignmentFixture.elements(count: 10)
        let a = RichFigureAssignment.make(elements: elements, dayKey: "2026-08-16", shuffleNonce: 3)
        let b = RichFigureAssignment.make(elements: elements, dayKey: "2026-08-16", shuffleNonce: 3)
        let c = RichFigureAssignment.make(elements: elements, dayKey: "2026-08-16", shuffleNonce: 4)

        XCTAssertEqual(a, b)
        XCTAssertNotEqual(elements.map { a[$0.id]?.family }, elements.map { c[$0.id]?.family })
        XCTAssertNotEqual(elements.map { a[$0.id]?.fill }, elements.map { c[$0.id]?.fill })
    }

    func testAssignmentPreservesSourceColors() {
        let element = RichAssignmentFixture.elements(count: 1)[0]
        let spec = RichFigureAssignment.make(
            elements: [element], dayKey: "2026-08-16", shuffleNonce: 0
        )[element.id]

        XCTAssertEqual(spec?.primaryHex, element.hexColor)
        XCTAssertEqual(spec?.secondaryHex, element.hexColor2)
    }
}
```

Put the fixture in the same test file. Build `CanvasElement` through its public initializer, use `size = 0.14 + Double(index) * 0.02`, and assign `createdAt` using `Date(timeIntervalSince1970: Double(index))`; use UUID strings ending in a zero-padded index so ordering and size spread are reproducible.

- [ ] **Step 3: Run the test target and verify RED**

```bash
xcodebuild test -project Steps4.xcodeproj -scheme Steps4 \
  -configuration Debug \
  -destination 'platform=iOS Simulator,name=iPhone 17,OS=latest' \
  -only-testing:Steps4Tests/RichFigureAssignmentTests \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO
```

Expected: compile failure because rich model and assignment types are not defined.

- [ ] **Step 4: Implement the internal gate and immutable model**

Use a compile-time gate that is `true` only for Debug or an explicitly flagged internal archive. Do not add `INTERNAL_BUILD` to Release settings globally.

```swift
enum ExperimentalFeatures {
    #if DEBUG || INTERNAL_BUILD
    static let richCanvasLab = true
    #else
    static let richCanvasLab = false
    #endif
}

enum RichFigureFamily: String, CaseIterable, Hashable {
    case circle, luminousOrganic, crystallineStar, rays, orbitalSpirograph
}

enum RichFillKind: String, CaseIterable, Hashable {
    case luminousGradient, nestedContours, orbitalLines
    case filamentField, outlineWithCore, layeredTranslucentMass
}

enum RichFigureDetailTier: Int, Hashable {
    case accent, medium, large
}

struct RichFigureStyleSpec: Hashable {
    let family: RichFigureFamily
    let fill: RichFillKind
    let primaryHex: String
    let secondaryHex: String?
    let geometrySeed: UInt64
    let animationPhase: Double
    let speedMultiplier: Double
    let detailTier: RichFigureDetailTier
    let glowIntensity: Double
    let particleEligible: Bool
}
```

`RichFigurePreviewItem` is `Identifiable` and contains `source: CanvasElement`, `style: RichFigureStyleSpec`, and later receives `layout: RichFigureLayoutSpec` in Task 2.

- [ ] **Step 5: Implement deterministic deck assignment**

Sort elements by `createdAt`, then UUID string. Build repeated decks, shuffle them with independent domains, and repair direct repeats by swapping with the first later different value.

```swift
enum RichFigureAssignment {
    static func make(
        elements: [CanvasElement],
        dayKey: String,
        shuffleNonce: Int
    ) -> [UUID: RichFigureStyleSpec] {
        let ordered = elements.sorted {
            ($0.createdAt, $0.id.uuidString) < ($1.createdAt, $1.id.uuidString)
        }
        let baseSeed = CanvasElement.makeSeed(
            optionId: "rich-lab-\(shuffleNonce)",
            dayKey: dayKey,
            index: ordered.count
        )
        var familyRNG = SeededRNG.derived(from: baseSeed, domain: "richFamily")
        var fillRNG = SeededRNG.derived(from: baseSeed, domain: "richFill")
        let families = repairedDeck(values: RichFigureFamily.allCases, count: ordered.count, using: &familyRNG)
        let fills = repairedDeck(values: RichFillKind.allCases, count: ordered.count, using: &fillRNG)

        let sizeOrdered = ordered.sorted {
            let lhs = Double($0.userSize ?? CGFloat($0.size))
            let rhs = Double($1.userSize ?? CGFloat($1.size))
            return lhs == rhs ? $0.id.uuidString < $1.id.uuidString : lhs < rhs
        }
        let sizeRank = Dictionary(uniqueKeysWithValues:
            sizeOrdered.enumerated().map { ($0.element.id, $0.offset) })

        return Dictionary(uniqueKeysWithValues: ordered.enumerated().map { index, element in
            let seed = element.shapeSeed ?? CanvasElement.stableSeed(for: element.id)
            var motion = SeededRNG.derived(from: seed ^ baseSeed, domain: "richMotion")
            return (element.id, RichFigureStyleSpec(
                family: families[index], fill: fills[index],
                primaryHex: element.hexColor, secondaryHex: element.hexColor2,
                geometrySeed: seed,
                animationPhase: motion.nextDouble(in: 0...(2 * .pi)),
                speedMultiplier: motion.nextDouble(in: 0.75...1.25),
                detailTier: detailTier(index: sizeRank[element.id] ?? index, count: ordered.count),
                glowIntensity: motion.nextDouble(in: 0.55...0.9),
                particleEligible: index % 3 == 0
            ))
        })
    }
}
```

Keep `repairedDeck` generic, deterministic, and private. For counts smaller than the number of cases, it returns a shuffled prefix. For ten elements, deck construction guarantees full coverage before shuffling.

- [ ] **Step 6: Run assignment tests and verify GREEN**

Run the Step 3 command again. Expected: zero failures.

- [ ] **Step 7: Commit Task 1**

```bash
git add StepsTrader/Utilities/ExperimentalFeatures.swift \
  StepsTrader/Experiments/RichCanvas/RichFigureModels.swift \
  StepsTrader/Experiments/RichCanvas/RichFigureAssignment.swift \
  Steps4Tests/RichFigureAssignmentTests.swift \
  Steps4.xcodeproj/project.pbxproj
git diff --cached --check
git commit -m "feat: add deterministic rich canvas styles"
```

---

### Task 2: Stable optical layout and Crystalline Star size normalization

**Files:**
- Create: `StepsTrader/Experiments/RichCanvas/RichFigureLayout.swift`
- Create: `Steps4Tests/RichFigureLayoutTests.swift`
- Modify: `StepsTrader/Experiments/RichCanvas/RichFigureModels.swift`
- Modify: `Steps4.xcodeproj/project.pbxproj`

**Interfaces:**
- Consumes: `RichFigureFamily`, `RichFigureStyleSpec`, `CanvasElement.userSize`, `CanvasElement.size`.
- Produces: `RichFigureLayoutSpec`, `RichFigureLayout.make(elements:styles:)`, `RichFigureLayout.fittedScale(canonicalBounds:targetDiameter:opticalScale:)`, completed `RichFigurePreviewItem`.

- [ ] **Step 1: Register layout source and test files**

Add both files to the correct PBX groups and Sources phases. Run `plutil -lint Steps4.xcodeproj/project.pbxproj`.

- [ ] **Step 2: Write failing layout tests**

```swift
final class RichFigureLayoutTests: XCTestCase {
    func testFootprintsAreStableAcrossShuffle() {
        let elements = RichAssignmentFixture.elements(count: 10)
        let a = RichFigureAssignment.make(elements: elements, dayKey: "2026-08-16", shuffleNonce: 0)
        let b = RichFigureAssignment.make(elements: elements, dayKey: "2026-08-16", shuffleNonce: 9)
        let layoutA = RichFigureLayout.make(elements: elements, styles: a)
        let layoutB = RichFigureLayout.make(elements: elements, styles: b)

        for element in elements {
            let diameterA = try! XCTUnwrap(layoutA[element.id]?.targetDiameterFraction)
            let diameterB = try! XCTUnwrap(layoutB[element.id]?.targetDiameterFraction)
            XCTAssertEqual(diameterA, diameterB, accuracy: 0.000_001)
            XCTAssertEqual(layoutA[element.id]?.center, layoutB[element.id]?.center)
        }
    }

    func testOnlySmallestSlotMayBeBelowMediumFloor() {
        let elements = RichAssignmentFixture.elements(count: 10)
        let styles = RichFigureAssignment.make(elements: elements, dayKey: "2026-08-16", shuffleNonce: 0)
        let values = RichFigureLayout.make(elements: elements, styles: styles)
            .values.map(\.targetDiameterFraction).sorted()
        XCTAssertEqual(try! XCTUnwrap(values.first), 0.19, accuracy: 0.000_001)
        XCTAssertTrue(values.dropFirst().allSatisfy { $0 >= 0.22 && $0 <= 0.34 })
    }

    func testStarOpticalScaleExceedsOrganicScale() {
        XCTAssertGreaterThan(RichFigureLayout.opticalScale(for: .crystallineStar),
                             RichFigureLayout.opticalScale(for: .luminousOrganic))
    }
}
```

- [ ] **Step 3: Run layout tests and verify RED**

Run only `Steps4Tests/RichFigureLayoutTests`. Expected: missing layout types.

- [ ] **Step 4: Implement stable composition slots**

```swift
struct RichFigureLayoutSpec: Equatable {
    let center: CGPoint
    let targetDiameterFraction: CGFloat
    let opticalScale: CGFloat
    let overscanFraction: CGFloat
}

enum RichFigureLayout {
    static func opticalScale(for family: RichFigureFamily) -> CGFloat {
        switch family {
        case .circle: 1.00
        case .luminousOrganic: 0.92
        case .crystallineStar: 1.12
        case .rays: 1.00
        case .orbitalSpirograph: 1.08
        }
    }

    static func fittedScale(
        canonicalBounds: CGRect,
        targetDiameter: CGFloat,
        opticalScale: CGFloat
    ) -> CGFloat {
        let extent = max(canonicalBounds.width, canonicalBounds.height)
        guard extent.isFinite, extent > 0 else { return targetDiameter * 0.5 }
        return targetDiameter / extent * opticalScale
    }
}
```

Sort source elements by `userSize ?? size`, tie-breaking by UUID. If source spread is below `0.02`, return `0.26` for every element. Otherwise map the smallest slot to `0.19` and ranks `1...(count-1)` monotonically into `0.22...0.34`. For one element use `0.26`; for two use `0.22` and `0.30`. Center is always the source `basePosition`.

- [ ] **Step 5: Complete preview items and run tests GREEN**

```swift
struct RichFigurePreviewItem: Identifiable {
    let source: CanvasElement
    let style: RichFigureStyleSpec
    let layout: RichFigureLayoutSpec
    var id: UUID { source.id }
}
```

Add `RichFigureAssignment.previewItems(elements:dayKey:shuffleNonce:)` to combine assignment and layout. Run assignment and layout tests.

Extend `RichAssignmentFixture` with `previewItems(count:nonce:)` so later motion tests reuse the same deterministic source elements rather than inventing a second fixture.

- [ ] **Step 6: Commit Task 2**

Stage only Task 2 files and commit with `git commit -m "feat: normalize rich figure composition"`.

---

### Task 3: Render budgets and phased geometry timing

**Files:**
- Create: `StepsTrader/Experiments/RichCanvas/RichRenderBudget.swift`
- Create: `Steps4Tests/RichRenderBudgetTests.swift`
- Modify: `Steps4.xcodeproj/project.pbxproj`

**Interfaces:**
- Produces: `RichRenderBudget.resolve(elementCount:lowPowerMode:)` and `RichTimeBuckets.phase(for:)`/`bucket(time:seed:)`.

- [ ] **Step 1: Register files and write failing budget tests**

```swift
final class RichRenderBudgetTests: XCTestCase {
    func testTenElementNormalBudgetMatchesApprovedCeilings() {
        let budget = RichRenderBudget.resolve(elementCount: 10, lowPowerMode: false)
        XCTAssertEqual(budget.contourCount, 8)
        XCTAssertEqual(budget.orbitalRingCount, 8)
        XCTAssertEqual(budget.filamentCount, 24)
        XCTAssertEqual(budget.glowPassCount, 2)
        XCTAssertEqual(budget.globalParticleCount, 24)
        XCTAssertEqual(budget.requestedFPS, 20)
        XCTAssertFalse(budget.trailsEnabled)
    }

    func testLowPowerNeverExceedsNormalBudget() {
        let normal = RichRenderBudget.resolve(elementCount: 10, lowPowerMode: false)
        let low = RichRenderBudget.resolve(elementCount: 10, lowPowerMode: true)
        XCTAssertLessThanOrEqual(low.contourCount, normal.contourCount)
        XCTAssertLessThanOrEqual(low.filamentCount, normal.filamentCount)
        XCTAssertLessThanOrEqual(low.glowPassCount, normal.glowPassCount)
        XCTAssertFalse(low.trailsEnabled)
    }

    func testSeedPhaseDesynchronizesGeometryUpdates() {
        XCTAssertNotEqual(RichTimeBuckets.phase(for: 1),
                          RichTimeBuckets.phase(for: 2))
    }
}
```

- [ ] **Step 2: Run tests RED**

Run only `Steps4Tests/RichRenderBudgetTests`. Expected: missing budget/cache types.

- [ ] **Step 3: Implement exact budgets**

```swift
struct RichRenderBudget: Equatable {
    let contourCount: Int
    let orbitalRingCount: Int
    let filamentCount: Int
    let glowPassCount: Int
    let globalParticleCount: Int
    let requestedFPS: Int
    let trailsEnabled: Bool

    static func resolve(elementCount: Int, lowPowerMode: Bool) -> Self {
        let normal: Self
        switch elementCount {
        case ...5:
            normal = .init(contourCount: 10, orbitalRingCount: 8, filamentCount: 32,
                           glowPassCount: 2, globalParticleCount: 30,
                           requestedFPS: 20, trailsEnabled: false)
        case ...10:
            normal = .init(contourCount: 8, orbitalRingCount: 8, filamentCount: 24,
                           glowPassCount: 2, globalParticleCount: 24,
                           requestedFPS: 20, trailsEnabled: false)
        default:
            normal = .init(contourCount: 6, orbitalRingCount: 6, filamentCount: 16,
                           glowPassCount: 1, globalParticleCount: 16,
                           requestedFPS: 20, trailsEnabled: false)
        }
        guard lowPowerMode else { return normal }
        return .init(contourCount: min(normal.contourCount, 5),
                     orbitalRingCount: min(normal.orbitalRingCount, 5),
                     filamentCount: min(normal.filamentCount, 12),
                     glowPassCount: min(normal.glowPassCount, 1),
                     globalParticleCount: min(normal.globalParticleCount, 8),
                     requestedFPS: 15, trailsEnabled: false)
    }
}
```

- [ ] **Step 4: Implement phased geometry timing**

Use a 1.5-second seed-phased bucket so expensive fill updates do not align on one frame.

```swift
enum RichTimeBuckets {
    static let bucketSeconds = 1.5

    static func phase(for seed: UInt64) -> Double {
        var rng = SeededRNG.derived(from: seed, domain: "richBucketPhase")
        return rng.nextDouble() * bucketSeconds
    }

    static func bucket(time: Double, seed: UInt64) -> Int {
        Int(floor((time + phase(for: seed)) / bucketSeconds))
    }

}
```

- [ ] **Step 5: Run tests GREEN and commit**

Run `RichRenderBudgetTests`; commit with `git commit -m "feat: budget rich canvas rendering"`.

---

### Task 4: Pure deterministic geometry for all five families

**Files:**
- Create: `StepsTrader/Experiments/RichCanvas/RichFigureGeometry.swift`
- Create: `Steps4Tests/RichFigureGeometryTests.swift`
- Modify: `Steps4.xcodeproj/project.pbxproj`

**Interfaces:**
- Consumes: rich model, budget, `SeededRNG`, and low-level math helpers.
- Produces: `RichPolyline`, `RichFigureGeometry`, `RichFigureGeometryFactory.make(family:seed:detailTier:canonicalTime:budget:)`.

- [ ] **Step 1: Register files and write failing geometry tests**

```swift
final class RichFigureGeometryTests: XCTestCase {
    func testEveryFamilyIsDeterministicFiniteAndNonDegenerate() {
        let budget = RichRenderBudget.resolve(elementCount: 10, lowPowerMode: false)
        for family in RichFigureFamily.allCases {
            let a = RichFigureGeometryFactory.make(
                family: family, seed: 42, detailTier: .medium,
                canonicalTime: 12.0, budget: budget
            )
            let b = RichFigureGeometryFactory.make(
                family: family, seed: 42, detailTier: .medium,
                canonicalTime: 12.0, budget: budget
            )
            XCTAssertEqual(a, b)
            XCTAssertTrue(a.allPoints.allSatisfy { $0.x.isFinite && $0.y.isFinite })
            XCTAssertGreaterThan(a.bounds.width, 0.5)
            XCTAssertGreaterThan(a.bounds.height, 0.5)
        }
    }

    func testCrystallineStarSeedsRemainReadableAfterMeasuredFitting() {
        let budget = RichRenderBudget.resolve(elementCount: 10, lowPowerMode: false)
        for seed in UInt64(0)..<UInt64(128) {
            let geometry = RichFigureGeometryFactory.make(
                family: .crystallineStar, seed: seed, detailTier: .medium,
                canonicalTime: 0, budget: budget
            )
            let scale = RichFigureLayout.fittedScale(
                canonicalBounds: geometry.bounds, targetDiameter: 100,
                opticalScale: RichFigureLayout.opticalScale(for: .crystallineStar)
            )
            XCTAssertGreaterThanOrEqual(max(geometry.bounds.width, geometry.bounds.height) * scale, 100)
        }
    }
}
```

- [ ] **Step 2: Run tests RED**

Expected: missing geometry types.

- [ ] **Step 3: Implement normalized geometry primitives**

```swift
struct RichPolyline: Equatable {
    enum Role: Equatable { case silhouette, structure, orbit, accent }
    let points: [CGPoint]
    let isClosed: Bool
    let role: Role
}

struct RichFigureGeometry: Equatable {
    let lines: [RichPolyline]
    let core: CGPoint
    let bounds: CGRect
    var allPoints: [CGPoint] { lines.flatMap(\.points) }
}
```

- [ ] **Step 4: Implement each family with explicit rules**

```swift
switch family {
case .circle:
    // 96-point unit circle silhouette plus two seeded offset structural ellipses.
case .luminousOrganic:
    // 96 polar samples. Radius = 0.82 + three seeded harmonic terms;
    // clamp to 0.62...1.0 so the silhouette remains readable.
case .crystallineStar:
    // Seeded 8...12 axes, outer radius 0.82...1.0, inner 0.22...0.38.
    // Time changes lengths by at most ±7% and never changes axis count.
case .rays:
    // One origin near (-0.75, 0.55), 18...24 fan rays ending on a smooth arc,
    // plus a closed fan envelope for fills.
case .orbitalSpirograph:
    // Four to six rotated ellipses plus one hypotrochoid structural line.
}
```

All geometry is normalized around `(0, 0)` and excludes glow expansion. Do not call production renderers.

- [ ] **Step 5: Run focused tests GREEN and commit**

Run geometry, layout, and budget suites. Commit with `git commit -m "feat: generate rich figure geometry"`.

---

### Task 5: Pure fill geometry for all six constructions

**Files:**
- Create: `StepsTrader/Experiments/RichCanvas/RichFillGeometry.swift`
- Extend: `Steps4Tests/RichFigureGeometryTests.swift`
- Modify: `Steps4.xcodeproj/project.pbxproj`

**Interfaces:**
- Consumes: `RichFigureGeometry`, `RichFillKind`, `RichRenderBudget`, `RichFigureStyleSpec`.
- Produces: `RichFillGeometry`, `RichFillGeometryFactory.make(fill:base:seed:budget:)`.

- [ ] **Step 1: Register the source file and write failing fill tests**

```swift
func testFillGeometryRespectsTenElementBudget() {
    let budget = RichRenderBudget.resolve(elementCount: 10, lowPowerMode: false)
    let base = RichFigureGeometryFactory.make(
        family: .luminousOrganic, seed: 7, detailTier: .medium,
        canonicalTime: 0, budget: budget
    )

    let contours = RichFillGeometryFactory.make(
        fill: .nestedContours, base: base, seed: 7, budget: budget
    )
    let rings = RichFillGeometryFactory.make(
        fill: .orbitalLines, base: base, seed: 7, budget: budget
    )
    let filaments = RichFillGeometryFactory.make(
        fill: .filamentField, base: base, seed: 7, budget: budget
    )

    XCTAssertLessThanOrEqual(contours.lines.count, budget.contourCount)
    XCTAssertLessThanOrEqual(rings.lines.count, budget.orbitalRingCount)
    XCTAssertLessThanOrEqual(filaments.lines.count, budget.filamentCount)
}
```

Also assert every fill is deterministic and finite. Assert `luminousGradient` and `outlineWithCore` do not allocate dense line fields.

- [ ] **Step 2: Run tests RED**

Run `RichFigureGeometryTests`. Expected: missing fill geometry types.

- [ ] **Step 3: Implement fill construction**

```swift
struct RichFillGeometry: Equatable {
    let lines: [RichPolyline]
    let translucentSurfaces: [[CGPoint]]
    let highlightPoints: [CGPoint]
}

enum RichFillGeometryFactory {
    static func make(
        fill: RichFillKind,
        base: RichFigureGeometry,
        seed: UInt64,
        budget: RichRenderBudget
    ) -> RichFillGeometry {
        switch fill {
        case .luminousGradient:
            return luminousGradient(base: base, seed: seed)
        case .nestedContours:
            return nestedContours(base: base, count: budget.contourCount)
        case .orbitalLines:
            return orbitalLines(base: base, seed: seed, count: budget.orbitalRingCount)
        case .filamentField:
            return filamentField(base: base, seed: seed, count: budget.filamentCount)
        case .outlineWithCore:
            return outlineWithCore(base: base)
        case .layeredTranslucentMass:
            let count = min(5, max(3, budget.contourCount / 2))
            return layeredMass(base: base, seed: seed, count: count)
        }
    }
}
```

Implement these exact roles:

- `luminousGradient`: no dense lines; one seeded offset highlight point.
- `nestedContours`: inset normalized silhouette copies up to `contourCount`.
- `orbitalLines`: rotated/scaled copies with deterministic gaps represented as separate polylines, up to `orbitalRingCount`.
- `filamentField`: deterministic clipped chords, up to `filamentCount`.
- `outlineWithCore`: silhouette only plus core highlight.
- `layeredTranslucentMass`: three to five deformed closed surfaces, capped by detail tier and Low Power budget.

All families may receive all fills. When a family lacks a closed silhouette, use its envelope line for clipping.

- [ ] **Step 4: Run tests GREEN and commit**

Run `RichFigureGeometryTests`; commit with `git commit -m "feat: generate rich figure fills"`.

---

### Task 6: Rich renderer, family motion, materials, and no-trail guarantee

**Files:**
- Create: `StepsTrader/Experiments/RichCanvas/RichRenderCache.swift`
- Create: `StepsTrader/Experiments/RichCanvas/RichFigureRenderer.swift`
- Extend: `Steps4Tests/RichFigureGeometryTests.swift`
- Extend: `Steps4Tests/RichRenderBudgetTests.swift`
- Modify: `Steps4.xcodeproj/project.pbxproj`

**Interfaces:**
- Consumes: preview items, normalized base/fill geometry, budget, cache, `GraphicsContext`.
- Produces: `RichFigureRenderer.draw(item:context:canvasSize:time:budget:particleCount:reduceMotion:cache:)`, `RichFigureRenderer.center(...)`, `RichFigureMotionState`.

- [ ] **Step 1: Register renderer/cache files and write failing pure motion tests**

Add both new app files to the RichCanvas PBX group and the Steps4 Sources phase, then add these tests:

```swift
func testReduceMotionReturnsCanonicalState() {
    let item = RichAssignmentFixture.previewItems(count: 1)[0]
    let size = CGSize(width: 390, height: 844)
    let a = RichFigureRenderer.motionState(
        for: item, canvasSize: size, time: 10, reduceMotion: true
    )
    let b = RichFigureRenderer.motionState(
        for: item, canvasSize: size, time: 200, reduceMotion: true
    )
    XCTAssertEqual(a, b)
}

func testNoRenderBudgetCanEnableTrails() {
    for count in [1, 5, 10, 20] {
        XCTAssertFalse(RichRenderBudget.resolve(elementCount: count, lowPowerMode: false).trailsEnabled)
        XCTAssertFalse(RichRenderBudget.resolve(elementCount: count, lowPowerMode: true).trailsEnabled)
    }
}
```

- [ ] **Step 2: Run motion tests RED**

Expected: missing renderer and motion-state types.

- [ ] **Step 3: Implement family motion without topology changes**

```swift
struct RichFigureMotionState: Equatable {
    let center: CGPoint
    let rotation: Angle
    let scale: CGFloat
    let deformationTime: Double
    let highlightPhase: Double
}
```

- Circle: ±2% breathing and offset-highlight phase.
- Organic: stable center and slow deformation time.
- Star: call `SnowflakeShapeRenderer.driftPosition` only for its existing Lissajous position math; do not call `draw`, `drawTrailGhosts`, or touch trail cache entries. Add opposing internal rotations.
- Rays: fixed origin with ±4% fan opening and one `0...1` light-impulse phase.
- Spirograph: fixed base center with independent orbit phases.
- Reduce Motion: base center, zero rotation, scale 1, and a seed-derived canonical deformation time independent of wall clock.

- [ ] **Step 4: Implement the typed bounded cache and cadence stats**

Now that base and fill geometry types exist, define the cache without `Any`:

```swift
struct RichGeometryCacheKey: Hashable {
    let family: RichFigureFamily
    let fill: RichFillKind
    let seed: UInt64
    let detailTier: RichFigureDetailTier
    let timeBucket: Int
}

struct RichCachedGeometry {
    let base: RichFigureGeometry
    let fill: RichFillGeometry
}

struct RichCadenceStats: Equatable {
    let observedFPS: Double
    let slowIntervalCount: Int
    static let zero = RichCadenceStats(observedFPS: 0, slowIntervalCount: 0)

    static func calculate(intervals: [Double], requestedFPS: Int) -> Self {
        guard !intervals.isEmpty else { return .zero }
        let average = intervals.reduce(0, +) / Double(intervals.count)
        let threshold = 1.5 / Double(requestedFPS)
        return .init(observedFPS: 1 / average,
                     slowIntervalCount: intervals.filter { $0 > threshold }.count)
    }
}
```

`@MainActor final class RichRenderCache` stores `[RichGeometryCacheKey: RichCachedGeometry]`, a monotonically increasing access tick, and an LRU access map. `geometry(for:build:)` inserts on miss and evicts the least-recently-used entry while count exceeds 256. Expose internal read-only `geometryCount` for `@testable` assertions. `removeAllGeometry()` clears geometry and access maps. `recordFrame(time:requestedFPS:)` keeps the most recent 60 positive intervals and updates `RichCadenceStats`; `cadenceSnapshot()` returns the current value.

Extend `RichRenderBudgetTests` to insert 300 unique keys and assert cache count remains 256, and to verify `removeAllGeometry()` returns it to zero.

- [ ] **Step 5: Implement bounded material drawing**

Transform normalized geometry through measured fitting and motion. Batch lines sharing stroke material into one `Path`. Draw in this order:

```swift
// 1. One outer halo drawLayer, blurred, when glowPassCount >= 1.
// 2. Optional compact core glow when glowPassCount == 2.
// 3. Translucent surfaces.
// 4. Crisp fill and structural lines.
// 5. Colored core/highlights.
// 6. A share of the global particle pool only when particleEligible.
```

Use `.plusLighter` on dark backgrounds and `.normal` otherwise. Never blur every contour, filament, ring, or particle separately. Derive highlights from `primaryHex`/`secondaryHex`; never force every core to white.

The Canvas host distributes `budget.globalParticleCount` across eligible items in stable item order. Pass each renderer its explicit `particleCount`; renderers must never allocate their own unbounded pool. If `secondaryHex` is nil or cannot form a color, use the primary color.

- [ ] **Step 6: Add graceful fallback geometry**

Validate points and bounds before drawing. Replace invalid geometry with a unit-circle `RichFigureGeometry` in the same slot, preserving style colors. Do not skip the element.

- [ ] **Step 7: Run tests and simulator build GREEN**

Run geometry and budget suites, then the full Debug simulator build. Confirm no production renderer file changed.

- [ ] **Step 8: Commit Task 6**

Commit with `git commit -m "feat: render animated rich figures"`.

---

### Task 7: Rich Canvas host, real background, labels, and diagnostic HUD

**Files:**
- Create: `StepsTrader/Experiments/RichCanvas/RichCanvasView.swift`
- Extend: `Steps4Tests/RichRenderBudgetTests.swift`
- Modify: `Steps4.xcodeproj/project.pbxproj`

**Interfaces:**
- Consumes: `DayCanvas`, preview items, renderer, budget/cache, `EnergyGradientBackground`.
- Produces: `RichCanvasView(canvas:shuffleNonce:)` and `RichCanvasHUD`.

- [ ] **Step 1: Register the view and write cadence-stat tests**

```swift
func testCadenceStatsDistinguishStableAndSlowIntervals() {
    let stable = RichCadenceStats.calculate(
        intervals: Array(repeating: 0.05, count: 30), requestedFPS: 20
    )
    let slow = RichCadenceStats.calculate(
        intervals: [0.05, 0.05, 0.10, 0.05], requestedFPS: 20
    )
    XCTAssertEqual(stable.observedFPS, 20, accuracy: 0.1)
    XCTAssertEqual(stable.slowIntervalCount, 0)
    XCTAssertEqual(slow.slowIntervalCount, 1)
}
```

- [ ] **Step 2: Implement `RichCanvasView`**

```swift
struct RichCanvasView: View {
    let canvas: DayCanvas
    let shuffleNonce: Int

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.renderingIsActive) private var renderingIsActive
    @Environment(\.scenePhase) private var scenePhase
    @State private var cache = RichRenderCache()

    var body: some View {
        let lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
        let budget = RichRenderBudget.resolve(
            elementCount: canvas.elements.count,
            lowPowerMode: lowPower
        )
        let items = RichFigureAssignment.previewItems(
            elements: canvas.elements,
            dayKey: canvas.dayKey,
            shuffleNonce: shuffleNonce
        )

        ZStack {
            EnergyGradientBackground(
                stepsPoints: canvas.stepsPoints,
                sleepPoints: canvas.sleepPoints,
                hasStepsData: canvas.resolvedHasStepsData,
                hasSleepData: canvas.resolvedHasSleepData,
                showGrain: true,
                gradientStyleOverride: canvas.gradientStyle,
                gradientPaletteOverride: canvas.gradientPalette,
                textureOverride: canvas.textureRaw
            )
            richTimeline(items: items, budget: budget)
            RichCanvasHUD(cache: cache, budget: budget,
                          elementCount: items.count, lowPowerMode: lowPower)
        }
    }
}
```

`richTimeline` requests `1 / budget.requestedFPS`, pauses outside the active scene, and freezes at a seed-derived canonical time under Reduce Motion. The Canvas closure records cadence, renders every item, then draws `displayLabel` at the renderer's animated center using an 11-point label treatment without calling production private methods.

Before drawing, form `eligibleIDs = items.filter(\.style.particleEligible).map(\.id)`. Divide the global particle count by `eligibleIDs.count`, distribute the remainder to the earliest stable IDs, and pass that exact per-item count into `RichFigureRenderer.draw`.

- [ ] **Step 3: Implement the periodic HUD reader**

Use `.periodic(from: .now, by: 0.5)` to read `cache.cadenceSnapshot()` without publishing state from the render closure. Display:

```text
20.0 FPS · 10 items · 8 contours · Normal
slow: 0
```

In Low Power, display `Low Power` and the reduced requested FPS/detail values. Keep the HUD small, monospaced, and top-leading.

On `UIApplication.didReceiveMemoryWarningNotification`, call `cache.removeAllGeometry()`. The cache is view-owned, so leaving the screen releases it. Scene inactivity pauses the animation TimelineView.

- [ ] **Step 4: Run tests and build GREEN**

Run `RichRenderBudgetTests` and the simulator build. Add a SwiftUI preview with an in-memory ten-element `DayCanvas`; never save preview fixtures.

- [ ] **Step 5: Commit Task 7**

Commit with `git commit -m "feat: host rich canvas with diagnostics"`.

---

### Task 8: Read-only Lab screen, Shuffle, empty state, and Settings entry

**Files:**
- Create: `StepsTrader/Experiments/RichCanvas/RichCanvasLabView.swift`
- Create: `Steps4Tests/RichCanvasLabIsolationTests.swift`
- Modify: `StepsTrader/Views/Settings/SettingsAppearancePage.swift`
- Modify: `Steps4.xcodeproj/project.pbxproj`

**Interfaces:**
- Consumes: feature gate, `CanvasStorageService.loadCanvas(for:)`, `AppModel.dayKey(for:)`, `RichCanvasView`.
- Produces: `RichCanvasLabView(model:loadCanvas:)` and gated Settings navigation.

- [ ] **Step 1: Register the Lab and isolation test files**

Add source/test membership. Do not modify `Localizable.xcstrings`.

- [ ] **Step 2: Write failing session and read-only loading tests**

```swift
struct RichCanvasLabSession: Equatable {
    private(set) var shuffleNonce = 0
    mutating func shuffle() { shuffleNonce &+= 1 }
}

final class RichCanvasLabIsolationTests: XCTestCase {
    func testShuffleIsSessionOnlyValueState() {
        var session = RichCanvasLabSession()
        session.shuffle()
        session.shuffle()
        XCTAssertEqual(session.shuffleNonce, 2)
        XCTAssertEqual(RichCanvasLabSession().shuffleNonce, 0)
    }

    func testSnapshotLoaderReceivesDayKeyAndReturnsCanvas() {
        let expected = DayCanvas(dayKey: "2026-08-16")
        var requestedKey: String?
        let loaded = RichCanvasLabSnapshot.load(dayKey: expected.dayKey) { key in
            requestedKey = key
            return expected
        }
        XCTAssertEqual(requestedKey, expected.dayKey)
        XCTAssertEqual(loaded?.dayKey, expected.dayKey)
        XCTAssertEqual(loaded?.elements.count, expected.elements.count)
    }

    func testRichAssignmentDoesNotMutateCanvasElementEncoding() throws {
        let elements = RichAssignmentFixture.elements(count: 10)
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        let before = try encoder.encode(elements)
        _ = RichFigureAssignment.previewItems(
            elements: elements, dayKey: "2026-08-16", shuffleNonce: 3
        )
        let after = try encoder.encode(elements)
        XCTAssertEqual(before, after)
    }
}
```

`RichCanvasLabSnapshot.load` accepts only `(String) -> DayCanvas?`; it has no save callback.

- [ ] **Step 3: Run isolation tests RED**

Expected: missing Lab session/snapshot types.

- [ ] **Step 4: Implement the Lab view**

```swift
struct RichCanvasLabView: View {
    @ObservedObject var model: AppModel
    let loadCanvas: (String) -> DayCanvas?

    @State private var canvas: DayCanvas?
    @State private var session = RichCanvasLabSession()

    init(
        model: AppModel,
        loadCanvas: @escaping (String) -> DayCanvas? = {
            CanvasStorageService.shared.loadCanvas(for: $0)
        }
    ) {
        self.model = model
        self.loadCanvas = loadCanvas
    }

    var body: some View {
        ZStack {
            if let canvas, !canvas.elements.isEmpty {
                RichCanvasView(canvas: canvas, shuffleNonce: session.shuffleNonce)
            } else {
                ContentUnavailableView(
                    "No canvas yet", systemImage: "sparkles",
                    description: Text("Add happenings to today's canvas first.")
                )
            }
            controls
        }
        .task {
            canvas = RichCanvasLabSnapshot.load(
                dayKey: AppModel.dayKey(for: .now), loader: loadCanvas
            )
        }
    }
}
```

Add a Settings-consistent back/title control and a bottom `Shuffle` button. Shuffle increments session state and triggers light haptics. It never reloads or writes the canvas. Disable it for the empty state.

- [ ] **Step 5: Add the minimal gated Settings hunk**

In `manualGroup`, add after the current canvas controls:

```swift
if ExperimentalFeatures.richCanvasLab {
    richCanvasLabSection
}
```

Use this section body:

```swift
NavigationLink {
    RichCanvasLabView(model: model)
} label: {
    HStack(spacing: 12) {
        Image(systemName: "sparkles.rectangle.stack")
        VStack(alignment: .leading, spacing: 2) {
            Text("Rich Canvas")
            Text("Preview today's canvas with experimental figures")
                .font(.caption)
                .foregroundStyle(theme.adaptiveSecondaryText)
        }
        Spacer()
        Image(systemName: "chevron.right")
    }
    .padding(.horizontal, 16)
    .padding(.vertical, 12)
    .contentShape(Rectangle())
}
.buttonStyle(.plain)
```

Do not touch `canvasFillsSection`, shape controls, thumbnail invalidation, or preference sync.

- [ ] **Step 6: Run tests and Debug build GREEN**

Run `RichCanvasLabIsolationTests`, then the full Debug build.

- [ ] **Step 7: Stage only owned hunks and commit**

```bash
git add StepsTrader/Experiments/RichCanvas/RichCanvasLabView.swift \
  Steps4Tests/RichCanvasLabIsolationTests.swift \
  Steps4.xcodeproj/project.pbxproj
git add -p StepsTrader/Views/Settings/SettingsAppearancePage.swift
git diff --cached --name-only
git diff --cached -- StepsTrader/Views/Settings/SettingsAppearancePage.swift
git diff --cached --check
git commit -m "feat: add internal rich canvas lab"
```

Expected staged Settings diff: only the Rich Canvas section and its `manualGroup` reference.

---

### Task 9: Full verification, visual review, and physical-device gate

**Files:**
- Modify only if verification exposes a defect in a Task 1–8 owned file.
- Create visual evidence under `docs/design/rich-canvas-lab/` only after capture.

**Interfaces:**
- Consumes: completed Lab.
- Produces: test/build evidence, screenshots or recording, iPhone 13 result.

- [ ] **Step 1: Verify the production boundary**

Record the pre-implementation commit before Task 1 as `RICH_LAB_BASE`, then run:

```bash
git diff "$RICH_LAB_BASE"..HEAD --name-only | sort
git diff "$RICH_LAB_BASE"..HEAD -- \
  StepsTrader/Models/CanvasElement.swift \
  StepsTrader/Models/ShapeStyles.swift \
  StepsTrader/Shapes/ProceduralTexture.swift \
  StepsTrader/Shapes/CircleShapeRenderer.swift \
  StepsTrader/Shapes/OrganicBlobShapeRenderer.swift \
  StepsTrader/Shapes/SnowflakeShapeRenderer.swift \
  StepsTrader/Shapes/RayShapeRenderer.swift \
  StepsTrader/Views/GenerativeCanvasView.swift \
  StepsTrader/Services/HistoryThumbnailCache.swift
```

Expected: the second command has no Lab-authored diff.

- [ ] **Step 2: Run all unit tests**

```bash
xcodebuild test -project Steps4.xcodeproj -scheme Steps4 \
  -configuration Debug \
  -destination 'platform=iOS Simulator,name=iPhone 17,OS=latest' \
  -only-testing:Steps4Tests \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO
```

Expected: `TEST SUCCEEDED`, zero failures.

- [ ] **Step 3: Run a clean Debug build**

```bash
xcodebuild clean build -project Steps4.xcodeproj -scheme Steps4 \
  -configuration Debug \
  -destination 'platform=iOS Simulator,name=iPhone 17,OS=latest' \
  CODE_SIGNING_ALLOWED=NO
```

Expected: `BUILD SUCCEEDED`.

- [ ] **Step 4: Verify Release gating**

Build Release without the internal condition:

```bash
xcodebuild build -project Steps4.xcodeproj -scheme Steps4 \
  -configuration Release \
  -destination 'generic/platform=iOS Simulator' \
  CODE_SIGNING_ALLOWED=NO
```

Confirm `ExperimentalFeatures.richCanvasLab` compiles to `false`. Before a TestFlight review build, compile once with `SWIFT_ACTIVE_COMPILATION_CONDITIONS='$(inherited) INTERNAL_BUILD'` and verify the entry appears. Do not add `INTERNAL_BUILD` to ordinary Release settings.

- [ ] **Step 5: Capture visual states**

Open a real ten-element current canvas and capture nonce 0, three Shuffles, Reduce Motion, and Low Power. Verify:

- all five silhouettes are identifiable;
- all six fills are visible;
- Crystalline Star is not a speck;
- only the deliberate accent slot falls below the medium floor;
- Shuffle does not move, recolor, or resize slots;
- glow is not clipped;
- labels stay attached;
- no trails appear;
- no family becomes a generic glowing circle.

Save approved images or recording under `docs/design/rich-canvas-lab/` with descriptive names.

- [ ] **Step 6: Run the iPhone 13 performance gate**

Install an internal build on a physical iPhone 13. Open the ten-element Lab, warm caches for five seconds, then record 30 seconds in normal mode and 30 seconds in Low Power.

Pass criteria:

- normal HUD cadence remains at or above 20 FPS after warm-up;
- Shuffle causes no sustained stall;
- back navigation and Shuffle remain responsive;
- Low Power reports and visibly uses its reduced budget;
- if normal mode misses 20 FPS, capture Time Profiler and Metal System Trace before changing code.

- [ ] **Step 7: Fix only evidenced defects and re-run the failed gate**

For any failure, add a focused regression test before the fix. Do not move the entire renderer to Metal. Optimize the measured hotspot only, then repeat the failed test, visual check, or device run.

- [ ] **Step 8: Final owned-files review and optional evidence commit**

```bash
git status --short
git diff --check
git log --oneline --decorate -10
```

If evidence files were added:

```bash
git add docs/design/rich-canvas-lab
git diff --cached --check
git commit -m "docs: capture rich canvas lab review"
```

Do not stage any pre-existing unrelated file.
