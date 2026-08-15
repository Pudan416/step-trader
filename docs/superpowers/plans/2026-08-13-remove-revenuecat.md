# RevenueCat Removal Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Delete RevenueCat, the paywall and the Free/Pro limits so the app is unconditionally free, keeping the gate scaffolding as the single place gating could return.

**Architecture:** Work outside-in so the build stays green at every commit. First strip the views that present the paywall and draw lock affordances, then delete the now-unreferenced paywall files, then collapse `SubscriptionGate` to unconditional `true`, then reduce `SubscriptionStore` to a 20-line stub and drop the SDK, and finally clean config, CI and test fixtures.

**Tech Stack:** Swift 6 / SwiftUI, Xcode 26, XCTest, xcconfig-based secrets, GitHub Actions + Xcode Cloud.

## Global Constraints

- Spec: `docs/superpowers/specs/2026-08-13-remove-revenuecat-design.md`.
- Every gate query function keeps its existing name **and its `isPro:` parameter**, so the 15 consumer files need no signature changes. The parameter becomes unused — that is intentional and produces no Swift warning.
- `Tariff.swift`, `TariffDecodingTests.swift` and the assertions in `PaymentTests.swift` concern the in-app steps-to-minutes economy, not purchases. Do not touch them except for the `isGrandfathered` fixture lines named in Task 5.
- Build command used throughout:
  `xcodebuild build -project Steps4.xcodeproj -scheme Steps4 -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17,OS=latest' CODE_SIGNING_ALLOWED=NO`
- Test command used throughout:
  `xcodebuild test -project Steps4.xcodeproj -scheme Steps4 -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17,OS=latest' -only-testing:Steps4Tests CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO`
- **Removing a file from disk is not enough.** `Steps4.xcodeproj/project.pbxproj` keeps a reference and the build fails with "Build input file cannot be found". Delete each file through Xcode (right-click → Delete → Move to Trash) so the reference goes with it, or remove its `PBXBuildFile` / `PBXFileReference` / group entries by hand and verify with the build command.

---

### Task 1: Strip paywall presentation and lock affordances from views

Removes every consumer of the paywall and of the Free-tier limits. After this task `PaywallView` and `SettingsSubscriptionPage` are unreferenced but still on disk, so the build stays green.

**Files:**
- Modify: `StepsTrader/Views/AppsPageSimplified.swift`
- Modify: `StepsTrader/Views/Settings/SettingsAppearancePage.swift`
- Modify: `StepsTrader/Views/SettingsSheet.swift`
- Modify: `StepsTrader/Views/MeViewSupport.swift`
- Modify: `StepsTrader/Views/Me/MeCalendarStrip.swift`
- Modify: `StepsTrader/Views/Me/MeWeekStats.swift`
- Modify: `StepsTrader/StepsTraderApp.swift`

**Interfaces:**
- Consumes: nothing from earlier tasks.
- Produces: `MeCalendarStrip` loses its `onLocked: () -> Void` parameter. `MeWeekStats.unlockedKeys(sortedKeys:isPro:freeCount:)` is deleted. Task 3 relies on `SubscriptionGate.freeHistoryDayCount`, `allFeaturesUnlocked`, `shouldShowPostOnboardingPaywall` and `markPostOnboardingPaywallShown` having no remaining callers.

- [ ] **Step 1: Remove the blocking-group limit in AppsPageSimplified**

In `StepsTrader/Views/AppsPageSimplified.swift`, delete the `showPaywall` state declaration:

```swift
    @State private var showPaywall = false
```

Replace the `attemptCreateGroup` function and its comment:

```swift
    /// Centralized gate for the "create new feed" entry points. Free users get
    /// a paywall once they've already created their allotted group(s); Pro
    /// users (and grandfathered legacy users) bypass the check entirely.
    private func attemptCreateGroup() {
        let canAdd = SubscriptionGate.canAddBlockingGroup(
            isPro: model.isPro,
            currentCount: model.blockingStore.ticketGroups.count
        )
        if canAdd {
            showTemplatePicker = true
        } else {
            showPaywall = true
        }
    }
```

with:

```swift
    /// Single entry point for the "create new feed" buttons. Feeds are
    /// unlimited — this stays a named function so the call sites keep reading
    /// as an intent rather than a raw state flip.
    private func attemptCreateGroup() {
        showTemplatePicker = true
    }
```

Delete the paywall cover near line 254:

```swift
            .fullScreenCover(isPresented: $showPaywall) {
                PaywallView(
                    model: model,
                    store: model.subscriptionStore,
                    source: .feature
                )
            }
```

- [ ] **Step 2: Remove the three lock checks in SettingsAppearancePage**

In `StepsTrader/Views/Settings/SettingsAppearancePage.swift`, delete the `showPaywall` state property and the cover:

```swift
        .fullScreenCover(isPresented: $showPaywall) {
            PaywallView(
                model: model,
                store: model.subscriptionStore,
                source: .feature
            )
        }
```

In `paletteHScroll`, replace:

```swift
                    let isUnlocked = SubscriptionGate.isGradientPaletteAvailable(
                        isPro: model.isPro,
                        paletteRaw: scheme.rawValue
                    )
                    Button {
                        guard !isDailyRandomActive else { return }
                        if isUnlocked {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                gradientPaletteRaw = scheme.rawValue
                            }
                            model.syncUserPreferencesToSupabase()
                        } else {
                            showPaywall = true
                        }
```

with:

```swift
                    Button {
                        guard !isDailyRandomActive else { return }
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                            gradientPaletteRaw = scheme.rawValue
                        }
                        model.syncUserPreferencesToSupabase()
```

In `gradientStyleHScroll`, replace:

```swift
                    let isUnlocked = SubscriptionGate.isGradientStyleAvailable(
                        isPro: model.isPro,
                        styleRaw: style.rawValue
                    )
                    Button {
                        guard !isDailyRandomActive else { return }
                        if isUnlocked {
                            previewConfig = GradientPreviewConfig(style: style)
                        } else {
                            showPaywall = true
                        }
```

with:

```swift
                    Button {
                        guard !isDailyRandomActive else { return }
                        previewConfig = GradientPreviewConfig(style: style)
```

In `textureChip`, replace:

```swift
        let isUnlocked = SubscriptionGate.isCanvasTextureAvailable(
            isPro: model.isPro,
            textureRaw: texture.rawValue
        )

        return Button {
            if isUnlocked {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                    canvasTextureRaw = texture.rawValue
                }
                                lightHapticTick &+= 1
                model.syncUserPreferencesToSupabase()
            } else {
```

with a button that always applies the texture. Then follow each `isUnlocked` identifier still reported by the compiler and delete the lock badge / dimming modifier it drives. After this step:

```bash
grep -n "isUnlocked\|showPaywall" StepsTrader/Views/Settings/SettingsAppearancePage.swift
```

must print nothing.

- [ ] **Step 3: Remove the Membership row from SettingsSheet**

In `StepsTrader/Views/SettingsSheet.swift`, delete:

```swift
                    if !SubscriptionGate.allFeaturesUnlocked {
                        section(header: String(localized: "Membership", comment: "Settings section header")) {
                            subscriptionRow
                        }
                    }
```

Then delete the whole `// MARK: - Subscription row` block: the `subscriptionRow`, `subscriptionIcon`, `subscriptionTint` and `subscriptionStatusLabel` properties. They are the only readers of `model.subscriptionStore.state`, which Task 4 removes.

- [ ] **Step 4: Remove the Me paywall cover**

In `StepsTrader/Views/MeViewSupport.swift`, delete the `showPaywall` binding from `MeSheetsModifier` and its cover:

```swift
    @Binding var showPaywall: Bool
```

```swift
            // Reached by tapping a day the dormant history gate has locked.
            .fullScreenCover(isPresented: $showPaywall) {
                PaywallView(model: model, store: model.subscriptionStore, source: .feature)
            }
```

Then update the `MeView` call site the compiler flags, dropping the `showPaywall:` argument and the `@State private var showPaywall` that fed it.

- [ ] **Step 5: Unlock every day in the calendar**

In `StepsTrader/Views/Me/MeCalendarStrip.swift` replace the file header comment:

```swift
// The Pro gate is dormant, not gone: `SubscriptionGate.allFeaturesUnlocked` is
// currently `true`, so `model.isPro` is unconditionally true and every day is
// open. The constant is a documented kill-switch, so the gating stays wired.
```

with:

```swift
// Every day is open — the app is free and there is no history gate.
```

Delete the `onLocked` property, the `debugForceUnlock` state, the `effectiveIsPro` computed property, and the `unlocked` set:

```swift
    let onLocked: () -> Void
```

```swift
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
```

```swift
        let unlocked = MeWeekStats.unlockedKeys(
            sortedKeys: keys,
            isPro: effectiveIsPro,
            freeCount: SubscriptionGate.freeHistoryDayCount
        )
```

At line ~118 replace the tile construction:

```swift
                            isLocked: !unlocked.contains(key),
```

by removing the `isLocked` argument entirely, and replace the tap handler:

```swift
                                if unlocked.contains(key) { onSelect(key) } else { onLocked() }
```

with:

```swift
                                onSelect(key)
```

Then delete the `isLocked` parameter from the tile view, the "Pro" badge at line ~248, and the locked accessibility string at line ~263:

```swift
                Text(String(localized: "Pro", comment: "Me calendar – locked tile badge"))
```

```swift
            return String(localized: "\(dayName), \(monthDay), locked, requires Pro", comment: "Me calendar – tile a11y, locked")
```

Update the `#Preview` at line ~313 to drop `onLocked: {}`. Then update the `MeView` call site the compiler flags.

- [ ] **Step 6: Delete unlockedKeys from MeWeekStats**

In `StepsTrader/Views/Me/MeWeekStats.swift` delete:

```swift
    /// The history days a user may open. Dormant today —
    /// `SubscriptionGate.allFeaturesUnlocked` makes `isPro` unconditionally
    /// true — but the constant is a documented kill-switch, so the rule stays
    /// live and tested. `sortedKeys` must be newest first.
    static func unlockedKeys(sortedKeys: [String], isPro: Bool, freeCount: Int) -> Set<String> {
        if isPro { return Set(sortedKeys) }
        return Set(sortedKeys.prefix(freeCount))
    }
```

- [ ] **Step 7: Remove the post-onboarding paywall**

In `StepsTrader/StepsTraderApp.swift` delete `presentPostOnboardingPaywallIfNeeded` in full:

```swift
    /// Decide whether to flip `showPostOnboardingPaywall` to `true`.
    /// Called only after `runCoachMarksIfRequested()` has returned, so the
    /// tour (if any) is guaranteed to be finished by this point.
    @MainActor
    private func presentPostOnboardingPaywallIfNeeded() async {
        guard SubscriptionGate.shouldShowPostOnboardingPaywall(isPro: model.isPro) else { return }
        // Brief cosmetic delay so the welcome screen renders before the paywall.
        try? await Task.sleep(for: .milliseconds(600))
        if Task.isCancelled { return }
        showPostOnboardingPaywall = true
    }
```

Delete the `@State private var showPostOnboardingPaywall` declaration, the entire `for _ in 0..<10 { switch model.subscriptionStore.state { … } }` polling loop around line 316 (it exists only to wait for RevenueCat before deciding whether to show the paywall), and the cover:

```swift
            .fullScreenCover(isPresented: $showPostOnboardingPaywall, onDismiss: {
                SubscriptionGate.markPostOnboardingPaywallShown()
            }) {
                PaywallView(
                    model: model,
                    store: model.subscriptionStore,
                    source: .promotion
                )
            }
```

- [ ] **Step 8: Build**

Run the build command from Global Constraints.
Expected: BUILD SUCCEEDED. If a `PaywallView` or `subscriptionRow` reference remains, the error names the file and line — fix and rebuild.

- [ ] **Step 9: Verify no paywall entry points survive**

```bash
grep -rn "PaywallView\|showPaywall\|onLocked" StepsTrader/ --include="*.swift" | grep -v "Views/PaywallView.swift"
```

Expected: no output.

- [ ] **Step 10: Commit**

```bash
git add StepsTrader/
git commit -m "refactor: remove paywall entry points and lock affordances"
```

---

### Task 2: Delete the paywall files

**Files:**
- Delete: `StepsTrader/Views/PaywallView.swift`
- Delete: `StepsTrader/Views/Settings/SettingsSubscriptionPage.swift`
- Delete: `Steps4/Configuration.storekit`
- Modify: `Steps4.xcodeproj/project.pbxproj` (via Xcode)

**Interfaces:**
- Consumes: Task 1 left both Swift files with zero references.
- Produces: `SubscriptionIDs` and `PurchasePackage` lose two of their three consumers; Task 4 removes the last.

- [ ] **Step 1: Confirm both files are unreferenced**

```bash
grep -rn "PaywallView\|SettingsSubscriptionPage" StepsTrader/ Steps4Tests/ --include="*.swift" \
  | grep -v "^StepsTrader/Views/PaywallView.swift" \
  | grep -v "^StepsTrader/Views/Settings/SettingsSubscriptionPage.swift"
```

Expected: no output. If anything prints, go back and finish Task 1.

- [ ] **Step 2: Delete the files through Xcode**

Open `Steps4.xcodeproj`, select `PaywallView.swift`, `SettingsSubscriptionPage.swift` and `Configuration.storekit` in the navigator, right-click → Delete → Move to Trash. This removes the `project.pbxproj` entries at the same time.

If the scheme references the StoreKit configuration, clear it: Product → Scheme → Edit Scheme → Run → Options → StoreKit Configuration → None.

- [ ] **Step 3: Build**

Run the build command.
Expected: BUILD SUCCEEDED, and no "Build input file cannot be found" error — that error means a `project.pbxproj` reference outlived its file.

- [ ] **Step 4: Commit**

```bash
git add -A
git commit -m "refactor: delete PaywallView, subscription settings page and StoreKit config"
```

---

### Task 3: Collapse SubscriptionGate to unconditional yes

**Files:**
- Modify: `StepsTrader/Stores/SubscriptionGate.swift`
- Test: `Steps4Tests/SubscriptionGateTests.swift`

**Interfaces:**
- Consumes: Tasks 1–2 removed every caller of `allFeaturesUnlocked`, `freeHistoryDayCount`, `freeMaxBlockingGroups`, `shouldShowPostOnboardingPaywall` and `markPostOnboardingPaywallShown`.
- Produces: `SubscriptionGate` exposes exactly eight static functions, all returning `true`, all keeping their current signatures: `canAddBlockingGroup(isPro:currentCount:)`, `canCreateCustomActivity(isPro:)`, `canAddMoment(isPro:)`, `canUseDailyRandomTheme(isPro:)`, `canCustomizeShapes(isPro:)`, `isGradientPaletteAvailable(isPro:paletteRaw:)`, `isGradientStyleAvailable(isPro:styleRaw:)`, `isCanvasTextureAvailable(isPro:textureRaw:)`.

- [ ] **Step 1: Write the failing test**

Replace `Steps4Tests/SubscriptionGateTests.swift` in full:

```swift
import XCTest
@testable import Steps4

/// The app is free: every gate answers yes for every input, including the
/// `isPro: false` case that used to be the restricted path. These tests exist
/// so a future reintroduction of gating has to break something visible.
final class SubscriptionGateTests: XCTestCase {

    func testBlockingGroupsAreUnlimited() {
        for isPro in [true, false] {
            for count in 0...10 {
                XCTAssertTrue(
                    SubscriptionGate.canAddBlockingGroup(isPro: isPro, currentCount: count),
                    "count \(count), isPro \(isPro)"
                )
            }
        }
    }

    func testEveryFeatureGateAnswersYes() {
        for isPro in [true, false] {
            XCTAssertTrue(SubscriptionGate.canCreateCustomActivity(isPro: isPro))
            XCTAssertTrue(SubscriptionGate.canAddMoment(isPro: isPro))
            XCTAssertTrue(SubscriptionGate.canUseDailyRandomTheme(isPro: isPro))
            XCTAssertTrue(SubscriptionGate.canCustomizeShapes(isPro: isPro))
        }
    }

    func testEveryVisualOptionIsAvailable() {
        for isPro in [true, false] {
            for palette in ["warmSunset", "ocean", "aurora", "dusk", "dawn", "ember", "horizon", "coolOcean"] {
                XCTAssertTrue(SubscriptionGate.isGradientPaletteAvailable(isPro: isPro, paletteRaw: palette))
            }
            for style in ["radial", "linear", "angular"] {
                XCTAssertTrue(SubscriptionGate.isGradientStyleAvailable(isPro: isPro, styleRaw: style))
            }
            for texture in ["none", "grain", "glass", "plastic"] {
                XCTAssertTrue(SubscriptionGate.isCanvasTextureAvailable(isPro: isPro, textureRaw: texture))
            }
        }
    }
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run the test command.
Expected: FAIL. `testBlockingGroupsAreUnlimited` fails at `count 2, isPro false` because `freeMaxBlockingGroups` is still 2, and `testEveryFeatureGateAnswersYes` fails on `canCreateCustomActivity(isPro: false)` because `freeCanCreateCustomActivity` is `false`.

- [ ] **Step 3: Rewrite SubscriptionGate**

Replace `StepsTrader/Stores/SubscriptionGate.swift` in full:

```swift
import Foundation

/// Central answer to "what can a user do".
///
/// The app is free and every gate returns `true`. The functions survive their
/// own retirement on purpose: they keep the call sites reading as intent, and
/// they are the one place to reintroduce gating without hunting through views.
/// The `isPro` parameters are deliberately unused.
enum SubscriptionGate {

    /// Blocking groups are unlimited.
    static func canAddBlockingGroup(isPro: Bool, currentCount: Int) -> Bool { true }

    /// Custom energy activities are available to everyone.
    static func canCreateCustomActivity(isPro: Bool) -> Bool { true }

    /// Moments are available to everyone.
    static func canAddMoment(isPro: Bool) -> Bool { true }

    /// The daily random theme is available to everyone.
    static func canUseDailyRandomTheme(isPro: Bool) -> Bool { true }

    /// Per-category shape customisation is available to everyone.
    static func canCustomizeShapes(isPro: Bool) -> Bool { true }

    /// Every gradient palette is available.
    static func isGradientPaletteAvailable(isPro: Bool, paletteRaw: String) -> Bool { true }

    /// Every gradient style is available.
    static func isGradientStyleAvailable(isPro: Bool, styleRaw: String) -> Bool { true }

    /// Every canvas texture is available.
    static func isCanvasTextureAvailable(isPro: Bool, textureRaw: String) -> Bool { true }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run the test command.
Expected: PASS, whole `Steps4Tests` suite green.

- [ ] **Step 5: Commit**

```bash
git add StepsTrader/Stores/SubscriptionGate.swift Steps4Tests/SubscriptionGateTests.swift
git commit -m "refactor: collapse the Free/Pro gate matrix to unconditional yes"
```

---

### Task 4: Reduce SubscriptionStore to a stub and drop the SDK

**Files:**
- Modify: `StepsTrader/Stores/SubscriptionStore.swift`
- Modify: `StepsTrader/StepsTraderApp.swift`
- Modify: `StepsTrader/Services/AuthenticationService.swift`
- Modify: `StepsTrader/Utilities/SharedKeys.swift`
- Delete: `StepsTrader/Models/SubscriptionEntitlement.swift`
- Delete: `Steps4Tests/SubscriptionStateTests.swift`
- Modify: `Steps4.xcodeproj/project.pbxproj` (via Xcode)

**Interfaces:**
- Consumes: `SubscriptionGate` from Task 3; `DIContainer.makeSubscriptionStore()` and `AppModel.subscriptionStore` / `AppModel.isPro` are unchanged and must keep working.
- Produces: `SubscriptionStore` is an `ObservableObject` with a single member, `var isPro: Bool { true }`, plus the existing `@MainActor static let shared` in `DIContainer.swift`. `SubscriptionState`, `SubscriptionPurchaseResult`, `PurchasePackage` and `SubscriptionIDs` no longer exist.

- [ ] **Step 1: Replace SubscriptionStore**

Replace `StepsTrader/Stores/SubscriptionStore.swift` in full:

```swift
import Foundation
import SwiftUI

/// Subscription state, retired.
///
/// The app is free for everyone and there is no purchase path, so this exists
/// only to keep `AppModel.isPro` and the `SubscriptionGate` call sites wired to
/// something. `DIContainer` still vends the shared instance; `AppModel`
/// subscribes to `objectWillChange` and that subscription simply never fires.
@MainActor
final class SubscriptionStore: ObservableObject {
    /// Always true. See `SubscriptionGate` for the gates this feeds.
    var isPro: Bool { true }
}
```

Leave `DIContainer.swift` alone — its `extension SubscriptionStore { @MainActor static let shared = SubscriptionStore() }` still compiles against the stub.

- [ ] **Step 2: Remove the RevenueCat configure call**

In `StepsTrader/StepsTraderApp.swift` delete:

```swift
        // Configure RevenueCat as early as possible. Reads `REVENUECAT_API_KEY` from
        // Info.plist (which interpolates from xcconfig at build time). Anonymous user
        // is fine — we'll `logIn(supabaseUserID:)` once Sign in with Apple completes.
        //
        // ORDER NOTE: configure() runs grandfather detection which reads
        // `appLaunchCount`. The increment below happens AFTER, so the threshold
        // logic in `SubscriptionStore.detectExistingUser` is order-independent
        // (it tolerates either ordering). Don't move this around carelessly.
        let rcKey = Bundle.main.object(forInfoDictionaryKey: "REVENUECAT_API_KEY") as? String ?? ""
        SubscriptionStore.shared.configure(apiKey: rcKey)
```

- [ ] **Step 3: Remove the auth-time RevenueCat calls**

In `StepsTrader/Services/AuthenticationService.swift`, inside `performTeardown`, delete:

```swift
        await SubscriptionStore.shared.logOut()
```

In `handleAuthorization`'s `postLoginSyncTask`, delete:

```swift
                    AppLogger.auth.debug("🔐 Post-login — linking RC userId: \(uid.prefix(8))…")
                    await SubscriptionStore.shared.logIn(supabaseUserID: uid)
```

In `loadStoredSessionAndRefreshUser`, delete:

```swift
            // Re-link RC on cold launch when we already have a session.
            if let uid = currentUser?.id {
                await SubscriptionStore.shared.logIn(supabaseUserID: uid)
            }
```

The compiler will then flag `uid` as unused in `postLoginSyncTask`. Keep the surrounding sync work and remove only the now-dead binding.

This also removes a real hazard: `Purchases.shared` traps when read before `configure`, and these were the calls that would have hit it.

- [ ] **Step 4: Delete the entitlement model and its tests through Xcode**

Delete `StepsTrader/Models/SubscriptionEntitlement.swift` and `Steps4Tests/SubscriptionStateTests.swift` via the Xcode navigator (Delete → Move to Trash) so their `project.pbxproj` references go too.

- [ ] **Step 5: Remove the dead SharedKeys entries**

In `StepsTrader/Utilities/SharedKeys.swift` delete these three constants:

```swift
    static let isGrandfathered = "subscription_isGrandfathered_v1"
```

```swift
    static let cachedHasProEntitlement = "subscription_cachedHasPro_v1"
```

```swift
    static let rcAppUserID = "subscription_rcAppUserID_v1"
```

Values already written to UserDefaults on real devices are left as harmless orphans — a migration to delete them is not worth the code.

Test files still reference `SharedKeys.isGrandfathered`; Task 5 removes those. To keep this task's build green, do Step 5 and Task 5 Step 1 before running the test command.

- [ ] **Step 6: Remove the RevenueCat SPM package**

In Xcode: select the project → Package Dependencies → `purchases-ios` → `−`. Then check the Steps4 target's General → Frameworks, Libraries, and Embedded Content for leftover `RevenueCat` / `RevenueCatUI` entries and remove them.

Verify:

```bash
grep -n "purchases-ios\|RevenueCat" Steps4.xcodeproj/project.pbxproj
```

Expected: no output.

- [ ] **Step 7: Verify no RevenueCat symbol survives**

```bash
grep -rn "RevenueCat\|Purchases\.\|CustomerInfo\|StoreProduct\|SubscriptionIDs" StepsTrader/ Steps4Tests/ --include="*.swift"
```

Expected: no output.

- [ ] **Step 8: Build and test**

Run the build command, then the test command.
Expected: BUILD SUCCEEDED, all tests pass.

- [ ] **Step 9: Commit**

```bash
git add -A
git commit -m "refactor: reduce SubscriptionStore to a stub and drop the RevenueCat SDK"
```

---

### Task 5: Clean config, CI and stale fixtures

**Files:**
- Modify: `Steps4/Info.plist`
- Modify: `Config/Secrets.xcconfig.template`
- Modify: `Config/Secrets.xcconfig` (untracked, plus five worktree copies)
- Modify: `ci_scripts/ci_post_clone.sh`
- Modify: `.github/workflows/ci.yml`
- Modify: `Steps4Tests/EnergyRecalcTests.swift`, `Steps4Tests/PaymentTests.swift`, `Steps4Tests/HappeningAdditionsTests.swift`, `Steps4Tests/HappeningLiquidLayoutTests.swift`
- Modify: `StepsTrader/AppModel+DailyEnergy.swift`, `StepsTrader/Views/Me/MeWeekStats.swift`

**Interfaces:**
- Consumes: Task 4 deleted `SharedKeys.isGrandfathered`, so the fixture lines below no longer compile until removed.
- Produces: `Scripts/check-secrets-config.sh` passes with two keys instead of three.

- [ ] **Step 1: Remove the grandfathered fixtures from unrelated tests**

In each of `Steps4Tests/EnergyRecalcTests.swift`, `Steps4Tests/PaymentTests.swift`, `Steps4Tests/HappeningAdditionsTests.swift` and `Steps4Tests/HappeningLiquidLayoutTests.swift`, delete the lines that set or clear the flag:

```swift
        defaults.set(true, forKey: SharedKeys.isGrandfathered)
```

```swift
            SharedKeys.isGrandfathered,
```

The second form appears inside arrays of keys being cleaned up in `tearDown`; remove just that element, keeping the rest of the array. Leave every assertion untouched — these tests were only buying Pro behaviour that is now the default.

- [ ] **Step 2: Remove REVENUECAT_API_KEY from Info.plist**

In `Steps4/Info.plist` delete both lines:

```xml
	<key>REVENUECAT_API_KEY</key>
	<string>$(REVENUECAT_API_KEY)</string>
```

- [ ] **Step 3: Remove the key from the secrets template**

In `Config/Secrets.xcconfig.template` delete:

```
// RevenueCat — public Apple SDK key.
// Get it from: https://app.revenuecat.com → Project Settings → API Keys
// Use the "Public app-specific" key for iOS (starts with `appl_`).
REVENUECAT_API_KEY = appl_YOUR_PUBLIC_KEY_HERE
```

- [ ] **Step 4: Remove the key from the local secrets files**

The real `Config/Secrets.xcconfig` is gitignored, so it must be edited directly. Delete its `REVENUECAT_API_KEY` line, then propagate to every worktree:

```bash
cd "$(git rev-parse --show-toplevel)" && SRC="$(pwd)/Config/Secrets.xcconfig"; git worktree list --porcelain | awk '/^worktree /{print substr($0,10)}' | while read -r w; do [ "$w" = "$(pwd)" ] && continue; [ -d "$w/Config" ] && cp "$SRC" "$w/Config/Secrets.xcconfig" && echo "copied -> $w"; done
```

- [ ] **Step 5: Remove the key from the release script**

In `ci_scripts/ci_post_clone.sh` delete these three lines:

```sh
substitute "REVENUECAT_API_KEY" "${REVENUECAT_API_KEY:-}"
```

```sh
assert_substituted "REVENUECAT_API_KEY"
```

and the `REVENUECAT_API_KEY` mention in the header comment:

```sh
# Set REVENUECAT_API_KEY (and Supabase keys) as Xcode Cloud workflow secrets;
```

Replace that comment line with:

```sh
# Set the Supabase keys as Xcode Cloud workflow secrets;
```

- [ ] **Step 6: Remove the key from the CI comment**

In `.github/workflows/ci.yml` update the "Create placeholder secrets" comment so it stops naming a variable that no longer exists:

```yaml
        # The build's Info.plist references $(SUPABASE_URL)/$(SUPABASE_ANON_KEY)/
        # $(REVENUECAT_API_KEY) via Config/Secrets.xcconfig, which is gitignored.
```

becomes:

```yaml
        # The build's Info.plist references $(SUPABASE_URL)/$(SUPABASE_ANON_KEY)
        # via Config/Secrets.xcconfig, which is gitignored.
```

- [ ] **Step 7: Fix the stale comments**

In `StepsTrader/AppModel+DailyEnergy.swift` around line 286 and `StepsTrader/Views/Me/MeWeekStats.swift` around line 60, rewrite the comments that describe `SubscriptionGate.allFeaturesUnlocked` or `freeHistoryDayCount` so they state plainly that history is unlimited and the app is free. Verify:

```bash
grep -rn "allFeaturesUnlocked\|freeHistoryDayCount\|grandfather" StepsTrader/ Steps4Tests/ --include="*.swift" -i
```

Expected: no output.

- [ ] **Step 8: Run the secrets guard**

```bash
./Scripts/check-secrets-config.sh
```

Expected: `✅ Secrets config OK (2 keys).` A failure naming `REVENUECAT_API_KEY` means one config layer still carries it — that is exactly what the guard is for.

- [ ] **Step 9: Test the release script both ways**

```bash
T=$(mktemp -d) && mkdir -p "$T/Config" && cp Config/Secrets.xcconfig.template "$T/Config/"
(CI_PRIMARY_REPOSITORY_PATH="$T" sh ci_scripts/ci_post_clone.sh); echo "expect exit 1, got $?"
rm -f "$T/Config/Secrets.xcconfig"
(CI_PRIMARY_REPOSITORY_PATH="$T" SUPABASE_URL="https://example.supabase.co" SUPABASE_ANON_KEY="k" sh ci_scripts/ci_post_clone.sh); echo "expect exit 0, got $?"
rm -rf "$T"
```

Expected: first run exits 1 naming a Supabase key, second exits 0.

- [ ] **Step 10: Build and test**

Run the build command, then the test command.
Expected: BUILD SUCCEEDED, all tests pass.

- [ ] **Step 11: Verify in the running app**

Launch on the simulator and confirm: onboarding finishes with no paywall, the Me calendar shows every day unblurred with no "Pro" badge, Settings has no Membership row, and a third blocking group can be created.

- [ ] **Step 12: Commit**

```bash
git add -A
git commit -m "chore: drop the RevenueCat key from config, CI and test fixtures"
```

---

## Self-Review

**Spec coverage.** Every "Deleted outright" row maps to Task 2 (`PaywallView`, `SettingsSubscriptionPage`, `Configuration.storekit`) or Task 4 (`SubscriptionEntitlement`, `SubscriptionStateTests`, the SPM package). "Reduced" maps to Task 4 (`SubscriptionStore`) and Task 3 (`SubscriptionGate`). Every row of the UI-cleanup table maps to a numbered step in Task 1, except the `AuthenticationService` row which is Task 4 Step 3 — it belongs with the store reduction because that is what deletes the methods it calls. "Config and CI" maps to Task 5 Steps 2–6, and the spec's note that `Scripts/check-secrets-config.sh` needs no edit is confirmed by Task 5 Step 8. The `SharedKeys` and orphan-value decisions map to Task 4 Step 5. The four fixture files map to Task 5 Step 1. All four spec verification items map to Task 4 Step 7, Task 5 Step 10, Task 5 Step 8 and Task 5 Step 11 respectively.

**Placeholder scan.** No TBD/TODO. The only step that does not quote exact final code is Task 1 Step 2's lock-badge removal in `SettingsAppearancePage`, because the badge modifiers are scattered through a 550-line file; it is bounded by a grep whose required output is stated, which is a checkable finish condition rather than an open instruction.

**Type consistency.** `SubscriptionGate`'s eight surviving function names and signatures in Task 3 match the call sites left standing after Task 1 — `canAddBlockingGroup` is deleted from `AppsPageSimplified` but retained in the enum, which is consistent because `AppModel+DailyRandomTheme.swift:91` still calls `canUseDailyRandomTheme` and `SettingsAppearancePage` still calls it via `canUseDailyRandom`. `SubscriptionStore.isPro` in Task 4 matches `AppModel.isPro`'s existing body. `MeCalendarStrip`'s dropped `onLocked` in Task 1 Step 5 is matched by the `MeView` call-site update in the same step.

## Execution Handoff

Plan complete and saved to `docs/superpowers/plans/2026-08-13-remove-revenuecat.md`.
