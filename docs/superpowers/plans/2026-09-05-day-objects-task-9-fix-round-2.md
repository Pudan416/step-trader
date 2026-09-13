# Day Objects Task 9 Fix Round 2 Implementation Plan

> Execute locally with strict RED/GREEN/refactor. No subagents are permitted for this fix round.

**Goal:** Make the offline worst-case overlap originate at the real production transport's second-chord boundary, prove audible Harmony crossfade progress, and release the diagnostic Bass note on deterministic virtual time.

**Architecture:** Keep the production transport and player graph authoritative. Add bounded DEBUG/INTERNAL Harmony transition observations, coordinate the stress audition from actual transport callbacks after `WorldState.render`, and schedule Bass release as an offline-render frame boundary rather than a wall-clock task.

**Tech Stack:** Swift 6, XCTest, AVFAudio manual rendering, Xcode command-line test/build tooling.

---

### Task 1: Capture the semantic defect as RED

**Files:**
- Modify: `Steps4Tests/DayObjectsMixScenarioTests.swift`

1. Add a focused regression deriving the second-chord host time from the production tempo and schedule.
2. Assert the current stress activities occur there, not at the initial host time.
3. Run only that regression and retain the expected failure showing the synthetic future jump.

### Task 2: Add truthful Harmony transition observation

**Files:**
- Modify: `StepsTrader/Experiments/DayObjects/Sound/Playback/HarmonyPlayer.swift`
- Modify: `Steps4Tests/HarmonyPlayerTests.swift`

1. Add failing tests for scheduler-recorded role/chord/start subdivision/start host time and positive crossfade progress.
2. Add the smallest DEBUG/INTERNAL observation state populated only by real `render(barBoundary:)` and `render(subdivision:)` calls.
3. Keep the scheduling, voicing, topology, and processor behavior unchanged.

### Task 3: Drive stress and Bass release from virtual transport time

**Files:**
- Modify: `StepsTrader/Experiments/DayObjects/Sound/Diagnostics/DayObjectsOfflineMixRenderer.swift`
- Modify: `Steps4Tests/DayObjectsMixScenarioTests.swift`

1. Move stress triggering into the actual second-chord bar-boundary callback after production world rendering.
2. Remove the manual future Harmony event and synthetic transition append.
3. Record the scheduler-observed transition start and first positive audible progress.
4. Add an exact 220 ms offline frame boundary and release the diagnostic Bass gate there, recording release time and zero active voices.
5. Assert all eight onset activities share the real transition host time, progression is monotonic, crossfade progress is positive, and Bass is released before cleanup.

### Task 4: Add bounded plan-aware crest calibration

**Files:**
- Modify: `StepsTrader/Experiments/DayObjects/Sound/Playback/DayObjectsMixController.swift`
- Modify: `StepsTrader/Experiments/DayObjects/Sound/Playback/DayObjectsMusicPlaybackEngine.swift`
- Modify: `Steps4Tests/DayObjectsMixControllerTests.swift`
- Modify: `Steps4Tests/DayMusicPlanDifferTests.swift`
- Modify: `Steps4Tests/DayObjectsMusicPlaybackEngineTests.swift`

1. Add RED pure mappings for finite/capped Steps density, exact groove-mode
   targets, endpoints, continuity, and deterministic bounds no wider than 1 dB.
2. Apply only existing direct/spatial-send controls through the established
   250 ms ramp; leave graph topology, event density, and scheduling unchanged.
3. Prove Steps-only calibration changes remain continuous in the plan differ
   and do not allocate or restart a live runtime world.
4. Run Steps, percussion, three fresh Arp phases, and H/Happenings/Lead
   isolation guards sequentially. Stop before the matrix on any gate failure.

### Task 5: Verify and regenerate evidence

**Files:**
- Modify: `Steps4Tests/DayObjectsMixScenarioTests.swift`
- Modify: `docs/day-objects-mix-scenario-report.json`
- Modify: `docs/day-objects-bass-mix-listening-checklist.md`
- Modify: `.superpowers/sdd/2026-09-04-day-objects-bass-mixing-mastering/task-9-report.md`

1. Run the focused worst-case guard sequentially and stop if it reaches 60 seconds.
2. Run the 31 x 60-second matrix once only after every guard passes; return immediately on any per-scenario time violation.
3. Copy the fresh JSON artifact and update checklist/report with actual timestamps, progress, release, calibration ledger, measurements, and timing.
4. Run focused renderer, analyzer, mix, differ, runtime, Harmony, transport, lease, and isolation tests plus unsigned/signed generic iOS builds.
5. Review the diff, stage only Fix Round 2 files, and commit.
