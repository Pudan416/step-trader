# Public Canvas onboarding implementation plan

> **For agentic workers:** Execute tasks with superpowers:executing-plans; bounded independent implementation may use superpowers:subagent-driven-development.

**Goal:** Replace first-run stories and legacy coach marks with the existing real Canvas tour in Debug and Release, with a safe first-launch test entry.

**Architecture:** CanvasTour owns guarded presentation progress; CanvasOnboardingState owns the existing durable first-run completion marker and legacy migration. Root bootstrap loads real data without prompting, then claims first-run start once per process. DEBUG replay/diagnostics remain separate from automatic first-run completion.

**Tech Stack:** SwiftUI, Observation, UserDefaults, XCTest, existing Health/FamilyControls/account services.

**Spec:** User-approved replacement of the DEBUG Canvas tour described in this conversation, including Test first launch without data deletion.

## Global constraints

- Preserve real data, model economy, permissions and shared services.
- Finish and confirmed Skip complete first run; an interrupted first run starts at Welcome next process.
- Completed legacy users do not automatically see the new tour. Retain flag migration, delete old UI and coach machinery.
- DEBUG fixtures and launch arguments have no Release effect.
- No installation or publishing is part of this change unless requested separately.

### Task 1: First-run lifecycle

**Files:** Create `StepsTrader/Views/Onboarding/CanvasOnboardingState.swift`, `Steps4Tests/CanvasOnboardingStateTests.swift`; modify `StepsTrader/StepsTraderApp.swift`.

- [x] Test fresh state, modern/legacy completion, once-per-process automatic start, completion after restart, and first-launch reset preserving unrelated defaults.
- [x] Implement `isCompleted`, `claimAutomaticStart()`, `complete()`, `resetForFirstLaunchTest()` using `onboarding_state_v1` and the three historical completion inputs.
- [x] Always show real MainTabView; gate PayGate/handoff/tips/review until completion. After awaited bootstrap without requests, start `CanvasTour.shared.start(source: "firstLaunch")` if automatic start is claimed.
- [x] Remove old root story branch, coach manager and deferred coach task. Preserve model initialization/restore.

### Task 2: Promote the real tour

**Files:** Rename DebugCanvasTour/Setup/UI into CanvasTour/Setup/UI; update Gallery, palette, drawer, Feeds, Apps, Me and permission event producers, MainTabView and Supabase analytics.

- [x] Compile production tour and real result callbacks in both configurations; retain fixture/debug diagnostics guards.
- [x] Use a new public progress storage key so old DEBUG sessions never become public sessions.
- [x] Mark `CanvasOnboardingState.shared.complete()` only for actual `firstLaunch` Finish/confirmed exit, not diagnostic replay or Stop.
- [x] Keep DEBUG replay analytics suppression; production mutations retain normal product analytics.
- [x] Remove old CoachMarkManager/Overlay/AnchorKey and all their producers/consumers. Remove old stories, models, floaters, onboarding-only Apple helper and demo.

### Task 3: Developer first-launch test and regression tests

**Files:** `SettingsDeveloperPage.swift`, `CanvasTourDeveloperPage.swift`, existing tour unit/UI tests; remove legacy-only tests.

- [x] Add `canvas_tour.debug.testFirstLaunch`: stop replay and reset only completion flags, tell user to restart app.
- [x] Preserve the existing Start/Restart/Resume/Stop, target IDs, diagnostics and per-sheet exit ownership.
- [x] Test completion callback on Finish and Skip, absent on developer Stop/replay; test real automatic Welcome, exit persistence and unchanged render viewport.

### Task 4: Verification and report

- [x] Build Debug tests and run first-run state and coordinator regressions plus explicit critical UI paths.
- [x] Build Release with code signing disabled to verify no missing DEBUG dependencies.
- [x] Search for deleted legacy types, check diff, document tested routes and device-only permission limitations.
- [x] Commit the change; leave physical install to a separately authorized installation task.
