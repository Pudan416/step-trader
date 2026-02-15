# Proof — Code Audit & Strategy-Aligned Fix Plan

> Produced by three sub-agents (Senior Swift/iOS Engineer, Senior Backend Engineer, Senior Product/Systems Analyst) operating through a strategy-first lens after fully internalizing `PROJECT_STRATEGY.md` and `design.json`.

---

## 🎯 STRATEGY ALIGNMENT SUMMARY

**Core Value**: Your life is a daily exhibition. You curate it with every choice. Screen time is what you trade to leave your own gallery and enter someone else's.

**Target Personas**: Intentional living (25–35), Quantified self (22–35), Creative/philosophical (20–30)

**Key KPIs**: D7 retention > 20%, beta users explain app in one sentence, premium conversion > 2%, >500 installs from launch

**Vocabulary Contract**: experience (not EXP/balance/energy), pieces (not activities/selections), rooms — body/mind/heart (not Move/Reboot/Joy), tickets (not shields), spend (not pay/deduct), archive (not history/memories)

**Tone**: Gallery wall text. Observational. Brief. No exclamation marks. No motivational language. No punishment language.

**This Audit Ensures**: Every line of user-facing code matches the strategic "best outcome" vision. Technical debt that blocks beta launch is identified and prioritized.

---

## 📋 CURRENT ARCHITECTURE vs STRATEGY

| Strategic Goal | Current State | Gap | Priority |
|---|---|---|---|
| App name = "Proof" | Code says "DOOM CTRL", "Steps4", "StepsTrader" everywhere | **Critical** — brand identity doesn't exist in code | P0 |
| Vocabulary = "experience" | StepBalanceCard shows "EXP"; variables use `steps`, `balance` | **Critical** — contradicts one-word-per-concept rule | P0 |
| Three rooms = body / mind / heart | UI shows "My activities / My creativity / My joys" | **Critical** — core metaphor absent from UI | P0 |
| Shield copy = gallery tone | Extension shows "⚡ BLOCKED" + "DOOM CTRL" | **Critical** — directly anti-strategic (punishment language) | P0 |
| English-only for v1 | All UI strings wrapped in `loc(appLanguage, ...)` with RU branches | **Critical** — dead code, maintenance drag, blocks vocabulary pass | P0 |
| PayGate = "keep it closed" | Code says "Keep it locked" | **High** — punishment framing | P1 |
| Gallery = conceptual center | Gallery is tab index 1; Tickets is default tab 0 | **High** — gallery buried behind tickets | P1 |
| Guides tab = philosophy wall texts | ManualsPage is empty VStack | **High** — missed opportunity, strategic feature | P1 |
| Piece names = action phrases | "Dancing", "Curiosity", "Cringe" (nouns) | **High** — should be "dancing it out", "following my curiosity" | P1 |
| Onboarding = 7 gallery-first slides | 13+ slides, permissions-first | **High** — onboarding completion rate at risk | P2 |
| Weekly reflection card | Not built | **Medium** — Week 3 deliverable | P2 |
| Lock Screen widget | Not built | **Medium** — biggest retention driver per strategy | P2 |
| Rest day override | Not built | **Medium** — Week 3 deliverable | P2 |
| SharedKeys.swift | Doesn't exist; 50+ raw string keys | **High** — extension/app drift risk, crash potential | P1 |

---

## 🔍 WEAK SPOTS BY DOMAIN (Strategy-Impacting Only)

### 1. Swift/iOS Issues (Agent 1)

| ID | File:Line | Issue | Strategy Impact | Fix |
|---|---|---|---|---|
| **S1** ✅ | `AppModel.swift:719` | Notification title = `"🚶‍♂️ DOOM CTRL"` and body uses motivational language | — | **DONE** — Replaced with "Proof" / "Your exhibition is still open." |
| **S2** ✅ | `AppModel.swift:760` | Periodic notification = `"⏰ DOOM CTRL"` / unlock reminder | — | **DONE** — Replaced with "Proof" / "You have experience to earn." |
| **S3** ✅ | `StepBalanceCard.swift:68` | Header label = `"EXP"` | — | **DONE** — Changed to "experience" (lowercase, .medium weight, 0.3 tracking). |
| **S4** ✅ | `StepBalanceCard.swift:175-196` | Category chips show SF Symbols only (figure.run / sparkles / heart.fill) with no text labels | — | **DONE** — Added text labels "body", "mind", "heart" alongside icons in `compactCategoryChip`; chips now read body · mind · heart explicitly. |
| **S5** ✅ | `ChoiceView.swift:278-283` | Gallery section headers = `"My activities"` / `"My creativity"` / `"My joys"` | — | **DONE** — `categoryTitle` updated to `"my body"` / `"my mind"` / `"my heart"` in gallery sections. |
| **S6** ✅ | `PayGateView.swift:204` | Close button = `"Keep it locked"` | — | **DONE** — Button copy changed to `"keep it closed"` (choice framing, no punishment language). |
| **S7** ✅ | `PayGateView.swift:85-87` | Header shows `bolt.fill` icon next to balance | — | **DONE** — Removed bolt icon; header shows balance number only in capsule. |
| **S8** ✅ | `PayGateView.swift:117` | Title = `"Spend experience"` (capitalized) | — | **DONE** — Changed to lowercase `"spend experience"`. |
| **S9** ✅ | `PayGateView.swift:261-265` | Unlock labels / cost format | — | **DONE** — Time labels "10 min" / "30 min" / "1 hour"; cost shown as "· N experience" (bolt removed from unlock buttons). |
| **S10** ✅ | `ShieldConfigurationExtension.swift:88-89` | Shield showed "⚡ BLOCKED" + punishment copy | — | **DONE** — Rewritten to "[app] is closed." / "Open Proof to spend experience." / "Open". Bolt fallback icon → shield.fill. |
| **S11** ✅ | `ShieldConfigurationExtension.swift:95-106` | Second state: "👆 CHECK ABOVE" + "Open DOOM CTRL app" | — | **DONE** — "Check your notifications." / "A notification is waiting. Or open Proof directly." / "Open Proof". Same for webDomain. |
| **S12** ✅ | `ShieldActionExtension.swift:131-133` | Notification = "DOOM CTRL" / "Tap to choose unlock time." | — | **DONE** — "Proof" / "This app is closed. Tap to spend experience." |
| **S13** ✅ | `ManualsPage.swift:11` | Guides tab = empty `VStack {}` | Strategy calls this "where the philosophy lives" — 5 wall texts planned. Blocks beta messaging. | Implement with at least 3 entries ("On proof", "On the three rooms", "On the threshold") |
| **S14** ✅ | `DailyEnergy.swift:112-147` | Option titles are nouns: "Dancing", "Meal", "Curiosity", "Cringe", "Embrace" | Strategy: action phrases — "dancing it out", "eating a real meal", "following my curiosity", "embracing the cringe", "holding someone close" | Update all `titleEn` values |
| **S15** ✅ | `DailyEnergy.swift:145` | Typo: `"joysl_junkfood"` (extra 'l') | Asset mismatch risk, data corruption for users who select it | Rename to `"joys_junkfood"` with migration |
| **S16** ✅ | `AppModel.swift:65-180` | 65+ forwarding computed properties from AppModel → 3 stores | — | **DONE** — Migrated UI call sites to direct store access (`model.healthStore`, `model.blockingStore`, `model.userEconomyStore`) across core screens (`MainTabView`, `GalleryView`, ticket/paygate/settings surfaces, quick status, handoff). AppModel forwarding remains as compatibility shim while UI no longer depends on it. |
| **S17** ✅ | `MainTabView.swift:11-47` | Tab order: tickets(0), gallery(1), me(2), guides(3), settings(4) | Strategy says gallery IS the product. It should be the default tab, or at minimum more prominent | Move gallery to tab 0, or set `selection` default to 1 |
| **S18** ✅ | `MainTabView.swift:64` | Balance card params use `movePoints`, `rebootPoints`, `joyPoints` | Variable names contradict vocabulary. Should be `bodyPoints`, `mindPoints`, `heartPoints` | Rename parameters |
| **S19** ✅ | `AppsPageSimplified.swift:229` | Empty state: `"Create your first ticket to collect experience"` | "Collect" is gamification-adjacent. Strategy empty state template: `"[What's absent]. [Neutral observation]. [Action]. Or not."` | Rewrite: `"No tickets yet. Create one when you're ready."` |
| **S20** ✅ | `AppsPageSimplified.swift:386-404` | Ticket front shows `bolt.fill` icon for experience cost | Strategy: no lightning bolts throughout | Remove bolt icons, show just the number or use the word "experience" |
| **S21** ✅ | All files using `loc()` | Every user-facing string wrapped in `loc(appLanguage, en, ru)` with Russian branches | v1 is English-only. `loc()` wrappers are dead weight, make vocabulary pass harder, and obscure actual copy in code review | ~~Strip all `loc()` calls — replace with plain English strings. Delete `loc()` helper function, remove `appLanguage` property/toggle from Settings.~~ **DONE** — all `loc()` calls stripped, `Localization.swift` emptied, `@AppStorage("appLanguage")` removed from all views, all `appLanguage == "ru"` branches eliminated. |

### 2. Backend/API Issues (Agent 2)

| ID | Location | Issue | Strategy Impact | Fix |
|---|---|---|---|---|
| **B1** ✅ | Entire codebase | 50+ raw UserDefaults string keys scattered across app + 3 extensions with no shared schema | — | **DONE** — `SharedKeys.swift` created in StepsTrader/Utilities with full enum, added to app + ShieldAction + ShieldConfiguration + DeviceActivityMonitor targets. UserDefaults+StepsTrader and all three extensions use SharedKeys for app group and shared state keys. |
| **B2** ✅ | `AppModel.swift:481-484` | `deleteSupabaseTicket()` was a stub/TODO | — | **DONE** — Implemented real delete path via `SupabaseSyncService.deleteTicket(bundleId:)` that removes current user's row from `shields` (`user_id` + `bundle_id`) using authenticated Supabase REST call. |
| **B3** ✅ | `DeviceActivityMonitorExtension.swift:87-94` | Extension duplicates `stepsTraderDefaults()` function locally instead of sharing | — | **DONE** — Centralized App Group defaults access in `SharedKeys.appGroupDefaults()` and replaced all local `stepsTraderDefaults()` usage in `DeviceActivityMonitorExtension`. |
| **B4** ✅ | `SupabaseSyncService.swift` | Daily selections sync worked but ticket group sync was TODO | — | **DONE** — Implemented debounced `syncTicketGroups(_:)` in `SupabaseSyncService` (delete+reinsert `group:*` rows in `shields`) and wired calls from ticket-group mutations in `AppModel+TicketGroups`. |
| **B5** ✅ | `SupabaseSyncService.swift` + call sites | No analytics tracking for strategic KPIs (D7 retention, onboarding completion, gallery engagement) | — | **DONE** — Added queued analytics pipeline (`trackAnalyticsEvent`) with Supabase flush to `user_analytics_events`, and wired required events: `onboarding_completed` (`OnboardingFlowView`), `piece_selected` (`AppModel+DailyEnergy`), `experience_spent` (`AppModel+Payment`), `gallery_viewed` (`GalleryView`), `ticket_created` (`AppModel+TicketGroups`). |
| **B6** ✅ | `DeviceActivityMonitorExtension.swift:96-105` | Monitor log retains up to 200 string entries in UserDefaults | App Group storage bloat risk (extensions have tight memory limits) | Reduce to 50 entries or move to file-based logging |
| **B7** ✅ | `PastDaySnapshot.swift:7-9` | Snapshot uses `controlGained` / `controlSpent` | Vocabulary violation — should be `experienceEarned` / `experienceSpent`. Affects Supabase schema and historical data. | Rename with backward-compat decoding (add new coding keys, keep old ones for reading) |

### 3. Product/UX Gaps (Agent 3)

| ID | Strategic Goal | Current Gap | User Impact | Fix Plan |
|---|---|---|---|---|
| **P1** ✅ | App identity = "Proof" | Bundle display name = "Steps4", all internal references = "DOOM CTRL" / "StepsTrader" | Beta testers can't identify the product. Word-of-mouth impossible. | Update display name in Info.plist, all user-facing strings |
| **P2** ✅ | Gallery = soul of product | Gallery was not the conceptual center in tab order/navigation | — | **DONE** — Reordered `MainTabView` so gallery is tab `0` and default selection, moved tickets to tab `1`, and replaced hardcoded tab indices with `Tab.*.rawValue` for robust routing. |
| **P3** ✅ | Onboarding = 7 slides, gallery-first | Previous onboarding path had extra intro/login/permission/profile phases and 13+ interactions | — | **DONE** — Rewrote `OnboardingFlowView` into a single 7-slide flow with gallery-first ordering (joys first), collapsed multi-phase onboarding into one sequence, and moved permission prompts to a single post-onboarding request step. |
| **P4** ✅ | Weekly reflection | Not implemented | — | **DONE** — Added `WeeklyReflectionCard` in `MeView` using last-7-day snapshots to show weekly earned/spent/kept experience and strongest room, with an interpretive headline ("Strong/Balanced/Expensive week"). |
| **P5** ✅ | Lock Screen widget | — | — | **DONE** — Added `ProofLockScreenWidget` WidgetKit extension with Lock Screen accessory families (inline/circular/rectangular) that read current experience from App Group UserDefaults (`stepsBalance`) and refresh timeline every 15 minutes. |
| **P6** ✅ | Rest day override | Not implemented | — | **DONE** — Added a user-facing "Rest day override" toggle in `SettingsView` persisted via `SharedKeys.restDayOverrideEnabled`; when enabled, daily base energy is floored to 30 EXP in `recalculateDailyEnergy()`. |
| **P7** ✅ | Difficulty labels = gamification | "Rookie / Rebel / Fighter / Warrior / Legend" | — | **DONE** — Replaced gamified difficulty labels with neutral numeric labels (`Level 1` … `Level 5`) across ticket list/detail and shield group settings views. |
| **P8** ✅ | Privacy manifest | Not present | App Store requirement. Blocks public launch (Phase 3). | **DONE** — Added `PrivacyInfo.xcprivacy` to main app target (`Steps4`) with NSPrivacyAccessedAPITypes: UserDefaults CA92.1 and tracking explicitly set to false. |
| **P9** ✅ | README contradicts code | README claimed "ManagedSettings shield blocking was removed" while shielding is active in code | — | **DONE** — Rewrote `README.md` to match current behavior (Proof branding, active ManagedSettings/Shield extensions, accurate target/capability notes). |
| **P10** ✅ | `joys_money` in heart room | "Money" was listed under joys/heart though strategy places it in mind | — | **DONE** — Removed `joys_money` from joys defaults, kept `creativity_doing_cash` ("making money happen") in mind, and added migration that moves legacy `joys_money` IDs in daily/preferred/snapshot data to mind. |

---

## 🚀 2-WEEK STRATEGY EXECUTION PLAN

### Week 1: Strategy Blockers (Critical Path to Beta)

```
Day 1-2: Identity & Vocabulary Pass
  ✅ S21: Strip ALL loc() wrappers → plain English strings (DO THIS FIRST — unblocks every other string change)
  ✅ S21: Delete loc() helper, remove appLanguage property & Settings toggle
  ✅ **S1, S2, S12: Replace all "DOOM CTRL" with "Proof" in notifications** — DONE (AppModel, NotificationManager, ShieldActionExtension; gallery-toned bodies)
  ✅ **S3: StepBalanceCard "EXP" → "experience"** — DONE
  ✅ **S10, S11: Shield copy rewrite** — DONE (blocked + waitingPush; app + webDomain; bolt fallback → shield.fill)
  ✅ S5: Gallery headers "My activities/creativity/joys" → "my body/mind/heart"
  ✅ S6: PayGate "Keep it locked" → "keep it closed"
  ✅ S14: Update all option titleEn to action phrases
  ✅ S15: Fix "joysl_junkfood" typo
  ✅ P1: Update app display name to "Proof"
  ⏱️ ~10 engineering hours

Day 3-4: Shield & PayGate Rewrite
  ✅ S10, S11: Rewrite ShieldConfigurationExtension copy entirely
  ✅ S7, S8, S9: Remove bolt.fill from PayGate header; lowercase "spend experience"; unlock cost as "· N experience" (no bolt) — DONE
  ✅ B7: Rename controlGained/controlSpent → experienceEarned/experienceSpent — DONE
  ⏱️ ~6 engineering hours

Day 5: Architecture & Keys
  ✅ B1: Create SharedKeys.swift with all UserDefaults keys — DONE
  ✅ S18: Rename movePoints/rebootPoints/joyPoints → body/mind/heart
  ✅ S19: Fix empty state copy
  ✅ P7: Neutralize difficulty labels
  ⏱️ ~4 engineering hours

📈 Impact: Entire user-facing vocabulary matches strategy. Shield no longer screams.
   Beta testers will be able to explain "Proof" in one sentence.
```

### Week 2: Strategy Accelerators

```
Day 6-7: Gallery Elevation & Guides
  ✅ P2/S17: Make gallery the default tab
  ✅ S4: Add body/mind/heart text labels to balance card chips — DONE
  ✅ S13: Build Guides tab with 3 philosophy entries
  ⏱️ ~8 engineering hours

Day 8-9: Backend & Sync
  ✅ B2: Implement Supabase ticket deletion (`deleteSupabaseTicket` no longer stub)
  ✅ B4: Complete ticket group Supabase sync
  ✅ B5: Add basic analytics events for KPI tracking
  ✅ B6: Reduce monitor log retention — DONE
  ⏱️ ~8 engineering hours

Day 10: Polish & Ship
  ✅ P3: Simplify onboarding to 7 slides (can be incremental)
  ✅ **P8: Add privacy manifest** — DONE (PrivacyInfo.xcprivacy, UserDefaults CA92.1)
  ✅ P9: Fix README
  ✅ P10: Move joys_money to mind, rename
  ⏱️ ~6 engineering hours

📈 Impact: Gallery-first experience. Philosophy present. Backend ready for beta feedback loop.
   Enables Phase 1 beta launch (30-50 TestFlight users).
```

---

## 🔗 CROSS-AGENT DEPENDENCIES

```
Shield copy rewrite (S10/S11) requires:
  → SharedKeys.swift (B1) for shared state key
  → App name finalized (P1) for "Open Proof to spend experience"

Guides tab (S13) requires:
  → Gallery-as-default (P2) so users discover Guides naturally
  → Vocabulary pass complete so Guides text matches UI

Analytics (B5) requires:
  → Vocabulary-correct events (can't track "movePoints" if it's "body")
  → Backend Supabase schema (B4) for persistent storage

Weekly reflection (P4) requires:
  → PastDaySnapshot rename (B7) so aggregation uses correct fields
  → Supabase daily stats sync (already partially working)
```

---

## 📊 STRATEGY SUCCESS METRICS

```
Technical (post-Week 1):
  - 0 instances of "DOOM CTRL", "EXP", "BLOCKED" in user-facing strings
  - 0 `loc()` calls remaining — all strings are plain English
  - 0 Russian string literals in codebase
  - 0 lightning bolt emojis/icons in UI
  - All 3 extensions use SharedKeys.swift
  - ShieldConfiguration copy passes strategy tone check

Strategic (post-Week 2):
  - Gallery is default tab with body/mind/heart rooms labeled
  - Guides tab has ≥3 philosophy entries
  - Onboarding ≤ 7 slides
  - Beta-ready TestFlight build

Business (Week 4 checkpoint):
  - 30-50 beta testers recruited
  - Can beta users explain Proof in one sentence? (strategy checkpoint)
  - D7 retention tracking operational via analytics events
```

---

## 🔧 DETAILED CODE DIFFS FOR CRITICAL FIXES

### S3: StepBalanceCard "EXP" → "experience"

**File**: `StepsTrader/Views/Components/StepBalanceCard.swift`

```diff
- Text("EXP")
-     .font(.caption.weight(.bold))
-     .foregroundColor(accent)
-     .tracking(0.5)
+ Text("experience")
+     .font(.caption.weight(.medium))
+     .foregroundColor(accent)
+     .tracking(0.3)
```

### S5: Gallery headers → three rooms

**File**: `StepsTrader/Views/ChoiceView.swift` (CategoryCardsRow)

```diff
  private var categoryTitle: String {
      switch category {
-     case .activity: return loc(appLanguage, "My activities")   // strip loc() — English only
-     case .creativity: return loc(appLanguage, "My creativity")
-     case .joys: return loc(appLanguage, "My joys")
+     case .activity: return "my body"
+     case .creativity: return "my mind"
+     case .joys: return "my heart"
      }
  }
```

### S6: PayGate close button

**File**: `StepsTrader/Views/PayGateView.swift`

```diff
- Text(loc(appLanguage, "Keep it locked"))
+ Text("keep it closed")   // strip loc() — English only
```

### S10: Shield copy rewrite

**File**: `ShieldConfiguration/ShieldConfigurationExtension.swift`

```diff
  case .blocked:
      return baseConfiguration(
-         title: "⚡ BLOCKED",
-         subtitle: "\(appName) is under control.\nYou set the rules. Now follow them.",
-         primaryButtonText: "Pay to unlock"
+         title: "\(appName) is closed.",
+         subtitle: "Open Proof to spend experience.",
+         primaryButtonText: "Open"
      )
      
  case .waitingPush:
      return baseConfiguration(
-         title: "👆 CHECK ABOVE",
-         subtitle: """
-             ↑ ↑ ↑
-             Swipe down for notification.
-             Choose your unlock time there.
-             
-             No push? Open DOOM CTRL app
-             → find this shield → unlock manually.
-             """,
-         primaryButtonText: "Still nothing"
+         title: "Check your notifications.",
+         subtitle: "A notification is waiting.\nOr open Proof directly.",
+         primaryButtonText: "Open Proof"
      )
```

### S14: Option titles → action phrases (sample)

**File**: `StepsTrader/Models/DailyEnergy.swift`

```diff
  // Activity
- EnergyOption(id: "activity_dancing", titleEn: "Dancing", ...
- EnergyOption(id: "activity_meal", titleEn: "Meal", ...
- EnergyOption(id: "activity_overcome", titleEn: "Overcome", ...
- EnergyOption(id: "activity_risk", titleEn: "Risk", ...
- EnergyOption(id: "activity_sex", titleEn: "Sex", ...
- EnergyOption(id: "activity_sport", titleEn: "Sport", ...
- EnergyOption(id: "activity_strong", titleEn: "Strong", ...
+ EnergyOption(id: "activity_dancing", titleEn: "dancing it out", ...
+ EnergyOption(id: "activity_meal", titleEn: "eating a real meal", ...
+ EnergyOption(id: "activity_overcome", titleEn: "overcoming something hard", ...
+ EnergyOption(id: "activity_risk", titleEn: "taking a real risk", ...
+ EnergyOption(id: "activity_sex", titleEn: "making love", ...
+ EnergyOption(id: "activity_sport", titleEn: "pushing my limits", ...
+ EnergyOption(id: "activity_strong", titleEn: "feeling my strength", ...
  
  // Creativity
- EnergyOption(id: "creativity_curiosity", titleEn: "Curiosity", ...
- EnergyOption(id: "creativity_doing_cash", titleEn: "Cash doing", ...
- EnergyOption(id: "creativity_fantasizing", titleEn: "Fantasizing", ...
- EnergyOption(id: "creativity_general", titleEn: "General", ...
- EnergyOption(id: "creativity_invisible", titleEn: "Invisible", ...
- EnergyOption(id: "creativity_museum", titleEn: "Museum", ...
- EnergyOption(id: "creativity_observe", titleEn: "Observe", ...
+ EnergyOption(id: "creativity_curiosity", titleEn: "following my curiosity", ...
+ EnergyOption(id: "creativity_doing_cash", titleEn: "making money happen", ...
+ EnergyOption(id: "creativity_fantasizing", titleEn: "letting my mind wander", ...
+ EnergyOption(id: "creativity_general", titleEn: "creating something new", ...
+ EnergyOption(id: "creativity_invisible", titleEn: "noticing the invisible", ...
+ EnergyOption(id: "creativity_museum", titleEn: "visiting a real place", ...
+ EnergyOption(id: "creativity_observe", titleEn: "watching the world closely", ...
  
  // Joys
- EnergyOption(id: "joys_cringe", titleEn: "Cringe", ...
- EnergyOption(id: "joys_embrase", titleEn: "Embrace", ...
- EnergyOption(id: "joys_emotional", titleEn: "Emotional", ...
- EnergyOption(id: "joys_friends", titleEn: "Friends", ...
- EnergyOption(id: "joys_happy_tears", titleEn: "Happy tears", ...
- EnergyOption(id: "joys_in_love", titleEn: "In love", ...
- EnergyOption(id: "joys_kiss", titleEn: "Kiss", ...
- EnergyOption(id: "joys_love_myself", titleEn: "Love myself", ...
- EnergyOption(id: "joys_rebel", titleEn: "Rebel", ...
- EnergyOption(id: "joys_range", titleEn: "Range", ...
- EnergyOption(id: "joysl_junkfood", titleEn: "Junk food", ...
+ EnergyOption(id: "joys_cringe", titleEn: "embracing the cringe", ...
+ EnergyOption(id: "joys_embrase", titleEn: "holding someone close", ...
+ EnergyOption(id: "joys_emotional", titleEn: "feeling deeply today", ...
+ EnergyOption(id: "joys_friends", titleEn: "being with my people", ...
+ EnergyOption(id: "joys_happy_tears", titleEn: "crying from joy", ...
+ EnergyOption(id: "joys_in_love", titleEn: "feeling in love", ...
+ EnergyOption(id: "joys_kiss", titleEn: "kissing someone", ...
+ EnergyOption(id: "joys_love_myself", titleEn: "choosing myself today", ...
+ EnergyOption(id: "joys_rebel", titleEn: "breaking my rules", ...
+ EnergyOption(id: "joys_range", titleEn: "going all out", ...
+ EnergyOption(id: "joys_junkfood", titleEn: "guilty pleasures", ...
```

### S1/S2: Notification copy

**File**: `StepsTrader/AppModel.swift`

```diff
  private func scheduleReturnNotification() {
      let content = UNMutableNotificationContent()
-     content.title = "🚶‍♂️ DOOM CTRL"
-     content.body = "Walk more steps to earn extra entertainment time!"
+     content.title = "Proof"
+     content.body = "Your exhibition is still open."
      content.sound = .default
      ...
-         title: "Open DOOM CTRL",
+         title: "Open Proof",
      ...
  }

  func schedulePeriodicNotifications() {
      ...
-     content.title = "⏰ DOOM CTRL"
-     content.body = "Reminder: walk more steps to unlock!"
+     content.title = "Proof"
+     content.body = "You have experience to earn."
      ...
  }
```

### B1: SharedKeys.swift (new file needed)

```swift
// SharedKeys.swift — shared across app + 3 extensions
// Single source of truth for all UserDefaults keys.

import Foundation

enum SharedKeys {
    static let appGroupId = "group.personal-project.StepsTrader"
    
    // MARK: - Day boundary
    static let dayEndHour = "dayEndHour_v1"
    static let dayEndMinute = "dayEndMinute_v1"
    
    // MARK: - Energy
    static let dailyEnergyAnchor = "dailyEnergyAnchor_v1"
    static let dailySleepHours = "dailySleepHours_v1"
    static let baseEnergyToday = "baseEnergyToday_v1"
    static let stepsBalance = "stepsBalance"
    static let spentStepsToday = "spentStepsToday"
    static let bonusSteps = "debugStepsBonus_v1"
    static let cachedStepsToday = "cachedStepsToday"
    
    // MARK: - Ticket groups
    static let ticketGroups = "ticketGroups_v1"
    static let legacyShieldGroups = "shieldGroups_v1"
    static let liteTicketConfig = "liteTicketConfig_v1"
    static let appUnlockSettings = "appUnlockSettings_v1"
    
    // MARK: - Shield state
    static let shieldState = "doomShieldState_v1"
    static let lastBlockedAppBundleId = "lastBlockedAppBundleId"
    static let lastBlockedGroupId = "lastBlockedGroupId"
    
    // MARK: - PayGate
    static let shouldShowPayGate = "shouldShowPayGate"
    static let payGateTargetGroupId = "payGateTargetGroupId"
    static let payGateTargetBundleId = "payGateTargetBundleId_v1"
    static let payGateDismissedUntil = "payGateDismissedUntil_v1"
    
    // MARK: - Spend tracking
    static let appStepsSpentToday = "appStepsSpentToday_v1"
    static let appStepsSpentLifetime = "appStepsSpentLifetime_v1"
    static let appStepsSpentByDay = "appStepsSpentByDay_v1"
    static let minuteChargeLogs = "minuteChargeLogs_v1"
    static let minuteTimeByDay = "minuteTimeByDay_v1"
    
    // MARK: - Selections
    static let appSelection = "appSelection_v1"
    static let customEnergyOptions = "customEnergyOptions_v1"
    static let pastDaySnapshots = "pastDaySnapshots_v1"
    static let dailyGallerySlots = "dailyChoiceSlots_v1"
    
    // MARK: - Monitor
    static let monitorLogs = "monitorLogs_v1"
    static let monitorErrorLogs = "monitorErrorLogs_v1"
    static let monitorErrorCount = "monitorErrorCount_v1"
    
    // MARK: - Helpers
    static func groupUnlockKey(_ groupId: String) -> String { "groupUnlock_\(groupId)" }
    static func blockUntilKey(_ bundleId: String) -> String { "blockUntil_\(bundleId)" }
    static func timeAccessSelectionKey(_ bundleId: String) -> String { "timeAccessSelection_v1_\(bundleId)" }
    static func dailySelectionsKey(_ category: String) -> String { "dailyEnergySelections_v1_\(category)" }
    static func preferredOptionsKey(_ category: String) -> String { "preferredEnergyOptions_v1_\(category)" }
    static func minuteCountKey(dayKey: String, bundleId: String) -> String { "minuteCount_\(dayKey)_\(bundleId)" }
}
```

---

## 🎯 NEXT STEPS (Strategy-Aligned)

```
1. Implement Week 1 fixes (vocabulary + shield + identity)
   → Test: grep codebase for "DOOM", "EXP", "BLOCKED", "bolt.fill"
   → Target: zero hits in user-facing strings

2. Implement Week 2 fixes (gallery elevation + Guides + backend)
   → Test: launch app, confirm gallery is default tab, Guides has content
   → Test: Supabase receives ticket group sync data

3. Build TestFlight (Week 4)
   → Recruit 30-50 beta testers
   → Run positioning test: "Life earns screen time" vs "Your day is an exhibition"
   → Begin D7 retention tracking

4. Schedule Phase 2 technical prep (Month 2)
   → Weekly reflection card
   → ✅ Lock Screen widget  
   → Rest day override
   → Onboarding A/B test
```

---

## 🧹 CODE CLEANUP & OPTIMIZATION

### Architecture: AppModel God Object

The single biggest technical debt item. `AppModel.swift` is 900+ lines in the main file plus **8 extension files** (`+DailyEnergy`, `+PayGate`, `+Payment`, `+HealthKit`, `+BudgetTracking`, `+TicketGroups`, `+AppSettings`, `+AccessWindow`). It forwards **65+ computed properties** to three stores (`HealthStore`, `BlockingStore`, `UserEconomyStore`), creating a massive passthrough layer that adds zero value and drifts constantly.

| ID | Issue | Impact | Fix |
|---|---|---|---|
| **C1** | AppModel forwards 65+ properties (lines 66–183) | Every store property change triggers AppModel → views. Adds indirection, hides ownership, creates stale-data bugs. | **Phase 1**: Stop adding new forwarders. **Phase 2**: Views access `model.healthStore.stepsToday` directly. Remove forwarding props one screen at a time. |
| **C2** | AppModel+TicketGroups is pure delegation (74 lines, every method is `blockingStore.xxx()`) | Dead indirection layer. | Delete file. Views call `model.blockingStore.createTicketGroup()` directly. |
| **C3** ✅ | AppModel+HealthKit has a `fetchSleepForCurrentDay()` that returns `0` with comment "Placeholder" | Dead code, misleading API. | **DONE** — Deleted the method. |
| **C4** ✅ | AppModel+HealthKit `startStepObservation()` has 20 lines of self-debating comments about how to observe steps | Comments-as-code, no actual logic beyond `healthStore.startObservingSteps()`. | **DONE** — Replaced with one-liner `healthStore.startObservingSteps()`. |

### Dead Code & Legacy Files

| ID | File | Evidence | Action |
|---|---|---|---|
| **C5** ✅ | `Views/AppsPage.swift` | `AppsPageSimplified.swift` replaced it. Not referenced in `MainTabView`. | **DONE** — Removed from project and deleted file. MainTabView uses AppsPageSimplified only. |
| **C6** ✅ | `Views/BlockScreen.swift` + `Views/BlockScreenNew.swift` | Two block screen implementations. Shield system replaced both. Neither referenced in main navigation. | **DONE** — Removed both from project and deleted files. Shield config + PayGate handle blocking UX. |
| **C7** ✅ | `AppModel.swift:59-62` | `rebuildShieldTask` getter returns `nil`, setter is no-op. Comment says "Deprecated/Moved to BlockingStore". | **DONE** — Deleted the property. |
| **C8** ✅ | `AppModel.swift:220` | `spentStepsToday` in AppModel — also exists in UserEconomyStore as `spentSteps`. Comment: "Legacy? Or duplicate of spentSteps?" | **DONE** — Single source: `UserEconomyStore.spentSteps`; AppModel.`spentStepsToday` is a forwarder. Store persists via `didSet` to `SharedKeys.spentStepsToday`; removed duplicate `g.set` from Payment/DailyEnergy. |
| **C9** ✅ | `Models/AutomationUIModels.swift` + `Views/AutomationGuideView.swift` | Automation shortcut setup UI — not in strategic MVP. | **DONE** — Gated `AutomationGuideView` behind `#if DEBUG` (AutomationUIModels kept; used by SettingsView). |
| **C10** ✅ | `Models/StatusViewModels.swift` + `Utilities/StatusViewHelpers.swift` + `Views/QuickStatusView.swift` | Debug/diagnostic status views. Not user-facing. | **DONE** — All three gated behind `#if DEBUG`; StepsTraderApp shows MainTabView when showQuickStatusPage in Release. |
| **C11** ✅ | Entire budget/minute-mode timer system in `AppModel+BudgetTracking.swift` | Strategy says "Disable minute mode in v1 UI." Lines 188–371 implement timer fallback, minute tariff sessions, simulated usage. | **DONE** — Added `static let minuteModeEnabled = false`. `isMinuteTariffEnabled`/`setMinuteTariffEnabled`/`minutesAvailable` gated; ShieldRowView `isActive` uses flag so minute-only groups don't show active when off. |

### Excessive & Uncontrolled Logging

The codebase has **200+ `print()` statements** with emoji prefixes (`🔍`, `💰`, `💳`, `⚡️`, `🔓`, `🛡️`, `📱`, etc.). These:
- Ship to production (no `#if DEBUG` gates)
- Expose internal state in device Console (security risk for beta)
- Make actual errors impossible to find in log noise

| ID | Scope | Count (approx) | Fix |
|---|---|---|---|
| **C12** ✅ | `AppModel.swift` + extensions | ~80 print statements | **DONE** — Replaced with `AppLogger` by category (app, shield, energy, healthKit, network, familyControls). |
| **C13** ✅ | `AppModel+Payment.swift` | 25+ prints with `💳` prefix, including balance details | **DONE** — Replaced with `AppLogger.payment`; balance/cost details gated behind `#if DEBUG`. |
| **C14** ✅ | `StepsTraderApp.swift` | 20+ prints on every app lifecycle event | **DONE** — Replaced with `AppLogger.app.debug()`. |
| **C15** ✅ | `DeviceActivityMonitorExtension.swift` | Has proper `MonitorLogger` using `os_log` | **DONE** — Main app now uses `AppLogger` (OSLog) throughout; pattern replicated. |

### Deprecated API Usage

| ID | Location | Issue | Fix |
|---|---|---|---|
| **C16** ✅ | `AppModel+Payment.swift:111`, `:232` | `UserDefaults.synchronize()` — deprecated since iOS 12, Apple docs: "unnecessary and shouldn't be used" | Delete all `.synchronize()` calls. iOS handles persistence automatically. |
| **C17** ✅ | `AppModel.swift:564-575` | `DispatchQueue.main.async` inside `@MainActor` class with `UIApplication.shared.open` completion handler | **DONE** — Refactored `attemptOpen` to `async -> Bool` using `await UIApplication.shared.open(url, options: [:])`; `handleBlockedRedirect()` calls it via `Task { _ = await attemptOpen(...) }`. |

### Redundant `objectWillChange.send()`

Multiple methods call `objectWillChange.send()` manually even though `@Published` properties already trigger it. Some call it **2-3 times in sequence** with `Task.sleep` between (hoping SwiftUI "catches" the update).

| ID | File:Line | Pattern | Fix |
|---|---|---|---|
| **C18** ✅ | `AppModel+PayGate.swift:84-95` | Two `objectWillChange.send()` with 200ms sleep between them | Remove both. The `@Published` property changes (`showPayGate`, `payGateTargetGroupId`) already trigger updates. |
| **C19** ✅ | `AppModel+Payment.swift:42,71,117` | `objectWillChange.send()` after every property mutation | Remove. `stepsBalance`, `bonusSteps`, `spentStepsToday` are all `@Published` or forward to `@Published` stores. |
| **C20** ✅ | `AppModel+PayGate.swift:131` | 200ms sleep "to ensure UI has updated" before dismissing PayGate | Remove the sleep. Use proper SwiftUI state flow — dismiss triggers on the next render cycle automatically. |

### Inconsistent Concurrency Patterns

The codebase mixes three async patterns unpredictably:

```
Pattern A: Task { @MainActor in ... }
Pattern B: DispatchQueue.main.async { ... }
Pattern C: await MainActor.run { ... }
```

| ID | Issue | Fix |
|---|---|---|
| **C21** ✅ | `AppModel.swift:707-710` — `DispatchQueue.main.asyncAfter` for notification scheduling inside `@MainActor` class | Use `Task { try await Task.sleep(...); ... }` |
| **C22** ✅ | `AppModel+BudgetTracking.swift:240-255` — `Task { [weak self] in ... await MainActor.run { ... } }` nested inside `@MainActor` method | Already on MainActor — remove the nesting. Just `await` directly. |
| **C23** ✅ | `StepsTraderApp.swift:132-138` — `while !Task.isCancelled { try? await Task.sleep(...) }` polling loop for cleanup | Works but fragile. Consider `Timer.publish` or a proper background task scheduler. |

### UserDefaults as Database

Several large data structures are stored in `UserDefaults` (App Group), which Apple recommends for "small amounts of data" (preferences, flags). This risks:
- Slow reads on app launch (all keys loaded into memory)
- Extension memory limits exceeded
- Data corruption on concurrent writes from app + extension

| ID | Data | Current Size | Fix |
|---|---|---|---|
| **C24** ✅ | `paymentTransactions_v1` | Up to 1000 `PaymentTransaction` objects | **DONE** — PersistenceManager.paymentTransactionsFileURL; logPaymentTransaction reads/writes JSON file, migrates from UD on first load. |
| **C25** ✅ | `pastDaySnapshots_v1` | Unbounded — grows by 1 entry/day, never pruned | **DONE** — PersistenceManager.pastDaySnapshotsFileURL; load/save use file, migrate from UD; prunePastDaySnapshotsToRetention keeps last 90 days. |
| **C26** ✅ | `monitorLogs_v1` | 200 string entries in extension's UserDefaults | **DONE** — Cap reduced to 30 for both monitorLogs and monitorErrorLogs in DeviceActivityMonitorExtension. |
| **C27** ✅ | `minuteChargeLogs_v1` | 100 entries in extension, also read by app | **DONE** — Single source: shared file `SharedKeys.minuteChargeLogsFileURL()` (App Group). UserEconomyStore loads/saves that file; extension reads/writes same file. Migration from UD/old persistence on first load. |

### Russian Language Cleanup (Comments + UI Strings)

**Russian comments** ✅: **DONE** — All ~100+ Russian comments translated to English across 27 files (AppModel + extensions, Views, Models, Services, DeviceActivityMonitor, ShieldAction). Also translated Russian return values in `Types.swift` and `PayGateBackgroundStyle.swift`. Only `titleRu` data fields in `DailyEnergy.swift` remain (intentional localization data, not comments).

**Fix**: ~~Translate all comments to English in a single pass. Grep-and-replace — doesn't affect logic.~~ DONE.

**Russian UI strings (S21)**: Every user-facing string is wrapped in `loc(appLanguage, englishString, russianString)`. v1 is English-only. This means:

1. Replace every `loc(appLanguage, "english text", "russian text")` call with just `"english text"` (or the new strategic copy).
2. Delete the `loc()` helper function entirely.
3. Remove the `appLanguage` property from AppModel and the language toggle from Settings.
4. Delete all Russian string literals.

This is a mechanical pass but touches many files. Best done as the **first step** of the vocabulary fix — strip `loc()` first, then update the now-plain English strings to match strategy. Doing both in one pass avoids double-touching every string.

### Fragile String Matching

| ID | File | Issue | Fix |
|---|---|---|---|
| **C28** ✅ | `AppModel+TicketGroups.swift:57-62` | `findTicketGroup` does case-insensitive **substring** matching (`bundleIdLower.contains(storedNameLower)`) to match apps to groups | **DONE** — ShieldConfiguration now stores `fc_bundleId_` per token; findTicketGroup prefers exact bundleId match, legacy path uses exact match only (no substring). |
| **C29** ✅ | `AppModel.swift:515-549` | `primaryAndFallbackSchemes` hardcodes URL schemes for 12 apps | **DONE** — Moved to `TargetResolver.primaryAndFallbackSchemes(for:)`; AppModel calls it for redirect. |

### Internal Naming vs Strategy Vocabulary

All internal variable names still use "steps" vocabulary. While not user-facing, this creates constant cognitive dissonance when working on the codebase:

| Current | Should Be | Scope |
|---|---|---|
| `stepsBalance` | `experienceBalance` | UserEconomyStore, AppModel, extensions |
| `spentSteps` / `spentStepsToday` | `experienceSpent` / `experienceSpentToday` | Everywhere |
| `bonusSteps` | `bonusExperience` | Everywhere |
| `totalStepsBalance` | `totalExperience` | Everywhere |
| `appStepsSpentToday` | `appExperienceSpentToday` | UserEconomyStore |
| `healthKitSteps` | Keep as-is | HealthKit is literally steps — this is correct |
| `baseEnergyToday` | `experienceEarnedToday` | HealthStore, AppModel |
| `movePoints` / `rebootPoints` / `joyPoints` | `bodyPoints` / `mindPoints` / `heartPoints` | StepBalanceCard, MainTabView |

**Recommendation**: Do this rename in a dedicated PR after all user-facing changes land. It's a large diff but mechanical (find-replace with compile checks). Don't mix with feature work.

### Unused Imports

Quick scan shows several files importing modules they don't use:

| ID | File | Unused Import | Fix |
|---|---|---|---|
| **Unused** ✅ | `AppModel.swift` | `AVFoundation`, `AudioToolbox` (only used in BudgetTracking extension) | **DONE** — Removed both. |
| **Unused** ✅ | `AppModel+BudgetTracking.swift` | `Combine` (not used in this extension) | **DONE** — Removed. |
| **Unused** ✅ | `StepsTraderApp.swift` | `CoreLocation` (location is handled by `LocationPermissionRequester`) | **DONE** — Removed. |
| — | `ChoiceView.swift` | (none — clean) | — |

### Suggested Cleanup Priority

```
Phase 1 (During Week 1 strategy fixes):
  ✅ C12-C15: Replace print() with AppLogger — DONE
  ✅ C16: Remove .synchronize() calls — DONE (none found in Swift)
  ✅ C5-C7: Delete confirmed dead files/properties — DONE
  ✅ Russian comments: Translate all to English — DONE
  ✅ S21: Strip loc() wrappers + delete Russian UI strings — DONE
  ✅ Unused imports: AppModel (AVFoundation, AudioToolbox), BudgetTracking (Combine), StepsTraderApp (CoreLocation) — DONE

Phase 2 (During Week 2):
  C18-C20: Remove redundant objectWillChange.send() calls
  C21-C23: Standardize on async/await pattern
  ✅ C11: Gate minute mode behind feature flag — DONE
  ✅ C28: Fix fragile string matching in findTicketGroup — DONE

Phase 3 (Post-beta, Month 2):
  C1-C4: Refactor AppModel forwarding layer (big diff, needs testing)
  Internal vocabulary rename (stepsBalance → experienceBalance etc.)
  ✅ C24: paymentTransactions to file — DONE
  ✅ C25: pastDaySnapshots 90-day + file — DONE
  ✅ C8: Consolidate spentStepsToday — DONE
  ✅ C29: primaryAndFallbackSchemes in TargetResolver — DONE
  ✅ C26: Monitor logs cap 30 — DONE
  ✅ C27: minuteChargeLogs single shared file — DONE
  ✅ Unused imports + C16 — DONE
```

---

*This audit was produced by reading the complete codebase (50+ Swift files, 3 extensions, design.json) through the lens of PROJECT_STRATEGY.md. Every finding references a specific strategic goal. Code cleanup items are prioritized by crash/drift risk first, then developer velocity impact.*
