# iOS 26 Liquid Glass Icon & UI Audit

**Date:** 2026-05-04  
**Scope:** Steps4 app (StepsTrader, UnlockWidget, ShieldConfiguration, OnboardingPreview)  
**Goal:** Ensure all icons use soft stroke (outline) style per iOS 26 Liquid Glass design language

---

## Summary

iOS 26 introduces the Liquid Glass design system where icons should be **outline/stroke-based** (not filled) to maintain visual harmony with translucent glass surfaces. Filled icons create visual heaviness that conflicts with the ethereal glass aesthetic. The app should use SF Symbols in their default (outline) or `.light`/`.thin` weight variants.

**Total filled icons found: 93 instances across 16 files**  
**Stroke icons (already compliant): ~45 instances**

---

## Critical Violations: Tab Bar Icons

| File | Line | Current (Filled) | Recommended (Stroke) |
|------|------|-------------------|---------------------|
| `MainTabView.swift` | 54 | `paintbrush.fill` | `paintbrush` |
| `MainTabView.swift` | 56 | `book.fill` | `book` |

Tab icons `square.grid.2x2`, `person.circle`, and `gearshape` are already compliant (stroke-based).

---

## Filled Icons by File

### StepsTrader/Models/DailyEnergy.swift

**Energy Options (lines 192–224) — 22 filled icons:**

| Line | Current | Recommended |
|------|---------|-------------|
| 192 | `dumbbell.fill` | `dumbbell` |
| 194 | `bed.double.fill` | `bed.double` |
| 196 | `hand.raised.fill` | `hand.raised` |
| 199 | `sun.max.fill` | `sun.max` |
| 201 | `cross.case.fill` | `cross.case` |
| 204 | `eye.fill` | `eye` |
| 205 | `book.fill` | `book` |
| 209 | `binoculars.fill` | `binoculars` |
| 210 | `questionmark.circle.fill` | `questionmark.circle` |
| 211 | `square.grid.2x2.fill` | `square.grid.2x2` |
| 213 | `leaf.fill` | `leaf` |
| 216 | `face.smiling.fill` | `face.smiling` |
| 217 | `moon.zzz.fill` | `moon.zzz` |
| 218 | `hands.sparkles.fill` | `hands.sparkles` |
| 219 | `person.2.fill` | `person.2` |
| 220 | `heart.circle.fill` | `heart.circle` |
| 222 | `lock.open.fill` | `lock.open` |
| 223 | `heart.slash.fill` | `heart.slash` |
| 224 | `house.fill` | `house` |
| 405 | `brain.head.profile.fill` | `brain.head.profile` |
| 417 | `leaf.fill` | `leaf` |
| 431 | `flame.fill` | `flame` |
| 432 | `dumbbell.fill` | `dumbbell` |

**Icon Picker Arrays (lines 495–511) — 40+ filled icons in catalogs:**

| Line | Filled Icons to Convert |
|------|------------------------|
| 495 | `sportscourt.fill` → `sportscourt`, `dumbbell.fill` → `dumbbell`, `skateboard.fill` → `skateboard` |
| 496 | `football.fill` → `football`, `baseball.fill` → `baseball`, `volleyball.fill` → `volleyball` |
| 500 | `moon.zzz.fill` → `moon.zzz`, `bed.double.fill` → `bed.double`, `cup.and.saucer.fill` → `cup.and.saucer`, `leaf.fill` → `leaf` |
| 501 | `drop.fill` → `drop`, `cloud.fill` → `cloud` |
| 502 | `sun.max.fill` → `sun.max`, `umbrella.fill` → `umbrella`, `flame.fill` → `flame` |
| 503 | `bubble.left.and.bubble.right.fill` → `bubble.left.and.bubble.right`, `heart.fill` → `heart`, `eye.fill` → `eye` |
| 507 | `paintbrush.fill` → `paintbrush`, `book.fill` → `book`, `gamecontroller.fill` → `gamecontroller` |
| 508 | `film.fill` → `film`, `tv.fill` → `tv`, `guitars.fill` → `guitars` |
| 509 | `camera.fill` → `camera`, `photo.fill` → `photo`, `heart.fill` → `heart`, `star.fill` → `star` |
| 510 | `gift.fill` → `gift`, `balloon.fill` → `balloon`, `party.popper.fill` → `party.popper`, `birthday.cake.fill` → `birthday.cake` |
| 511 | `face.smiling.fill` → `face.smiling`, `hands.clap.fill` → `hands.clap`, `hand.thumbsup.fill` → `hand.thumbsup`, `pawprint.fill` → `pawprint` |

---

### StepsTrader/Views/MainTabView.swift

| Line | Current | Recommended |
|------|---------|-------------|
| 54 | `paintbrush.fill` | `paintbrush` |
| 56 | `book.fill` | `book` |
| 323 | `xmark.circle.fill` | `xmark.circle` |

---

### StepsTrader/Views/CategoryDetailView.swift

| Line | Current | Recommended |
|------|---------|-------------|
| 573 | `heart.fill` | `heart` |
| 795 | `checkmark.square.fill` | `checkmark.square` |

---

### StepsTrader/Views/Components/PaperTicketView.swift

| Line | Current | Recommended |
|------|---------|-------------|
| 85 | `lock.fill` | `lock` |
| 241 | `app.fill` | `app` |
| 245 | `app.fill` | `app` |

---

### StepsTrader/Views/Components/StepBalanceCard.swift

| Line | Current | Recommended |
|------|---------|-------------|
| 200 | `shoeprints.fill` | `shoeprints` |
| 208 | `bed.double.fill` | `bed.double` |
| 235 | `heart.fill` | `heart` |

---

### StepsTrader/Views/DayEndSettingsView.swift

| Line | Current | Recommended |
|------|---------|-------------|
| 50 | `bed.double.fill` | `bed.double` |

---

### StepsTrader/Views/GalleryView.swift

| Line | Current | Recommended |
|------|---------|-------------|
| 1068 | `xmark.circle.fill` | `xmark.circle` |
| 1308 | `bed.double.fill` | `bed.double` |
| 1309 | `plus.circle.fill` | `plus.circle` |
| 1310 | `minus.circle.fill` | `minus.circle` |

---

### StepsTrader/Views/InlineTicketSettingsView.swift

| Line | Current | Recommended |
|------|---------|-------------|
| 31 | `gearshape.fill` | `gearshape` |
| 160 | `lock.open.fill` | `lock.open` |

---

### StepsTrader/Views/LoginView.swift

| Line | Current | Recommended |
|------|---------|-------------|
| 75 | `xmark.circle.fill` | `xmark.circle` |
| 111 | `eye.fill` | `eye` |
| 188 | `app.fill` | `app` |

---

### StepsTrader/Views/MeView.swift

| Line | Current | Recommended |
|------|---------|-------------|
| 146 | `person.fill` | `person` |
| 160 | `moon.zzz.fill` | `moon.zzz` |
| 208 | `moon.zzz.fill` | `moon.zzz` |
| 230 | `play.fill` | `play` |
| 625 | `bed.double.fill` | `bed.double` |

---

### StepsTrader/Views/OnboardingStoriesView.swift

| Line | Current | Recommended |
|------|---------|-------------|
| 548 | `app.fill` | `app` |
| 554 | `app.fill` | `app` |
| 861 | `lock.open.fill` | `lock.open` |
| 952 | `moon.fill` | `moon` |
| 1187 | `checkmark.circle.fill` | `checkmark.circle` |

---

### StepsTrader/Views/PayGateView.swift

| Line | Current | Recommended |
|------|---------|-------------|
| 59 | `xmark.circle.fill` | `xmark.circle` |
| 172 | `lock.fill` | `lock` |
| 190 | `lock.fill` | `lock` |

---

### StepsTrader/Views/OnboardingDemoView.swift

| Line | Current | Recommended |
|------|---------|-------------|
| 52 | `xmark.circle.fill` | `xmark.circle` |

---

### StepsTrader/Views/ProfileEditorView.swift

| Line | Current | Recommended |
|------|---------|-------------|
| 57 | `camera.fill` | `camera` |

---

### StepsTrader/Views/RadialHoldMenu.swift

| Line | Current | Recommended |
|------|---------|-------------|
| 20 | `heart.fill` | `heart` |

---

### StepsTrader/Views/Settings/GradientPreviewSheet.swift

| Line | Current | Recommended |
|------|---------|-------------|
| 69 | `xmark.circle.fill` | `xmark.circle` |
| 126 | `moon.fill` | `moon` |
| 129 | `sun.max.fill` | `sun.max` |

---

### StepsTrader/Views/Settings/SettingsPermissionsPage.swift

| Line | Current | Recommended |
|------|---------|-------------|
| 55 | `heart.fill` | `heart` |
| 95 | `bell.fill` | `bell` |
| 136 | `exclamationmark.triangle.fill` | `exclamationmark.triangle` |
| 191 | `checkmark.circle.fill` | `checkmark.circle` |

---

### StepsTrader/Views/Settings/SettingsEnergyPage.swift

| Line | Current | Recommended |
|------|---------|-------------|
| 54 | `bed.double.fill` | `bed.double` |

---

### StepsTrader/Views/Settings/SettingsWidgetPage.swift

| Line | Current | Recommended |
|------|---------|-------------|
| 122 | `checkmark.circle.fill` | `checkmark.circle` |

---

### UnlockWidget/UnlockWidgetViews.swift

| Line | Current | Recommended |
|------|---------|-------------|
| 133 | `bolt.fill` | `bolt` |
| 266 | `shoeprints.fill` | `shoeprints` |
| 267 | `bed.double.fill` | `bed.double` |
| 272 | `heart.fill` | `heart` |
| 368 | `lock.fill` | `lock` |
| 427 | `app.fill` | `app` |
| 466 | `bolt.fill` | `bolt` |
| 477 | `bolt.fill` | `bolt` |
| 675 | `lock.fill` | `lock` |
| 716 | `app.fill` | `app` |

---

### ShieldConfiguration/ShieldConfigurationExtension.swift

| Line | Current | Recommended |
|------|---------|-------------|
| 65 | `shield.fill` | `shield` |

---

## Already Compliant (Stroke Icons)

These icons are already using the correct outline/stroke style:

- `square.grid.2x2` — tab bar
- `person.circle` — tab bar
- `gearshape` — tab bar
- `plus` — action buttons
- `xmark` — dismiss buttons
- `chevron.left/right/up/down` — navigation
- `arrow.up.arrow.down` — sort
- `ticket` — ticket icon
- `ellipsis` — more menu
- `checkmark` — selection state
- `trash` — delete
- `dice` — randomize
- `clock` / `clock.arrow.circlepath` — time
- `hourglass` — waiting
- `envelope` — email
- `at` — username
- `lock.open` — unlocked state
- `questionmark.circle` — help
- `hand.draw` — drawing mode
- `arrow.up.left.and.arrow.down.right` — expand
- `arrow.down.right.and.arrow.up.left` — collapse
- `square.and.arrow.up` — share
- `square.and.arrow.down` — download
- `lock.screen` — lock screen
- `info.circle` — about
- `arrow.counterclockwise.circle` — reset
- `bell.badge` — notifications
- `sparkles` — AI/generative
- `list.bullet` — list view
- `hand.tap` — tap gesture
- `lock.shield` — security
- `apple.logo` — Apple Sign-In
- `arrow.clockwise` — refresh
- `moon.zzz` — sleep (widget)
- `app` — TicketTemplatePickerView line 147

---

## UI Surface Audit: Liquid Glass Compliance

### Glass Effects (Compliant)

The app already uses iOS 26 glass effects correctly:

| Component | Implementation | Status |
|-----------|---------------|--------|
| `GlassCardModifier` | `.glassEffect(.regular, in: RoundedRectangle)` with `ultraThinMaterial` fallback | Compliant |
| Tab Bar (iOS 26) | `.glassEffect(.regular, in: RoundedRectangle(cornerRadius: 28))` | Compliant |
| Tab Bar (fallback) | `.ultraThinMaterial` in RoundedRectangle | Compliant |
| StepBalanceCard | `.glassEffect(.regular, in: RoundedRectangle(cornerRadius: 16))` | Compliant |
| Settings pages | `.glassCard()` modifier throughout | Compliant |

### Material Backgrounds (Review Needed)

These use `ultraThinMaterial` without an iOS 26 glass upgrade path:

| File | Line | Usage |
|------|------|-------|
| `AppsPageSimplified.swift` | 87, 104, 303 | `.fill(.ultraThinMaterial)` |
| `LoginView.swift` | 215 | `.fill(.ultraThinMaterial)` |
| `HandoffProtectionView.swift` | 62 | `.fill(.ultraThinMaterial)` |
| `RadialHoldMenu.swift` | 93, 149 | `.fill(.ultraThinMaterial)` |
| `GalleryView.swift` | 413, 440, 532, 575, 796, 831, 891 | `.fill(.ultraThinMaterial)` |
| `QuickStatusView.swift` | 41, 54 | `.fill(.ultraThinMaterial)` |
| `CoachMarkOverlay.swift` | 123, 173, 336 | `.fill(.ultraThinMaterial)` |
| `WorkoutSuggestionBanner.swift` | 120 | `.background(.ultraThinMaterial, ...)` |
| `OnboardingStoriesView.swift` | 1682 | `.fill(.ultraThinMaterial.opacity(0.6))` |
| `MeView.swift` | 238, 298 | `.fill(.thinMaterial)` |

**Recommendation:** Wrap these in `if #available(iOS 26.0, *)` checks and use `.glassEffect()` on iOS 26+, similar to the existing `GlassCardModifier` pattern.

---

### Symbol Rendering Mode

The app uses `.symbolRenderingMode(.hierarchical)` in select places (MainTabView, LoginView, PayGateView, GradientPreviewSheet). This is correct for iOS 26 — hierarchical rendering pairs well with outline icons on glass surfaces.

**Recommendation:** Apply `.symbolRenderingMode(.hierarchical)` more broadly to icons displayed on glass surfaces for consistent depth layering.

---

## Font Weight on Glass (Minor)

Several places use `.font(.title2.bold())` or `.fontWeight(.bold)` on glass surfaces:

| File | Lines |
|------|-------|
| `GalleryView.swift` | 1136, 1183, 1191, 1208, 1216 |
| `QuickStatusView.swift` | 22, 37, 49 |
| `HandoffProtectionView.swift` | 22 |

**Recommendation:** iOS 26 Liquid Glass prefers medium/semibold weights over bold for content overlaid on glass. Consider `semibold` where visual hierarchy allows.

---

## Priority Action Items

1. **HIGH — Tab Bar Icons:** Change `paintbrush.fill` → `paintbrush` and `book.fill` → `book` in `MainTabView.swift`
2. **HIGH — StepBalanceCard icons:** Change category indicators (`shoeprints.fill`, `bed.double.fill`, `heart.fill`) to stroke
3. **HIGH — Widget icons:** Convert all `.fill` icons in `UnlockWidgetViews.swift` to stroke variants
4. **MEDIUM — DailyEnergy model:** Convert all 40+ filled icons in energy options and icon picker arrays
5. **MEDIUM — Dismiss buttons:** Change `xmark.circle.fill` → `xmark.circle` across all dismiss/close buttons
6. **MEDIUM — Lock icons:** Change `lock.fill` → `lock` in PayGateView and PaperTicketView
7. **LOW — Material surfaces:** Add `if #available(iOS 26.0, *)` glass effect upgrades to remaining `ultraThinMaterial` usages
8. **LOW — Font weights:** Soften bold → semibold on glass-backed text elements

---

## Notes

- The `GlassCardModifier` is well-implemented with proper iOS version gating
- The custom tab bar already uses glass effect on iOS 26 with material fallback
- `.symbolRenderingMode(.hierarchical)` is already applied to tab icons — good practice
- Icons in context menus (Labels with systemImage) are managed by the system and don't need changes
- Widget icons should also be stroke-based as widgets render on the home screen glass layer in iOS 26
