# Feeds Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the Feeds paper-ticket stack with a flat list, an unlock sheet, and an in-app timer that reports usage minutes honestly.

**Architecture:** Pure decision logic is extracted into small `Sendable` value types under `StepsTrader/Models/Feeds/`, unit-tested in `Steps4Tests`. SwiftUI views stay thin and are verified on a physical device. One row per `TicketGroup` — a plain icon when the group holds one app, a cluster when it holds several. The timer reads per-minute tick values that the existing `DeviceActivityMonitor` extension already writes to the app group.

**Tech Stack:** SwiftUI, FamilyControls, DeviceActivity, ManagedSettings, XCTest.

## Global Constraints

- **No ActivityKit, no Live Activity, no `NSSupportsLiveActivities`.** Dropped from scope: the `Feeds-Spec.md` §6 spike established that `DeviceActivityMonitor` sees an empty `Activity.activities` and cannot update one. Do not reintroduce it.
- `AccessWindow` keeps `minutes10` / `minutes30` / `hour1`. Costs stay 4 / 10 / 20. No enum migration, no repricing.
- **One row per `TicketGroup`, always.** Never split a group into per-app rows.
- Night theme throughout. The reference image for the timer is light; it illustrates *how time is displayed*, not colour direction.
- `SubscriptionGate.freeMaxBlockingGroups = 2` must not tighten.
- The shield extensions (`ShieldAction`, `ShieldConfiguration`) are untouched.
- The window is **spent, not elapsed**. Never render a wall-clock countdown. Never interpolate between ticks.
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
| `StepsTrader/Views/Feeds/FeedRowView.swift` | One row: plain icon or cluster, name, lock badge, remaining-time pill. |
| `StepsTrader/Views/Feeds/UnlockSheetView.swift` | The 10 / 30 / 60 sheet. |
| `StepsTrader/Views/Feeds/UnlockTimerView.swift` | The timer screen: depleting arc, mono digits, covered-apps list. |
| `Steps4Tests/FeedRowModelTests.swift` | Tests for `FeedRowModel`. |
| `Steps4Tests/UnlockTimerModelTests.swift` | Tests for `UnlockTimerModel`. |
| `Steps4Tests/UsageBudgetMonitoringErrorTests.swift` | Tests for the error mapping. |

**Modify:**

| File | Change |
|------|--------|
| `StepsTrader/Views/AppsPageSimplified.swift` | Ticket stack → flat list. Keep create / reorder / delete / paywall gating. |
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

**A note on testing SwiftUI here.** Tasks 1, 5 and 8 are pure logic and get real failing-test-first cycles. Tasks 2, 3, 4, 6, 7 and 9 are views over FamilyControls types that cannot be instantiated off-device; they get a build gate plus an explicit on-device observation list. Do not write assertion-free tests to make those tasks look symmetrical — an empty test that passes is worse than an honest manual check.

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

### Task 3: Feed row view

**Files:**
- Create: `StepsTrader/Views/Feeds/FeedRowView.swift`

**Interfaces:**
- Consumes: `FeedRowModel.kind(templateApp:appTokenCount:)`, `FeedIconView`, `AppModel.remainingUsageBudget(for:)`, `TargetResolver.displayName(for:)`.
- Produces: `FeedRowView(model:group:onTap:)`.

The lock badge must be identical for plain and cluster rows — `Feeds-Spec.md` calls this out explicitly, so draw it in one place, outside the kind switch.

- [ ] **Step 1: Write the view**

```swift
import SwiftUI
#if canImport(FamilyControls)
import FamilyControls
#endif

/// One row per `TicketGroup`. A single-app group draws a plain icon; a multi-app
/// group draws overlapping icons and the group's name. The lock badge is drawn
/// once, outside the kind switch, so it is provably identical for both.
struct FeedRowView: View {
    @ObservedObject var model: AppModel
    let group: TicketGroup
    let onTap: () -> Void

    @State private var remaining: Int = 0

    private var isUnlocked: Bool { remaining > 0 }

    private var kind: FeedRowKind {
        FeedRowModel.kind(
            templateApp: group.templateApp,
            appTokenCount: group.selection.applicationTokens.count
        )
    }

    private var title: String {
        if let templateApp = group.templateApp {
            return TargetResolver.displayName(for: templateApp)
        }
        return group.name
    }

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 14) {
                icons
                Text(title)
                    .font(.system(size: 17, weight: .medium, design: .rounded))
                    .foregroundStyle(AppColors.Night.textPrimary)
                    .lineLimit(1)
                Spacer(minLength: 8)
                trailing
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity)
            .background {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(Color.white.opacity(0.06))
            }
            .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        }
        .buttonStyle(.plain)
        .onAppear(perform: refresh)
        .task {
            // The honest signal arrives once a minute from the monitor extension.
            // Poll a little faster than that so the row is never more than a few
            // seconds stale, but never interpolate between ticks.
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(15))
                refresh()
            }
        }
    }

    @ViewBuilder
    private var icons: some View {
        switch kind {
        case .single(let source):
            icon(source: source, size: 44, index: 0)
        case .cluster(let sources, _):
            HStack(spacing: -14) {
                ForEach(Array(sources.enumerated()), id: \.offset) { index, source in
                    icon(source: source, size: 40, index: index)
                        .overlay {
                            RoundedRectangle(cornerRadius: 40 * 0.24, style: .continuous)
                                .strokeBorder(AppColors.Night.background, lineWidth: 2)
                        }
                        .zIndex(Double(sources.count - index))
                }
            }
        }
    }

    /// `FeedIconView`'s `token` parameter only exists where FamilyControls does,
    /// so the call itself has to be conditional — not just the value passed in.
    @ViewBuilder
    private func icon(source: FeedIconSource, size: CGFloat, index: Int) -> some View {
        #if canImport(FamilyControls)
        FeedIconView(source: source, size: size, token: token(at: index))
        #else
        FeedIconView(source: source, size: size)
        #endif
    }

    @ViewBuilder
    private var trailing: some View {
        if isUnlocked {
            Text(String(localized: "\(remaining)m", comment: "Feeds row – remaining usage minutes"))
                .font(.system(size: 15, weight: .semibold, design: .monospaced))
                .foregroundStyle(AppColors.brandAccent)
        }
        // Identical for both row kinds, by construction.
        Image(systemName: isUnlocked ? "lock.open" : "lock.fill")
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(isUnlocked ? AppColors.brandAccent : Color.white.opacity(0.35))
            .accessibilityLabel(isUnlocked
                ? String(localized: "Unlocked", comment: "Feeds row – lock badge state")
                : String(localized: "Locked", comment: "Feeds row – lock badge state"))
    }

    #if canImport(FamilyControls)
    private func token(at index: Int) -> ApplicationToken? {
        let tokens = Array(group.selection.applicationTokens)
        guard index < tokens.count else { return nil }
        return tokens[index]
    }
    #endif

    private func refresh() {
        remaining = model.remainingUsageBudget(for: group.id)
    }
}
```

- [ ] **Step 2: Verify it compiles**

Run: `xcodebuild -project Steps4.xcodeproj -scheme Steps4 -destination 'platform=iOS Simulator,name=iPhone 17' -configuration Debug build`

Expected: BUILD SUCCEEDED.

- [ ] **Step 3: Commit**

```bash
git add StepsTrader/Views/Feeds/FeedRowView.swift
git commit -m "feat: add FeedRowView — plain icon, cluster, shared lock badge"
```

---

### Task 4: Flat list replaces the ticket stack

**Files:**
- Modify: `StepsTrader/Views/AppsPageSimplified.swift:269-331` (the `ticketStack` property)

**Interfaces:**
- Consumes: `FeedRowView` from Task 3.
- Produces: a new `@State private var unlockSheetGroupId: TicketGroupId?`, which Task 6 attaches the unlock sheet to. `visibleGroups`, `moveTicket(_:up:)`, `attemptCreateGroup()`, `expandedSheetGroupId` and `groupIdToDelete` all keep their current meanings.

**Do not reuse `selectedGroupId`.** It is already taken: `AppsPageSimplified.swift:172-196` uses it to remember which group the `FamilyActivityPicker` is editing, paired with `showPicker`. Hanging the unlock sheet on it would break group editing. Add a separate state property.

Keep: the reorder chevrons, the context menu, the paywall gate, the empty state, the `FirstFeedAnchor` DEBUG coach-mark modifier. Only the row rendering changes.

- [ ] **Step 1: Add the unlock-sheet state**

Next to the other `@State` declarations near `AppsPageSimplified.swift:41`, add:

```swift
    @State private var unlockSheetGroupId: TicketGroupId? = nil
    @State private var timerGroupId: TicketGroupId? = nil
```

- [ ] **Step 2: Replace the stack body**

Replace the `ticketStack` property with:

```swift
    // MARK: - Feed List

    private var ticketStack: some View {
        LazyVStack(spacing: 10) {
            ForEach(visibleGroups) { group in
                FeedRowView(
                    model: model,
                    group: group,
                    onTap: {
                        guard !isReordering else { return }
                        unlockSheetGroupId = TicketGroupId(id: group.id)
                    }
                )
                .overlay(alignment: .trailing) {
                    if isReordering {
                        VStack(spacing: 0) {
                            Button {
                                moveTicket(group.id, up: true)
                            } label: {
                                Image(systemName: "chevron.up")
                                    .font(.system(size: 13, weight: .semibold))
                                    .frame(width: 44, height: 36)
                                    .contentShape(Rectangle())
                            }
                            .disabled(visibleGroups.first?.id == group.id)

                            Divider().frame(width: 20)

                            Button {
                                moveTicket(group.id, up: false)
                            } label: {
                                Image(systemName: "chevron.down")
                                    .font(.system(size: 13, weight: .semibold))
                                    .frame(width: 44, height: 36)
                                    .contentShape(Rectangle())
                            }
                            .disabled(visibleGroups.last?.id == group.id)
                        }
                        .foregroundStyle(Color.primary.opacity(0.7))
                        .liquidGlassControl(in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .padding(.trailing, 10)
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                    }
                }
                .contextMenu {
                    if !isReordering {
                        Button {
                            expandedSheetGroupId = TicketGroupId(id: group.id)
                        } label: {
                            Label(String(localized: "Settings", comment: "Context menu action"), systemImage: "gearshape")
                        }
                        Button(role: .destructive) {
                            groupIdToDelete = group.id
                        } label: {
                            Label(String(localized: "Delete"), systemImage: "trash")
                        }
                    }
                }
                #if DEBUG
                .modifier(FirstFeedAnchor(groupId: group.id, firstId: visibleGroups.first?.id))
                #endif
            }
        }
    }
```

- [ ] **Step 3: Verify it compiles**

Run: `xcodebuild -project Steps4.xcodeproj -scheme Steps4 -destination 'platform=iOS Simulator,name=iPhone 17' -configuration Debug build`

Expected: BUILD SUCCEEDED.

- [ ] **Step 4: Verify on the simulator**

Run the app, open Feeds. Confirm by eye:
- one row per group, no ticket cards, no sticker themes
- reorder chevrons still work and are still disabled at the ends
- long-press still offers Settings and Delete
- the empty state still appears with zero groups
- `+` still opens the template picker, and still paywalls a free user at the third group

- [ ] **Step 5: Commit**

```bash
git add StepsTrader/Views/AppsPageSimplified.swift
git commit -m "feat: render Feeds as a flat list of group rows"
```

---

### Task 5: Timer model — stepping, never backwards

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

### Task 6: Unlock sheet

**Files:**
- Create: `StepsTrader/Views/Feeds/UnlockSheetView.swift`
- Modify: `StepsTrader/Views/AppsPageSimplified.swift` — attach the sheet to `unlockSheetGroupId` (declared in Task 4)

**Interfaces:**
- Consumes: `AccessWindow.allCases`, `TicketGroup.cost(for:)`, `AppModel.handlePayGatePaymentForGroup(groupId:window:costOverride:)`, `AppModel.totalStepsBalance`, `AppModel.payGateError`.
- Produces: `UnlockSheetView(model:group:onUnlocked:)`, where `onUnlocked` fires only after a successful purchase.

Reuses the existing PayGate payment flow unchanged. This is Nowhere's own screen, not the system shield.

- [ ] **Step 1: Write the sheet**

```swift
import SwiftUI

/// Nowhere's own unlock screen — warm and deliberate like the PayGate, but not the
/// system shield. Intervals and prices are unchanged: 10 / 30 / 60 at 4 / 10 / 20.
struct UnlockSheetView: View {
    @ObservedObject var model: AppModel
    let group: TicketGroup
    let onUnlocked: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var isPurchasing = false

    private var title: String {
        if let templateApp = group.templateApp {
            return TargetResolver.displayName(for: templateApp)
        }
        return group.name
    }

    var body: some View {
        VStack(spacing: 24) {
            VStack(spacing: 6) {
                Text(title)
                    .font(.system(size: 22, weight: .semibold, design: .rounded))
                Text(String(localized: "How long?", comment: "Unlock sheet – subtitle"))
                    .font(.system(size: 15))
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 28)

            VStack(spacing: 10) {
                ForEach(AccessWindow.allCases, id: \.self) { window in
                    windowRow(window)
                }
            }

            if let error = model.payGateError {
                Text(error)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 20)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppColors.Night.background)
        .presentationDetents([.medium])
    }

    private func windowRow(_ window: AccessWindow) -> some View {
        let cost = group.cost(for: window)
        let affordable = model.totalStepsBalance >= cost

        return Button {
            guard !isPurchasing else { return }
            isPurchasing = true
            Task { @MainActor in
                await model.handlePayGatePaymentForGroup(
                    groupId: group.id,
                    window: window,
                    costOverride: nil
                )
                isPurchasing = false
                if model.payGateError == nil, model.isGroupUsageBudgetActive(group.id) {
                    onUnlocked()
                    dismiss()
                }
            }
        } label: {
            HStack {
                Text(window.displayName)
                    .font(.system(size: 17, weight: .medium, design: .rounded))
                Spacer()
                Text("\(cost)")
                    .font(.system(size: 17, weight: .semibold, design: .monospaced))
                    .foregroundStyle(affordable ? AppColors.brandAccent : Color.white.opacity(0.35))
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 16)
            .background {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color.white.opacity(0.06))
            }
        }
        .buttonStyle(.plain)
        .disabled(!affordable || isPurchasing)
        .opacity(affordable ? 1 : 0.5)
    }
}
```

- [ ] **Step 2: Attach it in `AppsPageSimplified`**

Add alongside the existing `.sheet` modifiers on the `NavigationStack`:

```swift
            .sheet(item: $unlockSheetGroupId) { wrapper in
                if let group = model.blockingStore.ticketGroups.first(where: { $0.id == wrapper.id }) {
                    UnlockSheetView(
                        model: model,
                        group: group,
                        onUnlocked: { timerGroupId = TicketGroupId(id: group.id) }
                    )
                }
            }
```

`unlockSheetGroupId` and `timerGroupId` were both declared in Task 4.

- [ ] **Step 3: Verify it compiles**

Run: `xcodebuild -project Steps4.xcodeproj -scheme Steps4 -destination 'platform=iOS Simulator,name=iPhone 17' -configuration Debug build`

Expected: BUILD SUCCEEDED.

- [ ] **Step 4: Verify on a physical device**

Purchasing touches FamilyControls and DeviceActivity and cannot be trusted in the simulator. On device, confirm:
- tapping a locked row opens the sheet, showing 10 min / 30 min / 1 hour at 4 / 10 / 20
- a window costing more than the balance is dimmed and unpressable
- buying deducts the colours once, and the row's lock badge flips to unlocked

- [ ] **Step 5: Commit**

```bash
git add StepsTrader/Views/Feeds/UnlockSheetView.swift StepsTrader/Views/AppsPageSimplified.swift
git commit -m "feat: add the Feeds unlock sheet"
```

---

### Task 7: Timer screen

**Files:**
- Create: `StepsTrader/Views/Feeds/UnlockTimerView.swift`
- Modify: `StepsTrader/Views/AppsPageSimplified.swift` — present it from `timerGroupId`

**Interfaces:**
- Consumes: `UnlockTimerModel` from Task 5, `FeedIconView` from Task 2, `AppModel.remainingUsageBudget(for:)`, `TargetResolver.primaryAndFallbackSchemes(for:)`.
- Produces: `UnlockTimerView(model:group:)`.

No pause control. The screen shows time and launches apps, nothing else.

- [ ] **Step 1: Write the screen**

```swift
import SwiftUI
#if canImport(FamilyControls)
import FamilyControls
#endif

/// The window is spent, not elapsed — this screen shows minutes of actual app use,
/// stepping once a minute. There is no pause control and no wall-clock countdown.
struct UnlockTimerView: View {
    @ObservedObject var model: AppModel
    let group: TicketGroup

    @Environment(\.openURL) private var openURL
    @Environment(\.dismiss) private var dismiss

    @State private var timer: UnlockTimerModel
    @State private var state: UnlockTimerModel.State

    init(model: AppModel, group: TicketGroup) {
        self.model = model
        self.group = group
        let initial = UserDefaults.stepsTrader()
            .integer(forKey: SharedKeys.usageBudgetInitialKey(group.id))
        var timer = UnlockTimerModel(initialMinutes: initial)
        let first = timer.observe(remainingMinutes: initial)
        _timer = State(initialValue: timer)
        _state = State(initialValue: first)
    }

    var body: some View {
        VStack(spacing: 32) {
            arc
            coveredApps
            Spacer(minLength: 0)
        }
        .padding(.top, 48)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppColors.Night.background.ignoresSafeArea())
        .onAppear(perform: refresh)
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(15))
                refresh()
            }
        }
    }

    private var arc: some View {
        ZStack {
            Circle()
                .stroke(Color.white.opacity(0.10), lineWidth: 14)

            Circle()
                .trim(from: 0, to: state.fraction)
                .stroke(
                    AppColors.brandAccent,
                    style: StrokeStyle(lineWidth: 14, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                // Animate the step itself so the boundary reads as deliberate.
                // This animates between observed values only — it never runs ahead
                // of the last tick.
                .animation(.easeOut(duration: 0.45), value: state.fraction)

            Text(state.digits)
                .font(.system(size: 44, weight: .medium, design: .monospaced))
                .foregroundStyle(AppColors.Night.textPrimary)
                .monospacedDigit()
        }
        .frame(width: 220, height: 220)
    }

    private var coveredApps: some View {
        VStack(spacing: 10) {
            Text(String(localized: "Covered by this window", comment: "Timer screen – app list header"))
                .font(.caption)
                .foregroundStyle(.secondary)

            if let templateApp = group.templateApp {
                appButton(bundleId: templateApp)
            } else {
                // Non-registry apps yield no launch scheme, so the row is shown but
                // not tappable rather than silently doing nothing on tap.
                Text(group.name)
                    .font(.system(size: 15))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 24)
    }

    private func appButton(bundleId: String) -> some View {
        let schemes = TargetResolver.primaryAndFallbackSchemes(for: bundleId)
        return Button {
            guard let first = schemes.first, let url = URL(string: first) else { return }
            openURL(url)
        } label: {
            HStack(spacing: 12) {
                FeedIconView(source: FeedRowModel.iconSource(forBundleId: bundleId), size: 36)
                Text(TargetResolver.displayName(for: bundleId))
                    .font(.system(size: 16, weight: .medium, design: .rounded))
                    .foregroundStyle(AppColors.Night.textPrimary)
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color.white.opacity(0.06))
            }
        }
        .buttonStyle(.plain)
        .disabled(schemes.isEmpty)
    }

    private func refresh() {
        let stored = UserDefaults.stepsTrader()
            .integer(forKey: SharedKeys.usageBudgetInitialKey(group.id))
        if stored > timer.initialMinutes {
            // The user bought more time; this is the one legitimate increase.
            timer.reset(initialMinutes: stored)
        }
        state = timer.observe(remainingMinutes: model.remainingUsageBudget(for: group.id))
        if state.remainingMinutes == 0 { dismiss() }
    }
}
```

- [ ] **Step 2: Present it from the list**

Add alongside the other modifiers on the `NavigationStack` in `AppsPageSimplified`:

```swift
            .fullScreenCover(item: $timerGroupId) { wrapper in
                if let group = model.blockingStore.ticketGroups.first(where: { $0.id == wrapper.id }) {
                    UnlockTimerView(model: model, group: group)
                }
            }
```

- [ ] **Step 3: Verify it compiles**

Run: `xcodebuild -project Steps4.xcodeproj -scheme Steps4 -destination 'platform=iOS Simulator,name=iPhone 17' -configuration Debug build`

Expected: BUILD SUCCEEDED.

- [ ] **Step 4: Verify on a physical device**

This is the acceptance criterion the whole spec is built around, so do not skip it:
- buy a 10-minute window; the timer opens on the night theme with a full arc and `10:00`
- tap the app in the list; it launches
- **leave the phone idle for five minutes with the window open, then reopen the timer — the arc must not have moved.** The window is spent, not elapsed.
- use the app for two minutes; the arc steps down twice and the digits read `08:00`
- confirm the arc never jumps forward at any point

- [ ] **Step 5: Commit**

```bash
git add StepsTrader/Views/Feeds/UnlockTimerView.swift StepsTrader/Views/AppsPageSimplified.swift
git commit -m "feat: add the unlock timer screen"
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
        let message = UsageBudgetMonitoringError.excessiveActivities.userFacingMessage
        XCTAssertTrue(message.contains("too many"), "the message must name the cause")
        XCTAssertTrue(message.lowercased().contains("close"), "the message must offer a remedy")
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

Mapped from `Feeds-Spec.md` and `Feeds-Brief.md` §8, minus everything the spike removed.

- [ ] Feeds is a single scrolling list, one row per `TicketGroup`; no ticket stack remains — Tasks 4, 9
- [ ] A registry app shows its bundled asset; a non-registry app shows a system `Label` — Tasks 1, 2
- [ ] A single-app group, including every template group, renders as a plain icon — Tasks 1, 3
- [ ] A multi-app custom group renders as a cluster with the group's name — Tasks 1, 3
- [ ] Locked entries carry a lock badge, identical for plain and cluster rows — Task 3
- [ ] Tapping a locked entry offers 10 / 30 / 60 minutes at 4 / 10 / 20 colors, for that group — Task 6
- [ ] Buying a window opens the timer screen, in the night theme — Tasks 6, 7
- [ ] The timer lists the window's apps, and tapping one launches it — Task 7
- [ ] **The timer does not move while the covered apps are unused** — Task 7, device check
- [ ] The arc steps on tick boundaries and never runs backwards — Task 5 tests, Task 7 device check
- [ ] Exceeding the DeviceActivity cap surfaces a user-facing error — Task 8

**Explicitly not in scope, and not a gap:** the Live Activity, `NSSupportsLiveActivities`, and anything ActivityKit. The `Feeds-Spec.md` §6 spike returned negative on 2026-08-09; the harness is archived at tag `spike/feeds-live-activity-archive`.

## Known gaps to decide later, not silently

- **A cluster row shows only system labels.** `FeedRowModel.kind` returns `.systemLabel` for every icon in a cluster, because a custom group's tokens carry no bundle id to look up in the registry — only template groups have a `templateApp`. A registry app inside a custom group therefore renders unstyled. Fixing it needs a token→bundleId mapping; `SharedKeys.fcBundleIdKey(_:)` already stores one for tokens the shield has seen, so this is tractable but is not attempted here.
- **The timer lists one app for template groups and a bare name for custom groups.** Per-app rows inside a custom group need the same token→bundleId mapping. Task 7 shows the group name rather than pretending.
