# Feeds Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the Feeds paper-ticket stack with a flat list, an unlock sheet, and an in-app timer that reports usage minutes honestly.

**Architecture:** Pure decision logic is extracted into small `Sendable` value types under `StepsTrader/Models/Feeds/`, unit-tested in `Steps4Tests`. SwiftUI views stay thin and are verified on a physical device. One row per `TicketGroup` — a plain icon when the group holds one app, a cluster when it holds several. The timer reads per-minute tick values that the existing `DeviceActivityMonitor` extension already writes to the app group.

**Tech Stack:** SwiftUI, FamilyControls, DeviceActivity, ManagedSettings, XCTest.

## Revised 2026-08-10, after seeing the Figma reference

The first version of this plan followed `Feeds-Spec.md`: one vertical scroll of
capsule rows, a modal unlock sheet, and a separate full-screen timer. The Figma
reference (node `1284-146`) shows a different architecture, and the reference
governs. Tasks 3 and 4 were built to the old shape and have been reverted
(commit `a040ae5`); tasks 1, 2, 5 and 8 were unaffected and remain done.

What changed:

- The page is **not** a vertical list. It is a contextual surface over a
  horizontal dock of circular app tiles.
- There is **no modal unlock sheet** and **no separate timer screen**. Both are
  states of the one surface, so the old tasks 6 and 7 are gone.
- The surface's background is the user's canvas, blurred like frosted glass.
- Tile hue carries lock state; tile brightness carries selection.

Interaction, as specified by the author: the tab opens with nothing selected and
only the blurred canvas. Tapping a locked app fills the surface with three window
options plus a corner menu. Buying turns the surface into that app's timer.
Tapping another locked app switches the surface to its options — the first app's
window keeps running in the background and its tile stays amber.

## Global Constraints

- **No ActivityKit, no Live Activity, no `NSSupportsLiveActivities`.** Dropped from scope: the `Feeds-Spec.md` §6 spike established that `DeviceActivityMonitor` sees an empty `Activity.activities` and cannot update one. Do not reintroduce it.
- `AccessWindow` keeps `minutes10` / `minutes30` / `hour1`. Costs stay 4 / 10 / 20. No enum migration, no repricing.
- **One row per `TicketGroup`, always.** Never split a group into per-app rows.
- Night theme throughout. The reference image for the timer is light; it illustrates *how time is displayed*, not colour direction.
- `SubscriptionGate.freeMaxBlockingGroups = 2` must not tighten.
- The shield extensions (`ShieldAction`, `ShieldConfiguration`) are untouched.
- The window is **spent, not elapsed**. Never render a wall-clock countdown. Never interpolate between ticks.
- **No modal sheet and no separate timer screen.** Unlock options and the timer are states of the one surface.
- Tile **hue** encodes lock state (amber open / grey closed); tile **brightness** encodes selection. The two vary independently — never collapse them into one parameter.
- The surface's background is `GenerativeCanvasView` rendered with `fixedTime` (a static frame) and blurred. Do not animate it: under a blur the motion is invisible and only costs battery.
- Build: `xcodebuild -project Steps4.xcodeproj -scheme Steps4 -destination 'platform=iOS Simulator,name=iPhone 17' -configuration Debug build`
- Tests: `xcodebuild test -project Steps4.xcodeproj -scheme Steps4 -destination 'platform=iOS Simulator,name=iPhone 17'`
- FamilyControls and DeviceActivity do not work in the simulator. The list and sheet can be built there; the timer, the monitor and unlocking cannot be trusted until run on a physical device.

## File Structure

**Create:**

| File | Responsibility |
|------|----------------|
| `StepsTrader/Models/Feeds/FeedRowModel.swift` | Pure: group → row kind, icon source, lock state. No SwiftUI. |
| `StepsTrader/Models/Feeds/UnlockTimerModel.swift` | Pure: remaining/initial → arc fraction and digits, with the never-runs-backwards guard. No SwiftUI. |
| `StepsTrader/Models/Feeds/UsageBudgetMonitoringError.swift` | Typed monitoring failures, so `excessiveActivities` is distinguishable from everything else. |
| `StepsTrader/Views/Feeds/FeedIconView.swift` | Renders one app icon: bundled asset for registry apps, system `Label(token)` otherwise. |
| `StepsTrader/Views/Feeds/FeedTileView.swift` | One circular dock tile, plus the trailing `+` tile. |
| `StepsTrader/Views/Feeds/FeedsSurfaceView.swift` | The contextual surface: idle, window options, or timer, over the blurred canvas. |
| `Steps4Tests/FeedRowModelTests.swift` | Tests for `FeedRowModel`. |
| `Steps4Tests/UnlockTimerModelTests.swift` | Tests for `UnlockTimerModel`. |
| `Steps4Tests/UsageBudgetMonitoringErrorTests.swift` | Tests for the error mapping. |

**Modify:**

| File | Change |
|------|--------|
| `StepsTrader/Views/AppsPageSimplified.swift` | Ticket stack → surface over dock. Keep create / delete / paywall gating; drop the vertical reorder mode. |
| `StepsTrader/AppModel+PayGate.swift` | `startUsageBudgetMonitoring` returns a typed error; `excessiveActivities` gets its own user-facing message. |

**Delete, in the last task only:**

| File | Reason |
|------|--------|
| `StepsTrader/Views/Components/PaperTicketView.swift` | Replaced by `FeedRowView`. |

## Adding a file to the Xcode project — read before Task 1

**Every task that creates a file must do this, or the file will not compile into anything.** `StepsTrader/` and `Steps4Tests/` are plain `PBXGroup`s, not synchronized folders — only `ShieldConfiguration`, `ShieldAction`, `UnlockWidget` and `DeviceActivityMonitor` sync from disk. Writing a `.swift` file into `StepsTrader/Models/Feeds/` and stopping leaves it invisible to the compiler, and a test file that is not in the test target's Sources phase produces a green run that asserted nothing.

For each new file, add four entries to `Steps4.xcodeproj/project.pbxproj`. Pick a 24-character hex-ish id that `grep` shows is unused, and place each entry immediately after an existing sibling of the same kind so the surrounding formatting is preserved:

1. **`PBXBuildFile`**, in the `PBXBuildFile` section:
   `<BUILDID> /* Foo.swift in Sources */ = {isa = PBXBuildFile; fileRef = <FILEID> /* Foo.swift */; };`
2. **`PBXFileReference`**, in the `PBXFileReference` section:
   `<FILEID> /* Foo.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = Foo.swift; sourceTree = "<group>"; };`
3. **Group child** — add `<FILEID> /* Foo.swift */,` to the children list of the group whose `path` matches the file's directory. The `Feeds` subdirectories under `Models` and `Views` do not exist yet; create a new `PBXGroup` for each with `path = Feeds;` and add it as a child of the parent group.
4. **Sources phase** — add `<BUILDID> /* Foo.swift in Sources */,` to the right phase:

| Target | Sources phase id | Used by |
|--------|------------------|---------|
| Steps4 | `2089F0B02E71A18E00ABF5FA` | everything under `StepsTrader/` |
| Steps4Tests | `2089F0C02E71A18F00ABF5FA` | everything under `Steps4Tests/` |

Existing group ids you will need: `Models` is `2089F0E32E71AE3400ABF5FA`, `Views` is `209424BE2E8593DA00904A0A`.

**A test file goes only into the Steps4Tests phase, never the Steps4 phase.** Getting this backwards makes `@testable import Steps4` fail in confusing ways.

Verify after editing, before building: `plutil -lint Steps4.xcodeproj/project.pbxproj` must print `OK`. Then confirm the file actually compiled — a build that succeeds without your file is the failure this section exists to prevent:

```bash
grep -c "Foo.swift" Steps4.xcodeproj/project.pbxproj   # expect 4
```

**A note on testing SwiftUI here.** Tasks 1, 5 and 8 are pure logic and get real failing-test-first cycles. Tasks 2, 3, 4, 6 and 9 are views over FamilyControls types that cannot be instantiated off-device; they get a build gate plus an explicit on-device observation list. Do not write assertion-free tests to make those tasks look symmetrical — an empty test that passes is worse than an honest manual check.

---

### Task 1: Row model — one row per group, plain or cluster

**Files:**
- Create: `StepsTrader/Models/Feeds/FeedRowModel.swift`
- Test: `Steps4Tests/FeedRowModelTests.swift`

**Interfaces:**
- Consumes: `TargetResolver.imageName(for:)` and `.displayName(for:)` from `StepsTrader/TargetResolver.swift`.
- Produces: `FeedIconSource` (`.asset(String)`, `.systemLabel`), `FeedRowKind` (`.single(FeedIconSource)`, `.cluster(sources:[FeedIconSource], total:Int)`), `FeedRowModel.iconSource(forBundleId:) -> FeedIconSource`, `FeedRowModel.kind(templateApp:appTokenCount:) -> FeedRowKind`, `FeedRowModel.clusterDisplayLimit: Int`.

- [ ] **Step 1: Write the failing test**

```swift
import XCTest
@testable import Steps4

final class FeedRowModelTests: XCTestCase {

    // MARK: - Icon source

    func testRegistryAppUsesBundledAsset() {
        XCTAssertEqual(
            FeedRowModel.iconSource(forBundleId: "com.burbn.instagram"),
            .asset("instagram")
        )
    }

    func testUnknownAppFallsBackToSystemLabel() {
        XCTAssertEqual(
            FeedRowModel.iconSource(forBundleId: "com.example.unknown"),
            .systemLabel
        )
    }

    func testNilBundleIdFallsBackToSystemLabel() {
        XCTAssertEqual(FeedRowModel.iconSource(forBundleId: nil), .systemLabel)
    }

    // MARK: - Row kind

    func testSingleAppGroupRendersAsPlainIcon() {
        let kind = FeedRowModel.kind(templateApp: "com.burbn.instagram", appTokenCount: 1)
        XCTAssertEqual(kind, .single(.asset("instagram")))
    }

    func testTemplateGroupWithNoTokensStillRendersAsSingle() {
        // Template groups are validated to exactly one app, but the token count
        // can read zero before the picker's selection has been persisted.
        let kind = FeedRowModel.kind(templateApp: "com.burbn.instagram", appTokenCount: 0)
        XCTAssertEqual(kind, .single(.asset("instagram")))
    }

    func testCustomGroupWithTwoAppsRendersAsCluster() {
        let kind = FeedRowModel.kind(templateApp: nil, appTokenCount: 2)
        XCTAssertEqual(kind, .cluster(sources: [.systemLabel, .systemLabel], total: 2))
    }

    func testClusterCapsRenderedIconsButKeepsTrueTotal() {
        let kind = FeedRowModel.kind(templateApp: nil, appTokenCount: 7)
        XCTAssertEqual(
            kind,
            .cluster(sources: Array(repeating: .systemLabel, count: FeedRowModel.clusterDisplayLimit), total: 7)
        )
    }

    func testCustomGroupWithOneAppRendersAsPlainIcon() {
        XCTAssertEqual(FeedRowModel.kind(templateApp: nil, appTokenCount: 1), .single(.systemLabel))
    }
}
```

- [ ] **Step 2: Wire the test file into the project, then run it to verify it fails**

Add `Steps4Tests/FeedRowModelTests.swift` to the project per "Adding a file to the Xcode project" above — `PBXBuildFile`, `PBXFileReference`, group child, and the **Steps4Tests** Sources phase `2089F0C02E71A18F00ABF5FA`. Then:

Run: `xcodebuild test -project Steps4.xcodeproj -scheme Steps4 -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:Steps4Tests/FeedRowModelTests`

Expected: FAIL — `cannot find 'FeedRowModel' in scope`. A run that reports "no tests" instead means the file is not in the test target; fix the wiring before continuing, because a green run at Step 4 would then be meaningless.

- [ ] **Step 3: Write the minimal implementation**

Create `StepsTrader/Models/Feeds/FeedRowModel.swift` and wire it into the **Steps4** Sources phase `2089F0B02E71A18E00ABF5FA`, creating the `Feeds` `PBXGroup` under `Models` (`2089F0E32E71AE3400ABF5FA`).

```swift
import Foundation

/// Which artwork a row can draw for one app.
///
/// `FamilyActivitySelection` yields opaque `ApplicationToken`s and Apple provides no
/// API to read a name or icon from one. Registry apps carry a bundled asset we can
/// style freely; everything else must fall back to the system-drawn `Label(token)`,
/// which cannot be recoloured, masked, or reshaped. The list looks visually mixed as
/// a result, and that is accepted — see `Feeds-Spec.md`.
enum FeedIconSource: Equatable, Sendable {
    case asset(String)
    case systemLabel
}

/// How one `TicketGroup` renders as a row. Always one row per group.
enum FeedRowKind: Equatable, Sendable {
    case single(FeedIconSource)
    case cluster(sources: [FeedIconSource], total: Int)
}

enum FeedRowModel {

    /// Overlapping icons beyond this add noise without adding information.
    /// The true count is carried separately so the row can still say "+4".
    static let clusterDisplayLimit = 3

    static func iconSource(forBundleId bundleId: String?) -> FeedIconSource {
        guard let bundleId, let imageName = TargetResolver.imageName(for: bundleId) else {
            return .systemLabel
        }
        return .asset(imageName)
    }

    static func kind(templateApp: String?, appTokenCount: Int) -> FeedRowKind {
        // A template group is validated to exactly one app at creation time
        // (`TargetResolver.singleAppPresetValidationMessage`), so its template
        // bundle id is authoritative regardless of what the token count reads.
        if let templateApp {
            return .single(iconSource(forBundleId: templateApp))
        }
        if appTokenCount <= 1 {
            return .single(.systemLabel)
        }
        let shown = min(appTokenCount, clusterDisplayLimit)
        return .cluster(
            sources: Array(repeating: .systemLabel, count: shown),
            total: appTokenCount
        )
    }
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `xcodebuild test -project Steps4.xcodeproj -scheme Steps4 -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:Steps4Tests/FeedRowModelTests`

Expected: PASS, 7 tests.

- [ ] **Step 5: Commit**

```bash
git add StepsTrader/Models/Feeds/FeedRowModel.swift Steps4Tests/FeedRowModelTests.swift Steps4.xcodeproj/project.pbxproj
git commit -m "feat: add the Feeds row model — one row per group, plain or cluster"
```

---

### Task 2: Feed icon view

**Files:**
- Create: `StepsTrader/Views/Feeds/FeedIconView.swift`

**Interfaces:**
- Consumes: `FeedIconSource` from Task 1.
- Produces: `FeedIconView(source:token:size:)`, where `token` is an optional `ApplicationToken` used only when `source == .systemLabel`.

Note: `PaperTicketView` never used `Label(token)` — it fell back to `Image(systemName: "app.fill")`. Introducing it here is new work, and it is the only way a non-registry app gets a real icon.

- [ ] **Step 1: Write the view**

```swift
import SwiftUI
#if canImport(FamilyControls)
import FamilyControls
#endif

/// One app icon. Registry apps get our bundled asset with full styling control;
/// everything else gets the system-drawn `Label(token)`, which the system renders
/// in its own process and which cannot be recoloured, masked, or reshaped.
struct FeedIconView: View {
    let source: FeedIconSource
    let size: CGFloat
    #if canImport(FamilyControls)
    var token: ApplicationToken? = nil
    #endif

    var body: some View {
        switch source {
        case .asset(let imageName):
            assetIcon(imageName)
        case .systemLabel:
            systemIcon
        }
    }

    private func assetIcon(_ imageName: String) -> some View {
        Image(imageName)
            .resizable()
            .scaledToFill()
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: size * 0.24, style: .continuous))
    }

    @ViewBuilder
    private var systemIcon: some View {
        #if canImport(FamilyControls)
        if let token {
            // Drawn out-of-process. Do not attempt to style it — masks and tints
            // are silently ignored, and clipping it produces a blank square.
            Label(token)
                .labelStyle(.iconOnly)
                .frame(width: size, height: size)
        } else {
            placeholder
        }
        #else
        placeholder
        #endif
    }

    private var placeholder: some View {
        RoundedRectangle(cornerRadius: size * 0.24, style: .continuous)
            .fill(Color.white.opacity(0.12))
            .frame(width: size, height: size)
            .overlay {
                Image(systemName: "app.dashed")
                    .font(.system(size: size * 0.42, weight: .light))
                    .foregroundStyle(Color.white.opacity(0.5))
            }
    }
}
```

- [ ] **Step 2: Verify it compiles**

Run: `xcodebuild -project Steps4.xcodeproj -scheme Steps4 -destination 'platform=iOS Simulator,name=iPhone 17' -configuration Debug build`

Expected: BUILD SUCCEEDED.

- [ ] **Step 3: Commit**

```bash
git add StepsTrader/Views/Feeds/FeedIconView.swift
git commit -m "feat: add FeedIconView — bundled asset or system Label"
```

---

### Task 3: The app tile

**Files:**
- Create: `StepsTrader/Views/Feeds/FeedTileView.swift`

**Interfaces:**
- Consumes: `FeedIconSource` and `FeedRowModel.kind(templateApp:appTokenCount:)` from Task 1, `FeedIconView` from Task 2.
- Produces: `FeedTileView(model:group:isSelected:onTap:)` and `FeedAddTileView(onTap:)`.

A circular tile, 83pt across, in a dock of four. Measured from the Figma reference (node `1284-146`, 590×1280 over a 393×852 screen, so divide by 1.5): tile 125→83pt, spacing 146→97pt, first tile x 13→9pt.

**Two independent visual channels — do not collapse them.**

| | Locked | Unlocked |
|---|---|---|
| **Not selected** | grey glow, dimmed | amber glow, dimmed |
| **Selected** | grey glow, full | amber glow, full |

Hue carries the window's state; brightness carries selection. They are orthogonal because both vary independently: a window keeps draining in the background while a different app is selected, so an unlocked-but-unselected tile must stay amber and a selected-but-locked tile must stay grey.

- [ ] **Step 1: Write the view**

```swift
import SwiftUI
#if canImport(FamilyControls)
import FamilyControls
#endif

/// One app in the Feeds dock. Hue says whether a window is open; brightness says
/// whether this is the app the surface is currently showing. The two are
/// independent — a window keeps draining while another app is selected.
struct FeedTileView: View {
    @ObservedObject var model: AppModel
    let group: TicketGroup
    let isSelected: Bool
    let onTap: () -> Void

    @State private var remaining: Int = 0

    static let diameter: CGFloat = 83

    private var isUnlocked: Bool { remaining > 0 }

    private var glowColor: Color {
        isUnlocked ? AppColors.brandAccent : Color.white.opacity(0.55)
    }

    /// Selection is brightness. Unselected tiles stay legible rather than vanishing.
    private var glowOpacity: Double { isSelected ? 1.0 : 0.45 }

    private var kind: FeedRowKind {
        FeedRowModel.kind(
            templateApp: group.templateApp,
            appTokenCount: group.selection.applicationTokens.count
        )
    }

    var body: some View {
        Button(action: onTap) {
            ZStack {
                // The glow is a soft radial wash behind the icon, not a ring on it.
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [glowColor.opacity(0.85), glowColor.opacity(0)],
                            center: .center,
                            startRadius: 0,
                            endRadius: Self.diameter * 0.62
                        )
                    )
                    .frame(width: Self.diameter, height: Self.diameter)
                    .opacity(glowOpacity)

                icon
            }
            .frame(width: Self.diameter, height: Self.diameter)
            .contentShape(Circle())
            .animation(.easeOut(duration: 0.22), value: isSelected)
            .animation(.easeOut(duration: 0.22), value: isUnlocked)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
        .onAppear(perform: refresh)
        .task {
            // The honest signal steps once a minute. Poll a little faster so the tile
            // is never badly stale; never interpolate between ticks.
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(15))
                refresh()
            }
        }
    }

    @ViewBuilder
    private var icon: some View {
        switch kind {
        case .single(let source):
            tileIcon(source: source, size: 42, index: 0)
        case .cluster(let sources, _):
            HStack(spacing: -10) {
                ForEach(Array(sources.enumerated()), id: \.offset) { index, source in
                    tileIcon(source: source, size: 30, index: index)
                        .zIndex(Double(sources.count - index))
                }
            }
        }
    }

    /// `FeedIconView`'s `token:` parameter only exists where FamilyControls does, so
    /// the call itself must be conditional, not just the value passed in.
    @ViewBuilder
    private func tileIcon(source: FeedIconSource, size: CGFloat, index: Int) -> some View {
        #if canImport(FamilyControls)
        FeedIconView(source: source, size: size, token: token(at: index))
        #else
        FeedIconView(source: source, size: size)
        #endif
    }

    #if canImport(FamilyControls)
    private func token(at index: Int) -> ApplicationToken? {
        let tokens = Array(group.selection.applicationTokens)
        guard index < tokens.count else { return nil }
        return tokens[index]
    }
    #endif

    private var accessibilityLabel: String {
        let name = group.templateApp.map { TargetResolver.displayName(for: $0) } ?? group.name
        return isUnlocked
            ? String(localized: "\(name), unlocked, \(remaining) minutes left", comment: "Feeds tile – VoiceOver, window open")
            : String(localized: "\(name), locked", comment: "Feeds tile – VoiceOver, window closed")
    }

    private func refresh() {
        remaining = model.remainingUsageBudget(for: group.id)
    }
}

/// The trailing `+` tile. Same footprint as an app tile so the dock stays even.
struct FeedAddTileView: View {
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            ZStack {
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [Color.white.opacity(0.35), Color.white.opacity(0)],
                            center: .center,
                            startRadius: 0,
                            endRadius: FeedTileView.diameter * 0.62
                        )
                    )
                Image(systemName: "plus")
                    .font(.system(size: 28, weight: .light))
                    .foregroundStyle(AppColors.Night.textPrimary)
            }
            .frame(width: FeedTileView.diameter, height: FeedTileView.diameter)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(String(localized: "Add a feed", comment: "Feeds dock – add button VoiceOver label"))
    }
}
```

- [ ] **Step 2: Wire it into the project**

Follow "Adding a file to the Xcode project". The `Feeds` group under `Views` already exists from Task 2; add the file to it and to the **Steps4** Sources phase `2089F0B02E71A18E00ABF5FA`.

- [ ] **Step 3: Verify it compiles**

Run: `xcodebuild -project Steps4.xcodeproj -scheme Steps4 -destination 'platform=iOS Simulator,name=iPhone 17' -configuration Debug build`

Expected: BUILD SUCCEEDED. No unit tests — the tile renders FamilyControls types that cannot be instantiated off-device.

- [ ] **Step 4: Commit**

```bash
git add StepsTrader/Views/Feeds/FeedTileView.swift Steps4.xcodeproj/project.pbxproj
git commit -m "feat: add the Feeds app tile — hue for lock state, brightness for selection"
```

---

### Task 4: The contextual surface

**Files:**
- Create: `StepsTrader/Views/Feeds/FeedsSurfaceView.swift`

**Interfaces:**
- Consumes: `UnlockTimerModel` from Task 5 of the original plan (already on the branch), `GenerativeCanvasView`, `AccessWindow`, `TicketGroup.cost(for:)`, `AppModel.handlePayGatePaymentForGroup(groupId:window:costOverride:)`, `AppModel.remainingUsageBudget(for:)`, `AppModel.payGateError`.
- Produces: `FeedsSurfaceView(model:selectedGroup:onSettings:onDelete:)`.

**This replaces both the unlock sheet and the timer screen from the original plan.** There is no `.sheet` and no `fullScreenCover`. The surface is one region of the page, 387×443pt at y≈193, that shows one of three states:

1. **Nothing selected** — the blurred canvas alone. This is how the tab opens.
2. **A locked group selected** — three window options (10 / 30 / 60 at 4 / 10 / 20), plus a menu button in the corner offering Settings and Delete.
3. **An unlocked group selected** — the timer: depleting indicator and large monospaced digits.

Selecting a different locked group while a window runs switches the surface back to state 2 for the new group. The running window is unaffected — it lives in `DeviceActivity`, not in this view.

**The background is the canvas, blurred.** Reuse `GenerativeCanvasView` rather than inventing a second renderer. Pass `fixedTime` so it renders one static frame: the live view animates continuously, and under a blur nobody can see the motion, so animating it only costs battery. Set `showLabelsOnCanvas: false` — labels under a blur are noise. Then `.blur(radius: 18)` and a dimming scrim so the digits stay legible.

The `Feeds-Spec.md` rules still bind the timer: the arc steps on tick boundaries, never interpolates, and never runs backwards. `UnlockTimerModel` already enforces all three — use it and do not re-derive remaining time.

- [ ] **Step 1: Write the surface**

The three states go in one file behind a private enum, so the transitions are visible in one place:

```swift
private enum SurfaceState {
    case idle
    case offeringWindows(TicketGroup)
    case running(TicketGroup)
}
```

Derive it from `selectedGroup` and `model.remainingUsageBudget(for:)` rather than storing it — a stored copy drifts from the budget the monitor extension is writing.

Layout, from the reference: the surface is 387×443pt with a corner radius of about 28pt. "My Feeds" sits **over** the surface at its bottom-left, inset 13pt, baseline about 601pt in screen coordinates. The corner menu button goes top-trailing, inset 16pt, and uses `Menu` with two items — Settings and Delete — matching what the ticket context menu offers today.

Window options in state 2: three full-width rows inside the surface, each showing `AccessWindow.displayName` and its cost, dimmed and disabled when `model.totalStepsBalance` is short. Reuse the payment call unchanged; on success the surface moves to state 3 by itself because the budget changed.

Digits in state 3: `UnlockTimerModel.State.digits`, `.system(size: 44, weight: .medium, design: .monospaced)`, centred. The depleting indicator is drawn over the blurred canvas from `State.fraction`.

- [ ] **Step 2: Wire it into the project and build**

Same wiring steps. Expected: BUILD SUCCEEDED.

- [ ] **Step 3: Commit**

```bash
git add StepsTrader/Views/Feeds/FeedsSurfaceView.swift Steps4.xcodeproj/project.pbxproj
git commit -m "feat: add the Feeds contextual surface — idle, window options, timer"
```

---

### Task 5: Timer model — stepping, never backwards  ✅ done (commit c7edf15)

**Files:**
- Create: `StepsTrader/Models/Feeds/UnlockTimerModel.swift`
- Test: `Steps4Tests/UnlockTimerModelTests.swift`

**Interfaces:**
- Consumes: nothing.
- Produces: `UnlockTimerModel(initialMinutes:)`, `mutating func observe(remainingMinutes:) -> UnlockTimerModel.State`, and `State` carrying `remainingMinutes: Int`, `fraction: Double`, `digits: String`.

This is where the two hardest rules in `Feeds-Spec.md` live, so they are enforced by tests rather than by care:

1. **The arc never runs backwards.** Ticks can arrive late or be replayed, and `remainingUsageBudget` applies a wall-clock floor that can disagree with the last tick. A rising `remaining` must be clamped to the last observed value.
2. **The arc steps, it does not flow.** `fraction` is derived only from whole observed minutes. There is no time-based interpolation anywhere in this type — it has no clock.

Extending a window is the one legitimate increase, and it goes through `reset(initialMinutes:)`, not `observe`.

- [ ] **Step 1: Write the failing test**

```swift
import XCTest
@testable import Steps4

final class UnlockTimerModelTests: XCTestCase {

    func testStartsFull() {
        var model = UnlockTimerModel(initialMinutes: 10)
        let state = model.observe(remainingMinutes: 10)
        XCTAssertEqual(state.remainingMinutes, 10)
        XCTAssertEqual(state.fraction, 1.0, accuracy: 0.0001)
    }

    func testDepletesInWholeMinuteSteps() {
        var model = UnlockTimerModel(initialMinutes: 10)
        _ = model.observe(remainingMinutes: 10)
        XCTAssertEqual(model.observe(remainingMinutes: 9).fraction, 0.9, accuracy: 0.0001)
        XCTAssertEqual(model.observe(remainingMinutes: 5).fraction, 0.5, accuracy: 0.0001)
    }

    func testNeverRunsBackwards() {
        var model = UnlockTimerModel(initialMinutes: 10)
        _ = model.observe(remainingMinutes: 4)
        // A late or replayed tick reports more time left than we last showed.
        let state = model.observe(remainingMinutes: 7)
        XCTAssertEqual(state.remainingMinutes, 4, "a rising reading must be clamped to the last shown value")
        XCTAssertEqual(state.fraction, 0.4, accuracy: 0.0001)
    }

    func testRepeatedIdenticalReadingsDoNotDrift() {
        var model = UnlockTimerModel(initialMinutes: 30)
        let first = model.observe(remainingMinutes: 12)
        let second = model.observe(remainingMinutes: 12)
        XCTAssertEqual(first.fraction, second.fraction)
        XCTAssertEqual(first.digits, second.digits)
    }

    func testClampsAtZeroAndDoesNotGoNegative() {
        var model = UnlockTimerModel(initialMinutes: 10)
        let state = model.observe(remainingMinutes: -3)
        XCTAssertEqual(state.remainingMinutes, 0)
        XCTAssertEqual(state.fraction, 0.0, accuracy: 0.0001)
    }

    func testReadingAboveInitialIsClampedToInitial() {
        var model = UnlockTimerModel(initialMinutes: 10)
        let state = model.observe(remainingMinutes: 99)
        XCTAssertEqual(state.remainingMinutes, 10)
        XCTAssertEqual(state.fraction, 1.0, accuracy: 0.0001)
    }

    func testExtendingTheWindowResetsAndIsAllowedToRise() {
        var model = UnlockTimerModel(initialMinutes: 10)
        _ = model.observe(remainingMinutes: 3)
        model.reset(initialMinutes: 33)
        let state = model.observe(remainingMinutes: 33)
        XCTAssertEqual(state.remainingMinutes, 33)
        XCTAssertEqual(state.fraction, 1.0, accuracy: 0.0001)
    }

    func testZeroInitialDoesNotDivideByZero() {
        var model = UnlockTimerModel(initialMinutes: 0)
        let state = model.observe(remainingMinutes: 0)
        XCTAssertEqual(state.fraction, 0.0, accuracy: 0.0001)
    }

    // MARK: - Digits

    func testDigitsUseZeroPaddedMinutesAndSeconds() {
        var model = UnlockTimerModel(initialMinutes: 60)
        XCTAssertEqual(model.observe(remainingMinutes: 60).digits, "60:00")
        XCTAssertEqual(model.observe(remainingMinutes: 9).digits, "09:00")
        XCTAssertEqual(model.observe(remainingMinutes: 0).digits, "00:00")
    }
}
```

The seconds field is always `00` on purpose: the underlying signal has one-minute resolution, and showing a running seconds counter would claim precision the data does not have.

- [ ] **Step 2: Run the test to verify it fails**

Run: `xcodebuild test -project Steps4.xcodeproj -scheme Steps4 -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:Steps4Tests/UnlockTimerModelTests`

Expected: FAIL — `cannot find 'UnlockTimerModel' in scope`.

- [ ] **Step 3: Write the minimal implementation**

```swift
import Foundation

/// Turns observed usage-budget readings into what the timer draws.
///
/// The window is spent, not elapsed: the honest signal is the per-minute
/// `usageBudgetTick_<groupId>_<m>` event the monitor extension writes to the app
/// group. This type therefore has no clock and performs no interpolation — the arc
/// steps a minute at a time. A stepping arc that is correct beats a flowing arc
/// that is not.
struct UnlockTimerModel: Sendable {

    struct State: Equatable, Sendable {
        let remainingMinutes: Int
        let fraction: Double
        let digits: String
    }

    private(set) var initialMinutes: Int
    private var lastShownMinutes: Int?

    init(initialMinutes: Int) {
        self.initialMinutes = max(0, initialMinutes)
    }

    /// Call when the user buys more time. This is the only path along which the
    /// displayed remaining time is allowed to increase.
    mutating func reset(initialMinutes: Int) {
        self.initialMinutes = max(0, initialMinutes)
        self.lastShownMinutes = nil
    }

    mutating func observe(remainingMinutes: Int) -> State {
        var value = min(max(0, remainingMinutes), initialMinutes)

        // Ticks can arrive late, and the wall-clock floor in
        // `AppModel.remainingUsageBudget(for:)` can disagree with the last tick.
        // Either way the arc must not jump forward and then fall back.
        if let last = lastShownMinutes {
            value = min(value, last)
        }
        lastShownMinutes = value

        let fraction = initialMinutes > 0 ? Double(value) / Double(initialMinutes) : 0
        return State(
            remainingMinutes: value,
            fraction: fraction,
            digits: String(format: "%02d:00", value)
        )
    }
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `xcodebuild test -project Steps4.xcodeproj -scheme Steps4 -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:Steps4Tests/UnlockTimerModelTests`

Expected: PASS, 9 tests.

- [ ] **Step 5: Commit**

```bash
git add StepsTrader/Models/Feeds/UnlockTimerModel.swift Steps4Tests/UnlockTimerModelTests.swift
git commit -m "feat: add UnlockTimerModel — stepping arc that never runs backwards"
```

---

### Task 6: Assemble the Feeds page

**Files:**
- Modify: `StepsTrader/Views/AppsPageSimplified.swift`

**Interfaces:**
- Consumes: `FeedTileView`, `FeedAddTileView`, `FeedsSurfaceView`.
- Produces: nothing new outside the file.

Replaces the ticket stack with the surface plus the dock, and adds the selection state the surface reads.

```swift
@State private var selectedFeedGroupId: String? = nil
```

**Do not reuse `selectedGroupId`** — it already holds which group the `FamilyActivityPicker` is editing, paired with `showPicker` at lines 172-196. Reusing it breaks group editing.

Layout order top to bottom: the existing energy card inset, then `FeedsSurfaceView`, then the dock, then the existing tab bar inset. The dock is a horizontal row of `FeedTileView` for each group followed by one `FeedAddTileView`; when the tiles overflow the width, it scrolls horizontally with the add tile last.

Keep: `attemptCreateGroup()` and its `SubscriptionGate` paywall, the empty state, the delete confirmation, and the `#if DEBUG` `FirstFeedAnchor` anchor.

Remove: the `isReordering` mode and its up/down chevrons. They ordered a vertical list that no longer exists; reordering a horizontal dock is a separate design question and is out of scope. Remove `moveTicket(_:up:)` only if nothing else calls it — check first.

- [ ] **Step 1: Make the change, then build and run the full suite**

Build, then `xcodebuild test …` — expect 252 tests, 1 skipped, 0 failures.

- [ ] **Step 2: Verify on a physical device**

FamilyControls does not authorise in the simulator, so the tiles cannot be judged there. On device:
- the tab opens with nothing selected and only the blurred canvas showing
- tapping a locked tile brings up three windows at 4 / 10 / 20; the corner menu offers Settings and Delete
- buying turns the surface into the timer for that app
- tapping a different locked tile switches the surface to its window options while the first window keeps running — its tile stays amber
- **leaving the phone idle does not move the timer**
- the arc steps and never runs backwards

- [ ] **Step 3: Commit**

```bash
git add StepsTrader/Views/AppsPageSimplified.swift
git commit -m "feat: assemble the Feeds page — surface over the dock"
```

---

### Task 8: Surface the DeviceActivity cap

**Files:**
- Create: `StepsTrader/Models/Feeds/UsageBudgetMonitoringError.swift`
- Modify: `StepsTrader/AppModel+PayGate.swift:101-119` (the failure branch) and `:142-228` (`startUsageBudgetMonitoring`)
- Test: `Steps4Tests/UsageBudgetMonitoringErrorTests.swift`

**Interfaces:**
- Consumes: nothing.
- Produces: `UsageBudgetMonitoringError` with cases `.excessiveActivities` and `.other(String)`, `static func classify(_ error: Error) -> UsageBudgetMonitoringError`, and `var userFacingMessage: String`.

Today the throw is caught, the monitor is stopped, and the user is told nothing specific. Silent failure here means an app the user paid to block stays open.

- [ ] **Step 1: Write the failing test**

```swift
import XCTest
@testable import Steps4
#if canImport(DeviceActivity)
import DeviceActivity
#endif

final class UsageBudgetMonitoringErrorTests: XCTestCase {

    #if canImport(DeviceActivity)
    func testExcessiveActivitiesIsClassifiedDistinctly() {
        let classified = UsageBudgetMonitoringError.classify(
            DeviceActivityCenter.MonitoringError.excessiveActivities
        )
        XCTAssertEqual(classified, .excessiveActivities)
    }
    #endif

    func testUnknownErrorFallsBackToOther() {
        struct Boom: Error, LocalizedError {
            var errorDescription: String? { "boom" }
        }
        XCTAssertEqual(UsageBudgetMonitoringError.classify(Boom()), .other("boom"))
    }

    func testCapMessageNamesTheCauseAndTheRemedy() {
        let message = UsageBudgetMonitoringError.excessiveActivities.userFacingMessage.lowercased()
        XCTAssertTrue(message.contains("too many"), "the message must name the cause")
        XCTAssertTrue(message.contains("close"), "the message must offer a remedy")
    }

    func testOtherMessageMentionsTheRefund() {
        let message = UsageBudgetMonitoringError.other("boom").userFacingMessage
        XCTAssertTrue(message.lowercased().contains("refunded"))
    }
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `xcodebuild test -project Steps4.xcodeproj -scheme Steps4 -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:Steps4Tests/UsageBudgetMonitoringErrorTests`

Expected: FAIL — `cannot find 'UsageBudgetMonitoringError' in scope`.

- [ ] **Step 3: Write the minimal implementation**

```swift
import Foundation
#if canImport(DeviceActivity)
import DeviceActivity
#endif

/// Why a usage-budget monitor refused to start.
///
/// `DeviceActivity` caps an app and its extensions at twenty concurrently monitored
/// activities. The ceiling counts open windows, not rows in the list, so reaching it
/// is unlikely — but it must fail legibly rather than leaving an app the user paid
/// to block sitting open.
enum UsageBudgetMonitoringError: Equatable, Sendable {
    case excessiveActivities
    case other(String)

    static func classify(_ error: Error) -> UsageBudgetMonitoringError {
        #if canImport(DeviceActivity)
        if let monitoring = error as? DeviceActivityCenter.MonitoringError,
           case .excessiveActivities = monitoring {
            return .excessiveActivities
        }
        #endif
        return .other(error.localizedDescription)
    }

    var userFacingMessage: String {
        switch self {
        case .excessiveActivities:
            String(
                localized: "Too many windows are open at once. Close one and try again — your colors were refunded.",
                comment: "Unlock failure – DeviceActivity activity cap reached"
            )
        case .other:
            String(
                localized: "Couldn't start the timer. Your colors were refunded — please try again in a moment.",
                comment: "Unlock failure – generic monitoring failure, after refund"
            )
        }
    }
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `xcodebuild test -project Steps4.xcodeproj -scheme Steps4 -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:Steps4Tests/UsageBudgetMonitoringErrorTests`

Expected: PASS, 4 tests.

- [ ] **Step 5: Thread the error through the PayGate**

In `StepsTrader/AppModel+PayGate.swift`, change `startUsageBudgetMonitoring` to return `UsageBudgetMonitoringError?` (nil on success) instead of `Bool`. In both `catch` blocks, replace the bare log with classification:

```swift
            } catch {
                let classified = UsageBudgetMonitoringError.classify(error)
                let msg = "[\(iso.string(from: Date.now))] FAIL usageBudget_\(groupId) — \(error.localizedDescription) sched=[\(schedDesc)]"
                logDefaults.set(msg, forKey: SharedKeys.lastStartMonitoringLog)
                return classified
            }
```

Return `nil` where it currently returns `true`. Then in `handlePayGatePaymentForGroup`, replace the failure branch:

```swift
        if let failure = startUsageBudgetMonitoring(groupId: groupId, minutes: totalMinutes) {
            AppLogger.shield.error("❌ Monitoring failed after payment — refunding \(cost) colors")
            refund(cost: cost)
            defaults.removeObject(forKey: budgetKey)
            defaults.removeObject(forKey: initialKey)
            defaults.removeObject(forKey: startedKey)
            defaults.removeObject(forKey: SharedKeys.usageBudgetExpiryKey(groupId))
            payGateError = failure.userFacingMessage
            dismissPayGate(reason: .programmatic)
            return
        }
```

Note the `#if !canImport(DeviceActivity)` early-return at the top of the function currently returns `true`; it must now return `nil`.

- [ ] **Step 6: Verify the whole suite still passes**

Run: `xcodebuild test -project Steps4.xcodeproj -scheme Steps4 -destination 'platform=iOS Simulator,name=iPhone 17'`

Expected: PASS. `PaymentTests` exercises the refund path and must be unaffected.

- [ ] **Step 7: Commit**

```bash
git add StepsTrader/Models/Feeds/UsageBudgetMonitoringError.swift Steps4Tests/UsageBudgetMonitoringErrorTests.swift StepsTrader/AppModel+PayGate.swift
git commit -m "feat: surface the DeviceActivity activity cap to the user"
```

---

### Task 9: Retire the paper ticket

**Files:**
- Delete: `StepsTrader/Views/Components/PaperTicketView.swift`
- Modify: `Steps4.xcodeproj/project.pbxproj` — remove its `PBXBuildFile`, `PBXFileReference`, group child, and Sources entry

Do this last, so every earlier task can be reverted independently without losing the old row.

- [ ] **Step 1: Confirm nothing still references it**

Run: `grep -rn "PaperTicketView\|RayCapsuleSurface" StepsTrader UnlockWidget Steps4Tests`

Expected: matches only inside `PaperTicketView.swift` itself. If `RayCapsuleSurface` or any other helper defined in that file is used elsewhere, move it to its own file under `StepsTrader/Views/Components/` first and commit that move separately.

- [ ] **Step 2: Remove the file and its project entries**

```bash
git rm StepsTrader/Views/Components/PaperTicketView.swift
```

Then remove the four `PaperTicketView.swift` lines from `Steps4.xcodeproj/project.pbxproj` — locate them with `grep -n "PaperTicketView" Steps4.xcodeproj/project.pbxproj`.

- [ ] **Step 3: Verify the project still parses and builds**

Run: `plutil -lint Steps4.xcodeproj/project.pbxproj && xcodebuild -project Steps4.xcodeproj -scheme Steps4 -destination 'platform=iOS Simulator,name=iPhone 17' -configuration Debug build`

Expected: `OK` then BUILD SUCCEEDED.

- [ ] **Step 4: Run the whole suite**

Run: `xcodebuild test -project Steps4.xcodeproj -scheme Steps4 -destination 'platform=iOS Simulator,name=iPhone 17'`

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "refactor: remove PaperTicketView, replaced by the flat Feeds list"
```

---

## Acceptance criteria

Mapped from `Feeds-Spec.md`, `Feeds-Brief.md` §8 and the Figma reference, minus
everything the spike and the revision removed.

- [x] A registry app shows its bundled asset; a non-registry app shows a system `Label` — Tasks 1, 2
- [x] The arc steps on tick boundaries and never runs backwards — Task 5 tests, Task 6 device check
- [x] Exceeding the DeviceActivity cap surfaces a user-facing error — Task 8
- [ ] Feeds is a surface over a horizontal dock; no ticket stack and no vertical list remains — Tasks 3, 6, 9
- [ ] One tile per `TicketGroup`; a multi-app group shows a cluster inside its tile — Tasks 1, 3
- [ ] Tile hue tracks lock state and tile brightness tracks selection, independently — Task 3
- [ ] The tab opens with nothing selected and only the blurred canvas showing — Tasks 4, 6
- [ ] Tapping a locked tile fills the surface with 10 / 30 / 60 at 4 / 10 / 20 for that group — Tasks 4, 6
- [ ] The surface's corner menu offers Settings and Delete for the selected group — Task 4
- [ ] Buying a window turns the surface into that group's timer — Tasks 4, 6
- [ ] Selecting another locked group switches the surface to its options while the running window continues and its tile stays amber — Task 6
- [ ] **The timer does not move while the covered apps are unused** — Task 6, device check

**Explicitly not in scope, and not a gap:** the Live Activity, `NSSupportsLiveActivities`,
and anything ActivityKit — the §6 spike returned negative on 2026-08-09, harness archived
at tag `spike/feeds-live-activity-archive`. Also gone in this revision: the modal unlock
sheet, the separate timer screen, and the vertical reorder mode.

## Known gaps to decide later, not silently

- **A cluster row shows only system labels.** `FeedRowModel.kind` returns `.systemLabel` for every icon in a cluster, because a custom group's tokens carry no bundle id to look up in the registry — only template groups have a `templateApp`. A registry app inside a custom group therefore renders unstyled. Fixing it needs a token→bundleId mapping; `SharedKeys.fcBundleIdKey(_:)` already stores one for tokens the shield has seen, so this is tractable but is not attempted here.
- **The timer lists one app for template groups and a bare name for custom groups.** Per-app rows inside a custom group need the same token→bundleId mapping. Task 7 shows the group name rather than pretending.
