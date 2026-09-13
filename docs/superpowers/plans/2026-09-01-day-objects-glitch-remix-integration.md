# Day Objects Glitch and Remix Integration Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make Spent colors clearly audible but gradual through three degradation characters, make Remix generate a recognizably new coherent world without immediate repeats, and prove the complete audio system remains stable on the target iPhone.

**Architecture:** Replace the current squared glitch mapping with a tested perceptual curve and role-specific commands derived from one selected character. Extend the Remix signature to cover every structural sound choice. Apply all effects through role buses in the existing single engine, leaving the timing-anchor kick protected and the final limiter authoritative.

**Tech Stack:** Swift 6, AudioKit 5, AVFAudio, XCTest/XCUITest, os.signpost/MetricKit-compatible metrics, Xcode device builds.

**Spec:** `docs/superpowers/specs/2026-09-01-day-objects-expanded-sound-palette-design.md`

## Global Constraints

- Begin only after both preceding implementation plans pass on simulator and physical iPhone.
- Work only in `.worktrees/day-objects-generative-audio`; do not merge to `main`.
- Spent colors must affect harmony and Happenings even when the finger lead is idle.
- Map exact anchors `0→0`, `10→0.08`, `25→0.20`, `50→0.45`, `75→0.72`, `100→1.0` using smooth monotonic interpolation; clamp outside `0...100`.
- Parameter ramps must be at least 300 ms. The timing-anchor kick is never dropped, stuttered, or pitch-jumped.
- One engine, one limiter, and all Phase 1/2 voice/player/memory budgets remain unchanged.
- Remix changes structure at the safe bar boundary and may not repeat the immediately previous compound signature.
- Add tests before each production edit; do not fix failures by weakening assertions.

---

### Task 1: Replace squared intensity with the perceptual anchor curve

**Files:**

- Create: `StepsTrader/Experiments/DayObjects/Sound/Director/SpentColorsCurve.swift`
- Modify: `StepsTrader/Experiments/DayObjects/Sound/Director/GlitchPlanner.swift`
- Modify: `Steps4Tests/GlitchPlannerTests.swift`
- Create: `Steps4Tests/SpentColorsCurveTests.swift`
- Modify: `Steps4.xcodeproj/project.pbxproj`

**Interface:**

```swift
enum SpentColorsCurve {
    static let anchors: [(spentColors: Int, intensity: Double)] = [
        (0, 0), (10, 0.08), (25, 0.20),
        (50, 0.45), (75, 0.72), (100, 1),
    ]
    static func intensity(for spentColors: Int) -> Double
}
```

- [ ] Write failing tests for all anchors, clamping, monotonic output at every integer `0...100`, continuity at segment boundaries, and no step larger than `0.02` between neighboring integer inputs.
- [ ] Add a regression assertion that value 50 produces `0.45`, not the current squared `0.25`.
- [ ] Run `xcodebuild test -project Steps4.xcodeproj -scheme Steps4 -destination 'platform=iOS Simulator,name=iPhone 16 Pro' -only-testing:Steps4Tests/SpentColorsCurveTests -only-testing:Steps4Tests/GlitchPlannerTests`; confirm missing-type/value failures.
- [ ] Implement per-segment smoothstep interpolation: normalize the position between adjacent anchors, compute `t * t * (3 - 2 * t)`, and mix the two anchor amounts. This matches the approved curve, is continuous and monotonic, and lands exactly on every anchor.
- [ ] Route `GlitchPlanner` exclusively through this curve and remove duplicated squaring.
- [ ] Re-run `xcodebuild test -project Steps4.xcodeproj -scheme Steps4 -destination 'platform=iOS Simulator,name=iPhone 16 Pro' -only-testing:Steps4Tests/SpentColorsCurveTests -only-testing:Steps4Tests/GlitchPlannerTests`; expect all pass.
- [ ] Commit: `git commit -m "fix: make spent colors perceptually progressive" -- StepsTrader/Experiments/DayObjects/Sound/Director/SpentColorsCurve.swift StepsTrader/Experiments/DayObjects/Sound/Director/GlitchPlanner.swift Steps4Tests/SpentColorsCurveTests.swift Steps4Tests/GlitchPlannerTests.swift Steps4.xcodeproj/project.pbxproj`

### Task 2: Define three degradation characters and role-safe commands

**Files:**

- Modify: `StepsTrader/Experiments/DayObjects/Sound/Director/GlitchPlan.swift`
- Modify: `StepsTrader/Experiments/DayObjects/Sound/Director/GlitchPlanner.swift`
- Modify: `Steps4Tests/GlitchPlannerTests.swift`

**Interfaces and character behavior:**

```swift
enum GlitchCharacterID: String, CaseIterable, Codable, Sendable {
    case wornTape, brokenDelay, digitalDust
}

struct GlitchPlan: Equatable, Sendable {
    let characterID: GlitchCharacterID
    let intensity: Double
    let roles: [GlitchRolePlan]
}
```

```text
wornTape: wow/flutter + gentle saturation + bandwidth narrowing; no hard stutter below 0.75
brokenDelay: delay-time drift + feedback blooms + rare gated repeats above 0.55
digitalDust: sample-rate reduction + sparse bit dust + short dropouts above 0.65
```

At intensity `0...0.45`, every profile emphasizes warmth/wear. Above `0.45`, destructive parameters may grow. The anchor kick command always has dropout `0`, stutter `0`, pitch offset `0`, and saturation capped at `0.12`.

- [ ] Add failing table tests for every character at intensities `0`, `0.08`, `0.20`, `0.45`, `0.72`, `1.0` and every music role.
- [ ] Assert harmony and Happening commands are non-neutral by `0.20`, all commands are neutral at `0`, destructive gates remain zero below their thresholds, and the anchor kick invariants always hold.
- [ ] Run `xcodebuild test -project Steps4.xcodeproj -scheme Steps4 -destination 'platform=iOS Simulator,name=iPhone 16 Pro' -only-testing:Steps4Tests/GlitchPlannerTests`; confirm failures.
- [ ] Implement deterministic command derivation with no runtime random calls; event probabilities use precomputed Remix-seeded streams.
- [ ] Re-run `xcodebuild test -project Steps4.xcodeproj -scheme Steps4 -destination 'platform=iOS Simulator,name=iPhone 16 Pro' -only-testing:Steps4Tests/GlitchPlannerTests`; expect all pass.
- [ ] Commit: `git commit -m "feat: add three spent color characters" -- StepsTrader/Experiments/DayObjects/Sound/Director/GlitchPlan.swift StepsTrader/Experiments/DayObjects/Sound/Director/GlitchPlanner.swift Steps4Tests/GlitchPlannerTests.swift`

### Task 3: Apply Spent colors across all audible role buses

**Files:**

- Modify: `StepsTrader/Experiments/DayObjects/Sound/Playback/GlitchProcessor.swift`
- Modify: `StepsTrader/Experiments/DayObjects/Sound/Engine/DayObjectsInstrumentBankProtocol.swift`
- Modify: `StepsTrader/Experiments/DayObjects/Sound/Engine/DayObjectsInstrumentBank.swift`
- Modify: `StepsTrader/Experiments/DayObjects/Sound/Engine/DayObjectsHappeningSamplePool.swift`
- Modify: `StepsTrader/Experiments/DayObjects/Sound/Playback/HarmonyPlayer.swift`
- Modify: `StepsTrader/Experiments/DayObjects/Sound/Playback/RhythmPlayer.swift`
- Modify: `StepsTrader/Experiments/DayObjects/Sound/Playback/LeadPlayer.swift`
- Modify: `Steps4Tests/GlitchProcessorTests.swift`
- Modify: `Steps4Tests/DayObjectsInstrumentBankTests.swift`

**Role graph:**

```text
harmony tonal+piano ─ harmony wear bus ┐
happening sample pool ─ happening bus  ├─ master delay/reverb ─ final limiter
lead voice ─ lead character bus        │
drums except anchor ─ percussion bus   │
anchor kick ─ protected clean bus ─────┘
```

- [ ] Add failing fake-node tests showing commands reach harmony, Happenings, lead, and percussion buses; verify all parameter ramps are `>= 0.3 s`, repeated equal commands do not reschedule ramps, and non-finite inputs resolve to neutral.
- [ ] Add a no-lead regression: with harmony playing and no gesture, Spent colors 0→50 changes at least filter bandwidth and saturation metrics; with one Happening active it also changes its delay/filter metrics.
- [ ] Run `xcodebuild test -project Steps4.xcodeproj -scheme Steps4 -destination 'platform=iOS Simulator,name=iPhone 16 Pro' -only-testing:Steps4Tests/GlitchProcessorTests -only-testing:Steps4Tests/DayObjectsInstrumentBankTests`; confirm failures.
- [ ] Implement role-bus nodes once during instrument-bank preparation. `GlitchProcessor` translates plans into bounded node commands and never adds/removes nodes while playing.
- [ ] Preserve current program delay/reverb and final limiter; do not stack a second master distortion.
- [ ] Re-run `xcodebuild test -project Steps4.xcodeproj -scheme Steps4 -destination 'platform=iOS Simulator,name=iPhone 16 Pro' -only-testing:Steps4Tests/GlitchProcessorTests -only-testing:Steps4Tests/DayObjectsInstrumentBankTests`; expect all pass and engine-node count stable across 100 slider updates.
- [ ] Commit: `git commit -m "feat: apply spent colors across the full canvas mix" -- StepsTrader/Experiments/DayObjects/Sound/Playback/GlitchProcessor.swift StepsTrader/Experiments/DayObjects/Sound/Engine StepsTrader/Experiments/DayObjects/Sound/Playback/HarmonyPlayer.swift StepsTrader/Experiments/DayObjects/Sound/Playback/RhythmPlayer.swift StepsTrader/Experiments/DayObjects/Sound/Playback/LeadPlayer.swift Steps4Tests/GlitchProcessorTests.swift Steps4Tests/DayObjectsInstrumentBankTests.swift`

### Task 4: Add audibility and overload regression metrics

**Files:**

- Modify: `StepsTrader/Experiments/DayObjects/Sound/Playback/DayObjectsMusicPlaybackProtocol.swift`
- Modify: `StepsTrader/Experiments/DayObjects/Sound/Playback/DayObjectsMusicPlaybackEngine.swift`
- Modify: `StepsTrader/Experiments/DayObjects/Sound/Playback/PlaybackWorldBank.swift`
- Modify: `Steps4Tests/DayObjectsMusicPlaybackEngineTests.swift`

**Metrics additions:**

```swift
struct DayObjectsPlaybackMetrics: Equatable, Sendable {
    // existing fields remain
    let engineStartCount: Int
    let allocatedAudioNodeCount: Int
    let decodedSampleBytes: Int
    let peakLimiterReductionDB: Double
    let roleEffectIntensity: [GlitchRole: Double]
    let coldPreparationSeconds: Double?
}
```

- [ ] Add failing tests for one engine start, stable node count after 100 Remix/slider changes, decoded bytes limit, finite limiter reduction, and role-effect metrics matching the planned curve.
- [ ] Run `xcodebuild test -project Steps4.xcodeproj -scheme Steps4 -destination 'platform=iOS Simulator,name=iPhone 16 Pro' -only-testing:Steps4Tests/DayObjectsMusicPlaybackEngineTests`; confirm failures.
- [ ] Instrument preparation and commands without polling the audio callback or retaining unbounded histories. Cap debug attack history at its existing fixed limit.
- [ ] Re-run `xcodebuild test -project Steps4.xcodeproj -scheme Steps4 -destination 'platform=iOS Simulator,name=iPhone 16 Pro' -only-testing:Steps4Tests/DayObjectsMusicPlaybackEngineTests`; expect all pass.
- [ ] Commit: `git commit -m "test: expose bounded canvas audio metrics" -- StepsTrader/Experiments/DayObjects/Sound/Playback/DayObjectsMusicPlaybackProtocol.swift StepsTrader/Experiments/DayObjects/Sound/Playback/DayObjectsMusicPlaybackEngine.swift StepsTrader/Experiments/DayObjects/Sound/Playback/PlaybackWorldBank.swift Steps4Tests/DayObjectsMusicPlaybackEngineTests.swift`

### Task 5: Define the complete Remix world signature

**Files:**

- Create: `StepsTrader/Experiments/DayObjects/Sound/Director/DayObjectsWorldSignature.swift`
- Create: `StepsTrader/Experiments/DayObjects/Sound/Director/DayObjectsWorldSelector.swift`
- Modify: `StepsTrader/Experiments/DayObjects/Sound/Director/DayMusicPlan.swift`
- Modify: `StepsTrader/Experiments/DayObjects/Sound/Director/DeterministicMusicDirector.swift`
- Modify: `StepsTrader/Experiments/DayObjects/Sound/Lab/DayObjectsMusicLabController.swift`
- Create: `Steps4Tests/DayObjectsWorldSelectorTests.swift`
- Modify: `Steps4Tests/DeterministicMusicDirectorTests.swift`
- Modify: `Steps4Tests/DayObjectsMusicLabControllerTests.swift`
- Modify: `Steps4.xcodeproj/project.pbxproj`

**Interface:**

```swift
struct DayObjectsTimbreSignature: Equatable, Hashable, Sendable {
    let harmonyPalette: HarmonyPaletteID
    let leadProfile: LeadProfileID
    let drumKit: DayObjectsDrumKitID
    let glitchCharacter: GlitchCharacterID
}

struct DayObjectsWorldSignature: Equatable, Hashable, Sendable {
    let timbre: DayObjectsTimbreSignature
    let happeningPermutationSeed: UInt64
    let progressionSeed: UInt64
    let rhythmSeed: UInt64
    let effectsSeed: UInt64
}
```

- [ ] Add failing selector tests proving the world retains the eight approved values through its four-field timbre signature plus four seeds, same Remix seed is deterministic, 1,000 sequential selections never repeat the explicitly supplied previous four-field timbre signature, and bounded retry terminates.
- [ ] Add a collision-path test using an injected candidate generator that returns the old timbre combination with different effect seeds twice, then a different timbre combination; expect exactly three attempts.
- [ ] Add a controller regression test proving one Remix tap publishes a plan with a new signature while leaving Steps, Sleep, Happenings count, and Spent colors unchanged.
- [ ] Run `xcodebuild test -project Steps4.xcodeproj -scheme Steps4 -destination 'platform=iOS Simulator,name=iPhone 16 Pro' -only-testing:Steps4Tests/DayObjectsWorldSelectorTests -only-testing:Steps4Tests/DeterministicMusicDirectorTests -only-testing:Steps4Tests/DayObjectsMusicLabControllerTests`; confirm failures.
- [ ] Implement candidate generation with up to eight deterministic salted attempts. Reject equality on `DayObjectsTimbreSignature`, not merely the complete seed-bearing world. If all eight collide, deterministically advance the lead-profile catalog index by one while retaining the other generated fields.
- [ ] Carry the signature in `DayMusicPlan`; keep continuous inputs out of it. Have `DayObjectsMusicLabController.remix()` ask the selector for a signature avoiding `currentPlan.worldSignature`.
- [ ] Re-run `xcodebuild test -project Steps4.xcodeproj -scheme Steps4 -destination 'platform=iOS Simulator,name=iPhone 16 Pro' -only-testing:Steps4Tests/DayObjectsWorldSelectorTests -only-testing:Steps4Tests/DeterministicMusicDirectorTests -only-testing:Steps4Tests/DayObjectsMusicLabControllerTests`; expect all pass.
- [ ] Commit: `git commit -m "feat: make remix replace the complete sound world" -- StepsTrader/Experiments/DayObjects/Sound/Director/DayObjectsWorldSignature.swift StepsTrader/Experiments/DayObjects/Sound/Director/DayObjectsWorldSelector.swift StepsTrader/Experiments/DayObjects/Sound/Director/DayMusicPlan.swift StepsTrader/Experiments/DayObjects/Sound/Director/DeterministicMusicDirector.swift StepsTrader/Experiments/DayObjects/Sound/Lab/DayObjectsMusicLabController.swift Steps4Tests/DayObjectsWorldSelectorTests.swift Steps4Tests/DeterministicMusicDirectorTests.swift Steps4Tests/DayObjectsMusicLabControllerTests.swift Steps4.xcodeproj/project.pbxproj`

### Task 6: Make structural Remix atomic at the safe bar boundary

**Files:**

- Modify: `StepsTrader/Experiments/DayObjects/Sound/Playback/DayMusicPlanChange.swift`
- Modify: `StepsTrader/Experiments/DayObjects/Sound/Playback/DayMusicPlanDiffer.swift`
- Modify: `StepsTrader/Experiments/DayObjects/Sound/Playback/DayObjectsMusicPlaybackEngine.swift`
- Modify: `Steps4Tests/DayMusicPlanDifferTests.swift`
- Modify: `Steps4Tests/DayObjectsMusicPlaybackEngineTests.swift`

- [ ] Add failing `DayObjectsMobilePlaybackRuntime` tests that a Remix preloads all new required Synth One presets and drum samples into the existing bank, retains the old plan before boundary, swaps all structural IDs on one boundary event, and never exposes a mixed signature.
- [ ] Add tests for repeated Remix taps: only the latest pending world activates; pending count stays one; no preparation task leaks after stop/interruption.
- [ ] Run `xcodebuild test -project Steps4.xcodeproj -scheme Steps4 -destination 'platform=iOS Simulator,name=iPhone 16 Pro' -only-testing:Steps4Tests/DayMusicPlanDifferTests -only-testing:Steps4Tests/DayObjectsMusicPlaybackEngineTests`; confirm failures.
- [ ] Implement one `PreparedStructuralWorld` transaction inside `DayObjectsMobilePlaybackRuntime` containing palette, lead, kit, Happening permutation, glitch character, progression, and seeds. Prepare resources in the current single instrument bank, then activate in the order: stop new attacks, release old assignments, swap prepared assignments, update plans, resume scheduling, crossfade role gains.
- [ ] Use a `0.35...0.8 s` role-bus fade and preserve the current bar clock. Do not construct the legacy second `PlaybackWorldBank` path.
- [ ] Re-run `xcodebuild test -project Steps4.xcodeproj -scheme Steps4 -destination 'platform=iOS Simulator,name=iPhone 16 Pro' -only-testing:Steps4Tests/DayMusicPlanDifferTests -only-testing:Steps4Tests/DayObjectsMusicPlaybackEngineTests`; expect all pass.
- [ ] Commit: `git commit -m "feat: activate remixes as atomic musical worlds" -- StepsTrader/Experiments/DayObjects/Sound/Playback/DayMusicPlanChange.swift StepsTrader/Experiments/DayObjects/Sound/Playback/DayMusicPlanDiffer.swift StepsTrader/Experiments/DayObjects/Sound/Playback/DayObjectsMusicPlaybackEngine.swift Steps4Tests/DayMusicPlanDifferTests.swift Steps4Tests/DayObjectsMusicPlaybackEngineTests.swift`

### Task 7: Surface the active world and Spent colors character in the Lab

**Files:**

- Modify: `StepsTrader/Experiments/DayObjects/Sound/Lab/DayObjectsMusicLabController.swift`
- Modify: `StepsTrader/Experiments/DayObjects/DayObjectsLabView.swift`
- Modify: `Steps4Tests/DayObjectsMusicLabControllerTests.swift`
- Modify: `Steps4UITests/DayObjectsLabUITests.swift`

- [ ] Add failing controller tests for a concise summary containing tonal center/mode, harmony palette, lead family, drum kit, and glitch character; summary updates only when a pending Remix activates.
- [ ] Add failing UI tests that the summary and Spent colors value are accessible, Remix changes the signature, and all 30 Happening pads remain available afterward.
- [ ] Run `xcodebuild test -project Steps4.xcodeproj -scheme Steps4 -destination 'platform=iOS Simulator,name=iPhone 16 Pro' -only-testing:Steps4Tests/DayObjectsMusicLabControllerTests -only-testing:Steps4UITests/DayObjectsLabUITests`; confirm failures.
- [ ] Update the existing monospaced `worldSummary`; do not add manual instrument selectors. Display character names as `Worn Tape`, `Broken Delay`, and `Digital Dust`.
- [ ] Re-run `xcodebuild test -project Steps4.xcodeproj -scheme Steps4 -destination 'platform=iOS Simulator,name=iPhone 16 Pro' -only-testing:Steps4Tests/DayObjectsMusicLabControllerTests -only-testing:Steps4UITests/DayObjectsLabUITests`; expect all pass.
- [ ] Commit: `git commit -m "feat: show the generated canvas sound world" -- StepsTrader/Experiments/DayObjects/Sound/Lab/DayObjectsMusicLabController.swift StepsTrader/Experiments/DayObjects/DayObjectsLabView.swift Steps4Tests/DayObjectsMusicLabControllerTests.swift Steps4UITests/DayObjectsLabUITests.swift`

### Task 8: Run full automated verification

**Files:** none unless a new failing regression requires a scoped fix.

- [ ] Run `xcodebuild test -project Steps4.xcodeproj -scheme Steps4 -destination 'platform=iOS Simulator,name=iPhone 16 Pro' -only-testing:Steps4Tests/DayObjectsAudioResourceTests -only-testing:Steps4Tests/DayObjectsInstrumentManifestTests -only-testing:Steps4Tests/DayObjectsInstrumentBankTests -only-testing:Steps4Tests/DayObjectsHappeningSamplePoolTests -only-testing:Steps4Tests/DayObjectsDrumBankTests -only-testing:Steps4Tests/DayObjectsFeltPianoTests -only-testing:Steps4Tests/HarmonyPaletteTests -only-testing:Steps4Tests/HarmonyPlannerTests -only-testing:Steps4Tests/HarmonyPlayerTests -only-testing:Steps4Tests/LeadProfileTests -only-testing:Steps4Tests/LeadPlannerTests -only-testing:Steps4Tests/LeadPlayerTests -only-testing:Steps4Tests/LeadGestureMapperTests -only-testing:Steps4Tests/DayObjectsDrumKitTests -only-testing:Steps4Tests/RhythmPlannerTests -only-testing:Steps4Tests/RhythmPlayerTests -only-testing:Steps4Tests/HappeningSoundCatalogTests -only-testing:Steps4Tests/HappeningPitchResolverTests -only-testing:Steps4Tests/HappeningMusicPlannerTests -only-testing:Steps4Tests/HappeningScheduleAllocatorTests -only-testing:Steps4Tests/HappeningSchedulerTests -only-testing:Steps4Tests/SpentColorsCurveTests -only-testing:Steps4Tests/GlitchPlannerTests -only-testing:Steps4Tests/GlitchProcessorTests -only-testing:Steps4Tests/LayerMixPlannerTests -only-testing:Steps4Tests/TonalWorldPlannerTests -only-testing:Steps4Tests/AmbientVoiceLeadingTests -only-testing:Steps4Tests/StableMusicRandomTests -only-testing:Steps4Tests/DeterministicMusicDirectorTests -only-testing:Steps4Tests/DayObjectsRemixCoordinatorTests -only-testing:Steps4Tests/DayMusicPlanDifferTests -only-testing:Steps4Tests/DayObjectsMusicPlaybackEngineTests -only-testing:Steps4Tests/DayObjectsMusicLabControllerTests`.
- [ ] Run `xcodebuild test -project Steps4.xcodeproj -scheme Steps4 -destination 'platform=iOS Simulator,name=iPhone 16 Pro' -only-testing:Steps4UITests/DayObjectsLabUITests`.
- [ ] Run `xcodebuild build -project Steps4.xcodeproj -scheme Steps4 -destination 'generic/platform=iOS'` and confirm success.
- [ ] Inspect `git diff --check`, asset-manifest verification scripts, resource size, decoded-buffer metrics, allocated voice/player counts, and node count stability.
- [ ] Run `rg -n 'TODO|TBD|FIXME|fatalError' StepsTrader/Experiments/DayObjects/Sound scripts/day_objects_audio`; expect no matches in the new audio code. Verify every external resource has a pinned URL, revision, hash, and license entry.
- [ ] Do not declare completion until all failures are fixed and the same commands are rerun cleanly.

### Task 9: Install and perform the physical-iPhone acceptance pass

**Files:** none unless a reproducible defect first receives a failing regression test.

- [ ] Build for iPhone Costa UDID `00008130-001E3CE622C0001C`, install bundle `personal-project.StepsTrader`, and launch after the user unlocks the device.
- [ ] Verify cold full Canvas ready `<= 8 s`, cold isolated Happening tap `<= 1.5 s`, warm pad retrigger `<= 100 ms`, and no UI stalls while opening diagnostics or moving sliders.
- [ ] Listen at Spent colors 0/10/25/50/75/100 for each character. Confirm 10 is subtle, 25 audible, 50 unmistakable, 75 strongly degraded, 100 extreme but limiter-safe; no small-value cliff.
- [ ] With no finger contact, confirm harmony and Happenings audibly change. With touch lead, confirm its character also changes without harsh jumps.
- [ ] At Steps 100%, confirm full rhythm/percussion and stable kick. At Sleep 100%, confirm a developed moving progression rather than one static chord. At 10 Happenings, confirm all assigned objects recur.
- [ ] Trigger at least 20 Remixes and confirm each consecutive world is audibly different and UI summary matches the activated signature.
- [ ] Watch for clipping, thermal throttling, interruption recovery, background/foreground recovery, and repeated Sound on/off. Any reproducible issue gets a failing test before the fix.
- [ ] Record final test counts, build version, device OS, measured timings, resource sizes, and commit hashes in the final handoff; keep the branch unmerged for the user's listening decision.
