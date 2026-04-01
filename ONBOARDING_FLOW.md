# Onboarding Flow — Nowhere v4

**Status:** Approved structure — ready for implementation
**Slides:** 9 (down from 13)
**Estimated completion time:** 45–70 seconds

---

## Emotional Arc

```
RECOGNITION → REVELATION → WONDER → AGENCY → TRUST → UNDERSTANDING → COMMITMENT → CONNECTION → BELONGING
     1              1           2       3,4       5          6              7             8          9
```

The arc follows a single rule: **feel first, understand second, act last.**

---

## Global Behaviors

### Navigation
- **Forward:** bottom button (always visible)
- **Back:** tap left ⅓ of screen OR swipe right (standard stories pattern)
- **Back is disabled** on slide 1 (nothing to go back to)
- `scrollDisabled(true)` stays — we control pacing, but back gives escape

### Progress Bar
- 9 segments, **grouped into 3 phases** with subtle spacing:
  - Phase 1 (Story): slides 1–2
  - Phase 2 (Setup): slides 3–6
  - Phase 3 (Action): slides 7–9
- 3px height (up from 2px for visibility)
- Filled segments use `AppColors.brandAccent`, unfilled use accent at 0.12 opacity

### Background
- `EnergyGradientRenderer` with `warmSunset` palette, progress-driven opacity (same as current)
- Background figure image (`onboarding_figure_1` — fix the typo from `figuer`) stays
- Grain overlay at 0.2 stays

### Floating Elements
- **Active only on non-interactive slides:** 1, 2, 6, 9
- **Paused on interactive slides:** 3, 4, 5, 7, 8
- Reduces distraction during input and saves battery

### Haptics
- `UIImpactFeedbackGenerator(.light)` on each slider step change (slides 3, 4)
- `UINotificationFeedbackGenerator(.success)` when a permission is granted
- `UIImpactFeedbackGenerator(.medium)` on final "let's go" button

### Analytics (per-slide)
Every slide fires two events via `SupabaseSyncService.trackAnalyticsEvent`:

```
onboarding_slide_viewed
  properties: { slide_index, slide_name, flow_version: "v4" }

onboarding_slide_completed
  properties: { slide_index, slide_name, flow_version: "v4", duration_ms, action_taken }
```

`action_taken` values: `next`, `back`, `permission_granted`, `permission_denied`, `skipped`, `signed_in`, `finished`

An **anonymous session ID** is generated on first appear (UUID stored in UserDefaults) so events are attributable even before Apple Sign In.

### Permission Handling
- Each permission is requested **exactly once**, on its designated slide
- `finishOnboarding()` does NOT re-request any permission
- If a permission was already granted (e.g., re-running onboarding from settings), the slide detects this and shows "already enabled" state instead of the system prompt

---

## Slide-by-Slide Specification

---

### Slide 1 — THE HOOK

**Emotion:** Recognition → Revelation
**Type:** `nowHereReveal` (new type)

**Copy:**
```
Line 1: "Lately I've felt stuck in nowhere."
Line 2: "Working, scrolling, staring at a screen."

[pause 1.2s]

Line 3: "So I decided to turn"
```

**Visual:**
- After line 3 appears, the word **NOWHERE** renders in large serif type (centered)
- After 0.8s, a typographic animation **splits** it: `NOW  HERE`
  - The space opens from the center — letters slide left and right
  - The accent color (#FFD369) bleeds into the gap as it opens
- Below: `"And built this app."`

**Button:** "Next"
**Back:** Disabled (first slide)
**Floaters:** Active (ambient, low density)

**Why this works:** The wordplay IS the brand. Currently it's a plain text sentence. This is the single most memorable moment in the entire app — it deserves a visual payoff. Users who see this animation will screenshot it and share it.

---

### Slide 2 — THE CANVAS

**Emotion:** Wonder
**Type:** `canvasPreview` (new type)

**Copy:**
```
Line 1: "Each day is a canvas"
Line 2: "you color by living real life."
Line 3: "Every 24 hours, it resets."
```

**Visual:**
- Below the text: a **mini canvas preview** (roughly 200x200pt)
- The canvas uses `EnergyGradientRenderer` with `warmSunset` palette
- On appear, it animates from empty (dark) to ~60% filled over 3 seconds
  - Gold blobs fade in (simulating steps)
  - Navy tones deepen (simulating sleep)
  - Small colored shapes appear (simulating activities)
- This is NOT interactive — it's a showcase of what the user's daily canvas will look like

**Button:** "Next"
**Back:** Tap left ⅓ or swipe right → slide 1
**Floaters:** Active (body/mind/heart shapes, reinforcing the canvas concept)

**Why this works:** "Each day is a canvas" is the pitch. Show it, don't just say it. The old version was identical to a plain text slide — zero visual differentiation.

---

### Slide 3 — STEPS

**Emotion:** Agency
**Type:** `stepsSetup` (existing)

**Copy:**
```
Line 1: "Walking adds bright color."
Line 2: "I feel best around 7k steps."
Line 3: "How about you?"
```

**Visual:**
- Large accent-colored number showing current target (e.g., `10,000`)
- Below: "steps" label in muted white
- Below: slider (5,000–15,000, step 500)
- Below slider: min/max labels

**Interactive:**
- Slider with haptic feedback on each 500-step increment
- Number updates in real-time with the slider

**Button:** "Next"
**Back:** Tap left ⅓ or swipe right → slide 2
**Floaters:** Paused (user is focused on input)
**Default value:** 10,000

---

### Slide 4 — SLEEP

**Emotion:** Agency
**Type:** `sleepSetup` (existing)

**Copy:**
```
Line 1: "Sleep adds the dark tones."
Line 2: "For me, 9 hours is the sweet spot."
Line 3: "What about you?"
```

**Visual:**
- Large accent-colored number showing current target (e.g., `8.0`)
- Below: "hours" label in muted white
- Below: slider (6–10h, step 0.5)
- Below slider: min/max labels

**Interactive:**
- Slider with haptic feedback on each 0.5h increment
- Number updates in real-time

**Button:** "Next"
**Back:** → slide 3
**Floaters:** Paused
**Default value:** 8.0

---

### Slide 5 — HEALTH PERMISSION

**Emotion:** Trust
**Type:** `text` with action (existing pattern)

**Copy:**
```
Line 1: "To color your canvas,"
Line 2: "share your steps and sleep data."
```

**Microcopy** (below main text, smaller, muted):
```
"you can change this later in Settings"
```

**Visual:** Standard text slide layout. The microcopy is new — it reduces anxiety about granting permissions by making the decision feel reversible.

**Button:** "Allow" → triggers HealthKit authorization
**Action:** `.requestHealth`
**Back:** → slide 4
**Floaters:** Paused (system dialog will appear)

**Post-action:** After permission dialog dismisses, auto-advance to slide 6 after 0.5s delay. If user denies, still advance — don't trap them.

---

### Slide 6 — COLORS

**Emotion:** Understanding
**Type:** `colorsExplainer` (new type, replaces old `colorsDemo` + the philosophy from old slide 8)

**Copy:**
```
Line 1: "Colors show how intentionally"
Line 2: "you lived the day."
Line 3: "You can't buy them — only live them."
```

**Visual:**
- Below text: the color source breakdown (same chips as current `colorsDemo`)
  - Row 1: [Steps icon] 20 / [Sleep icon] 20
  - Row 2: [Body icon] 20 / [Mind icon] 20 / [Heart icon] 20
- Below chips: a subtle "= 100 colors / day" total in accent color
- The chips animate in one by one (staggered 0.15s each) on appear

**Button:** "Next"
**Back:** → slide 5
**Floaters:** Active (body/mind/heart shapes become relevant here — visual connection to the chips)

**What changed:** Old slides 7 ("Hit your targets to earn colors...") and 8 ("What are colors?...") are merged. The philosophy and the mechanics are now one slide. Family Controls permission is decoupled from here and moved to slide 7 where it belongs — right before the user picks an app.

---

### Slide 7 — FEEDS

**Emotion:** Commitment (optional)
**Type:** `feedSelection` (existing, heavily modified)

**Copy:**
```
Line 1: "Spend colors to unlock apps"
Line 2: "you've chosen to close."
Line 3: "Pick your first — or skip for now."
```

**Visual:**
- 8-app grid (same apps as current: Instagram, TikTok, YouTube, X, Reddit, Facebook, Snapchat, Telegram)
- Tapping an app:
  1. Triggers Family Controls authorization (if not yet granted)
  2. Opens `FamilyActivitySelection` picker
  3. On picker dismiss with selection → checkmark appears, app is selected
- Below grid (after selection): microcopy in accent color:
  ```
  "I'll nudge you when colors are ready."
  ```
  This replaces the old standalone notifications slide. Tapping "Next" after a selection triggers the notification permission request inline.

**Interactive:**
- App grid selection
- FamilyActivitySelection system picker (same as current)

**Button:** "Next" — **ALWAYS ENABLED** (no longer blocks progress)
- If user has a selection → fires `.requestNotifications` on advance, then proceeds
- If user skips → proceeds without any permission request

**Secondary action:** "skip for now" text link below the grid (same behavior as tapping Next without a selection)

**Back:** → slide 6
**Floaters:** Paused (interactive + system picker)

**What changed:**
- **Not a hard blocker anymore.** The `isNextDisabled` gate is removed. Users who aren't ready to commit can explore the app first and set up feeds later.
- **Family Controls and Notifications are requested here**, contextually, not on separate slides. Family Controls fires when user taps an app. Notifications fire when user advances past this slide with a selection.
- Old slide 10 (standalone notifications) and old slide 11 (wallpaper filler) are eliminated.

---

### Slide 8 — IDENTITY

**Emotion:** Connection
**Type:** `appleLogin` (existing)

**Copy:**
```
Line 1: "By the way, I'm Kosta."
Line 2: "Who are you?"
```

**Visual:**
- Text centered vertically
- Below: if not signed in → Sign in with Apple button (standard `ASAuthorizationAppleIDButton`)
- Below button: "continue without signing in" text link
- If signed in → green checkmark + "Signed in" confirmation (same as current)

**Button:**
- Not signed in: "Sign in" → triggers Apple Sign In flow
- Signed in: "Next" → advances
- "continue without signing in" link always visible → advances

**Back:** → slide 7
**Floaters:** Paused

**What changed:**
- "continue without signing in" skip link is new — lets users opt out gracefully
- Login stays at this position in the flow (Editor, UX, and User all argued for late login; PM/Investor are satisfied by anonymous session ID from slide 1)

---

### Slide 9 — WELCOME

**Emotion:** Belonging
**Type:** `welcome` (modified)

**Copy:**
```
"Welcome to Nowhere, [name]."
```

Where `[name]` is:
1. Apple Sign In display name (if signed in)
2. Fallback to empty → just "Welcome to Nowhere."

**Visual:**
- Text centered
- The `[name]` part animates in: 0.3s delay, then scale from 0.85→1.0 with opacity 0→1
- If no name, just "Welcome to Nowhere." with the same gentle fade
- Background gradient reaches full warmth (progress = 1.0)

**Button:** "Let's go" → calls `finishOnboarding()`
**Back:** → slide 8
**Floaters:** Active (full density — all shapes visible, celebrating the moment)
**Haptic:** `UIImpactFeedbackGenerator(.medium)` on "Let's go" tap

---

## finishOnboarding() Changes

```swift
private func finishOnboarding() {
    // 1. Save targets
    let defaults = UserDefaults.stepsTrader()
    defaults.set(stepsTarget, forKey: "userStepsTarget")
    defaults.set(sleepTarget, forKey: "userSleepTarget")
    
    // 2. Create ticket group if user selected an app
    let hasApps = !onboardingSelection.applicationTokens.isEmpty
        || !onboardingSelection.categoryTokens.isEmpty
    if hasApps {
        let name = selectedFeedApp.map { TargetResolver.displayName(for: $0) }
            ?? String(localized: "My Apps")
        let group = model.createTicketGroup(name: name, templateApp: selectedFeedApp)
        model.addAppsToGroup(group.id, selection: onboardingSelection)
    }
    
    // 3. Recalculate energy
    Task { @MainActor in
        model.recalculateDailyEnergy()
    }
    
    // 4. Track completion with rich properties
    Task {
        await SupabaseSyncService.shared.trackAnalyticsEvent(
            name: "onboarding_completed",
            properties: [
                "flow": "v4",
                "steps_target": String(Int(stepsTarget)),
                "sleep_target": String(format: "%.1f", sleepTarget),
                "selected_feed": selectedFeedApp ?? "none",
                "selected_apps_count": String(onboardingSelection.applicationTokens.count),
                "signed_in": String(authService.isAuthenticated),
                "skipped_feed_selection": String(!hasApps),
                "total_duration_ms": String(totalOnboardingDurationMs)
            ],
            dedupeKey: "onboarding_completed_v1"
        )
    }
    
    // 5. NO duplicate permission requests here
    // Permissions are requested exactly once, on their designated slides:
    //   - HealthKit: slide 5
    //   - Family Controls: slide 7 (when user taps an app)
    //   - Notifications: slide 7 (on advance, if user selected an app)
    
    // 6. Complete
    withAnimation(.easeInOut(duration: 0.3)) {
        onComplete()
    }
}
```

**Key difference:** Lines 86–89 of the old `finishOnboarding()` (re-requesting notifications + Family Controls) are **deleted**.

---

## Slide Type Enum (Updated)

```swift
enum OnboardingSlideType: Equatable {
    case text
    case nowHereReveal      // NEW — slide 1
    case canvasPreview      // NEW — slide 2
    case stepsSetup         // existing — slide 3
    case sleepSetup         // existing — slide 4
    case colorsExplainer    // NEW — slide 6 (replaces colorsDemo)
    case feedSelection      // existing — slide 7
    case appleLogin         // existing — slide 8
    case welcome            // replaces generic text for slide 9
}
```

**Removed types:** `activitySelection`, `nameInput`, `avatarSetup`, `welcomeWithName`, `canvasDemo`, `colorsDemo`
These were either unused in the current flow or replaced by new types.

---

## Slide Action Enum (Updated)

```swift
enum OnboardingSlideAction: Equatable {
    case none
    case requestHealth
    case requestNotifications
    case requestFamilyControls
}
```

**Removed:** `.requestLocation` (not used in this flow)

---

## Slide Definitions (Swift)

```swift
private func mainSlides() -> [OnboardingSlide] {
    let displayName: String = {
        if let name = authService.currentUser?.displayName
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !name.isEmpty {
            return name
        }
        return ""
    }()

    let welcomeLine = displayName.isEmpty
        ? String(localized: "Welcome to Nowhere.")
        : String(localized: "Welcome to Nowhere, \(displayName).")

    return [
        // 1 — hook + reveal
        OnboardingSlide(
            lines: [
                String(localized: "Lately I've felt stuck in nowhere."),
                String(localized: "Working, scrolling, staring at a screen."),
                String(localized: "So I decided to turn")
            ],
            slideType: .nowHereReveal
        ),
        
        // 2 — canvas
        OnboardingSlide(
            lines: [
                String(localized: "Each day is a canvas"),
                String(localized: "you color by living real life."),
                String(localized: "Every 24 hours, it resets.")
            ],
            slideType: .canvasPreview
        ),
        
        // 3 — steps
        OnboardingSlide(
            lines: [
                String(localized: "Walking adds bright color."),
                String(localized: "I feel best around 7k steps."),
                String(localized: "How about you?")
            ],
            slideType: .stepsSetup
        ),
        
        // 4 — sleep
        OnboardingSlide(
            lines: [
                String(localized: "Sleep adds the dark tones."),
                String(localized: "For me, 9 hours is the sweet spot."),
                String(localized: "What about you?")
            ],
            slideType: .sleepSetup
        ),
        
        // 5 — health permission
        OnboardingSlide(
            lines: [
                String(localized: "To color your canvas,"),
                String(localized: "share your steps and sleep data.")
            ],
            action: .requestHealth
        ),
        
        // 6 — colors
        OnboardingSlide(
            lines: [
                String(localized: "Colors show how intentionally"),
                String(localized: "you lived the day."),
                String(localized: "You can't buy them — only live them.")
            ],
            slideType: .colorsExplainer
        ),
        
        // 7 — feeds (skippable)
        OnboardingSlide(
            lines: [
                String(localized: "Spend colors to unlock apps"),
                String(localized: "you've chosen to close."),
                String(localized: "Pick your first — or skip for now.")
            ],
            slideType: .feedSelection
        ),
        
        // 8 — identity
        OnboardingSlide(
            lines: [
                String(localized: "By the way, I'm Kosta."),
                String(localized: "Who are you?")
            ],
            slideType: .appleLogin
        ),
        
        // 9 — welcome
        OnboardingSlide(
            lines: [welcomeLine],
            slideType: .welcome
        )
    ]
}
```

---

## What Was Cut (and Where It Went)

| Old Slide | Decision | Destination |
|-----------|----------|-------------|
| 1 + 2 (story) | **Merged** into slide 1 with typographic reveal | — |
| 7 (colors demo) + 8 (colors philosophy) | **Merged** into slide 6 | — |
| 10 (notifications) | **Absorbed** into slide 7 (contextual, after feed selection) | — |
| 11 (wallpaper) | **Cut** | Post-onboarding tooltip on Canvas tab |
| Duplicate permissions in `finishOnboarding()` | **Deleted** | — |

---

## Implementation Order

1. **Per-slide analytics + remove duplicate permissions** — quick win, no UI changes
2. **Back navigation** — add tap-left-third and swipe-right gesture
3. **Make feed selection skippable** — remove `isNextDisabled` gate
4. **Restructure slide array** — new 9-slide sequence, new types
5. **Build `nowHereReveal` slide** — typographic split animation
6. **Build `canvasPreview` slide** — mini canvas with fill animation
7. **Build `colorsExplainer` slide** — staggered chip animation
8. **Build `welcome` slide** — name scale animation
9. **Add haptics** throughout
10. **Bundle notifications into feed selection** — contextual request
11. **Polish** — progress bar phases, floater pause logic, microcopy
