# Me, and the collapse to three tabs — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Strip the Me tab to three readings (average sleep, average steps, most frequent happenings), a connected-apps block priced in colors, and a horizontal calendar of past days — and collapse the tab bar from five destinations to three by folding History into Me and moving Settings to a button.

**Architecture:** All aggregation moves out of the view into one pure, testable namespace (`MeWeekStats`) that takes snapshots and dictionaries and returns values. `MeView` becomes a thin layout over it. The radar (`EnergySignatureView`, `MeAxisDetailView`, `RadarLayout` and the radar spotlight cache in `RayShapeRenderer`) is deleted outright. The calendar reuses `DayHistoryTile` and `DayCanvasViewerView` unchanged, re-laid-out as a horizontal strip; `HistoryView` itself goes away. Tab selection gains a clamp so stored raw values from the five-tab era resolve to canvas.

**Tech Stack:** Swift 6, SwiftUI, XCTest (`@testable import Steps4`), iOS Simulator `iPhone 17`.

## Global Constraints

- Build: `xcodebuild -project Steps4.xcodeproj -scheme Steps4 -destination 'platform=iOS Simulator,name=iPhone 17' -configuration Debug build`
- Test: `xcodebuild test -project Steps4.xcodeproj -scheme Steps4 -destination 'platform=iOS Simulator,name=iPhone 17'`
- **The `Steps4` target is NOT a file-system-synchronized group.** Every new `.swift` file needs four edits in `Steps4.xcodeproj/project.pbxproj`: a `PBXBuildFile` entry, a `PBXFileReference` entry, a child entry in the owning `PBXGroup`, and an entry in the target's `Sources` build phase. Copy the shape of the four `HappeningLiquidField.swift` lines (pbxproj lines 154, 474, 1144, 1511). Test files go in the `Steps4Tests` group and that target's Sources phase.
- The analytics event `piece_selected` keeps its name. Do not rename it.
- **No screen may report minutes spent per app.** Per-app minutes are not obtainable — the existing numbers come from the payment log (minutes *bought*) and systematically overstate. They are deleted, not ported.
- `SubscriptionGate.allFeaturesUnlocked` stays `true` in every commit. It is flipped to `false` only inside a verification step and flipped back before committing.
- User-facing strings use `String(localized:comment:)`, matching the surrounding code.
- Tests use XCTest and `@testable import Steps4`, matching every file in `Steps4Tests/`.
- Collections feeding a ranked list must be sorted explicitly with a total order (count desc, then id asc). Swift randomises hash seeds per process, so `Dictionary` iteration order differs between launches.
- The happenings rework has already landed on this branch: `PastDaySnapshot.happeningIds` is flat, `Happening.useCount` / `lastUsedAt` exist, and no `EnergyCategory` remains in Swift. Nothing in this plan waits on it.

## Design decision recorded

`Me-Brief.md` §3.1 suggests sourcing "most frequent happenings" from `Happening.useCount` / `lastUsedAt`. Those are **lifetime** counters — they answer "what do you do most, ever", not "what came up this week", and the screen's own subtitle says *last 7 days*. This plan counts occurrences in the seven `PastDaySnapshot.happeningIds` arrays instead, and resolves ids to titles through `AppModel.resolveOptionTitle`. `useCount` stays untouched and keeps serving the palette ordering.

---

## File Structure

**Tab shell**
- Modify `StepsTrader/Views/MainTabView.swift`: `Tab` becomes internal and gains `resolve(storedRawValue:)`; the History and Settings cases and pages go; `StepBalanceCard` becomes conditional; the feature-tip deep link presents a sheet instead of switching tabs.

**Me**
- Modify `StepsTrader/Views/MeView.swift` (908 lines): loses the radar, the axis-detail overlay, the week rings and the minutes machinery; gains the settings button, the three-number summary, the colors-per-app block and the calendar strip.
- Modify `StepsTrader/Views/MeViewSupport.swift`: `MeWeekSummary` is deleted (superseded by `MeWeekStats.Summary`); `MeSheetsModifier` gains the paywall cover.
- Create `StepsTrader/Views/Me/MeWeekStats.swift`: pure aggregation — week summary, per-app color spend, history unlock set. No SwiftUI, no `Date()`, no `UserDefaults`.
- Create `StepsTrader/Views/Me/MeCalendarStrip.swift`: the horizontal calendar and the `DayHistoryTile` moved out of `HistoryView`.
- Delete `StepsTrader/Views/MeAxisDetailView.swift`, `StepsTrader/Views/Components/EnergySignatureView.swift`, `StepsTrader/Views/HistoryView.swift`.
- Modify `StepsTrader/Shapes/RayShapeRenderer.swift`: delete the radar spotlight cache block (radar-only). `renderSpotlightBitmap`, `rgbComponents` and `sstep` stay — the Gallery canvas path calls them.

**Tests**
- Create `Steps4Tests/MainTabSelectionTests.swift`
- Create `Steps4Tests/MeWeekStatsTests.swift`

**Docs**
- Modify `README.md`: three tabs, no Notes tab.

---

## Task 1: Settings leaves the tab bar — DONE (`57ce3e7`)

Two things this task's steps did not anticipate, both now in the commit:

- **`MainTabView.swift:488` rendered the permission-warning dot on `tab == .settings`.** Deleting the case broke the build with four cascading type-inference errors inside `tabBarItems`' `ForEach`. The dot moved to the `.me` tab icon and to the gear button in `MeView`, so the trail from badge to entry point stays unbroken.
- **The feature-tip CTA needs the 350ms deferral after all.** `FeatureTipSheet` calls `dismiss()` immediately before posting, and presenting the settings sheet on top of a dismissal already in flight gets dropped by UIKit. The handler sets the route immediately, returns early if the sheet is already open, and otherwise waits before presenting. Verified end-to-end: launch tip → CTA → settings sheet → Widget page pushed.


**Files:**
- Modify: `StepsTrader/Views/MainTabView.swift:14`, `:40-77`, `:171-175`, `:186-195`
- Modify: `StepsTrader/Views/MeView.swift`
- Create: `Steps4Tests/MainTabSelectionTests.swift`
- Modify: `Steps4.xcodeproj/project.pbxproj`

**Interfaces:**
- Produces: `MainTabView.Tab` (internal, `Int`-raw, `CaseIterable`) with `static func resolve(storedRawValue: Int) -> Tab`. Task 7 removes the `.history` case from the same enum.
- Produces: `MeView(model:onOpenSettings:)` — `var onOpenSettings: () -> Void = {}`, called by the gear button. **`MainTabView` owns the sheet and the deep-link route, not `MeView`.** `TabView` creates its pages lazily, so a notification that arrives before Me has ever been opened would be delivered to a view that does not exist yet; the host has to hold that state. This is the same reason the settings route was owned by `MainTabView` when Settings was a tab.

- [ ] **Step 1: Write the failing selection tests**

Create `Steps4Tests/MainTabSelectionTests.swift`:

```swift
import XCTest
@testable import Steps4

/// `@SceneStorage("selectedTab")` survives app updates, so a raw value stored by
/// the five-tab build must resolve to something that still exists.
final class MainTabSelectionTests: XCTestCase {

    func testKnownRawValuesResolveToThemselves() {
        XCTAssertEqual(MainTabView.Tab.resolve(storedRawValue: 0), .canvas)
        XCTAssertEqual(MainTabView.Tab.resolve(storedRawValue: 1), .feeds)
        XCTAssertEqual(MainTabView.Tab.resolve(storedRawValue: 2), .me)
    }

    func testRetiredSettingsRawValueResolvesToCanvas() {
        XCTAssertEqual(MainTabView.Tab.resolve(storedRawValue: 4), .canvas)
    }

    func testOutOfRangeRawValuesResolveToCanvas() {
        XCTAssertEqual(MainTabView.Tab.resolve(storedRawValue: -1), .canvas)
        XCTAssertEqual(MainTabView.Tab.resolve(storedRawValue: 99), .canvas)
    }

    func testSettingsIsNoLongerATab() {
        XCTAssertNil(MainTabView.Tab.allCases.first { $0.accessibilityId == "tab_settings" })
    }
}
```

Add the file to `Steps4.xcodeproj/project.pbxproj` (four entries, `Steps4Tests` group + that target's Sources phase).

- [ ] **Step 2: Run the test and verify it fails**

```bash
xcodebuild test -project Steps4.xcodeproj -scheme Steps4 -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:Steps4Tests/MainTabSelectionTests 2>&1 | tail -20
```

Expected: compile failure — `Tab` is `private` and `resolve` does not exist.

- [ ] **Step 3: Make `Tab` internal, drop the settings case, add `resolve`**

In `MainTabView.swift`, replace `private enum Tab: Int, CaseIterable {` with `enum Tab: Int, CaseIterable {`, delete `case settings = 4` and its three `switch` arms (`icon`, `title`, `accessibilityId`), and add:

```swift
        /// `@SceneStorage` persists a raw Int across app updates. Values written
        /// by builds that had more tabs (3 = History, 4 = Settings) no longer
        /// resolve, so anything unknown falls back to the canvas.
        static func resolve(storedRawValue: Int) -> Tab {
            Tab(rawValue: storedRawValue) ?? .canvas
        }
```

- [ ] **Step 4: Clamp the stored selection**

Replace line 14 with a stored value plus a clamped accessor, so every read and write in the file goes through `resolve`:

```swift
    @SceneStorage("selectedTab") private var storedSelection: Int = Tab.canvas.rawValue

    private var selection: Int {
        get { Tab.resolve(storedRawValue: storedSelection).rawValue }
        nonmutating set { storedSelection = Tab.resolve(storedRawValue: newValue).rawValue }
    }

    private var selectionBinding: Binding<Int> {
        Binding(get: { selection }, set: { selection = $0 })
    }
```

Change `TabView(selection: $selection)` (line 113) to `TabView(selection: selectionBinding)`. Every other `selection` read and assignment in the file stays exactly as written.

- [ ] **Step 5: Move the Settings page from a tab to a sheet on the host**

Remove lines 171-175 of `MainTabView.swift` — the `// 4: Settings` comment and the `SettingsSheet(model:embeddedInTab:featureTipRouteBinding:)` page with its `.tag(Tab.settings.rawValue)`. Keep `@State private var settingsDeepLinkRoute` (line 28) and add beside it:

```swift
    /// Settings is a sheet opened from Me. The host owns the flag and the route
    /// because `TabView` builds its pages lazily — a deep link that arrives
    /// before Me has ever been opened must not be delivered to a view that does
    /// not exist yet.
    @State private var showSettings = false
```

Present it on the outer `ZStack`, next to the existing `.overlay { colorsHelpOverlay }`:

```swift
        .sheet(isPresented: $showSettings) {
            SettingsSheet(model: model, featureTipRouteBinding: $settingsDeepLinkRoute)
        }
```

Note `embeddedInTab` is omitted — it defaults to `false`, which drops the `topCardHeight` inset the tab version needed.

- [ ] **Step 6: Re-point the feature-tip deep link at the sheet**

Replace the `onReceive(...openFeatureTipSettings)` block (lines 186-195). The route must be set **before** `showSettings` flips: `SettingsSheet` reads the binding when it is first created and pushes on appear.

```swift
            // Feature-tip CTA deep-link: Settings is a sheet on Me now. Set the
            // route first — SettingsSheet reads the binding at init and pushes
            // via navigationDestination on appear — then present.
            .onReceive(NotificationCenter.default.publisher(for: .openFeatureTipSettings)) { note in
                settingsDeepLinkRoute = (note.userInfo?["page"] as? String)
                    .flatMap(FeatureTipSettingsPage.init(rawValue:))
                withAnimation { selection = Tab.me.rawValue }
                showSettings = true
            }
```

- [ ] **Step 7: Add the settings button to Me**

In `MeView.swift`, add the callback the host wires up — defaulted so the `#Preview` and any other caller still compile:

```swift
    /// Opens the settings sheet. Owned by `MainTabView`, not by this view, so a
    /// deep link works even if Me has never been on screen.
    var onOpenSettings: () -> Void = {}
```

Wire it from the host — in `MainTabView.swift`, line 162:

```swift
                MeView(model: model, onOpenSettings: { showSettings = true })
```

Replace the greeting row (`greetingRow`, line 389) so the gear sits at the trailing edge:

```swift
    private var greetingRow: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(greetingString + ",")
                .font(greetingFont)
                .foregroundStyle(theme.textPrimary.opacity(0.55))
            Button {
                if authService.hasAppleAccount { showProfileEditor = true }
                else { showLogin = true }
            } label: {
                Text(userName)
                    .font(greetingFont.weight(.semibold))
                    .foregroundStyle(theme.textPrimary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(String(localized: "Profile, \(userName). Double tap to edit.", comment: "MeView – profile pill VoiceOver label"))

            Spacer(minLength: 12)

            Button { onOpenSettings() } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 18, weight: .regular))
                    .foregroundStyle(theme.textPrimary.opacity(0.7))
                    .frame(width: 44, height: 44, alignment: .trailing)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("me_settings_button")
            .accessibilityLabel(String(localized: "Settings", comment: "MeView – settings button VoiceOver label"))
        }
    }
```

- [ ] **Step 8: Run the tests and verify they pass**

```bash
xcodebuild test -project Steps4.xcodeproj -scheme Steps4 -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:Steps4Tests/MainTabSelectionTests 2>&1 | tail -20
```

Expected: PASS, 4 tests.

- [ ] **Step 9: Verify by hand in the simulator**

Build and run. Confirm: the tab bar has four destinations (Canvas, Feeds, Me, History); the gear at the top right of Me opens Settings; **Notes from Kosta** is reachable inside it (`Info` → `Notes from Kosta`); a feature-tip CTA that targets Wallpaper or Widget lands on that page inside the sheet.

- [ ] **Step 10: Commit**

```bash
git add StepsTrader/Views/MainTabView.swift StepsTrader/Views/MeView.swift Steps4Tests/MainTabSelectionTests.swift Steps4.xcodeproj/project.pbxproj
git commit -m "feat: move settings out of the tab bar into a sheet on Me"
```

---

## Task 2: The energy bar leaves Me

**Files:**
- Modify: `StepsTrader/Views/MainTabView.swift:245-289`
- Modify: `StepsTrader/Views/MeView.swift:54-56`

**Interfaces:**
- Consumes: `MainTabView.Tab` from Task 1.
- Produces: nothing new. `\.topCardHeight` keeps its meaning (the card's measured height) — Me simply stops insetting by it.

- [ ] **Step 1: Make the card conditional**

In `MainTabView.swift`, the `StepBalanceCard` overlay is currently gated on `if !isWideCanvas, !hidesSurroundingChromeForPalette`. Add the destination test:

```swift
        .overlay(alignment: .top) {
            // Me is where you look back, not where you check your balance.
            if !isWideCanvas, !hidesSurroundingChromeForPalette, selection != Tab.me.rawValue {
```

- [ ] **Step 2: Drop the matching inset in Me**

`MeView` reserves `topCardHeight` at the top of its content (lines 54-56). With no card above it that is a dead gap — `\.topCardHeight` still carries the height measured on the other tabs. Delete the modifier:

```swift
                .safeAreaInset(edge: .top, spacing: 0) {
                    Color.clear.frame(height: topCardHeight)
                }
```

Leave the `@Environment(\.topCardHeight)` declaration; `radarLayout` still reads it until Task 3 deletes it.

- [ ] **Step 3: Verify by hand in the simulator**

Build and run. Confirm the balance card is drawn on Canvas and on Feeds, is absent on Me, and that Me's greeting sits under the status bar with no empty band where the card used to be. Switch Canvas → Me → Canvas and confirm the card does not leave a gap behind on return.

- [ ] **Step 4: Commit**

```bash
git add StepsTrader/Views/MainTabView.swift StepsTrader/Views/MeView.swift
git commit -m "feat: hide the energy bar on Me"
```

---

## Task 3: Delete the radar

**Files:**
- Modify: `StepsTrader/Views/MeView.swift` (lines 23-39, 41-83, 85-237, 307-347, 349-380, 494-565, 643-678)
- Modify: `StepsTrader/Views/MeViewSupport.swift:9-15`
- Modify: `StepsTrader/Shapes/RayShapeRenderer.swift:199-253`
- Delete: `StepsTrader/Views/MeAxisDetailView.swift`
- Delete: `StepsTrader/Views/Components/EnergySignatureView.swift`
- Modify: `Steps4.xcodeproj/project.pbxproj`

**Interfaces:**
- Produces: `MeView` with a `cachedSnaps: [PastDaySnapshot]` state replacing `radarSnaps`, and no `MeWeekSummary` type anywhere. Task 4 introduces `MeWeekStats.Summary` as the replacement; between the two tasks Me shows only the greeting, the earned/spent row and the (still minutes-based) apps section.

- [ ] **Step 1: Delete the two radar view files**

```bash
git rm StepsTrader/Views/MeAxisDetailView.swift StepsTrader/Views/Components/EnergySignatureView.swift
```

Remove their four `project.pbxproj` entries each (`PBXBuildFile`, `PBXFileReference`, group child, Sources phase).

- [ ] **Step 2: Strip the radar out of `MeView`**

Delete, in `MeView.swift`:

- state: `axisDetail`, `radarSnaps`, `radarSummary`, `radarAxes`, `radarCenterGlobalY` (lines 23, 29-39) — and add `@State private var cachedSnaps: [PastDaySnapshot] = []` in their place.
- from `body`: the `.background { radarBackground … }` block, the `.onPreferenceChange(RadarCenterKey.self)`, the `radarTapOverlay` overlay and the `axisDetailOverlay` overlay (lines 44-52, 65-78).
- the whole `// MARK: - Radar layout math` section through `angularDist` (lines 85-237): `RadarCenterKey`, `RadarLayout`, `radarLayout(in:)`, `radarBackground`, `radarTapOverlay`, `angularDist`.
- `axisDetailOverlay` and `dismissAxisDetail` (lines 351-380).
- `averagesSection`, `activitiesSection`, `activityRow` (lines 494-565) — Task 4 replaces them.
- `weekRow`, `dayRing`, `dayRingAccessibilityLabel`, `shortDayLabel` and the ring metrics `weekRingOuter` / `weekRingInner` / `weekDayLabelSize` (lines 303-305, 682-746) — the rings are gone. Keep `isToday` and `computeDayKeys`.
- `colorsSection` (lines 460-490), the block commented "legacy — kept for reference". Nothing calls it.
- the `@Environment(\.topCardHeight)` declaration (line 8) — nothing reads it now.

In `contentSection`, replace `let snaps = radarSnaps` with `let snaps = cachedSnaps` and delete the `radarReserve` constant together with the `if !snaps.isEmpty { Color.clear.frame(height: radarReserve) }` spacer.

Rename `rebuildRadarModel()` to `rebuildWeekModel()` and reduce it to:

```swift
    /// Recomputes the cached week model from the current `pastDays` /
    /// `cachedDayKeys`. Call this whenever the snapshot set changes — NOT from
    /// `body` — so the per-frame render path only reads cached results.
    private func rebuildWeekModel() {
        cachedSnaps = cachedDayKeys.compactMap { pastDays[$0] }
    }
```

Delete `computeWeekSummary(from:)`. Update the two call sites in `loadAllSnapshots()` (lines 775, 799) to `rebuildWeekModel()`.

- [ ] **Step 3: Delete `MeWeekSummary`**

Remove the `MeWeekSummary` struct from `MeViewSupport.swift` (lines 9-15). The two modifiers below it stay untouched.

- [ ] **Step 4: Delete the radar spotlight cache**

In `RayShapeRenderer.swift`, delete the `// MARK: - Radar Spotlight Cache` section — the explanatory comment block, `_radarSpotCache`, `radarSpotlightColors`, `radarSpotlightIfReady` and `warmRadarSpotlights` (lines 199-253). Its only caller was `EnergySignatureView`.

Keep `rgbComponents`, `sstep` and `renderSpotlightBitmap`: the Gallery canvas element path calls them per frame (line 149). Update the two doc comments that say "Exposed for use by EnergySignatureView" / "Exposed for EnergySignatureView" to name the Gallery canvas path instead.

- [ ] **Step 5: Build and verify it compiles clean**

```bash
xcodebuild -project Steps4.xcodeproj -scheme Steps4 -destination 'platform=iOS Simulator,name=iPhone 17' -configuration Debug build 2>&1 | tail -20
```

Expected: `BUILD SUCCEEDED`, with no "unused"/"never used" warnings naming radar symbols. If the compiler reports an unresolved reference to anything deleted here, the reference is a survivor the plan missed — fix it and note it in the task report rather than reinstating the radar.

- [ ] **Step 6: Run the full suite**

```bash
xcodebuild test -project Steps4.xcodeproj -scheme Steps4 -destination 'platform=iOS Simulator,name=iPhone 17' 2>&1 | tail -25
```

Expected: all tests pass. Nothing tested the radar.

- [ ] **Step 7: Verify by hand in the simulator**

Open Me. Expect the greeting, the earned/spent row and the apps bars — no radar, no rings, no reflection, and no blank reserved band where the radar used to sit. Open the Canvas and confirm ray-family elements still render (that path shares `renderSpotlightBitmap`).

- [ ] **Step 8: Commit**

```bash
git add -A StepsTrader/Views StepsTrader/Shapes/RayShapeRenderer.swift Steps4.xcodeproj/project.pbxproj
git commit -m "refactor: delete the Me radar and its layout mathematics"
```

---

## Task 4: `MeWeekStats` — the aggregation, tested

**Files:**
- Create: `StepsTrader/Views/Me/MeWeekStats.swift`
- Create: `Steps4Tests/MeWeekStatsTests.swift`
- Modify: `Steps4.xcodeproj/project.pbxproj`

**Interfaces:**
- Produces, consumed by Tasks 5, 6 and 7:
  - `MeWeekStats.Summary` — `avgSteps: Int`, `avgSleepHours: Double`, `topHappeningIds: [String]`, `Equatable`.
  - `MeWeekStats.summary(snapshots: [PastDaySnapshot], topCount: Int = 3) -> Summary`
  - `MeWeekStats.appSpend(byDay: [String: [String: Int]], dayKeys: [String]) -> [String: Int]`
  - `MeWeekStats.unlockedKeys(sortedKeys: [String], isPro: Bool, freeCount: Int) -> Set<String>`

- [ ] **Step 1: Write the failing tests**

Create `Steps4Tests/MeWeekStatsTests.swift`:

```swift
import XCTest
@testable import Steps4

final class MeWeekStatsTests: XCTestCase {

    private func snap(
        steps: Int = 0,
        sleep: Double = 0,
        happenings: [String] = []
    ) -> PastDaySnapshot {
        PastDaySnapshot(
            inkEarned: 0,
            inkSpent: 0,
            happeningIds: happenings,
            steps: steps,
            sleepHours: sleep
        )
    }

    // MARK: - Summary

    func testEmptyWeekIsAllZeros() {
        let summary = MeWeekStats.summary(snapshots: [])
        XCTAssertEqual(summary, MeWeekStats.Summary())
        XCTAssertTrue(summary.topHappeningIds.isEmpty)
    }

    func testAveragesDivideByTheNumberOfSnapshotsPresent() {
        // Three recorded days; a missing fourth day must not drag the average down.
        let summary = MeWeekStats.summary(snapshots: [
            snap(steps: 9_000, sleep: 8.0),
            snap(steps: 6_000, sleep: 7.0),
            snap(steps: 3_000, sleep: 6.0)
        ])
        XCTAssertEqual(summary.avgSteps, 6_000)
        XCTAssertEqual(summary.avgSleepHours, 7.0, accuracy: 0.0001)
    }

    func testTopHappeningsAreRankedByCountAcrossTheWeek() {
        let summary = MeWeekStats.summary(snapshots: [
            snap(happenings: ["walk", "read"]),
            snap(happenings: ["walk", "call_mom"]),
            snap(happenings: ["walk", "read"])
        ])
        XCTAssertEqual(summary.topHappeningIds, ["walk", "read", "call_mom"])
    }

    func testTopHappeningsBreakTiesByIdSoOrderIsStableAcrossLaunches() {
        let summary = MeWeekStats.summary(snapshots: [
            snap(happenings: ["beta", "alpha", "gamma"])
        ])
        XCTAssertEqual(summary.topHappeningIds, ["alpha", "beta", "gamma"])
    }

    func testTopHappeningsRespectTopCount() {
        let summary = MeWeekStats.summary(
            snapshots: [snap(happenings: ["a", "b", "c", "d"])],
            topCount: 2
        )
        XCTAssertEqual(summary.topHappeningIds, ["a", "b"])
    }

    // MARK: - App spend

    func testAppSpendSumsOnlyTheGivenDays() {
        let byDay = [
            "2026-08-09": ["instagram": 12, "x": 4],
            "2026-08-10": ["instagram": 8],
            "2026-07-01": ["instagram": 999]   // outside the window
        ]
        let spend = MeWeekStats.appSpend(byDay: byDay, dayKeys: ["2026-08-09", "2026-08-10"])
        XCTAssertEqual(spend, ["instagram": 20, "x": 4])
    }

    func testAppSpendIsEmptyWhenNoDaysMatch() {
        let byDay = ["2026-08-09": ["instagram": 12]]
        XCTAssertTrue(MeWeekStats.appSpend(byDay: byDay, dayKeys: ["2026-01-01"]).isEmpty)
    }

    // MARK: - History gate

    func testProUnlocksEveryDay() {
        let keys = ["2026-08-10", "2026-08-09", "2026-08-08"]
        XCTAssertEqual(
            MeWeekStats.unlockedKeys(sortedKeys: keys, isPro: true, freeCount: 2),
            Set(keys)
        )
    }

    func testFreeUnlocksOnlyTheNewestDays() {
        let keys = ["2026-08-10", "2026-08-09", "2026-08-08"]
        XCTAssertEqual(
            MeWeekStats.unlockedKeys(sortedKeys: keys, isPro: false, freeCount: 2),
            ["2026-08-10", "2026-08-09"]
        )
    }

    func testFreeWithFewerDaysThanTheLimitUnlocksEverything() {
        let keys = ["2026-08-10"]
        XCTAssertEqual(
            MeWeekStats.unlockedKeys(sortedKeys: keys, isPro: false, freeCount: 7),
            Set(keys)
        )
    }
}
```

Add the file to `project.pbxproj` (`Steps4Tests` group + that target's Sources phase).

- [ ] **Step 2: Run the tests and verify they fail**

```bash
xcodebuild test -project Steps4.xcodeproj -scheme Steps4 -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:Steps4Tests/MeWeekStatsTests 2>&1 | tail -20
```

Expected: compile failure — `MeWeekStats` does not exist.

- [ ] **Step 3: Implement `MeWeekStats`**

Create `StepsTrader/Views/Me/MeWeekStats.swift`:

```swift
import Foundation

/// Everything Me computes, as pure functions over values. Lives outside the
/// view so the week's numbers can be tested without a SwiftUI host, and so the
/// (non-trivial) aggregation runs once per data load rather than per body pass.
enum MeWeekStats {

    struct Summary: Equatable {
        var avgSteps: Int = 0
        var avgSleepHours: Double = 0
        var topHappeningIds: [String] = []
    }

    /// Averages over the days that actually have a snapshot — a day with no
    /// recorded data is absent, not a zero, so it must not drag the mean down.
    /// Happenings are ranked by how often they came up across the whole window.
    static func summary(snapshots: [PastDaySnapshot], topCount: Int = 3) -> Summary {
        guard !snapshots.isEmpty else { return Summary() }
        let count = snapshots.count

        let totalSteps = snapshots.reduce(0) { $0 + $1.steps }
        let totalSleep = snapshots.reduce(0.0) { $0 + $1.sleepHours }

        var counts: [String: Int] = [:]
        for snapshot in snapshots {
            for id in snapshot.happeningIds { counts[id, default: 0] += 1 }
        }

        // Count descending, then id ascending: Dictionary order is randomised
        // per process, so the tie-break has to be total or the list reshuffles
        // between launches.
        let ranked = counts
            .sorted { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }
            .prefix(topCount)
            .map(\.key)

        return Summary(
            avgSteps: totalSteps / count,
            avgSleepHours: totalSleep / Double(count),
            topHappeningIds: Array(ranked)
        )
    }

    /// Exact per-app color spend over `dayKeys`, summed from the persisted
    /// per-day ledger. Colors, not minutes: minutes per app are not readable by
    /// an app, and the payment log only knows what was bought.
    static func appSpend(byDay: [String: [String: Int]], dayKeys: [String]) -> [String: Int] {
        var totals: [String: Int] = [:]
        for dayKey in dayKeys {
            guard let perApp = byDay[dayKey] else { continue }
            for (key, value) in perApp { totals[key, default: 0] += value }
        }
        return totals
    }

    /// The history days a user may open. Dormant today —
    /// `SubscriptionGate.allFeaturesUnlocked` makes `isPro` unconditionally
    /// true — but the constant is a documented kill-switch, so the rule stays
    /// live and tested.
    static func unlockedKeys(sortedKeys: [String], isPro: Bool, freeCount: Int) -> Set<String> {
        if isPro { return Set(sortedKeys) }
        return Set(sortedKeys.prefix(freeCount))
    }
}
```

Add the file to `project.pbxproj`. Create the `Me` group under `StepsTrader/Views` if the project has no group for it yet — or, matching how `StepsTrader/Views/Palette` files are referenced, add the file reference into the existing `Views` group with `path = Me/MeWeekStats.swift`.

- [ ] **Step 4: Run the tests and verify they pass**

```bash
xcodebuild test -project Steps4.xcodeproj -scheme Steps4 -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:Steps4Tests/MeWeekStatsTests 2>&1 | tail -20
```

Expected: PASS, 10 tests.

- [ ] **Step 5: Commit**

```bash
git add StepsTrader/Views/Me/MeWeekStats.swift Steps4Tests/MeWeekStatsTests.swift Steps4.xcodeproj/project.pbxproj
git commit -m "feat: add tested week aggregation for Me"
```

---

## Task 5: This week, in three numbers

**Files:**
- Modify: `StepsTrader/Views/MeView.swift`

**Interfaces:**
- Consumes: `MeWeekStats.summary(snapshots:topCount:)` from Task 4, `AppModel.resolveOptionTitle(for:)` (`AppModel+DailyEnergy.swift:256`).
- Produces: `MeView.cachedSummary: MeWeekStats.Summary`, rebuilt in `rebuildWeekModel()`.

- [ ] **Step 1: Cache the summary alongside the snapshots**

In `MeView.swift`, add state next to `cachedSnaps`:

```swift
    @State private var cachedSummary = MeWeekStats.Summary()
```

and extend `rebuildWeekModel()`:

```swift
    private func rebuildWeekModel() {
        cachedSnaps = cachedDayKeys.compactMap { pastDays[$0] }
        cachedSummary = MeWeekStats.summary(snapshots: cachedSnaps)
    }
```

- [ ] **Step 2: Add the three-number section**

Add to `MeView.swift`, replacing the deleted `averagesSection` / `activitiesSection`:

```swift
    // MARK: - This week, in three numbers
    //
    // Sleep, steps, happenings — the three things a day is made of, one reading
    // each. No radar, no rings.

    @ViewBuilder
    private func weekSummarySection(_ summary: MeWeekStats.Summary) -> some View {
        VStack(alignment: .leading, spacing: useTightMeLayout ? 10 : 14) {
            sectionHeader(String(localized: "THIS WEEK", comment: "MeView – week summary section header"))

            if summary.avgSleepHours > 0 {
                summaryRow(
                    icon: "moon.zzz.fill",
                    value: summary.avgSleepHours.formatted(.number.precision(.fractionLength(1))) + "h",
                    label: String(localized: "sleep a night", comment: "MeView – average sleep label")
                )
            }

            if summary.avgSteps > 0 {
                summaryRow(
                    icon: "figure.walk",
                    value: formatCompactNumber(summary.avgSteps),
                    label: String(localized: "steps a day", comment: "MeView – average steps label")
                )
            }

            if !summary.topHappeningIds.isEmpty {
                let titles = summary.topHappeningIds.map { model.resolveOptionTitle(for: $0) }
                summaryRow(
                    icon: "sparkles",
                    value: titles.joined(separator: ", "),
                    label: String(localized: "came up most", comment: "MeView – frequent happenings label")
                )
            }
        }
    }

    private func summaryRow(icon: String, value: String, label: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 13))
                .foregroundStyle(theme.textSecondary)
                .frame(width: 18, alignment: .center)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text(value)
                    .font(.system(useTightMeLayout ? .title3 : .title2, design: .rounded).weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(theme.textPrimary)
                    .lineLimit(2)
                Text(label)
                    .font(.caption)
                    .foregroundStyle(theme.textSecondary.opacity(0.6))
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(value), \(label)")
    }
```

Note `.monospacedDigit()` is harmless on the happenings row — the value there is text.

- [ ] **Step 3: Put it in the layout**

In `contentSection`, insert the section between the greeting block and the earned/spent row:

```swift
            weekSummarySection(cachedSummary)
```

- [ ] **Step 4: Build and check the screen**

```bash
xcodebuild -project Steps4.xcodeproj -scheme Steps4 -destination 'platform=iOS Simulator,name=iPhone 17' -configuration Debug build 2>&1 | tail -5
```

Run it. Add two or three happenings on the canvas today, return to Me, and confirm the three rows appear with real titles (not raw ids like `walk_1`). On a fresh install with no data, confirm the section collapses to nothing rather than showing zeros.

- [ ] **Step 5: Run the full suite**

```bash
xcodebuild test -project Steps4.xcodeproj -scheme Steps4 -destination 'platform=iOS Simulator,name=iPhone 17' 2>&1 | tail -25
```

Expected: all tests pass.

- [ ] **Step 6: Commit**

```bash
git add StepsTrader/Views/MeView.swift
git commit -m "feat: show sleep, steps and frequent happenings on Me"
```

---

## Task 6: Connected apps, priced in colors

**Files:**
- Modify: `StepsTrader/Views/MeView.swift` (lines 18-19, 567-622, 805-903)

**Interfaces:**
- Consumes: `MeWeekStats.appSpend(byDay:dayKeys:)` from Task 4, `AppModel.appStepsSpentByDay`, `AppModel.ticketGroups`, `TargetResolver.displayName(for:)`.
- Produces: `MeView.cachedTopApps: [(name: String, spent: Int)]` — the `minutes` member is gone.

- [ ] **Step 1: Delete the minutes machinery**

In `MeView.swift` remove:

- `@State private var cachedWeekMinutesByTarget: [String: Int] = [:]` (line 19).
- `private struct WeekTransactionEntry` and `loadWeeklyMinutesByTarget(dayKeys:)` (lines 872-903) — this is the code that resolves `minutes10` → 10 out of the payment log.
- `formatAppTime(_:)` (lines 615-622).

Narrow `cachedTopApps` to `[(name: String, spent: Int)]` (line 18).

In `loadAllSnapshots()`, drop the minutes half of the detached load:

```swift
        loadTask = Task { @MainActor in
            let names = await Task.detached { Self.loadTransactionNameMap() }.value
            guard !Task.isCancelled else { return }
            cachedTxNames = names
            rebuildTopConsumers()
        }
```

`loadTransactionNameMap()` and `TransactionNameEntry` stay — they supply display names for targets that are no longer in a ticket group.

- [ ] **Step 2: Rebuild the consumer list on exact color spend**

Replace the head of `rebuildTopConsumers()` with the shared aggregation, and drop the minutes lookup from its tail:

```swift
    private func rebuildTopConsumers() {
        let allSpending = MeWeekStats.appSpend(
            byDay: model.appStepsSpentByDay,
            dayKeys: cachedDayKeys
        )

        var results: [(name: String, spent: Int, key: String)] = []
        var claimedKeys: Set<String> = []

        for group in model.ticketGroups {
            let groupKey = "group_\(group.id)"
            var total = allSpending[groupKey] ?? 0
            if total > 0 { claimedKeys.insert(groupKey) }
            if let raw = allSpending[group.id] {
                total += raw
                claimedKeys.insert(group.id)
            }
            if total > 0 { results.append((name: group.name, spent: total, key: groupKey)) }
        }

        let txNames = cachedTxNames
        for (key, value) in allSpending.sorted(by: { $0.key < $1.key }) where !claimedKeys.contains(key) {
            let name: String
            if key.hasPrefix("group_") {
                guard let n = txNames[key] ?? txNames[String(key.dropFirst(6))], !n.isEmpty else {
                    continue
                }
                name = n
            } else {
                name = txNames[key] ?? TargetResolver.displayName(for: key)
            }
            results.append((name: name, spent: value, key: key))
        }

        cachedTopApps = results
            .sorted { $0.spent != $1.spent ? $0.spent > $1.spent : $0.name < $1.name }
            .prefix(5)
            .map { (name: $0.name, spent: $0.spent) }
    }
```

- [ ] **Step 3: Render colors instead of minutes**

Replace `topAppsSection` and `appBarRow` (lines 567-613):

```swift
    // MARK: - Connected apps
    //
    // Each connected app with the colors it cost this week. Bars are relative to
    // the heaviest app, so the ranking reads at a glance. Colors are exact —
    // they come from the per-day spend ledger, not from the payment log.

    private func connectedAppsSection(apps: [(name: String, spent: Int)]) -> some View {
        let maxSpent = max(1, apps.map(\.spent).max() ?? 1)
        return VStack(alignment: .leading, spacing: useTightMeLayout ? 8 : 12) {
            sectionHeader(String(localized: "CONNECTED APPS", comment: "MeView – connected apps section header"))

            VStack(alignment: .leading, spacing: useTightMeLayout ? 10 : 12) {
                ForEach(Array(apps.enumerated()), id: \.offset) { _, app in
                    appBarRow(name: app.name, spent: app.spent, maxSpent: maxSpent)
                }
            }
        }
    }

    private func appBarRow(name: String, spent: Int, maxSpent: Int) -> some View {
        // Minimum fraction so even tiny values are visible as a hint, not invisible.
        let fraction = max(0.04, CGFloat(spent) / CGFloat(maxSpent))
        let spentLabel = String(localized: "\(spent) colors", comment: "MeView – per-app color spend")
        return VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(name)
                    .font(useTightMeLayout ? .footnote : .subheadline)
                    .foregroundStyle(theme.textPrimary)
                    .lineLimit(1)
                Spacer(minLength: 8)
                Text(spentLabel)
                    .font((useTightMeLayout ? Font.footnote : Font.subheadline).weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(theme.textPrimary)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(theme.textPrimary.opacity(0.08))
                    Capsule()
                        .fill(theme.accentColor.opacity(0.75))
                        .frame(width: geo.size.width * fraction)
                }
            }
            .frame(height: 4)
            .accessibilityHidden(true)  // bar is decorative; the row already announces name + spend
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(name), \(spentLabel)")
    }
```

In `contentSection`, change the call site from `topAppsSection(apps:)` to `connectedAppsSection(apps:)`.

- [ ] **Step 4: Confirm no minutes survive anywhere**

```bash
grep -rn "minutes10\|minutes30\|formatAppTime\|loadWeeklyMinutesByTarget" StepsTrader --include="*.swift"
```

Expected: matches only in the payment/PayGate code that legitimately sells time windows — **no matches in any file under `StepsTrader/Views/Me`, and none in `MeView.swift`**. If a view still formats minutes per app, it has to go.

- [ ] **Step 5: Build, run and check against the ledger**

Build and run. Spend colors on one app through the PayGate, return to Me, and confirm that app appears with exactly the number of colors just spent (the same number the PayGate charged). Confirm no row anywhere shows a duration.

- [ ] **Step 6: Commit**

```bash
git add StepsTrader/Views/MeView.swift
git commit -m "feat: price connected apps in colors instead of bought minutes"
```

---

## Task 7: The calendar moves into Me

**Files:**
- Create: `StepsTrader/Views/Me/MeCalendarStrip.swift`
- Modify: `StepsTrader/Views/MeView.swift`
- Modify: `StepsTrader/Views/MeViewSupport.swift`
- Modify: `StepsTrader/Views/MainTabView.swift` (`Tab` enum, History page)
- Modify: `Steps4Tests/MainTabSelectionTests.swift`
- Delete: `StepsTrader/Views/HistoryView.swift`
- Modify: `Steps4.xcodeproj/project.pbxproj`

**Interfaces:**
- Consumes: `MeWeekStats.unlockedKeys(sortedKeys:isPro:freeCount:)` from Task 4, `DayCanvasViewerView(model:dayKey:)`, `PaywallView(model:store:source:)`, `HistoryThumbnailCache`, `CanvasStorageService`.
- Produces: `MeCalendarStrip(model:pastDays:onSelect:onLocked:)` and `DayHistoryTile` (moved verbatim out of `HistoryView.swift`, same members: `model`, `dayKey`, `snapshot`, `isLocked`, `onTap`).

- [ ] **Step 1: Write the failing tab test**

Extend `Steps4Tests/MainTabSelectionTests.swift`:

```swift
    func testTabBarHasExactlyThreeDestinations() {
        XCTAssertEqual(MainTabView.Tab.allCases.count, 3)
    }

    func testRetiredHistoryRawValueResolvesToCanvas() {
        XCTAssertEqual(MainTabView.Tab.resolve(storedRawValue: 3), .canvas)
    }
```

- [ ] **Step 2: Run it and verify it fails**

```bash
xcodebuild test -project Steps4.xcodeproj -scheme Steps4 -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:Steps4Tests/MainTabSelectionTests 2>&1 | tail -20
```

Expected: two failures — `allCases.count` is 4, and `resolve(3)` returns `.history`.

- [ ] **Step 3: Create the calendar strip**

Create `StepsTrader/Views/Me/MeCalendarStrip.swift`. `DayHistoryTile`, `HistoryDayKey` and the thumbnail loading move here from `HistoryView.swift` **verbatim** — the tile's rendering, blur, Pro badge and accessibility labels are already right and must not be re-derived:

```swift
import SwiftUI
import UIKit

// MARK: - Me calendar
//
// Past days as a horizontal strip, newest first, scrolling back into the past.
// Tapping a day opens `DayCanvasViewerView` — a pixel-faithful render of the
// persisted canvas at its frozen lastModified time.
//
// The Pro gate is dormant, not gone: `SubscriptionGate.allFeaturesUnlocked` is
// currently `true`, so `model.isPro` is unconditionally true and every day is
// open. The constant is a documented kill-switch, so the gating stays wired.
struct MeCalendarStrip: View {
    @ObservedObject var model: AppModel
    let pastDays: [String: PastDaySnapshot]
    let onSelect: (String) -> Void
    let onLocked: () -> Void

    @Environment(\.appTheme) private var theme

    #if DEBUG
    @State private var debugForceUnlock = false
    #endif

    private var effectiveIsPro: Bool {
        #if DEBUG
        return model.isPro || debugForceUnlock
        #else
        return model.isPro
        #endif
    }

    /// Newest first. Today is always present even before it has a snapshot.
    private var dayKeysSorted: [String] {
        var keys = Set(pastDays.keys)
        keys.insert(AppModel.dayKey(for: Date.now))
        return keys.sorted(by: >)
    }

    private var unlockedKeys: Set<String> {
        MeWeekStats.unlockedKeys(
            sortedKeys: dayKeysSorted,
            isPro: effectiveIsPro,
            freeCount: SubscriptionGate.freeHistoryDayCount
        )
    }

    var body: some View {
        let keys = dayKeysSorted
        let unlocked = unlockedKeys

        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(String(localized: "CALENDAR", comment: "MeView – calendar section header"))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(theme.textSecondary.opacity(0.55))
                    .tracking(0.6)
                Spacer(minLength: 8)
                Text(String(localized: "\(keys.count) days tracked", comment: "MeView – tracked count"))
                    .font(.caption)
                    .foregroundStyle(theme.textSecondary.opacity(0.5))
            }

            ScrollView(.horizontal) {
                LazyHStack(spacing: 10) {
                    ForEach(keys, id: \.self) { key in
                        DayHistoryTile(
                            model: model,
                            dayKey: key,
                            snapshot: pastDays[key],
                            isLocked: !unlocked.contains(key),
                            onTap: {
                                if unlocked.contains(key) { onSelect(key) } else { onLocked() }
                            }
                        )
                        .frame(width: 96, height: 128)
                    }
                }
            }
            .scrollIndicators(.hidden)

            #if DEBUG
            Toggle(isOn: $debugForceUnlock) {
                Text("🐛 Force unlock")
                    .font(.caption)
                    .foregroundStyle(theme.textSecondary)
            }
            .toggleStyle(.switch)
            .tint(AppColors.brandAccent)
            #endif
        }
    }
}
```

Then paste `DayHistoryTile` (lines 254-406 of `HistoryView.swift`) unchanged below it, and `private struct HistoryDayKey: Identifiable, Equatable { let id: String }` if `MeSheetsModifier` needs it (it does not — it keys off `MeDayKeyWrapper`, so drop `HistoryDayKey`).

Add the file to `project.pbxproj`.

- [ ] **Step 4: Host the strip in Me**

In `MeView.swift`, add paywall state:

```swift
    @State private var showPaywall = false
```

and put the strip at the bottom of `contentSection`:

```swift
            MeCalendarStrip(
                model: model,
                pastDays: pastDays,
                onSelect: { selectedDayKey = $0 },
                onLocked: { showPaywall = true }
            )
```

`pastDays` already holds every persisted day (`model.loadPastDaySnapshots()` at line 774 is unfiltered) plus whatever the server fetch merges in, so the strip needs no loader of its own.

In `MeViewSupport.swift`, add the paywall cover to `MeSheetsModifier` — bind it alongside the existing covers:

```swift
    @Binding var showPaywall: Bool
```

```swift
            .fullScreenCover(isPresented: $showPaywall) {
                PaywallView(model: model, store: model.subscriptionStore, source: .feature)
            }
```

and pass `showPaywall: $showPaywall` from `meSheets` in `MeView`.

- [ ] **Step 5: Remove the History tab**

In `MainTabView.swift`, delete `case history = 3` and its three `switch` arms, and delete the History page (lines 166-169). Then:

```bash
git rm StepsTrader/Views/HistoryView.swift
```

and remove its four `project.pbxproj` entries.

- [ ] **Step 6: Run the tests and verify they pass**

```bash
xcodebuild test -project Steps4.xcodeproj -scheme Steps4 -destination 'platform=iOS Simulator,name=iPhone 17' 2>&1 | tail -25
```

Expected: all tests pass, including the six in `MainTabSelectionTests`.

- [ ] **Step 7: Verify the tab bar and the calendar by hand**

Build and run. Confirm: the tab bar shows exactly Canvas, Feeds, Me. The calendar strip scrolls horizontally, newest day at the left, older days to the right. Tapping a past day opens its canvas as a poster; tapping today opens today's.

- [ ] **Step 8: Verify the stored-tab clamp with a real stored value**

Reasoning about this is not verification. `@SceneStorage` lives in UIKit's state-restoration archive, **not** in `UserDefaults` — `defaults write` cannot reach it. Reproduce the real upgrade instead.

Build the five-tab version and install it:

```bash
git stash --include-untracked && git checkout main
xcodebuild -project Steps4.xcodeproj -scheme Steps4 -destination 'platform=iOS Simulator,name=iPhone 17' -configuration Debug build
```

Launch it, switch to the **Settings** tab (raw value 4), then send the app to the background (`Device ▸ Home`) so the scene state is written to disk. Now, **without deleting the app from the simulator**:

```bash
git checkout feat/happenings && git stash pop
xcodebuild -project Steps4.xcodeproj -scheme Steps4 -destination 'platform=iOS Simulator,name=iPhone 17' -configuration Debug build
```

Install over the top and launch. **It must open the canvas, not a blank screen.** Repeat the whole loop with the **History** tab (raw value 3). Record both results in the task report.

- [ ] **Step 9: Verify the dormant Pro gate still fires**

Temporarily set `SubscriptionGate.allFeaturesUnlocked = false` (`StepsTrader/Stores/SubscriptionGate.swift:21`), rebuild, and open Me on an account with more than 7 days of history. Confirm days older than `freeHistoryDayCount` are blurred and carry the Pro badge, and that tapping one opens the paywall instead of the poster. Then flip the constant **back to `true`** and rebuild before committing.

```bash
grep -n "allFeaturesUnlocked" StepsTrader/Stores/SubscriptionGate.swift
```

Expected: `static let allFeaturesUnlocked = true`.

- [ ] **Step 10: Commit**

```bash
git add -A StepsTrader/Views Steps4Tests/MainTabSelectionTests.swift Steps4.xcodeproj/project.pbxproj
git commit -m "feat: fold history into Me as a horizontal calendar"
```

---

## Task 8: README and a pass over what is left

**Files:**
- Modify: `README.md:13-21`
- Modify: `StepsTrader/Views/MeViewSupport.swift`

**Interfaces:**
- Consumes: everything above. Produces: nothing new.

- [ ] **Step 1: Correct the tab table**

Replace the `## Tabs` table in `README.md` (lines 13-21) with:

```markdown
## Tabs

| Tab | View | Purpose |
|-----|------|---------|
| 0 (default) | Canvas | Generative canvas + the happenings palette |
| 1 | Feeds | App blocking groups — create tickets, set tariffs, configure time windows |
| 2 | Me | This week in three numbers, connected apps, the calendar of past days |

Settings is a button at the top right of Me, not a tab. **Notes from Kosta** — the
wall texts — is reached from inside Settings (`Info` → `Notes from Kosta`).
```

- [ ] **Step 2: Re-examine `MeViewSupport`**

`MeLifecycleModifier` and `MeSheetsModifier` survive, but `MeLifecycleModifier` still declares `onTopConsumersChange` and watches `model.ticketGroups` / `model.appStepsSpentByDay` — confirm both callbacks still have live call sites in `MeView` after Task 6, and delete any binding or closure that no longer does. Report what was removed.

- [ ] **Step 3: Confirm no stale references survive**

```bash
grep -rn "HistoryView\|MeAxisDetailView\|EnergySignatureView\|MeWeekSummary\|radar" StepsTrader --include="*.swift"
```

Expected: no matches other than incidental prose in unrelated comments. Doc comments in `SubscriptionGate.swift` and `AppModel+DailyEnergy.swift` that reference `HistoryView` by name must be updated to say `MeCalendarStrip`.

- [ ] **Step 4: Run the full suite and build clean**

```bash
xcodebuild test -project Steps4.xcodeproj -scheme Steps4 -destination 'platform=iOS Simulator,name=iPhone 17' 2>&1 | tail -25
```

Expected: all tests pass.

- [ ] **Step 5: Walk the acceptance criteria**

Confirm each, in the running app, and report any that could not be verified rather than assuming:

- [ ] Exactly three tab destinations
- [ ] A stored `selectedTab` of `3` or `4` opens the canvas (verified by setting it, Task 7 Step 8)
- [ ] `StepBalanceCard` on canvas and feeds, not on Me
- [ ] Settings opens from the button at the top right of Me
- [ ] Everything from the old Settings tab is still reachable, including `ManualsPage`
- [ ] The feature-tip deep link still lands on its settings page
- [ ] Me shows average sleep, average steps and the week's most frequent happenings
- [ ] The apps block shows exact color spend from `appStepsSpentByDay`
- [ ] No screen reports minutes spent per app
- [ ] The calendar scrolls horizontally into the past and opens a day's poster on tap
- [ ] With `allFeaturesUnlocked` temporarily `false`, days beyond `freeHistoryDayCount` blur behind the Pro badge (verified, Task 7 Step 9)
- [ ] `README.md` describes three tabs and no Notes tab

- [ ] **Step 6: Commit**

```bash
git add README.md StepsTrader/Views/MeViewSupport.swift StepsTrader/Stores/SubscriptionGate.swift StepsTrader/AppModel+DailyEnergy.swift
git commit -m "docs: describe three tabs and the calendar inside Me"
```

---

## Working agreement

- The two gates here — the `selectedTab` clamp and the history Pro limit — both fail silently and both affect existing users. They are tested deliberately in Task 7, Steps 8 and 9. Do not mark them done by reasoning.
- Reuse `DayHistoryTile` and `DayCanvasViewerView`. The poster rendering is pixel-faithful to persisted data and is not worth re-deriving.
- If removing the radar unpicks more of `MeViewSupport` than Task 3 assumes, say so in the task report rather than expanding scope quietly.
