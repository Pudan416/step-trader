# Nowhere — Brand Book & Product Guide

**Last updated:** March 25, 2026
**Version:** v1.0
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

1. **Earn colors by living.** Steps from HealthKit, sleep from your watch, plus activities you choose across body (yoga, gym, walk), mind (reading, journaling, deep work), and heart (calling a friend, cooking, quality time). Each category fills a 20-point bucket. Steps and sleep fill another 20 each. Max: 100 colors/day.

2. **Spend colors to scroll.** Pick the apps that drain you — we call them "feeds." They get blocked via Apple's Screen Time API. To open one, you spend colors: 4 for 10 minutes, 10 for 30 minutes, 20 for an hour. Once your budget runs out, the shield goes back up.

3. **Watch your day on a canvas.** A generative, data-driven canvas visualizes your day — warm gold blobs for steps, deep navy for sleep, colored shapes for activities. You can set it as your wallpaper. Every day looks different because every day *is* different.

No subscription required. No in-app purchases for colors. The friction is real, and that's the point.

### How it works (user flow)

```
Onboarding → Set step/sleep targets → Grant HealthKit + Family Controls
    → Pick first "feed" app to block → Land on Canvas tab
    
Daily loop:
    Wake up → Canvas is empty → Walk (steps auto-tracked) → Sleep (auto-tracked)
    → Add body/mind/heart activities manually → Colors accumulate
    → Try to open blocked app → Shield appears → "Unlock with colors"
    → Choose 10/30/60 min window → Colors deducted → Timer starts
    → Timer ends → Shield returns → Canvas reflects the day
    → Day resets at custom boundary (default midnight)
```

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

- Generative, data-driven daily visualization
- Elements spawn from steps, sleep, and activity selections
- "Ink earned" (from living) vs "ink spent" (from feeds) creates visual decay
- Canvas resets every day boundary
- Exportable as image, settable as wallpaper via Shortcuts
- Past canvases stored for 90 days

### Feeds (app blocking)

- Ticket groups: named bundles of apps/categories to block
- Shield UI when blocked app is opened: dark blur + gold accent
- PayGate: full-screen spend interface (black + gold, serif typography)
- Usage budget: countdown timer monitored by iOS device activity framework
- Re-blocks automatically when time expires

### Me (personal dashboard)

- 7-day ring visualization (how "full" each day was)
- Weekly stats: earned / spent / kept colors
- Average sleep and steps
- Body / Mind / Heart — "mostly from" breakdown
- Top energy consumers (which feeds cost the most)
- Day tap → detailed canvas snapshot

### Notes (editorial content)

- Paged serif/italic cards explaining the philosophy behind each feature
- Topics: Canvas, Body/Mind/Heart, Shapes, Sleep, Steps, Feeds, Limits, Wallpaper, Colors, About Kosta
- Unread dot indicator

### Settings

- **Appearance:** Theme (Daylight/Night), gradient palette (Warm Sunset, Rose Garden, Ember, Dusk), gradient style
- **Notifications:** Canvas reminder, day reset warning, access window alerts
- **Limits:** Steps goal, sleep goal, day reset time
- **Wallpaper:** Shortcuts integration for automatic wallpaper updates
- **Widget:** Solid vs wallpaper background
- **About:** Developer, version, contact

### Widgets

| Widget | Size | Content |
|--------|------|---------|
| Energy Status | Medium | Today's colors balance, energy breakdown |
| App Groups | Large | Unlock/manage ticket groups from Home Screen |

### Shield (system-level block screen)

Appears when a blocked app is opened:
- Title: "[App Name] is closed."
- Subtitle: "Spend colors in Nowhere to unlock it."
- Primary CTA: "Unlock with colors" (gold button)
- Dark blur material background, brand yellow accent

---

## 6. Information Architecture

### Tab structure

| Tab | Icon | Content |
|-----|------|---------|
| **Canvas** (default) | `hand.point.up.left.fill` | Generative day canvas + radial menu |
| **Feeds** | `square.grid.2x2` | Ticket groups (blocked apps) |
| **Me** | `person.circle` | Weekly dashboard + stats |
| **Notes** | `book.fill` | Editorial notes about the app |
| **Settings** | `gearshape` | Configuration + about |

### Persistent overlay

**StepBalanceCard** sits at the top across all tabs:
- Shows current colors balance
- Expandable to show category breakdown (steps, sleep, body, mind, heart chips)
- Countdown timer to day reset

---

## 7. Tone of Voice

### Principles

| Principle | Description |
|-----------|-------------|
| **First-person** | The app speaks as one person to another, not a brand to a user |
| **Reflective** | Observations, not commands. "Lately I've felt stuck" not "Stop wasting time" |
| **Anti-prescriptive** | No shoulds. "I feel best around 7k steps. How about you?" |
| **Warm but honest** | Acknowledges imperfection. Never preachy or motivational-poster tone |
| **Philosophical, not technical** | "Each day is a canvas you color by living" not "Track your daily metrics" |
| **Rebellious** | The daylight theme is described internally as "resistance." The accent color is a "rebellious marker" |

### Voice examples

**Do say:**
- "Lately I've felt stuck in nowhere."
- "So I decided to turn Nowhere into Now Here."
- "Each day is a canvas you color by living real life."
- "Walking adds bright color."
- "Sleep adds the dark tones."
- "You can't buy colors."
- "Steps are not a fitness metric. They're proof the body moved through the world."
- "Feeds are where minutes disappear. Not evil, not good — just expensive."
- "Colors are not a currency. I mean they are, but I'm not planning to sell them in microtransactions or whatever. Colors are yours."
- "It's not perfect, but neither am I — and neither are you."

**Don't say:**
- "Optimize your screen time habits"
- "Set limits and stick to them!"
- "You've been on your phone too long"
- "Great job! You earned 50 colors today!"
- "Unlock premium features"
- "Share your progress with friends"

### Copy style guide

- Sentence case for headers and buttons
- No exclamation marks in UI copy (the rare exception: onboarding slides)
- Ellipses are okay to create pause ("You can't buy colors, but...")
- Line breaks within strings for rhythm, not space constraints
- Localization-ready but English-only for v1

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
| **Rose Garden** | `#FFB0C4` pink | `#D4627A` rose | `#1B5E3B` forest | `#0C2318` deep green |
| **Ember** | `#FFF0A0` cream | `#E8864A` orange | `#7A1A1A` crimson | `#2A0808` dark red |
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

### Onboarding (13 slides)

The onboarding is a philosophical narrative, not a feature tour:

| # | Copy | Action |
|---|------|--------|
| 1 | "Lately I've felt stuck in nowhere." / "Working, scrolling, staring at a screen." | — |
| 2 | "So I decided to turn Nowhere into Now Here." / "And built this app." | — |
| 3 | "Each day is a canvas you color by living real life." / "Every 24 hours, it resets." | Canvas demo |
| 4 | "Walking adds bright color." / "I feel best around 7k steps." / "How about you?" | Steps slider (5k–15k) |
| 5 | "Sleep adds the dark tones." / "For me, 9 hours is the sweet spot." / "What about you?" | Sleep slider (6–10h) |
| 6 | "To color your canvas, share your steps and sleep data." | HealthKit permission |
| 7 | "Hit your sleep and steps targets to earn colors." / "Add body, mind, and heart activities to earn even more." | Colors demo chips |
| 8 | "What are colors?" / "They show how intentionally you lived your day." / "You can't buy colors, but..." | Family Controls permission |
| 9 | "...you can spend them to unlock apps." / "Pick your first one." | App selection grid |
| 10 | "To unlock the chosen app you'll get a notification from Nowhere." / "Better to allow them." | Notification permission |
| 11 | "Your canvas changes every day." / "From Settings, you can set it as your wallpaper." / "Practical and pretty." | — |
| 12 | "By the way, I'm Kosta." / "Who are you?" | Sign in with Apple |
| 13 | "Welcome to Nowhere, [Name]" | — |

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

- Canvas: "Hold + to color up the canvas"
- Feeds: "No feeds connected yet" / "Create one when you're ready."
- Notifications: "Get a nudge to fill your canvas..." / "A heads-up before your canvas resets..."

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
| **WidgetKit** | Home screen widgets | Yes — Energy Status, App Groups |
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

1. **Currency you can't buy.** Every competitor either has IAP or relies on willpower. Colors are earned exclusively through HealthKit-verified movement, tracked sleep, and declared daily activities.

2. **Living daily canvas.** No competitor creates a personal, generative artwork from your day's data that you can set as your wallpaper.

3. **Category system (Body/Mind/Heart).** Goes beyond steps — encourages a holistic view of daily living, inspired by Tibetan Buddhism's body-mind-heart harmony.

4. **Family Controls enforcement.** Uses Apple's strongest blocking API. You can't just tap "Ignore for 15 minutes."

5. **Anti-corporate brand voice.** Built by one person, written in first person, openly imperfect. The "About Kosta" note is a founder letter inside the app.

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

- 100 colors max per day — perfectly balanced across 5 categories
- 13-slide onboarding that reads like a personal letter
- Uses Apple Family Controls API (same as parental controls — can't be bypassed)
- Generative daily canvas that becomes your wallpaper
- Zero in-app purchases — the entire economy is earned
- Home screen widgets for colors balance and quick unlock

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
| **Ink** | Internal/canvas term for energy — earned ink adds color, spent ink (from feeds) drains it |
| **Usage budget** | The timed window (10/30/60 min) of access purchased with colors |
| **Daylight** | Light theme — "paper" aesthetic with high contrast, no shadows, printed feel |
| **Night** | Dark theme — same gold accent, deep blue-grey background |

---

*"It's not perfect, but neither am I — and neither are you. I'm trying to accept myself and find meaning beyond work."*
— Kosta, somewhere in Nowhere
