# Settings Native Editorial Calm Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Preserve the card-based Settings home while making all settings destinations native in navigation, truthful about permission state, calmer in presentation, safer for destructive actions, and complete under iOS accessibility settings.

**Architecture:** `SettingsSheet` remains the navigation owner. Pure presentation types convert model and system authorization state into user-facing status before SwiftUI renders it; shared navigation and grouped-surface components define the detail-page shell; business values continue to live in the existing stores and `AppStorage`. Appearance gains a view-only Automatic/Manual mode derived from the existing boolean, so no persistence migration is required.

**Tech Stack:** Swift 6, SwiftUI, HealthKit, UserNotifications, FamilyControls, `UserDefaults`/`@AppStorage`, XCTest, XCUITest, iOS Simulator.

**Spec:** `docs/superpowers/specs/2026-08-29-settings-native-editorial-calm-design.md`

## Global Constraints

- Preserve the approved Settings home order: account, `Your day`, four app destinations, information group, DEBUG-only Developer, footer.
- Signed-out users retain full access to step goal, sleep goal, and custom-day boundary.
- Do not change existing AppStorage keys, Supabase payloads, energy calculations, sync conflict policy, or automatic-sync behavior.
- `AppModel.updateDayEnd(hour:minute:)` remains the only custom-day writer.
- Health read denial cannot be queried reliably; absent Health samples must not be labeled `Denied` or contribute to an urgent warning.
- Keep standalone Widget and Wallpaper destinations for feature-tip deep links.
- Use system navigation bars, the system Back button, and system edge-swipe behavior; do not add a replacement full-surface dismiss gesture.
- Every interactive target is at least 44×44 pt; all user-facing text scales relative to a semantic text style and uses Caption 2 or larger at default size.
- Selection and permission state use text or symbols in addition to color and expose equivalent VoiceOver state.
- Honor Reduce Motion, Increase Contrast, Light Mode, and Dark Mode.
- Preserve unrelated working-tree changes. At planning time, `Steps4Tests/DayObjectChoreographyTests.swift`, `StepsTrader/Experiments/DayObjects/DayObjectChoreographyPreset.swift`, and `StepsTrader/Localizable.xcstrings` are already modified; do not overwrite the first two, and stage only this plan's extracted-string hunks from the localization catalog with `git add -p`.
- Before every commit, run `git diff --cached --check` and inspect `git diff --cached --name-only`; never use `git add .`, `git add -A`, or `git commit -a`.

### Verification commands

```bash
xcodebuild build -project Steps4.xcodeproj -scheme Steps4 -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17,OS=latest' CODE_SIGNING_ALLOWED=NO
```

```bash
xcodebuild test -project Steps4.xcodeproj -scheme Steps4 -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17,OS=latest' -only-testing:Steps4Tests/SettingsHomePresentationTests -only-testing:Steps4Tests/SettingsPermissionPresentationTests CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO
```

```bash
xcodebuild test -project Steps4.xcodeproj -scheme Steps4 -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17,OS=latest' -only-testing:Steps4UITests/SettingsRedesignUITests CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO
```

---

## File Map

### Create

- `StepsTrader/Views/Settings/SettingsPermissionPresentation.swift` — pure Health, Screen Time, and notification status presentation.
- `Steps4Tests/SettingsPermissionPresentationTests.swift` — truth-table tests for status, copy intent, actions, and warning contribution.

### Modify

- `StepsTrader/AppModel.swift` — make `hasPermissionIssues` reflect only known actionable issues.
- `StepsTrader/Views/SettingsSheet.swift` — system large title, visible Close action, truthful permission warning.
- `StepsTrader/Views/Settings/SettingsComponents.swift` — remove custom header/swipe; add shared detail background, grouped surface, and selection accessibility modifier.
- `StepsTrader/Views/Settings/SettingsHomePresentation.swift` — add the view-only Appearance mode mapping.
- `StepsTrader/Views/Settings/SettingsAppearancePage.swift` — Automatic/Manual hierarchy, progressive disclosure, scalable labels, selected semantics, Reduce Motion.
- `StepsTrader/Views/Settings/SettingsPermissionsPage.swift` — render truthful status and visible recovery errors.
- `StepsTrader/Views/NotificationSettingsView.swift` — authorization status card, recovery CTA, clarified copy, labeled controls.
- `StepsTrader/Views/Settings/SettingsEnergyPage.swift` — system navigation and quiet detail shell.
- `StepsTrader/Views/Settings/SettingsWidgetsWallpaperPage.swift` — system navigation and grouped detail sections.
- `StepsTrader/Views/Settings/SettingsWidgetPage.swift` — system navigation and selected-state semantics.
- `StepsTrader/Views/Settings/SettingsShortcutPage.swift` — system navigation and CTA-first setup disclosure.
- `StepsTrader/Views/Settings/SettingsAboutPage.swift` — system navigation, grouped rows, robust value layout.
- `StepsTrader/Views/Settings/SettingsAccountPage.swift` — system navigation and user-readable errors.
- `StepsTrader/Views/Settings/SettingsDeveloperPage.swift` — system navigation.
- `StepsTrader/Views/ManualsPage.swift` — system navigation and scalable note controls.
- `StepsTrader/Views/InlineTicketSettingsView.swift` — destructive confirmation, labeled interval toggles, Reduce Motion.
- `Steps4Tests/SettingsHomePresentationTests.swift` — Appearance mode mapping tests.
- `Steps4UITests/SettingsRedesignUITests.swift` — navigation, permission, appearance, and accessibility regression tests.
- `StepsTrader/Localizable.xcstrings` — Xcode-extracted strings for new status and recovery copy.
- `Steps4.xcodeproj/project.pbxproj` — register the two new Swift files.

---

### Task 1: Introduce Truthful Permission Presentation

**Files:**
- Create: `StepsTrader/Views/Settings/SettingsPermissionPresentation.swift`
- Create: `Steps4Tests/SettingsPermissionPresentationTests.swift`
- Modify: `StepsTrader/AppModel.swift:628-634`
- Modify: `Steps4.xcodeproj/project.pbxproj`

**Interfaces:**
- Consumes: `UNAuthorizationStatus`, Health availability, whether a Health query has returned, and Screen Time authorization.
- Produces: `SettingsPermissionPresentation.health(isAvailable:hasReturnedData:)`, `.notifications(status:)`, `.screenTime(isAuthorized:)`, plus `contributesToWarning`.

- [ ] **Step 1: Write the failing permission truth-table tests**

```swift
import UserNotifications
import XCTest
@testable import Steps4

final class SettingsPermissionPresentationTests: XCTestCase {
    func testHealthWithoutReturnedDataIsNeutralNotMissing() {
        let state = SettingsPermissionPresentation.health(
            isAvailable: true,
            hasReturnedData: false
        )
        XCTAssertEqual(state.status, .checkAccess)
        XCTAssertFalse(state.contributesToWarning)
        XCTAssertEqual(state.action, .checkAccess)
    }

    func testSuccessfulZeroValueHealthQueryCountsAsConnected() {
        let state = SettingsPermissionPresentation.health(
            isAvailable: true,
            hasReturnedData: true
        )
        XCTAssertEqual(state.status, .connected)
        XCTAssertFalse(state.contributesToWarning)
        XCTAssertNil(state.action)
    }

    func testDeniedNotificationsAreKnownActionableIssue() {
        let state = SettingsPermissionPresentation.notifications(status: .denied)
        XCTAssertEqual(state.status, .offInSystemSettings)
        XCTAssertEqual(state.action, .openSystemSettings)
        XCTAssertTrue(state.contributesToWarning)
    }

    func testNotDeterminedNotificationsOfferPermissionRequest() {
        let state = SettingsPermissionPresentation.notifications(status: .notDetermined)
        XCTAssertEqual(state.status, .notRequested)
        XCTAssertEqual(state.action, .requestPermission)
        XCTAssertTrue(state.contributesToWarning)
    }

    func testMissingScreenTimeIsKnownActionableIssue() {
        XCTAssertTrue(
            SettingsPermissionPresentation.screenTime(isAuthorized: false)
                .contributesToWarning
        )
    }
}
```

- [ ] **Step 2: Register the files and run the tests to verify failure**

Add explicit file references, build-file entries, group membership, and Sources build-phase entries to `Steps4.xcodeproj/project.pbxproj`.

Run the focused unit-test command. Expected: compile failure because `SettingsPermissionPresentation`, `SettingsPermissionStatus`, and `SettingsPermissionAction` do not exist.

- [ ] **Step 3: Implement the minimal pure presentation model**

```swift
import Foundation
import UserNotifications

enum SettingsPermissionStatus: Equatable {
    case connected
    case checkAccess
    case unavailable
    case allowed
    case notRequested
    case offInSystemSettings
    case actionNeeded
}

enum SettingsPermissionAction: Equatable {
    case checkAccess
    case requestPermission
    case openSystemSettings
}

struct SettingsPermissionPresentation: Equatable {
    let status: SettingsPermissionStatus
    let action: SettingsPermissionAction?
    let contributesToWarning: Bool

    static func health(isAvailable: Bool, hasReturnedData: Bool) -> Self {
        guard isAvailable else {
            return .init(status: .unavailable, action: nil, contributesToWarning: false)
        }
        return hasReturnedData
            ? .init(status: .connected, action: nil, contributesToWarning: false)
            : .init(status: .checkAccess, action: .checkAccess, contributesToWarning: false)
    }

    static func notifications(status: UNAuthorizationStatus) -> Self {
        switch status {
        case .authorized, .provisional, .ephemeral:
            return .init(status: .allowed, action: nil, contributesToWarning: false)
        case .notDetermined:
            return .init(status: .notRequested, action: .requestPermission, contributesToWarning: true)
        case .denied:
            return .init(status: .offInSystemSettings, action: .openSystemSettings, contributesToWarning: true)
        @unknown default:
            return .init(status: .checkAccess, action: .openSystemSettings, contributesToWarning: false)
        }
    }

    static func screenTime(isAuthorized: Bool) -> Self {
        isAuthorized
            ? .init(status: .connected, action: nil, contributesToWarning: false)
            : .init(status: .actionNeeded, action: .requestPermission, contributesToWarning: true)
    }
}
```

- [ ] **Step 4: Remove the false Health contribution from the global warning**

Change `AppModel.hasPermissionIssues` to use only known states:

```swift
var hasPermissionIssues: Bool {
    let familyMissing = !blockingStore.isAuthorized
    let notifications = SettingsPermissionPresentation.notifications(
        status: notificationAuthorizationStatus
    )
    return familyMissing || notifications.contributesToWarning
}
```

- [ ] **Step 5: Run tests and build**

Run the focused unit tests and build. Expected: all permission truth-table tests and existing Settings presentation tests pass.

- [ ] **Step 6: Commit the permission model**

```bash
git add StepsTrader/Views/Settings/SettingsPermissionPresentation.swift Steps4Tests/SettingsPermissionPresentationTests.swift StepsTrader/AppModel.swift
git add -p Steps4.xcodeproj/project.pbxproj
git diff --cached --check
git diff --cached --name-only
git commit -m "fix: represent settings permissions truthfully"
```

---

### Task 2: Restore System Settings Navigation

**Files:**
- Modify: `StepsTrader/Views/SettingsSheet.swift`
- Modify: `StepsTrader/Views/Settings/SettingsComponents.swift`
- Modify: `StepsTrader/Views/Settings/SettingsEnergyPage.swift`
- Modify: `StepsTrader/Views/Settings/SettingsAppearancePage.swift`
- Modify: `StepsTrader/Views/Settings/SettingsPermissionsPage.swift`
- Modify: `StepsTrader/Views/Settings/SettingsWidgetsWallpaperPage.swift`
- Modify: `StepsTrader/Views/Settings/SettingsWidgetPage.swift`
- Modify: `StepsTrader/Views/Settings/SettingsShortcutPage.swift`
- Modify: `StepsTrader/Views/Settings/SettingsAboutPage.swift`
- Modify: `StepsTrader/Views/Settings/SettingsAccountPage.swift`
- Modify: `StepsTrader/Views/Settings/SettingsDeveloperPage.swift`
- Modify: `StepsTrader/Views/NotificationSettingsView.swift`
- Modify: `StepsTrader/Views/ManualsPage.swift`
- Modify: `Steps4UITests/SettingsRedesignUITests.swift`

**Interfaces:**
- Consumes: the existing `NavigationStack` and all current `NavigationLink` destinations.
- Produces: root `settings.close`, system navigation titles, and uninterrupted horizontal interactions.

- [ ] **Step 1: Add failing root Close and detail navigation UI tests**

```swift
func testSettingsUsesVisibleCloseAndSystemBackNavigation() {
    let app = launchSettings()
    let close = app.buttons["settings.close"]
    XCTAssertTrue(close.waitForExistence(timeout: 3))
    assertMinimumHitTarget(close)

    app.buttons["settings.yourDay"].tap()
    XCTAssertTrue(app.navigationBars["Your day"].waitForExistence(timeout: 3))
    XCTAssertTrue(app.navigationBars.buttons.element(boundBy: 0).isHittable)
}

func testAppearanceHorizontalSwipeDoesNotDismissDestination() {
    let app = launchSettings()
    app.buttons["settings.destination.appearance"].tap()
    let carousel = app.otherElements["settings.appearance.paletteCarousel"]
    XCTAssertTrue(carousel.waitForExistence(timeout: 3))
    carousel.swipeRight()
    XCTAssertTrue(app.navigationBars["Appearance"].exists)
}
```

- [ ] **Step 2: Run the two tests to verify failure**

Run only the two new test methods. Expected: `settings.close` and the system navigation bars do not exist.

- [ ] **Step 3: Convert the root sheet to a system large title and Close action**

In `SettingsSheet`, add `@Environment(\.dismiss) private var dismiss`, remove the manually rendered `Text("Settings")`, and add:

```swift
.navigationTitle(String(localized: "Settings", comment: "Settings page title"))
.navigationBarTitleDisplayMode(.large)
.toolbar {
    if !embeddedInTab {
        ToolbarItem(placement: .topBarTrailing) {
            Button(String(localized: "Close", comment: "Settings sheet close button")) {
                if let onDone { onDone() } else { dismiss() }
            }
            .accessibilityIdentifier("settings.close")
        }
    }
}
```

- [ ] **Step 4: Convert every reachable destination to system navigation**

For each listed destination, remove `DetailHeader`, `.toolbar(.hidden, for: .navigationBar)`, and `.detailSwipeBack()`, then add:

```swift
.navigationTitle(String(localized: "Appearance", comment: "Settings section title"))
.navigationBarTitleDisplayMode(.inline)
```

Use each page's existing localized title. Add `settings.appearance.paletteCarousel` to the palette ScrollView.

- [ ] **Step 5: Delete the unused custom navigation implementation**

Remove `DetailHeader`, `DetailSwipeBackModifier`, `detailSwipeBack()`, and their comments from `SettingsComponents.swift`. Confirm:

```bash
rg -n 'DetailHeader|detailSwipeBack' StepsTrader/Views
```

Expected: no matches in reachable Settings destinations; `DayEndSettingsView` is handled in Task 7.

- [ ] **Step 6: Run the navigation tests and existing Settings UI suite**

Expected: Close exists, system Back is hittable, the Appearance carousel remains on-screen after a rightward swipe, and all existing routes still resolve.

- [ ] **Step 7: Commit the system navigation migration**

```bash
git add StepsTrader/Views/SettingsSheet.swift StepsTrader/Views/Settings/SettingsComponents.swift StepsTrader/Views/Settings StepsTrader/Views/NotificationSettingsView.swift StepsTrader/Views/ManualsPage.swift Steps4UITests/SettingsRedesignUITests.swift
git add -p StepsTrader/Localizable.xcstrings
git diff --cached --check
git diff --cached --name-only
git commit -m "refactor: use native settings navigation"
```

---

### Task 3: Establish the Quiet Grouped Detail Shell

**Files:**
- Modify: `StepsTrader/Views/Settings/SettingsComponents.swift`
- Modify: every detail page listed in Task 2
- Modify: `Steps4UITests/SettingsRedesignUITests.swift`

**Interfaces:**
- Produces: `SettingsDetailBackground`, `SettingsGroupedSurface`, and `settingsDetailPage(title:)` for consistent composition.

- [ ] **Step 1: Add a failing detail hierarchy smoke test**

```swift
func testNotificationsUsesGroupedDetailSurface() {
    let app = launchSettings()
    app.buttons["settings.destination.notifications"].tap()
    XCTAssertTrue(app.otherElements["settings.detail.background"].waitForExistence(timeout: 3))
    XCTAssertTrue(app.otherElements["settings.notifications.accessWindow"].exists)
}
```

- [ ] **Step 2: Run the test to verify failure**

Expected: neither identifier exists.

- [ ] **Step 3: Add shared calm detail components**

```swift
struct SettingsDetailBackground: View {
    @ObservedObject var model: AppModel
    @Environment(\.appTheme) private var theme

    var body: some View {
        ZStack {
            SettingsGradientBG(model: model)
            theme.backgroundColor.opacity(0.78)
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
        .accessibilityIdentifier("settings.detail.background")
    }
}

struct SettingsGroupedSurface<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(spacing: 0, content: content)
            .settingsCardSurface()
    }
}
```

- [ ] **Step 4: Apply the shell consistently**

Replace full-strength `SettingsGradientBG` with `SettingsDetailBackground` on ordinary detail pages. Wrap related rows inside `SettingsGroupedSurface`; retain richer preview surfaces only inside Appearance and Widget previews. Preserve all existing bindings and side effects.

- [ ] **Step 5: Run the detail smoke test, Settings UI suite, and build**

Expected: the identifiers exist, routes remain functional, and the app builds in both Light and Dark appearances.

- [ ] **Step 6: Commit the grouped detail shell**

```bash
git add StepsTrader/Views/Settings/SettingsComponents.swift StepsTrader/Views/Settings StepsTrader/Views/NotificationSettingsView.swift StepsTrader/Views/ManualsPage.swift Steps4UITests/SettingsRedesignUITests.swift
git diff --cached --check
git diff --cached --name-only
git commit -m "style: calm settings detail surfaces"
```

---

### Task 4: Restructure Appearance and Complete Selection Accessibility

**Files:**
- Modify: `StepsTrader/Views/Settings/SettingsHomePresentation.swift`
- Modify: `StepsTrader/Views/Settings/SettingsComponents.swift`
- Modify: `StepsTrader/Views/Settings/SettingsAppearancePage.swift`
- Modify: `StepsTrader/Views/Settings/SettingsWidgetPage.swift`
- Modify: `StepsTrader/Views/Settings/GradientPreviewSheet.swift`
- Modify: `Steps4Tests/SettingsHomePresentationTests.swift`
- Modify: `Steps4UITests/SettingsRedesignUITests.swift`

**Interfaces:**
- Produces: `SettingsAppearanceMode`, its binding to `dailyRandomThemeEnabled`, and `settingsSelectable(label:isSelected:)`.

- [ ] **Step 1: Write failing mode-mapping tests**

```swift
func testAppearanceModeMapsToExistingBooleanWithoutMigration() {
    XCTAssertEqual(SettingsAppearanceMode(dailyRandomEnabled: true), .automatic)
    XCTAssertEqual(SettingsAppearanceMode(dailyRandomEnabled: false), .manual)
    XCTAssertTrue(SettingsAppearanceMode.automatic.dailyRandomEnabled)
    XCTAssertFalse(SettingsAppearanceMode.manual.dailyRandomEnabled)
}
```

- [ ] **Step 2: Run the unit test to verify failure**

Expected: `SettingsAppearanceMode` is undefined.

- [ ] **Step 3: Add the view-only Appearance mode**

```swift
enum SettingsAppearanceMode: String, CaseIterable, Identifiable {
    case automatic
    case manual

    var id: Self { self }
    init(dailyRandomEnabled: Bool) { self = dailyRandomEnabled ? .automatic : .manual }
    var dailyRandomEnabled: Bool { self == .automatic }
}
```

Bind the segmented Picker directly to `dailyRandomThemeEnabled`; do not introduce a new stored key.

- [ ] **Step 4: Write failing Appearance accessibility UI coverage**

```swift
func testAppearanceManualChoicesExposeSelectedStateAtAccessibilitySize() {
    let app = launchSettings(contentSizeCategory: "UICTContentSizeCategoryAccessibilityM")
    app.buttons["settings.destination.appearance"].tap()
    app.segmentedControls.buttons["Manual"].tap()
    let selectedPalette = app.buttons.matching(
        NSPredicate(format: "value == 'Selected'")
    ).firstMatch
    XCTAssertTrue(selectedPalette.waitForExistence(timeout: 3))
    XCTAssertTrue(selectedPalette.isHittable)
}
```

- [ ] **Step 5: Add one reusable selectable semantic modifier**

Implement `settingsSelectable(label:isSelected:)` so it combines decorative children, supplies the label, emits `Selected`/`Not selected`, and adds `.isSelected` only when selected. Apply it to palette, gradient, modern palette, fill, shape, texture, and widget-background choices.

- [ ] **Step 6: Replace the long inventory with progressive disclosure**

Render:

```swift
Picker("Appearance mode", selection: appearanceModeBinding) {
    Text("Automatic").tag(SettingsAppearanceMode.automatic)
    Text("Manual").tag(SettingsAppearanceMode.manual)
}
.pickerStyle(.segmented)
```

Automatic mode shows the current theme summary and `Re-roll today's theme`. Manual mode shows `Background` followed by a `DisclosureGroup("Canvas ingredients")` containing shapes, fills, and textures. Manual controls are absent in Automatic mode rather than dimmed to 45%.

- [ ] **Step 7: Remove sub-11 pt and fixed user-facing labels**

Replace fixed 9–10 pt labels with `.geist(.caption2)` and other fixed interface text with the closest semantic `.geist(.caption)`, `.geist(.subheadline)`, or `.geist(_:relativeTo:)`. Keep fixed sizing only for decorative preview artwork.

- [ ] **Step 8: Honor Reduce Motion in Appearance**

Read `@Environment(\.accessibilityReduceMotion)` and replace direct springs/move transitions with `motionAnimation` or `withMotionAnimation`. Under Reduce Motion, use opacity-only transitions or no animation.

- [ ] **Step 9: Run unit tests, Appearance UI test, full Settings UI suite, and build**

Expected: no stored-value migration, selected state is spoken, AX layout remains hittable, and Automatic/Manual modes reveal only relevant controls.

- [ ] **Step 10: Commit the Appearance refinement**

```bash
git add StepsTrader/Views/Settings/SettingsHomePresentation.swift StepsTrader/Views/Settings/SettingsComponents.swift StepsTrader/Views/Settings/SettingsAppearancePage.swift StepsTrader/Views/Settings/SettingsWidgetPage.swift StepsTrader/Views/Settings/GradientPreviewSheet.swift Steps4Tests/SettingsHomePresentationTests.swift Steps4UITests/SettingsRedesignUITests.swift
git add -p StepsTrader/Localizable.xcstrings
git diff --cached --check
git diff --cached --name-only
git commit -m "feat: clarify appearance settings modes"
```

---

### Task 5: Make Permissions and Notifications Honest and Recoverable

**Files:**
- Modify: `StepsTrader/Views/SettingsSheet.swift`
- Modify: `StepsTrader/Views/Settings/SettingsPermissionsPage.swift`
- Modify: `StepsTrader/Views/NotificationSettingsView.swift`
- Modify: `Steps4UITests/SettingsRedesignUITests.swift`
- Modify: `StepsTrader/Localizable.xcstrings`

**Interfaces:**
- Consumes: Task 1's presentation types and `AppModel.notificationAuthorizationStatus`.
- Produces: visible authorization status, `Allow notifications`, `Open Settings`, and non-log-only Health errors.

- [ ] **Step 1: Add failing UI tests for neutral Health and denied notifications**

Use deterministic launch arguments to seed `.denied` notifications and a successful zero-value Health query, then assert:

```swift
func testZeroHealthDataDoesNotProduceUrgentWarning() {
    let app = launchSettings(extraArguments: ["ui-testing-health-zero-success"])
    app.buttons["settings.destination.permissions"].tap()
    XCTAssertTrue(app.staticTexts["Connected"].waitForExistence(timeout: 3))
    XCTAssertFalse(app.staticTexts["Health not granted"].exists)
}

func testDeniedNotificationsShowSystemRecoveryAction() {
    let app = launchSettings(extraArguments: ["ui-testing-notifications-denied"])
    app.buttons["settings.destination.notifications"].tap()
    XCTAssertTrue(app.staticTexts["Off in System Settings"].waitForExistence(timeout: 3))
    XCTAssertTrue(app.buttons["Open Settings"].exists)
}
```

Extend `launchSettings` with `extraArguments: [String] = []` and append them to `app.launchArguments`.

- [ ] **Step 2: Run the tests to verify failure**

Expected: the status copy and recovery action do not exist.

- [ ] **Step 3: Drive the Settings home warning from known issues only**

Keep `model.hasPermissionIssues` as the home signal after Task 1 changes it. Ensure `SettingsDestinationCardLabel.warningText` is absent when Health is merely unverified.

- [ ] **Step 4: Render Permissions from presentation state**

Replace `healthVerified = stepsToday > 0 || sleepHours > 0` with `model.hasStepsData || model.hasSleepData`. In the existing `HealthStore`, these flags are set after a successful fetch even when the returned value is zero, so they are the query-success signal rather than a nonzero-data test; do not add a second persisted flag. Render Health's neutral `Check access` without adding it to `missingPermissionCount`. If requestAuthorization throws, show an inline error state with `Try Again` and `Open Settings` where appropriate instead of logging only.

- [ ] **Step 5: Add the notification authorization group**

At the top of Notifications, render the Task 1 state:

- allowed → `Allowed`, no CTA;
- not determined → `Not requested`, `Allow notifications`;
- denied → `Off in System Settings`, `Open Settings`.

Refresh status on `.task` and when returning to the foreground. Keep reminder preferences persisted but add the footer `Reminders will not be delivered until notifications are allowed.` whenever delivery is unavailable.

- [ ] **Step 6: Clarify notification copy and labels**

Replace:

- `1 min before time is over` → `1 minute before access ends`;
- `When the timer is over` → `When access ends`.

Give the DatePicker a real label and change interval controls from `Toggle("")` to labeled Toggle initializers so visible text and accessibility text are the same control.

- [ ] **Step 7: Run the two new UI tests, Settings tests, and build**

Expected: zero Health data is honest, denied notifications have recovery, and the home warning represents only known actionable issues.

- [ ] **Step 8: Commit permission and notification UX**

```bash
git add StepsTrader/Views/SettingsSheet.swift StepsTrader/Views/Settings/SettingsPermissionsPage.swift StepsTrader/Views/NotificationSettingsView.swift Steps4UITests/SettingsRedesignUITests.swift
git add -p StepsTrader/Localizable.xcstrings
git diff --cached --check
git diff --cached --name-only
git commit -m "fix: surface actionable settings status"
```

---

### Task 6: Guard Feed Deletion and Label Inline Controls

**Files:**
- Modify: `StepsTrader/Views/InlineTicketSettingsView.swift`
- Modify: `Steps4UITests/SettingsRedesignUITests.swift`
- Modify: `StepsTrader/Localizable.xcstrings`

**Interfaces:**
- Preserves: `onAfterDelete` and `model.deleteTicketGroup(_:)`.
- Produces: `settings.feed.delete`, a named confirmation dialog, and labeled interval toggles.

- [ ] **Step 1: Add a failing destructive confirmation UI test**

Seed a deterministic Feed through `ui-testing-ticket-settings`, open its existing settings sheet, then assert:

```swift
func testDeletingFeedRequiresConfirmation() {
    let app = launchTicketSettings()
    app.buttons["settings.feed.delete"].tap()
    XCTAssertTrue(app.sheets["Delete Study?"].waitForExistence(timeout: 3))
    XCTAssertTrue(app.buttons["Cancel"].exists)
    XCTAssertTrue(app.buttons["Delete Feed"].exists)
    app.buttons["Cancel"].tap()
    XCTAssertTrue(app.staticTexts["Study"].exists)
}
```

- [ ] **Step 2: Run the test to verify failure**

Expected: deletion occurs immediately or the confirmation sheet is absent.

- [ ] **Step 3: Add confirmation state without changing store behavior**

Add `@State private var showDeleteConfirmation = false`. The row sets it to true. The destructive confirmation action captures `group.id`, calls `model.deleteTicketGroup(groupId)`, and only then calls `onAfterDelete?()`.

Use:

```swift
.confirmationDialog(
    String(localized: "Delete \(group.name.isEmpty ? "Feed" : group.name)?"),
    isPresented: $showDeleteConfirmation,
    titleVisibility: .visible
) {
    Button(String(localized: "Delete Feed"), role: .destructive) { confirmDelete() }
    Button(String(localized: "Cancel"), role: .cancel) {}
} message: {
    Text(String(localized: "This removes the Feed and its access options. This action cannot be undone."))
}
```

- [ ] **Step 4: Label the interval toggles and honor Reduce Motion**

Make `interval.displayName` the Toggle label instead of rendering a sibling `Text` beside `Toggle("")`. Replace the expansion animation and move transition with the existing Reduce Motion helpers.

- [ ] **Step 5: Run the confirmation UI test and build**

Expected: Cancel preserves the Feed, destructive confirmation removes it, and each interval is announced as one toggle with its current state.

- [ ] **Step 6: Commit the destructive-action fix**

```bash
git add StepsTrader/Views/InlineTicketSettingsView.swift Steps4UITests/SettingsRedesignUITests.swift
git add -p StepsTrader/Localizable.xcstrings
git diff --cached --check
git diff --cached --name-only
git commit -m "fix: confirm feed deletion"
```

---

### Task 7: Clarify Wallpaper, Account Errors, and Remove the Duplicate Day Reset Page

**Files:**
- Modify: `StepsTrader/Views/Settings/SettingsShortcutPage.swift`
- Modify: `StepsTrader/Views/Settings/SettingsAccountPage.swift`
- Delete: `StepsTrader/Views/DayEndSettingsView.swift`
- Modify: `Steps4.xcodeproj/project.pbxproj`
- Modify: `Steps4UITests/SettingsRedesignUITests.swift`
- Modify: `StepsTrader/Localizable.xcstrings`

**Interfaces:**
- Preserves: `SettingsWallpaperControls`, the shortcut URL, `SettingsEnergyPage` as the sole day-boundary destination, and account deletion behavior.

- [ ] **Step 1: Prove the legacy DayEnd page has no production caller**

```bash
rg -n 'DayEndSettingsView\(' StepsTrader --glob '*.swift'
```

Expected: only its own Preview. If any production caller appears, replace that route with `SettingsEnergyPage` before deleting the file.

- [ ] **Step 2: Add failing Wallpaper hierarchy coverage**

```swift
func testWallpaperOffersInstallBeforeOptionalInstructions() {
    let app = launchSettings()
    app.buttons["settings.destination.widgetsWallpaper"].tap()
    app.swipeUp()
    let install = app.buttons["settings.wallpaper.install"]
    let instructions = app.buttons["settings.wallpaper.instructions"]
    XCTAssertTrue(install.waitForExistence(timeout: 3))
    XCTAssertTrue(instructions.exists)
    XCTAssertLessThan(install.frame.minY, instructions.frame.minY)
}
```

- [ ] **Step 3: Put the CTA before an expandable checklist**

Give `Get Wallpaper Shortcut` identifier `settings.wallpaper.install`. Place it before a `DisclosureGroup` identified as `settings.wallpaper.instructions`; title the disclosure `Setup in Shortcuts`. Keep the five existing steps inside it, but replace step 1 with `Install the Nowhere wallpaper shortcut.` because the button is now above the list.

- [ ] **Step 4: Map account failures to stable user copy**

Do not surface raw `error.localizedDescription`. Use a local presentation function that returns:

- `We couldn't delete your account. Check your connection and try again.` for deletion;
- `We couldn't save your profile. Your previous details are still intact.` for profile saving;
- `Something went wrong. Please try again.` as the fallback.

Preserve the underlying error in `AppLogger` for diagnostics.

- [ ] **Step 5: Remove the dead duplicate DayEnd page**

Delete `DayEndSettingsView.swift` and remove only its file reference and Sources entry from the Xcode project. Confirm `SettingsEnergyPage` still owns `DayResetTimePicker` and calls `AppModel.updateDayEnd`.

- [ ] **Step 6: Run Wallpaper UI coverage, Settings tests, build, and the full test target that covers day-boundary persistence**

Expected: Wallpaper CTA appears first, account recovery copy is stable, no production route references the deleted type, and custom-day behavior is unchanged.

- [ ] **Step 7: Commit the clarity and cleanup pass**

```bash
git add StepsTrader/Views/Settings/SettingsShortcutPage.swift StepsTrader/Views/Settings/SettingsAccountPage.swift Steps4UITests/SettingsRedesignUITests.swift
git rm StepsTrader/Views/DayEndSettingsView.swift
git add -p Steps4.xcodeproj/project.pbxproj StepsTrader/Localizable.xcstrings
git diff --cached --check
git diff --cached --name-only
git commit -m "refactor: simplify settings recovery flows"
```

---

### Task 8: Complete the Accessibility and Visual Verification Matrix

**Files:**
- Modify: `Steps4UITests/SettingsRedesignUITests.swift`
- Modify only if failures require it: files changed in Tasks 2–7

**Interfaces:**
- Produces: repeatable evidence for default, accessibility, contrast, motion, and both color schemes.

- [ ] **Step 1: Add one parameterized launch helper**

Extend the UI-test helper to accept content size, appearance, Reduce Motion, and Increase Contrast launch configuration. Keep defaults equal to the existing deterministic English fixture.

- [ ] **Step 2: Add the final accessibility smoke test**

```swift
func testSettingsCriticalFlowAtAccessibilitySize() {
    let app = launchSettings(
        contentSizeCategory: "UICTContentSizeCategoryAccessibilityM",
        extraArguments: ["ui-testing-reduce-motion", "ui-testing-increase-contrast"]
    )
    let yourDay = app.buttons["settings.yourDay"]
    XCTAssertTrue(yourDay.waitForExistence(timeout: 3))
    XCTAssertTrue(yourDay.isHittable)
    assertMinimumHitTarget(yourDay)

    app.buttons["settings.destination.appearance"].tap()
    XCTAssertTrue(app.navigationBars["Appearance"].waitForExistence(timeout: 3))
    XCTAssertTrue(app.segmentedControls.buttons["Automatic"].isHittable)
    XCTAssertTrue(app.segmentedControls.buttons["Manual"].isHittable)
}
```

Use direct frame and hittability assertions for named critical controls. Verify the Caption 2 typography floor through source inspection and the Simulator visual matrix; XCUITest does not expose a reliable font-size property.

- [ ] **Step 3: Run the complete automated verification set**

Run the build, focused unit tests, Settings UI tests, and existing tests for preferences, notifications, day-boundary behavior, and BlockingStore deletion. Expected: all pass with no app-terminated failures.

- [ ] **Step 4: Capture the bounded Simulator matrix**

Capture Settings home, Appearance Manual, Notifications denied, Permissions neutral Health, and Feed delete confirmation in:

1. Dark / default text;
2. Light / default text;
3. Dark / Accessibility M;
4. Dark / Increase Contrast + Reduce Motion.

Inspect once for clipping, unintended gradient competition, selected state, row height, safe areas, and destructive hierarchy. Fix all observed defects in one batch, then confirm with one final matrix pass.

- [ ] **Step 5: Perform the hardware-only checks**

On a physical iPhone, verify the system edge-swipe, horizontal Appearance carousels, sheet Close action, haptics, and Reduce Motion posture. Record any hardware-only issue in the commit message body or follow-up issue; do not claim hardware verification from Simulator evidence.

- [ ] **Step 6: Commit verification coverage and any bounded fixes**

```bash
git add Steps4UITests/SettingsRedesignUITests.swift
git add -p StepsTrader Steps4Tests StepsTrader/Localizable.xcstrings
git diff --cached --check
git diff --cached --name-only
git commit -m "test: verify native settings accessibility"
```

---

## Completion Criteria

- Settings home retains its current information hierarchy and product character.
- Root Settings has a visible Close action; all destinations use system Back and edge-swipe behavior.
- Horizontal Appearance interactions cannot dismiss the page.
- Health zero/no-sample states never create a false urgent permission warning.
- Notifications disclose actual system delivery status and provide the correct recovery action.
- Appearance exposes Automatic/Manual hierarchy, scalable labels, non-color selected state, and VoiceOver semantics.
- Feed deletion cannot occur without explicit confirmation.
- Wallpaper offers installation before optional instructions.
- No reachable settings control is below 44×44 pt and no user-facing label is below the semantic Caption 2 floor.
- Light, Dark, Accessibility M, Increase Contrast, and Reduce Motion checks pass in Simulator; hardware-only checks are reported separately.
