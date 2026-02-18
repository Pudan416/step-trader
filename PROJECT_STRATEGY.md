# Proof — Strategic Blueprint (Updated February 15, 2026)

> Updated to reflect the current state of the codebase after completing the full code audit and strategy-aligned fix plan. The original six-agent vision document has been condensed and reconciled with what actually shipped.

---

## 1. Executive Summary

**What Proof is**: A SwiftUI iOS app where your real life — steps, sleep, and daily choices across three rooms (body, mind, heart) — earns experience. Experience is what you spend to unlock your apps. The gallery of lived experience is the soul of the product; screen time is what you trade to leave your own gallery and enter someone else's.

**Current state**: ~95% feature-complete for beta. All strategic vocabulary, identity, and UX changes from the original audit have been implemented. The app is branded as **Proof**, uses gallery-toned language throughout, and has a clean 7-slide onboarding flow. The codebase has been through a full audit with 60+ fixes landed.

**What remains for beta launch**: Final QA, TestFlight build, beta tester recruitment.

---

## 2. Current State (As of Feb 15, 2026)

### Completed — Identity & Vocabulary

| Goal | Status |
|------|--------|
| App name = "Proof" | Done. Display name, notifications, shield copy, onboarding all say "Proof". |
| Vocabulary = "experience" | Done. No more "EXP", "balance", "energy" in UI. StepBalanceCard reads "experience". |
| Three rooms = body / mind / heart | Done. Gallery headers, balance card chips, onboarding all use "my body / my mind / my heart". |
| Piece names = action phrases | Done. "dancing it out", "following my curiosity", "holding someone close", etc. |
| Shield copy = gallery tone | Done. "[app] is closed. Open Proof to spend experience." No bolts, no "BLOCKED". |
| PayGate = choice framing | Done. "keep it closed" (not locked), "spend experience" (lowercase), cost as "N experience" (no bolts). |
| English-only for v1 | Done. All `loc()` wrappers stripped, Russian branches deleted, `appLanguage` toggle removed. |
| Russian comments | Done. All ~100+ translated to English across 27 files. |
| Difficulty labels | Done. Neutral "Level 1" through "Level 5" (not Rookie/Rebel/Fighter/etc). |

### Completed — Architecture & UX

| Goal | Status |
|------|--------|
| Gallery = default tab | Done. Tab 0, default selection on launch. |
| Onboarding = 7 slides, gallery-first | Done. Welcome, heart picks, body picks, mind picks, steps setup, sleep setup, permissions. |
| Guides tab = philosophy wall texts | Done. 3 entries: "on proof", "on the three rooms", "on the threshold". |
| Weekly reflection card | Done. In Me tab — shows 7-day earned/spent/kept experience and strongest room. |
| Lock Screen widget | Done. ProofLockScreenWidget extension — inline/circular/rectangular accessories showing experience. |
| Rest day override | Done. Toggle in Settings, floors base energy to 30 when enabled. |
| SharedKeys.swift | Done. Single enum shared across app + 3 extensions. All raw string keys consolidated. |
| Privacy manifest | Done. PrivacyInfo.xcprivacy with UserDefaults API declaration. |
| README | Done. Matches current behavior (Proof branding, active shield extensions). |

### Completed — Backend & Data

| Goal | Status |
|------|--------|
| Supabase ticket sync | Done. Delete + reinsert pattern via `syncTicketGroups`. |
| Supabase ticket deletion | Done. Real delete via `deleteTicket(bundleId:)`. |
| Analytics events | Done. `onboarding_completed`, `piece_selected`, `experience_spent`, `gallery_viewed`, `ticket_created` — queued and flushed to `user_analytics_events`. |
| PastDaySnapshot vocabulary | Done. `experienceEarned` / `experienceSpent` with backward-compat decoding. |
| File-based persistence | Done. Payment transactions and past-day snapshots moved from UserDefaults to JSON files. Snapshots pruned to 90 days. |
| Monitor log retention | Done. Capped at 30 entries (was 200). |
| Minute charge logs | Done. Shared file in App Group (single source of truth for app + extensions). |

### Completed — Code Quality

| Goal | Status |
|------|--------|
| Structured logging | Done. `AppLogger` (OSLog) replaces 200+ `print()` statements. |
| Dead code removal | Done. `AppsPage.swift`, `BlockScreen.swift`, `BlockScreenNew.swift` deleted. Placeholder HealthKit method deleted. |
| Minute mode gated | Done. `minuteModeEnabled = false` flag; UI hidden. |
| Deprecated APIs | Done. `.synchronize()` removed, `UIApplication.shared.open` async. |
| Redundant objectWillChange | Done. Removed manual calls + sleep-based UI hacks. |
| Fragile string matching | Done. Exact bundleId matching replaces substring contains. |
| Dead forwarding properties | Done. `rebuildShieldTask` no-op deleted. |
| Unused imports | Done. AVFoundation, AudioToolbox, Combine, CoreLocation removed where unused. |
| Debug views gated | Done. QuickStatusView, AutomationGuideView behind `#if DEBUG`. |

### Known Remaining Items

| Item | Severity | Notes |
|------|----------|-------|
| 4 `bolt.fill` icons in ShieldGroupSettingsView + SettingsView | Low | Internal settings screens, not primary user flow. Should be replaced with "experience" text or neutral icon. |
| Internal variable names still use "steps" vocabulary | Low | `stepsBalance`, `spentStepsToday`, etc. Deliberate deferral — large mechanical rename, no user impact. Should be a dedicated PR. |
| A few `print()` calls remain in MainTabView | Low | Debug logging in tab bar and notification handlers. |
| AppModel forwarding layer | Medium | ~65 computed properties forward to stores. Views have been migrated to direct store access but forwarding shim remains. Remove incrementally. |
| `RatingView` placeholder | Low | "Outer World / map tab" concept — not in current scope. |
| Stale TODO in `AppModel+TicketManagement.swift:43` | Trivial | Says "TODO: Implement Supabase ticket sync" but sync is already implemented. Remove comment. |
| `joys_embrase` typo in option ID | Low | Should be `joys_embrace`. Needs migration for users who already selected it. |

---

## 3. Architecture Overview

### Targets (7)
1. **StepsTrader** — Main app (102 Swift files)
2. **DeviceActivityMonitor** — Extension: tracks app usage events
3. **ShieldAction** — Extension: handles shield button taps
4. **ShieldConfiguration** — Extension: provides shield UI content
5. **ProofLockScreenWidget** — WidgetKit extension: Lock Screen experience display
6. **Steps4Tests** — Unit tests (BudgetEngine, DailyEnergy, MinuteCharge, CustomActivity, DayBoundary)
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
       v              5 tabs: Gallery, Tickets,
  Supabase sync        Me, Guides, Settings
  (selections, stats,
   tickets, analytics)
```

### Persistence
- **UserDefaults (App Group)**: Settings, state flags, small config shared with extensions
- **JSON files (Application Support)**: Payment transactions, past-day snapshots, minute charge logs, canvases
- **Supabase**: User profiles, daily selections, daily stats, tickets, canvases, analytics events
- **No CoreData or SwiftData**

### Key Technical Moats
- **FamilyControls + DeviceActivity + ManagedSettings + 3 extensions** — months of integration work that competitors can't shortcut
- **Generative canvas** — real-time animated visualization of daily experience (circles for body/mind, rays for heart)
- **Energy gradient background** — ambient background that shifts with steps/sleep points

---

## 4. Product Direction

### The Core Loop
1. **Live** — Walk, sleep, choose pieces from three rooms (body, mind, heart)
2. **Exhibit** — Your gallery fills up. The canvas animates. Experience accumulates.
3. **Spend** — When you want into your apps, you spend experience through the PayGate. Consciously, visibly.

### Tab Structure
| Tab | View | Purpose |
|-----|------|---------|
| 0 (default) | Gallery | The soul. Generative canvas + daily piece selection via radial menu. |
| 1 | Tickets | App blocking groups. Create tickets, set tariffs, configure time windows. |
| 2 | Me | Profile, 60-day archive, weekly reflection card. |
| 3 | Guides | Philosophy wall texts (3 entries). |
| 4 | Settings | Theme, targets, account, rest day override. |

### Vocabulary Contract (Enforced)
| Concept | THE word | NOT these |
|---------|---------|-----------|
| What your life produces | **experience** | balance, energy, EXP, steps, points |
| What you do each day | **pieces** | activities, selections, options |
| The three categories | **rooms**: body, mind, heart | Move/Reboot/Joy, categories |
| The app groups | **tickets** | shields, groups, bundles |
| The exchange | **spend** | pay, deduct, use, trade |
| History | **archive** | memories, history |

---

## 5. Philosophical Foundation

### The Gallery Metaphor
Your life is a daily exhibition. You curate it with every choice. Screen time is what you trade to leave your own gallery and enter someone else's.

### The Three Rooms
| Room | Lineage | Covers |
|------|---------|--------|
| **my body** | Aristotle's *energeia* | dancing it out, eating a real meal, pushing my limits, taking a real risk, making love, feeling my strength, overcoming something hard |
| **my mind** | Arendt's *work* | following my curiosity, making money happen, letting my mind wander, creating something new, noticing the invisible, visiting a real place, watching the world closely |
| **my heart** | Epicurus's *hedone* | embracing the cringe, holding someone close, feeling deeply today, being with my people, crying from joy, feeling in love, kissing someone, choosing myself today, going all out, breaking my rules, guilty pleasures |

### Guides Tab Content (Implemented)
1. **"on proof"** — Proof is not self-improvement. It is a record of what you chose to trade.
2. **"on the three rooms"** — Body, mind, heart. Three rooms where the day leaves its traces.
3. **"on the threshold"** — Tickets are thresholds, not punishments. You pause. You decide.

---

## 6. Tone of Voice

**Model**: Gallery wall text. Observational. Brief. Trusting.

| Trait | How it sounds | Anti-pattern |
|-------|--------------|--------------|
| Observational | "Today: 6,200 steps. 7h sleep. 3 pieces." | "Great job! You're crushing it!" |
| Respectful | "You chose this. Change it anytime." | "Don't give up! Stay strong!" |
| Dry | Empty state: "No tickets yet. Create one when you're ready." | "Oops! Looks like you haven't started!" |
| Economical | "10 min · 4 experience" | "Unlock for 10 minutes at a cost of 4 experience" |
| Honest | "You're spending 10 experience on YouTube." | "Enjoy your well-deserved break!" |

**Rules**:
- No exclamation marks in UI
- No lightning bolt icons/emojis
- Empty states are gallery silence, not panic
- Shield copy is the firmest the voice gets
- Guides tab copy is poetry, not advice

---

## 7. Marketing & Launch Strategy

### Positioning
**Not a screen-time blocker.** A daily life exhibition that happens to control your apps.

**One-line pitch**: *"Prove you lived today — then scroll."*

### Target Audience
| Segment | Why | Where |
|---------|-----|-------|
| Intentional living (25-35) | Wants a system, not a blocker | r/digitalminimalism, r/nosurf, Substack |
| Quantified self (22-35) | Tracks everything, wants screen time in the dashboard | r/QuantifiedSelf, fitness Twitter |
| Creative/philosophical (20-30) | Attracted to the gallery metaphor and paper aesthetic | Design Twitter, Are.na, Tumblr |

### Phased GTM (Updated Timeline)

**Phase 1: Closed Beta (Weeks 1-4 from now)**
- TestFlight build from current codebase
- 30-50 testers from personal network + targeted Reddit posts
- Test positioning: "Your life earns screen time" vs "Your day is an exhibition"
- In-app feedback + weekly survey
- Key metric: D7 retention, can testers explain Proof in one sentence?

**Phase 2: Landing Page + Open Beta (Weeks 5-8)**
- Single-page site: hero screenshot of gallery tab + "Prove you lived today"
- 3-step visual: Live, Exhibit, Unlock
- ProductHunt prep
- 10 outreach emails to productivity/design newsletter creators

**Phase 3: Public Launch (Weeks 9-12)**
- App Store listing optimized for "Proof"
- Free with premium ($3.99/mo): unlimited tickets, weekly insights, widget customization
- Launch week: ProductHunt + Reddit + X + 2-3 podcast appearances

---

## 8. Roadmap

### Now: Beta Prep (1-2 weeks)

| Task | Status |
|------|--------|
| Final QA pass on device | Pending |
| Fix remaining `bolt.fill` icons (4 instances) | Pending |
| Remove stale TODO comments | Pending |
| TestFlight build | Pending |
| Recruit 30-50 beta testers | Pending |
| App Store Connect setup (name reservation, screenshots) | Pending |

### Post-Beta (Month 2-3)

| Feature | Priority | Notes |
|---------|----------|-------|
| Beta feedback analysis | P0 | Act on D7 retention data and user explanations |
| Onboarding A/B test | P1 | Gallery-first vs permissions-first |
| 2 more Guides entries | P1 | "on the spectacle" (Debord), "on imperfection" (wabi-sabi) |
| Internal variable rename | P2 | stepsBalance -> experienceBalance, etc. (dedicated PR) |
| AppModel forwarding cleanup | P2 | Remove remaining forwarding layer incrementally |
| Premium tier implementation | P1 | 3 free tickets, then $3.99/mo |
| Landing page | P1 | "Prove you lived today" |

### Medium-Term (Months 4-6)

| Feature | Priority | Notes |
|---------|----------|-------|
| Home Screen widgets | P1 | Expand beyond Lock Screen |
| Shortcuts integration | P2 | |
| Apple Watch (experience display) | P2 | |
| Re-enable minute mode as opt-in | P3 | Code exists, gated behind flag |
| Social exploration | P3 | Anonymous weekly exhibition leaderboard |

### Checkpoints

| When | Question | If no... |
|------|----------|----------|
| Week 4 | Can beta users explain Proof in one sentence? | Name/messaging needs rework. Test "Daylight" or "Vigil". |
| Week 6 | D7 retention > 20%? | Core loop needs investigation. Are users curating but not spending? Or not curating at all? |
| Month 3 | >500 installs from launch? | Pivot from organic to creator partnerships. |
| Month 4 | Premium conversion > 2%? | Test lower price, different feature gate, or "patron" tip jar model. |

---

## 9. Technical Debt (Prioritized)

### High Priority (Before Public Launch)

| Item | Impact | Effort |
|------|--------|--------|
| Internal "steps" vocabulary rename | Cognitive dissonance for devs working on the codebase | Large (mechanical, but touches many files) |
| AppModel forwarding layer cleanup | Indirection, stale-data risk, god-object pattern | Medium (incremental, screen by screen) |
| Remaining `print()` calls | Ships to production, clutters Console | Small |

### Low Priority (Post-Launch)

| Item | Impact | Effort |
|------|--------|--------|
| `RatingView` placeholder | Dead screen, no navigation path to it | Trivial (delete or implement) |
| `joys_embrase` typo in option ID | Data key mismatch for future users | Small (rename + migration) |
| Test coverage expansion | Only core logic tested; no view model or service tests | Large |

---

## 10. File Inventory (102 Swift Files)

### App Entry
- `StepsTraderApp.swift` — @main, lifecycle, onboarding gate, PayGate overlay

### Core
- `AppModel.swift` + 8 extensions — Central coordinator
- `DIContainer.swift` — Dependency injection
- `TargetResolver.swift` — URL scheme resolution
- `HandoffManager.swift` — Handoff token handling

### Stores (3)
- `HealthStore.swift` — Steps, sleep, HealthKit auth
- `BlockingStore.swift` — Tickets, app selection, shield state
- `UserEconomyStore.swift` — Balance, spending, transactions

### Models (12)
- `Types.swift`, `DailyEnergy.swift`, `BudgetEngine.swift`, `TicketGroup.swift`, `CanvasElement.swift`, `AccessWindow.swift`, `PayGateSession.swift`, `MinuteChargeLog.swift`, `AppUnlockSettings.swift`, `LiteTicketConfig.swift`, `PayGateBackgroundStyle.swift`, `ChoiceImageCatalog.swift`

### Services (11)
- `HealthKitService.swift`, `FamilyControlsService.swift`, `NotificationManager.swift`, `SupabaseSyncService.swift`, `CloudKitService.swift`, `AuthenticationService.swift`, `PersistenceManager.swift`, `ErrorManager.swift`, `NetworkClient.swift`, `CanvasStorageService.swift`, `ProfileLocationManager.swift`

### Views — Primary (12)
- `MainTabView.swift`, `GalleryView/ChoiceView.swift`, `AppsPageSimplified.swift`, `MeView.swift`, `ManualsPage.swift`, `SettingsView.swift`, `OnboardingFlowView.swift`, `OnboardingStoriesView.swift`, `PayGateView.swift`, `HandoffProtectionView.swift`, `LoginView.swift`, `GenerativeCanvasView.swift`

### Views — Components (9)
- `StepBalanceCard.swift`, `DailyEnergyCard.swift`, `TariffOptionView.swift`, `StatusRow.swift`, `StatMiniCard.swift`, `AppSelectionComponents.swift`, `ShieldRowView.swift`, `TimeAccessPickerSheet.swift`, `ImagePicker.swift`

### Views — Secondary (10)
- `RadialHoldMenu.swift`, `ColorPaletteView.swift`, `CategoryDetailView.swift`, `CategorySettingsView.swift`, `EnergySetupView.swift`, `OptionEntrySheet.swift`, `CustomActivityEditorView.swift`, `ShieldGroupSettingsView.swift`, `ProfileEditorView.swift`, `DayEndSettingsView.swift`

### Utilities (7)
- `SharedKeys.swift`, `UserDefaults+StepsTrader.swift`, `DayBoundary.swift`, `Date+Today.swift`, `ColorConstants.swift`, `Font+Custom.swift`, `AppLogger.swift`

### Extensions (4 targets)
- `DeviceActivityMonitorExtension.swift`
- `ShieldActionExtension.swift`
- `ShieldConfigurationExtension.swift`
- `ProofLockScreenWidget.swift`

### Tests
- 5 unit test files (BudgetEngine, DailyEnergy, MinuteCharge, CustomActivity, DayBoundary)
- 2 UI test files

---

*Last updated: February 15, 2026. Based on full codebase analysis (102 Swift files, 7 targets, 570-line design system). All claims verified against actual code.*
