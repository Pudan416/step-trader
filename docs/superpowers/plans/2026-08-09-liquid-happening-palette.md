# Liquid Happening Palette Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the approved native-SwiftUI `Living island` palette: ten user-selected happenings, one addition per happening per day, liquid removal/reflow, catalog chooser, and custom creation directly over the live canvas.

**Architecture:** Replace daily ranked palette caching with a persistent ten-id selection store. The domain layer rejects duplicate additions for a `dayKey`; the palette derives its live items by subtracting today's additions. A focused SwiftUI overlay renders an irregular metaball/mesh field over `GalleryView`, while pure layout and selection logic remain unit-testable.

**Tech Stack:** Swift 6, SwiftUI, native `Canvas`, `Shape`, `TimelineView`/animatable state, XCTest, existing `ProceduralShapeGenerator`, iOS Simulator (`iPhone 17`). No raster palette art and no third-party rendering dependency.

## Global Constraints

- The configured palette contains exactly 10 happening ids.
- A configured happening can be added at most once per custom `dayKey`.
- Logged happenings stay hidden until the next custom day; the palette remains open after each pick.
- The palette closes only through `×` or a tap on free canvas space outside the field and controls.
- The colored field is an irregular transparent overlay over the live canvas, never a rectangular sheet or bitmap.
- The approved visual direction is `Living island`: soft warm mesh color, organic asymmetry, restrained glass controls, and readable labels.
- Support VoiceOver, Dynamic Type, Reduce Motion, and iPhone 17 without scrolling the field.

---

## File Structure

- Create `StepsTrader/Models/HappeningPaletteSelection.swift`: pure validation, repair, replacement, and ordering rules.
- Create `StepsTrader/Stores/HappeningPaletteSelectionStore.swift`: persistence of the configured ten ids.
- Replace `StepsTrader/Models/HappeningPaletteOrder.swift`: remove daily ranking/cache behavior after migration.
- Create `StepsTrader/Views/Palette/HappeningLiquidLayout.swift`: deterministic sources and hit regions for counts 0...10.
- Create `StepsTrader/Views/Palette/HappeningLiquidField.swift`: native rendering and removal transition.
- Rewrite `StepsTrader/Views/Palette/HappeningPaletteView.swift`: overlay composition and state machine.
- Create `StepsTrader/Views/Palette/HappeningChooserView.swift`: complete catalog checklist.
- Rewrite `StepsTrader/Views/Palette/HappeningFreeTextField.swift` as the compact creator panel.
- Modify `StepsTrader/AppModel+DailyEnergy.swift`: selection access, available-today derivation, and duplicate guard.
- Modify `StepsTrader/AppModel.swift`: own the selection store instead of the daily order cache.
- Modify `StepsTrader/Utilities/SharedKeys.swift`: add the v2 selection key and retain v1 keys only for migration.
- Modify `StepsTrader/Views/GalleryView.swift`: present the palette as a canvas overlay and coordinate spawn motion.
- Modify `StepsTrader/Views/MainTabView.swift`: remove duplicate sheet ownership and route external palette requests to canvas.
- Replace `Steps4Tests/HappeningPaletteOrderTests.swift` with `Steps4Tests/HappeningPaletteSelectionTests.swift`.
- Create `Steps4Tests/HappeningLiquidLayoutTests.swift`.
- Modify `Steps4Tests/HappeningAdditionsTests.swift`: enforce one id per day.

---

### Task 1: Persistent Ten-Slot Selection

**Files:**
- Create: `StepsTrader/Models/HappeningPaletteSelection.swift`
- Create: `StepsTrader/Stores/HappeningPaletteSelectionStore.swift`
- Modify: `StepsTrader/Utilities/SharedKeys.swift`
- Delete: `StepsTrader/Models/HappeningPaletteOrder.swift`
- Replace: `Steps4Tests/HappeningPaletteOrderTests.swift` → `Steps4Tests/HappeningPaletteSelectionTests.swift`
- Modify: `Steps4.xcodeproj/project.pbxproj`

**Interfaces:**
- Produces: `HappeningPaletteSelection.repaired(ids:catalog:defaults:) -> [String]`
- Produces: `HappeningPaletteSelection.replacingLeastUsed(in:with:catalog:) -> [String]`
- Produces: `HappeningPaletteSelectionStore.ids`, `save(_:)`, and `insertReplacingLeastUsed(_:catalog:)`

- [ ] **Step 1: Write failing selection tests**

Cover: first launch seeds the ten built-ins in source order; unknown ids are removed and deterministically refilled; duplicates are removed; saving anything except ten live ids fails without changing stored state; a new custom id replaces the least-used visible id; ties use oldest `lastUsedAt`, then current slot order; the replaced catalog item is not deleted; v1 frozen order migrates once only when it contains ten live ids.

Use this core assertion shape:

```swift
func testCustomHappeningReplacesLeastUsedSlot() throws {
    let catalog = makeCatalog(counts: [5, 4, 3, 2, 1, 0, 8, 7, 6, 9])
        + [Happening(id: "user_sauna", title: "Sauna", isBuiltIn: false)]
    let store = HappeningPaletteSelectionStore(defaults: defaults)
    try store.save(Array(catalog.prefix(10).map(\.id)), catalog: catalog)

    let removed = try store.insertReplacingLeastUsed("user_sauna", catalog: catalog)

    XCTAssertEqual(removed, catalog[5].id)
    XCTAssertEqual(store.ids[5], "user_sauna")
    XCTAssertEqual(store.ids.count, 10)
}
```

- [ ] **Step 2: Run the focused tests and verify red**

Run:

```bash
xcodebuild test -project Steps4.xcodeproj -scheme Steps4 -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:Steps4Tests/HappeningPaletteSelectionTests
```

Expected: compile failure because the selection types do not exist.

- [ ] **Step 3: Implement pure rules and persistence**

Use a throwing save API so invalid transient chooser state never reaches disk:

```swift
enum HappeningPaletteSelectionError: Error, Equatable { case requiresExactlyTen }

enum HappeningPaletteSelection {
    static let slotCount = 10
    static func repaired(ids: [String], catalog: [Happening], defaults: [String]) -> [String]
    static func replacementIndex(in ids: [String], catalog: [Happening]) -> Int
}

final class HappeningPaletteSelectionStore {
    private(set) var ids: [String] = []
    func load(catalog: [Happening])
    func save(_ ids: [String], catalog: [Happening]) throws
    @discardableResult
    func insertReplacingLeastUsed(_ id: String, catalog: [Happening]) throws -> String
}
```

Add `SharedKeys.happeningPaletteSelection = "happeningPaletteSelection_v2"`. Read the old `paletteOrderIds_v1` only during initial migration; stop writing the v1 day key and order.

- [ ] **Step 4: Run focused tests and the existing model/store suites**

Run:

```bash
xcodebuild test -project Steps4.xcodeproj -scheme Steps4 -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:Steps4Tests/HappeningPaletteSelectionTests -only-testing:Steps4Tests/HappeningStoreTests -only-testing:Steps4Tests/HappeningModelTests
```

Expected: all selected suites pass.

- [ ] **Step 5: Commit**

```bash
git add StepsTrader/Models/HappeningPaletteSelection.swift StepsTrader/Stores/HappeningPaletteSelectionStore.swift StepsTrader/Utilities/SharedKeys.swift Steps4Tests/HappeningPaletteSelectionTests.swift Steps4.xcodeproj/project.pbxproj
git rm StepsTrader/Models/HappeningPaletteOrder.swift Steps4Tests/HappeningPaletteOrderTests.swift
git commit -m "feat: persist ten happening palette slots"
```

### Task 2: One Happening Addition Per Custom Day

**Files:**
- Modify: `StepsTrader/AppModel.swift`
- Modify: `StepsTrader/AppModel+DailyEnergy.swift`
- Modify: `Steps4Tests/HappeningAdditionsTests.swift`

**Interfaces:**
- Consumes: `HappeningPaletteSelectionStore.ids`
- Produces: `configuredPaletteHappenings() -> [Happening]`
- Produces: `availablePaletteHappenings(on:) -> [Happening]`
- Changes: `addHappening(id:colorHex:at:recordUse:) -> OptionEntry?`

- [ ] **Step 1: Replace repeat-addition tests with duplicate-guard tests**

Test that the first addition returns an entry, a second addition of the same id and day returns `nil`, no second use is recorded or sync-triggering state appended, a different id succeeds, removing today's entry makes that id available again, and the same id succeeds on a new `dayKey`.

```swift
func testDuplicateHappeningIsRejectedWithinCustomDay() throws {
    let model = makeModel()
    let date = Date(timeIntervalSince1970: 1_786_176_000)
    XCTAssertNotNil(model.addHappening(id: "happening_walk", colorHex: "#AABBCC", at: date))
    XCTAssertNil(model.addHappening(id: "happening_walk", colorHex: "#DDEEFF", at: date.addingTimeInterval(1)))
    XCTAssertEqual(model.todayAdditions.map(\.optionId), ["happening_walk"])
}
```

- [ ] **Step 2: Run the focused suite and verify the duplicate test fails**

Run the `HappeningAdditionsTests` suite on iPhone 17. Expected: duplicate is appended by the current implementation.

- [ ] **Step 3: Add domain-level deduplication and palette derivation**

At the start of `addHappening`, compute the requested `dayKey` and guard that no existing entry has the same `(dayKey, optionId)`. Return `nil` without mutation when duplicated. Load the selection store after `happeningStore.load()` and implement:

```swift
func availablePaletteHappenings(on date: Date = .now) -> [Happening] {
    let used = Set(todayAdditions.lazy
        .filter { $0.dayKey == Self.dayKey(for: date) }
        .map(\.optionId))
    return configuredPaletteHappenings().filter { !used.contains($0.id) }
}
```

Creation remains catalog-only; it must not call `addHappening`. Change
`HappeningStore.create` so a new item starts with `useCount == 0` and
`lastUsedAt == nil`; only a successful daily addition records use. Update the
existing store/addition tests that previously treated creation itself as use.

- [ ] **Step 4: Run additions, economy, migration, and sync suites**

Run `HappeningAdditionsTests`, `DailyEnergyLogicTests`, `HappeningMigrationTests`, and sync tests matching `rg -l 'OptionEntry' Steps4Tests`.

Expected: all pass; economy still counts distinct additions and caps at 60.

- [ ] **Step 5: Commit**

```bash
git add StepsTrader/AppModel.swift StepsTrader/AppModel+DailyEnergy.swift Steps4Tests/HappeningAdditionsTests.swift
git commit -m "feat: limit happenings to once per day"
```

### Task 3: Deterministic Liquid Layout

**Files:**
- Create: `StepsTrader/Views/Palette/HappeningLiquidLayout.swift`
- Create: `Steps4Tests/HappeningLiquidLayoutTests.swift`
- Modify: `Steps4.xcodeproj/project.pbxproj`
- Delete after migration: `StepsTrader/Views/Palette/HappeningBlobLayout.swift`
- Delete after migration: `Steps4Tests/HappeningBlobLayoutTests.swift`

**Interfaces:**
- Produces: `HappeningLiquidLayout.layout(count:in:safeInsets:) -> Layout`
- `Layout` contains `sources`, `labelFrames`, `contourBounds`, and `dockAnchor`.

- [ ] **Step 1: Write failing geometry tests for counts 0...10**

For every count assert: one source and non-overlapping minimum 44×44 label hit frame per item; all hit frames fit within safe bounds; the contour leaves tappable free canvas on every edge; dock anchor is below but visually touches the contour; relative item order is preserved after 10→9→8; zero items returns an empty field and a valid close dock.

```swift
func testRemovingIndexPreservesRelativeIdentityOrder() {
    let before = HappeningLiquidLayout.layout(count: 10, in: size, safeInsets: .zero)
    let after = HappeningLiquidLayout.layout(count: 9, in: size, safeInsets: .zero)
    XCTAssertEqual(before.labelFrames.count, 10)
    XCTAssertEqual(after.labelFrames.count, 9)
    XCTAssertTrue(after.contourBounds.width < size.width)
}
```

- [ ] **Step 2: Run the layout suite and verify red**

Expected: compile failure because `HappeningLiquidLayout` is missing.

- [ ] **Step 3: Implement normalized Living-island templates**

Use hand-tuned normalized source templates for 0...10 rather than physics simulation. Interpolate source centers/radii between old and new layouts in the view. Keep geometry deterministic for stable labels and tests. Use a larger irregular outer silhouette and separate rectangular hit frames; visual overlap must never imply hit overlap.

- [ ] **Step 4: Run layout tests and inspect a debug preview grid**

Add a development-only `#Preview` showing counts 10, 9, 6, 3, and 0. Verify no clipping at iPhone 17 logical size and at accessibility text sizes.

- [ ] **Step 5: Commit**

```bash
git add StepsTrader/Views/Palette/HappeningLiquidLayout.swift Steps4Tests/HappeningLiquidLayoutTests.swift Steps4.xcodeproj/project.pbxproj
git rm StepsTrader/Views/Palette/HappeningBlobLayout.swift Steps4Tests/HappeningBlobLayoutTests.swift
git commit -m "feat: add adaptive liquid palette layout"
```

### Task 4: Native SwiftUI Living-Island Renderer and Motion

**Files:**
- Create: `StepsTrader/Views/Palette/HappeningLiquidField.swift`
- Modify: `StepsTrader/Views/Palette/HappeningPaletteView.swift`
- Modify: `Steps4.xcodeproj/project.pbxproj`

**Interfaces:**
- Consumes: ordered `[Happening]`, `HappeningLiquidLayout.Layout`, `dayKey`, and `onPick(Happening, CGPoint)`.
- Produces: native transparent field and `RemovalPhase` motion (`idle`, `pressing`, `sinking`, `reflowing`).

- [ ] **Step 1: Add a preview harness with deterministic data**

The preview must expose buttons for 10→9→8 and a Reduce Motion toggle. Use the production palette colors and real titles, not placeholders.

- [ ] **Step 2: Build the field with native drawing only**

Render the contour through existing `ProceduralShapeGenerator.metaballPath`. Render the interior through SwiftUI `Canvas` using overlapping radial gradients clipped to the contour, plus a restrained blur/luminance pass. Keep the parent background `Color.clear`; do not use `.presentationBackground`, a full-screen material, or any rectangular field fill.

Place labels in independent layout frames above the Canvas. Apply contrast from sampled source luminance, 2–3 lines maximum, minimum scale factor 0.78, and explicit accessibility button traits.

- [ ] **Step 3: Implement the selected-zone transition**

On tap: lock that id, animate scale to 0.92 for 120 ms, contract its source radius/text opacity toward the sink point, call `onPick` at breakthrough, remove the id from local presentation state, and spring remaining sources to the smaller-count template over 380 ms. Keep the overlay mounted. Trigger one light sensory feedback at breakthrough.

For `accessibilityReduceMotion`, use 150 ms opacity removal followed by immediate layout replacement. Ignore duplicate taps while an id is in a non-idle phase.

- [ ] **Step 4: Add view-inspection seams and verify interaction state**

Keep transition state in a small internal model whose pure `beginRemoval(id:)` and `finishRemoval(id:)` behavior can be tested without pixel assertions. Verify a second tap on the same id is ignored and another id becomes tappable after reflow.

- [ ] **Step 5: Build on iPhone 17**

Run:

```bash
xcodebuild build -project Steps4.xcodeproj -scheme Steps4 -destination 'platform=iOS Simulator,name=iPhone 17'
```

Expected: `BUILD SUCCEEDED`, no Swift concurrency or deprecated-animation warnings introduced.

- [ ] **Step 6: Commit**

```bash
git add StepsTrader/Views/Palette/HappeningLiquidField.swift StepsTrader/Views/Palette/HappeningPaletteView.swift Steps4.xcodeproj/project.pbxproj
git commit -m "feat: render liquid happening field"
```

### Task 5: Catalog Chooser and Custom Creator

**Files:**
- Create: `StepsTrader/Views/Palette/HappeningChooserView.swift`
- Modify: `StepsTrader/Views/Palette/HappeningFreeTextField.swift`
- Modify: `StepsTrader/Views/Palette/HappeningPaletteView.swift`
- Modify: `StepsTrader/Stores/HappeningPaletteSelectionStore.swift`
- Modify: `Steps4Tests/HappeningPaletteSelectionTests.swift`
- Modify: `Steps4.xcodeproj/project.pbxproj`

**Interfaces:**
- Chooser input: full `[Happening]`, selected `[String]`, `onSave([String])`.
- Creator input: `onCreate(String)`; parent creates catalog item and calls `insertReplacingLeastUsed`.

- [ ] **Step 1: Add tests for transactional chooser edits and creation replacement**

Test that cancelled drafts do not persist, `Done` requires exactly ten unique live ids, catalog order is stable, and creation replaces the deterministic slot without logging an addition.

- [ ] **Step 2: Implement the chooser panel**

Use a compact floating panel over the dimmed field, not a system full-screen sheet. Include `Choose happenings`, `N of 10 selected`, searchable scroll content, circular checks, Cancel, and Done. When ten are selected, tapping an unchecked item should announce that one must be deselected first. Preserve surviving slot order and append newly checked ids in check order.

- [ ] **Step 3: Implement the creator panel**

Use `Add a happening`, one focused text field, `Add to palette`, and the message `This will replace one of the 10 shown happenings.` Trim whitespace, reject blank input, allow duplicate titles, and dismiss the keyboard interactively. Creation closes only the panel; the liquid palette stays open and highlights the inserted zone.

- [ ] **Step 4: Verify Dynamic Type and VoiceOver order in previews**

Ensure panels scroll at accessibility sizes and focus order is heading → status → rows/input → actions. Side controls are labelled `Choose happenings`, `Close`, and `Add a happening`.

- [ ] **Step 5: Run focused tests and build**

Run selection tests and the iPhone 17 build. Expected: pass.

- [ ] **Step 6: Commit**

```bash
git add StepsTrader/Views/Palette/HappeningChooserView.swift StepsTrader/Views/Palette/HappeningFreeTextField.swift StepsTrader/Views/Palette/HappeningPaletteView.swift StepsTrader/Stores/HappeningPaletteSelectionStore.swift Steps4Tests/HappeningPaletteSelectionTests.swift Steps4.xcodeproj/project.pbxproj
git commit -m "feat: manage happening palette catalog"
```

### Task 6: Canvas Overlay Integration

**Files:**
- Modify: `StepsTrader/Views/GalleryView.swift`
- Modify: `StepsTrader/Views/MainTabView.swift`
- Modify: `StepsTrader/AppModel+DailyEnergy.swift`

**Interfaces:**
- Consumes: `model.availablePaletteHappenings()`, full catalog, selection-store actions.
- Produces: one source of palette presentation truth inside `GalleryView`.

- [ ] **Step 1: Remove both `.sheet(isPresented: $showHappeningPalette)` paths**

`GalleryView` owns the overlay because it has the live canvas and spawn functions. `MainTabView` must route a request from another tab by selecting the canvas tab and posting a palette-open notification after the tab transition; it must not render a second palette instance.

- [ ] **Step 2: Mount the palette as a transparent ZStack overlay**

Layer order: canvas elements → existing texture → palette field → palette labels and dock → top balance card/tab bar as required by safe-area layout. Add a full-screen clear outside-tap surface behind the contour but above the canvas; use the contour/hit regions to prevent inside taps from dismissing. Keep the tab bar visible but noninteractive while the palette is open.

- [ ] **Step 3: Connect removal breakthrough to canvas spawn**

Change `addAndSpawnHappening` to
`@discardableResult func addAndSpawnHappening(optionId:color:recordUse:origin:) -> Bool`.
It remains the single function that calls `model.addHappening`; when that call
returns `nil`, return `false` without creating a canvas element. On success,
animate the element from the supplied field sink coordinate into its normal
canvas position and return `true`. The field removes the zone only after
`true`; on `false` it cancels the sink and restores the zone. Do not close the
palette. Refresh available items from model state after persistence.

- [ ] **Step 4: Connect chooser and creator**

Chooser saves configured ids and refreshes the field minus today's used ids. Creator calls `model.createHappening`, inserts it into the configured ten without adding to today, and refreshes/highlights the replacement slot.

- [ ] **Step 5: Verify dismissal and day rollover**

Exercise: `×`, outside tap, inside-blob tap, side controls, keyboard dismissal, app background/foreground, and a custom-day boundary. At rollover all configured ids must reappear without recreating the overlay.

- [ ] **Step 6: Run all tests and commit**

```bash
xcodebuild test -project Steps4.xcodeproj -scheme Steps4 -destination 'platform=iOS Simulator,name=iPhone 17'
git add StepsTrader/Views/GalleryView.swift StepsTrader/Views/MainTabView.swift StepsTrader/AppModel+DailyEnergy.swift
git commit -m "feat: overlay happening palette on canvas"
```

### Task 7: Art-Direction and Simulator Verification Pass

**Files:**
- Modify as findings require: `StepsTrader/Views/Palette/HappeningLiquidField.swift`
- Modify as findings require: `StepsTrader/Views/Palette/HappeningPaletteView.swift`
- Modify as findings require: `StepsTrader/Views/Palette/HappeningChooserView.swift`
- Modify as findings require: `StepsTrader/Views/Palette/HappeningFreeTextField.swift`

**Interfaces:**
- No new product behavior. This task is a visual acceptance gate.

- [ ] **Step 1: Build and launch iPhone 17 simulator**

Start from a clean install with the default ten. Capture: closed canvas, open 10-item field, 9-item reflow, 8-item reflow, chooser, creator, newly inserted custom item, and all-items-used state.

- [ ] **Step 2: Review screenshots against the approved Living-island direction**

Check: silhouette is visibly irregular; no rectangular field/background is visible; canvas texture and elements remain legible around the field; colors blend without muddy gray seams; labels have deliberate hierarchy and no collisions; the three-control dock reads as attached but not fused; top card and tab bar do not compete; field has breathing room on all edges.

- [ ] **Step 3: Review motion at normal and 0.25× simulator speed**

Record 10→9 and 3→2. Reject the result if the selected zone merely fades, remaining labels jump, contour clips, color flashes, or the field closes. Tune spring, sink point, and source interpolation until the motion reads as one continuous material.

- [ ] **Step 4: Run accessibility matrix**

Verify Reduce Motion, Increase Contrast, VoiceOver, and an accessibility Dynamic Type size. Confirm every remaining happening is reachable and outside-tap dismissal does not steal label taps.

- [ ] **Step 5: Run final verification from a clean build**

```bash
xcodebuild clean build test -project Steps4.xcodeproj -scheme Steps4 -destination 'platform=iOS Simulator,name=iPhone 17'
git diff --check
git status --short
```

Expected: build and all tests pass; only intentional files are modified.

- [ ] **Step 6: Commit visual polish**

```bash
git add StepsTrader/Views/Palette
git commit -m "polish: refine liquid happening palette"
```

Do not create an empty polish commit when screenshot review requires no changes.
