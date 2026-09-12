# Day Objects Task 9 Fix Round 1 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkboxes for resumable progress.

**Goal:** Correct Task 9's offline true-peak and production-graph evidence paths, make live/offline exclusion process-wide, and regenerate truthful 31 × 60-second acceptance evidence without changing the shipping graph topology or the physical −6 dB pre-limiter master trim.

**Architecture:** Keep diagnostics DEBUG/INTERNAL-only. Put the BS.1770-5 Annex 2 four-phase FIR in the analyzer with explicit zero state and tail flush. Add one process-wide `@MainActor` playback lease at actual runtime entry points. Keep offline rendering on the production bank/transport graph, but make isolation zero before frame zero and make the worst-case injection return an auditable timestamp ledger. Rename the manual-render limiter value so every API and artifact calls it an estimated required attenuation gate.

**Tech stack:** Swift 6, XCTest, AVFAudio/AVAudioEngine manual rendering, AudioKit, `xcodebuild`, JSON evidence. No Python is required.

**Spec:** `.superpowers/sdd/2026-09-04-day-objects-bass-mixing-mastering/task-9-brief.md`, plus the parent-issued Task 9 Fix Round 1 findings dated 2026-09-05.

**Global constraints:** Strict RED/GREEN for every behavior change; no subagents; render scenarios sequentially; stop on any single render over 60 seconds; preserve the 4.5-second authored asset cap and Tasks 1–8; never raise the physical pre-limiter master trim above −6 dB; adjust only named descriptor/drum/role/return calibration points if corrected measurements require it; do not touch unrelated user documentation.

---

## Task 1: Make true peak and capture policy standards-conformant

**Files:**

- Modify: `Steps4Tests/DayObjectsLoudnessAnalyzerTests.swift`
- Modify: `StepsTrader/Experiments/DayObjects/Sound/Diagnostics/DayObjectsLoudnessAnalyzer.swift`

- [x] Add failing direct estimator fixtures for `[1, 1]`, a leading-edge impulse, and a trailing-edge impulse. Assert the expected BS.1770-5 Annex 2 four-phase FIR amplitudes with zero initial state and a zero-padded tail.
- [x] Add a failing analyzer test rejecting captures shorter than one complete 400 ms gating block.
- [x] Add a failing stereo-adapter test for interleaved Float32 PCM with the same loudness and peak as its planar equivalent.
- [x] Run only `DayObjectsLoudnessAnalyzerTests` and preserve the failing output as RED evidence.
- [x] Replace the custom/windowed valid-only interpolator with the Annex 2 order-48, four-phase coefficient table. Evaluate all phases at every input clock, begin from zero FIR state, and flush eleven zero input frames after EOF. Remove both the short-input shortcut and raw-sample peak shortcut.
- [x] Reject sub-400 ms input with a dedicated analyzer error before K-weighting, and deinterleave one- or two-channel Float32 PCM buffers in the adapter.
- [x] Rerun only `DayObjectsLoudnessAnalyzerTests` to GREEN.

## Task 2: Add one process-wide live/offline playback lease

**Files:**

- Modify: `Steps4Tests/DayObjectsInstrumentBankTests.swift`
- Modify: `Steps4Tests/DayObjectsMixScenarioTests.swift`
- Modify: `StepsTrader/Experiments/DayObjects/Sound/Engine/DayObjectsInstrumentBankProtocol.swift`
- Modify: `StepsTrader/Experiments/DayObjects/Sound/Engine/DayObjectsInstrumentBank.swift`
- Modify: `StepsTrader/Experiments/DayObjects/Sound/Diagnostics/DayObjectsOfflineMixRenderer.swift`

- [x] Add failing tests with distinct standalone bank/runtime instances proving live blocks offline and offline blocks live.
- [x] Add failing tests proving a throwing live start, a throwing offline begin, a completed offline render, and a cancelled/failed offline render all release ownership.
- [x] Run the focused lease tests and preserve RED.
- [x] Implement a DEBUG/INTERNAL-only `@MainActor` process lease with exclusive offline ownership and live ownership forbidden during offline use.
- [x] Acquire/release it around every standalone live start/stop and offline begin/end path. Acquire/release it at the shared AudioKit engine transition for pair and individual-pair starts, so pair promotion/demotion cannot leak or double-release the lease.
- [x] Keep renderer cleanup in a single unconditional error/cancellation path and rerun focused lease tests to GREEN.

## Task 3: Make isolation silent before frame zero

**Files:**

- Modify: `Steps4Tests/DayObjectsInstrumentBankTests.swift`
- Modify: `Steps4Tests/DayObjectsMixScenarioTests.swift`
- Modify: `StepsTrader/Experiments/DayObjects/Sound/Engine/DayObjectsInstrumentBank.swift`
- Modify: `StepsTrader/Experiments/DayObjects/Sound/Playback/DayObjectsMusicPlaybackEngine.swift`

- [x] Add a failing graph-state regression showing a role at the explicit diagnostic −60 dB target receives an immediate zero direct gain and zero sends, while the selected role retains its configured direct and spatial sends.
- [x] Add a failing production-path offline render in which the selected isolated role has no source; assert the rendered buffer is truly silent rather than an initial ramp leak.
- [x] Run the focused tests and preserve RED.
- [x] Apply the existing diagnostic mute sentinel as hard-zero direct/send state before engine start. Do not change sends for full-composition states, topology, or effect processor behavior.
- [x] Reset/release the production graph before manual rendering if needed to guarantee deterministic empty return state.
- [x] Rerun the focused isolation tests to GREEN.

## Task 4: Rename the offline limiter proxy truthfully

**Files:**

- Modify: `StepsTrader/Experiments/DayObjects/Sound/Diagnostics/DayObjectsOfflineMixRenderer.swift`
- Modify: `Steps4Tests/DayObjectsMixScenarioTests.swift`
- Modify: `docs/day-objects-mix-scenario-report.json`
- Modify: `docs/day-objects-bass-mix-listening-checklist.md`
- Modify: `.superpowers/sdd/2026-09-04-day-objects-bass-mixing-mastering/task-9-report.md`

- [x] First update focused assertions to demand `maximumEstimatedLimiterReductionDB` and verify the old JSON key/label is absent; confirm compilation/artifact RED.
- [x] Rename only the offline diagnostic accumulator, result field, JSON key, output labels, and documentation. Preserve Task 7's timestamp-aligned `DayObjectsMasterMetrics.estimatedLimiterReductionDB` implementation.
- [x] Rerun the focused renderer test to GREEN.

## Task 5: Prove the worst-case overlap at one host time

**Files:**

- Modify: `Steps4Tests/DayObjectsMixScenarioTests.swift`
- Modify: `StepsTrader/Experiments/DayObjects/Sound/Diagnostics/DayObjectsOfflineMixRenderer.swift`
- Modify only if required: `StepsTrader/Experiments/DayObjects/Sound/Playback/HarmonyPlayer.swift`

- [x] Add a failing renderer guard requiring timestamped activity records for `kickSoft`, Bass, a chord transition, held Lead, and four distinct Happenings, all at the same finite host time.
- [x] Add failing audition-failure coverage: if any requested component cannot be scheduled, rendering throws rather than silently weakening the stress case.
- [x] Run the focused worst-case guards and preserve RED.
- [x] Replace the loose post-start stimulus with deterministic explicit scheduling through the injected offline transport clock. Establish the first chord, schedule a second chord transition at the shared stress host time, begin/update the held Lead at that same time, require the kick/Bass audition result, and require four Happening handles.
- [x] Record the component, host time, and relevant identity in diagnostics; validate completeness/equal timestamps before rendering proceeds.
- [x] Rerun focused worst-case guards to GREEN. Do not use a wall-clock delay or sleep.

## Task 6: Produce controlled calibration evidence and recalibrate only if needed

**Files:**

- Modify: `Steps4Tests/DayObjectsMixScenarioTests.swift` (opt-in sequential calibration probe only)
- Modify only if corrected measurements fail: named calibration constants in the Task 9 brief
- Modify: `docs/day-objects-bass-mix-listening-checklist.md`
- Modify: `.superpowers/sdd/2026-09-04-day-objects-bass-mixing-mastering/task-9-report.md`

- [x] Add an explicitly gated calibration-probe path that emits LUFS-I, corrected dBTP, every role-bus RMS, and maximum estimated required peak attenuation for selected scenarios without asserting final acceptance.
- [x] Define two truthful batches: (A) the approved source/role/return/final-ceiling Task 9 calibration versus the exact pre-Task-9 constants; (B) BB Röy's descriptor trim at 0 dB versus −0.75 dB, extended by approval to −3.00 dB after fresh-run variance, with all other final constants held fixed.
- [x] Temporarily apply the exact baseline constants, render the selected probes sequentially, save the emitted baseline JSON, and immediately restore the final constants. Do not commit temporary baselines in production code.
- [x] Render the matching final probes sequentially. Record the controlled before/after values in a ledger; do not reconstruct or invent values.
- [x] If corrected true peak, representative loudness, role spread, Glitch delta, or normal estimated attenuation fails, adjust only the brief-authorized named calibration points and repeat the affected narrow guards before continuing.

## Task 7: Regenerate the complete matrix and public evidence once

**Files:**

- Modify: `docs/day-objects-mix-scenario-report.json`
- Modify: `docs/day-objects-bass-mix-listening-checklist.md`
- Modify: `.superpowers/sdd/2026-09-04-day-objects-bass-mixing-mastering/task-9-report.md`

- [x] From a clean stopped state, run the changed five-case guard (representative loudness/true peak, worst case, isolation, Glitch pair, and BB Röy) sequentially. Continue only if every hard gate passes and every render finishes below 60 seconds.
- [x] Run the full 31 × 60-second matrix exactly once after the final passing guard, sequentially. Stop immediately if any scenario exceeds 60 seconds.
- [x] Copy the generated JSON into the tracked public report, retain exact measured values, and update the checklist/report with corrected true-peak method, renamed estimated gate, deterministic overlap activity, isolation silence, wall times, and the controlled calibration ledger.

## Task 8: Verify, self-review, and commit only Fix Round 1

**Files:** all Fix Round 1 files above

- [x] Run the focused analyzer, renderer, instrument-bank, and regression groups specified by the brief.
- [x] Run the generic iOS build and the established signed paired-device build/install workflow if the paired device remains available; record any simulator/audio-device limitation honestly.
- [x] Inspect `git diff`, search for stale `maximumLimiterReductionDB` Task 9 labels, verify physical master trim is exactly −6 dB, verify no topology/ratio drift, and confirm unrelated docs remain unstaged.
- [x] Commit only Task 9 Fix Round 1 files with a scoped message.
- [x] Report status, commit, concise tests/renders/builds, corrected measurements/concerns, and the evidence report path to the parent.
