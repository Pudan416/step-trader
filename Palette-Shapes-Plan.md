# Palette shapes implementation plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the liquid metaball palette with a staggered 3-2-3-2 field where every tile is drawn as the exact figure that happening will become on the canvas.

**Architecture:** The shape roll moves out of `CanvasElement.spawn` and into the palette, so a tile can preview a decision that is currently made after the tap. A happening's figure for the day is a pure function of `(happeningId, dayKey, shuffleNonce)` — nothing but the nonce is stored. Tiles draw through the real canvas renderers, so the preview cannot drift from the canvas.

**Tech Stack:** SwiftUI, XCTest, `Canvas`/`GraphicsContext`, the existing `StepsTrader/Shapes/*Renderer` family, `UserDefaults.stepsTrader()` app group.

## Global Constraints

- Branch: `feat/palette-shapes`. It is stacked on `feat/happenings`; rebase onto `main` after PR #13 merges.
- `StepsTrader` and `Steps4Tests` use **explicit PBXGroups**, not synchronized folders. Every new file needs four hand-written `project.pbxproj` entries: `PBXBuildFile`, `PBXFileReference`, a child entry in its group, and an entry in the target's Sources phase. Follow the `DA00NN00NN00NN00NN0010` / `...0011` id pattern already used by `HappeningPaletteSelection.swift`.
- Test command: `xcodebuild test -project Steps4.xcodeproj -scheme Steps4 -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:Steps4Tests/<Class>/<test>`. There is no `iPhone 16 Pro` on this machine.
- User-facing strings go through `Localizable.xcstrings` with a `comment:`. Edit that file **textually**, preserving Xcode's `"key" : {` spacing — never re-serialise it with a JSON tool.
- `CanvasShapeType.allowedByUser` is the only source of assignable shape types. Never bypass it.
- Colours come from `CanvasColorPalette.paletteHex` (29 entries).
- Reduce Motion (`@Environment(\.accessibilityReduceMotion)`) must skip transitions, never skip the state change.

## Deviation from the spec, flagged for approval

`Palette-Shapes-Spec.md` says three keys are persisted: an assignment map, its day key, and a shuffle nonce. This plan stores **only the nonce**.

The assignment is a pure function of `(happeningId, dayKey, nonce)`, so the map is derivable and storing it adds a second source of truth that can go stale — for example when the user swaps a palette slot mid-day. Every acceptance criterion in the spec still holds. If you want the map persisted anyway, say so before Task 3 and it is a small change there.

Related and load-bearing: the seed **cannot** come from `CanvasElement.makeSeed(optionId:dayKey:index:)` with `index: existingElements.count`, which is what `spawn` does today. That index changes every time an element is added, so every remaining tile would silently change silhouette after each pick. Task 2 derives an index-independent seed instead.

---

### Task 1: Draw a canvas element at tile scale

The spec names this the design's biggest risk: the renderers were written for one full-screen canvas and have never been driven into a small box. Prove it before anything is built on top.

**Files:**
- Create: `StepsTrader/Views/Palette/HappeningShapeTile.swift`
- Modify: `Steps4.xcodeproj/project.pbxproj`
- Test: `Steps4Tests/HappeningShapeTileTests.swift`

**Interfaces:**
- Consumes: `CanvasElement`, `CanvasShapeType`, the four renderers in `StepsTrader/Shapes/`.
- Produces:
  - `HappeningShapeTile.previewElement(optionId:label:shapeType:colorHex:seed:) -> CanvasElement`
  - `struct HappeningShapeTile: View` taking `element: CanvasElement`, `side: CGFloat`.

- [ ] **Step 1: Write the failing test**

```swift
import XCTest
@testable import Steps4

final class HappeningShapeTileTests: XCTestCase {

    func testPreviewElementCarriesTheAssignedFigure() {
        let element = HappeningShapeTile.previewElement(
            optionId: "happening_walk",
            label: "Walk",
            shapeType: .snowflake,
            colorHex: "#EF9F27",
            seed: 42
        )

        XCTAssertEqual(element.frozenShapeType, .snowflake)
        XCTAssertEqual(element.hexColor, "#EF9F27")
        XCTAssertEqual(element.shapeSeed, 42)
        XCTAssertEqual(element.optionId, "happening_walk")
    }

    /// The tile is a fixed square. A preview element must sit dead centre and
    /// at a fixed size, or tiles of different shape types would render at
    /// different scales and the grid would look ragged.
    func testPreviewElementIsCentredAndFixedSize() {
        let element = HappeningShapeTile.previewElement(
            optionId: "happening_read",
            label: "Read",
            shapeType: .circle,
            colorHex: "#378ADD",
            seed: 7
        )

        XCTAssertEqual(element.basePosition.x, 0.5, accuracy: 0.0001)
        XCTAssertEqual(element.basePosition.y, 0.5, accuracy: 0.0001)
        XCTAssertEqual(element.size, HappeningShapeTile.previewSize, accuracy: 0.0001)
    }

    /// Two tiles of the same type must differ when their seeds differ — that is
    /// the whole reason ten tiles can share four shape types.
    func testSameTypeDifferentSeedProducesDifferentElements() {
        let a = HappeningShapeTile.previewElement(
            optionId: "a", label: "A", shapeType: .organicBlob, colorHex: "#1D9E75", seed: 1
        )
        let b = HappeningShapeTile.previewElement(
            optionId: "b", label: "B", shapeType: .organicBlob, colorHex: "#1D9E75", seed: 2
        )

        XCTAssertNotEqual(a.shapeSeed, b.shapeSeed)
        XCTAssertEqual(a.frozenShapeType, b.frozenShapeType)
    }
}
```

- [ ] **Step 2: Run it to verify it fails**

Run: `xcodebuild test -project Steps4.xcodeproj -scheme Steps4 -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:Steps4Tests/HappeningShapeTileTests`

Expected: build failure, `cannot find 'HappeningShapeTile' in scope`.

- [ ] **Step 3: Write `HappeningShapeTile.swift`**

`rays` is the known hard case: `RayShapeRenderer` composes Metal spotlight cones anchored to the canvas edges, for a tall screen. Render it into an offscreen context that keeps the canvas aspect ratio and scale that down to fit, the way the app icon does — do not stretch it into a square.

```swift
import SwiftUI

/// One palette tile: the canvas renderers driven at tile scale so the preview
/// cannot drift from what the canvas will draw.
struct HappeningShapeTile: View {
    /// Fixed for every tile. Shape types pick their own random size inside
    /// `CanvasElement.spawn`; here they must all render at one scale or the
    /// grid looks ragged.
    static let previewSize: CGFloat = 0.62

    let element: CanvasElement
    let side: CGFloat

    static func previewElement(
        optionId: String,
        label: String,
        shapeType: CanvasShapeType,
        colorHex: String,
        seed: UInt64
    ) -> CanvasElement {
        CanvasElement(
            id: UUID(),
            kind: shapeType == .rays ? .ray : .circle,
            optionId: optionId,
            label: label,
            hexColor: colorHex,
            hexColor2: nil,
            size: previewSize,
            basePosition: CGPoint(x: 0.5, y: 0.5),
            phaseOffset: 0,
            driftSpeed: 0,
            driftAmplitude: 0,
            pulseFrequency: 0,
            pulseAmplitude: 0,
            rotationSpeed: 0,
            opacity: 1,
            createdAt: .now,
            shapeSeed: seed,
            frozenShapeType: shapeType
        )
    }

    var body: some View {
        Canvas(opaque: false, colorMode: .linear, rendersAsynchronously: false) { context, size in
            Self.draw(element, in: &context, size: size)
        }
        .frame(width: side, height: side)
        .allowsHitTesting(false)
    }

    private static func draw(
        _ element: CanvasElement,
        in context: inout GraphicsContext,
        size: CGSize
    ) {
        let color = Color(hex: element.hexColor)
        switch element.frozenShapeType ?? .circle {
        case .circle, .blob, .spirograph:
            CircleShapeRenderer.draw(
                element, context: &context, size: size, t: 0, decay: 1,
                blendMode: .normal, ampScale: 0, interaction: nil,
                decayedColor: color, decayedColor2: nil
            )
        case .snowflake:
            SnowflakeShapeRenderer.draw(
                element, context: &context, size: size, t: 0, decay: 1,
                blendMode: .normal, ampScale: 0, interaction: nil,
                decayedColor: color, decayedColor2: nil
            )
        case .organicBlob:
            OrganicBlobShapeRenderer.draw(
                element, context: &context, size: size, t: 0, decay: 1,
                blendMode: .normal, ampScale: 0, interaction: nil,
                decayedColor: color, decayedColor2: nil
            )
        case .rays:
            drawRaysPreservingCanvasAspect(element, in: &context, size: size, color: color)
        }
    }

    /// Rays are edge-anchored cones composed for a tall canvas. Render them in
    /// the canvas aspect ratio and scale the result down into the square, so
    /// the cones stay recognisable instead of smearing.
    private static func drawRaysPreservingCanvasAspect(
        _ element: CanvasElement,
        in context: inout GraphicsContext,
        size: CGSize,
        color: Color
    ) {
        let canvasSize = GenerativeCanvasView.canonicalPortraitSize
        let scale = min(size.width / canvasSize.width, size.height / canvasSize.height)
        var scaled = context
        scaled.translateBy(
            x: (size.width - canvasSize.width * scale) / 2,
            y: (size.height - canvasSize.height * scale) / 2
        )
        scaled.scaleBy(x: scale, y: scale)
        RayShapeRenderer.draw(
            element, context: &scaled, size: canvasSize, t: 0, decay: 1,
            blendMode: .normal, ampScale: 0, interaction: nil,
            decayedColor: color, decayedColor2: nil
        )
    }
}
```

Check the four `draw` signatures against the renderer sources before compiling — `RayShapeRenderer.draw` in particular may take different parameters than `CircleShapeRenderer.draw`. Match what is there; do not change the renderers.

- [ ] **Step 4: Register the two files in `project.pbxproj`**

Four entries each, following `HappeningPaletteSelection.swift` (lines 152, 474, 792, 1521) and `HappeningPaletteSelectionTests.swift` (lines 227, 549, 1128, 1687). Use fresh ids `DA0020002000200020000010`/`...0011` for the view and `DA0021002100210021000010`/`...0011` for the test. Put the view in the `Palette` group and the test in the `Steps4Tests` group.

- [ ] **Step 5: Run the tests to verify they pass**

Run: `xcodebuild test -project Steps4.xcodeproj -scheme Steps4 -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:Steps4Tests/HappeningShapeTileTests`

Expected: 3 tests pass.

- [ ] **Step 6: Look at all four shape types on the simulator**

Unit tests cannot tell you whether a renderer looks right in a 100pt box, and that is the risk this task exists to retire. Add a temporary `#Preview` rendering one tile of each of `.circle`, `.snowflake`, `.organicBlob`, `.rays` at `side: 100`, build, and look at it.

**Gate:** if any type is unrecognisable at tile scale, stop and report before starting Task 2. The whole design rests on the preview being truthful, and a renderer that cannot be driven small makes it unreachable.

Delete the temporary preview once you have looked.

- [ ] **Step 7: Commit**

```bash
git add StepsTrader/Views/Palette/HappeningShapeTile.swift Steps4Tests/HappeningShapeTileTests.swift Steps4.xcodeproj/project.pbxproj
git commit -m "feat: draw a canvas element at palette tile scale"
```

---

### Task 2: The figure a happening takes today

Pure derivation, no storage and no SwiftUI. This is where the promise lives.

**Files:**
- Create: `StepsTrader/Models/HappeningShapeAssignment.swift`
- Modify: `Steps4.xcodeproj/project.pbxproj`
- Test: `Steps4Tests/HappeningShapeAssignmentTests.swift`

**Interfaces:**
- Consumes: `CanvasShapeType.allowedByUser`, `CanvasColorPalette.paletteHex`, `CanvasElement.makeSeed(optionId:dayKey:index:)`.
- Produces:
  - `struct HappeningShapeAssignment: Equatable { let shapeType: CanvasShapeType; let colorHex: String; let seed: UInt64 }`
  - `enum HappeningShapeRoll { static func assignments(for ids: [String], dayKey: String, nonce: UInt64, allowedShapes: [CanvasShapeType], palette: [String]) -> [String: HappeningShapeAssignment] }`

- [ ] **Step 1: Write the failing test**

```swift
import XCTest
@testable import Steps4

final class HappeningShapeAssignmentTests: XCTestCase {

    private let ids = (0..<10).map { "happening_\($0)" }

    private func roll(nonce: UInt64, dayKey: String = "2026-08-10") -> [String: HappeningShapeAssignment] {
        HappeningShapeRoll.assignments(
            for: ids,
            dayKey: dayKey,
            nonce: nonce,
            allowedShapes: CanvasShapeType.selectableCases,
            palette: CanvasColorPalette.paletteHex
        )
    }

    func testEveryHappeningGetsAnAssignment() {
        let assignments = roll(nonce: 0)
        XCTAssertEqual(Set(assignments.keys), Set(ids))
    }

    func testSameInputsProduceTheSameFigures() {
        XCTAssertEqual(roll(nonce: 7), roll(nonce: 7))
    }

    func testColoursAreDistinctWithinASet() {
        let colours = roll(nonce: 3).values.map(\.colorHex)
        XCTAssertEqual(Set(colours).count, ids.count)
    }

    func testShapeTypesComeOnlyFromTheAllowedSet() {
        let assignments = HappeningShapeRoll.assignments(
            for: ids,
            dayKey: "2026-08-10",
            nonce: 1,
            allowedShapes: [.organicBlob],
            palette: CanvasColorPalette.paletteHex
        )
        XCTAssertTrue(assignments.values.allSatisfy { $0.shapeType == .organicBlob })
    }

    /// A single allowed type is a legitimate configuration. The tiles must still
    /// differ, and the seed is what makes that true.
    func testOneAllowedTypeStillGivesDistinctSeeds() {
        let assignments = HappeningShapeRoll.assignments(
            for: ids,
            dayKey: "2026-08-10",
            nonce: 1,
            allowedShapes: [.organicBlob],
            palette: CanvasColorPalette.paletteHex
        )
        XCTAssertEqual(Set(assignments.values.map(\.seed)).count, ids.count)
    }

    func testANewNonceChangesTheFigures() {
        let before = roll(nonce: 1)
        let after = roll(nonce: 2)
        XCTAssertNotEqual(before, after)
    }

    func testANewDayChangesTheFigures() {
        XCTAssertNotEqual(roll(nonce: 1, dayKey: "2026-08-10"), roll(nonce: 1, dayKey: "2026-08-11"))
    }

    /// The seed must not depend on how many elements are already on the canvas.
    /// `CanvasElement.spawn` derives it from `existingElements.count`, which
    /// would shift every remaining tile's silhouette after each pick.
    func testSeedDoesNotDependOnHowManyHappeningsRemain() {
        let full = roll(nonce: 5)
        let shortened = HappeningShapeRoll.assignments(
            for: Array(ids.prefix(4)),
            dayKey: "2026-08-10",
            nonce: 5,
            allowedShapes: CanvasShapeType.selectableCases,
            palette: CanvasColorPalette.paletteHex
        )
        for id in ids.prefix(4) {
            XCTAssertEqual(full[id]?.seed, shortened[id]?.seed)
            XCTAssertEqual(full[id]?.shapeType, shortened[id]?.shapeType)
        }
    }

    func testEmptyAllowedSetFallsBackToCircleRatherThanCrashing() {
        let assignments = HappeningShapeRoll.assignments(
            for: ["a"], dayKey: "2026-08-10", nonce: 0,
            allowedShapes: [], palette: CanvasColorPalette.paletteHex
        )
        XCTAssertEqual(assignments["a"]?.shapeType, .circle)
    }
}
```

- [ ] **Step 2: Run it to verify it fails**

Run: `xcodebuild test -project Steps4.xcodeproj -scheme Steps4 -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:Steps4Tests/HappeningShapeAssignmentTests`

Expected: build failure, `cannot find 'HappeningShapeRoll' in scope`.

- [ ] **Step 3: Write `HappeningShapeAssignment.swift`**

Colour distinctness comes from shuffling the palette with a seeded generator and taking a prefix. Shape and seed are per-id so they do not move when the id list shrinks.

```swift
import Foundation

/// The figure a happening takes for one custom day: which shape type, which
/// colour, and the seed that gives it its own silhouette within that type.
struct HappeningShapeAssignment: Equatable {
    let shapeType: CanvasShapeType
    let colorHex: String
    let seed: UInt64
}

/// Deterministic, storage-free derivation of a day's figures.
///
/// Nothing is persisted but the nonce: the same `(id, dayKey, nonce)` always
/// gives the same figure, so a stored map would only be a second source of
/// truth that can go stale when the configured ten change mid-day.
enum HappeningShapeRoll {

    /// Small, fast, and — unlike `SystemRandomNumberGenerator` — reproducible,
    /// which is what lets the tests above assert anything at all.
    struct SplitMix64: RandomNumberGenerator {
        private var state: UInt64

        init(seed: UInt64) { state = seed }

        mutating func next() -> UInt64 {
            state &+= 0x9E37_79B9_7F4A_7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
            z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
            return z ^ (z >> 31)
        }
    }

    static func assignments(
        for ids: [String],
        dayKey: String,
        nonce: UInt64,
        allowedShapes: [CanvasShapeType] = CanvasShapeType.allowedByUser,
        palette: [String] = CanvasColorPalette.paletteHex
    ) -> [String: HappeningShapeAssignment] {
        let shapes = allowedShapes.isEmpty ? [.circle] : allowedShapes
        let colours = distinctColours(count: ids.count, dayKey: dayKey, nonce: nonce, palette: palette)

        return ids.enumerated().reduce(into: [:]) { result, pair in
            let (index, id) = pair
            let seed = figureSeed(optionId: id, dayKey: dayKey, nonce: nonce)
            var generator = SplitMix64(seed: seed)
            result[id] = HappeningShapeAssignment(
                shapeType: shapes.randomElement(using: &generator) ?? .circle,
                colorHex: colours[index % colours.count],
                seed: seed
            )
        }
    }

    /// Index-independent, unlike `CanvasElement.spawn`'s own derivation. Index 0
    /// is passed deliberately: the palette must not change a tile's silhouette
    /// as other tiles are picked.
    static func figureSeed(optionId: String, dayKey: String, nonce: UInt64) -> UInt64 {
        let base = CanvasElement.makeSeed(optionId: optionId, dayKey: dayKey, index: 0)
        var mixed = base ^ (nonce &* 0x9E37_79B9_7F4A_7C15)
        mixed = (mixed ^ (mixed >> 29)) &* 0xBF58_476D_1CE4_E5B9
        return mixed ^ (mixed >> 32)
    }

    private static func distinctColours(
        count: Int,
        dayKey: String,
        nonce: UInt64,
        palette: [String]
    ) -> [String] {
        guard !palette.isEmpty else { return [AppColors.goldFallbackHex] }
        var generator = SplitMix64(
            seed: CanvasElement.makeSeed(optionId: "palette-colours", dayKey: dayKey, index: 0) ^ nonce
        )
        let shuffled = palette.shuffled(using: &generator)
        guard count <= shuffled.count else { return shuffled }
        return Array(shuffled.prefix(count))
    }
}
```

- [ ] **Step 4: Register both files in `project.pbxproj`**

Ids `DA0022002200220022000010`/`...0011` for the model (group `Models`), `DA0023002300230023000010`/`...0011` for the test.

- [ ] **Step 5: Run the tests to verify they pass**

Run: `xcodebuild test -project Steps4.xcodeproj -scheme Steps4 -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:Steps4Tests/HappeningShapeAssignmentTests`

Expected: 8 tests pass.

- [ ] **Step 6: Commit**

```bash
git add StepsTrader/Models/HappeningShapeAssignment.swift Steps4Tests/HappeningShapeAssignmentTests.swift Steps4.xcodeproj/project.pbxproj
git commit -m "feat: derive a happening's figure for the day"
```

---

### Task 3: Persist the shuffle nonce

**Files:**
- Create: `StepsTrader/Stores/HappeningShapeNonceStore.swift`
- Modify: `StepsTrader/Utilities/SharedKeys.swift` (beside line 121, `happeningPaletteSelection`)
- Modify: `Steps4.xcodeproj/project.pbxproj`
- Test: `Steps4Tests/HappeningShapeNonceStoreTests.swift`

**Interfaces:**
- Consumes: `UserDefaults.stepsTrader()`.
- Produces:
  - `SharedKeys.happeningShapeNonce` = `"happeningShapeNonce_v1"`
  - `SharedKeys.happeningShapeNonceDayKey` = `"happeningShapeNonceDayKey_v1"`
  - `final class HappeningShapeNonceStore` with `init(defaults:)`, `func nonce(for dayKey: String) -> UInt64`, `@discardableResult func reroll(for dayKey: String) -> UInt64`

- [ ] **Step 1: Write the failing test**

```swift
import XCTest
@testable import Steps4

final class HappeningShapeNonceStoreTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        super.setUp()
        suiteName = "HappeningShapeNonceStoreTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    func testNonceIsStableWithinADay() {
        let store = HappeningShapeNonceStore(defaults: defaults)
        XCTAssertEqual(store.nonce(for: "2026-08-10"), store.nonce(for: "2026-08-10"))
    }

    func testNonceSurvivesAReload() {
        let first = HappeningShapeNonceStore(defaults: defaults).nonce(for: "2026-08-10")
        let second = HappeningShapeNonceStore(defaults: defaults).nonce(for: "2026-08-10")
        XCTAssertEqual(first, second)
    }

    func testANewDayRollsANewNonce() {
        let store = HappeningShapeNonceStore(defaults: defaults)
        let today = store.nonce(for: "2026-08-10")
        let tomorrow = store.nonce(for: "2026-08-11")
        XCTAssertNotEqual(today, tomorrow)
        XCTAssertEqual(store.nonce(for: "2026-08-11"), tomorrow)
    }

    func testRerollChangesTheNonceAndPersists() {
        let store = HappeningShapeNonceStore(defaults: defaults)
        let before = store.nonce(for: "2026-08-10")
        let after = store.reroll(for: "2026-08-10")

        XCTAssertNotEqual(before, after)
        XCTAssertEqual(store.nonce(for: "2026-08-10"), after)
        XCTAssertEqual(HappeningShapeNonceStore(defaults: defaults).nonce(for: "2026-08-10"), after)
    }
}
```

- [ ] **Step 2: Run it to verify it fails**

Run: `xcodebuild test -project Steps4.xcodeproj -scheme Steps4 -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:Steps4Tests/HappeningShapeNonceStoreTests`

Expected: build failure, `cannot find 'HappeningShapeNonceStore' in scope`.

- [ ] **Step 3: Add the two keys to `SharedKeys.swift`**

```swift
    static let happeningShapeNonce = "happeningShapeNonce_v1"
    static let happeningShapeNonceDayKey = "happeningShapeNonceDayKey_v1"
```

- [ ] **Step 4: Write `HappeningShapeNonceStore.swift`**

`UserDefaults` has no `UInt64` accessor; store the bit pattern as `Int64` via `NSNumber` and convert, which round-trips exactly.

```swift
import Foundation

/// The one persisted piece of the palette's figures. Everything else is derived
/// from it by `HappeningShapeRoll`, so there is nothing else to keep in sync.
final class HappeningShapeNonceStore {
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .stepsTrader()) {
        self.defaults = defaults
    }

    /// The nonce for `dayKey`, minting and persisting one when the stored value
    /// belongs to another day. Reading is what rolls the day over — there is no
    /// separate rollover hook to forget to call.
    func nonce(for dayKey: String) -> UInt64 {
        guard
            defaults.string(forKey: SharedKeys.happeningShapeNonceDayKey) == dayKey,
            let stored = defaults.object(forKey: SharedKeys.happeningShapeNonce) as? NSNumber
        else {
            return mint(for: dayKey)
        }
        return UInt64(bitPattern: stored.int64Value)
    }

    @discardableResult
    func reroll(for dayKey: String) -> UInt64 {
        mint(for: dayKey)
    }

    private func mint(for dayKey: String) -> UInt64 {
        let value = UInt64.random(in: UInt64.min...UInt64.max)
        defaults.set(NSNumber(value: Int64(bitPattern: value)), forKey: SharedKeys.happeningShapeNonce)
        defaults.set(dayKey, forKey: SharedKeys.happeningShapeNonceDayKey)
        return value
    }
}
```

- [ ] **Step 5: Register both files in `project.pbxproj`**

Ids `DA0024002400240024000010`/`...0011` for the store (group `Stores`), `DA0025002500250025000010`/`...0011` for the test.

- [ ] **Step 6: Run the tests to verify they pass**

Run: `xcodebuild test -project Steps4.xcodeproj -scheme Steps4 -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:Steps4Tests/HappeningShapeNonceStoreTests`

Expected: 4 tests pass.

- [ ] **Step 7: Commit**

```bash
git add StepsTrader/Stores/HappeningShapeNonceStore.swift Steps4Tests/HappeningShapeNonceStoreTests.swift StepsTrader/Utilities/SharedKeys.swift Steps4.xcodeproj/project.pbxproj
git commit -m "feat: persist the palette shuffle nonce per day"
```

---

### Task 4: Let the caller hand `spawn` its figure

**Files:**
- Modify: `StepsTrader/Models/CanvasElement.swift:207-269` (`spawn`)
- Test: `Steps4Tests/CanvasElementSpawnFigureTests.swift`

**Interfaces:**
- Consumes: `HappeningShapeAssignment` (Task 2).
- Produces: `CanvasElement.spawn(..., figure: HappeningShapeAssignment? = nil, ...)` — when `figure` is non-nil, `frozenShapeType`, `hexColor` and `shapeSeed` come from it; when nil, behaviour is exactly what it is today.

The default must stay byte-for-byte behaviour-compatible: `testLegacyCanvasDecodesToUnchangedFrozenShapeTypes` in `HappeningMigrationTests` guards that old canvases keep their shapes, and `GalleryView.swift:1126` is the only production call site.

- [ ] **Step 1: Write the failing test**

```swift
import XCTest
@testable import Steps4

final class CanvasElementSpawnFigureTests: XCTestCase {

    func testSpawnUsesTheSuppliedFigure() {
        let figure = HappeningShapeAssignment(shapeType: .snowflake, colorHex: "#EF9F27", seed: 99)

        let element = CanvasElement.spawn(
            optionId: "happening_walk",
            color: "#000000",
            label: "Walk",
            existingElements: [],
            dayKey: "2026-08-10",
            figure: figure
        )

        XCTAssertEqual(element.frozenShapeType, .snowflake)
        XCTAssertEqual(element.hexColor, "#EF9F27")
        XCTAssertEqual(element.shapeSeed, 99)
    }

    /// The figure decides the shape, so it must also decide the element kind —
    /// rays render through a different path than the closed shapes.
    func testSuppliedRaysFigureSetsTheRayKind() {
        let element = CanvasElement.spawn(
            optionId: "happening_walk",
            color: "#000000",
            label: "Walk",
            existingElements: [],
            dayKey: "2026-08-10",
            figure: HappeningShapeAssignment(shapeType: .rays, colorHex: "#378ADD", seed: 3)
        )

        XCTAssertEqual(element.kind, .ray)
    }

    /// Without a figure, spawn must behave exactly as it did before this change.
    func testSpawnWithoutAFigureStillRollsItsOwn() {
        let element = CanvasElement.spawn(
            optionId: "happening_walk",
            color: "#AABBCC",
            label: "Walk",
            existingElements: [],
            allowedShapeTypes: [.circle],
            dayKey: "2026-08-10"
        )

        XCTAssertEqual(element.frozenShapeType, .circle)
        XCTAssertEqual(element.hexColor, "#AABBCC")
        XCTAssertEqual(
            element.shapeSeed,
            CanvasElement.makeSeed(optionId: "happening_walk", dayKey: "2026-08-10", index: 0)
        )
    }
}
```

- [ ] **Step 2: Run it to verify it fails**

Run: `xcodebuild test -project Steps4.xcodeproj -scheme Steps4 -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:Steps4Tests/CanvasElementSpawnFigureTests`

Expected: build failure, `extra argument 'figure' in call`.

- [ ] **Step 3: Add the parameter to `spawn`**

Add `figure: HappeningShapeAssignment? = nil` to the signature after `allowedShapeTypes`, then replace the first line of the body and the seed/colour derivation:

```swift
        let shapeType = figure?.shapeType ?? (allowedShapeTypes.randomElement() ?? .circle)
        let resolvedColor = figure?.colorHex ?? color
```

and

```swift
        let seed = figure?.seed
            ?? dayKey.map { makeSeed(optionId: optionId, dayKey: $0, index: existingElements.count) }
            ?? UInt64.random(in: UInt64.min...UInt64.max)
```

then pass `hexColor: resolvedColor` into the `CanvasElement(...)` return. Leave `size`, `opacity`, `pulseFrequency` and the rest random — the promise is about the figure, not about how large it lands.

- [ ] **Step 4: Run the new tests and the migration guard**

Run: `xcodebuild test -project Steps4.xcodeproj -scheme Steps4 -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:Steps4Tests/CanvasElementSpawnFigureTests -only-testing:Steps4Tests/HappeningMigrationTests`

Expected: all pass, including `testLegacyCanvasDecodesToUnchangedFrozenShapeTypes`.

- [ ] **Step 5: Commit**

```bash
git add StepsTrader/Models/CanvasElement.swift Steps4Tests/CanvasElementSpawnFigureTests.swift Steps4.xcodeproj/project.pbxproj
git commit -m "feat: let the caller hand spawn its figure"
```

---

### Task 5: Wire the figures through the model

**Files:**
- Modify: `StepsTrader/AppModel.swift:183` (add the store beside `happeningPaletteSelectionStore`)
- Modify: `StepsTrader/AppModel+DailyEnergy.swift` (add the two accessors beside `configuredPaletteHappenings`)
- Test: `Steps4Tests/HappeningShapeAssignmentModelTests.swift`

**Interfaces:**
- Consumes: `HappeningShapeRoll` (Task 2), `HappeningShapeNonceStore` (Task 3).
- Produces:
  - `AppModel.happeningShapeNonceStore: HappeningShapeNonceStore`
  - `AppModel.paletteFigures(on date: Date = .now) -> [String: HappeningShapeAssignment]`
  - `AppModel.rerollPaletteFigures(on date: Date = .now)`

- [ ] **Step 1: Write the failing test**

```swift
import XCTest
@testable import Steps4

@MainActor
final class HappeningShapeAssignmentModelTests: XCTestCase {

    private func makeModel() -> AppModel {
        AppModel(
            healthKitService: MockHealthKitService(),
            familyControlsService: MockFamilyControlsService(),
            notificationService: MockNotificationService(),
            budgetEngine: MockBudgetEngine(),
            subscriptionStore: SubscriptionStore.shared
        )
    }

    func testEveryConfiguredHappeningHasAFigure() {
        let model = makeModel()
        model.loadDailyEnergyState()

        let figures = model.paletteFigures()
        for happening in model.configuredPaletteHappenings() {
            XCTAssertNotNil(figures[happening.id], "No figure for \(happening.id)")
        }
    }

    func testFiguresAreStableAcrossCalls() {
        let model = makeModel()
        model.loadDailyEnergyState()
        XCTAssertEqual(model.paletteFigures(), model.paletteFigures())
    }

    func testRerollChangesTheFigures() {
        let model = makeModel()
        model.loadDailyEnergyState()

        let before = model.paletteFigures()
        model.rerollPaletteFigures()

        XCTAssertNotEqual(before, model.paletteFigures())
    }

    /// Shake must not touch what is already on the canvas. The addition keeps
    /// the colour it was logged with regardless of later rerolls.
    func testRerollDoesNotChangeAlreadyLoggedAdditions() {
        let model = makeModel()
        let date = Date(timeIntervalSince1970: 1_786_176_000)
        model.loadDailyEnergyState()
        _ = model.addHappening(id: "happening_walk", colorHex: "#AABBCC", at: date)

        model.rerollPaletteFigures(on: date)

        XCTAssertEqual(model.todayAdditions.first?.colorHex, "#AABBCC")
    }
}
```

- [ ] **Step 2: Run it to verify it fails**

Run: `xcodebuild test -project Steps4.xcodeproj -scheme Steps4 -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:Steps4Tests/HappeningShapeAssignmentModelTests`

Expected: build failure, `value of type 'AppModel' has no member 'paletteFigures'`.

- [ ] **Step 3: Add the store to `AppModel.swift`**

Beside line 183:

```swift
    let happeningShapeNonceStore = HappeningShapeNonceStore()
```

- [ ] **Step 4: Add the accessors to `AppModel+DailyEnergy.swift`**

Place them directly after `configuredPaletteHappenings()`:

```swift
    /// The figure each configured happening takes today. Derived, not stored —
    /// see `HappeningShapeRoll`.
    func paletteFigures(on date: Date = .now) -> [String: HappeningShapeAssignment] {
        let dayKey = Self.dayKey(for: date)
        return HappeningShapeRoll.assignments(
            for: configuredPaletteHappenings().map(\.id),
            dayKey: dayKey,
            nonce: happeningShapeNonceStore.nonce(for: dayKey)
        )
    }

    /// Shake. Only unpicked tiles are affected, because additions already
    /// carry their colour and their canvas elements already froze their shape.
    func rerollPaletteFigures(on date: Date = .now) {
        happeningShapeNonceStore.reroll(for: Self.dayKey(for: date))
        objectWillChange.send()
    }
```

- [ ] **Step 5: Register the test file in `project.pbxproj`**

Ids `DA0026002600260026000010`/`...0011`.

- [ ] **Step 6: Run the tests to verify they pass**

Run: `xcodebuild test -project Steps4.xcodeproj -scheme Steps4 -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:Steps4Tests/HappeningShapeAssignmentModelTests`

Expected: 4 tests pass.

- [ ] **Step 7: Commit**

```bash
git add StepsTrader/AppModel.swift StepsTrader/AppModel+DailyEnergy.swift Steps4Tests/HappeningShapeAssignmentModelTests.swift Steps4.xcodeproj/project.pbxproj
git commit -m "feat: expose today's palette figures on the model"
```

---

### Task 6: The 3-2-3-2 layout

Pure geometry, no SwiftUI, so the stagger is testable rather than eyeballed.

**Files:**
- Create: `StepsTrader/Views/Palette/HappeningTileLayout.swift`
- Modify: `Steps4.xcodeproj/project.pbxproj`
- Test: `Steps4Tests/HappeningTileLayoutTests.swift`

**Interfaces:**
- Produces:
  - `enum HappeningTileLayout { static func rowCounts(for count: Int) -> [Int]; static func frames(count: Int, in bounds: CGRect, tileSide: CGFloat) -> [CGRect] }`

- [ ] **Step 1: Write the failing test**

```swift
import XCTest
@testable import Steps4

final class HappeningTileLayoutTests: XCTestCase {

    func testTenTilesFallIntoThreeTwoThreeTwo() {
        XCTAssertEqual(HappeningTileLayout.rowCounts(for: 10), [3, 2, 3, 2])
    }

    func testRowsAlternateThreeAndTwoAsTilesAreConsumed() {
        XCTAssertEqual(HappeningTileLayout.rowCounts(for: 9), [3, 2, 3, 1])
        XCTAssertEqual(HappeningTileLayout.rowCounts(for: 8), [3, 2, 3])
        XCTAssertEqual(HappeningTileLayout.rowCounts(for: 5), [3, 2])
        XCTAssertEqual(HappeningTileLayout.rowCounts(for: 3), [3])
        XCTAssertEqual(HappeningTileLayout.rowCounts(for: 1), [1])
        XCTAssertEqual(HappeningTileLayout.rowCounts(for: 0), [])
    }

    func testEveryTileGetsAFrame() {
        let frames = HappeningTileLayout.frames(
            count: 10,
            in: CGRect(x: 0, y: 0, width: 360, height: 560),
            tileSide: 84
        )
        XCTAssertEqual(frames.count, 10)
    }

    /// The point of the stagger: the row of two sits in the gaps of the row of
    /// three, not aligned to its columns.
    func testTheRowOfTwoSitsInTheGapsOfTheRowOfThree() {
        let frames = HappeningTileLayout.frames(
            count: 10,
            in: CGRect(x: 0, y: 0, width: 360, height: 560),
            tileSide: 84
        )
        let firstRow = frames[0..<3].map(\.midX)
        let secondRow = frames[3..<5].map(\.midX)

        XCTAssertEqual(secondRow[0], (firstRow[0] + firstRow[1]) / 2, accuracy: 0.5)
        XCTAssertEqual(secondRow[1], (firstRow[1] + firstRow[2]) / 2, accuracy: 0.5)
    }

    func testTilesStayInsideTheBounds() {
        let bounds = CGRect(x: 20, y: 40, width: 360, height: 560)
        let frames = HappeningTileLayout.frames(count: 10, in: bounds, tileSide: 84)

        for frame in frames {
            XCTAssertTrue(bounds.contains(frame), "\(frame) escapes \(bounds)")
        }
    }

    func testRowsDoNotOverlapVertically() {
        let frames = HappeningTileLayout.frames(
            count: 10,
            in: CGRect(x: 0, y: 0, width: 360, height: 560),
            tileSide: 84
        )
        XCTAssertLessThanOrEqual(frames[0].maxY, frames[3].minY)
        XCTAssertLessThanOrEqual(frames[3].maxY, frames[5].minY)
        XCTAssertLessThanOrEqual(frames[5].maxY, frames[8].minY)
    }
}
```

- [ ] **Step 2: Run it to verify it fails**

Run: `xcodebuild test -project Steps4.xcodeproj -scheme Steps4 -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:Steps4Tests/HappeningTileLayoutTests`

Expected: build failure, `cannot find 'HappeningTileLayout' in scope`.

- [ ] **Step 3: Write `HappeningTileLayout.swift`**

```swift
import SwiftUI

/// Staggered rows of three and two. A flat grid would leave a ragged last row
/// at ten items and read as a table; offsetting the twos into the gaps of the
/// threes keeps it structured without turning into one.
enum HappeningTileLayout {
    static func rowCounts(for count: Int) -> [Int] {
        guard count > 0 else { return [] }
        var rows: [Int] = []
        var remaining = count
        var wide = true
        while remaining > 0 {
            let take = min(wide ? 3 : 2, remaining)
            rows.append(take)
            remaining -= take
            wide.toggle()
        }
        return rows
    }

    static func frames(count: Int, in bounds: CGRect, tileSide: CGFloat) -> [CGRect] {
        let rows = rowCounts(for: count)
        guard !rows.isEmpty else { return [] }

        let rowStep = rows.count > 1
            ? min(tileSide + 24, (bounds.height - tileSide) / CGFloat(rows.count - 1))
            : 0
        let blockHeight = tileSide + rowStep * CGFloat(rows.count - 1)
        let firstMidY = bounds.minY + (bounds.height - blockHeight) / 2 + tileSide / 2

        // Column pitch is fixed by the row of three so the twos can land in its
        // gaps. Deriving it per row instead would put them under the threes.
        let pitch = min(tileSide + 20, (bounds.width - tileSide) / 2)

        var frames: [CGRect] = []
        for (rowIndex, rowCount) in rows.enumerated() {
            let midY = firstMidY + rowStep * CGFloat(rowIndex)
            let span = pitch * CGFloat(rowCount - 1)
            let firstMidX = bounds.midX - span / 2
            for column in 0..<rowCount {
                let midX = firstMidX + pitch * CGFloat(column)
                frames.append(
                    CGRect(
                        x: midX - tileSide / 2,
                        y: midY - tileSide / 2,
                        width: tileSide,
                        height: tileSide
                    )
                )
            }
        }
        return frames
    }
}
```

- [ ] **Step 4: Register both files in `project.pbxproj`**

Ids `DA0027002700270027000010`/`...0011` for the layout (group `Palette`), `DA0028002800280028000010`/`...0011` for the test.

- [ ] **Step 5: Run the tests to verify they pass**

Run: `xcodebuild test -project Steps4.xcodeproj -scheme Steps4 -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:Steps4Tests/HappeningTileLayoutTests`

Expected: 6 tests pass. If `testTilesStayInsideTheBounds` fails, the pitch or `rowStep` clamp is wrong — fix the layout, not the test.

- [ ] **Step 6: Commit**

```bash
git add StepsTrader/Views/Palette/HappeningTileLayout.swift Steps4Tests/HappeningTileLayoutTests.swift Steps4.xcodeproj/project.pbxproj
git commit -m "feat: lay palette tiles out in staggered rows"
```

---

### Task 7: The field, the hint, and the end of the liquid palette

This is the visible change. The liquid field goes in the same commit as its replacement so there is never a window with 2700 lines of dead code in the tree.

**Files:**
- Create: `StepsTrader/Views/Palette/HappeningShapeField.swift`
- Modify: `StepsTrader/Views/Palette/HappeningPaletteView.swift`
- Modify: `StepsTrader/Views/GalleryView.swift:212-221` (`handlePalettePick`), `:1126` (`addAndSpawnHappening`)
- Modify: `StepsTrader/Localizable.xcstrings`
- Delete: `StepsTrader/Views/Palette/HappeningLiquidField.swift`, `StepsTrader/Views/Palette/HappeningLiquidLayout.swift`, `Steps4Tests/HappeningLiquidLayoutTests.swift`
- Modify: `Steps4.xcodeproj/project.pbxproj`

**Interfaces:**
- Consumes: `HappeningShapeTile` (Task 1), `HappeningShapeAssignment` (Task 2), `HappeningTileLayout` (Task 6), `AppModel.paletteFigures(on:)` (Task 5).
- Produces: `struct HappeningShapeField: View` taking `happenings: [Happening]`, `figures: [String: HappeningShapeAssignment]`, `onPick: (Happening, CGPoint) -> Bool`.

- [ ] **Step 1: Write `HappeningShapeField.swift`**

Keep the hit-testing order that the liquid field had to learn the hard way: `.contentShape()` must be applied to the sized frame **before** `.position()`, because `.position()` expands a view to fill its parent and a shape applied after it swallows every tap in the container.

```swift
import SwiftUI

/// Ten tiles, each drawn as the figure its happening will become.
struct HappeningShapeField: View {
    let happenings: [Happening]
    let figures: [String: HappeningShapeAssignment]
    let onPick: (Happening, CGPoint) -> Bool

    private let tileSide: CGFloat = 84

    var body: some View {
        GeometryReader { proxy in
            let bounds = CGRect(origin: .zero, size: proxy.size)
            let frames = HappeningTileLayout.frames(
                count: happenings.count,
                in: bounds,
                tileSide: tileSide
            )

            ZStack(alignment: .topLeading) {
                ForEach(Array(happenings.enumerated()), id: \.element.id) { index, happening in
                    if index < frames.count, let figure = figures[happening.id] {
                        tile(happening, figure: figure, frame: frames[index])
                    }
                }
            }
        }
    }

    private func tile(
        _ happening: Happening,
        figure: HappeningShapeAssignment,
        frame: CGRect
    ) -> some View {
        VStack(spacing: 6) {
            HappeningShapeTile(
                element: HappeningShapeTile.previewElement(
                    optionId: happening.id,
                    label: happening.localizedTitle(),
                    shapeType: figure.shapeType,
                    colorHex: figure.colorHex,
                    seed: figure.seed
                ),
                side: tileSide
            )
            Text(happening.localizedTitle())
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(AppColors.Night.textPrimary)
                .multilineTextAlignment(.center)
                .lineLimit(2)
        }
        // contentShape before position: `.position()` expands the view to fill
        // its parent, so a shape applied after it covers the whole field and the
        // topmost tile eats every tap.
        .frame(width: frame.width, height: frame.height)
        .contentShape(Rectangle())
        .onTapGesture { _ = onPick(happening, CGPoint(x: frame.midX, y: frame.midY)) }
        .position(x: frame.midX, y: frame.midY)
        .accessibilityElement(children: .ignore)
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel(Text(happening.localizedTitle()))
    }
}
```

- [ ] **Step 2: Add the hint string to `Localizable.xcstrings`**

Insert textually, preserving the file's `"key" : {` style. Key: `Shake to change the shapes`, comment `Palette shake hint`. Russian: `Встряхни, чтобы поменять фигуры`.

- [ ] **Step 3: Rewrite `HappeningPaletteView` around the new field**

Keep, unchanged: the dock's three buttons, `dockButtonSpacing`, `alignedToCanvasControls` and its `hidesSurroundingChrome` gate, the chooser and creator panels, and the completion island. The dock's "Add a happening" button stays the only route to free-text creation — the spec's "eleventh affordance" is that button, not an eleventh tile.

Replace the `HappeningLiquidField(...)` child with `HappeningShapeField(...)`.

Add the frosted background the spec calls for. The root overlay does not have one today — the only `.ultraThinMaterial` in this file is the scrim behind the chooser and creator panels. Put it on the backdrop that currently sits first in the `ZStack` as `Color.clear`, keeping its dismiss tap:

```swift
                Rectangle()
                    .fill(.ultraThinMaterial)
                    .ignoresSafeArea()
                    .contentShape(Rectangle())
                    .onTapGesture {
                        guard activePanel == nil else { return }
                        onDismiss()
                    }
```

Then add the hint above the field. `AppColors.Night.textSecondary` is a deliberate alias of `textPrimary` — hierarchy in this theme comes from opacity, so the hint needs it explicitly or it will read as loud as the labels:

```swift
                Text("Shake to change the shapes", comment: "Palette shake hint")
                    .font(.system(size: 13, weight: .regular, design: .rounded))
                    .foregroundStyle(AppColors.Night.textSecondary.opacity(0.6))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
                    .position(x: proxy.size.width / 2, y: proxy.safeAreaInsets.top + 24)
                    .accessibilityHidden(activePanel != nil)
```

The Russian string is about a quarter longer than the English and wraps to two lines on narrow screens and at accessibility type sizes. Give the field's bounds `proxy.safeAreaInsets.top + 56` as its top inset so a two-line hint cannot collide with the first row.

- [ ] **Step 4: Pass the figure through the pick**

In `GalleryView.handlePalettePick`, replace the random colour with the assigned figure, and thread it into `addAndSpawnHappening` and on into `CanvasElement.spawn(..., figure:)`:

```swift
    private func handlePalettePick(_ happening: Happening, origin: CGPoint) -> Bool {
        guard let figure = model.paletteFigures()[happening.id] else { return false }
        return addAndSpawnHappening(
            optionId: happening.id,
            color: figure.colorHex,
            figure: figure,
            recordUse: true,
            origin: origin
        )
    }
```

Add `figure: HappeningShapeAssignment? = nil` to `addAndSpawnHappening` and pass it to `CanvasElement.spawn`.

- [ ] **Step 5: Delete the liquid palette**

```bash
git rm StepsTrader/Views/Palette/HappeningLiquidField.swift StepsTrader/Views/Palette/HappeningLiquidLayout.swift Steps4Tests/HappeningLiquidLayoutTests.swift
```

Remove all four `project.pbxproj` entries for each of the three files. Then grep for stragglers:

```bash
grep -rn "HappeningLiquid" StepsTrader Steps4Tests Steps4UITests Steps4.xcodeproj/project.pbxproj
```

Expected: no matches. `HappeningLiquidSlotStyle` and any other type that lived in those files must have its still-used parts moved into `HappeningShapeField.swift` first.

- [ ] **Step 6: Build and run the whole unit suite**

Run: `xcodebuild test -project Steps4.xcodeproj -scheme Steps4 -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:Steps4Tests`

Expected: green. Tests that referenced the liquid layout are gone with it; anything else that fails is a real regression.

- [ ] **Step 7: Commit**

```bash
git add -A
git commit -m "feat: show happenings as the shapes they will become"
```

---

### Task 8: Shake to re-roll

**Files:**
- Modify: `StepsTrader/Views/Palette/HappeningPaletteView.swift`
- Test: `Steps4UITests/Steps4UITestsLaunchTests.swift`

**Interfaces:**
- Consumes: `AppModel.rerollPaletteFigures(on:)` (Task 5).

- [ ] **Step 1: Add the shake hook**

SwiftUI has no shake modifier. `UIDevice` posts `UIDevice.deviceDidShakeNotification` only if something forwards `motionEnded`; add the forwarding in an extension on `UIWindow` and observe the notification from the palette:

```swift
extension UIDevice {
    static let deviceDidShakeNotification = Notification.Name("deviceDidShakeNotification")
}

extension UIWindow {
    open override func motionEnded(_ motion: UIEvent.EventSubtype, with event: UIEvent?) {
        super.motionEnded(motion, with: event)
        guard motion == .motionShake else { return }
        NotificationCenter.default.post(name: UIDevice.deviceDidShakeNotification, object: nil)
    }
}
```

Then in `HappeningPaletteView`:

```swift
        .onReceive(NotificationCenter.default.publisher(for: UIDevice.deviceDidShakeNotification)) { _ in
            guard activePanel == nil else { return }
            if reduceMotion {
                onReroll()
            } else {
                withAnimation(.easeInOut(duration: 0.32)) { onReroll() }
            }
        }
```

`onReroll` is a new closure parameter on `HappeningPaletteView`, wired in `GalleryView` to `model.rerollPaletteFigures()`. Guarding on `activePanel == nil` keeps a shake from re-rolling behind the chooser or the creator.

- [ ] **Step 2: Give the fixture a way to fire a shake**

XCUITest cannot synthesise a device shake, so the app has to fire one on request. Follow the existing fixture convention — the Task 7 harness already reads `TASK7_DYNAMIC_TYPE_SIZE` and `TASK7_INCREASED_CONTRAST` from `launchEnvironment` (`Steps4UITestsLaunchTests.swift:254`, `:261`). Add a third:

```swift
        if ProcessInfo.processInfo.environment["TASK7_SHAKE_PALETTE"] == "1" {
            shakeTrigger
                .accessibilityIdentifier("task7_shake_trigger")
                .accessibilityLabel(Text(verbatim: "Fire shake"))
        }
```

where `shakeTrigger` is a plain `Button` posting `UIDevice.deviceDidShakeNotification`. It exists only under that environment variable, so it can never appear in the shipping app.

- [ ] **Step 3: Write the UI test**

```swift
    func testShakeChangesTheFieldWithoutTouchingTheDock() throws {
        let app = launchTask7App(dynamicTypeSize: "large", shakeTrigger: true)
        openPalette(in: app)

        XCTAssertTrue(app.staticTexts["Shake to change the shapes"].exists)
        XCTAssertTrue(app.buttons["Choose happenings"].isHittable)
        XCTAssertTrue(app.buttons["Close"].isHittable)
        XCTAssertTrue(app.buttons["Add a happening"].isHittable)

        for title in task7BuiltInTitles {
            XCTAssertTrue(app.buttons[title].exists, "Missing tile: \(title)")
        }

        app.buttons["Fire shake"].tap()
        attachScreenshot(named: "palette-shapes-after-shake")

        for title in task7BuiltInTitles {
            XCTAssertTrue(app.buttons[title].exists, "Tile disappeared on shake: \(title)")
        }
    }
```

Add the `shakeTrigger: Bool = false` parameter to `launchTask7App` and have it set `app.launchEnvironment["TASK7_SHAKE_PALETTE"] = "1"`.

The assertion this test can actually make is that shaking changes nothing structural — the ten tiles survive and the dock keeps exactly its three buttons. That the *figures* changed is checked by hand in Task 9; XCUITest cannot see a silhouette.

- [ ] **Step 4: Run the UI test**

Run: `xcodebuild test -project Steps4.xcodeproj -scheme Steps4 -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:Steps4UITests/Steps4UITestsLaunchTests/testShakeChangesTheFieldWithoutTouchingTheDock`

Expected: pass. The ten tiles survive the shake, the dock has exactly its three buttons, and the hint is on screen.

- [ ] **Step 5: Commit**

```bash
git add StepsTrader/Views/Palette/HappeningPaletteView.swift Steps4UITests/Steps4UITestsLaunchTests.swift Steps4.xcodeproj/project.pbxproj
git commit -m "feat: shake the palette to re-roll its figures"
```

---

### Task 9: Verify the whole thing by hand

Unit tests cannot see that a tile matches what landed on the canvas — that is the one claim this design is built on, and only a person can check it.

- [ ] **Step 1: Run the full scheme**

Run: `xcodebuild test -project Steps4.xcodeproj -scheme Steps4 -destination 'platform=iOS Simulator,name=iPhone 17'`

Expected: unit and UI tests green together. Run them in one invocation — the canvas fixtures interact across targets, which is what `CanvasPersistenceRegressionTests` exists to catch.

- [ ] **Step 2: Walk the acceptance criteria on the simulator**

Build, install, and check each by hand:

- Open the palette. Ten tiles, rows of 3-2-3-2, the twos offset into the gaps.
- Ten visibly different colours.
- Tap a tile. The figure that lands on the canvas is the same type, silhouette and colour as the tile was.
- The tile is gone and the rest re-flow.
- Close and reopen. The remaining tiles are unchanged.
- Shake. Every remaining tile changes type, silhouette and colour; the element already on the canvas does not.
- The hint is readable and does not collide with the first row — check at the largest accessibility type size, where the Russian string wraps.
- The dock has three buttons at the height the canvas `+` sits at.
- In Settings, restrict allowed shapes to one type, reopen the palette: all ten tiles use it and still differ by silhouette and colour.
- Move the day end past now so `dayKey` rolls, reopen: the whole set has changed.

- [ ] **Step 3: Check what ten live canvases cost**

The spec flags this: ten `Canvas` views over a blurred material is not free, and the liquid field it replaces was one canvas, not ten. Open and close the palette a dozen times on the oldest simulator available (`xcrun simctl list devices available` — pick the lowest-end iPhone there, not the newest), and watch for dropped frames on open and on shake.

If it stutters, the fix is to rasterise: render each tile once into an `Image` and redraw only when its figure changes. Do that before adding any further motion, not after.

- [ ] **Step 4: Report what you saw**

Write down the result of each check above, including anything that looked wrong. Do not mark the plan complete on a green test run alone — the test run cannot see the thing the design promises.
