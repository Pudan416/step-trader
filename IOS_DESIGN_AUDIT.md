# iOS Design Guidelines Audit

**Date:** 2026-05-04  
**App:** Steps4 / StepsTrader  
**Standard:** Apple HIG (Human Interface Guidelines) + iOS 26  

---

## Executive Summary

The app has a strong visual identity and already handles several advanced patterns well (custom glass tab bar, spring animations, contextual haptics, safe area insets). The critical gaps are: **hardcoded font sizes breaking Dynamic Type**, **tap targets below 44pt**, **hardcoded `.black` foreground colors failing dark mode contrast**, and **thin accessibility coverage** (only 40 annotated elements across the entire app).

---

## 1. Typography & Dynamic Type

**Status: FAIL**

The app uses `.font(.system(size:))` with hardcoded point values in **100+ places** across 20 files. None of these scale with the user's preferred text size. Users who rely on large text (accessibility setting) will see unchanged, too-small text.

### Critical instances

| File | Line | Hardcoded Size | Fix |
|------|------|---------------|-----|
| [SettingsSheet.swift](StepsTrader/Views/SettingsSheet.swift:32) | 32 | `size: 28, .bold` (title) | `.font(.largeTitle.bold())` |
| [SettingsSheet.swift](StepsTrader/Views/SettingsSheet.swift:86) | 86 | `size: 11, .monospaced` (version) | `.font(.caption2)` |
| [SettingsAboutPage.swift](StepsTrader/Views/Settings/SettingsAboutPage.swift:29) | 29 | `size: 28, .black, .serif` | `.font(.largeTitle)` + `.fontDesign(.serif)` |
| [CategoryDetailView.swift](StepsTrader/Views/CategoryDetailView.swift:98) | 98 | `size: 20, .bold` (section title) | `.font(.title3.bold())` |
| [CategoryDetailView.swift](StepsTrader/Views/CategoryDetailView.swift:203) | 203 | `size: 10, .bold` (badge) | `.font(.caption2.bold())` |
| [MeView.swift](StepsTrader/Views/MeView.swift:186) | 186 | `size: useTightMeLayout ? 10 : 11` | `@ScaledMetric` with `.caption2` |
| [MeView.swift](StepsTrader/Views/MeView.swift:263) | 263 | `size: 9, .medium` | `.font(.caption2)` — 9pt is too small even at default size |
| [SettingsComponents.swift](StepsTrader/Views/Settings/SettingsComponents.swift:173) | 173 | `size: 10, .semibold` (badge label) | `.font(.caption2.weight(.semibold))` |
| [WorkoutSuggestionBanner.swift](StepsTrader/Views/Components/WorkoutSuggestionBanner.swift:41) | 41 | `size: 11, .semibold` | `.font(.caption2.weight(.semibold))` |
| [RadialHoldMenu.swift](StepsTrader/Views/RadialHoldMenu.swift:159) | 159 | `size: 10, .semibold` | `.font(.caption2.weight(.semibold))` |

### What's already good
- Tab icon sizes use `@ScaledMetric` ([MainTabView.swift:36–37](StepsTrader/Views/MainTabView.swift:36)) ✓
- `MeView` conditionally adjusts layout with `useTightMeLayout` ✓

### Fix
Replace every `.font(.system(size: X))` with the nearest semantic equivalent:

```swift
// Before
.font(.system(size: 15, weight: .semibold))

// After
.font(.subheadline.weight(.semibold))
```

For display numbers that must stay a specific design size, use `@ScaledMetric`:
```swift
@ScaledMetric(relativeTo: .body) private var mySize: CGFloat = 15
```

---

## 2. Tap Target Sizes

**Status: FAIL**

Apple HIG requires a minimum **44×44pt** touch target for all interactive elements. The app has several buttons well below this threshold.

### Violations

| File | Line | Element | Current Size | Fix |
|------|------|---------|-------------|-----|
| [StepBalanceCard.swift](StepsTrader/Views/Components/StepBalanceCard.swift:162) | 162–168 | Info (?) button | 28×28pt | `.frame(width: 44, height: 44)` |
| [StepBalanceCard.swift](StepsTrader/Views/Components/StepBalanceCard.swift:179) | 179–185 | Expand chevron button | 80×32pt | `.frame(minHeight: 44)` |
| [DayEndSettingsView.swift](StepsTrader/Views/DayEndSettingsView.swift:53) | 53 | Sleep icon button | 28×28pt | `.frame(width: 44, height: 44)` |
| [DayEndSettingsView.swift](StepsTrader/Views/DayEndSettingsView.swift:79) | 79 | Clock icon button | 28×28pt | `.frame(width: 44, height: 44)` |
| [SettingsSheet.swift](StepsTrader/Views/SettingsSheet.swift:157) | 157 | Settings row | ~40pt height | `.padding(.vertical, 14)` |

### Fix pattern
Use `.contentShape` to extend the hit area without changing visual size:
```swift
Button { ... } label: {
    Image(systemName: "questionmark.circle")
        .font(.system(size: 18))
        .frame(width: 44, height: 44)  // visual frame + tap target combined
        .contentShape(Rectangle())
}
```

---

## 3. Color & Dark Mode Contrast

**Status: FAIL**

The app uses `.foregroundColor(.black)` in 6 places. On glass/material backgrounds this fails WCAG AA contrast in dark mode (black text disappears on dark translucent surfaces).

### Violations

| File | Line | Context |
|------|------|---------|
| [StepBalanceCard.swift](StepsTrader/Views/Components/StepBalanceCard.swift:76) | 76 | Yellow earnings pill — black text on gold badge |
| [OnboardingStoriesView.swift](StepsTrader/Views/OnboardingStoriesView.swift:245) | 245 | Step counter text |
| [GradientPreviewSheet.swift](StepsTrader/Views/Settings/GradientPreviewSheet.swift:141) | 141 | Mode toggle button label |
| [CoachMarkOverlay.swift](StepsTrader/Views/CoachMark/CoachMarkOverlay.swift:107) | 107 | Coach mark headline |
| [CoachMarkOverlay.swift](StepsTrader/Views/CoachMark/CoachMarkOverlay.swift:157) | 157 | Coach mark body |
| [SettingsShortcutPage.swift](StepsTrader/Views/Settings/SettingsShortcutPage.swift:88) | 88 | Shortcut action label |
| [PaperTicketView.swift](StepsTrader/Views/Components/PaperTicketView.swift:242) | 242 | `.foregroundStyle(.black.opacity(0.4))` on ticket placeholder |

### Additional: hardcoded RGB value in a view
[LoginView.swift:196](StepsTrader/Views/LoginView.swift:196) — `Color(red: 0.12, green: 0.08, blue: 0.35)` — deep purple hardcoded inline. Should be a named color asset or `AppColors` entry.

### Fix
```swift
// Before
.foregroundColor(.black)

// After — adapts to light/dark mode automatically
.foregroundStyle(Color.primary)

// For text ON a coloured badge that's always light:
// Use a Color Asset with light/dark variants in Assets.xcassets
.foregroundStyle(Color("BadgeText"))
```

---

## 4. Accessibility — VoiceOver & Labels

**Status: FAIL**

Only **40 accessibility annotations** exist across the entire app. Most interactive elements have no `.accessibilityLabel`, making VoiceOver users unable to navigate meaningfully.

### Missing labels on interactive elements

| File | Element | Issue |
|------|---------|-------|
| [StepBalanceCard.swift:162](StepsTrader/Views/Components/StepBalanceCard.swift:162) | Info (?) button | No label — VoiceOver reads nothing |
| [StepBalanceCard.swift:179](StepsTrader/Views/Components/StepBalanceCard.swift:179) | Expand/collapse chevron | No label |
| [MainTabView.swift:323](StepsTrader/Views/MainTabView.swift:323) | `xmark.circle.fill` dismiss | No label |
| [MeView.swift:254](StepsTrader/Views/MeView.swift:254) | `valuePill()` button | Label on text child, not on Button |
| [MeView.swift:382](StepsTrader/Views/MeView.swift:382) | Day ring (tappable) | No label or hint |
| [SettingsSheet.swift:199](StepsTrader/Views/SettingsSheet.swift:199) | Account avatar row | Name/email not announced |
| [RadialHoldMenu.swift:100](StepsTrader/Views/RadialHoldMenu.swift:100) | Radial menu trigger | No label for hold gesture |
| [GalleryView.swift:885](StepsTrader/Views/GalleryView.swift:885) | Canvas element actions | No contextual labels |

### Pattern to apply across the app

```swift
// Close / dismiss buttons
Button { dismiss() } label: {
    Image(systemName: "xmark.circle.fill")
}
.accessibilityLabel(Text("Close"))

// Toggle buttons with state
Button { isExpanded.toggle() } label: {
    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
}
.accessibilityLabel(isExpanded ? "Collapse" : "Expand")

// Composite content (icon + value)
HStack { ... }
    .accessibilityElement(children: .combine)
    .accessibilityLabel("Steps: \(stepsValue) of \(maxValue)")
```

---

## 5. Spacing Consistency

**Status: WARN**

The app uses an inconsistent spacing grid. Padding values of 4, 8, 10, 11, 12, 13, 14, 16, 20pt appear throughout — there is no shared design token file.

### Common inconsistencies

- [SettingsSheet.swift](StepsTrader/Views/SettingsSheet.swift): rows use `.padding(.vertical, 13)` and `.padding(.horizontal, 14)` — off an 8pt grid
- [SettingsComponents.swift:62](StepsTrader/Views/Settings/SettingsComponents.swift:62): `.padding(.horizontal, 14)` vs same file line 142: `.padding(.vertical, 13)` — both should be 12 or 16
- [MeView.swift](StepsTrader/Views/MeView.swift): `.padding(.horizontal, 16)` and `.padding(.horizontal, 20)` used for similar containers

### Recommended fix
Create a `DesignTokens` struct in `AppConstants.swift`:

```swift
enum Spacing {
    static let xs: CGFloat = 4
    static let sm: CGFloat = 8
    static let md: CGFloat = 12
    static let lg: CGFloat = 16
    static let xl: CGFloat = 24
    static let xxl: CGFloat = 32
}
```

Then replace magic numbers: `.padding(.horizontal, 14)` → `.padding(.horizontal, Spacing.md)`

---

## 6. Navigation & Toolbar Patterns

**Status: PASS with notes**

The app deliberately hides system navigation bars and builds custom navigation. This is valid for a full-bleed design. A few rough edges:

### Issues

- **[TicketTemplatePickerView.swift:118–119](StepsTrader/Views/TicketTemplatePickerView.swift:118)** — Sets `toolbarBackground` to `theme.backgroundColor` with `.visible`, but other sheets hide the toolbar entirely. Inconsistent.
- **[AppsPageSimplified.swift:389–390](StepsTrader/Views/AppsPageSimplified.swift:389)** — Same inconsistency on the inner NavigationStack for app picker.
- **Back gesture** — With `.toolbar(.hidden, for: .navigationBar)`, the system back swipe gesture is disabled on NavigationStack children. Users lose swipe-to-go-back. Add `.navigationBarBackButtonHidden(false)` only where you provide a visible back button, or re-enable the edge swipe gesture explicitly.

### Fix for swipe-back
```swift
// After hiding the nav bar, restore gesture
.gesture(
    DragGesture().onEnded { v in
        if v.startLocation.x < 30 && v.translation.width > 80 {
            dismiss()
        }
    }
)
```
Or use `UINavigationController.interactivePopGestureRecognizer?.isEnabled = true`.

---

## 7. Haptic Feedback

**Status: PASS**

Haptics are well-used throughout: `CategoryDetailView`, `GalleryView`, `RadialHoldMenu`, `PaperTicketView`, `SleepGoalArcPicker`, and more all have `UIImpactFeedbackGenerator`. 

### One gap
- **Tab bar selection** — [MainTabView.swift:369](StepsTrader/Views/MainTabView.swift:369) — switching tabs has no haptic. Add a `.selection` haptic for native feel:
```swift
.onChange(of: selection) { _ in
    UISelectionFeedbackGenerator().selectionChanged()
}
```

### Note on API
`UIImpactFeedbackGenerator` is fine, but iOS 17+ offers the cleaner `.sensoryFeedback` modifier:
```swift
.sensoryFeedback(.impact(flexibility: .soft), trigger: isExpanded)
```

---

## 8. Small/Illegible Font Sizes

**Status: FAIL**

Apple's minimum recommended readable body size is **11pt at the default text size setting**. Several elements go below this.

| File | Line | Size | Problem |
|------|------|------|---------|
| [MeView.swift:263](StepsTrader/Views/MeView.swift:263) | 263 | **9pt** | Below minimum readable size |
| [CategoryDetailView.swift:203](StepsTrader/Views/CategoryDetailView.swift:203) | 203 | **10pt** | Badge label too small |
| [SettingsComponents.swift:173](StepsTrader/Views/Settings/SettingsComponents.swift:173) | 173 | **10pt** | Section badge too small |
| [GradientPreviewSheet.swift:116](StepsTrader/Views/Settings/GradientPreviewSheet.swift:116) | 116 | **10pt** | Segmented control label |
| [SettingsAppearancePage.swift:196](StepsTrader/Views/Settings/SettingsAppearancePage.swift:196) | 196 | **10pt** | Theme selector label |
| [StepGoalDrumPicker.swift:139](StepsTrader/Views/Components/StepGoalDrumPicker.swift:139) | 139 | **10pt** | Picker stepper label |

**Fix:** Raise to 11pt minimum (`.caption2`) and use semantic font styles so Dynamic Type applies.

---

## 9. Missing `.contentShape` on Tappable Containers

**Status: WARN**

Several `Button` elements with `.buttonStyle(.plain)` wrap HStack/VStack content without `.contentShape(Rectangle())`. This creates invisible dead zones within the button frame where taps are not registered.

| File | Issue |
|------|-------|
| [MeView.swift:254](StepsTrader/Views/MeView.swift:254) | `valuePill()` — gaps between icon and label not tappable |
| [MeView.swift:382](StepsTrader/Views/MeView.swift:382) | Day ring — tappable area is shape of ring only |
| [StepBalanceCard.swift:298](StepsTrader/Views/Components/StepBalanceCard.swift:298) | Metric chip — gaps in content not tappable |

**Fix:**
```swift
Button { action() } label: {
    HStack { ... }
}
.buttonStyle(.plain)
.contentShape(Rectangle())  // ← makes entire bounding box tappable
```

---

## 10. `Form` in `ProfileEditorView`

**Status: WARN**

[ProfileEditorView.swift:18](StepsTrader/Views/ProfileEditorView.swift:18) uses a `Form {}` with `.listRowBackground(Color.clear)`. On iOS 26, `Form` has a new grouped glass appearance by default. The current `.listRowBackground(Color.clear)` override may strip the glass treatment and show raw transparent rows, which look unfinished against the app's gradient background.

**Fix:** Either embrace the native Form styling (with glass), or replace with a custom `VStack` + `glassCard()` pattern already used elsewhere.

---

## Priority Fix List

| Priority | Issue | Files |
|----------|-------|-------|
| **P0 — Critical** | 6× `.foregroundColor(.black)` — dark mode contrast failure | StepBalanceCard, OnboardingStoriesView, CoachMarkOverlay, GradientPreviewSheet, SettingsShortcutPage, PaperTicketView |
| **P0 — Critical** | Tap targets < 44pt | StepBalanceCard (info + expand), DayEndSettingsView (2×) |
| **P1 — High** | 100+ hardcoded font sizes — Dynamic Type broken | All Views (worst: CategoryDetailView, SettingsSheet) |
| **P1 — High** | Font sizes < 10pt in production UI | MeView (9pt), 5 other files |
| **P1 — High** | Zero accessibility labels on most interactive elements | App-wide |
| **P2 — Medium** | Inconsistent spacing grid (10/11/12/13/14/16pt chaos) | SettingsSheet, SettingsComponents, MeView |
| **P2 — Medium** | Missing `.contentShape(Rectangle())` on plain-styled buttons | MeView, StepBalanceCard |
| **P2 — Medium** | Tab switch has no haptic feedback | MainTabView |
| **P3 — Low** | Swipe-back gesture disabled on hidden-navbar screens | Several sheets |
| **P3 — Low** | `Form` may conflict with iOS 26 glass rendering | ProfileEditorView |
| **P3 — Low** | `UIImpactFeedbackGenerator` could migrate to `.sensoryFeedback` | App-wide |
