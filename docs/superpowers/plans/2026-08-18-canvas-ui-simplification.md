# Canvas UI Simplification Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the Canvas screen's large expandable balance card and mixed edit chrome with a compact daily-energy pill, a fixed three-control bottom row, a Data bottom sheet, a viewing-only Full screen mode, and an Editing mode limited to dragging elements and a batch Remix.

**Architecture:** Three pure, unit-testable value types carry all logic — `CanvasEnergyStatus` (clamped daily readout), `CanvasPresentationState` (a four-state machine that replaces the ad-hoc `isWideCanvas` + `editState.isEditMode` pair), and `CanvasRemix` (batch re-roll preserving identity and position). Five new dumb SwiftUI components render each state from props. `GalleryView` keeps ownership of persistence and canvas data and becomes the only place the state machine is driven; `MainTabView` renders the pill and keeps hiding chrome for wide/editing/Me.

**Tech Stack:** Swift 6, SwiftUI (iOS deployment target 26.1), XCTest, XCUITest, Xcode project file with explicit source membership.

**Spec:** `docs/design/2026-08-16-canvas-ui-simplification-spec.md`

## Global Constraints

- Read the spec before editing. Run `git status --short` first: the worktree already contains unrelated uncommitted changes (Rich Canvas experiment, Me, Feeds, Supabase, tests). **Preserve them.** Never run `git add -A` or `git commit -a`; stage exactly the files each task owns, and use `git add -p` where a file already carries unrelated changes.
- Do not change the energy formula, HealthKit, Supabase, App Group, or day-boundary contracts.
- Do not change the persisted `CanvasElement` JSON schema. Remix writes only existing mutable fields.
- No new persisted presentation-state key. Canvas/Data/FullScreen/Editing are transient `@State`.
- Do not change the bottom tab bar (Canvas / Feeds / Me) or the data-driven background gradient.
- Do not hand-edit `StepsTrader/Localizable.xcstrings`. New `String(localized:)` keys are extracted by Xcode at build time; if the file changes after a build, stage only the new keys with `git add -p`. The file already has unrelated pending changes.
- Reuse existing primitives only: `AppColors.brandAccent`, `AppColors.Night.textPrimary`, `AppAccentInk.primary`, `glassCard(cornerRadius:style:)`, `liquidGlassControl(in:style:)`, `GlassEffectContainer`, `minimumHitTarget()`, `contrastingOnGlass()`. Never introduce a second yellow or a hand-rolled glass implementation.
- Every new source and test file needs four explicit `project.pbxproj` entries: a `PBXBuildFile`, a `PBXFileReference`, a `PBXGroup` `children` entry, and a Sources build-phase entry. Add each next to the anchor file named in the task so it lands in the right group and target.
- Use the ID prefixes reserved by this plan (listed per task) so IDs cannot collide with existing ones.
- Simulator build command:
  `xcodebuild build -project Steps4.xcodeproj -scheme Steps4 -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17,OS=latest' CODE_SIGNING_ALLOWED=NO`
- Unit-test command:
  `xcodebuild test -project Steps4.xcodeproj -scheme Steps4 -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17,OS=latest' -only-testing:Steps4Tests CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO`
- UI-test command:
  `xcodebuild test -project Steps4.xcodeproj -scheme Steps4 -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17,OS=latest' -only-testing:Steps4UITests CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO`
- Any manual check in the simulator must launch the app with the `ui-testing` launch
  argument. `StepsTraderApp.swift` passes `requestPermissions: !isUITest` to
  `model.bootstrap`, so without that flag a Screen Time / FamilyControls authorization
  alert appears on first launch and swallows every touch, making the screen impossible
  to drive. It also skips the pay gate, the quick-status page and handoff protection.
- Before every commit run `git diff --cached --check` and confirm `git diff --cached --name-only` lists only that task's files.

## Decisions taken on top of the spec

These four points were ambiguous or self-contradictory in the spec and were resolved with the product owner before planning. Implement them as written here.

1. **Share moves into the Full screen dock.** The spec fixes the Canvas bottom row at exactly three controls, which evicts the existing Share button along with its `Save as Routine` / apply-routine context menu. The Full-screen dock becomes `Exit full screen · Share · Edit`.
2. **Delete survives as a long press.** §7.2 removes the per-element `x`, which is the only delete affordance in the app. Editing keeps deletion behind a long press on the selected element plus a confirmation dialog — no permanently visible per-element button, so the spec's visual rule holds.
3. **The pill replaces the card everywhere it is shown today** — Canvas and Feeds. `StepBalanceCard.swift` is deleted. Consequence: the card's "tap Happenings from Feeds to open the palette on Canvas" shortcut disappears; the pill is a non-interactive readout per §4.2/§11.
4. **Coach marks re-anchor to Show data, not to the full-screen circle.** §17 asks for the expand anchor on the bottom-left circle, but `.expandChevron` only advances on tap, and tapping the full-screen circle hides all chrome — leaving the next tour step (`.categoriesRevealed`) with no anchor. Mapping: `.colorBalance` → energy pill, `.expandChevron` → Show data pill, `.categoriesRevealed` → data panel rows, `.tapPlusButton` → yellow Add circle. `CoachMarkStep` and `CoachMarkTourTests` stay untouched.

## File Map

### New app files

- `StepsTrader/Models/CanvasEnergyStatus.swift` — clamped `remaining / earned` readout and its progress fraction.
- `StepsTrader/Models/CanvasRemix.swift` — batch re-roll over `[CanvasElement]` preserving identity, position and count.
- `StepsTrader/Views/Gallery/CanvasPresentationState.swift` — the four-state machine, its derived chrome flags, and analytics event names.
- `StepsTrader/Views/Gallery/CanvasEnergyStatusPill.swift` — top-center compact status pill.
- `StepsTrader/Views/Gallery/CanvasFullScreenDock.swift` — Exit / Share / Edit dock.
- `StepsTrader/Views/Gallery/CanvasBottomActionRow.swift` — Full screen / Show data / Add row.
- `StepsTrader/Views/Gallery/CanvasDataPanel.swift` — Data bottom sheet, its rows, and its max-height rule.
- `StepsTrader/Views/Gallery/CanvasEditingDock.swift` — Done control, Remix capsule, one-time drag coach text.

### Modified app files

- `StepsTrader/Views/MainTabView.swift` — renders the pill instead of the card; drops the colors-help overlay and the cross-tab palette shortcut.
- `StepsTrader/Views/GalleryView.swift` — owns `CanvasPresentationState`; new bottom row, dock, data panel, editing chrome; simplified edit gestures; Remix; analytics.
- `StepsTrader/Views/Gallery/CanvasStateManagers.swift` — `CanvasEditState` loses `isEditMode`, `gestureStartRotation`, `gestureStartSize`.
- `StepsTrader/Models/CanvasElement.swift` — `reroll` gains injectable `allowedShapes` and `at:` date.
- `Steps4.xcodeproj/project.pbxproj` — membership for new and deleted files.

### Deleted app files

- `StepsTrader/Views/Components/StepBalanceCard.swift`

### New tests

- `Steps4Tests/CanvasEnergyStatusTests.swift`
- `Steps4Tests/CanvasPresentationStateTests.swift`
- `Steps4Tests/CanvasRemixTests.swift`
- `Steps4Tests/CanvasDataPanelLayoutTests.swift`
- `Steps4UITests/CanvasSimplificationUITests.swift`

---

## Task 1: Daily energy status model

**Files:**
- Create: `StepsTrader/Models/CanvasEnergyStatus.swift`
- Test: `Steps4Tests/CanvasEnergyStatusTests.swift`
- Modify: `Steps4.xcodeproj/project.pbxproj`

**Interfaces:**
- Consumes: nothing.
- Produces: `struct CanvasEnergyStatus: Equatable` with `init(stepsBalance: Int, baseEnergyToday: Int)`, `let remaining: Int`, `let earned: Int`, `var progress: Double`.

- [ ] **Step 1: Write the failing test**

Create `Steps4Tests/CanvasEnergyStatusTests.swift`:

```swift
import XCTest
@testable import Steps4

/// The Canvas status pill answers one question: how much of what was earned
/// today is still unspent. Bonus balance and the product-wide 100 ceiling are
/// deliberately outside it, so the numbers can never disagree with the bar.
final class CanvasEnergyStatusTests: XCTestCase {

    func testShowsRemainingOutOfEarned() {
        let status = CanvasEnergyStatus(stepsBalance: 58, baseEnergyToday: 72)

        XCTAssertEqual(status.remaining, 58)
        XCTAssertEqual(status.earned, 72)
        XCTAssertEqual(status.progress, 58.0 / 72.0, accuracy: 0.0001)
    }

    func testNothingEarnedYetShowsZeroOverZero() {
        let status = CanvasEnergyStatus(stepsBalance: 0, baseEnergyToday: 0)

        XCTAssertEqual(status.remaining, 0)
        XCTAssertEqual(status.earned, 0)
        XCTAssertEqual(status.progress, 0, accuracy: 0.0001)
    }

    func testEverythingSpentKeepsTheEarnedTrack() {
        let status = CanvasEnergyStatus(stepsBalance: 0, baseEnergyToday: 40)

        XCTAssertEqual(status.remaining, 0)
        XCTAssertEqual(status.earned, 40)
        XCTAssertEqual(status.progress, 0, accuracy: 0.0001)
    }

    /// A stale balance can outrun today's earnings between a recalculation and
    /// a HealthKit refresh. The pill must never claim more left than gained.
    func testStaleBalanceClampsToEarned() {
        let status = CanvasEnergyStatus(stepsBalance: 90, baseEnergyToday: 72)

        XCTAssertEqual(status.remaining, 72)
        XCTAssertEqual(status.progress, 1.0, accuracy: 0.0001)
    }

    func testNegativeInputsFloorAtZero() {
        let status = CanvasEnergyStatus(stepsBalance: -5, baseEnergyToday: -10)

        XCTAssertEqual(status.remaining, 0)
        XCTAssertEqual(status.earned, 0)
        XCTAssertEqual(status.progress, 0, accuracy: 0.0001)
    }

    /// The pill takes the daily balance, never `totalStepsBalance` — a bonus
    /// top-up must not make today look richer than it was.
    func testEqualInputsProduceEqualStatuses() {
        XCTAssertEqual(
            CanvasEnergyStatus(stepsBalance: 12, baseEnergyToday: 30),
            CanvasEnergyStatus(stepsBalance: 12, baseEnergyToday: 30)
        )
    }
}
```

- [ ] **Step 2: Add both files to the Xcode project**

Edit `Steps4.xcodeproj/project.pbxproj` and add four entries per file.

App file — anchor on `CanvasElement.swift`:
- In `PBXBuildFile`, next to the `CanvasElement.swift in Sources` line:
  `		CA51B0010000000000000001 /* CanvasEnergyStatus.swift in Sources */ = {isa = PBXBuildFile; fileRef = CA51F0010000000000000001 /* CanvasEnergyStatus.swift */; };`
- In `PBXFileReference`, next to the `CanvasElement.swift */ = {isa = PBXFileReference` line:
  `		CA51F0010000000000000001 /* CanvasEnergyStatus.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = CanvasEnergyStatus.swift; sourceTree = "<group>"; };`
- In the `PBXGroup` `children` list that already contains `30CA0002300000000000CA02 /* CanvasElement.swift */`:
  `				CA51F0010000000000000001 /* CanvasEnergyStatus.swift */,`
- In the Sources build phase that already contains `30CA0001300000000000CA01 /* CanvasElement.swift in Sources */`:
  `				CA51B0010000000000000001 /* CanvasEnergyStatus.swift in Sources */,`

Test file — anchor on `MainTabSelectionTests.swift` (its `PBXGroup` and its Sources phase belong to the `Steps4Tests` target):
- `		CA51B0110000000000000011 /* CanvasEnergyStatusTests.swift in Sources */ = {isa = PBXBuildFile; fileRef = CA51F0110000000000000011 /* CanvasEnergyStatusTests.swift */; };`
- `		CA51F0110000000000000011 /* CanvasEnergyStatusTests.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = CanvasEnergyStatusTests.swift; sourceTree = "<group>"; };`
- `				CA51F0110000000000000011 /* CanvasEnergyStatusTests.swift */,` in the children list holding `ME7A00ME7A00ME7A00F010 /* MainTabSelectionTests.swift */`
- `				CA51B0110000000000000011 /* CanvasEnergyStatusTests.swift in Sources */,` in the Sources phase holding `ME7A00ME7A00ME7A00F011 /* MainTabSelectionTests.swift in Sources */`

- [ ] **Step 3: Run the test to verify it fails**

Run:

```bash
xcodebuild test -project Steps4.xcodeproj -scheme Steps4 -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17,OS=latest' -only-testing:Steps4Tests/CanvasEnergyStatusTests CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO
```

Expected: compile failure — `cannot find 'CanvasEnergyStatus' in scope`.

- [ ] **Step 4: Write the implementation**

Create `StepsTrader/Models/CanvasEnergyStatus.swift`:

```swift
import Foundation

/// The daily energy readout behind the Canvas status pill.
///
/// It answers exactly one question — how much of what was *earned today* is
/// still unspent — so the two numbers can never disagree with the bar between
/// them. Deliberately excluded: `bonusSteps`, `totalStepsBalance`, and the
/// product-wide 100 ceiling. Those describe the wallet, not the day.
struct CanvasEnergyStatus: Equatable {
    /// Unspent energy from today's earnings, clamped into `0...earned`.
    let remaining: Int
    /// Energy gained today. The progress track represents this, not 100.
    let earned: Int

    /// - Parameters:
    ///   - stepsBalance: `model.userEconomyStore.stepsBalance` — the daily
    ///     balance without bonuses.
    ///   - baseEnergyToday: `model.healthStore.baseEnergyToday`.
    init(stepsBalance: Int, baseEnergyToday: Int) {
        let earned = max(0, baseEnergyToday)
        self.earned = earned
        // A recalculation can land before a HealthKit refresh, leaving a
        // balance that outruns today's earnings. Showing `90 / 72` would read
        // as a bug, so the stale side loses.
        self.remaining = min(max(0, stepsBalance), earned)
    }

    /// Fill fraction of the progress track. Zero when nothing was earned —
    /// an empty day shows an empty bar, not a full one.
    var progress: Double {
        guard earned > 0 else { return 0 }
        return Double(remaining) / Double(earned)
    }
}
```

- [ ] **Step 5: Run the test to verify it passes**

Run the same command as Step 3. Expected: 6 tests pass, 0 failures.

- [ ] **Step 6: Commit**

```bash
git add StepsTrader/Models/CanvasEnergyStatus.swift Steps4Tests/CanvasEnergyStatusTests.swift Steps4.xcodeproj/project.pbxproj && git commit -m "feat: add canvas energy status model"
```

---

## Task 2: Canvas presentation state machine

**Files:**
- Create: `StepsTrader/Views/Gallery/CanvasPresentationState.swift`
- Test: `Steps4Tests/CanvasPresentationStateTests.swift`
- Modify: `Steps4.xcodeproj/project.pbxproj`

**Interfaces:**
- Consumes: nothing.
- Produces:
  - `enum CanvasPresentationState: String, CaseIterable, Equatable { case canvas, data, fullScreen, editing }`
  - `enum CanvasPresentationEvent: Equatable { case showData, hideData, enterFullScreen, exitFullScreen, beginEditing, endEditing, openHappeningPalette, leftCanvasTab, dayBoundary }`
  - `func applying(_ event: CanvasPresentationEvent) -> CanvasPresentationState`
  - Derived flags: `isWideCanvas`, `isEditing`, `showsStatusPill`, `showsBottomActionRow`, `showsDataPanel`, `showsFullScreenDock`, `showsEditingChrome`
  - `static func analyticsEventName(from: CanvasPresentationState, to: CanvasPresentationState) -> String?`

- [ ] **Step 1: Write the failing test**

Create `Steps4Tests/CanvasPresentationStateTests.swift`:

```swift
import XCTest
@testable import Steps4

/// Canvas has four mutually exclusive presentation states. The combinations the
/// old `isWideCanvas` + `isEditMode` pair allowed — a data sheet over full
/// screen, edit mode without full screen, chrome over a full-screen canvas —
/// must be unrepresentable, not merely unreachable.
final class CanvasPresentationStateTests: XCTestCase {

    // MARK: - The transition table from the spec

    func testShowDataFromCanvas() {
        XCTAssertEqual(CanvasPresentationState.canvas.applying(.showData), .data)
    }

    func testHideDataReturnsToCanvas() {
        XCTAssertEqual(CanvasPresentationState.data.applying(.hideData), .canvas)
    }

    func testEnterFullScreenFromCanvasAndFromData() {
        XCTAssertEqual(CanvasPresentationState.canvas.applying(.enterFullScreen), .fullScreen)
        XCTAssertEqual(CanvasPresentationState.data.applying(.enterFullScreen), .fullScreen)
    }

    func testExitFullScreenReturnsToCanvas() {
        XCTAssertEqual(CanvasPresentationState.fullScreen.applying(.exitFullScreen), .canvas)
    }

    func testEditIsReachableOnlyFromFullScreen() {
        XCTAssertEqual(CanvasPresentationState.fullScreen.applying(.beginEditing), .editing)
        XCTAssertEqual(CanvasPresentationState.canvas.applying(.beginEditing), .canvas)
        XCTAssertEqual(CanvasPresentationState.data.applying(.beginEditing), .data)
    }

    /// Done returns to viewing, not to the collapsed canvas.
    func testDoneReturnsToFullScreen() {
        XCTAssertEqual(CanvasPresentationState.editing.applying(.endEditing), .fullScreen)
    }

    func testOpeningThePaletteDismissesDataAndKeepsCanvas() {
        XCTAssertEqual(CanvasPresentationState.data.applying(.openHappeningPalette), .canvas)
        XCTAssertEqual(CanvasPresentationState.canvas.applying(.openHappeningPalette), .canvas)
    }

    /// The palette cannot present over a wide canvas, so the event is inert there.
    func testOpeningThePaletteDoesNotCollapseFullScreen() {
        XCTAssertEqual(CanvasPresentationState.fullScreen.applying(.openHappeningPalette), .fullScreen)
        XCTAssertEqual(CanvasPresentationState.editing.applying(.openHappeningPalette), .editing)
    }

    func testLeavingTheCanvasTabAlwaysCollapsesToCanvas() {
        for state in CanvasPresentationState.allCases {
            XCTAssertEqual(state.applying(.leftCanvasTab), .canvas, "\(state)")
        }
    }

    func testDayBoundaryAlwaysResetsToCanvas() {
        for state in CanvasPresentationState.allCases {
            XCTAssertEqual(state.applying(.dayBoundary), .canvas, "\(state)")
        }
    }

    /// An event that does not apply leaves the state alone rather than
    /// dropping the user somewhere unexpected.
    func testInapplicableEventsAreInert() {
        XCTAssertEqual(CanvasPresentationState.canvas.applying(.hideData), .canvas)
        XCTAssertEqual(CanvasPresentationState.canvas.applying(.exitFullScreen), .canvas)
        XCTAssertEqual(CanvasPresentationState.fullScreen.applying(.showData), .fullScreen)
        XCTAssertEqual(CanvasPresentationState.editing.applying(.showData), .editing)
        XCTAssertEqual(CanvasPresentationState.fullScreen.applying(.endEditing), .fullScreen)
    }

    // MARK: - Forbidden combinations

    func testDataPanelNeverCoexistsWithAWideCanvas() {
        for state in CanvasPresentationState.allCases {
            XCTAssertFalse(state.showsDataPanel && state.isWideCanvas, "\(state)")
        }
    }

    func testEditingAlwaysImpliesAWideCanvas() {
        for state in CanvasPresentationState.allCases where state.isEditing {
            XCTAssertTrue(state.isWideCanvas, "\(state)")
        }
    }

    func testChromeIsHiddenWheneverTheCanvasIsWide() {
        for state in CanvasPresentationState.allCases where state.isWideCanvas {
            XCTAssertFalse(state.showsStatusPill, "\(state)")
            XCTAssertFalse(state.showsBottomActionRow, "\(state)")
        }
    }

    /// Raising the canvas must never START an edit by itself.
    func testEnteringFullScreenNeverStartsEditing() {
        for state in CanvasPresentationState.allCases where state != .editing {
            XCTAssertFalse(state.applying(.enterFullScreen).isEditing, "\(state)")
        }
    }

    /// It is not a way out of an edit either: from `.editing` the canvas is
    /// already full screen, so the event has nothing left to do. Ending an edit
    /// is `.endEditing`'s job, and abandoning one is `.leftCanvasTab`'s.
    func testEnteringFullScreenIsInertWhileEditing() {
        XCTAssertEqual(CanvasPresentationState.editing.applying(.enterFullScreen), .editing)
    }

    func testExactlyOneDockIsVisiblePerState() {
        for state in CanvasPresentationState.allCases {
            let docks = [state.showsFullScreenDock, state.showsEditingChrome, state.showsBottomActionRow]
            XCTAssertEqual(docks.filter { $0 }.count, 1, "\(state)")
        }
    }

    // MARK: - Analytics

    func testAnalyticsNamesCoverTheTrackedTransitions() {
        XCTAssertEqual(CanvasPresentationState.analyticsEventName(from: .canvas, to: .data), "canvas_data_opened")
        XCTAssertEqual(CanvasPresentationState.analyticsEventName(from: .data, to: .canvas), "canvas_data_closed")
        XCTAssertEqual(CanvasPresentationState.analyticsEventName(from: .canvas, to: .fullScreen), "canvas_fullscreen_entered")
        XCTAssertEqual(CanvasPresentationState.analyticsEventName(from: .fullScreen, to: .canvas), "canvas_fullscreen_exited")
        XCTAssertEqual(CanvasPresentationState.analyticsEventName(from: .fullScreen, to: .editing), "canvas_edit_entered")
        XCTAssertEqual(CanvasPresentationState.analyticsEventName(from: .editing, to: .fullScreen), "canvas_edit_exited")
    }

    func testAnalyticsNameIsNilWhenNothingChanged() {
        for state in CanvasPresentationState.allCases {
            XCTAssertNil(CanvasPresentationState.analyticsEventName(from: state, to: state), "\(state)")
        }
    }
}
```

- [ ] **Step 2: Add both files to the Xcode project**

App file — anchor on `CanvasStateManagers.swift` (its `PBXGroup` is `30CA000B300000000000CA0B /* Gallery */`):
- `		CA51B0020000000000000002 /* CanvasPresentationState.swift in Sources */ = {isa = PBXBuildFile; fileRef = CA51F0020000000000000002 /* CanvasPresentationState.swift */; };`
- `		CA51F0020000000000000002 /* CanvasPresentationState.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = CanvasPresentationState.swift; sourceTree = "<group>"; };`
- `				CA51F0020000000000000002 /* CanvasPresentationState.swift */,` in the `Gallery` group children
- `				CA51B0020000000000000002 /* CanvasPresentationState.swift in Sources */,` next to `30CA0007300000000000CA07 /* CanvasStateManagers.swift in Sources */`

Test file — anchor on `MainTabSelectionTests.swift` as in Task 1, using IDs `CA51B0120000000000000012` / `CA51F0120000000000000012`.

- [ ] **Step 3: Run the test to verify it fails**

Run:

```bash
xcodebuild test -project Steps4.xcodeproj -scheme Steps4 -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17,OS=latest' -only-testing:Steps4Tests/CanvasPresentationStateTests CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO
```

Expected: compile failure — `cannot find 'CanvasPresentationState' in scope`.

- [ ] **Step 4: Write the implementation**

Create `StepsTrader/Views/Gallery/CanvasPresentationState.swift`:

```swift
import Foundation

/// The Canvas screen's four mutually exclusive presentation states.
///
/// This replaces the old `isWideCanvas` + `editState.isEditMode` pair, whose
/// product allowed states the design forbids: a data sheet over a full-screen
/// canvas, edit mode without full screen, chrome floating over an expanded
/// canvas. Here those are simply not spellable.
enum CanvasPresentationState: String, CaseIterable, Equatable {
    /// Canvas with the status pill and the three-control bottom row.
    case canvas
    /// Canvas with the data bottom sheet over it. Pill and row stay put.
    case data
    /// Chrome-free canvas with a viewing dock. Never an editing state.
    case fullScreen
    /// Chrome-free canvas with Done + Remix and draggable elements.
    case editing
}

/// Everything that can move the Canvas screen between states.
enum CanvasPresentationEvent: Equatable {
    case showData
    case hideData
    case enterFullScreen
    case exitFullScreen
    case beginEditing
    case endEditing
    /// The happening palette is opening; the canvas must be visible behind it.
    case openHappeningPalette
    /// The user switched to Feeds or Me.
    case leftCanvasTab
    /// The custom day rolled over while a state was open.
    case dayBoundary
}

extension CanvasPresentationState {

    // MARK: - Derived chrome

    /// Matches the legacy `isWideCanvas` binding `MainTabView` reads to hide
    /// the tab bar and the top pill.
    var isWideCanvas: Bool { self == .fullScreen || self == .editing }

    var isEditing: Bool { self == .editing }

    var showsStatusPill: Bool { self == .canvas || self == .data }

    var showsBottomActionRow: Bool { self == .canvas || self == .data }

    var showsDataPanel: Bool { self == .data }

    var showsFullScreenDock: Bool { self == .fullScreen }

    var showsEditingChrome: Bool { self == .editing }

    // MARK: - Transitions

    /// The full transition table. Anything not listed leaves the state alone:
    /// a stray event should be inert, never a surprise navigation.
    func applying(_ event: CanvasPresentationEvent) -> CanvasPresentationState {
        switch event {
        case .leftCanvasTab, .dayBoundary:
            // Both collapse everything: the tab bar is hidden while wide, and a
            // new day must not inherit the previous day's presentation.
            return .canvas

        case .showData:
            return self == .canvas ? .data : self

        case .hideData:
            return self == .data ? .canvas : self

        case .enterFullScreen:
            return (self == .canvas || self == .data) ? .fullScreen : self

        case .exitFullScreen:
            return isWideCanvas ? .canvas : self

        case .beginEditing:
            return self == .fullScreen ? .editing : self

        case .endEditing:
            return self == .editing ? .fullScreen : self

        case .openHappeningPalette:
            // The palette never presents over a wide canvas, so it cannot
            // collapse one either.
            return isWideCanvas ? self : .canvas
        }
    }

    // MARK: - Analytics

    /// Event name for a completed transition, or `nil` when nothing moved.
    /// Names only — never energy values, HealthKit values, happening labels or
    /// element IDs.
    static func analyticsEventName(
        from old: CanvasPresentationState,
        to new: CanvasPresentationState
    ) -> String? {
        guard old != new else { return nil }
        switch (old, new) {
        case (.canvas, .data):           return "canvas_data_opened"
        case (.data, .canvas):           return "canvas_data_closed"
        case (_, .fullScreen) where !old.isWideCanvas: return "canvas_fullscreen_entered"
        case (.fullScreen, .editing):    return "canvas_edit_entered"
        case (.editing, .fullScreen):    return "canvas_edit_exited"
        case (_, _) where old.isWideCanvas && !new.isWideCanvas:
            return "canvas_fullscreen_exited"
        default:                         return nil
        }
    }
}
```

- [ ] **Step 5: Run the test to verify it passes**

Run the same command as Step 3. Expected: 17 tests pass, 0 failures.

- [ ] **Step 6: Commit**

```bash
git add StepsTrader/Views/Gallery/CanvasPresentationState.swift Steps4Tests/CanvasPresentationStateTests.swift Steps4.xcodeproj/project.pbxproj && git commit -m "feat: add canvas presentation state machine"
```

---

## Task 3: Batch remix

**Files:**
- Create: `StepsTrader/Models/CanvasRemix.swift`
- Modify: `StepsTrader/Models/CanvasElement.swift:242-287` (the `reroll` method)
- Test: `Steps4Tests/CanvasRemixTests.swift`
- Modify: `Steps4.xcodeproj/project.pbxproj`

**Interfaces:**
- Consumes: `CanvasElement`, `DayComposition.forDay(dayKey:happeningCount:)`, `CanvasShapeType.allowedByUser`.
- Produces:
  - `mutating func CanvasElement.reroll(rank: Int, composition: DayComposition, allowedShapes: [CanvasShapeType] = CanvasShapeType.allowedByUser, at date: Date = .now)`
  - `enum CanvasRemix` with `static func remixed(_ elements: [CanvasElement], composition: DayComposition, allowedShapes: [CanvasShapeType] = CanvasShapeType.allowedByUser, at date: Date = .now) -> [CanvasElement]`

- [ ] **Step 1: Write the failing test**

Create `Steps4Tests/CanvasRemixTests.swift`:

```swift
import XCTest
@testable import Steps4

/// Remix restyles the whole canvas at once. What it may never do is move an
/// element the user placed, rename it, drop it, or invent a new one — the
/// picture changes, the day it records does not.
final class CanvasRemixTests: XCTestCase {

    private let dayKey = "2026-08-18"

    private var composition: DayComposition {
        DayComposition.forDay(dayKey: dayKey, happeningCount: 4)
    }

    private func makeElements(count: Int = 4) -> [CanvasElement] {
        var elements: [CanvasElement] = []
        for index in 0..<count {
            var element = CanvasElement.spawn(
                optionId: "happening_\(index)",
                label: "Happening \(index)",
                existingElements: elements,
                dayKey: dayKey,
                composition: composition
            )
            // A position the user "dragged" to, so preservation is observable.
            element.basePosition = CGPoint(x: 0.11 + 0.2 * Double(index), y: 0.9)
            elements.append(element)
        }
        return elements
    }

    func testPreservesIdentityOrderAndCount() {
        let before = makeElements()
        let after = CanvasRemix.remixed(before, composition: composition)

        XCTAssertEqual(after.count, before.count)
        XCTAssertEqual(after.map(\.id), before.map(\.id))
        XCTAssertEqual(after.map(\.optionId), before.map(\.optionId))
        XCTAssertEqual(after.map(\.label), before.map(\.label))
        XCTAssertEqual(after.map(\.createdAt), before.map(\.createdAt))
    }

    /// The one thing a user manually arranges. Remix must not touch it.
    func testPreservesManuallyArrangedPositions() {
        let before = makeElements()
        let after = CanvasRemix.remixed(before, composition: composition)

        for (old, new) in zip(before, after) {
            XCTAssertEqual(new.basePosition.x, old.basePosition.x, accuracy: 0.0001)
            XCTAssertEqual(new.basePosition.y, old.basePosition.y, accuracy: 0.0001)
        }
    }

    func testChangesTheVisualSeedOfEveryElement() {
        let before = makeElements()
        let after = CanvasRemix.remixed(before, composition: composition)

        for (old, new) in zip(before, after) {
            XCTAssertNotEqual(new.shapeSeed, old.shapeSeed)
        }
    }

    func testDrawsShapesOnlyFromTheAllowedSet() {
        let allowed: [CanvasShapeType] = [.snowflake]
        let after = CanvasRemix.remixed(
            makeElements(count: 6),
            composition: composition,
            allowedShapes: allowed
        )

        for element in after {
            XCTAssertEqual(element.frozenShapeType, .snowflake)
        }
    }

    func testDrawsColorsOnlyFromTheDayPalette() {
        let palette = Set(composition.palette)
        let after = CanvasRemix.remixed(makeElements(count: 6), composition: composition)

        for element in after {
            XCTAssertTrue(palette.contains(element.hexColor), element.hexColor)
            if let second = element.hexColor2 {
                XCTAssertTrue(palette.contains(second), second)
            }
        }
    }

    /// One batch, one timestamp — the whole canvas changed at the same moment,
    /// and last-write-wins merging needs that to be true.
    func testStampsEveryElementWithTheSameEditDate() {
        let date = Date(timeIntervalSince1970: 1_800_000_000)
        let after = CanvasRemix.remixed(makeElements(), composition: composition, at: date)

        for element in after {
            XCTAssertEqual(element.lastEditedAt, date)
        }
    }

    /// A pinch-resized element must follow the new shape's size curve, not keep
    /// a size chosen for the shape it no longer has.
    func testClearsTheUserSizeOverride() {
        var before = makeElements()
        before[0].userSize = 0.6
        let after = CanvasRemix.remixed(before, composition: composition)

        XCTAssertNil(after[0].userSize)
    }

    func testEmptyCanvasRemixesToAnEmptyCanvas() {
        XCTAssertTrue(CanvasRemix.remixed([], composition: composition).isEmpty)
    }
}
```

- [ ] **Step 2: Add both files to the Xcode project**

App file — anchor on `CanvasElement.swift` exactly as in Task 1, using IDs `CA51B0030000000000000003` / `CA51F0030000000000000003` and path `CanvasRemix.swift`.

Test file — anchor on `MainTabSelectionTests.swift`, using IDs `CA51B0130000000000000013` / `CA51F0130000000000000013`.

- [ ] **Step 3: Run the test to verify it fails**

Run:

```bash
xcodebuild test -project Steps4.xcodeproj -scheme Steps4 -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17,OS=latest' -only-testing:Steps4Tests/CanvasRemixTests CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO
```

Expected: compile failure — `cannot find 'CanvasRemix' in scope`.

- [ ] **Step 4: Make `reroll` injectable**

In `StepsTrader/Models/CanvasElement.swift`, change the signature and the two lines that read globals. Replace:

```swift
    mutating func reroll(rank: Int, composition: DayComposition) {
        shapeSeed = UInt64.random(in: UInt64.min...UInt64.max)

        // Freeze one currently allowed shape so historical renders stay stable.
        let resolvedShape = CanvasShapeType.allowedByUser.randomElement() ?? .circle
        frozenShapeType = resolvedShape
```

with:

```swift
    /// - Parameters:
    ///   - allowedShapes: injected so a batch Remix and the tests can pin the
    ///     set instead of reading `UserDefaults` once per element.
    ///   - date: injected so one Remix stamps every element with one instant.
    mutating func reroll(
        rank: Int,
        composition: DayComposition,
        allowedShapes: [CanvasShapeType] = CanvasShapeType.allowedByUser,
        at date: Date = .now
    ) {
        shapeSeed = UInt64.random(in: UInt64.min...UInt64.max)

        // Freeze one currently allowed shape so historical renders stay stable.
        let resolvedShape = allowedShapes.randomElement() ?? .circle
        frozenShapeType = resolvedShape
```

And at the end of the same method replace `lastEditedAt = .now` with `lastEditedAt = date`.

Leave the existing call site in `GalleryView.rerollElement(id:)` untouched — the new parameters default to the previous behaviour.

- [ ] **Step 5: Write the implementation**

Create `StepsTrader/Models/CanvasRemix.swift`:

```swift
import Foundation

/// Restyles every decorative element on a canvas in one pass.
///
/// Remix is a request for a different-looking day, not a different day. Shape,
/// silhouette seed, colours, size and motion personality are re-rolled inside
/// the day's own composition; identity, arrangement and count are carried
/// through untouched, so the canvas still records the same happenings in the
/// same places.
enum CanvasRemix {

    /// - Parameters:
    ///   - elements: the canvas in arrival order. Order is preserved because
    ///     rank drives size, colour and texture.
    ///   - composition: the day's composition, so a remix cannot leave the
    ///     day's palette or archetype.
    ///   - allowedShapes: the user's allowed shape set.
    ///   - date: one instant stamped on the whole batch, so last-write-wins
    ///     merging treats the remix as a single edit.
    static func remixed(
        _ elements: [CanvasElement],
        composition: DayComposition,
        allowedShapes: [CanvasShapeType] = CanvasShapeType.allowedByUser,
        at date: Date = .now
    ) -> [CanvasElement] {
        elements.enumerated().map { rank, element in
            var copy = element
            copy.reroll(
                rank: rank,
                composition: composition,
                allowedShapes: allowedShapes,
                at: date
            )
            return copy
        }
    }
}
```

- [ ] **Step 6: Run the tests to verify they pass**

Run:

```bash
xcodebuild test -project Steps4.xcodeproj -scheme Steps4 -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17,OS=latest' -only-testing:Steps4Tests/CanvasRemixTests -only-testing:Steps4Tests/CanvasElementSpawnFigureTests CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO
```

Expected: all pass, 0 failures. The spawn-figure suite is included to prove the `reroll` signature change did not disturb spawning.

- [ ] **Step 7: Commit**

```bash
git add StepsTrader/Models/CanvasRemix.swift StepsTrader/Models/CanvasElement.swift Steps4Tests/CanvasRemixTests.swift Steps4.xcodeproj/project.pbxproj && git commit -m "feat: add batch canvas remix"
```

---

## Task 4: Compact energy pill replaces the balance card

**Files:**
- Create: `StepsTrader/Views/Gallery/CanvasEnergyStatusPill.swift`
- Modify: `StepsTrader/Views/MainTabView.swift:36-46, 265-316, 383-425`
- Delete: `StepsTrader/Views/Components/StepBalanceCard.swift`
- Modify: `Steps4.xcodeproj/project.pbxproj`

**Interfaces:**
- Consumes: `CanvasEnergyStatus` (Task 1).
- Produces: `struct CanvasEnergyStatusPill: View` with a single `let status: CanvasEnergyStatus` property.

**Note:** after this task the coach-mark steps `.expandChevron` and `.categoriesRevealed` have no anchor until Tasks 7 and 8. `CoachMarkOverlay` renders those steps without a spotlight cutout rather than crashing, so the intermediate commits build and run. Verify the full tour only at Task 11.

- [ ] **Step 1: Write the component**

Create `StepsTrader/Views/Gallery/CanvasEnergyStatusPill.swift`:

```swift
import SwiftUI

/// Compact daily-energy readout pinned under the Dynamic Island on Canvas.
///
/// It shows `remaining / earnedToday` and a bar whose track *is* today's
/// earnings — not the product's 100 ceiling. There is deliberately no `100`,
/// no `Energy` caption, no reset timer, no expand chevron and no metric chips:
/// what used to be a card is now one line the user reads without stopping.
struct CanvasEnergyStatusPill: View {
    let status: CanvasEnergyStatus

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let minWidth: CGFloat = 148
    private static let maxWidth: CGFloat = 176
    private static let minHeight: CGFloat = 58
    private static let progressHeight: CGFloat = 6

    private var textPrimary: Color { AppColors.Night.textPrimary }

    var body: some View {
        VStack(spacing: 7) {
            numbers
            progressBar
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .frame(minWidth: Self.minWidth, maxWidth: Self.maxWidth, minHeight: Self.minHeight)
        .glassCard(cornerRadius: 16, style: .lens)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            String(localized: "Daily energy", comment: "Canvas status pill – VoiceOver label")
        )
        .accessibilityValue(
            String(
                localized: "\(status.remaining) remaining out of \(status.earned) earned today",
                comment: "Canvas status pill – VoiceOver value"
            )
        )
        .accessibilityIdentifier("canvas_energy_pill")
    }

    private var numbers: some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text("\(status.remaining)")
                .font(.system(size: 20, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(AppColors.brandAccent)

            // Not localizable copy — a separator between two numbers.
            Text(verbatim: "/")
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(textPrimary.opacity(0.65))

            Text("\(status.earned)")
                .font(.system(size: 17, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(textPrimary)
        }
        .lineLimit(1)
        .minimumScaleFactor(0.8)
        .contrastingOnGlass()
    }

    private var progressBar: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            ZStack(alignment: .leading) {
                Capsule(style: .continuous)
                    .fill(textPrimary.opacity(0.20))
                Capsule(style: .continuous)
                    .fill(AppColors.brandAccent)
                    .frame(width: max(0, width * status.progress))
            }
        }
        .frame(height: Self.progressHeight)
        // Ease only, never a spring: an overshooting bar reads as a value that
        // briefly went past what the user actually has.
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.3), value: status)
        // The numbers above already say this; VoiceOver should not repeat it.
        .accessibilityHidden(true)
    }
}

#Preview {
    VStack(spacing: 16) {
        CanvasEnergyStatusPill(status: CanvasEnergyStatus(stepsBalance: 58, baseEnergyToday: 72))
        CanvasEnergyStatusPill(status: CanvasEnergyStatus(stepsBalance: 0, baseEnergyToday: 0))
        CanvasEnergyStatusPill(status: CanvasEnergyStatus(stepsBalance: 0, baseEnergyToday: 40))
    }
    .padding()
    .background(Color.black)
}
```

- [ ] **Step 2: Swap the card for the pill in `MainTabView`**

In `StepsTrader/Views/MainTabView.swift`, replace the whole `StepBalanceCard(...)` block inside `.overlay(alignment: .top)` (currently lines 265–311) with:

```swift
        .overlay(alignment: .top) {
            // Me is where you look back, not where you check your balance — the
            // pill is drawn on canvas and feeds only.
            if !isWideCanvas, !hidesSurroundingChromeForPalette, selection != Tab.me.rawValue {
                CanvasEnergyStatusPill(
                    status: CanvasEnergyStatus(
                        stepsBalance: model.userEconomyStore.stepsBalance,
                        baseEnergyToday: model.healthStore.baseEnergyToday
                    )
                )
                .padding(.top, 8)
                .padding(.bottom, 8)
                .background(
                    GeometryReader { geo in
                        Color.clear
                            .preference(key: TopCardHeightPreferenceKey.self, value: geo.size.height)
                    }
                )
                .coachMarkAnchor(.colorBalance)
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
```

Note the removed `.padding(.horizontal)`: the pill is content-sized and stays horizontally centred by the overlay alignment, so no animation can shift it sideways.

- [ ] **Step 3: Remove what the card carried**

Still in `MainTabView.swift`:

1. Delete `@State private var showColorsHelp: Bool = false` (line 38).
2. Delete the `.overlay { if showColorsHelp { colorsHelpOverlay } }` block (lines 312–316).
3. Delete the `private var colorsHelpOverlay: some View { ... }` computed property (lines 390–425).
4. Delete `private func openHappeningPaletteOnCanvas()` (lines 383–388). Its only caller was the card's `onMoveTap`.

Leave `paletteRoute`, `metricOverlay`, `TopCardHeightPreferenceKey` and the `\.topCardHeight` environment key exactly as they are — Tasks 5–8 still use them.

- [ ] **Step 4: Delete `StepBalanceCard`**

```bash
git rm StepsTrader/Views/Components/StepBalanceCard.swift
```

Then remove its four `project.pbxproj` entries:
- `		20F5A0102FFF020000000001 /* StepBalanceCard.swift in Sources */ = {isa = PBXBuildFile; ... };`
- `		20F5A00F2FFF020000000000 /* StepBalanceCard.swift */ = {isa = PBXFileReference; ... };`
- `				20F5A00F2FFF020000000000 /* StepBalanceCard.swift */,` from the `Components` group children
- `				20F5A0102FFF020000000001 /* StepBalanceCard.swift in Sources */,` from the Sources build phase

And add the new pill with IDs `CA51B0040000000000000004` / `CA51F0040000000000000004`, anchored on `CanvasStateManagers.swift` (the `Gallery` group, `30CA000B300000000000CA0B`) exactly as in Task 2.

- [ ] **Step 5: Build and verify nothing else referenced the card**

Run:

```bash
grep -rn "StepBalanceCard\|colorsHelpOverlay\|openHappeningPaletteOnCanvas" StepsTrader Steps4Tests Steps4UITests
```

Expected: no matches. Then run:

```bash
xcodebuild build -project Steps4.xcodeproj -scheme Steps4 -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17,OS=latest' CODE_SIGNING_ALLOWED=NO
```

Expected: BUILD SUCCEEDED.

- [ ] **Step 6: Run the unit suite**

Run:

```bash
xcodebuild test -project Steps4.xcodeproj -scheme Steps4 -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17,OS=latest' -only-testing:Steps4Tests CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO
```

Expected: 0 failures **except one**: `CoachMarkTourTests.testActionDrivenStepsAreAnchoredAndReportedInTheSources` fails from here until Task 7.

That test greps the app sources for `coachMarkAnchor(.expandChevron)` and a matching `postAction(for: .expandChevron)`. Both lived in the deleted `StepBalanceCard.swift`, and their new home — the Show data control — does not exist until Task 7. This is an interim regression the plan creates knowingly. Do not re-anchor `.expandChevron` early, and do not edit the test: Task 7 restores both call sites and Task 7's Step 3 verifies the test is green again. Any OTHER failure is a real one.

- [ ] **Step 7: Commit**

```bash
git add StepsTrader/Views/Gallery/CanvasEnergyStatusPill.swift StepsTrader/Views/MainTabView.swift StepsTrader/Views/Components/StepBalanceCard.swift Steps4.xcodeproj/project.pbxproj && git commit -m "feat: replace balance card with compact energy pill"
```

---

## Task 5: Drive Canvas chrome from the state machine

Pure refactor: no visual change. It replaces the `isWideCanvas` + `editState.isEditMode` pair inside `GalleryView` with one `CanvasPresentationState`, so Tasks 6–9 have one place to change.

**Files:**
- Modify: `StepsTrader/Views/GalleryView.swift`

**Interfaces:**
- Consumes: `CanvasPresentationState`, `CanvasPresentationEvent` (Task 2).
- Produces: a private `@State var presentation: CanvasPresentationState` in `GalleryView`, plus `private func send(_ event: CanvasPresentationEvent)`. The `@Binding var isWideCanvas: Bool` stays as the outward mirror `MainTabView` reads.

- [ ] **Step 1: Add the state and its funnel**

In `GalleryView`, next to `@State private var editState = CanvasEditState()` (line 60), add:

```swift
    /// The single source of truth for what Canvas is showing. `isWideCanvas`
    /// below is now a mirror the tab host reads, never something written
    /// independently — the two used to drift into states the design forbids.
    @State private var presentation: CanvasPresentationState = .canvas
```

And add this method next to `openHappeningPalette()`:

```swift
    /// Every presentation change goes through here, so the mirrored binding and
    /// the edit-mode flag can never disagree with the state.
    private func send(_ event: CanvasPresentationEvent) {
        // `userCollapsedWide` is decided here rather than in the observer below,
        // because only the event knows WHY the canvas stopped being wide. The
        // observer sees just the old and new state, and a day rollover collapsing
        // the canvas looks identical there to the user collapsing it by hand —
        // which would wrongly stop the iPad naturally-wide branch from ever
        // re-expanding. Set ahead of the no-op guard so a rollover clears the flag
        // whether or not it also changes the state, exactly as the pre-refactor
        // rollover sites did.
        switch event {
        case .exitFullScreen where presentation.isWideCanvas: userCollapsedWide = true
        case .dayBoundary:                                    userCollapsedWide = false
        default:                                              break
        }
        let next = presentation.applying(event)
        guard next != presentation else { return }
        withAnimation(.easeInOut(duration: next.isWideCanvas || presentation.isWideCanvas ? 0.35 : 0.3)) {
            presentation = next
        }
    }
```

- [ ] **Step 2: Mirror the state onto the legacy flags**

Add these observers to the `observingCanvas` chain (next to the existing `.onChange(of: isWideCanvas)` handlers around line 509):

```swift
        .onChange(of: presentation, initial: true) { old, new in
            if isWideCanvas != new.isWideCanvas { isWideCanvas = new.isWideCanvas }
            editState.isEditMode = new.isEditing

            if !new.isEditing {
                // Leaving editing commits whatever the finger was doing — on
                // EVERY exit, not just Done. Before this plan the collapse button
                // called `editState.reset()` and silently threw the in-flight
                // drag away; spec §7.3 wants the position kept (it already says
                // so for Done and for the app resigning active), and there is no
                // reason a different exit should lose the user's arrangement.
                if editState.isDraggingElement { handleEditDragEnd() }
                editState.editFreezeTime = nil
                editState.activeElementId = nil
            } else if editState.editFreezeTime == nil {
                editState.editFreezeTime = Date.now
            }

            if !new.isWideCanvas {
                isManuallyExpanded = false
            } else {
                userCollapsedWide = false
                isManuallyExpanded = true
            }

            refreshAddHint()
            consumePaletteOpenRequestIfReady()
        }
```

Then delete the three now-superseded observers: `.onChange(of: isWideCanvas) { refreshAddHint() }`, `.onChange(of: isWideCanvas) { consumePaletteOpenRequestIfReady() }` (lines 509–512), and the `.onChange(of: isWideCanvas) { _, wide in ... }` block that resets `editState` (lines 579–586).

- [ ] **Step 3: Replace every read of the legacy flags**

Mechanical substitution inside `GalleryView` — replace `isWideCanvas` with `presentation.isWideCanvas` and `editState.isEditMode` with `presentation.isEditing` at these sites:

- `bottomControlsPadding` (line 111)
- `happeningPaletteOverlay` guard (line 196)
- `consumePaletteOpenRequestIfReady` → `canPresent: !presentation.isWideCanvas` (line 188)
- `refreshAddHint` guards (lines 256, 283)
- `canvasLayers`: `showLabelsOnCanvas:` (line 344), the `if !editState.isEditMode` overlay guard (line 357), and both `if editState.isEditMode` blocks (lines 377, 385)
- `body` overlays: the controls guard (line 407), the wide overlay guard (line 417), the metric-overlay guard (line 422)
- `canvasControls`: lines 607, 614, 625

Replace the two animation values at the end of `body` (lines 577–578) with one:

```swift
        .animation(.easeInOut(duration: 0.35), value: presentation)
```

- [ ] **Step 4: Route every existing action through `send`**

- `openHappeningPalette()`: insert `send(.openHappeningPalette)` before `refreshHappeningPalette()`.
- `expandCanvasButton` action body (lines 750–756) becomes:

```swift
        Button {
            send(.enterFullScreen)
            lightHapticTick &+= 1
        } label: {
```

- The collapse button in `wideCanvasOverlayContent` (lines 1255–1262) becomes:

```swift
            Button {
                send(.exitFullScreen)
                lightHapticTick &+= 1
            } label: {
```

- The edit toggle in `wideCanvasOverlayContent` (lines 1277–1289) becomes:

```swift
            Button {
                if presentation.isEditing {
                    saveCanvasLocally()
                    send(.endEditing)
                } else {
                    send(.beginEditing)
                }
                lightHapticTick &+= 1
            } label: {
                Image(systemName: presentation.isEditing ? "checkmark" : "hand.draw")
```

- The iPad naturally-wide branch (lines 446–448) becomes:

```swift
                            if wide && !userCollapsedWide && !isManuallyExpanded {
                                // Naturally wide is a viewing state. It must
                                // never walk the user into editing.
                                send(.enterFullScreen)
                            }
```

- `.onChange(of: isCanvasSelected)` (line 487): after the existing palette handling, add `if !selected { send(.leftCanvasTab) }`.
- Both day-rollover paths — `.onChange(of: todayKey)` (line 497) and the `scenePhase == .active` branch (line 524) — add `send(.dayBoundary)` alongside the existing resets, and drop the now-redundant `userCollapsedWide = false` / `isManuallyExpanded = false` lines there (the `presentation` observer handles them).

- [ ] **Step 5: Build and run the full unit suite**

Run:

```bash
xcodebuild build -project Steps4.xcodeproj -scheme Steps4 -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17,OS=latest' CODE_SIGNING_ALLOWED=NO && xcodebuild test -project Steps4.xcodeproj -scheme Steps4 -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17,OS=latest' -only-testing:Steps4Tests CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO
```

Expected: BUILD SUCCEEDED. Test failures: 0 **except** `CoachMarkTourTests.testActionDrivenStepsAreAnchoredAndReportedInTheSources`, which stays red from Task 4 until Task 7 re-anchors `.expandChevron` on the Show data control. Any other failure is a real one.

- [ ] **Step 6: Verify no legacy writes remain**

Run:

```bash
grep -n "isWideCanvas = \|editState.isEditMode = \|editState.isEditMode.toggle" StepsTrader/Views/GalleryView.swift
```

Expected: exactly two matches, both inside the `.onChange(of: presentation)` observer.

- [ ] **Step 7: Commit**

```bash
git add StepsTrader/Views/GalleryView.swift && git commit -m "refactor: drive canvas chrome from presentation state"
```

---

## Task 6: Full screen dock

**Files:**
- Create: `StepsTrader/Views/Gallery/CanvasFullScreenDock.swift`
- Modify: `StepsTrader/Views/GalleryView.swift` (`wideCanvasOverlay`, `wideCanvasOverlayContent`, `shareButton`)
- Modify: `Steps4.xcodeproj/project.pbxproj`

**Interfaces:**
- Consumes: `CanvasPresentationState` (Task 2).
- Produces: `struct CanvasFullScreenDock<Share: View>: View` with `let onExit: () -> Void`, `let onEdit: () -> Void`, `@ViewBuilder let share: () -> Share`.

- [ ] **Step 1: Write the dock**

Create `StepsTrader/Views/Gallery/CanvasFullScreenDock.swift`:

```swift
import SwiftUI

/// The dock shown while the canvas is raised for viewing.
///
/// Full screen is a viewing state, so its two navigation actions carry visible
/// labels rather than icons a user has to decode — "Edit" must never be
/// something you press by accident on the way out. Share is passed in from the
/// host because its context menu needs routines the dock knows nothing about.
struct CanvasFullScreenDock<Share: View>: View {
    let onExit: () -> Void
    let onEdit: () -> Void
    @ViewBuilder let share: () -> Share

    private var ink: Color { AppColors.Night.textPrimary }

    var body: some View {
        Group {
            if #available(iOS 26.0, *) {
                GlassEffectContainer(spacing: 0) { content }
            } else {
                content
            }
        }
    }

    private var content: some View {
        HStack(spacing: 8) {
            label(
                String(localized: "Exit full screen", comment: "Full screen dock – collapse action"),
                systemImage: "arrow.down.right.and.arrow.up.left",
                action: onExit
            )
            .accessibilityIdentifier("canvas_exit_fullscreen_button")

            share()

            label(
                String(localized: "Edit", comment: "Full screen dock – enter editing"),
                systemImage: "hand.draw",
                action: onEdit
            )
            .accessibilityIdentifier("canvas_edit_button")
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .liquidGlassControl(in: Capsule(style: .continuous))
    }

    private func label(
        _ title: String,
        systemImage: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: systemImage)
                    .font(.system(size: 15, weight: .regular))
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
            .foregroundStyle(ink)
            .padding(.horizontal, 14)
            .frame(minHeight: 56)
            .contentShape(Capsule(style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
    }
}
```

- [ ] **Step 2: Use it in `GalleryView`**

Replace `wideCanvasOverlayContent` (lines 1253–1302) with nothing, and replace `wideCanvasOverlay` (lines 1238–1251) with:

```swift
    private var wideCanvasOverlay: some View {
        VStack {
            Spacer()
            CanvasFullScreenDock(
                onExit: {
                    send(.exitFullScreen)
                    lightHapticTick &+= 1
                },
                onEdit: {
                    send(.beginEditing)
                    lightHapticTick &+= 1
                },
                share: { shareButton }
            )
            .padding(.horizontal, 8)
            .padding(.bottom, max(safeAreaBottom, 34) + 16)
        }
    }
```

Then change the overlay guard in `body` (line 417) so the dock only appears while viewing, not while editing:

```swift
        .overlay {
            if presentation.showsFullScreenDock {
                wideCanvasOverlay
                    .ignoresSafeArea()
            }
        }
```

- [ ] **Step 3: Make the share button fit a labelled dock**

In `shareButton` (lines 775–798), replace the icon-only frame chain with a labelled capsule so it matches its neighbours. Replace:

```swift
            .frame(width: 56, height: 56)
            .liquidGlassControl(in: Circle())
            .frame(width: 72, height: 72)
            .contentShape(Circle())
```

with:

```swift
            .frame(minWidth: 56, minHeight: 56)
            .contentShape(Capsule(style: .continuous))
```

The dock's own glass capsule now supplies the material; a nested `liquidGlassControl` inside it would double the lens.

- [ ] **Step 4: Build and check by eye in the simulator**

Run:

```bash
xcodebuild build -project Steps4.xcodeproj -scheme Steps4 -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17,OS=latest' CODE_SIGNING_ALLOWED=NO
```

Expected: BUILD SUCCEEDED. (If you also run the unit suite here, `CoachMarkTourTests.testActionDrivenStepsAreAnchoredAndReportedInTheSources` is still red — it stays red from Task 4 until Task 7. Any other failure is a real one.) Then launch the app in the simulator, tap the expand control, and confirm: the dock reads `Exit full screen · Share · Edit`, tapping `Exit full screen` returns to Canvas, and tapping `Edit` enters editing (the existing element outlines appear) rather than doing so automatically on entry.

- [ ] **Step 5: Commit**

```bash
git add StepsTrader/Views/Gallery/CanvasFullScreenDock.swift StepsTrader/Views/GalleryView.swift Steps4.xcodeproj/project.pbxproj && git commit -m "feat: add canvas full screen dock"
```

Use IDs `CA51B0050000000000000005` / `CA51F0050000000000000005` for the new file, anchored on `CanvasStateManagers.swift` as in Task 2.

---

## Task 7: Bottom action row

**Files:**
- Create: `StepsTrader/Views/Gallery/CanvasBottomActionRow.swift`
- Modify: `StepsTrader/Views/GalleryView.swift` (`bottomControlsBar`, `bottomControlsContent`, `expandCanvasButton`)
- Modify: `Steps4.xcodeproj/project.pbxproj`

**Interfaces:**
- Consumes: `CanvasPresentationState` (Task 2).
- Produces: `struct CanvasBottomActionRow: View` with `let isDataExpanded: Bool`, `let onFullScreen: () -> Void`, `let onToggleData: () -> Void`, `let onAdd: () -> Void`.

- [ ] **Step 1: Write the row**

Create `StepsTrader/Views/Gallery/CanvasBottomActionRow.swift`:

```swift
import SwiftUI

/// The three Canvas actions, in a fixed order: raise the canvas, show the data
/// behind it, add something that happened.
///
/// The order is spatial, not linguistic — these are utility controls anchored
/// to corners of the screen — so it is pinned left-to-right even in RTL. Only
/// the text inside "Show data" localises.
struct CanvasBottomActionRow: View {
    let isDataExpanded: Bool
    let onFullScreen: () -> Void
    let onToggleData: () -> Void
    let onAdd: () -> Void

    @Environment(\.colorSchemeContrast) private var colorSchemeContrast

    private var ink: Color { AppColors.Night.textPrimary }

    /// Increase Contrast lifts the outlined circle off a busy canvas.
    private var outlineOpacity: Double {
        colorSchemeContrast == .increased ? 0.65 : 0.35
    }

    var body: some View {
        Group {
            // Without the container, iOS 26 merges sibling interactive glass
            // surfaces and routes every tap to the first one in the hierarchy.
            if #available(iOS 26.0, *) {
                GlassEffectContainer(spacing: 0) { content }
            } else {
                content
            }
        }
        .padding(.horizontal, 24)
    }

    private var content: some View {
        HStack(alignment: .center, spacing: 0) {
            fullScreenControl
            Spacer(minLength: 8)
            showDataControl
            Spacer(minLength: 8)
            addControl
        }
        .environment(\.layoutDirection, .leftToRight)
    }

    // MARK: - Left: full screen

    private var fullScreenControl: some View {
        Button(action: onFullScreen) {
            Image(systemName: "arrow.up.left.and.arrow.down.right")
                .font(.system(size: 20, weight: .regular))
                .foregroundStyle(ink)
                .frame(width: 56, height: 56)
                // Outline, not glass: the canvas is the subject here, and a
                // filled pill in the corner competes with it.
                .overlay(Circle().strokeBorder(ink.opacity(outlineOpacity), lineWidth: 1))
                .frame(width: 72, height: 72)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(
            String(localized: "Expand canvas", comment: "Canvas – full screen button VoiceOver label")
        )
        .accessibilityHint(
            String(localized: "Opens the canvas without editing",
                   comment: "Canvas – full screen button VoiceOver hint")
        )
        .accessibilityIdentifier("canvas_fullscreen_button")
    }

    // MARK: - Center: show / hide data

    private var showDataControl: some View {
        Button(action: onToggleData) {
            HStack(spacing: 4) {
                Text(
                    isDataExpanded
                        ? String(localized: "Hide data", comment: "Canvas – collapse the data panel")
                        : String(localized: "Show data", comment: "Canvas – expand the data panel")
                )
                .lineLimit(1)
                .minimumScaleFactor(0.85)

                Image(systemName: isDataExpanded ? "chevron.down" : "chevron.up")
            }
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(ink)
            .padding(.horizontal, 16)
            .frame(minWidth: 128, minHeight: 56)
            .liquidGlassControl(in: Capsule(style: .continuous), style: .lens)
            .contentShape(Capsule(style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(
            String(localized: "Show canvas data", comment: "Canvas – data panel VoiceOver label")
        )
        .accessibilityValue(
            isDataExpanded
                ? String(localized: "Expanded", comment: "Canvas – data panel VoiceOver value")
                : String(localized: "Collapsed", comment: "Canvas – data panel VoiceOver value")
        )
        .accessibilityIdentifier("canvas_show_data_button")
        .coachMarkAnchor(.expandChevron)
    }

    // MARK: - Right: add

    private var addControl: some View {
        Button(action: onAdd) {
            Image(systemName: "plus")
                .font(.system(size: 22, weight: .regular))
                .foregroundStyle(AppAccentInk.primary)
                .frame(width: 56, height: 56)
                .background(AppColors.brandAccent, in: Circle())
                .frame(width: 72, height: 72)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(String(localized: "Add happening", comment: "Canvas add button"))
        .accessibilityIdentifier("canvas_add_button")
        .coachMarkAnchor(.tapPlusButton)
        // The palette docks on this button's line rather than re-deriving it
        // from tab-bar height and paddings.
        .background(
            GeometryReader { proxy in
                Color.clear.preference(
                    key: CanvasAddButtonCenterKey.self,
                    value: proxy.frame(in: .global).midY
                )
            }
        )
    }
}
```

- [ ] **Step 2: Use it in `GalleryView`**

Delete `bottomControlsContent` (lines 686–743) and `expandCanvasButton` (lines 749–769). Replace `bottomControlsBar` (lines 669–684) with:

```swift
    private var bottomControlsBar: some View {
        CanvasBottomActionRow(
            isDataExpanded: presentation.showsDataPanel,
            onFullScreen: {
                send(.enterFullScreen)
                lightHapticTick &+= 1
            },
            onToggleData: {
                CoachMarkManager.postAction(for: .expandChevron)
                send(presentation.showsDataPanel ? .hideData : .showData)
                lightHapticTick &+= 1
            },
            onAdd: {
                CoachMarkManager.postAction(for: .tapPlusButton)
                openHappeningPalette()
            }
        )
    }
```

`shareButton` keeps its definition — it is now only referenced by `wideCanvasOverlay`.

- [ ] **Step 3: Build and check by eye**

Run:

```bash
xcodebuild build -project Steps4.xcodeproj -scheme Steps4 -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17,OS=latest' CODE_SIGNING_ALLOWED=NO
```

Expected: BUILD SUCCEEDED. In the simulator confirm the row is exactly `outlined circle · Show data · yellow +`, that the `+` still opens the happening palette, and that the palette's dock still lines up with the `+`.

Then close the coach-mark regression this plan opened at Task 4. Run:

```bash
xcodebuild test -project Steps4.xcodeproj -scheme Steps4 -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17,OS=latest' -only-testing:Steps4Tests/CoachMarkTourTests CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO
```

Expected: all pass, including `testActionDrivenStepsAreAnchoredAndReportedInTheSources`. That test greps the app sources for both `coachMarkAnchor(.expandChevron)` and `postAction(for: .expandChevron)`; this task is what restores them — the anchor on the Show data control inside `CanvasBottomActionRow`, and the post inside `bottomControlsBar`'s `onToggleData`. If it is still red, one of the two is missing.

- [ ] **Step 4: Commit**

```bash
git add StepsTrader/Views/Gallery/CanvasBottomActionRow.swift StepsTrader/Views/GalleryView.swift Steps4.xcodeproj/project.pbxproj && git commit -m "feat: add canvas bottom action row"
```

Use IDs `CA51B0060000000000000006` / `CA51F0060000000000000006`.

---

## Task 8: Data panel

**Files:**
- Create: `StepsTrader/Views/Gallery/CanvasDataPanel.swift`
- Test: `Steps4Tests/CanvasDataPanelLayoutTests.swift`
- Modify: `StepsTrader/Views/GalleryView.swift` (`body` overlays)
- Modify: `Steps4.xcodeproj/project.pbxproj`

**Interfaces:**
- Consumes: `MetricOverlayKind`.
- Produces:
  - `struct CanvasDataRow: Identifiable, Equatable` with `let kind: MetricOverlayKind`, `let title: String`, `let systemImage: String`, `let value: Int`, `let maxValue: Int`
  - `struct CanvasDataPanel: View` with `let rows: [CanvasDataRow]`, `let maxHeight: CGFloat`, `let onSelect: (MetricOverlayKind) -> Void`, `let onHide: () -> Void`
  - `static func CanvasDataPanel.maxHeight(viewportHeight: CGFloat, topInset: CGFloat, bottomInset: CGFloat) -> CGFloat`

- [ ] **Step 1: Write the failing layout test**

Create `Steps4Tests/CanvasDataPanelLayoutTests.swift`:

```swift
import XCTest
@testable import Steps4

/// The data sheet is a strip over the canvas, not a takeover: it may claim at
/// most 40% of the space between the status pill and the tab bar, so the
/// picture stays the subject of the screen.
final class CanvasDataPanelLayoutTests: XCTestCase {

    func testClaimsFortyPercentOfTheSpaceBetweenChrome() {
        let height = CanvasDataPanel.maxHeight(
            viewportHeight: 800,
            topInset: 120,
            bottomInset: 130
        )

        // 800 - 120 - 130 = 550 available; 40% of that.
        XCTAssertEqual(height, 220, accuracy: 0.001)
    }

    func testNeverGoesNegativeWhenChromeExceedsTheViewport() {
        let height = CanvasDataPanel.maxHeight(
            viewportHeight: 200,
            topInset: 150,
            bottomInset: 150
        )

        XCTAssertEqual(height, 0, accuracy: 0.001)
    }

    /// A first layout pass reports a zero viewport while the chrome insets are
    /// already known. An unclamped formula would hand back a negative height here.
    func testZeroViewportWithKnownChromeAsksForNothing() {
        XCTAssertEqual(
            CanvasDataPanel.maxHeight(viewportHeight: 0, topInset: 133, bottomInset: 206),
            0,
            accuracy: 0.001
        )
    }
}
```

- [ ] **Step 2: Add both files to the project, then run the test to verify it fails**

App file IDs `CA51B0070000000000000007` / `CA51F0070000000000000007` anchored on `CanvasStateManagers.swift`; test file IDs `CA51B0140000000000000014` / `CA51F0140000000000000014` anchored on `MainTabSelectionTests.swift`.

Run:

```bash
xcodebuild test -project Steps4.xcodeproj -scheme Steps4 -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17,OS=latest' -only-testing:Steps4Tests/CanvasDataPanelLayoutTests CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO
```

Expected: compile failure — `cannot find 'CanvasDataPanel' in scope`.

- [ ] **Step 3: Write the panel**

Create `StepsTrader/Views/Gallery/CanvasDataPanel.swift`:

```swift
import SwiftUI

/// One metric line in the data sheet.
struct CanvasDataRow: Identifiable, Equatable {
    let kind: MetricOverlayKind
    let title: String
    let systemImage: String
    let value: Int
    let maxValue: Int

    var id: String { kind.id }

    var fill: Double {
        guard maxValue > 0 else { return 0 }
        return min(1, Double(value) / Double(maxValue))
    }
}

/// The data behind today's canvas, as a sheet over the canvas rather than a
/// card that pushes it down.
///
/// Steps and Sleep come from HealthKit and are read-only here — the exploratory
/// mockups' small trailing `+` glyphs are not part of the product. Adding
/// something remains the single yellow `+` on Canvas.
struct CanvasDataPanel: View {
    let rows: [CanvasDataRow]
    let maxHeight: CGFloat
    let onSelect: (MetricOverlayKind) -> Void
    let onHide: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var dragOffset: CGFloat = 0

    /// Dismiss thresholds: a deliberate pull, or a flick that clearly meant it.
    private static let dismissDistance: CGFloat = 60
    private static let dismissVelocity: CGFloat = 700

    private var ink: Color { AppColors.Night.textPrimary }

    /// A ceiling for growth, not a promise for today's three rows.
    ///
    /// SwiftUI's `.frame(maxHeight:)` constrains the PROPOSAL, not the render: a
    /// child whose own minimum exceeds it simply draws larger. Three 52 pt rows
    /// plus the header need ~266 pt, which is above 40% of the available space on
    /// every current iPhone, so the panel is content-sized in practice. The cap
    /// starts to bite once the row list grows past three.
    static func maxHeight(
        viewportHeight: CGFloat,
        topInset: CGFloat,
        bottomInset: CGFloat
    ) -> CGFloat {
        max(0, (viewportHeight - topInset - bottomInset)) * 0.4
    }

    var body: some View {
        VStack(spacing: 12) {
            header
            VStack(spacing: 8) {
                ForEach(rows) { row in
                    rowView(row)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 16)
        .frame(maxWidth: .infinity, maxHeight: maxHeight, alignment: .top)
        .glassCard(cornerRadius: 24, style: .lens)
        .offset(y: max(0, dragOffset))
        .gesture(dismissDrag)
        .accessibilityIdentifier("canvas_data_panel")
        .coachMarkAnchor(.categoriesRevealed)
    }

    private var header: some View {
        VStack(spacing: 10) {
            Capsule()
                .fill(ink.opacity(0.45))
                .frame(width: 36, height: 4)
                .accessibilityHidden(true)

            Button(action: onHide) {
                HStack(spacing: 4) {
                    Text(String(localized: "Hide data", comment: "Canvas – collapse the data panel"))
                    Image(systemName: "chevron.down")
                }
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(ink)
                .frame(maxWidth: .infinity, minHeight: 30)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("canvas_hide_data_button")
        }
    }

    private func rowView(_ row: CanvasDataRow) -> some View {
        Button {
            onSelect(row.kind)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: row.systemImage)
                    .font(.footnote)
                Text(row.title)
                    .font(.footnote.weight(.semibold))
                Spacer(minLength: 8)
                Text("\(row.value)/\(row.maxValue)")
                    .font(.footnote.weight(.semibold))
                    .monospacedDigit()
            }
            .foregroundStyle(ink)
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
            .background {
                GeometryReader { proxy in
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(AppColors.brandAccent.opacity(0.85))
                        .frame(width: max(0, proxy.size.width * row.fill))
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(ink.opacity(0.08))
            )
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(row.title), \(row.value) of \(row.maxValue)")
    }

    private var dismissDrag: some Gesture {
        DragGesture(minimumDistance: 8)
            .onChanged { value in
                // Downward only — dragging up must not detach the sheet.
                dragOffset = max(0, value.translation.height)
            }
            .onEnded { value in
                let flicked = value.velocity.height > Self.dismissVelocity
                let pulled = value.translation.height > Self.dismissDistance
                if flicked || pulled {
                    onHide()
                }
                withAnimation(
                    reduceMotion
                        ? .easeInOut(duration: 0.15)
                        : .interactiveSpring(response: 0.32, dampingFraction: 0.86)
                ) {
                    dragOffset = 0
                }
            }
    }
}
```

- [ ] **Step 4: Present it from `GalleryView`**

Add this computed property next to `canvasControls`:

```swift
    private var dataPanelRows: [CanvasDataRow] {
        [
            CanvasDataRow(
                kind: .steps,
                title: String(localized: "Steps", comment: "Canvas data panel – steps row"),
                systemImage: "shoeprints.fill",
                value: model.stepsPointsToday,
                maxValue: EnergyDefaults.stepsMaxPoints
            ),
            CanvasDataRow(
                kind: .sleep,
                title: String(localized: "Sleep", comment: "Canvas data panel – sleep row"),
                systemImage: "bed.double.fill",
                value: model.sleepPointsToday,
                maxValue: EnergyDefaults.sleepMaxPoints
            ),
            CanvasDataRow(
                kind: .happenings,
                title: String(localized: "Happenings", comment: "Canvas data panel – happenings row"),
                systemImage: "sparkles",
                value: model.happeningPointsToday,
                maxValue: HappeningDefaults.happeningsMaxPoints
            )
        ]
    }

    /// The sheet sits above the action row, so the row's own hit height counts
    /// as chrome for both the clearance and the 40% budget.
    private var dataPanelBottomClearance: CGFloat { bottomControlsPadding + 72 }

    @ViewBuilder
    private var dataPanelOverlay: some View {
        if presentation.showsDataPanel {
            VStack {
                Spacer(minLength: 0)
                CanvasDataPanel(
                    rows: dataPanelRows,
                    maxHeight: CanvasDataPanel.maxHeight(
                        viewportHeight: canvasViewportSize.height,
                        topInset: safeAreaTop + topCardHeight,
                        bottomInset: dataPanelBottomClearance
                    ),
                    onSelect: { metricOverlay = $0 },
                    onHide: {
                        send(.hideData)
                        lightHapticTick &+= 1
                    }
                )
                .padding(.horizontal, 12)
                .padding(.bottom, dataPanelBottomClearance)
            }
            .transition(
                reduceMotion
                    ? .opacity
                    : .move(edge: .bottom).combined(with: .opacity)
            )
        }
    }
```

Then add the overlay to `body`, immediately after the `canvasControls` overlay (line 414):

```swift
        .overlay {
            dataPanelOverlay
        }
```

- [ ] **Step 5: Run the layout test and build**

Run:

```bash
xcodebuild test -project Steps4.xcodeproj -scheme Steps4 -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17,OS=latest' -only-testing:Steps4Tests/CanvasDataPanelLayoutTests CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO
```

Expected: 3 tests pass. Then in the simulator confirm: `Show data` raises the sheet without moving the pill, the label flips to `Hide data`, dragging the sheet down past ~60pt dismisses it, tapping a row opens the existing metric overlay, and tapping `+` or the full-screen circle dismisses the sheet first.

- [ ] **Step 6: Commit**

```bash
git add StepsTrader/Views/Gallery/CanvasDataPanel.swift Steps4Tests/CanvasDataPanelLayoutTests.swift StepsTrader/Views/GalleryView.swift Steps4.xcodeproj/project.pbxproj && git commit -m "feat: add canvas data panel"
```

---

## Task 9: Editing — drag, remix, delete on long press

**Files:**
- Create: `StepsTrader/Views/Gallery/CanvasEditingDock.swift`
- Modify: `StepsTrader/Views/GalleryView.swift` (`editModeElementOverlays`, `editModeGestureOverlay`, gesture handlers, `body`)
- Modify: `StepsTrader/Views/Gallery/CanvasStateManagers.swift`
- Modify: `Steps4.xcodeproj/project.pbxproj`

**Interfaces:**
- Consumes: `CanvasRemix` (Task 3), `CanvasPresentationState` (Task 2).
- Produces: `struct CanvasEditingDock: View` with `let showsDragHint: Bool`, `let onDone: () -> Void`, `let onRemix: () -> Void`.

- [ ] **Step 1: Write the editing chrome**

Create `StepsTrader/Views/Gallery/CanvasEditingDock.swift`:

```swift
import SwiftUI

/// Editing chrome: Done in the top-left, Remix at the bottom, and a one-time
/// line telling the user the only gesture there is.
///
/// There is no Select / Draw / Text / Elements toolbar. The canvas is not a
/// drawing surface — it is an arrangement of things that happened, and the only
/// thing worth arranging is where they sit.
struct CanvasEditingDock: View {
    let showsDragHint: Bool
    let onDone: () -> Void
    let onRemix: () -> Void

    private var ink: Color { AppColors.Night.textPrimary }

    var body: some View {
        ZStack {
            VStack {
                HStack {
                    doneControl
                    Spacer(minLength: 0)
                }
                if showsDragHint {
                    dragHint
                        .padding(.top, 12)
                        .transition(.opacity)
                }
                Spacer(minLength: 0)
            }

            VStack {
                Spacer(minLength: 0)
                remixControl
            }
        }
    }

    private var doneControl: some View {
        Button(action: onDone) {
            Text(String(localized: "Done", comment: "Canvas editing – finish editing"))
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(ink)
                .padding(.horizontal, 20)
                .frame(minHeight: 44)
                .liquidGlassControl(in: Capsule(style: .continuous))
                .contentShape(Capsule(style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(String(localized: "Done editing", comment: "Canvas editing – Done VoiceOver label"))
        .accessibilityIdentifier("canvas_done_button")
    }

    private var remixControl: some View {
        Button(action: onRemix) {
            Text(String(localized: "Remix", comment: "Canvas editing – restyle every element"))
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(AppAccentInk.primary)
                .padding(.horizontal, 28)
                .frame(minHeight: 56)
                .background(AppColors.brandAccent, in: Capsule(style: .continuous))
                .contentShape(Capsule(style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("canvas_remix_button")
    }

    private var dragHint: some View {
        Text(String(localized: "Drag elements to move", comment: "Canvas editing – one-time coach text"))
            .font(.system(size: 14, weight: .medium, design: .rounded))
            .foregroundStyle(ink)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .liquidGlassControl(in: Capsule(style: .continuous))
            .contrastingOnGlass()
            .allowsHitTesting(false)
    }
}
```

- [ ] **Step 2: Trim `CanvasEditState`**

In `StepsTrader/Views/Gallery/CanvasStateManagers.swift`, delete `isEditMode`, `gestureStartRotation` and `gestureStartSize` along with their `reset()` lines. The class becomes:

```swift
@Observable @MainActor
final class CanvasEditState {
    var editFreezeTime: Date? = nil
    var isDraggingElement: Bool = false
    var dragStartBasePosition: CGPoint? = nil
    var activeElementId: UUID? = nil

    func reset() {
        editFreezeTime = nil
        isDraggingElement = false
        dragStartBasePosition = nil
        activeElementId = nil
    }

    func cancelDrag() {
        isDraggingElement = false
        dragStartBasePosition = nil
    }
}
```

Then delete the `editState.isEditMode = new.isEditing` line from the `.onChange(of: presentation)` observer added in Task 5.

- [ ] **Step 3: Replace the per-element overlays with a selection outline**

Replace `editModeElementOverlays` (lines 1308–1375) with:

```swift
    /// Selection feedback only. No bounding box, no resize handles, no delete
    /// button and no per-element dice — the element itself is the control.
    private var editModeElementOverlays: some View {
        let refSize = GenerativeCanvasView.canonicalPortraitSize
        let dim = min(refSize.width, refSize.height)
        let freezeDate = editState.editFreezeTime ?? Date.now

        return ZStack {
            ForEach(dayCanvas.elements) { element in
                let center = GenerativeCanvasView.frozenElementCenter(element, size: refSize, at: freezeDate)
                let effectiveSize = Double(element.userSize ?? CGFloat(element.size))
                let diameter = RayShapeRenderer.editBoundsDiameter(
                    normalizedSize: effectiveSize,
                    canvasDim: dim,
                    shapeType: element.resolvedShapeType
                )
                let isActive = editState.activeElementId == element.id

                if isActive {
                    Circle()
                        .strokeBorder(buttonColor.opacity(0.55), lineWidth: 1.5)
                        .shadow(color: AppColors.brandAccent.opacity(0.45), radius: 6)
                        .frame(width: diameter, height: diameter)
                        .position(x: center.x, y: center.y)
                        .accessibilityElement()
                        .accessibilityLabel(
                            "\(element.displayLabel), \(String(localized: "Selected", comment: "Canvas editing – selected element state"))"
                        )
                        .transition(.opacity)
                }
            }
        }
        .allowsHitTesting(false)
        .animation(.spring(response: 0.25, dampingFraction: 0.8), value: editState.activeElementId)
    }
```

- [ ] **Step 4: Reduce the gestures to drag, tap and long press**

In `editModeGestureOverlay` (lines 1381–1424), delete both the `RotationGesture` and the `MagnificationGesture` `simultaneousGesture` blocks, and add a long press after the tap gesture:

```swift
                .onLongPressGesture(minimumDuration: 0.45) {
                    guard let id = editState.activeElementId else { return }
                    pendingDeleteElementId = id
                    mediumHapticTick &+= 1
                }
```

Delete the four now-unused handlers `handleEditRotation`, `handleEditRotationEnd`, `handleEditPinch`, `handleEditPinchEnd` (lines 1466–1514).

Add the confirmation state next to `presentation`:

```swift
    /// Deletion is deliberate but hidden: no permanent per-element button, and
    /// a long press alone never removes anything.
    @State private var pendingDeleteElementId: UUID? = nil
```

And attach the dialog in `body`, after the `.sheet(isPresented: $toolbar.showShareSheet)` modifier:

```swift
        .confirmationDialog(
            String(localized: "Remove this happening?", comment: "Canvas editing – delete confirmation title"),
            isPresented: Binding(
                get: { pendingDeleteElementId != nil },
                set: { if !$0 { pendingDeleteElementId = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button(String(localized: "Delete"), role: .destructive) {
                if let id = pendingDeleteElementId { removeElement(id: id) }
                pendingDeleteElementId = nil
                editState.activeElementId = nil
            }
            Button(String(localized: "Cancel"), role: .cancel) { pendingDeleteElementId = nil }
        }
```

- [ ] **Step 5: Add Remix and the editing overlay**

Add the action to `GalleryView`:

```swift
    /// Restyles every element at once: one mutation counter bump, one save, one
    /// haptic. Positions, identities, energy and the background gradient are
    /// exactly what they were.
    private func remixCanvas() {
        guard !dayCanvas.elements.isEmpty else { return }
        let composition = DayComposition.forDay(
            dayKey: dayCanvas.dayKey,
            happeningCount: dayCanvas.elements.count
        )
        let remixed = CanvasRemix.remixed(dayCanvas.elements, composition: composition)
        // One ease for both motion settings on purpose: replacing the elements
        // in place *is* the crossfade Reduce Motion asks for — nothing travels
        // and nothing springs, so there is no motion to reduce.
        withAnimation(.easeInOut(duration: 0.3)) {
            dayCanvas.elements = remixed
        }
        dayCanvas.lastModified = Date.now
        localMutationCounter &+= 1
        saveCanvasLocally()
        mediumHapticTick &+= 1
        Task {
            await SupabaseSyncService.shared.trackAnalyticsEvent(name: "canvas_remixed")
        }
    }
```

Add the one-time hint flag next to the other `@AppStorage` fields:

```swift
    /// The drag hint earns one appearance per install, then gets out of the way.
    @AppStorage("canvasEditDragHintShown", store: UserDefaults.stepsTrader())
    private var editDragHintShown: Bool = false
    @State private var showsEditDragHint = false
    @State private var editDragHintTask: Task<Void, Never>? = nil
```

Add the overlay to `body`, after `wideCanvasOverlay`:

```swift
        .overlay {
            if presentation.showsEditingChrome {
                CanvasEditingDock(
                    showsDragHint: showsEditDragHint,
                    onDone: {
                        if editState.isDraggingElement { handleEditDragEnd() }
                        editState.activeElementId = nil
                        saveCanvasLocally()
                        send(.endEditing)
                        lightHapticTick &+= 1
                    },
                    onRemix: { remixCanvas() }
                )
                .padding(.horizontal, 16)
                .padding(.top, max(safeAreaTop, 20))
                .padding(.bottom, max(safeAreaBottom, 34) + 16)
                .ignoresSafeArea()
            }
        }
```

Drive the hint from the presentation observer added in Task 5 — inside its `if !new.isEditing { ... } else { ... }` branches add:

```swift
            if new.isEditing, !editDragHintShown {
                editDragHintShown = true
                showsEditDragHint = true
                editDragHintTask?.cancel()
                editDragHintTask = Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(2500))
                    guard !Task.isCancelled else { return }
                    withAnimation(.easeOut(duration: 0.25)) { showsEditDragHint = false }
                }
            } else if !new.isEditing {
                editDragHintTask?.cancel()
                showsEditDragHint = false
            }
```

And dismiss it on the first successful drag — at the top of `handleEditDragEnd()`:

```swift
        if showsEditDragHint {
            editDragHintTask?.cancel()
            withAnimation(.easeOut(duration: 0.25)) { showsEditDragHint = false }
        }
```

- [ ] **Step 6: Return to viewing when the app resigns active**

In the `willResignActiveNotification` receiver (line 542) and in the `scenePhase` `.inactive` / `.background` branches (lines 513–521), replace the bare `handleEditDragEnd()` calls with:

```swift
            if editState.isDraggingElement { handleEditDragEnd() }
            editState.activeElementId = nil
            if presentation.isEditing { send(.endEditing) }
```

- [ ] **Step 7: Build, test, and check by eye**

Run:

```bash
xcodebuild build -project Steps4.xcodeproj -scheme Steps4 -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17,OS=latest' CODE_SIGNING_ALLOWED=NO && xcodebuild test -project Steps4.xcodeproj -scheme Steps4 -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17,OS=latest' -only-testing:Steps4Tests CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO
```

Expected: BUILD SUCCEEDED, 0 failures. In the simulator confirm: entering editing shows Done + Remix and the hint once; dragging an element moves and persists it; pinch and two-finger rotation no longer change anything; long-pressing a selected element offers Delete; Remix changes every element's look while leaving them where they were; Done returns to Full screen, not to Canvas.

- [ ] **Step 8: Commit**

```bash
git add StepsTrader/Views/Gallery/CanvasEditingDock.swift StepsTrader/Views/Gallery/CanvasStateManagers.swift StepsTrader/Views/GalleryView.swift Steps4.xcodeproj/project.pbxproj && git commit -m "feat: simplify canvas editing to drag and remix"
```

Use IDs `CA51B0080000000000000008` / `CA51F0080000000000000008` for the new file.

---

## Task 10: Presentation analytics

**Files:**
- Modify: `StepsTrader/Views/GalleryView.swift` (the `.onChange(of: presentation)` observer)

**Interfaces:**
- Consumes: `CanvasPresentationState.analyticsEventName(from:to:)` (Task 2), `SupabaseSyncService.shared.trackAnalyticsEvent(name:properties:dedupeKey:)`.
- Produces: nothing new.

- [ ] **Step 1: Emit on every tracked transition**

Inside the `.onChange(of: presentation)` observer, after the mirroring block, add:

```swift
            // Names only. No energy values, HealthKit values, happening labels
            // or element IDs ever go into an analytics property.
            if let event = CanvasPresentationState.analyticsEventName(from: old, to: new) {
                Task { await SupabaseSyncService.shared.trackAnalyticsEvent(name: event) }
            }
```

Note the observer uses `initial: true`, which fires once with `old == new`; `analyticsEventName` returns `nil` there, so no launch-time event is emitted.

`canvas_remixed` is already emitted by `remixCanvas()` from Task 9.

- [ ] **Step 2: Verify the seven names are all wired**

Run:

```bash
grep -rn "canvas_data_opened\|canvas_data_closed\|canvas_fullscreen_entered\|canvas_fullscreen_exited\|canvas_edit_entered\|canvas_edit_exited\|canvas_remixed" StepsTrader
```

Expected: the six transition names in `CanvasPresentationState.swift` and `canvas_remixed` in `GalleryView.swift`.

- [ ] **Step 3: Build and test**

Run:

```bash
xcodebuild build -project Steps4.xcodeproj -scheme Steps4 -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17,OS=latest' CODE_SIGNING_ALLOWED=NO && xcodebuild test -project Steps4.xcodeproj -scheme Steps4 -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17,OS=latest' -only-testing:Steps4Tests CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO
```

Expected: BUILD SUCCEEDED, 0 failures.

- [ ] **Step 4: Commit**

```bash
git add StepsTrader/Views/GalleryView.swift && git commit -m "feat: track canvas presentation analytics"
```

---

## Task 11: UI tests and full verification

**Files:**
- Create: `Steps4UITests/CanvasSimplificationUITests.swift`
- Modify: `Steps4.xcodeproj/project.pbxproj`

**Interfaces:**
- Consumes: the accessibility identifiers added in Tasks 4, 6, 7, 8 and 9.
- Produces: nothing.

- [ ] **Step 1: Write the UI tests**

Create `Steps4UITests/CanvasSimplificationUITests.swift`:

```swift
import XCTest

/// The Canvas screen's four states and the paths between them. These assert
/// structure, not looks: which controls exist, and where a tap lands you.
final class CanvasSimplificationUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    private func launchCanvas() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [
            "ui-testing",
            "ui-testing-task7",
            "-AppleLanguages", "(en)",
            "-AppleLocale", "en_US",
        ]
        app.launch()
        XCTAssertTrue(app.buttons["canvas_add_button"].waitForExistence(timeout: 12))
        return app
    }

    func testCanvasShowsExactlyThreeBottomActions() {
        let app = launchCanvas()

        XCTAssertTrue(app.buttons["canvas_fullscreen_button"].exists)
        XCTAssertTrue(app.buttons["canvas_show_data_button"].exists)
        XCTAssertTrue(app.buttons["canvas_add_button"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["canvas_energy_pill"].exists)
        XCTAssertFalse(app.otherElements["canvas_data_panel"].exists)
    }

    func testShowDataOpensAndClosesThePanelWithoutMovingThePill() {
        let app = launchCanvas()
        let pill = app.descendants(matching: .any)["canvas_energy_pill"]
        let pillFrameBefore = pill.frame

        app.buttons["canvas_show_data_button"].tap()
        XCTAssertTrue(app.otherElements["canvas_data_panel"].waitForExistence(timeout: 3))
        XCTAssertEqual(pill.frame.midX, pillFrameBefore.midX, accuracy: 0.5)

        app.buttons["canvas_hide_data_button"].tap()
        XCTAssertTrue(app.otherElements["canvas_data_panel"].waitForNonExistence(timeout: 3))
        XCTAssertEqual(pill.frame.midX, pillFrameBefore.midX, accuracy: 0.5)
    }

    /// Raising the canvas is a viewing action. Nothing in it may start an edit.
    func testFullScreenHidesChromeAndDoesNotStartEditing() {
        let app = launchCanvas()

        app.buttons["canvas_fullscreen_button"].tap()

        XCTAssertTrue(app.buttons["canvas_exit_fullscreen_button"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["canvas_edit_button"].exists)
        XCTAssertFalse(app.buttons["canvas_add_button"].exists)
        XCTAssertFalse(app.buttons["canvas_show_data_button"].exists)
        XCTAssertFalse(app.buttons["tab_canvas"].exists)
        XCTAssertFalse(app.buttons["canvas_remix_button"].exists)
        XCTAssertFalse(app.buttons["canvas_done_button"].exists)
    }

    func testDoneReturnsToFullScreenAndExitReturnsToCanvas() {
        let app = launchCanvas()

        app.buttons["canvas_fullscreen_button"].tap()
        XCTAssertTrue(app.buttons["canvas_edit_button"].waitForExistence(timeout: 3))
        app.buttons["canvas_edit_button"].tap()

        XCTAssertTrue(app.buttons["canvas_done_button"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["canvas_remix_button"].exists)

        app.buttons["canvas_done_button"].tap()
        // Done goes back to viewing, not all the way out.
        XCTAssertTrue(app.buttons["canvas_exit_fullscreen_button"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.buttons["canvas_add_button"].exists)

        app.buttons["canvas_exit_fullscreen_button"].tap()
        XCTAssertTrue(app.buttons["canvas_add_button"].waitForExistence(timeout: 3))
    }

    func testAddOpensTheExistingHappeningPalette() {
        let app = launchCanvas()

        app.buttons["canvas_add_button"].tap()

        XCTAssertTrue(app.buttons["Close"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Choose happenings"].exists)
    }

    func testOpeningThePaletteDismissesTheDataPanel() {
        let app = launchCanvas()

        app.buttons["canvas_show_data_button"].tap()
        XCTAssertTrue(app.otherElements["canvas_data_panel"].waitForExistence(timeout: 3))

        app.buttons["canvas_add_button"].tap()
        XCTAssertTrue(app.buttons["Close"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.otherElements["canvas_data_panel"].exists)
    }
}
```

- [ ] **Step 2: Add the file to the UI-test target**

Anchor on `Steps4UITestsLaunchTests.swift` — add its `PBXBuildFile`, `PBXFileReference`, group child and Sources entry in the same lists, using IDs `CA51B0210000000000000021` / `CA51F0210000000000000021`.

- [ ] **Step 3: Run the UI tests**

Run:

```bash
xcodebuild test -project Steps4.xcodeproj -scheme Steps4 -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17,OS=latest' -only-testing:Steps4UITests/CanvasSimplificationUITests CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO
```

Expected: 6 tests pass. If a test cannot reach Canvas because onboarding intercepts the launch, fix the launch arguments (the `ui-testing` + `ui-testing-task7` pair is what the existing palette tests use) — do not weaken the assertions.

- [ ] **Step 4: Run the whole suite**

Run:

```bash
xcodebuild test -project Steps4.xcodeproj -scheme Steps4 -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17,OS=latest' CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO
```

Expected: 0 failures across `Steps4Tests` and `Steps4UITests`, including `CoachMarkTourTests`.

- [ ] **Step 5: Walk the acceptance criteria by hand**

In the simulator, confirm each item of spec §15 and record the result:

1. Canvas opens with a centred `remaining / earnedToday` pill; no `100`, no `Energy`.
2. The pill never shows remaining greater than earned (check with a spent day).
3. The pill stays centred in both Canvas and Data.
4. Bottom actions are exactly outlined circle · Show data · yellow `+`.
5. Show data opens a bottom panel and does not expand the pill.
6. Full screen hides pill, data controls, `+` and tab bar.
7. Entering full screen does not activate editing.
8. Editing begins only from Edit in Full screen.
9. Editing supports dragging and has no generic toolbar.
10. Remix restyles every element while preserving positions and count.
11. Done returns Editing → Full screen.
12. Changes survive relaunch.
13. VoiceOver on the pill reads "Daily energy — 58 remaining out of 72 earned today".
14. Repeat 1–6 with Reduce Motion and with Reduce Transparency enabled in Settings › Accessibility, then with Increase Contrast (the full-screen circle's outline must visibly darken).

- [ ] **Step 6: Commit**

```bash
git add Steps4UITests/CanvasSimplificationUITests.swift Steps4.xcodeproj/project.pbxproj && git commit -m "test: cover simplified canvas ui flows"
```

If the build regenerated `StepsTrader/Localizable.xcstrings` with the new keys, stage only those hunks:

```bash
git add -p StepsTrader/Localizable.xcstrings && git commit -m "chore: extract canvas simplification strings"
```

---

## Self-review notes

**Spec coverage.** §2 → Task 1. §3 → Task 2. §4 → Tasks 4, 7. §5 → Task 8. §6 → Task 6. §7 → Tasks 3, 9. §8 → Tasks 4–9 (the spec's four recommended extractions plus `CanvasEditingDock`, which §7.1's Done + Remix chrome requires). §9 tokens → used verbatim in Tasks 4, 6, 7, 8, 9. §10 motion/haptics → Tasks 4 (300 ms ease progress), 6/7 (light on navigation), 8 (interactive spring, 150 ms under Reduce Motion), 9 (medium on Remix, 300 ms swap). §11 accessibility → Tasks 4, 7, 8, 9, verified in Task 11 Step 5. §12 strings → introduced where each control is built; extraction handled in Task 11. §13 edge cases → Tasks 2 (day boundary, tab switch, palette), 8 (energy changes with the sheet open), 7 (Dynamic Type minimum scale). §14 analytics → Task 10. §15 → Task 11 Step 5. §16 → Tasks 1, 2, 3, 8 (unit) and 11 (UI). §17 → Global Constraints plus the coach-mark mapping in "Decisions taken on top of the spec".

**Not covered, deliberately.** The spec's snapshot-test matrix (§16, "SwiftUI / snapshot coverage") is replaced by the manual accessibility pass in Task 11 Step 5: the project has no snapshot-testing infrastructure, and standing one up is a separate piece of work. Flag this to the product owner if snapshot regressions matter more than the schedule.

**Known regression accepted in Task 4.** Opening the happening palette from the Feeds tab (previously the card's Happenings chip) no longer exists. `CanvasPaletteRouteState` and `GalleryView.consumePaletteOpenRequestIfReady()` remain in place, so restoring the shortcut later is a one-line caller change.
