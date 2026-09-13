# Canvas UI Follow-ups Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Act on the product owner's review of the shipped Canvas redesign: put the day's 100-point ceiling back in the status pill, stop the data panel clipping its own last row, explain where each metric's contribution comes from, and lift the suggestion banner out of the way.

**Architecture:** Six changes, no new subsystems. `CanvasEnergyStatus` gains the day's maximum so the pill can show two dynamic numbers against one static ceiling. `CanvasDataPanel` drops its duplicate header control and sizes to its content. `GalleryMetricOverlayView` gains a per-metric explanation, a research link and a pointer to Settings, reached from a faint `?` in each panel row. The suggestion banner moves up under the pill.

**Tech Stack:** Swift 6, SwiftUI (iOS deployment target 26.1), XCTest, XCUITest.

**Predecessor:** `docs/superpowers/plans/2026-08-18-canvas-ui-simplification.md` — this plan amends what that one shipped. Spec: `docs/design/2026-08-16-canvas-ui-simplification-spec.md`.

## Global Constraints

- Branch `feat/canvas-ui-simplification` is already pushed and has an open PR (#18) into `codex/remove-stipple`. New commits land in that PR automatically.
- **The working tree carries ~51 uncommitted files belonging to the repo owner's own parallel work** (a "GenerativeScene" experiment among them), and `Steps4.xcodeproj/project.pbxproj` holds their in-progress edits. PRESERVE ALL OF IT. Never `git add -A`, `git add .`, or `git commit -a`. If a task must touch `project.pbxproj`, stage it with `git add -p` and verify `git diff --cached -- Steps4.xcodeproj/project.pbxproj | grep -ci generativescene` prints `0` before committing.
- **Do not change the energy formula.** `EnergyDefaults.maxBaseEnergy` is 100; steps 20 + sleep 20 + happenings 60 sum to exactly that. Row denominators stay `0/20`, `0/20`, `60/60`. This was explicitly confirmed with the product owner.
- Do not change the persisted `CanvasElement` JSON schema, HealthKit, Supabase, App Group or day-boundary contracts.
- Do not hand-edit `StepsTrader/Localizable.xcstrings`; Xcode extracts new `String(localized:)` keys at build time. That file already carries unrelated pending changes — leave it unstaged.
- Reuse existing primitives only: `AppColors.brandAccent`, `AppColors.Night.textPrimary`, `AppAccentInk.primary`, `glassCard`, `liquidGlassControl`, `contrastingOnGlass`, `minimumHitTarget`. No second yellow, no hand-rolled glass.
- **Any manual check in the simulator must pass the `ui-testing` launch argument.** `StepsTraderApp.swift:362` calls `bootstrap(requestPermissions: !isUITest)`; without it a Screen Time / FamilyControls alert swallows every touch.
- Before every commit run `git diff --cached --check` and confirm `git diff --cached --name-only` lists only that task's files.
- Build: `xcodebuild build -project Steps4.xcodeproj -scheme Steps4 -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17,OS=latest' CODE_SIGNING_ALLOWED=NO`
- Unit tests: `xcodebuild test -project Steps4.xcodeproj -scheme Steps4 -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17,OS=latest' -only-testing:Steps4Tests CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO`
- Baseline at branch head `3cf1fc9`: `Steps4Tests` 718 tests / 1 skipped / 0 failures (718 includes 12 of the owner's own `GenerativeSceneParamsTests`), `Steps4UITests` 18 / 0 failures.
- `Steps4Tests/CanvasPersistenceRegressionTests.swift:70` is a known wall-clock flake firing roughly one run in four. Rerun before treating it as a regression.

## Decisions from the product owner

1. **The pill shows two dynamic numbers and one static one:** how much was earned across the day, how much of it is left, and the day's ceiling of 100. Its bar measures 100, not today's earnings.
2. **No formula change.** The `60/60` on the Happenings row is correct and stays; it stops reading as "day complete" because the pill now carries the real ceiling.
3. **The panel may grow** — "расширим панель data при необходимости". Size it to its content rather than clipping.
4. **The duplicate `Hide data` in the panel header goes.** The bottom action row keeps its copy.
5. **The `?` feeds the existing metric overlay** rather than expanding the row, so the panel stays compact.
6. **Research links, one per metric** (supplied by the owner):
   - Steps — `https://pubmed.ncbi.nlm.nih.gov/24749966/`
   - Sleep — `https://www.nature.com/articles/nrn2762`
   - Happenings — `https://www.sciencedirect.com/science/article/pii/S0022103112000212`

## Assumption stated, not asked

The "you can change this in Settings" line is plain text naming Settings, not a deep link. Deep-linking would need a `FeatureTipSettingsPage` route and a dismissal of the overlay first; that is more machinery than the sentence is worth. Flag it if the owner wants the jump.

## File Map

### Modified

- `StepsTrader/Models/CanvasEnergyStatus.swift` — gains `maximum`, `progress` re-based on it, plus `earnedProgress`.
- `Steps4Tests/CanvasEnergyStatusTests.swift` — cases updated for the new denominator.
- `StepsTrader/Views/Gallery/CanvasEnergyStatusPill.swift` — three numbers, 100-scale bar with an earned tick, wider frame.
- `StepsTrader/Views/MainTabView.swift` — passes the maximum.
- `StepsTrader/Views/Gallery/CanvasDataPanel.swift` — header control removed, content-sized, `?` per row.
- `StepsTrader/Views/Gallery/GalleryMetricOverlayView.swift` — explanation, research link, Settings line.
- `StepsTrader/Views/GalleryView.swift` — banner placement, panel wiring.

---

## Task 1: The pill carries the day's ceiling

**Files:**
- Modify: `StepsTrader/Models/CanvasEnergyStatus.swift`
- Test: `Steps4Tests/CanvasEnergyStatusTests.swift`

**Interfaces:**
- Produces: `CanvasEnergyStatus(stepsBalance:baseEnergyToday:maximum:)` with `let maximum: Int`, `var progress: Double` (remaining ÷ maximum) and `var earnedProgress: Double` (earned ÷ maximum). `remaining` and `earned` keep their current meaning and clamping.

- [ ] **Step 1: Rewrite the test file**

The denominator changes, so every progress expectation changes with it. Replace `Steps4Tests/CanvasEnergyStatusTests.swift` with:

```swift
import XCTest
@testable import Steps4

/// The Canvas status pill answers two questions against one fixed ceiling: how
/// much the day earned, and how much of that is still unspent. The ceiling is
/// the product's daily maximum, so a full bar means a full day — not merely
/// that nothing has been spent yet.
final class CanvasEnergyStatusTests: XCTestCase {

    private func status(balance: Int, earned: Int, max: Int = 100) -> CanvasEnergyStatus {
        CanvasEnergyStatus(stepsBalance: balance, baseEnergyToday: earned, maximum: max)
    }

    func testShowsRemainingEarnedAndCeiling() {
        let s = status(balance: 40, earned: 60)

        XCTAssertEqual(s.remaining, 40)
        XCTAssertEqual(s.earned, 60)
        XCTAssertEqual(s.maximum, 100)
    }

    /// Both bars measure the ceiling, so a day that earned 60 of 100 reads as
    /// 60% earned even when none of it has been spent.
    func testBothProgressesMeasureTheCeiling() {
        let s = status(balance: 60, earned: 60)

        XCTAssertEqual(s.progress, 0.6, accuracy: 0.0001)
        XCTAssertEqual(s.earnedProgress, 0.6, accuracy: 0.0001)
    }

    func testSpendingMovesRemainingButNotEarned() {
        let s = status(balance: 40, earned: 60)

        XCTAssertEqual(s.progress, 0.4, accuracy: 0.0001)
        XCTAssertEqual(s.earnedProgress, 0.6, accuracy: 0.0001)
    }

    func testNothingEarnedYet() {
        let s = status(balance: 0, earned: 0)

        XCTAssertEqual(s.remaining, 0)
        XCTAssertEqual(s.earned, 0)
        XCTAssertEqual(s.progress, 0, accuracy: 0.0001)
        XCTAssertEqual(s.earnedProgress, 0, accuracy: 0.0001)
    }

    func testFullDay() {
        let s = status(balance: 100, earned: 100)

        XCTAssertEqual(s.progress, 1.0, accuracy: 0.0001)
        XCTAssertEqual(s.earnedProgress, 1.0, accuracy: 0.0001)
    }

    /// A stale balance can outrun today's earnings between a recalculation and
    /// a HealthKit refresh. Remaining still cannot exceed earned.
    func testStaleBalanceClampsToEarned() {
        let s = status(balance: 90, earned: 60)

        XCTAssertEqual(s.remaining, 60)
        XCTAssertEqual(s.progress, 0.6, accuracy: 0.0001)
    }

    /// Earnings cannot exceed the ceiling either — the formula caps
    /// `baseEnergyToday` at 100, and the pill must not draw past its track if
    /// that ever changes.
    func testEarnedClampsToTheCeiling() {
        let s = status(balance: 120, earned: 120)

        XCTAssertEqual(s.earned, 100)
        XCTAssertEqual(s.remaining, 100)
        XCTAssertEqual(s.earnedProgress, 1.0, accuracy: 0.0001)
    }

    func testNegativeInputsFloorAtZero() {
        let s = status(balance: -5, earned: -10)

        XCTAssertEqual(s.remaining, 0)
        XCTAssertEqual(s.earned, 0)
        XCTAssertEqual(s.progress, 0, accuracy: 0.0001)
    }

    /// A zero or negative ceiling would divide by nothing. Both progresses
    /// report empty rather than crashing or reporting a full bar.
    func testNonPositiveCeilingReportsEmpty() {
        let s = status(balance: 10, earned: 10, max: 0)

        XCTAssertEqual(s.progress, 0, accuracy: 0.0001)
        XCTAssertEqual(s.earnedProgress, 0, accuracy: 0.0001)
    }

    func testEqualInputsProduceEqualStatuses() {
        XCTAssertEqual(status(balance: 12, earned: 30), status(balance: 12, earned: 30))
    }
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run the unit-test command with `-only-testing:Steps4Tests/CanvasEnergyStatusTests`.
Expected: compile failure — no `maximum:` parameter.

- [ ] **Step 3: Implement**

Replace the body of `StepsTrader/Models/CanvasEnergyStatus.swift` with:

```swift
import Foundation

/// The daily energy readout behind the Canvas status pill.
///
/// It carries two moving numbers and one fixed one: what the day earned, how
/// much of that is still unspent, and the product's daily ceiling. Both bars
/// measure the ceiling, so a half-full pill means a half-full day rather than
/// "half of whatever happened to be earned so far".
struct CanvasEnergyStatus: Equatable {
    /// Unspent energy from today's earnings, clamped into `0...earned`.
    let remaining: Int
    /// Energy gained today, clamped into `0...maximum`.
    let earned: Int
    /// The product's daily maximum — the static number in the pill.
    let maximum: Int

    /// - Parameters:
    ///   - stepsBalance: `model.userEconomyStore.stepsBalance` — the daily
    ///     balance without bonuses.
    ///   - baseEnergyToday: `model.healthStore.baseEnergyToday`.
    ///   - maximum: `EnergyDefaults.maxBaseEnergy`.
    init(stepsBalance: Int, baseEnergyToday: Int, maximum: Int) {
        self.maximum = maximum
        // The formula already caps earnings at the ceiling, but the pill draws
        // a bar: a value past the track would render outside it.
        let earned = min(max(0, baseEnergyToday), max(0, maximum))
        self.earned = earned
        // A recalculation can land before a HealthKit refresh, leaving a
        // balance that outruns today's earnings. The stale side loses.
        self.remaining = min(max(0, stepsBalance), earned)
    }

    /// Fill fraction for the unspent portion.
    var progress: Double { fraction(of: remaining) }

    /// Fill fraction for everything earned today — drawn as a tick, so the
    /// user can see how far the day got even after spending some of it.
    var earnedProgress: Double { fraction(of: earned) }

    private func fraction(of value: Int) -> Double {
        guard maximum > 0 else { return 0 }
        return Double(value) / Double(maximum)
    }
}
```

- [ ] **Step 4: Run the test to verify it passes**

Same command. Expected: 10 tests pass.

- [ ] **Step 5: Commit**

```bash
git add StepsTrader/Models/CanvasEnergyStatus.swift Steps4Tests/CanvasEnergyStatusTests.swift && git commit -m "feat: give the energy status the day's ceiling"
```

---

## Task 2: The pill shows earned, remaining and the ceiling

**Files:**
- Modify: `StepsTrader/Views/Gallery/CanvasEnergyStatusPill.swift`
- Modify: `StepsTrader/Views/MainTabView.swift`

**Interfaces:**
- Consumes: `CanvasEnergyStatus` with `maximum`, `progress`, `earnedProgress` (Task 1).

- [ ] **Step 1: Rebuild the pill**

Replace the `numbers` and `progressBar` members of `CanvasEnergyStatusPill` with the following, and widen the frame constants from `minWidth: 148 / maxWidth: 176` to `minWidth: 176 / maxWidth: 208`:

```swift
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

            Spacer(minLength: 8)

            // The day's ceiling. Static, and quieter than the two numbers that
            // move, so it reads as the scale rather than as a third reading.
            Text("\(status.maximum)")
                .font(.system(size: 13, weight: .medium))
                .monospacedDigit()
                .foregroundStyle(textPrimary.opacity(0.45))
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

                // Everything earned today, as a quiet band: it shows how far
                // the day got, which spending no longer erases.
                Capsule(style: .continuous)
                    .fill(AppColors.brandAccent.opacity(0.35))
                    .frame(width: max(0, width * status.earnedProgress))

                // What is actually left to spend.
                Capsule(style: .continuous)
                    .fill(AppColors.brandAccent)
                    .frame(width: max(0, width * status.progress))
            }
        }
        .frame(height: Self.progressHeight)
        // Ease only, never a spring: an overshooting bar reads as a value the
        // user briefly did not have.
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.3), value: status)
        // The numbers above already say this; VoiceOver should not repeat it.
        .accessibilityHidden(true)
    }
```

- [ ] **Step 2: Update the accessibility value**

The pill is one accessibility element and its value must now mention all three numbers. Replace the `.accessibilityValue(...)` argument with:

```swift
        .accessibilityValue(
            String(
                localized: "\(status.remaining) remaining of \(status.earned) earned today, out of \(status.maximum)",
                comment: "Canvas status pill – VoiceOver value"
            )
        )
```

- [ ] **Step 3: Pass the ceiling from `MainTabView`**

In `StepsTrader/Views/MainTabView.swift`, the pill is constructed inside `.overlay(alignment: .top)`. Add the argument:

```swift
                CanvasEnergyStatusPill(
                    status: CanvasEnergyStatus(
                        stepsBalance: model.userEconomyStore.stepsBalance,
                        baseEnergyToday: model.healthStore.baseEnergyToday,
                        maximum: EnergyDefaults.maxBaseEnergy
                    )
                )
```

- [ ] **Step 4: Update the previews**

`CanvasEnergyStatusPill`'s `#Preview` constructs three statuses. Give each a `maximum: EnergyDefaults.maxBaseEnergy`, and change the middle one to `stepsBalance: 40, baseEnergyToday: 60` so the preview shows the spent-today case the product owner described.

- [ ] **Step 5: Build and check by eye**

Build, then launch the simulator with the `ui-testing` argument and confirm the pill reads `40 / 60` with a quiet `100` at its right, that the bar's bright fill stops at 40% and its dim band at 60%, and that the pill stays horizontally centred.

- [ ] **Step 6: Commit**

```bash
git add StepsTrader/Views/Gallery/CanvasEnergyStatusPill.swift StepsTrader/Views/MainTabView.swift && git commit -m "feat: show the day's ceiling in the status pill"
```

---

## Task 3: The data panel fits its own content

**Files:**
- Modify: `StepsTrader/Views/Gallery/CanvasDataPanel.swift`
- Modify: `StepsTrader/Views/GalleryView.swift`
- Test: `Steps4Tests/CanvasDataPanelLayoutTests.swift`

- [ ] **Step 1: Delete the duplicate header control**

In `CanvasDataPanel`, the header carries both a drag handle and a `Hide data` button, duplicating the bottom action row's centre control. Replace the whole `header` property with just the handle:

```swift
    /// The bottom action row already carries `Hide data`; a second copy inside
    /// the panel was the same control twice on one screen. The handle stays —
    /// it is what makes the sheet feel draggable.
    private var header: some View {
        Capsule()
            .fill(ink.opacity(0.45))
            .frame(width: 36, height: 4)
            .accessibilityHidden(true)
    }
```

Delete `canvas_hide_data_button` along with it. Its only assertion lives in the UI tests, which Task 6 updates.

- [ ] **Step 2: Stop capping the frame below the content**

The panel's `.frame(maxWidth: .infinity, maxHeight: maxHeight, alignment: .top)` is what let the rows draw outside the glass: `.frame(maxHeight:)` constrains the proposal, not the render, so the background painted at the capped height while the content overflowed it. The product owner has asked for the panel to grow instead. Replace that modifier with:

```swift
        // No `maxHeight` clamp: it constrained the proposal, not the render, so
        // the rows drew outside the glass that was supposed to contain them.
        // The panel is sized by its content and the host gives it room.
        .frame(maxWidth: .infinity, alignment: .top)
```

Delete the `maxHeight` stored property and the `static func maxHeight(viewportHeight:topInset:bottomInset:)` along with it, and delete `Steps4Tests/CanvasDataPanelLayoutTests.swift` — the rule it tested no longer exists. Remove the test file's four `project.pbxproj` entries (IDs `CA51B0140000000000000014` / `CA51F0140000000000000014`), staging that file with `git add -p` per the global constraints.

- [ ] **Step 3: Simplify the host**

In `GalleryView.dataPanelOverlay`, drop the `maxHeight:` argument. Keep `dataPanelBottomClearance` — it is what holds the panel above the action row.

- [ ] **Step 4: Add the `?` control to each row**

`CanvasDataRow` gains nothing; the control is a sibling of the row button so a tap on it does not also trigger the row. In `rowView`, wrap the existing button in an `HStack` with the help control leading:

```swift
    private func rowView(_ row: CanvasDataRow) -> some View {
        HStack(spacing: 8) {
            Button {
                onExplain(row.kind)
            } label: {
                Image(systemName: "questionmark.circle")
                    .font(.system(size: 15, weight: .regular))
                    .foregroundStyle(ink.opacity(0.35))
                    .frame(width: 28, height: 28)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(
                String(localized: "What counts as \(row.title)?",
                       comment: "Canvas data panel – per-row explanation button")
            )
            .accessibilityIdentifier("canvas_row_help_\(row.kind.id)")

            rowButton(row)
        }
    }
```

Rename the existing row body to `rowButton(_:)`, unchanged apart from the name, and add `let onExplain: (MetricOverlayKind) -> Void` to `CanvasDataPanel`'s properties.

- [ ] **Step 5: Wire the new closure**

In `GalleryView.dataPanelOverlay`, pass `onExplain: { metricOverlay = $0 }` alongside the existing `onSelect`. Both open the same overlay today; Task 4 is what makes the overlay carry the explanation, and keeping them separate means a later change can send them to different places without touching the panel.

- [ ] **Step 6: Build, test and check by eye**

Build, run the unit suite (expect 718 − 3 deleted layout tests = 715, plus the owner's tests), then launch with `ui-testing`, open the data panel and confirm all three rows are fully inside the glass, that the panel does not reach the bottom action row, and that only one `Hide data` control is on screen.

- [ ] **Step 7: Commit**

```bash
git add StepsTrader/Views/Gallery/CanvasDataPanel.swift StepsTrader/Views/GalleryView.swift Steps4Tests/CanvasDataPanelLayoutTests.swift Steps4.xcodeproj/project.pbxproj && git commit -m "fix: let the data panel contain its own rows"
```

---

## Task 4: The metric overlay explains and cites

**Files:**
- Modify: `StepsTrader/Views/Gallery/GalleryMetricOverlayView.swift`

- [ ] **Step 1: Add the explanation block**

Append this to the overlay's `VStack`, after `overlayContent(for: kind)`:

```swift
                Divider()
                    .overlay(Color.white.opacity(0.15))

                VStack(alignment: .leading, spacing: 10) {
                    Text(explanation(for: kind))
                        .font(.footnote)
                        .foregroundStyle(.white.opacity(0.8))
                        .fixedSize(horizontal: false, vertical: true)

                    Text(String(localized: "You can change your daily goals in Settings.",
                                comment: "MetricOverlay – where to adjust goals"))
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.55))

                    Link(destination: researchURL(for: kind)) {
                        HStack(spacing: 4) {
                            Text(String(localized: "Read the research",
                                        comment: "MetricOverlay – link to the source study"))
                            Image(systemName: "arrow.up.right")
                        }
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(AppColors.brandAccent)
                    }
                    .accessibilityIdentifier("metric_research_link_\(kind.id)")
                }
```

- [ ] **Step 2: Add the copy and the links**

Add these two methods to `GalleryMetricOverlayView`. The copy says what the metric contributes to the day's 100 and where the number comes from — it is not a health claim, and it does not tell the user what to do.

```swift
    /// What this metric contributes to the day, in one breath. The point is to
    /// answer "why is this number what it is", not to advise.
    private func explanation(for kind: MetricOverlayKind) -> String {
        switch kind {
        case .steps:
            return String(
                localized: "Steps fill up to \(EnergyDefaults.stepsMaxPoints) of the day's \(EnergyDefaults.maxBaseEnergy) colors, in proportion to your daily step goal.",
                comment: "MetricOverlay – how steps contribute"
            )
        case .sleep:
            return String(
                localized: "Sleep fills up to \(EnergyDefaults.sleepMaxPoints) of the day's \(EnergyDefaults.maxBaseEnergy) colors, in proportion to your sleep goal. A night without data is assumed rather than counted as zero.",
                comment: "MetricOverlay – how sleep contributes"
            )
        case .happenings:
            return String(
                localized: "Happenings fill up to \(HappeningDefaults.happeningsMaxPoints) of the day's \(EnergyDefaults.maxBaseEnergy) colors — the largest share, because they are the part of the day you choose. Each happening counts once per day.",
                comment: "MetricOverlay – how happenings contribute"
            )
        }
    }

    /// The study behind each metric's share of the day. Supplied by the
    /// product owner; force-unwrapped because these are compile-time literals
    /// and a malformed one should fail loudly in the first preview, not
    /// silently render a dead link.
    private func researchURL(for kind: MetricOverlayKind) -> URL {
        switch kind {
        case .steps:
            return URL(string: "https://pubmed.ncbi.nlm.nih.gov/24749966/")!
        case .sleep:
            return URL(string: "https://www.nature.com/articles/nrn2762")!
        case .happenings:
            return URL(string: "https://www.sciencedirect.com/science/article/pii/S0022103112000212")!
        }
    }
```

- [ ] **Step 3: Build and check by eye**

Build, launch with `ui-testing`, open the data panel and tap each row's `?`. Confirm the overlay shows the explanation, the Settings line and the link for each of the three metrics, that the card still hugs its content without scrolling off screen, and that tapping the link opens Safari.

- [ ] **Step 4: Commit**

```bash
git add StepsTrader/Views/Gallery/GalleryMetricOverlayView.swift && git commit -m "feat: explain each metric's share of the day"
```

---

## Task 5: The suggestion banner sits under the pill

**Files:**
- Modify: `StepsTrader/Views/GalleryView.swift`

- [ ] **Step 1: Raise it and stop the truncation**

The banner currently sits at `deviceTopSafeAreaInset + topCardHeight + 24` and its subtitle truncates mid-sentence ("You slept — add it to your can…"). Reduce the gap so it tucks under the pill, and let the subtitle wrap:

In `canvasControls`, change the banner's padding to:

```swift
                // Tucked under the pill rather than floating below it: the
                // suggestion is about the same day the pill is measuring.
                .padding(.top, deviceTopSafeAreaInset + topCardHeight + 8)
```

- [ ] **Step 2: Let the copy breathe**

Open `ActivitySuggestionBanner` (find it with `grep -rn "struct ActivitySuggestionBanner" StepsTrader/`) and give its subtitle `.lineLimit(2)` and `.fixedSize(horizontal: false, vertical: true)` if it currently truncates to one line. If the banner is shared with another screen, do not restyle it — instead report that and stop, so the owner can decide whether the change belongs there.

- [ ] **Step 3: Build and check by eye**

Build, launch with `ui-testing`, and confirm the banner sits directly under the pill with its full sentence visible, and that its Add and dismiss buttons still respond to taps. That last check matters: a control too close to the top of the screen is exactly what broke the editing Done button in the previous plan.

- [ ] **Step 4: Commit**

```bash
git add StepsTrader/Views/GalleryView.swift && git commit -m "fix: tuck the suggestion banner under the pill"
```

---

## Task 6: Update the UI tests and verify

**Files:**
- Modify: `Steps4UITests/CanvasSimplificationUITests.swift`

- [ ] **Step 1: Fix the assertions the panel change broke**

`testShowDataOpensAndClosesThePanelWithoutMovingThePill` taps `canvas_hide_data_button`, which Task 3 deleted. Retarget it at the bottom row's `canvas_show_data_button`, which now flips to `Hide data` while the panel is open:

```swift
        app.buttons["canvas_show_data_button"].tap()
        XCTAssertTrue(app.otherElements["canvas_data_panel"].waitForNonExistence(timeout: 3))
```

- [ ] **Step 2: Cover the new help affordance**

Add:

```swift
    /// The `?` opens the metric overlay with its explanation, and does so
    /// without the row's own tap firing as well.
    func testRowHelpOpensTheExplanation() {
        let app = launchCanvas()

        app.buttons["canvas_show_data_button"].tap()
        XCTAssertTrue(app.otherElements["canvas_data_panel"].waitForExistence(timeout: 3))

        app.buttons["canvas_row_help_steps"].tap()

        XCTAssertTrue(app.links["metric_research_link_steps"].waitForExistence(timeout: 3))
    }
```

- [ ] **Step 3: Run everything**

Run the full suite (both targets). Expect `Steps4Tests` green and `Steps4UITests` 19 passing.

- [ ] **Step 4: Walk the owner's punch list by hand**

In the simulator, with the `ui-testing` argument, confirm each of the six reported items:

1. the pill shows remaining, earned and a static 100;
2. the suggestion banner sits under the pill with its full sentence;
3. all three data rows fit inside the panel;
4. each row has a faint `?`;
5. the overlay carries an explanation and a working research link per metric;
6. the overlay names Settings as where the goals change.

- [ ] **Step 5: Commit**

```bash
git add Steps4UITests/CanvasSimplificationUITests.swift && git commit -m "test: cover the data panel help affordance"
```

---

## Self-review notes

**Owner's list → tasks.** Ceiling of 100 in the pill → Tasks 1–2. Banner raised and untruncated → Task 5. Data panel fitting its content → Task 3. Faint `?` per row → Task 3. Explanation, research link, Settings note → Task 4. Verification → Task 6.

**What this plan deletes.** `CanvasDataPanel.maxHeight` and its three unit tests go, because the product owner replaced the rule they encoded ("never exceed 40%") with a different one ("grow as needed"). Deleting a test whose rule no longer exists is correct; silently loosening it would not be.

**Known risk.** Task 3 removes the only clamp on the panel's height. On the smallest supported screen the panel plus the bottom row plus the pill could crowd the canvas. Task 6's manual pass should look at an iPhone SE as well as the default device, and if the panel dominates there, say so rather than reinstating a cap that was just removed by decision.
