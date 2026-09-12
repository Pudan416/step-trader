# Settings Information Architecture Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the flat Settings list with the approved card-based hub, make daily goals available without authentication, and reduce Account to identity, automatic sync status, sign out, and deletion.

**Architecture:** Keep existing `AppStorage`, `AppModel`, authentication, and Supabase behavior as the source of truth. Add a small pure presentation layer for summary formatting and responsive layout, focused reusable Settings card labels, a signed-in Account destination, a combined Widgets & wallpaper destination, and a DEBUG-only Developer destination. `SettingsSheet` remains the navigation owner and composes those pieces without taking over their business logic.

**Tech Stack:** Swift 6, SwiftUI, `UserDefaults`/`@AppStorage`, existing `AuthenticationService` and `SupabaseSyncService`, XCTest, XCUITest, iOS Simulator.

**Spec:** `docs/superpowers/specs/2026-08-24-settings-information-architecture-design.md`

## Global Constraints

- Daily step goal, sleep goal, and custom-day boundary are editable while signed out. No authentication guard may be introduced around `SettingsEnergyPage`.
- Account sync is automatic and read-only in the UI. Do not add a sync toggle, manual sync button, `Up to date`, or `Last synced` claim.
- Do not change the existing server/local conflict policy, Supabase payloads, preference keys, energy formulas, or custom-day semantics.
- All custom-day writes continue through `AppModel.updateDayEnd(hour:minute:)`; do not directly write the hour/minute from picker callbacks.
- Preserve the individual Widget and Wallpaper destinations used by feature-tip deep links. The new combined page composes their controls without inserting an intermediate menu.
- Generated mockups are design references only and must not be added as app assets.
- Reuse the existing energy-gradient background, `AppTheme` colors, `MattePressStyle`, `DetailHeader`, `DetailDivider`, and Settings typography.
- New cards have one accessibility element, a minimum 44-point hit target, and no color-only status. At accessibility Dynamic Type sizes the two-column grid becomes one column.
- New user-facing strings use `String(localized:comment:)` or `LocalizedStringKey`; number, duration, and time output use locale-aware formatters.
- Preserve all unrelated working-tree changes. Never use `git add .`, `git add -A`, or `git commit -a`. Before every commit, run `git diff --cached --check` and inspect `git diff --cached --name-only`.
- New Swift files require explicit `PBXFileReference`, `PBXBuildFile`, group membership, and Sources build-phase entries in `Steps4.xcodeproj/project.pbxproj`. Stage only the new-file registration hunks with `git add -p` if that project file acquires unrelated edits.
- Any manual simulator run uses the `ui-testing` launch argument so permission prompts do not swallow taps.
- Focused build command:

  ```bash
  xcodebuild build -project Steps4.xcodeproj -scheme Steps4 -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17,OS=latest' CODE_SIGNING_ALLOWED=NO
  ```

- Focused unit-test command:

  ```bash
  xcodebuild test -project Steps4.xcodeproj -scheme Steps4 -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17,OS=latest' -only-testing:Steps4Tests/SettingsHomePresentationTests CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO
  ```

- Focused UI-test command:

  ```bash
  xcodebuild test -project Steps4.xcodeproj -scheme Steps4 -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17,OS=latest' -only-testing:Steps4UITests/SettingsRedesignUITests CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO
  ```

---

## File Map

### Create

- `StepsTrader/Views/Settings/SettingsHomePresentation.swift` — pure account/summary presentation values, locale-aware formatting, and responsive column count.
- `StepsTrader/Views/Settings/SettingsHomeCards.swift` — reusable visual labels for account, Your day, destination, and information cards.
- `StepsTrader/Views/Settings/SettingsAccountPage.swift` — signed-in identity, automatic-sync explanation, sign out, and deletion.
- `StepsTrader/Views/Settings/SettingsWidgetsWallpaperPage.swift` — one scroll surface composing widget and wallpaper controls.
- `StepsTrader/Views/Settings/SettingsDeveloperPage.swift` — DEBUG-only home for the existing diagnostics.
- `Steps4Tests/SettingsHomePresentationTests.swift` — pure presentation and responsive-layout tests.
- `Steps4UITests/SettingsRedesignUITests.swift` — signed-out navigation, hierarchy, combined destination, and accessibility smoke tests.

### Modify

- `StepsTrader/Views/SettingsSheet.swift` — replace the flat sections with the card hub and route each card.
- `StepsTrader/Views/Settings/SettingsEnergyPage.swift` — rename to `Your day` and expose stable accessibility identifiers.
- `StepsTrader/Views/ProfileEditorView.swift` — keep identity editing only; remove daily preferences and account actions.
- `StepsTrader/Views/MeViewSupport.swift` — update the profile-editor initializer after removing its `AppModel` dependency.
- `StepsTrader/Views/Settings/SettingsWidgetPage.swift` — extract reusable widget controls while preserving the standalone page.
- `StepsTrader/Views/Settings/SettingsShortcutPage.swift` — extract reusable wallpaper controls while preserving the standalone page.
- `StepsTrader/Views/Settings/SettingsComponents.swift` — add the shared matte card surface and grouped-card styling tokens.
- `StepsTrader/StepsTraderApp.swift` — seed deterministic Your day values only for the Settings UI-test fixture.
- `StepsTrader/Localizable.xcstrings` — accept Xcode-extracted source keys if extraction updates the catalog; do not rewrite unrelated entries.
- `Steps4.xcodeproj/project.pbxproj` — register new production and test sources.

---

### Task 1: Add Pure Settings Presentation Values

**Files:**
- Create: `StepsTrader/Views/Settings/SettingsHomePresentation.swift`
- Create: `Steps4Tests/SettingsHomePresentationTests.swift`
- Modify: `Steps4.xcodeproj/project.pbxproj`

**Interfaces:**
- Consumes: `AppUser`, `DynamicTypeSize`, `Locale`, `Calendar`, `TimeZone`.
- Produces: `SettingsAccountPresentation`, `SettingsYourDaySummary`, and `SettingsGridLayout.columnCount(for:)` for all later UI tasks.

- [ ] **Step 1: Write the failing presentation tests**

  Create `SettingsHomePresentationTests.swift` with deterministic locale and time-zone coverage:

  ```swift
  import SwiftUI
  import XCTest
  @testable import Steps4

  final class SettingsHomePresentationTests: XCTestCase {
      private let enUS = Locale(identifier: "en_US")
      private let utc = TimeZone(secondsFromGMT: 0)!

      func testYourDaySummaryFormatsCurrentTargets() {
          let summary = SettingsYourDaySummary(
              stepsTarget: 10_000,
              sleepTargetHours: 8,
              dayEndHour: 0,
              dayEndMinute: 0
          )

          XCTAssertEqual(summary.stepsText(locale: enUS), "10,000")
          XCTAssertEqual(summary.sleepText(locale: enUS), "8 h")
          XCTAssertEqual(
              summary.dayStartText(locale: enUS, timeZone: utc)
                  .replacingOccurrences(of: "\u{202F}", with: " "),
              "12:00 AM"
          )
      }

      func testYourDaySummaryClampsInvalidBoundaryComponents() {
          let summary = SettingsYourDaySummary(
              stepsTarget: -1,
              sleepTargetHours: -1,
              dayEndHour: 27,
              dayEndMinute: -4
          )

          XCTAssertEqual(summary.stepsTarget, 0)
          XCTAssertEqual(summary.sleepTargetHours, 0)
          XCTAssertEqual(summary.dayStartMinutes, 23 * 60)
      }

      func testAccountInitialsUseAtMostTwoWords() {
          XCTAssertEqual(SettingsAccountPresentation.initials(for: "Konstantin Pudan"), "KP")
          XCTAssertEqual(SettingsAccountPresentation.initials(for: "Konstantin"), "KO")
          XCTAssertEqual(SettingsAccountPresentation.initials(for: "  "), "U")
      }

      func testAccessibilityTypeUsesOneGridColumn() {
          XCTAssertEqual(SettingsGridLayout.columnCount(for: .large), 2)
          XCTAssertEqual(SettingsGridLayout.columnCount(for: .accessibility1), 1)
          XCTAssertEqual(SettingsGridLayout.columnCount(for: .accessibility5), 1)
      }
  }
  ```

- [ ] **Step 2: Register the new files and verify the tests fail**

  Add both files to the correct groups and Sources phases in `project.pbxproj`, then run the focused unit-test command. Expected: compile failure because `SettingsYourDaySummary`, `SettingsAccountPresentation`, and `SettingsGridLayout` do not exist.

- [ ] **Step 3: Implement the pure presentation types**

  Create `SettingsHomePresentation.swift` with these exact public-to-module shapes:

  ```swift
  import Foundation
  import SwiftUI

  enum SettingsAccountPresentation: Equatable {
      case signedOut
      case signedIn(displayName: String, initials: String, avatarData: Data?)

      static func initials(for displayName: String) -> String {
          let words = displayName.split(whereSeparator: \Character.isWhitespace)
          guard !words.isEmpty else { return "U" }
          if words.count == 1 {
              return String(words[0].prefix(2)).uppercased()
          }
          return words.prefix(2).compactMap(\.first).map(String.init).joined().uppercased()
      }
  }

  struct SettingsYourDaySummary: Equatable {
      let stepsTarget: Int
      let sleepTargetHours: Double
      let dayStartMinutes: Int

      init(stepsTarget: Double, sleepTargetHours: Double, dayEndHour: Int, dayEndMinute: Int) {
          self.stepsTarget = max(0, Int(stepsTarget.rounded()))
          self.sleepTargetHours = max(0, sleepTargetHours)
          self.dayStartMinutes = min(max(dayEndHour, 0), 23) * 60
              + min(max(dayEndMinute, 0), 59)
      }

      func stepsText(locale: Locale = .current) -> String {
          stepsTarget.formatted(.number.locale(locale))
      }

      func sleepText(locale: Locale = .current) -> String {
          let hours = sleepTargetHours.formatted(
              .number.locale(locale).precision(.fractionLength(0...1))
          )
          return String(localized: "\(hours) h", comment: "Settings Your day – sleep target summary")
      }

      func dayStartText(locale: Locale = .current, timeZone: TimeZone = .current) -> String {
          var calendar = Calendar(identifier: .gregorian)
          calendar.timeZone = timeZone
          let date = calendar.date(
              from: DateComponents(year: 2001, month: 1, day: 1,
                                   hour: dayStartMinutes / 60,
                                   minute: dayStartMinutes % 60)
          )!
          return date.formatted(
              Date.FormatStyle(date: .omitted, time: .shortened)
                  .locale(locale)
                  .timeZone(timeZone)
          )
      }
  }

  enum SettingsGridLayout {
      static func columnCount(for dynamicTypeSize: DynamicTypeSize) -> Int {
          dynamicTypeSize.isAccessibilitySize ? 1 : 2
      }
  }
  ```

- [ ] **Step 4: Run the focused tests and build**

  Run the focused unit-test command, then the focused build command. Expected: four tests pass and the application target builds.

- [ ] **Step 5: Commit the presentation layer**

  ```bash
  git add StepsTrader/Views/Settings/SettingsHomePresentation.swift Steps4Tests/SettingsHomePresentationTests.swift
  git add -p Steps4.xcodeproj/project.pbxproj
  git diff --cached --check
  git commit -m "test: define settings home presentation"
  ```

---

### Task 2: Make Your Day the Only Home for Daily Preferences

**Files:**
- Modify: `StepsTrader/Views/Settings/SettingsEnergyPage.swift:3-148`
- Modify: `StepsTrader/Views/ProfileEditorView.swift:3-316`
- Modify: `StepsTrader/Views/SettingsSheet.swift:45-69`
- Modify: `StepsTrader/Views/MeViewSupport.swift:741-748`
- Modify: `StepsTrader/StepsTraderApp.swift:124-140`
- Create: `Steps4UITests/SettingsRedesignUITests.swift`
- Modify: `Steps4.xcodeproj/project.pbxproj`

**Interfaces:**
- Consumes: existing `SharedKeys.userStepsTarget`, `SharedKeys.userSleepTarget`, `SharedKeys.dayEndHour`, `SharedKeys.dayEndMinute`, and `AppModel.updateDayEnd`.
- Produces: authentication-independent `SettingsEnergyPage` navigation and `ProfileEditorView(authService:)` containing identity editing only.

- [ ] **Step 1: Write the failing signed-out navigation test**

  Create `SettingsRedesignUITests.swift`:

  ```swift
  import XCTest

  final class SettingsRedesignUITests: XCTestCase {
      override func setUpWithError() throws { continueAfterFailure = false }

      private func launchSettings() -> XCUIApplication {
          let app = XCUIApplication()
          app.launchArguments = [
              "ui-testing", "ui-testing-settings",
              "-AppleLanguages", "(en)", "-AppleLocale", "en_US"
          ]
          app.launch()
          XCTAssertTrue(app.buttons["tab_me"].waitForExistence(timeout: 10))
          app.buttons["tab_me"].tap()
          XCTAssertTrue(app.buttons["me_settings_button"].waitForExistence(timeout: 5))
          app.buttons["me_settings_button"].tap()
          XCTAssertTrue(app.staticTexts["Settings"].waitForExistence(timeout: 5))
          return app
      }

      func testYourDayIsAvailableWithoutOpeningLogin() {
          let app = launchSettings()

          let yourDay = app.buttons["settings.yourDay"]
          XCTAssertTrue(yourDay.waitForExistence(timeout: 3))
          yourDay.tap()

          XCTAssertTrue(app.staticTexts["Your day"].waitForExistence(timeout: 3))
          XCTAssertTrue(app.otherElements["settings.yourDay.steps"].exists)
          XCTAssertTrue(app.otherElements["settings.yourDay.sleep"].exists)
          XCTAssertTrue(app.otherElements["settings.yourDay.boundary"].exists)
          XCTAssertFalse(app.staticTexts["Sign in to continue"].exists)
      }
  }
  ```

- [ ] **Step 2: Register and run the UI test to verify failure**

  Register the UI-test source in `project.pbxproj` and run the focused UI-test command. Expected: failure because `settings.yourDay` is absent from the home screen.

- [ ] **Step 3: Seed deterministic Settings values in UI-test mode**

  In `StepsTraderApp.init()`, add a fixture guarded only by `ui-testing-settings`:

  ```swift
  if ProcessInfo.processInfo.arguments.contains("ui-testing-settings") {
      let defaults = UserDefaults.stepsTrader()
      defaults.set(10_000.0, forKey: SharedKeys.userStepsTarget)
      defaults.set(8.0, forKey: SharedKeys.userSleepTarget)
      defaults.set(0, forKey: SharedKeys.dayEndHour)
      defaults.set(0, forKey: SharedKeys.dayEndMinute)
  }
  ```

  Do not clear authentication or any unrelated defaults.

- [ ] **Step 4: Expose Your day from the current Settings list**

  Before the later card redesign, add a `NavigationLink` at the top of the current General section:

  ```swift
  flatRow(icon: "figure.walk", title: String(localized: "Your day")) {
      SettingsEnergyPage(model: model)
  }
  .accessibilityIdentifier("settings.yourDay")
  ```

  Keep this temporary row compiling until Task 6 replaces the entire home layout.

- [ ] **Step 5: Rename and identify the detail controls**

  In `SettingsEnergyPage`, change the `DetailHeader` title from `Limits` to `Your day`. Add identifiers to the three section containers:

  ```swift
  .accessibilityIdentifier("settings.yourDay.steps")
  .accessibilityIdentifier("settings.yourDay.sleep")
  .accessibilityIdentifier("settings.yourDay.boundary")
  ```

  Do not alter either goal callback or the `model.updateDayEnd` callback.

- [ ] **Step 6: Strip non-profile content from `ProfileEditorView`**

  Remove its `model` property, all four daily `@AppStorage` properties, `allowedBedtimeMinutes`, `bedtimeMinutes`, the three Daily Goals sections, the sign-out section, the delete-account section, `showDeleteConfirmation`, `isDeleting`, `syncBedtimeFromStorage()`, and `performAccountDeletion()`.

  Keep the photo, nickname, read-only email, Save/Cancel, photo alert, save alert, and `saveProfileAsync()` behavior. The initializer becomes:

  ```swift
  ProfileEditorView(authService: AuthenticationService.shared)
  ```

  Change `.onAppear` to call only `loadCurrentProfile()`, and update the Me sheet call to `ProfileEditorView(authService: authService)`.

- [ ] **Step 7: Run the focused UI test and build**

  Run the focused UI-test command and focused build. Expected: the signed-out path reaches all three controls and no profile call site references the removed model parameter.

- [ ] **Step 8: Commit the Your day separation**

  ```bash
  git add StepsTrader/Views/Settings/SettingsEnergyPage.swift StepsTrader/Views/ProfileEditorView.swift StepsTrader/Views/SettingsSheet.swift StepsTrader/Views/MeViewSupport.swift StepsTrader/StepsTraderApp.swift Steps4UITests/SettingsRedesignUITests.swift
  git add -p Steps4.xcodeproj/project.pbxproj
  git diff --cached --check
  git commit -m "feat: make daily settings available without login"
  ```

---

### Task 3: Build the Signed-In Account Destination

**Files:**
- Create: `StepsTrader/Views/Settings/SettingsAccountPage.swift`
- Modify: `StepsTrader/Views/SettingsSheet.swift:214-287`
- Modify: `StepsTrader/Views/ProfileEditorView.swift`
- Modify: `Steps4.xcodeproj/project.pbxproj`

**Interfaces:**
- Consumes: `AuthenticationService.currentUser`, `AuthenticationService.signOut()`, `AuthenticationService.deleteAccount()`, and `ProfileEditorView(authService:)` from Task 2.
- Produces: `SettingsAccountPage(authService:model:)` for the signed-in account card.

- [ ] **Step 1: Add failing source-level account tests**

  Extend `SettingsHomePresentationTests`:

  ```swift
  func testSignedInPresentationCarriesIdentityButNoSyncControl() {
      let state = SettingsAccountPresentation.signedIn(
          displayName: "Konstantin",
          initials: "KO",
          avatarData: nil
      )
      XCTAssertEqual(
          state,
          .signedIn(displayName: "Konstantin", initials: "KO", avatarData: nil)
      )
  }
  ```

  Run the focused unit test. It should compile and pass; this locks the presentation interface before the view is wired.

- [ ] **Step 2: Create the Account page shell and sections**

  Implement `SettingsAccountPage` with this state and action boundary:

  ```swift
  struct SettingsAccountPage: View {
      @ObservedObject var authService: AuthenticationService
      @ObservedObject var model: AppModel
      @Environment(\.dismiss) private var dismiss
      @State private var showProfileEditor = false
      @State private var showDeleteConfirmation = false
      @State private var isDeleting = false
      @State private var errorMessage: String?
  }
  ```

  Its scroll content is ordered as:

  1. `DetailHeader(title: "Account")`.
  2. Avatar, display name, and `Edit profile` button that presents `ProfileEditorView(authService:)`.
  3. `PROFILE` card with display name and read-only email.
  4. `SYNC` card with `Automatic sync` / `On` and footer `Settings and history sync automatically across your devices.`; render `On` as text, never `Toggle`.
  5. `ACCOUNT` card with `Sign out`.
  6. `DANGER ZONE` card with coral `Delete account`.

  Give the sync row `settings.account.automaticSync`, sign-out button `settings.account.signOut`, and delete button `settings.account.delete`.

- [ ] **Step 3: Move session and destructive actions into Account**

  Sign out must call `authService.signOut()` and then `dismiss()`. Deletion must keep the existing confirmation copy and implementation:

  ```swift
  @MainActor
  private func performAccountDeletion() async {
      isDeleting = true
      do {
          try await authService.deleteAccount()
          dismiss()
      } catch {
          errorMessage = error.localizedDescription
          isDeleting = false
      }
  }
  ```

  Present errors with the same localized `Error` / `OK` alert pattern currently used by `ProfileEditorView`.

- [ ] **Step 4: Route the current signed-in account row to the Account page**

  Replace the signed-in `Button { showProfileEditor = true }` in `SettingsSheet` with a `NavigationLink` whose destination is:

  ```swift
  SettingsAccountPage(authService: authService, model: model)
  ```

  Keep signed-out behavior opening `LoginView` directly. Remove `showProfileEditor` and its sheet from `SettingsSheet`.

- [ ] **Step 5: Build and manually exercise account actions**

  Run the focused build. In a signed-in simulator session, verify Edit profile opens the existing editor, automatic sync has no switch, Sign out returns to signed-out Settings, and Delete account still requires confirmation. Do not complete deletion against a non-test account.

- [ ] **Step 6: Commit the account destination**

  ```bash
  git add StepsTrader/Views/Settings/SettingsAccountPage.swift StepsTrader/Views/SettingsSheet.swift StepsTrader/Views/ProfileEditorView.swift Steps4Tests/SettingsHomePresentationTests.swift
  git add -p Steps4.xcodeproj/project.pbxproj
  git diff --cached --check
  git commit -m "feat: separate account and automatic sync settings"
  ```

---

### Task 4: Combine Widgets and Wallpaper Without Breaking Deep Links

**Files:**
- Create: `StepsTrader/Views/Settings/SettingsWidgetsWallpaperPage.swift`
- Modify: `StepsTrader/Views/Settings/SettingsWidgetPage.swift:4-174`
- Modify: `StepsTrader/Views/Settings/SettingsShortcutPage.swift:3-104`
- Modify: `StepsTrader/Views/SettingsSheet.swift:69-77`
- Modify: `Steps4UITests/SettingsRedesignUITests.swift`
- Modify: `Steps4.xcodeproj/project.pbxproj`

**Interfaces:**
- Consumes: existing widget-background `@AppStorage`, wallpaper thumbnail lookup, `WidgetCenter.reloadAllTimelines()`, and `AppConstants.URLs.wallpaperShortcut`.
- Produces: reusable `SettingsWidgetControls`, `SettingsWallpaperControls`, and `SettingsWidgetsWallpaperPage(model:)` while preserving `SettingsWidgetPage` and `SettingsShortcutPage`.

- [ ] **Step 1: Write the failing combined-destination UI test**

  Add to `SettingsRedesignUITests`:

  ```swift
  func testWidgetsAndWallpaperShareOneDetailPage() {
      let app = launchSettings()
      let combined = app.buttons["settings.destination.widgetsWallpaper"]
      XCTAssertTrue(combined.waitForExistence(timeout: 3))
      combined.tap()

      XCTAssertTrue(app.staticTexts["Widgets & wallpaper"].waitForExistence(timeout: 3))
      XCTAssertTrue(app.otherElements["settings.widgets.controls"].exists)
      app.swipeUp()
      XCTAssertTrue(app.otherElements["settings.wallpaper.controls"].exists)
  }
  ```

  Run the focused UI test. Expected: failure because the combined destination does not exist.

- [ ] **Step 2: Extract widget controls from their page shell**

  Move `backgroundMode`, `wallpaperThumbnail`, `wallpaperStatus`, `bgCard`, the background picker, and the configuration hint into:

  ```swift
  struct SettingsWidgetControls: View {
      @Environment(\.appTheme) private var theme
      @AppStorage(
          SharedKeys.widgetBackgroundMode,
          store: UserDefaults(suiteName: SharedKeys.appGroupId)
      ) private var backgroundMode: String = "basic"

      var body: some View {
          VStack(alignment: .leading, spacing: 20) {
              VStack(alignment: .leading, spacing: 0) {
                  SettingsSectionLabel(text: String(localized: "Background"))
                      .padding(.bottom, 12)
                  HStack(spacing: 12) {
                      bgCard(title: String(localized: "Solid"),
                             isSelected: backgroundMode == "basic",
                             value: "basic") {
                          RoundedRectangle(cornerRadius: 8)
                              .fill(Color(red: 0x22/255, green: 0x28/255, blue: 0x31/255))
                      }
                      bgCard(title: String(localized: "Wallpaper"),
                             isSelected: backgroundMode == "wallpaper",
                             value: "wallpaper") {
                          wallpaperPreview
                      }
                  }
                  if backgroundMode == "wallpaper" {
                      DetailDivider()
                      wallpaperStatus.padding(.vertical, 12)
                  }
              }
              HStack(alignment: .top, spacing: 10) {
                  Image(systemName: "hand.tap").frame(width: 24)
                  Text(String(localized: "Long-press the widget → Edit to choose which group to display."))
                      .font(.caption)
                      .foregroundStyle(theme.adaptiveSecondaryText)
              }
          }
      }
  }
  ```

  Move the current thumbnail lookup into `wallpaperPreview`, and move the
  current `wallpaperStatus` and `bgCard` implementations without changing their
  image loading, selection animation, or colors. Attach
  `.onChange(of: backgroundMode) { WidgetCenter.shared.reloadAllTimelines() }`,
  sensory feedback, and `settings.widgets.controls` to this component.
  `SettingsWidgetPage` remains a background + scroll +
  `DetailHeader("Widget")` wrapper around `SettingsWidgetControls()`.

- [ ] **Step 3: Extract wallpaper controls from their page shell**

  Move `shortcutURL`, setup steps, description, numbered instructions, and CTA into:

  ```swift
  struct SettingsWallpaperControls: View {
      @Environment(\.openURL) private var openURL
      @Environment(\.appTheme) private var theme

      private let shortcutURL = AppConstants.URLs.wallpaperShortcut
      private let steps: [(number: String, text: LocalizedStringKey)] = [
          ("1", "Tap the button below to add the wallpaper shortcut"),
          ("2", "Open Shortcuts → Automation → +"),
          ("3", "Choose App → select Nowhere → pick \"Is Closed\""),
          ("4", "Set the action to the wallpaper shortcut"),
          ("5", "Turn off \"Ask Before Running\""),
      ]

      var body: some View {
          VStack(alignment: .leading, spacing: 20) {
              VStack(alignment: .leading, spacing: 12) {
                  Label(String(localized: "Auto-wallpaper"), systemImage: "sparkles")
                      .font(.subheadline.weight(.semibold))
                  Text(String(localized: "Set today's energy canvas as your Lock Screen wallpaper automatically each time you close the app."))
                      .font(.subheadline)
                      .foregroundStyle(theme.adaptiveSecondaryText)
              }
              VStack(alignment: .leading, spacing: 0) {
                  SettingsSectionLabel(text: String(localized: "Setup"))
                      .padding(.bottom, 10)
                  ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                      if index > 0 { DetailDivider() }
                      HStack(alignment: .top, spacing: 12) {
                          Text(step.number)
                              .font(.caption.weight(.bold).monospacedDigit())
                              .frame(width: 20, height: 20)
                              .background(Circle().fill(AppColors.brandAccent.opacity(0.15)))
                          Text(step.text)
                              .font(.subheadline)
                              .foregroundStyle(theme.adaptiveSecondaryText)
                      }
                      .padding(.vertical, 10)
                  }
              }
              Button { openURL(shortcutURL) } label: {
                  Label(String(localized: "Get Wallpaper Shortcut"),
                        systemImage: "square.and.arrow.down")
                      .font(.subheadline.weight(.semibold))
                      .foregroundStyle(AppAccentInk.primary)
                      .frame(maxWidth: .infinity)
                      .padding(.vertical, 14)
                      .background(Capsule().fill(AppColors.brandAccent))
              }
              .buttonStyle(MattePressStyle())
          }
      }
  }
  ```

  Attach `settings.wallpaper.controls`. `SettingsShortcutPage` remains a wrapper with `DetailHeader("Wallpaper")` around `SettingsWallpaperControls()`.

- [ ] **Step 4: Compose the combined page**

  Create `SettingsWidgetsWallpaperPage(model:)` using the standard Settings detail shell:

  ```swift
  ZStack {
      SettingsGradientBG(model: model)
      ScrollView {
          VStack(alignment: .leading, spacing: 28) {
              DetailHeader(title: String(localized: "Widgets & wallpaper"))
              SettingsSectionLabel(text: String(localized: "Widget"))
              SettingsWidgetControls()
              DetailDivider()
              SettingsSectionLabel(text: String(localized: "Wallpaper"))
              SettingsWallpaperControls()
          }
          .padding(.horizontal, 16)
          .padding(.bottom, 80)
      }
  }
  ```

  Apply the existing top inset, hidden navigation bar, and swipe-back modifier.

- [ ] **Step 5: Replace the two current home rows with one destination**

  In the pre-card Settings home, replace Wallpaper and Widget rows with one row titled `Widgets & wallpaper`, destination `SettingsWidgetsWallpaperPage(model:)`, and identifier `settings.destination.widgetsWallpaper`. Leave `featureTipRoute` mapping unchanged so tips still reach the standalone pages.

- [ ] **Step 6: Run the focused UI test and build**

  Expected: both component identifiers exist on the same scroll page; standalone feature-tip destinations still compile.

- [ ] **Step 7: Commit the combined destination**

  ```bash
  git add StepsTrader/Views/Settings/SettingsWidgetsWallpaperPage.swift StepsTrader/Views/Settings/SettingsWidgetPage.swift StepsTrader/Views/Settings/SettingsShortcutPage.swift StepsTrader/Views/SettingsSheet.swift Steps4UITests/SettingsRedesignUITests.swift
  git add -p Steps4.xcodeproj/project.pbxproj
  git diff --cached --check
  git commit -m "feat: combine widget and wallpaper settings"
  ```

---

### Task 5: Move Developer Diagnostics Off the Main Page

**Files:**
- Create: `StepsTrader/Views/Settings/SettingsDeveloperPage.swift`
- Modify: `StepsTrader/Views/SettingsSheet.swift:292-543`
- Modify: `Steps4UITests/SettingsRedesignUITests.swift`
- Modify: `Steps4.xcodeproj/project.pbxproj`

**Interfaces:**
- Consumes: existing DEBUG diagnostic actions and `CoachMarkManager` environment.
- Produces: `SettingsDeveloperPage(model:)` compiled only in DEBUG and one main-page destination.

- [ ] **Step 1: Add the failing Developer navigation assertion**

  Add to the existing home UI test:

  ```swift
  let developer = app.buttons["settings.destination.developer"]
  XCTAssertTrue(developer.exists)
  developer.tap()
  XCTAssertTrue(app.staticTexts["Developer"].waitForExistence(timeout: 3))
  XCTAssertTrue(app.buttons["Copy Shield Diagnostics"].exists)
  ```

  Run the focused UI test. Expected: failure because diagnostics are still inline and no destination exists.

- [ ] **Step 2: Create the DEBUG-only Developer page shell**

  Wrap the new file contents in `#if DEBUG`. Import SwiftUI and DeviceActivity conditionally, then define:

  ```swift
  struct SettingsDeveloperPage: View {
      @ObservedObject var model: AppModel
      @Environment(\.appTheme) private var theme
      @Environment(\.topCardHeight) private var topCardHeight
      @Environment(CoachMarkManager.self) private var coachMarkManager
      // existing diagnostic state moves here unchanged
  }
  ```

  Use `SettingsGradientBG`, `ScrollView`, `DetailHeader(title: "Developer")`, the existing rows, top inset, hidden toolbar, and `detailSwipeBack()`.

- [ ] **Step 3: Move every existing diagnostic action without changing behavior**

  Move the complete `#if DEBUG` state, `shieldDiagnosticsRows`, `diagButton`, sheets, full-screen covers, and feature-tip sheet from `SettingsSheet` into the new page. Preserve these actions exactly:

  - copy shield diagnostics;
  - view/copy/clear ShieldAction logs;
  - reset usage budgets;
  - restore colors;
  - force health reset;
  - preview demo onboarding;
  - replay live onboarding;
  - preview coach marks;
  - preview Widget and Wallpaper tips;
  - reset feature-tip flags.

  Add local row icon/divider helpers inside `SettingsDeveloperPage`; do not keep private helper dependencies on `SettingsSheet`.

- [ ] **Step 4: Replace inline diagnostics with one row**

  Under `#if DEBUG`, `SettingsSheet` contains only a `NavigationLink` to `SettingsDeveloperPage(model:)` with identifier `settings.destination.developer`. Delete the old diagnostic state and presentation modifiers from `SettingsSheet`.

- [ ] **Step 5: Run the focused UI test and build Debug and Release**

  Run the focused UI test and Debug build. Then run:

  ```bash
  xcodebuild build -project Steps4.xcodeproj -scheme Steps4 -configuration Release -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO
  ```

  Expected: Debug shows one Developer destination; Release has no reference to the DEBUG-only view.

- [ ] **Step 6: Commit the Developer extraction**

  ```bash
  git add StepsTrader/Views/Settings/SettingsDeveloperPage.swift StepsTrader/Views/SettingsSheet.swift Steps4UITests/SettingsRedesignUITests.swift
  git add -p Steps4.xcodeproj/project.pbxproj
  git diff --cached --check
  git commit -m "refactor: move diagnostics into developer settings"
  ```

---

### Task 6: Build the Approved Card-Based Settings Home

**Files:**
- Create: `StepsTrader/Views/Settings/SettingsHomeCards.swift`
- Modify: `StepsTrader/Views/Settings/SettingsComponents.swift:261-272`
- Modify: `StepsTrader/Views/SettingsSheet.swift:1-290`
- Modify: `Steps4UITests/SettingsRedesignUITests.swift`
- Modify: `Steps4.xcodeproj/project.pbxproj`

**Interfaces:**
- Consumes: Task 1 presentation types and Tasks 2–5 destinations.
- Produces: final `SettingsSheet` hierarchy and reusable card labels with stable accessibility identifiers.

- [ ] **Step 1: Expand the failing home-hierarchy UI test**

  Add this test:

  ```swift
  func testCardHomePrioritizesAccountThenYourDay() {
      let app = launchSettings()
      let account = app.buttons["settings.account"]
      let yourDay = app.buttons["settings.yourDay"]

      XCTAssertTrue(account.waitForExistence(timeout: 3))
      XCTAssertTrue(yourDay.exists)
      XCTAssertLessThan(account.frame.minY, yourDay.frame.minY)
      XCTAssertGreaterThan(yourDay.frame.height, account.frame.height)

      for id in [
          "settings.destination.appearance",
          "settings.destination.notifications",
          "settings.destination.permissions",
          "settings.destination.widgetsWallpaper",
          "settings.destination.notes",
          "settings.destination.about",
      ] {
          XCTAssertTrue(app.buttons[id].exists, "Missing Settings destination: \(id)")
      }
  }
  ```

  Run the focused UI test. Expected: failure because the old flat home has no card identifiers or relative sizing.

- [ ] **Step 2: Add the shared matte card surface**

  In `SettingsComponents.swift`, add:

  ```swift
  struct SettingsCardSurface: ViewModifier {
      @Environment(\.appTheme) private var theme

      func body(content: Content) -> some View {
          content
              .background(theme.adaptivePrimaryText.opacity(0.055))
              .overlay {
                  RoundedRectangle(cornerRadius: 18, style: .continuous)
                      .stroke(theme.adaptivePrimaryText.opacity(0.16), lineWidth: 0.75)
              }
              .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
      }
  }

  extension View {
      func settingsCardSurface() -> some View { modifier(SettingsCardSurface()) }
  }
  ```

  Keep it matte: no blur, glass material, glow, or shadow.

- [ ] **Step 3: Implement the four card labels**

  Create `SettingsHomeCards.swift` with:

  ```swift
  struct SettingsAccountCardLabel: View {
      let presentation: SettingsAccountPresentation
  }

  struct SettingsYourDayCardLabel: View {
      let summary: SettingsYourDaySummary
  }

  struct SettingsDestinationCardLabel: View {
      let icon: String
      let title: String
      var warningText: String? = nil
  }

  struct SettingsInformationGroup<Content: View>: View {
      let content: Content

      init(@ViewBuilder content: () -> Content) {
          self.content = content()
      }

      var body: some View {
          VStack(spacing: 0) { content }
              .settingsCardSurface()
      }
  }
  ```

  Implement them according to the approved mockup:

  - account: 56-point avatar/Apple icon, title, subtitle, trailing chevron, 88-point minimum height;
  - Your day: title, three equal metrics, divider, `Goals & schedule`, chevron, 220-point minimum height;
  - destination: icon above a bottom-aligned title and chevron, 132-point minimum height;
  - information group: existing book/info row style inside one card.

  Use `.accessibilityElement(children: .ignore)` and explicit labels/values on the account and Your day labels. Hide decorative symbols from accessibility.

- [ ] **Step 4: Add live local summary state to `SettingsSheet`**

  Add the same four `@AppStorage` properties used by `SettingsEnergyPage`, plus dynamic type:

  ```swift
  @AppStorage(SharedKeys.userStepsTarget, store: UserDefaults.stepsTrader())
  private var stepsTarget = EnergyDefaults.stepsTarget
  @AppStorage(SharedKeys.userSleepTarget, store: UserDefaults.stepsTrader())
  private var sleepTarget = EnergyDefaults.sleepTargetHours
  @AppStorage(SharedKeys.dayEndHour, store: UserDefaults.stepsTrader())
  private var dayEndHour = 0
  @AppStorage(SharedKeys.dayEndMinute, store: UserDefaults.stepsTrader())
  private var dayEndMinute = 0
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize
  ```

  Derive `SettingsYourDaySummary` directly from those values so returning from the detail page updates the card without a manual refresh.

- [ ] **Step 5: Replace the flat home body with the approved hierarchy**

  Inside the existing `NavigationStack` and `ScrollView`, compose:

  1. large Settings title;
  2. account destination or login button;
  3. `NavigationLink` to `SettingsEnergyPage` using `SettingsYourDayCardLabel`;
  4. `LazyVGrid` with `SettingsGridLayout.columnCount(for:)` equal flexible columns for Appearance, Notifications, Permissions, and Widgets & wallpaper;
  5. one information group containing Notes and About;
  6. DEBUG Developer destination;
  7. existing version footer.

  Use spacing `12` inside the grid and `24` between major blocks. Keep horizontal page padding at `20...24` points. Attach the exact identifiers from the UI test. For permission issues, pass localized `Action needed` as `warningText`; do not show a color-only dot.

  Signed-in account presentation is:

  ```swift
  .signedIn(
      displayName: user.displayName,
      initials: SettingsAccountPresentation.initials(for: user.displayName),
      avatarData: user.avatarData
  )
  ```

  Signed-out tap still sets `showLogin = true`. Signed-in tap navigates to `SettingsAccountPage`.

- [ ] **Step 6: Delete obsolete flat-list helpers**

  Remove `section(header:content:)`, `flatRow`, `permissionsRow`, the old account-row implementation, and any row-icon/title/divider helpers no longer used after Developer moved out. Keep `versionFooter`, feature-tip routing, login sheet, safe-area behavior, and energy-gradient background.

- [ ] **Step 7: Run focused unit tests, UI tests, and build**

  Run all three focused commands from Global Constraints. Expected: presentation tests pass, hierarchy/order UI tests pass, Your day remains reachable, combined destination remains reachable, and Debug builds.

- [ ] **Step 8: Commit the final home redesign**

  ```bash
  git add StepsTrader/Views/Settings/SettingsHomeCards.swift StepsTrader/Views/Settings/SettingsComponents.swift StepsTrader/Views/SettingsSheet.swift Steps4UITests/SettingsRedesignUITests.swift
  git add -p Steps4.xcodeproj/project.pbxproj
  git diff --cached --check
  git commit -m "feat: redesign settings as a card hub"
  ```

---

### Task 7: Complete Localization, Accessibility, and Regression Verification

**Files:**
- Modify: `StepsTrader/Localizable.xcstrings` only if Xcode extraction produces the new keys
- Modify: `Steps4UITests/SettingsRedesignUITests.swift`
- Modify: implementation files from Tasks 2–6 only when verification reveals a settings-specific defect

**Interfaces:**
- Consumes: completed Settings flow.
- Produces: final accessibility/visual evidence and full-suite confidence.

- [ ] **Step 1: Add an accessibility-size layout test**

  Add a launcher parameter to the UI-test helper and this case:

  ```swift
  func testAccessibilityTypeKeepsDestinationCardsReadable() {
      let app = launchSettings(contentSizeCategory: "UICTContentSizeCategoryAccessibilityM")
      let appearance = app.buttons["settings.destination.appearance"]
      let notifications = app.buttons["settings.destination.notifications"]

      XCTAssertTrue(appearance.waitForExistence(timeout: 3))
      XCTAssertTrue(notifications.exists)
      XCTAssertEqual(appearance.frame.minX, notifications.frame.minX, accuracy: 2)
      XCTAssertGreaterThan(notifications.frame.minY, appearance.frame.minY)
      XCTAssertTrue(appearance.isHittable)
      XCTAssertTrue(notifications.isHittable)
  }
  ```

  Implement the helper overload by appending:

  ```swift
  app.launchArguments += [
      "-UIPreferredContentSizeCategoryName", contentSizeCategory
  ]
  ```

  If the simulator runtime ignores that defaults key, retain the pure column-count test from Task 1 and perform this case as a manual Accessibility Inspector check instead of adding fixture behavior to production.

- [ ] **Step 2: Verify source-language localization coverage**

  Confirm these literals are all created through localization APIs: `Your day`, `Goals & schedule`, `New day`, `Automatic sync on`, `Sign in with Apple`, `Sync settings and history across devices`, `Widgets & wallpaper`, `Automatic sync`, `Settings and history sync automatically across your devices.`, and `Developer`.

  Build once in Xcode with string-catalog extraction enabled. If `Localizable.xcstrings` changes, stage only these extracted keys. Do not alter existing translation states or unrelated catalog entries.

- [ ] **Step 3: Run all automated regression gates**

  ```bash
  xcodebuild test -project Steps4.xcodeproj -scheme Steps4 -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17,OS=latest' -only-testing:Steps4Tests CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO
  xcodebuild test -project Steps4.xcodeproj -scheme Steps4 -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17,OS=latest' -only-testing:Steps4UITests/SettingsRedesignUITests CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO
  xcodebuild build -project Steps4.xcodeproj -scheme Steps4 -configuration Release -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO
  ```

  Expected: all Steps4 unit tests pass, all Settings UI tests pass, and Release builds without DEBUG settings references.

- [ ] **Step 4: Perform the visual and interaction matrix**

  On iPhone 17 and the smallest supported iPhone simulator, capture Settings home and each new destination for:

  - signed out;
  - signed in;
  - permission warning present;
  - default Dynamic Type;
  - accessibility Dynamic Type;
  - both app themes;
  - VoiceOver reading order;
  - Reduce Motion.

  Confirm the account card is above Your day but visually smaller, Your day remains the primary anchor, every card is fully tappable, warning copy is not color-only, the grid collapses rather than truncates, and no goal control appears inside Account.

  While signed out, change all three Your day values, terminate and relaunch the
  app, and confirm the summary and detail controls retain the new values. Sign
  in and back out once, then confirm the Your day entry remains visible and
  editable in both states.

- [ ] **Step 5: Commit only verification-driven changes**

  If verification required code or catalog changes, stage only those files and commit:

  ```bash
  git diff --cached --check
  git commit -m "test: verify redesigned settings flow"
  ```

  If no files changed, do not create an empty commit; report the commands, simulator matrix, and screenshot locations in the handoff.

---

## Completion Criteria

- The Settings home matches the approved second visual direction with Account first and Your day visually dominant.
- Signed-out users can edit steps, sleep, and day boundary and retain values across relaunch.
- Account contains identity, automatic-sync explanation, sign out, and deletion only.
- Widget and wallpaper controls share one page while existing deep links continue to work.
- DEBUG diagnostics occupy one destination and never lengthen the Release Settings home.
- All new cards meet accessibility, Dynamic Type, localization, and minimum-hit-target constraints.
- Focused Settings tests, the full unit suite, Debug build, and Release build pass.
