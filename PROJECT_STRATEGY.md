# Nowhere — Strategic Blueprint (Updated February 24, 2026)

> Reconciled with the actual codebase as of late February 2026. All claims verified against shipped code.

---

## 1. Executive Summary

**What Nowhere is**: A SwiftUI iOS app where your real life — steps, sleep, and daily choices across three categories (body, mind, heart) — produces colors. Colors are what you spend to open your feeds. The canvas is the soul of the product; screen time is what you trade to leave your own canvas and enter someone else's feed.

**Current state**: ~95% feature-complete for beta. Branded as **Nowhere**, uses canvas/colors language throughout, 12-entry Notes tab, 7-slide onboarding, and a 5-tab layout. The codebase has been through a full audit with 60+ fixes landed.

**What remains for beta launch**: Final QA, TestFlight build, beta tester recruitment, fix remaining "Proof" references in shield copy.

---

## 2. Current State (As of Feb 24, 2026)

### Completed — Identity & Vocabulary

| Goal | Status |
|------|--------|
| App name = "Nowhere" | Done. Notifications, onboarding, StepBalanceCard header ("NOW / HERE") all say Nowhere. |
| Currency = "colors" | Done in UI. PayGate reads "spend colors", "N colors". Internal model uses `ink` (inkEarned/inkSpent). |
| Three categories = body / mind / heart | Done. Canvas headers, balance card chips, onboarding, notes all use body / mind / heart. |
| 10+ activities per category | Done. Body (11), Mind (10), Heart (10). Custom user-added activities supported. |
| Shield copy = canvas tone | Partial. Copy reads "[app] is closed. Open Nowhere to spend colors." |
| PayGate = choice framing | Done. "keep it closed", "spend colors", cost as "N colors". |
| English-only for v1 | Done. All `loc()` wrappers stripped. `titleRu` fields remain in models for backward compat but are unused. |
| Difficulty labels | Done. Neutral "Level 1" through "Level 5". |

### Completed — Architecture & UX

| Goal | Status |
|------|--------|
| Canvas = default tab | Done. Tab 0, default selection on launch. |
| Onboarding = 7 slides, canvas-first | Done. Welcome, heart picks, body picks, mind picks, steps setup, sleep setup, permissions. |
| Notes tab = 12 wall texts | Done. Topics: canvas, body/mind/heart, sleep, steps, feeds, limits, wallpaper, colors, proof, threshold, time. |
| Me tab = weekly reflection | Done. 7-day ring row, reflection line, dimension breakdown (body/mind/heart), average stats, top consumers. |
| Lock Screen widget | Done. ProofLockScreenWidget extension — inline/circular/rectangular accessories showing colors. |
| Rest day override | Done. Toggle in Settings, floors base energy to 30 when enabled. |
| SharedKeys.swift | Done. Single enum shared across app + 3 extensions. |
| Privacy manifest | Done. PrivacyInfo.xcprivacy with UserDefaults API declaration. |

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
| Shield copy says "Proof" instead of "Nowhere" | Medium | `ShieldConfigurationExtension.swift` — "Open Proof to spend colors." should be "Open Nowhere to spend colors." |
| ProofLockScreenWidget target name | Low | Code target is still named `ProofLockScreenWidget`. Renaming requires Xcode project changes. User-facing display name may differ. |
| Internal variable names still use "steps" vocabulary | Low | `stepsBalance`, `spentStepsToday`, etc. Deliberate deferral — large mechanical rename, no user impact. |
| AppModel forwarding layer | Medium | ~65 computed properties forward to stores. Remove incrementally. |
| A few `print()` calls remain | Low | Debug logging in tab bar and notification handlers. |

---

## 3. Architecture Overview

### Targets (7)
1. **StepsTrader** — Main app
2. **DeviceActivityMonitor** — Extension: tracks app usage events
3. **ShieldAction** — Extension: handles shield button taps
4. **ShieldConfiguration** — Extension: provides shield UI content
5. **ProofLockScreenWidget** — WidgetKit extension: Lock Screen colors display
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
  Supabase sync        Me, Notes, Settings
  (selections, stats,
   tickets, analytics)
```

### Persistence
- **UserDefaults (App Group)**: Settings, state flags, small config shared with extensions
- **JSON files (Application Support)**: Payment transactions, past-day snapshots, minute charge logs, canvases
- **Supabase**: User profiles, daily selections, daily stats, tickets, canvases, analytics events
- **No CoreData or SwiftData**

### Key Technical Moats
- **FamilyControls + DeviceActivity + ManagedSettings + 3 extensions** — months of integration work
- **Generative canvas** — real-time animated visualization of daily colors (circles for body/mind, beams for heart)
- **Energy gradient background** — ambient background that shifts with steps/sleep points

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
| 2 | Me | Profile, 7-day ring row, weekly reflection, dimension breakdown, top consumers. |
| 3 | Notes | 12 wall texts — philosophy, not instructions. Shuffle + browse. |
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

### Notes Tab Content (12 Entries)
| Note | Opening line |
|------|-------------|
| on canvas | "The canvas is not a to-do list. It is a mirror of the day..." |
| on body, mind and heart | "Three rooms. You don't rank them..." |
| on sleep | "Sleep is not a reward. It is the opening act..." |
| on steps | "Steps are the raw currency. Not a fitness metric..." |
| on feeds | "Feeds are the places where minutes disappear..." |
| on limits | "A limit is not a punishment. It is a threshold..." |
| on wallpaper | "The wallpaper is proof that today happened..." |
| on colors | "Colors shift with energy. They are not decoration — they are weather..." |
| on colors | "Colors are energy made visible..." |
| on proof | "Proof is not self-improvement. It is a record of what you chose to trade..." |
| on the threshold | "Tickets are thresholds, not punishments. You pause..." |
| on time | "Time doesn't refill. Steps do..." |

---

## 6. Tone of Voice

**Model**: Canvas wall text. Observational. Brief. Trusting.

| Trait | How it sounds | Anti-pattern |
|-------|--------------|--------------|
| Observational | "Today: 6,200 steps. 7h sleep. 3 pieces." | "Great job! You're crushing it!" |
| Respectful | "You chose this. Change it anytime." | "Don't give up! Stay strong!" |
| Dry | Empty state: "No tickets yet. Create one when you're ready." | "Oops! Looks like you haven't started!" |
| Economical | "10 min · 4 colors" | "Unlock for 10 minutes at a cost of 4 colors" |
| Honest | "spend colors" — then the number, no decoration | "Enjoy your well-deserved break!" |

**Rules**:
- No exclamation marks in UI
- No lightning bolt icons/emojis
- Empty states are canvas silence, not panic
- Shield copy is the firmest the voice gets
- Notes tab copy is poetry, not advice
- StepBalanceCard header splits the name: "NOW" over "HERE"

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
| Fix shield copy: "Proof" → "Nowhere" | Pending |
| Final QA pass on device | Pending |
| TestFlight build | Pending |
| Recruit 30-50 beta testers | Pending |
| App Store Connect setup (name reservation, screenshots) | Pending |

### Post-Beta (Month 2-3)

| Feature | Priority | Notes |
|---------|----------|-------|
| Beta feedback analysis | P0 | Act on D7 retention data and user explanations |
| Onboarding A/B test | P1 | Canvas-first vs permissions-first |
| More notes entries | P1 | "on the spectacle" (Debord), "on imperfection" (wabi-sabi) |
| Internal variable rename | P2 | stepsBalance -> colorsBalance, etc. (dedicated PR) |
| AppModel forwarding cleanup | P2 | Remove remaining forwarding layer incrementally |
| Premium tier implementation | P1 | 3 free tickets, then $3.99/mo |
| Landing page | P1 | "Your life makes colors. Your feeds cost them." |

### Medium-Term (Months 4-6)

| Feature | Priority | Notes |
|---------|----------|-------|
| Home Screen widgets | P1 | Expand beyond Lock Screen |
| Shortcuts integration | P2 | |
| Apple Watch (colors display) | P2 | |
| Re-enable minute mode as opt-in | P3 | Code exists, gated behind flag |
| Social exploration | P3 | Anonymous weekly canvas leaderboard |

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
| Shield copy still says "Proof" | User-facing inconsistency — shield is the most visible surface | Small (2 string changes in ShieldConfigurationExtension.swift) |
| Internal "steps" vocabulary rename | Cognitive dissonance for devs working on the codebase | Large (mechanical, touches many files) |
| AppModel forwarding layer cleanup | Indirection, stale-data risk, god-object pattern | Medium (incremental) |

### Low Priority (Post-Launch)

| Item | Impact | Effort |
|------|--------|--------|
| ProofLockScreenWidget target rename | Target name says "Proof", user-facing display may differ | Medium (Xcode project changes) |
| `titleRu` fields in models | Dead weight — no Russian UI path exists | Small (remove field, migration) |
| Test coverage expansion | Only core logic tested; no view model or service tests | Large |

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
- `MainTabView.swift`, `GalleryView.swift`, `AppsPageSimplified.swift`, `MeView.swift`, `ManualsPage.swift`, `SettingsSheet.swift`, `OnboardingFlowView.swift`, `OnboardingStoriesView.swift`, `PayGateView.swift`, `HandoffProtectionView.swift`, `LoginView.swift`, `GenerativeCanvasView.swift`

### Views — Components
- `StepBalanceCard.swift`, `DailyEnergyCard.swift`, `TariffOptionView.swift`, `StatusRow.swift`, `StatMiniCard.swift`, `AppSelectionComponents.swift`, `TimeAccessPickerSheet.swift`, `ImagePicker.swift`, `EnergyGradientBackground.swift`, `PaperTicketView.swift`

### Views — Secondary
- `RadialHoldMenu.swift`, `ColorPaletteView.swift`, `CategoryDetailView.swift`, `EnergySetupView.swift`, `OptionEntrySheet.swift`, `CustomActivityEditorView.swift`, `TicketGroupSettingsView.swift`, `InlineTicketSettingsView.swift`, `AutomationGuideView.swift`

### Utilities
- `SharedKeys.swift`, `UserDefaults+StepsTrader.swift`, `DayBoundary.swift`, `Date+Today.swift`, `ColorConstants.swift`, `Font+Custom.swift`, `AppLogger.swift`

### Extensions (4 targets)
- `DeviceActivityMonitorExtension.swift`
- `ShieldActionExtension.swift`
- `ShieldConfigurationExtension.swift`
- `ProofLockScreenWidget.swift`

### Tests
- Unit tests: BudgetEngine, DailyEnergy, MinuteCharge, CustomActivity, DayBoundary
- UI tests: CustomActivityUITests

---

*Last updated: February 24, 2026. Verified against actual codebase. All vocabulary, tab names, note content, and UI copy reflect current shipped state.*
