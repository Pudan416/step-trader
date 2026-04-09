# Nowhere — Brand Book & Product Guide

**Last updated:** April 2, 2026
**Version:** v1.1
**Author:** Konstantin Pudan

---

## Table of Contents

1. [Brand Identity](#1-brand-identity)
2. [Product Overview](#2-product-overview)
3. [Target Audience](#3-target-audience)
4. [Core Mechanics](#4-core-mechanics)
5. [Feature Map](#5-feature-map)
6. [Information Architecture](#6-information-architecture)
7. [Tone of Voice](#7-tone-of-voice)
8. [Visual Identity](#8-visual-identity)
9. [Typography](#9-typography)
10. [Iconography & Symbols](#10-iconography--symbols)
11. [Key Screens & Copy](#11-key-screens--copy)
12. [Monetization Philosophy](#12-monetization-philosophy)
13. [Technical Integrations](#13-technical-integrations)
14. [Competitive Positioning](#14-competitive-positioning)
15. [Pitch Toolkit](#15-pitch-toolkit)

---

## 1. Brand Identity

### Name

**Nowhere** — deliberately a wordplay. Read it one way and it says *nowhere*. Read it again and it says *now here*. The name captures the core tension of the product: the feeling of being lost in screens vs. the practice of being present.

- **User-facing name:** Nowhere
- **Internal / code name:** StepsTrader, Steps4
- **Domain:** itsnowhere.net
- **Contact:** hello@itsnowhere.net

### Tagline

> "You are not nowhere. You are now here."

### Secondary tagline (login screen)

> "The sense of being present"

### Origin story (in the founder's words)

> "I've spent years working on creative projects for brands — winning awards, getting recognition. It made me feel successful, creative, whatever. But recently I realized I was living inside my work, hiding in it. I didn't really know myself anymore. Could I do something on my own? For myself? Was I capable of something else? You know... the classic midlife corporate crisis. It felt like I was nowhere. So I started building this app — at first just for myself. Over time it became something deeply personal."

### Brand values

| Value | Meaning |
|-------|---------|
| **Presence** | The app exists to pull you out of the feed and into your day |
| **Honesty** | No dark patterns, no fake urgency, no manufactured scarcity |
| **Earned, not bought** | The in-app currency (colors) cannot be purchased with real money |
| **Personal accountability** | You set your own limits and hold yourself to them |
| **Imperfection** | "It's not perfect, but neither am I — and neither are you" |

---

## 2. Product Overview

### One-liner

Nowhere is an iOS app that turns your daily steps, sleep, and intentional living choices into a visual currency called **colors** — which you spend to unlock apps you've chosen to block.

### Elevator pitch (30 seconds)

Every morning you wake up with an empty canvas. Walking adds bright color. Sleep adds dark tones. Body, mind, and heart activities fill in the rest. The fuller your day, the more **colors** you earn — up to 100 per day. Colors are the only way to unlock the apps you've blocked (Instagram, TikTok, whatever drains your time). You can't buy colors. You can only live them. And every 24 hours, the canvas resets. That's Nowhere — turning *nowhere* into *now here*.

### Expanded pitch (2 minutes)

We all know the loop: pick up the phone, open a feed, twenty minutes vanish. Screen Time limits? You just tap "Ignore." Nowhere takes a different approach. Instead of shaming you or setting timers you'll dismiss, it builds a simple economy around your real life:

1. **Earn colors by living.** Steps and sleep from HealthKit (each up to 20 colors toward the 100 cap), plus **pieces** you choose across **body, mind, and heart** (preset catalog + custom activities, up to 20 each). Max: **100 colors/day**.

2. **Spend colors to scroll.** Pick the apps that drain you — we call them "feeds." They get blocked via Apple's Screen Time API. To open one, you spend colors: 4 for 10 minutes, 10 for 30 minutes, 20 for an hour. Once your budget runs out, the shield goes back up.

3. **Watch your day on a canvas.** A generative, data-driven canvas visualizes your day — warm gold blobs for steps, deep navy for sleep, colored shapes for activities. You can set it as your wallpaper. Every day looks different because every day *is* different.

No subscription required. No in-app purchases for colors. The friction is real, and that's the point.

### How it works (user flow)

```
Onboarding (v5, 13 slides) → Interactive paint + color-cap + spend demos
    → Set step/sleep targets → HealthKit → Pick first feed (or skip) → Sign in with Apple → Canvas tab

Daily loop:
    Wake up → Canvas is empty (“Today is uncolored”) → Walk + sleep (HealthKit)
    → Add body/mind/heart pieces → Colors accumulate (up to 100)
    → Open blocked app → Shield → PayGate → choose 10/30/60 min → colors spent, canvas decays
    → Timer ends → shield returns → day rolls at custom boundary (default midnight)

Side paths: Home Screen widgets (Energy Status, App Groups), wallpaper shortcut, deep links from shield/notifications.
```

### What feels different (product soul)

- **Canvas as mirror, not dashboard** — Generative art from real inputs; **Metal smudge** lets you physically “move” paint on top of the generative layer.
- **v5 onboarding** — Lowercase, first-person poetry *before* the product name appears; you paint and spend in demos before permissions.
- **Honest economy** — Same default tariffs everywhere: **4 / 10 / 20 colors** for **10 min / 30 min / 1 h**; “keep it closed” is always explicit.
- **Voice** — One person (`TONE_OF_VOICE.md`), Notes as essays, shields as facts.

---

## 3. Target Audience

### Primary persona: The Conscious Scroller

- **Age:** 22–40
- **Profile:** Digital professional, creative, or student who's self-aware about phone addiction but hasn't found a solution that sticks
- **Behavior:** Has tried Screen Time limits, deleted and re-downloaded apps, set app timers — none of it worked because it was too easy to override
- **Motivation:** Wants friction, not punishment. Wants to *earn* access through real-world action
- **Values:** Health-conscious, reflective, appreciates design and craft
- **Device:** iPhone (required), Apple Watch (ideal for sleep/step data)

### Secondary persona: The Self-Quantifier

- **Profile:** Enjoys tracking daily habits (steps, sleep, reading hours) but wants it connected to something tangible
- **Draw:** The canvas as a daily visual journal, the colors system as a feedback loop

### Anti-persona: The Casual Optimizer

- **Not for:** Someone looking for a set-it-and-forget-it parental control or simple timer
- **Why not:** Nowhere requires daily engagement and personal honesty; it's a practice, not a utility

---

## 4. Core Mechanics

### Colors (in-app currency)

| Property | Detail |
|----------|--------|
| **Name** | Colors |
| **Max per day** | 100 |
| **Cannot be purchased** | Fundamental design constraint |
| **Earned from** | Steps (up to 20), Sleep (up to 20), Body activities (up to 20), Mind activities (up to 20), Heart activities (up to 20) |
| **Spent on** | Unlocking blocked apps for timed windows |
| **Resets** | At customizable day boundary (default midnight) |

### Energy categories

| Category | Examples | Canvas representation |
|----------|----------|----------------------|
| **Body** | Gym, yoga, running, stretching | Large, breathing shapes |
| **Mind** | Reading, journaling, deep work, meditation | Drifting circles (ideas) |
| **Heart** | Calling a friend, cooking, quality time, gratitude | Beams of light that move and scan |

### Feeds (blocked apps)

- Users choose which apps to block (called "feeds")
- Organized into **Ticket Groups** — named collections of apps/categories
- Each group has a visual **ticket** metaphor in the UI
- Blocking uses Apple's Family Controls / Screen Time API (cannot be bypassed like regular Screen Time)

### Unlock pricing

| Window | Cost |
|--------|------|
| 10 minutes | 4 colors |
| 30 minutes | 10 colors |
| 1 hour | 20 colors |

### Day boundary

The "day" doesn't have to start/end at midnight. Users can set a custom reset time (range: 9 PM – 3 AM, 15-minute increments) reflecting when their day actually ends.

---

## 5. Feature Map

### Canvas (default tab)

- **SwiftUI `Canvas`** engine (`GenerativeCanvasView`): timeline-driven motion, steps/sleep tint, body / mind / heart geometry (breathing masses, drifting circles, heart beams).
- **Metal smudge overlay** — finger painting on the live canvas (`SmudgeOverlayView` / `MetalSmudgeRenderer`); separate from the data-driven layer, same emotional “this is mine” feeling.
- Earned vs spent energy drives **decay** (feeds drain the picture).
- Resets at day boundary; persist + **Supabase** canvas sync; **~90 days** local snapshot history.
- Share sheet export; **Shortcuts** intent for wallpaper pipeline (see Settings).

### Feeds (app blocking)

- **Ticket groups** with paper-ticket UI; **template picker** for common apps (Instagram, TikTok, YouTube, etc.).
- Shield: system blur + **brand gold** primary button.
- **PayGate:** serif headline “spend colors”, interval rows, optional styled backgrounds (`PayGateBackgroundStyle`).
- **DeviceActivity** monitors usage windows; shields return when time is up.

### Now (personal dashboard — tab label)

- Tab bar says **“Now”** (weekly you-state, not “Me”).
- 7-day rings, earned / spent / kept, averages, body/mind/heart mix, top feed consumers, day drill-in.

### Notes (editorial content)

- Eleven cards, **ten topics** — two separate essays both filed under **About Colors** (palette vs economy).
- Topics: Canvas; Body, Mind, and Heart; **Shapes**; Sleep; Steps; Feeds; Limits; Wallpaper; Colors (×2); About Kosta.
- **Unread tracking** (`NoteReadTracker`); presentation is literary, not instructional.

### Settings

- **Appearance:** Daylight / Night, energy gradient palettes (Sunset, Ocean, Aurora, Dusk).
- **Notifications:** Reminders, reset warnings, access-window alerts.
- **Limits:** Steps, sleep, **day boundary** (when “today” flips).
- **Wallpaper / Shortcuts:** Guided setup for pushing canvas to lock screen.
- **Widget:** **Solid** vs **wallpaper** thumbnail background (App Group snapshot).
- **About:** Contact, version, founder context.

### Widgets (`UnlockWidgetExtension`)

Home Screen **WidgetKit** (not a separate Lock Screen–only target in the current project).

| Widget | Size | Configuration | Content |
|--------|------|---------------|---------|
| Energy Status | Medium | Static | Today’s colors + breakdown |
| App Groups | Large | **App Intent** (`SelectGroupIntent`) | Pick a ticket group; unlock / manage from the widget |

### Shield (system-level block screen)

Appears when a blocked app is opened:
- Title: "[App Name] is closed."
- Subtitle: "Spend colors in Nowhere to unlock it."
- Primary CTA: "Unlock with colors" (gold button)
- Dark blur material background, brand yellow accent

Notifications echo the same neutral facts (“An app is closed…”) — see `TONE_OF_VOICE.md`.

---

## 6. Information Architecture

### Tab structure

| Tab | Icon | Label in app | Content |
|-----|------|--------------|---------|
| **Canvas** (default) | `hand.point.up.left.fill` | Canvas | Generative canvas + radial hold menu + smudge layer |
| **Feeds** | `square.grid.2x2` | Feeds | Tickets, templates, tariffs, time windows |
| **Now** | `person.circle` | **Now** | Weekly dashboard + stats (same surface as legacy “Me”) |
| **Notes** | `book.fill` | Notes | Editorial cards + shuffle |
| **Settings** | `gearshape` | Settings | Appearance, limits, widget, account |

### Persistent overlay

**StepBalanceCard** (name is legacy; user sees **colors**):
- Colors glyph + **current / earned today / 100** + progress strip + time to reset
- Expandable chips: steps, sleep, body, mind, heart
- “About colors” help affordance

---

## 7. Tone of Voice

**Source of truth:** `TONE_OF_VOICE.md` — rules, surface-by-surface examples, templates, anti-patterns.

### Principles (summary)

| Principle | Description |
|-----------|-------------|
| **First-person** | Especially onboarding and Notes — “i keep ending days i never touched.” |
| **Lowercase bias** | UI labels and short phrases often lowercase (“spend colors”, “keep it closed”) per `TONE_OF_VOICE.md` |
| **Anti-hype** | No cheerleading, no streaks, no guilt |
| **Metaphor over metric** | Canvas, colors, threshold — not “optimization” |
| **Shield = facts** | Short, neutral, no moralizing |

### Voice examples (still on-brand)

**Do say:**
- "i wanted a mirror / that could hold a whole day."
- "spend what you lived / to open what you chose to close."
- "walking brightens the canvas." / "sleep lays down the dark."
- "You can't buy colors."
- "Feeds are where minutes disappear. Not evil, not good — just expensive."
- "It's not perfect, but neither am I — and neither are you."

**Don't say:**
- Productivity-coach clichés, fake enthusiasm, premium upsell for colors

### Copy style guide

- Navigation titles may use title case (“Settings”); body/button copy follows `TONE_OF_VOICE.md`
- Onboarding v5 is the most literary surface; routine chrome stays quiet
- Strings live in **`Localizable.xcstrings`** — English ships first; structure supports more locales later

---

## 8. Visual Identity

### Color palette

#### Brand accent

| Name | Hex | RGB | Usage |
|------|-----|-----|-------|
| **Brand Gold** | `#FFD369` | 255, 211, 105 | Primary accent everywhere — toggles, pills, shield button, colors indicator |

#### Daylight theme ("Paper")

Internal philosophy: *"This is not a light mode. This is a daytime version of resistance. The screen is not your life. This is just a place to notice."*

| Role | Hex | Description |
|------|-----|-------------|
| Background | `#F2F2F2` | Off-white paper |
| Background secondary | `#F3F4F6` | Grouped content |
| Background tertiary | `#EBECF0` | Deep grouping |
| Text | Near-black | High contrast, printed feel |
| Stroke | Near-black | Thin lines for separation — no shadows, no soft cards |
| Accent | `#FFD369` | Same gold as Night mode |

#### Night theme

| Role | Hex | Description |
|------|-----|-------------|
| Background | `#222831` | Dark blue-grey |
| Background secondary | `#30303A` | Elevated surfaces |
| Text | `#F2F2F2` | Light, high contrast |
| Accent | `#FFD369` | Same gold |
| Accent muted | `#FFD369` at 60% | Disabled/secondary states |

#### Energy gradient palettes

The background of the entire app is a living, data-driven gradient that responds to your steps and sleep:

| Palette | Bright (steps) | Warm (mid) | Cool (sleep) | Dark (deep sleep) |
|---------|---------------|------------|-------------|-------------------|
| **Warm Sunset** (default) | `#FFBF65` gold | `#FD8973` coral | `#003A6C` navy | `#002646` night |
| **Ocean** | `#7FDBDA` teal | `#3A9FBF` cerulean | `#1A4B6E` deep blue | `#0B1E33` midnight |
| **Aurora** | `#C4B5FD` lavender | `#7C6FBF` violet | `#1F6E5C` emerald | `#0F1B2D` dark slate |
| **Dusk** | Warm beige | Dusty rose | Deep teal | Near-black |

The gradient uses organic blob shapes, grain texture overlay, and smooth transitions. More steps = brighter warm tones. More sleep = deeper cool tones. No data = neutral state.

#### PayGate styles

Six themed backgrounds for the app-unlock screen:
- **Midnight** — deep indigo/violet
- **Aurora** — teal/emerald
- **Sunset** — crimson/warm
- **Ocean** — deep blue
- **Neon** — purple/magenta
- **Minimal** — near-black (default)

### Design language

| Element | Treatment |
|---------|-----------|
| **Cards** | Glass/frosted material on iOS 26+ (liquid glass), ultraThinMaterial on older OS. Rounded corners (12–16pt) |
| **Backgrounds** | Energy gradient covers entire screen. No flat solid backgrounds in main flow |
| **Shadows** | Avoided in Daylight theme. Minimal/contextual in Night |
| **Borders** | Thin strokes for separation in Daylight, subtle in Night |
| **Motion** | Spring animations on tab switches, card expansions. Breathing/drifting on canvas elements |
| **Grain** | Subtle noise overlay on gradients (onboarding, canvas, preview sheets) |
| **Ticket metaphor** | Blocked app groups are visualized as paper tickets with lock/unlock states, pill-shaped interval selectors |

---

## 9. Typography

### System fonts

| Context | Style |
|---------|-------|
| **Body text** | SF Pro (system default), `.rounded` variant for main app |
| **Onboarding lines** | Light serif (`.systemSerif`) — poetic, reflective |
| **PayGate title** | Bold serif — weighty, intentional |
| **Login / app name** | Black weight serif, size 32 |
| **Balance numbers** | Serif — gives financial/serious weight to the colors counter |
| **Notes (editorial)** | Serif italic — personal, handwritten quality |
| **Tab bar labels** | System, size 11 |
| **Small caps** | Used for topic labels in Notes |

### Custom fonts (bundled)

| Font | Usage |
|------|-------|
| Reenie Beanie | Handwritten feel (canvas labels, personal touch) |
| Big Shoulders Stencil | Display/stencil weight for headers |
| Carter One | Bold, friendly display |
| Tourney | Variable width display |
| UnifrakturCook | Decorative/blackletter (limited use) |
| Vast Shadow | Heavy display with shadow effect |

### Sizing principles

- Onboarding uses generous sizes (18, 20, 32, 60) for dramatic, slide-like presentation
- In-app keeps standard iOS sizing with `.subheadline`, `.caption`, `.title2` etc.
- Balance card and PayGate use larger numbers for emphasis

---

## 10. Iconography & Symbols

### App icon

- Purple-indigo gradient rounded rectangle
- White eye symbol (`eye.fill`) centered
- Shadow: indigo, offset down

The eye represents awareness, presence, seeing the day as it is.

### SF Symbols used throughout

| Symbol | Meaning |
|--------|---------|
| `hand.point.up.left.fill` | Canvas (interactive, touch) |
| `square.grid.2x2` | Feeds (apps grid) |
| `person.circle` | Profile / Me |
| `book.fill` | Notes |
| `gearshape` | Settings |
| `eye.fill` | App icon / awareness / brand mark |
| `figure.walk` | Steps / movement |
| `chart.line.uptrend.xyaxis` | Tracking / progress |
| `shield.fill` | Blocking / protection |
| `envelope` | Contact email |
| `paperplane` | Telegram contact |
| `xmark.circle.fill` | Dismiss / close |
| `lock.fill` / `lock.open.fill` | Blocked / unblocked state |

### Canvas element shapes

| Category | Shape | Behavior |
|----------|-------|----------|
| Body | Large rounded forms | Slow breathing/scale animation |
| Mind | Circles | Drifting, floating motion |
| Heart | Ray/beam shapes | Rotating, scanning, radiating light |

---

## 11. Key Screens & Copy

### Onboarding (v5 — 13 slides)

Interactive narrative: you **feel** canvas → colors → spend **before** the app asks for HealthKit. Flow identifier in analytics: `flow: v5`.

| # | Theme | Representative copy (English) | Interaction |
|---|--------|-------------------------------|-------------|
| 1 | Cold open | "i keep ending days i never touched." | — |
| 2 | Canvas idea | "i wanted a mirror" / "that could hold a whole day." / "not a dashboard. not a score." | — |
| 3 | Paint demo | "swipe to color it." | User paints sample canvas |
| 4 | 100 cap | "one hundred colors. that's a full day." / "tap each to see." | Tap orbs |
| 5 | Spend demo | "spend what you lived" / "to open what you chose to close." | Tap apps, watch pool drain |
| 6 | Loop | "every morning, empty." / "earn colors by living." / "spend them to scroll." | Animated summary |
| 7 | Steps | "walking brightens the canvas." / "set your target." | Steps target |
| 8 | Sleep | "sleep lays down the dark." / "how much rest colors the night?" | Sleep target |
| 9 | HealthKit | "to paint your real day," / "share what your body already knows." | Allow Health |
| 10 | Feeds | "what pulls you when you're tired?" / "pick an app to close — or skip for now." | App picker + Family Controls + notifications as needed |
| 11 | Name | "i called it nowhere." / "i still read it as now here." | — |
| 12 | Identity | "i'm kosta." / "who are you?" | Sign in with Apple |
| 13 | Welcome | "welcome to nowhere" | — |

### Shield (blocked app)

- **Title:** "[App Name] is closed."
- **Subtitle:** "Spend colors in Nowhere to unlock it."
- **Primary button:** "Unlock with colors"

### PayGate (unlock screen)

- Black background, gold accent
- Group name displayed
- Unlock options: "10 min · 4 colors" / "30 min · 10 colors" / "1 hour · 20 colors"
- Secondary: "keep it closed"
- Balance displayed in a capsule

### Login

- **Heading:** "Nowhere"
- **Subhead:** "The sense of being present"
- **Features:**
  - "Turn movement into energy"
  - "Stay present, control screen time"
  - "Track what matters"
- **Footer:** "Account syncs across devices"

### Empty states

- Canvas: **"Today is uncolored"** (hint to add pieces / paint)
- Feeds: **"No feeds connected yet"** / **"Create one when you're ready."**
- Notifications settings: gentle opt-in copy (see `Localizable.xcstrings`)

---

## 12. Monetization Philosophy

### Current model: Free, no IAP

Nowhere has **no StoreKit integration, no subscriptions, and no in-app purchases** in v1. Colors are purely an internal economy tied to real-world actions. This is a core brand principle: you cannot buy your way past the friction.

### Positioning for future monetization (if needed)

| Approach | Alignment with brand |
|----------|---------------------|
| **Tip jar / support the developer** | High — honest, no pressure |
| **Cosmetic unlocks** (themes, canvas styles, ticket skins) | Medium-High — doesn't break the economy |
| **Premium widget styles** | Medium — adds value without affecting core loop |
| **Selling colors or "skip" tokens** | **Never** — violates core brand promise |
| **Subscription for sync/backup** | Low-Medium — needs careful framing |

### Why this matters for pitching

The absence of IAP is the story. In a world of engagement hacking and microtransaction dark patterns, Nowhere bets on a different model: build something so meaningful that people want to support it because it changed their relationship with their phone.

---

## 13. Technical Integrations

| Integration | Purpose | User-facing? |
|-------------|---------|-------------|
| **HealthKit** | Steps + sleep data (read) | Yes — drives the entire ray system |
| **Family Controls / Screen Time API** | App blocking, shield, usage budgets | Yes — the "feeds" enforcement |
| **ManagedSettings + DeviceActivity** | Shield rendering, minute-by-minute tracking | Background — user sees shield UI |
| **Sign in with Apple** | Authentication | Yes — onboarding + settings |
| **Supabase** | Backend sync, analytics, canvas backup | Background |
| **CloudKit** | Legacy sync (ticket settings, spent data) | Background |
| **WidgetKit** | Home Screen widgets + App Intents | Yes — `UnlockWidgetExtension` |
| **App Intents / Shortcuts** | Canvas wallpaper export automation | Yes — Settings-guided setup |
| **UserNotifications** | Canvas reminders, reset warnings, unlock prompts | Yes — configurable in settings |

---

## 14. Competitive Positioning

### Landscape

| Product | Approach | Nowhere's difference |
|---------|----------|---------------------|
| **Screen Time (Apple)** | Timers you tap through | Nowhere uses Family Controls — can't be bypassed with a tap |
| **One Sec** | Delay/friction before opening apps | Nowhere adds a real cost (colors from real-world activity) |
| **Opal** | Session blocking + focus modes | Nowhere ties access to holistic daily living, not just willpower |
| **Forest** | Gamified focus timer (grow trees) | Nowhere is always-on economy, not session-based; connected to actual health data |
| **ScreenZen** | Usage dashboards + nudges | Nowhere enforces rather than nudges |
| **Clearspace** | Breathing exercise before unlock | Nowhere requires sustained real-world activity, not a 30-second exercise |

### Unique differentiators

1. **Currency you can't buy.** Colors come from living (HealthKit + declared pieces), not IAP.

2. **Living canvas + paint.** Generative visualization **plus** optional **Metal smudge** interaction — not just a chart.

3. **Body / Mind / Heart.** Holistic buckets with distinct **visual grammar** on the canvas (documented in Notes → Shapes).

4. **Family Controls enforcement.** Strongest Apple path for self-imposed blocks.

5. **Voice and onboarding as art direction.** v5 story flow, lowercase poetry, name reveal late — feels like a zine, not a utility.

6. **Widgets that participate in the economy.** Large widget uses **App Intents** to tie Home Screen to ticket groups and unlock flow.

---

## 15. Pitch Toolkit

### One-liners (for different audiences)

**For press:**
> Nowhere is an iOS app where you earn the right to scroll by walking, sleeping, and living — with a currency you can't buy.

**For investors:**
> We've built a digital wellbeing platform where real-world health data gates access to addictive apps, using Apple's strongest Screen Time API and a non-purchasable internal economy.

**For users:**
> Block your feeds. Earn colors by living. Spend them to scroll. Your day is the canvas.

**For App Store:**
> Turn nowhere into now here. Walk, sleep, and live to earn colors — the only way to unlock your blocked apps. Each day is a canvas you color by living.

### Key stats to mention

- 100 colors max per day — five buckets × 20 (steps, sleep, body, mind, heart)
- 13-slide **v5** onboarding — interactive demos, then permissions
- Apple Family Controls + DeviceActivity — self-chosen blocks
- Generative canvas + optional **Metal smudge** + wallpaper shortcut
- No StoreKit for colors — economy is earned
- **UnlockWidgetExtension** — medium “Energy Status”, large “App Groups” with App Intents

### Story beats for a pitch deck

1. **The problem:** We're all stuck in feeds. Screen Time limits don't work because you can tap through them. (Stat: average person spends 3+ hours on social media daily)
2. **The insight:** What if access to feeds had a real cost — not money, but movement and presence?
3. **The mechanism:** Colors — earned from steps, sleep, and daily activities via HealthKit. Spent to unlock blocked apps via Family Controls. Can't be bought.
4. **The canvas:** Your day becomes a living artwork. Steps brighten it. Sleep deepens it. Feed usage drains it.
5. **The brand:** Nowhere → Now Here. Built by one person. First-person voice. No dark patterns. A manifesto disguised as an app.
6. **The traction:** [Insert metrics — downloads, daily active users, average colors earned, average feed time reduction]
7. **The ask:** [Investment / partnership / press coverage / whatever applies]

### Messaging don'ts (for anyone creating content about Nowhere)

- Don't call it a "screen time management tool" — it's a presence practice with enforcement
- Don't compare it to parental controls — it's self-imposed, voluntary friction
- Don't use "gamification" language — there are no streaks, no leaderboards, no achievements
- Don't say "detox" — it's not about quitting apps, it's about making them cost something real
- Don't frame it as health tracking — health data is the input, not the output
- Don't promise "productivity gains" — the value is presence, not optimization

---

## Appendix: Glossary

| Term | Definition |
|------|-----------|
| **Colors** | The in-app currency earned from daily living (steps, sleep, activities). Max 100/day. Cannot be purchased. |
| **Canvas** | The generative daily artwork that visualizes how fully you lived your day |
| **Feeds** | User-selected apps and categories to block (social media, games, etc.) |
| **Ticket Group** | A named collection of blocked apps with shared unlock settings |
| **Shield** | The iOS-level block screen that appears when opening a blocked app |
| **PayGate** | The in-app screen where you spend colors to unlock a feed for a timed window |
| **Energy** | The daily points system (0–100) derived from steps, sleep, and category activities |
| **Body / Mind / Heart** | The three categories of daily activities that earn colors beyond steps and sleep |
| **Day boundary** | The customizable time when "today" resets (default midnight, configurable 9 PM–3 AM) |
| **Ink** | Internal persistence/analytics field (`inkEarned` / `inkSpent`); user-facing word is **colors** |
| **Now** | Tab bar name for the weekly profile / stats surface (implementation: `MeView`, etc.) |
| **Usage budget** | The timed window (10/30/60 min) of access purchased with colors |
| **Daylight** | Light theme — "paper" aesthetic with high contrast, no shadows, printed feel |
| **Night** | Dark theme — same gold accent, deep blue-grey background |

---

*"It's not perfect, but neither am I — and neither are you. I'm trying to accept myself and find meaning beyond work."*
— Kosta, somewhere in Nowhere
