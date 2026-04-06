# Nowhere — Onboarding Flow (v7)

**Status:** Implemented  
**Version:** v7  
**Based on:** v6 (11 slides) → narrative rewrite + canvas intro + customization = 13 slides  
**Estimated completion time:** 60–80 seconds  
**Last updated:** April 4, 2026

---

## Table of Contents

1. [Core "Aha!" Moment](#1-core-aha-moment)
2. [Flow Overview & Diagram](#2-flow-overview--diagram)
3. [Screen-by-Screen Specification](#3-screen-by-screen-specification)
4. [Product-Led Recommendations](#4-product-led-recommendations)
5. [Micro-Copy Reference](#5-micro-copy-reference)
6. [Technical Implementation Notes](#6-technical-implementation-notes)

---

## 1. Core "Aha!" Moment

### Definition

The **aha moment** for Nowhere is:

> **The user sees that their real-world actions produce something visible (colors on a canvas) — and then feels the cost of spending those colors to open a feed.**

This is not a single tap. It's a two-beat realization:

1. **Beat 1 — "My day makes something."** The user taps five category orbs (steps, sleep, body, mind, heart) and watches a ring fill to 100 — their real life has a visual output.

2. **Beat 2 — "Opening feeds costs what I lived."** The user sees a locked app and picks a time window to unlock it, watching the color pool drain. Scrolling isn't free — it costs presence.

**When it should happen:** Within the first 45 seconds of onboarding (slides 0–5 in the v7 flow).

**Why this is the aha and not something else:**
- It's *not* blocking an app (that's the mechanism, not the insight)
- It's *not* earning steps (that's an input, not the value)
- It's the **connection** between living and spending that no other app makes tangible

### Activation Metric

A user is "activated" when they have:
- Set step and sleep targets (even at defaults)
- Granted HealthKit access
- Completed onboarding (reached the main canvas)

Bonus activation (strongest predictor of D7 retention, speculative):
- Selected at least one feed to block during onboarding

---

## 2. Flow Overview & Diagram

### Phase Structure

The 13 screens (indices 0–12) group into **3 phases** that mirror the emotional arc:

| Phase | Slides | Emotion | Purpose |
|-------|--------|---------|---------|
| **Story** | 0–5 | Recognition → Agency → Wonder | The founder's story + how the economy works |
| **Setup** | 6–9 | Agency → Trust | Collect targets, grant permissions |
| **Action** | 10–12 | Commitment → Belonging | Identity, customization teaser, welcome |

### Flow Diagram

```
Launch
  │
  ▼
┌──────────────────────────────────────────────────────────────┐
│  PHASE 1: STORY                                              │
│                                                              │
│  [0] Recognition ─► [1] NOWHERE → NOW HERE (the turn)       │
│                           │                                  │
│                           ▼                                  │
│  [2] Canvas Concept ─► [3] Color Cap (tap 5 orbs)            │
│                                 │                            │
│                                 ▼                            │
│              [4] Spend Demo (feeds UI) ─► [5] The Economy    │
└──────────────────────────────────────────────────────────────┘
  │
  ▼
┌──────────────────────────────────────────────────────────────┐
│  PHASE 2: SETUP                                              │
│                                                              │
│  [6] Steps Target ─► [7] Sleep Target ─► [8] HealthKit      │
│                                                │             │
│                                                ▼             │
│                              [9] Feed Selection (skippable)  │
│                         (bundles Family Controls + Notifs)    │
└──────────────────────────────────────────────────────────────┘
  │
  ▼
┌──────────────────────────────────────────────────────────────┐
│  PHASE 3: ACTION                                             │
│                                                              │
│  [10] Identity (skippable) ─► [11] Make It Yours ─►          │
│                                       [12] Welcome           │
└──────────────────────────────────────────────────────────────┘
  │
  ▼
Main App (Canvas tab)
```

### One-Line Flow

```
Launch → Recognition → Name Reveal → Canvas Concept → Color Cap → Spend Demo → Economy → Steps → Sleep → HealthKit → Feeds → Identity → Make It Yours → Welcome → Main App
```

### What Changed from v6 (11 slides)

| v6 Slide | Decision | v7 Destination |
|----------|----------|----------------|
| 0 (cold open) | **Rewritten** — new copy follows founder narrative: "i live one day over and over" | Slide 0 |
| 1 (now here reveal) | **Rewritten** — "it felt like being stuck in" + "so i made this app." | Slide 1 |
| — | **New** — canvas concept slide introduces the canvas before interactive demos | Slide 2 |
| 2 (color cap) | **Kept** — copy unchanged | Slide 3 |
| 3 (spend demo) | **Rewritten** — "spend them on the apps that pull you away" | Slide 4 |
| 4 (how it works) | **Rewritten** — "an economy between online and offline" | Slide 5 |
| 5 (steps setup) | **Rewritten** — "walking fills the canvas. how far do you go?" | Slide 6 |
| 6 (sleep setup) | **Rewritten** — "sleep deepens the dark. how many hours feel right?" | Slide 7 |
| 7 (health permission) | **Rewritten** — "let your phone see what your body already knows." | Slide 8 |
| 8 (feed selection) | **Rewritten** — "where does your reality fade?" | Slide 9 |
| 9 (apple login) | **Kept** | Slide 10 |
| — | **New** — wallpaper + widget teaser with iOS caveat | Slide 11 |
| 10 (welcome) | **Kept** | Slide 12 |

**Change:** 11 → 13 slides (+2). Added: canvas concept (slide 2), customization teaser (slide 11). Sleep slide gains microcopy about iOS update lag. All copy rewritten to follow the founder's personal narrative.

---

## 3. Screen-by-Screen Specification

---

### Slide 0 — RECOGNITION

**Position in flow:** First screen after launch (app cold start, `hasCompletedOnboarding == false`)  
**Goal:** The user sees themselves — "I live like this too"  
**Slide type:** `coldOpen`  
**Phase:** Story

#### UI Elements

| Element | Description |
|---------|-------------|
| **Background** | `EnergyGradientRenderer`, `warmSunset` palette, low progress (dark, moody) |
| **Floating elements** | Active — body/mind/heart shapes at low density, ambient motion |
| **Figure** | `onboarding_figuer_1` image at bottom, opacity 0.3 (fades to full on later slides) |
| **Copy block** | Two lines, staggered fade-in after 500ms |
| **Progress bar** | 12 segments, grouped 6-4-2 with spacing; segment 0 filled |
| **CTA** | "Next" (gold, full-width, bottom) |
| **Back** | Disabled (first slide) |

#### Copy

```
Line 1: "i found that i live one day over and over."
Line 2: "working. scrolling. staring at a screen."
```

#### Why This Design

The founder speaks first. Not the brand, not a feature pitch. The copy mirrors the user's own realization — the same loop of work and scroll. Two short punches instead of one. Users who relate stay.

---

### Slide 1 — THE TURN (NOWHERE → NOW HERE)

**Position in flow:** After recognition  
**Goal:** The founder names the feeling and flips it — nowhere becomes now here  
**Slide type:** `nowHereReveal`  
**Phase:** Story

#### UI Elements

| Element | Description |
|---------|-------------|
| **Background** | Same gradient, slightly progressed |
| **Floating elements** | Active — body/mind/heart shapes |
| **Copy block** | "it felt like being stuck in" fades in (phase 1), then NOWHERE text appears |
| **Typography reveal** | After 1.2s, large serif "NOWHERE" splits into "NOW | HERE" with accent gold (#FFD369) bleeding into the gap (phase 2) |
| **Closing line** | "so i made this app." fades in below the split (phase 3) |
| **Progress bar** | Segment 1 filled |
| **CTA** | "Next" |
| **Back** | Swipe right (>60pt) → slide 0 |

#### Copy

```
Line 1: "it felt like being stuck in"

[NOWHERE → NOW | HERE animation]

Line 2: "so i made this app."
```

#### Animation Sequence

1. **Phase 1** (500ms delay): "it felt like being stuck in" fades in with NOWHERE text visible
2. **Phase 2** (1200ms after phase 1): NOWHERE splits — `nowhereSplit` animates to 20pt gap, gold accent rectangle bleeds into the gap, text color shifts to accent gold. Spring animation (response: 1.0, dampingFraction: 0.75).
3. **Phase 3** (1200ms after phase 2): "so i made this app." fades in below

#### Haptics

- `UIImpactFeedbackGenerator(.heavy)` on the NOWHERE → NOW HERE split moment (phase 2)
- `UINotificationFeedbackGenerator(.success)` when "so i made this app." appears (phase 3)

#### Why This Design

The storyline now follows a natural arc: recognition → naming the problem → agency. "it felt like being stuck in NOWHERE" is the low point, and the split animation physically transforms the word into its opposite. "so i made this app." is the turn — the founder decided to act, and the user is about to see what came from it.

---

### Slide 2 — THE CANVAS

**Position in flow:** After the name reveal, before the interactive demos  
**Goal:** Introduce what the app actually is — a canvas that reflects your real day  
**Slide type:** `text`  
**Phase:** Story

#### UI Elements

| Element | Description |
|---------|-------------|
| **Background** | Gradient continuing |
| **Floating elements** | Active |
| **Copy block** | Three lines, staggered fade-in |
| **Progress bar** | Segment 2 filled |
| **CTA** | "Next" |
| **Back** | Swipe right (>60pt) → slide 1 |

#### Copy

```
Line 1: "your day lives on a canvas."
Line 2: "the background comes from steps and sleep."
Line 3: "what colors it are the things you notice."
```

#### Why This Design

This bridges the emotional hook (slides 0–1) with the interactive mechanic (slides 3–4). Without it, users jump from "so i took control" straight into tapping orbs with no context for what the canvas means. Three lines paint the full picture: the canvas exists, the background is passive (steps/sleep), and color is active (the things you notice). The phrasing "things you notice" deliberately avoids jargon — it'll map to body/mind/heart activities later, but here it's just presence.

---

### Slide 3 — COLOR CAP (Interactive)

**Position in flow:** After canvas concept, before spend demo  
**Goal:** Teach the five sources of color — steps, sleep, body, mind, heart = 100 max  
**Slide type:** `colorCap`  
**Phase:** Story

#### UI Elements

| Element | Description |
|---------|-------------|
| **Background** | Gradient continuing |
| **Floating elements** | Paused (interactive slide) |
| **Copy block** | Two lines, centered |
| **Ring** | 160pt circle, fills as orbs are tapped |
| **Central counter** | Shows accumulated colors (0 → 20 → 40 → ... → 100) as orbs are tapped |
| **Category orbs** | 5 orbs around the ring at equal angles: steps (gold), sleep (navy), body (green), mind (blue), heart (pink) |
| **Post-tap microcopy** | Appears when all 5 are tapped |
| **Progress bar** | Segment 3 filled |
| **CTA** | "Next" |
| **Back** | Swipe right (>60pt) → slide 2 |

#### Copy

```
Line 1: "one hundred colors. that's a full day."
Line 2: "tap each to see."

[User taps 5 category orbs → ring fills to 100]

Microcopy (after all tapped): "you can't buy them — only live them."
```

#### Interaction Flow

1. Five orbs arranged in a ring: steps (`figure.walk`), sleep (`bed.double`), body (`figure.run`), mind (`brain.head.profile`), heart (`heart`)
2. Each tap adds +20 to central counter, fills 20% of progress ring
3. Tapped orbs shift from muted white to their category color with scale bump (1.0 → 1.1)
4. After all 5 tapped, ring is full, microcopy fades in

#### Haptics

- `UIImpactFeedbackGenerator(.light)` on each orb tap (1–4)
- `UINotificationFeedbackGenerator(.success)` when ring hits 100 (5th orb)

#### Why This Design

After the canvas concept (slide 2), this makes it tangible. Tapping each orb creates a physical memory of the five categories. The "+20" labels make the math self-evident. Now the user knows: 100 colors = a full day lived.

---

### Slide 4 — SPEND DEMO (Interactive)

**Position in flow:** After color cap, before economy  
**Goal:** Show the cost of scrolling — you spend your colors to open the apps that pull you away  
**Slide type:** `spendDemo`  
**Phase:** Story

#### UI Elements

| Element | Description |
|---------|-------------|
| **Background** | Gradient continuing |
| **Floating elements** | Paused (interactive slide) |
| **Copy block** | Two lines, centered |
| **Color pool counter** | Gold accent dot + count (starts at 100) + "colors" label |
| **App icon** | Instagram icon (56pt, rounded rect), locked state (0.4 opacity) / unlocked state (full opacity + green lock.open icon) |
| **Status line** | "Instagram is closed." when locked |
| **Tariff rows** | Three rows with time label and cost: "10 min · 4 colors", "30 min · 10 colors", "1 hour · 20 colors" |
| **Microcopy** | Changes based on state |
| **Progress bar** | Segment 4 filled |
| **CTA** | "Next" |
| **Back** | Swipe right (>60pt) → slide 3 |

#### Copy

```
Line 1: "spend them on the apps that pull you away."
Line 2: "pick how long."
Line 3: "the clock runs only when the screen is on."

[Color pool: 100 colors]

[Instagram icon — locked]
"Instagram is closed."

[Tariff rows]
10 min     4 colors
30 min     10 colors
1 hour     20 colors

[Before selection]
Microcopy: "pick a window to unlock it."

[After selecting a tariff, e.g., 30 min]
Microcopy: "30 min for 10 colors. that's the deal."
```

#### Interaction Flow

1. Color pool shows 100 (carried from color cap concept)
2. Instagram icon is locked (0.4 opacity)
3. User taps one of three tariff rows to unlock
4. Pool drains by the tariff cost, app icon becomes full opacity with green lock icon
5. After unlocking, all tariff rows become disabled — one purchase per demo
6. If user taps a tariff they can't afford → rigid haptic (shouldn't happen with 100 pool)

#### Tariff Data

| Label | Duration (min) | Cost (colors) |
|-------|---------------|---------------|
| 10 min | 10 | 4 |
| 30 min | 30 | 10 |
| 1 hour | 60 | 20 |

#### Haptics

- `UIImpactFeedbackGenerator(.medium)` on tariff selection (unlock)
- `UIImpactFeedbackGenerator(.rigid)` if "not enough" (can't afford)

#### Why This Design

The copy shift from "feeds cost colors" to "spend them on the apps that pull you away" directly continues the canvas narrative — you earned colors by living, and now you see where they go. "pick how long." is blunter and more personal than the old "pay what it's worth."

---

### Slide 5 — THE ECONOMY

**Position in flow:** After spend demo, before setup phase  
**Goal:** Name what's happening — an economy between online and offline  
**Slide type:** `howItWorks`  
**Phase:** Story

#### UI Elements

| Element | Description |
|---------|-------------|
| **Background** | Gradient at ~45% progress |
| **Floating elements** | Active |
| **Copy block** | Three lines, centered |
| **Loop icons** | Three circles in a row: earn (`figure.walk`) → spend (`lock.open`) → reset (`moon.fill`), connected by arrows |
| **Animated reveal** | Icons appear one at a time (500ms intervals), scaling from 0.9→1.0 with spring |
| **Midnight line** | Appears after all three icons are visible |
| **Progress bar** | Segment 5 filled |
| **CTA** | "Next" |
| **Back** | Swipe right (>60pt) → slide 4 |

#### Copy

```
Line 1: "an economy between online and offline."
Line 2: "earn by living. spend to scroll."
Line 3: "tomorrow, it resets."

[Animated icons: earn → spend → reset]

Microcopy (after animation): "at midnight, it resets."
```

#### Animation Sequence

1. **Phase 1** (500ms): earn icon appears
2. **Phase 2** (1000ms): spend icon appears
3. **Phase 3** (1500ms): reset icon appears
4. **Phase 4** (2000ms): "at midnight, it resets." microcopy fades in

#### Why This Design

This is the thesis statement. The founder already told you how the app works through the interactive demos — now they name the pattern. "an economy between online and offline" is the one-liner users will remember and tell friends. "earn by living. spend to scroll." compresses the entire mechanic into six words. "tomorrow, it resets." closes the loop and invites daily return.

---

### Slide 6 — STEPS TARGET

**Position in flow:** Start of setup phase  
**Goal:** Set daily step target  
**Slide type:** `stepsSetup`  
**Phase:** Setup

#### UI Elements

| Element | Description |
|---------|-------------|
| **Background** | Gradient at ~50% progress |
| **Floating elements** | Paused (user is adjusting slider) |
| **Copy block** | Two lines above the number |
| **Large number** | Steps target (serif, 60pt, thin weight, gold accent) |
| **Unit label** | "steps" below the number |
| **Slider** | 5,000–15,000, step 500, gold tint |
| **Min/max labels** | "5,000" and "15,000" |
| **Progress bar** | Segment 6 filled |
| **CTA** | "Next" |
| **Back** | Swipe right (>60pt) → slide 5 |

#### Copy

```
Line 1: "walking fills the canvas."
Line 2: "how far do you go?"

[10,000]
steps
|——————●——————|
5,000         15,000
```

#### Defaults

- Steps: 10,000 (stored in `SharedKeys.userStepsTarget`)

#### Haptics

- `UIImpactFeedbackGenerator(.light)` on each slider step change

---

### Slide 7 — SLEEP TARGET

**Position in flow:** After steps target  
**Goal:** Set daily sleep target  
**Slide type:** `sleepSetup`  
**Phase:** Setup

#### UI Elements

| Element | Description |
|---------|-------------|
| **Background** | Gradient continuing |
| **Floating elements** | Paused (user is adjusting slider) |
| **Copy block** | Two lines above the number |
| **Large number** | Sleep target (serif, 60pt, thin weight, gold accent, one decimal) |
| **Unit label** | "hours" below the number |
| **Slider** | 6–10h, step 0.5, gold tint |
| **Min/max labels** | "6h" and "10h" |
| **Progress bar** | Segment 7 filled |
| **CTA** | "Next" |
| **Back** | Swipe right (>60pt) → slide 6 |

#### Copy

```
Line 1: "sleep deepens the dark."
Line 2: "how many hours feel right?"

Microcopy: "sleep data may lag a bit — ios updates it on its own schedule."

[8.0]
hours
|——————●——————|
6h            10h
```

#### Defaults

- Sleep: 8.0 hours (stored in `SharedKeys.userSleepTarget`)

#### Haptics

- `UIImpactFeedbackGenerator(.light)` on each slider step change

#### iOS Caveat

Sleep data from HealthKit doesn't update in real time. iOS processes sleep sessions with its own cadence, so the canvas background may lag behind the user's actual sleep. The microcopy sets this expectation early so users don't think the app is broken.

---

### Slide 8 — HEALTHKIT PERMISSION

**Position in flow:** After sleep target (context: "you just set your targets — now let us read the real data")  
**Goal:** Grant HealthKit read access for steps, sleep, and activities  
**Slide type:** `text` with `.requestHealth` action  
**Phase:** Setup

#### UI Elements

| Element | Description |
|---------|-------------|
| **Background** | Gradient continuing |
| **Floating elements** | Active |
| **Copy block** | Two lines, centered, plus microcopy |
| **Progress bar** | Segment 8 filled |
| **CTA** | "Allow" → triggers HealthKit authorization system dialog |
| **Back** | Swipe right (>60pt) → slide 7 |

#### Copy

```
Line 1: "let your phone see what your body already knows."
Line 2: "steps, sleep, and the things you notice."

Microcopy: "you'll add activities after."
```

#### Permission Behavior

- Tapping "Allow" triggers `model.ensureHealthAuthorizationAndRefresh()` **once** (flag: `didTriggerHealthRequest`)
- If the system dialog is dismissed (granted or denied), auto-advance to slide 9 after 0.5s
- If permission was already granted (re-running onboarding from settings), show "already connected" state with a green checkmark and auto-advance
- **Never blocks progress** — user advances regardless of permission result

#### Why This Design

"let your phone see what your body already knows." flips the permission from a request to a revelation — you're not giving data, you're letting the phone notice what it already sees. "steps, sleep, and the things you notice." echoes slide 2's language ("the things you notice"), tying the permission back to the canvas concept. The shorter microcopy ("you'll add activities after.") is less instructional and more of a promise.

---

### Slide 9 — FEED SELECTION (Skippable)

**Position in flow:** After HealthKit, before identity  
**Goal:** (Optional) Select the first app to block — the strongest activation signal  
**Slide type:** `feedSelection`  
**Phase:** Setup

#### UI Elements

| Element | Description |
|---------|-------------|
| **Background** | Gradient at ~75% |
| **Floating elements** | Paused (interactive + system picker may appear) |
| **Copy block** | Two lines, centered |
| **App grid** | 4×2 grid of 8 popular apps (Instagram, TikTok, YouTube, X, Reddit, Facebook, Snapchat, Telegram); each shows icon + name |
| **Selected state** | Gold checkmark overlay on selected app; background highlight |
| **Post-selection microcopy** | Accent-colored text confirming nudge notifications |
| **Progress bar** | Segment 9 filled |
| **CTA** | "Next" (always enabled — never blocks progress) |
| **Skip** | "skip for now" text button below CTA (visible when nothing selected) |
| **Back** | Swipe right (>60pt) → slide 8 |

#### Copy

```
Line 1: "where does your reality fade?"
Line 2: "close one — or skip for now."

[After selecting an app and completing the FamilyActivitySelection picker]

Microcopy: "i'll nudge you when colors are ready to spend."
```

#### Permission Bundling

This single slide handles **two permissions contextually**:

1. **Family Controls** — requested when the user taps an app icon (before the `FamilyActivitySelection` picker opens). Fires `model.familyControlsService.requestAuthorization()` once.
2. **Push Notifications** — requested when the user advances past this slide **with a selection**. Fires `model.requestNotificationPermission()` once. If user skips (no selection), notifications are NOT requested here — deferred to post-onboarding.

#### Why This Design

"where does your reality fade?" hits harder than the v6 "where does your day disappear?" — it's not about time management, it's about presence. The rest of the slide mechanic is unchanged.

---

### Slide 10 — IDENTITY (Skippable)

**Position in flow:** After feed setup, before final welcome  
**Goal:** Apple Sign In for cross-device sync (fully optional)  
**Slide type:** `appleLogin`  
**Phase:** Action

#### UI Elements

| Element | Description |
|---------|-------------|
| **Background** | Gradient near full warmth |
| **Floating elements** | Paused |
| **Copy block** | Two lines, personal, founder voice |
| **Sign in state** | If not signed in: CTA triggers Apple Sign In; if signed in: green checkmark + "Signed in" |
| **Loading** | `ProgressView` during auth |
| **Progress bar** | Segment 10 filled |
| **CTA** | Not signed in: "Sign in" / Signed in: "Next" |
| **Skip** | "continue without signing in" text button (always visible when not signed in) |
| **Back** | Swipe right (>60pt) → slide 9 |

#### Copy

```
Line 1: "i'm kosta."
Line 2: "who are you?"

[If signed in]
✓ Signed in

[Skip link]
"continue without signing in"
```

#### Why This Design

Late-stage login is deliberate: by this point the user has lived through the founder's story, seen the economy, set targets, and optionally closed a feed. Asking for identity now feels earned, not extractive. The skip option ensures zero friction for users who want to explore anonymously first.

**Data collected at sign-in:** Apple ID user identifier, optional display name, optional email (per Apple Sign In privacy settings). Synced to Supabase for cross-device persistence.

---

### Slide 11 — MAKE IT YOURS

**Position in flow:** After identity, before final welcome  
**Goal:** Tease wallpaper + widget customization so users know it exists  
**Slide type:** `text`  
**Phase:** Action

#### UI Elements

| Element | Description |
|---------|-------------|
| **Background** | Gradient near full warmth |
| **Floating elements** | Active |
| **Copy block** | Three lines, staggered fade-in |
| **Progress bar** | Segment 11 filled |
| **CTA** | "Next" |
| **Back** | Swipe right (>60pt) → slide 10 |

#### Copy

```
Line 1: "set your canvas as a wallpaper."
Line 2: "add widgets — they update on their own."
Line 3: "if they feel behind, tap refresh. ios thing."
```

#### Why This Design

Users often discover wallpaper export and widgets days later — or never. Mentioning it here plants the seed while the user is still engaged. The third line ("ios thing") is honest about the platform constraint: iOS limits widget refresh frequency, so the displayed time may be stale until the user taps. Saying it upfront prevents a "broken app" perception later.

---

### Slide 12 — WELCOME

**Position in flow:** Last screen before the main app  
**Goal:** Emotional payoff — "you belong here"  
**Slide type:** `welcome`  
**Phase:** Action

#### UI Elements

| Element | Description |
|---------|-------------|
| **Background** | Gradient at full warmth (progress = 1.0); all floaters visible at full density |
| **Floating elements** | Active — all shapes, celebrating |
| **Copy block** | Personalized welcome text, centered |
| **Name animation** | User's display name scales from 0.85→1.0 with opacity 0→1 after 0.3s delay |
| **Tagline** | Muted below the name |
| **Progress bar** | Segment 12 filled (complete) |
| **CTA** | "let's go" (final — calls `finishOnboarding()`) |
| **Back** | Swipe right (>60pt) → slide 11 |

#### Copy

```
"welcome to nowhere"

[If signed in with display name]
"[Name]"
"you're here."

[If not signed in or no name]
"you're here."
```

#### Haptics

- `UIImpactFeedbackGenerator(.medium)` on "let's go" tap

#### What `finishOnboarding()` Does

1. Saves step and sleep targets to UserDefaults (App Group)
2. Creates a ticket group if user selected an app (with `TargetResolver.displayName`)
3. Recalculates daily energy
4. Tracks `onboarding_completed` analytics event with properties:
   - `flow: "v7"`, `steps_target`, `sleep_target`, `selected_feed`, `selected_apps_count`, `signed_in`, `skipped_feed_selection`, `total_duration_ms`
5. Sets `hasCompletedOnboarding = true`
6. Refreshes steps and sleep from HealthKit
7. Transitions to `MainTabView` (Canvas tab) with `.opacity` animation

**No duplicate permission requests in finishOnboarding().** Each permission fires exactly once on its designated slide.

---

## 4. Product-Led Recommendations

### 4.1 What Can Be Skipped or Deferred (Progressive Onboarding)

| Element | Skippable? | Defer Strategy |
|---------|-----------|----------------|
| **Canvas concept** (slide 2) | No — text-only, sets up the mental model | — |
| **Color cap** (slide 3) | No — it's the aha moment; user can simply tap "Next" without tapping orbs | Canvas tab in main app has its own interactive state |
| **Spend demo** (slide 4) | No — teaches the economy; user can tap "Next" without picking a tariff | PayGate teaches the same mechanic in-app |
| **Step target** (slide 6) | No — default (10k) applies if user doesn't adjust | Adjustable in Settings → Limits |
| **Sleep target** (slide 7) | No — default (8h) applies if user doesn't adjust | Adjustable in Settings → Limits |
| **HealthKit** (slide 8) | Yes — user advances regardless of permission result | Banner on Canvas tab: "connect Health to fill your canvas" |
| **Feed selection** (slide 9) | Yes — explicit "skip for now" button | Feeds tab empty state: "create one when you're ready." + prompt after D1/D3 |
| **Family Controls** (slide 9) | Yes — only triggered if user taps an app | Requested when user creates first ticket in main app |
| **Notifications** (slide 9) | Yes — only triggered if user selects a feed | Settings → Notifications; soft prompt after first feed creation |
| **Apple Sign In** (slide 10) | Yes — "continue without signing in" | Settings → Account; nudge after D3 ("sync your canvas across devices") |

### 4.2 Data Collection Strategy

| Data Point | When Collected | Why |
|------------|---------------|-----|
| **Steps target** | Onboarding slide 6 (default: 10,000) | Required to calculate daily energy; changes don't need re-onboarding |
| **Sleep target** | Onboarding slide 7 (default: 8.0h) | Same as above |
| **HealthKit authorization** | Onboarding slide 8 | Needed for canvas to reflect real data; can be deferred |
| **First feed (blocked app)** | Onboarding slide 9 (optional) | Strongest activation signal; ok to defer |
| **Apple ID / display name** | Onboarding slide 10 (optional) | For sync + personalization; deferrable to settings |
| **Full profile** | Never during onboarding | No profile fields collected; "who are you?" = Apple Sign In, not a form |
| **Body/Mind/Heart pieces** | Post-onboarding (Canvas tab radial menu) | Introducing activity selection during onboarding would add 2+ slides and hurt completion rate |
| **Day boundary** | Post-onboarding (Settings → Limits) | Power user feature; defaults to midnight |

### 4.3 Returning Users & Re-Running Onboarding

**From Settings:**
- Settings → About → "Replay onboarding" triggers the full flow again
- All slides are shown regardless of existing permission state
- Permission slides detect existing authorization and show "already connected" / "already enabled" state instead of firing the system dialog
- Targets pre-fill with current values (not defaults)
- Feed selection pre-fills with existing ticket groups
- Sign in slide shows current auth state

**Technical gate:**
- `@AppStorage("hasCompletedOnboarding_v1")` controls whether `OnboardingFlowView` or `MainTabView` is displayed
- Re-running from settings temporarily sets this to `false`, re-shows the flow, then re-sets on completion
- Analytics tracks `flow: "v7"` + `is_replay: true` to distinguish first-run from replays

**Edge cases:**
- If user reinstalls: `hasCompletedOnboarding` resets → full onboarding
- If user updates from v5: existing `hasCompletedOnboarding_v1 = true` is honored → no re-onboarding forced
- Migration flag (`hasMigratedOnboarding_v1`) prevents forced re-onboarding on flow version bumps

### 4.4 Drop-Off Mitigation

| Risk Point | Mitigation |
|------------|-----------|
| **Slide 0 abandonment** (user closes app immediately) | Founder's voice, not a pitch. Two lines that feel like a journal entry. Users who relate stay. |
| **Slide 1 abandonment** (still early) | The NOWHERE→NOW HERE animation is a "wait, what?" moment. Users stay to see what happens. |
| **Slide 2 too much text** (canvas concept) | Three short lines — reads in 5 seconds. Sets up the interactive demo that follows. |
| **Slide 4 confusion** (spend demo) | Clear progressive disclosure: locked app + three simple rows. Microcopy guides: "pick a window to unlock it." |
| **Slide 8 permission denial** (HealthKit) | Auto-advance regardless. Canvas tab shows "connect Health" banner post-onboarding. No guilt copy. |
| **Slide 9 abandonment** (permission fatigue) | Feed selection is explicitly skippable. Family Controls fires only on intent. Notifications only if feed selected. |
| **Slide 10 sign-in friction** | Skip link is always visible. No functional difference in D1 experience between signed-in and anonymous users. |

### 4.5 Post-Onboarding Progressive Disclosure

Items intentionally left out of onboarding, surfaced later:

| Feature | Surface | Timing |
|---------|---------|--------|
| **Body/Mind/Heart pieces** | Radial hold menu on Canvas tab | First canvas visit (tooltip: "hold to add a piece") |
| **Wallpaper export** | Notes tab → "About Wallpaper" card | Appears after D2 |
| **Widgets** | Settings → Widget section | User-initiated |
| **Day boundary** | Settings → Limits | User-initiated |
| **Canvas smudge/paint** | Canvas tab long-press | Discovered organically; Notes → "About the Canvas" explains |
| **Ticket group customization** | Feeds tab → group settings | After first ticket creation |

---

## 5. Micro-Copy Reference

### Complete Copy by Screen

#### Slide 0 — Recognition
```
"i found that i live one day over and over."
"working. scrolling. staring at a screen."
```

#### Slide 1 — The Turn
```
"it felt like being stuck in"

NOWHERE → NOW | HERE

"so i made this app."
```

#### Slide 2 — Canvas Concept
```
"your day lives on a canvas."
"the background comes from steps and sleep."
"what colors it are the things you notice."
```

#### Slide 3 — Color Cap
```
"one hundred colors. that's a full day."
"tap each to see."
[after 5 orbs] "you can't buy them — only live them."
```

#### Slide 4 — Spend Demo
```
"spend them on the apps that pull you away."
"pick how long."
"the clock runs only when the screen is on."
[pool] "100 colors"
[locked] "Instagram is closed."
[tariffs] "10 min · 4 colors" / "30 min · 10 colors" / "1 hour · 20 colors"
[before unlock] "pick a window to unlock it."
[after unlock] "[time] for [cost] colors. that's the deal."
```

#### Slide 5 — The Economy
```
"an economy between online and offline."
"earn by living. spend to scroll."
"tomorrow, it resets."
[icons] earn → spend → reset
[after animation] "at midnight, it resets."
```

#### Slide 6 — Steps Target
```
"walking fills the canvas."
"how far do you go?"
[steps] "10,000" / "steps"
```

#### Slide 7 — Sleep Target
```
"sleep deepens the dark."
"how many hours feel right?"
[microcopy] "sleep data may lag a bit — ios updates it on its own schedule."
[sleep] "8.0" / "hours"
```

#### Slide 8 — HealthKit
```
"let your phone see what your body already knows."
"steps, sleep, and the things you notice."
[microcopy] "you'll add activities after."
[button] "Allow"
```

#### Slide 9 — Feeds
```
"where does your reality fade?"
"close one — or skip for now."
[after selection] "i'll nudge you when colors are ready to spend."
[skip] "skip for now"
```

#### Slide 10 — Identity
```
"i'm kosta."
"who are you?"
[button] "Sign in"
[signed in] "✓ Signed in"
[skip] "continue without signing in"
```

#### Slide 11 — Make It Yours
```
"set your canvas as a wallpaper."
"add widgets — they update on their own."
"if they feel behind, tap refresh. ios thing."
```

#### Slide 12 — Welcome
```
"welcome to nowhere"
"[Name]" (if available)
"you're here."
[button] "let's go"
```

### Copy Principles (from TONE_OF_VOICE.md)

- **Lowercase bias** throughout — "spend colors", not "Spend Colors"
- **First person** in Story phase — "i" not "we" or "you" (founder speaking)
- **Second person** in Setup phase — "you" addressing the user directly
- **No exclamation marks** in any slide
- **No productivity language** — no "optimize", "boost", "level up"
- **Serif typography** for all onboarding lines (`.systemSerif`, light weight)
- **System serif italic** for microcopy

---

## 6. Technical Implementation Notes

### Slide Type Enum

```swift
enum OnboardingSlideType: Equatable {
    case coldOpen           // Slide 0
    case nowHereReveal      // Slide 1
    case text               // Slide 2 (canvas concept), Slide 8 (health permission)
    case colorCap           // Slide 3
    case spendDemo          // Slide 4
    case howItWorks         // Slide 5
    case stepsSetup         // Slide 6
    case sleepSetup         // Slide 7
    case feedSelection      // Slide 9
    case appleLogin         // Slide 10
    case welcome            // Slide 12

    // Legacy — still in enum, not used in v7 slide definitions
    case theCanvas
    case paintDemo
}
```

### Slide Action Enum (unchanged)

```swift
enum OnboardingSlideAction: Equatable {
    case none
    case requestHealth
    case requestNotifications
    case requestFamilyControls
}
```

### Slide Definitions

```swift
private func mainSlides() -> [OnboardingSlide] {
    return [
        // 0 — recognition
        OnboardingSlide(
            lines: [
                String(localized: "i found that i live one day over and over."),
                String(localized: "working. scrolling. staring at a screen.")
            ],
            slideType: .coldOpen
        ),

        // 1 — nowhere → now here (the turn)
        OnboardingSlide(
            lines: [
                String(localized: "it felt like being stuck in")
            ],
            slideType: .nowHereReveal
        ),

        // 2 — the canvas concept
        OnboardingSlide(
            lines: [
                String(localized: "your day lives on a canvas."),
                String(localized: "the background comes from steps and sleep."),
                String(localized: "what colors it are the things you notice.")
            ]
        ),

        // 3 — color cap (interactive — tap 5 orbs)
        OnboardingSlide(
            lines: [
                String(localized: "one hundred colors. that's a full day."),
                String(localized: "tap each to see.")
            ],
            slideType: .colorCap
        ),

        // 4 — spend demo (feeds-style — the cost)
        OnboardingSlide(
            lines: [
                String(localized: "spend them on the apps that pull you away."),
                String(localized: "pick how long."),
                String(localized: "the clock runs only when the screen is on.")
            ],
            slideType: .spendDemo
        ),

        // 5 — the economy
        OnboardingSlide(
            lines: [
                String(localized: "an economy between online and offline."),
                String(localized: "earn by living. spend to scroll."),
                String(localized: "tomorrow, it resets.")
            ],
            slideType: .howItWorks
        ),

        // 6 — steps target
        OnboardingSlide(
            lines: [
                String(localized: "walking fills the canvas."),
                String(localized: "how far do you go?")
            ],
            slideType: .stepsSetup
        ),

        // 7 — sleep target
        OnboardingSlide(
            lines: [
                String(localized: "sleep deepens the dark."),
                String(localized: "how many hours feel right?")
            ],
            slideType: .sleepSetup,
            microcopy: String(localized: "sleep data may lag a bit — ios updates it on its own schedule.")
        ),

        // 8 — health permission
        OnboardingSlide(
            lines: [
                String(localized: "let your phone see what your body already knows."),
                String(localized: "steps, sleep, and the things you notice.")
            ],
            action: .requestHealth,
            microcopy: String(localized: "you'll add activities after.")
        ),

        // 9 — feed selection (skippable)
        OnboardingSlide(
            lines: [
                String(localized: "where does your reality fade?"),
                String(localized: "close one — or skip for now.")
            ],
            slideType: .feedSelection
        ),

        // 10 — identity
        OnboardingSlide(
            lines: [
                String(localized: "i'm kosta."),
                String(localized: "who are you?")
            ],
            slideType: .appleLogin
        ),

        // 11 — make it yours
        OnboardingSlide(
            lines: [
                String(localized: "set your canvas as a wallpaper."),
                String(localized: "add widgets — they update on their own."),
                String(localized: "if they feel behind, tap refresh. ios thing.")
            ]
        ),

        // 12 — welcome
        OnboardingSlide(
            lines: [String(localized: "welcome to nowhere")],
            slideType: .welcome
        )
    ]
}
```

### Progress Bar Phase Grouping

```swift
private enum OnboardingPhase {
    case story, setup, action

    static func phase(for index: Int) -> OnboardingPhase {
        switch index {
        case 0...5: return .story    // Slides 0-5
        case 6...9: return .setup    // Slides 6-9
        default:    return .action   // Slides 10-12
        }
    }
}
```

### Interactive Slide Indices (floaters paused)

```swift
private let interactiveSlideIndices: Set<Int> = [3, 4, 6, 7, 9, 10]
// colorCap, spendDemo, stepsSetup, sleepSetup, feedSelection, appleLogin
```

### Navigation

```swift
// Back: swipe right only (>60pt horizontal drag)
.gesture(
    DragGesture(minimumDistance: 40)
        .onEnded { value in
            if value.translation.width > 60, index > 0 {
                goBack()
            }
        }
)
```

- **Forward:** bottom CTA button (always visible)
- **Back:** swipe right (>60pt horizontal) — **tap left ⅓ removed in v6** (fixes heart orb bug on colorCap)
- **Back disabled** on slide 0
- **Scroll disabled** (`scrollDisabled(true)`) — we control pacing
- **Grain overlay** at 0.2 opacity (covers all slides)

### Analytics Events

Every slide fires:

```
onboarding_slide_viewed
  { slide_index, slide_name, flow_version: "v7" }

onboarding_slide_completed
  { slide_index, slide_name, flow_version: "v7", duration_ms, action_taken }
```

`action_taken` values: `next`, `back`, `permission_granted`, `permission_denied`, `skipped`, `signed_in`, `finished`

### Onboarding Completion Event

```
onboarding_completed
  { flow: "v7", steps_target, sleep_target, selected_feed, selected_apps_count,
    signed_in, skipped_feed_selection, total_duration_ms }
  dedupeKey: "onboarding_completed_v1"
```

### Haptic Summary

| Slide | Trigger | Generator |
|-------|---------|-----------|
| 1 | NOWHERE→NOW HERE split (phase 2) | `.heavy` |
| 1 | "so i made this app." appears (phase 3) | `.success` |
| 3 | Each orb tap (1–4) | `.light` |
| 3 | Ring full — 5th orb (100) | `.success` |
| 4 | Tariff selection (unlock) | `.medium` |
| 4 | Can't afford tariff | `.rigid` |
| 6 | Slider step change | `.light` |
| 7 | Slider step change | `.light` |
| 8 | "Allow" tap (HealthKit) | `.success` |
| 10 | Successful Apple Sign In | `.success` |
| 12 | "Let's go" tap | `.medium` |

---

## Appendix: Comparison Table (v5 → v6 → v7)

| Metric | v5 | v6 | v7 |
|--------|-----|-----|-----|
| Total slides | 13 | 11 | 13 |
| Interactive slides | 4 | 2 (colorCap, spendDemo) | 2 (colorCap, spendDemo) |
| Permission requests | 3 (separate) | 3 (contextual) | 3 (contextual) |
| Skippable slides | 2 | 2 (feeds, sign-in) | 2 (feeds, sign-in) |
| Estimated time | 70–100s | 50–70s | 60–80s |
| "Aha" moment at | ~slide 5 | ~slide 3 | ~slide 4 |
| Name reveal at | slide 11 | slide 1 | slide 1 |
| Narrative voice | — | generic | founder's personal story |
| Canvas concept | paintDemo (removed) | implicit | dedicated slide (2) |
| Economy framing | — | "earn→spend→reset" | "economy between online and offline" |
| Back navigation | tap left ⅓ + swipe | swipe only | swipe only |
| Analytics version | `v5` | `v6` | `v7` |

---

*"It's not perfect, but neither am I — and neither are you."*
