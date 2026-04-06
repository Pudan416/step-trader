# Nowhere — Strategic Blueprint (Updated April 2, 2026)

> Reconciled with the actual codebase. Claims below were checked against the repo (Swift sources, widget extension, shield extension, `NoteCatalog`, onboarding v5).

---

## 1. Executive Summary

**What Nowhere is**: A SwiftUI iOS app where your real life — steps, sleep, and daily choices across three categories (body, mind, heart) — produces **colors**. Colors are what you spend to open your **feeds** (blocked apps). The **canvas** is the soul of the product: a generative, animated picture of the day; opening feeds spends colors and visibly drains that picture.

**Current state**: Feature-complete for a serious beta. Branded **Nowhere** end-to-end (shield, notifications, onboarding). **v5 onboarding** (13 slides) is interactive and poetic — paint demo, 100-color cap, spend demo, then permissions and identity. **Notes** holds 11 editorial cards across 10 topics (two essays both titled “About Colors”). **Home Screen widgets** ship via **UnlockWidgetExtension** (Energy Status + configurable App Groups). The canvas combines **SwiftUI `Canvas`** drawing with an optional **Metal smudge** overlay for tactile “painting.”

**What remains for beta launch**: Device QA, TestFlight distribution, tester cohort, App Store Connect assets — not a single known “wrong app name on shield” blocker (shield subtitle is Nowhere).

---

## 2. Current State (As of Apr 2, 2026)

### Completed — Identity & Vocabulary

| Goal | Status |
|------|--------|
| App name = "Nowhere" | Done. Shield: “Spend colors in Nowhere to unlock it.” Notifications match. Onboarding reveals the name late (“nowhere” / “now here”). |
| Currency = "colors" | Done in UI. PayGate: “spend colors”, “N colors”. Snapshots/events use `inkEarned` / `inkSpent` (and legacy keys for decode). |
| Three categories = body / mind / heart | Done. Canvas, chips, onboarding, notes. |
| 10+ preset pieces per category | Done. `EnergyOption.options`: body 11, mind 10, heart 10. Plus user-defined custom activities. |
| Shield copy | Done. Consistent Nowhere + colors language (`ShieldConfigurationExtension`). |
| PayGate = choice framing | Done. “keep it closed”, interval lines like “10 min · 4 colors” (defaults 4 / 10 / 20 for 10m / 30m / 1h). |
| Copy pipeline | Primary English strings live in **`Localizable.xcstrings`** via `String(localized:)`. `titleRu` still on `EnergyOption` for backward compatibility. |
| Difficulty labels | Done. Neutral level labels where used. |

### Completed — Architecture & UX

| Goal | Status |
|------|--------|
| Canvas = default tab | Done. Tab 0 (`MainTabView`). |
| Onboarding = v5, 13 slides | Done. Cold open → canvas concept → **paint demo** → **color cap** → **spend demo** → loop summary → steps/sleep → HealthKit → feed selection (skippable) → nowhere/now here → Sign in with Apple → welcome. Analytics: `onboarding_completed` with `flow: v5`. |
| Notes tab | Done. `NoteCatalog.all`: About the Canvas; Body, Mind, and Heart; **Shapes**; Sleep; Steps; Feeds; Limits; Wallpaper; **two** “About Colors” cards (different bodies; same `id` in code — see debt); About Kosta. Unread tracking via `NoteReadTracker`. |
| **Now** tab (profile / week) | Done. Tab bar label is **“Now”** (not “Me”); 7-day rings, reflection, breakdown, top consumers. |
| Home Screen widgets | Done. **UnlockWidgetExtension**: **Energy Status** (medium), **App Groups** (large, `AppIntentConfiguration` + `SelectGroupIntent`). Widget background: solid vs wallpaper snapshot (Settings → Widget). |
| Canvas tech | Done. `GenerativeCanvasView` (SwiftUI Canvas, Timeline animation) + `SmudgeOverlayView` / `MetalSmudgeRenderer` for paint-like interaction on the gallery canvas. |
| Feeds UX | Done. Paper ticket metaphor, **ticket templates** for common apps (`TicketTemplatePickerView` + `TargetResolver`). |
| Rest day override | Done. Settings toggle; floors base energy when enabled. |
| SharedKeys.swift | Done. App group + extensions. |
| Privacy manifest | Done. `PrivacyInfo.xcprivacy`. |

### Completed — Backend & Data

| Goal | Status |
|------|--------|
| Supabase ticket sync | Done. Delete + reinsert pattern via `syncTicketGroups`. |
| Supabase ticket deletion | Done. Real delete via `deleteTicket(bundleId:)`. |
| Analytics events | Done. `onboarding_completed`, `piece_selected`, `experience_spent`, `canvas_viewed`, `ticket_created`. |
| PastDaySnapshot vocabulary | Done. `inkEarned` / `inkSpent` with backward-compat decoding from `experienceEarned`/`controlGained`. |
| File-based persistence | Done. Payment transactions and past-day snapshots moved from UserDefaults to JSON. Snapshots pruned to 90 days. |
| Monitor log retention | Done. Capped at 30 entries. |
| Minute charge logs | Done. Shared file in App Group. |

### Completed — Code Quality

| Goal | Status |
|------|--------|
| Structured logging | Done. `AppLogger` (OSLog) replaces print statements. |
| Dead code removal | Done. Old views deleted. |
| Minute mode gated | Done. `minuteModeEnabled = false` flag; UI hidden. |
| Deprecated APIs | Done. `.synchronize()` removed, `UIApplication.shared.open` async. |
| Redundant objectWillChange | Done. Removed manual calls. |
| Fragile string matching | Done. Exact bundleId matching. |
| Unused imports | Done. |
| Debug views gated | Done. Behind `#if DEBUG`. |

### Known Remaining Items

| Item | Severity | Notes |
|------|----------|-------|
| Duplicate `Note.id` for two “About Colors” entries | Low | Both use `about_colors` in `NoteCatalog` — shuffle/read logic can treat them as one note for unread counts; consider distinct ids. |
| Internal names still say “steps” in places | Low | e.g. `totalStepsBalance`, `StepBalanceCard`, “Steps balance” a11y label — user sees “colors”; rename is mechanical. |
| AppModel forwarding layer | Medium | Coordinator still forwards heavily to stores; thin incrementally. |
| Residual `print()` in extensions/models | Low | Some encode paths and legacy logging; prefer `AppLogger` everywhere over time. |

---

## 3. Architecture Overview

### Targets (7)
1. **Steps4** — Main app target (bundle hosts SwiftUI app code under **StepsTrader/**)
2. **DeviceActivityMonitor** — Extension: app usage events, shield rebuild hooks
3. **ShieldAction** — Extension: shield button → deep link / unlock flow
4. **ShieldConfiguration** — Extension: shield UI (title, subtitle, brand gold button)
5. **UnlockWidgetExtension** — WidgetKit: **Energy Status** + **App Groups** (App Intents)
6. **Steps4Tests** — Unit tests
7. **Steps4UITests** — UI tests

### Data Flow
```
HealthKit (steps, sleep)
       |
       v
  HealthStore ──────────> AppModel (coordinator) <────── BlockingStore (tickets, shields)
       |                       |                              |
       v                       v                              v
  UserEconomyStore        UI (SwiftUI)                FamilyControls
  (balance, spending)          |                     ManagedSettings
       |                       v                     DeviceActivity
       v              5 tabs: Canvas, Feeds,
  Supabase sync        Now (week), Notes, Settings
  (selections, stats,
   tickets, analytics)
```

### Persistence
- **UserDefaults (App Group)**: Settings, state flags, small config shared with extensions
- **JSON files (Application Support)**: Payment transactions, past-day snapshots, minute charge logs, canvases
- **Supabase**: User profiles, daily selections, daily stats, tickets, canvases, analytics events
- **No CoreData or SwiftData**

### Key Technical Moats
- **FamilyControls + DeviceActivity + ManagedSettings + shield extensions** — hard to replicate; strongest iOS enforcement path
- **Generative canvas** — SwiftUI `Canvas` + timeline-driven motion; body / mind / heart visual grammar (breathing forms, drifting circles, heart beams); **Metal smudge** layer for direct manipulation
- **Energy gradient background** — full-screen ambient gradient driven by steps/sleep points
- **Widget + Intent surface** — spend/unlock path from Home Screen via `UnlockWidgetExtension`

---

## 4. Product Direction

### The Core Loop
1. **Live** — Walk, sleep, choose from three categories (body, mind, heart)
2. **See** — Your canvas fills up. The painting animates. Colors accumulate.
3. **Spend** — When you want into your feeds, you spend colors through the PayGate. Consciously, visibly.

### Tab Structure
| Tab | View | Purpose |
|-----|------|---------|
| 0 (default) | Canvas | The soul. Generative canvas + daily piece selection via radial menu. |
| 1 | Feeds | App blocking groups. Create tickets, set tariffs, configure time windows. |
| 2 | Now | Same as legacy “Me”: profile, 7-day ring row, weekly reflection, dimension breakdown, top consumers. |
| 3 | Notes | 11 cards, 10 topics — philosophy + founder letter; shuffle + browse. |
| 4 | Settings | Theme, targets, account, rest day override. |

### Vocabulary Contract (Enforced)
| Concept | THE word | NOT these |
|---------|---------|-----------|
| What your life produces | **colors** | balance, energy, EXP, experience, steps, points, ink (ink is code-only) |
| What you do each day | **pieces** | activities, selections, options |
| The three categories | **body, mind, heart** | Move/Reboot/Joy |
| The app groups | **tickets** (code) / **feeds** (tab) | shields, groups, bundles |
| The exchange | **spend** | pay, deduct, use, trade |
| The dismiss option | **keep it closed** | cancel, dismiss, close, lock |
| History | **archive** | memories, history |
| Philosophy entries | **notes** | guides, manuals, help |

---

## 5. Philosophical Foundation

### The Canvas Metaphor
Your life is a daily canvas. You paint it with every choice. Screen time is what you trade to leave your own canvas and enter someone else's feed.

### The Three Categories
| Category | Lineage | Activities (10+ each) |
|----------|---------|---------------------|
| **body** | Aristotle's *energeia* | Walking, Physical Effort, Stretching, Resting, Breathing, Touch, Balance, Repetition, Warming, Stillness, Healing |
| **mind** | Arendt's *work* | Focusing, Learning, Thinking, Planning, Writing, Observing, Questioning, Ordering, Remembering, Letting Go |
| **heart** | Epicurus's *hedone* | Joy, Calm, Gratitude, Connection, Care, Wonder, Trust, Vulnerability, Belonging, Peace |

### Notes Tab Content (shipped `NoteCatalog`)

| Topic (title) | What it covers |
|---------------|----------------|
| About the Canvas | Day as reflection; noticing what makes days different |
| About Body, Mind, and Heart | Tibetan-inspired three-part framing, humble voice |
| About Shapes | Why body = breathing shapes, mind = drifting circles, heart = beams |
| About Sleep | Sleep on canvas (darker = more rest), HealthKit sync honesty |
| About Steps | Steps as proof of moving through the world, not fitness flex |
| About Feeds | Minutes disappear; spending colors drains the canvas |
| About Limits | Personal thresholds, not universal musts |
| About Wallpaper | Canvas as lock-screen mirror; shortcut tradeoff |
| About Colors (×2) | Palette intent + “not for sale” economy stance (two separate essays) |
| About Kosta | Founder letter — nowhere → now here, burnout, contact in Settings |

---

## 6. Tone of Voice

**Canonical reference**: `TONE_OF_VOICE.md` (principles, surface-by-surface examples, anti-patterns).

**Model**: One human speaking to another. Onboarding and Notes lean **lowercase and literary**; shields and notifications stay **short and factual**.

| Trait | How it sounds | Anti-pattern |
|-------|--------------|--------------|
| Observational | Me tab: compact numbers, “earned · spent · kept” | Trophy language, streak hype |
| Respectful | “Create one when you're ready.” | Guilt, urgency |
| Dry | Canvas empty: “Today is uncolored” | Busy placeholders |
| Economical | “10 min · 4 colors”, “keep it closed” | Marketing padding |
| Honest | “spend colors” with the number | Fake rewards |

**Rules** (summary):
- No exclamation marks in routine UI (onboarding can use rare emphasis sparingly — follow `TONE_OF_VOICE.md`)
- Shield: “[App] is closed.” / spend colors in Nowhere
- Notes: essay tone, not help docs
- **StepBalanceCard**: colors glyph + balance **current / earned-today / 100** + reset timer + expandable category chips (no “NOW/HERE” split header in current UI)

---

## 7. Marketing & Launch Strategy

### Positioning
**Not a screen-time blocker.** A daily life canvas that happens to control your feeds.

**One-line pitch**: *"Your life makes colors. Your feeds cost them."*

### Target Audience
| Segment | Why | Where |
|---------|-----|-------|
| Intentional living (25-35) | Wants a system, not a blocker | r/digitalminimalism, r/nosurf, Substack |
| Quantified self (22-35) | Tracks everything, wants screen time in the dashboard | r/QuantifiedSelf, fitness Twitter |
| Creative/philosophical (20-30) | Attracted to the canvas metaphor and paper aesthetic | Design Twitter, Are.na, Tumblr |

### Phased GTM

**Phase 1: Closed Beta (Weeks 1-4 from now)**
- TestFlight build from current codebase
- 30-50 testers from personal network + targeted Reddit posts
- Test positioning: "Your life makes colors" vs "Your day is a canvas"
- In-app feedback + weekly survey
- Key metric: D7 retention, can testers explain Nowhere in one sentence?

**Phase 2: Landing Page + Open Beta (Weeks 5-8)**
- Single-page site: hero screenshot of canvas tab + pitch line
- 3-step visual: Live, See, Spend
- ProductHunt prep
- 10 outreach emails to productivity/design newsletter creators

**Phase 3: Public Launch (Weeks 9-12)**
- App Store listing optimized for "Nowhere"
- Free with premium ($3.99/mo): unlimited tickets, weekly insights, widget customization
- Launch week: ProductHunt + Reddit + X + 2-3 podcast appearances

---

## 8. Roadmap

### Now: Beta Prep (1-2 weeks)

| Task | Status |
|------|--------|
| Final QA pass on device | Pending |
| TestFlight build | Pending |
| Recruit 30-50 beta testers | Pending |
| App Store Connect setup (name reservation, screenshots, widget screenshots) | Pending |
| Fix `NoteCatalog` duplicate `id` for two color essays | Optional polish |

### Post-Beta (Month 2-3)

| Feature | Priority | Notes |
|---------|----------|-------|
| Beta feedback analysis | P0 | D7 retention; can users explain the loop (canvas → colors → feeds)? |
| Onboarding A/B test | P1 | v5 interactive flow vs shorter permission-first variant |
| More notes entries | P1 | e.g. spectacle, imperfection — match existing voice |
| Internal variable rename | P2 | `totalStepsBalance` → colors naming (dedicated PR) |
| AppModel forwarding cleanup | P2 | Incremental |
| Premium / tip jar | P1 | Strategy doc historically floated $3.99/mo — **no StoreKit in repo yet**; align with “can’t buy colors” promise |
| Landing page | P1 | Hero: canvas + one line pitch |

### Medium-Term (Months 4-6)

| Feature | Priority | Notes |
|---------|----------|-------|
| Lock Screen–native complications | P2 | If desired — current widgets are Home Screen medium/large |
| Shortcuts | P2 | Canvas wallpaper export intent exists — expand if needed |
| Apple Watch (glance at colors) | P2 | |
| Minute-based tariffs | P3 | Legacy hooks in `FamilyControlsService`; core UX is color windows |
| Social exploration | P3 | Speculative — only if it fits anti-gamification stance |

### Checkpoints

| When | Question | If no... |
|------|----------|----------|
| Week 4 | Can beta users explain Nowhere in one sentence? | Name/messaging needs rework. |
| Week 6 | D7 retention > 20%? | Core loop needs investigation. Are users curating but not spending? Or not curating at all? |
| Month 3 | >500 installs from launch? | Pivot from organic to creator partnerships. |
| Month 4 | Premium conversion > 2%? | Test lower price, different feature gate, or "patron" tip jar model. |

---

## 9. Technical Debt (Prioritized)

### High Priority (Before Public Launch)

| Item | Impact | Effort |
|------|--------|--------|
| Device + shield + widget QA on release OS | Extensions are fragile across iOS updates | Ongoing |
| Internal "steps" vocabulary rename | Dev clarity; optional a11y string tweaks | Large (mechanical) |
| AppModel forwarding layer cleanup | Maintainability | Medium (incremental) |

### Low Priority (Post-Launch)

| Item | Impact | Effort |
|------|--------|--------|
| Note duplicate `id` | Edge cases for read/shuffle | Tiny |
| `titleRu` on `EnergyOption` | Unused in UI | Small migration |
| Test coverage expansion | Beyond BudgetEngine, DailyEnergy, DayBoundary, etc. | Large |

---

## 10. File Inventory

### App Entry
- `StepsTraderApp.swift` — @main, lifecycle, onboarding gate, PayGate overlay

### Core
- `AppModel.swift` + extensions — Central coordinator
- `DIContainer.swift` — Dependency injection
- `TargetResolver.swift` — URL scheme resolution
- `HandoffManager.swift` — Handoff token handling

### Stores (3)
- `HealthStore.swift` — Steps, sleep, HealthKit auth
- `BlockingStore.swift` — Tickets, app selection, shield state
- `UserEconomyStore.swift` — Balance (colors), spending, transactions

### Models
- `Types.swift`, `DailyEnergy.swift`, `BudgetEngine.swift`, `TicketGroup.swift`, `CanvasElement.swift`, `AccessWindow.swift`, `PayGateSession.swift`, `MinuteChargeLog.swift`, `AppUnlockSettings.swift`, `LiteTicketConfig.swift`, `PayGateBackgroundStyle.swift`, `ChoiceImageCatalog.swift`, `Note.swift`

### Services
- `HealthKitService.swift`, `FamilyControlsService.swift`, `NotificationManager.swift`, `SupabaseSyncService.swift`, `CloudKitService.swift`, `AuthenticationService.swift`, `PersistenceManager.swift`, `ErrorManager.swift`, `NetworkClient.swift`, `CanvasStorageService.swift`, `ProfileLocationManager.swift`, `UnlockExpiryTaskManager.swift`

### Views — Primary
- `MainTabView.swift`, `GalleryView.swift`, `AppsPageSimplified.swift`, `MeView.swift`, `ManualsPage.swift`, `SettingsSheet.swift`, `OnboardingFlowView.swift`, `OnboardingStoriesView.swift`, `PayGateView.swift`, `HandoffProtectionView.swift`, `LoginView.swift`, `GenerativeCanvasView.swift`, `TicketTemplatePickerView.swift`

### Views — Components
- `StepBalanceCard.swift`, `SmudgeCanvasView.swift` / `SmudgeOverlayView`, `DailyEnergyCard.swift`, `TariffOptionView.swift`, `StatusRow.swift`, `StatMiniCard.swift`, `AppSelectionComponents.swift`, `TimeAccessPickerSheet.swift`, `ImagePicker.swift`, `EnergyGradientBackground.swift`, `PaperTicketView.swift`

### Views — Secondary
- `RadialHoldMenu.swift`, `ColorPaletteView.swift`, `CategoryDetailView.swift`, `EnergySetupView.swift`, `OptionEntrySheet.swift`, `CustomActivityEditorView.swift`, `TicketGroupSettingsView.swift`, `InlineTicketSettingsView.swift`, `AutomationGuideView.swift`

### Utilities & strings
- `SharedKeys.swift`, `UserDefaults+StepsTrader.swift`, `DayBoundary.swift`, `Date+Today.swift`, `ColorConstants.swift`, `Font+Custom.swift`, `AppLogger.swift`, `Localizable.xcstrings`

### Extensions (4 targets)
- `DeviceActivityMonitorExtension.swift`
- `ShieldActionExtension.swift`
- `ShieldConfigurationExtension.swift`
- **UnlockWidget/** — `UnlockWidgetBundle.swift`, `UnlockWidgetViews.swift`, `UnlockTimelineProvider.swift`, `UnlockGroupWidgetIntent.swift`

### Metal
- `MetalSmudgeRenderer.swift`, `SmudgeShaders.metal`

### Tests
- Unit tests: BudgetEngine, DailyEnergy, MinuteCharge, CustomActivity, DayBoundary
- UI tests: CustomActivityUITests

---

*Last updated: April 2, 2026. Verified against this repository (app, shield, widgets, onboarding v5, `NoteCatalog`, `MainTabView` tab titles).*
