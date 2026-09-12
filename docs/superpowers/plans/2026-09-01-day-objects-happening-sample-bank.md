# Day Objects Happening Sample Bank Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the similar-sounding tonal Happening voices with 30 stable, chord-aware production recipes, expose them as pads `01`–`30` in Day Objects Lab, and make the same recipes power automatic births and recurrence.

**Architecture:** Add an immutable recipe catalog and deterministic resolver above a fixed four-voice sample pool. The sample pool joins the existing single AudioKit graph and supports two preparation levels: sample-only audition and full composition. Manual pads call the same resolver and playback path as scheduled Happenings without changing scene state.

**Tech Stack:** Swift 6, SwiftUI, AudioKit 5, AVFAudio, XCTest/XCUITest, Python 3 offline asset renderer, Xcode project resources.

**Spec:** `docs/superpowers/specs/2026-09-01-day-objects-expanded-sound-palette-design.md`

## Global Constraints

- Work only in `.worktrees/day-objects-generative-audio`; do not merge to `main`.
- Preserve the user-owned edits in `docs/superpowers/specs/2026-08-30-day-objects-native-instrument-bank-design.md` and `docs/day-objects-instrument-bank-listening-checklist.md`.
- Keep exactly one AudioKit engine and one final limiter. Manual audition may prepare fewer nodes, but may not create a second engine.
- Use four shared Happening sample voices. Remove the current two-voice tonal Happening pool, leaving eight tonal harmony/lead voices.
- Keep 30 stable IDs and labels; no pad may alter Happenings count, visual actors, Remix seed, or recurrence counters.
- App-bundled new audio must remain at or below 30 MiB; decoded Happening buffers at or below 48 MiB.
- Use VCSL at exact revision `c1ea7bcc3c7309650ab0da9d15c9cd1fbc4a4c7e` under CC0-1.0. Do not add Splice or Freesound assets.
- Run each production change test-first and commit only the files listed in that task.

---

### Task 1: Define the immutable 30-recipe contract

**Files:**

- Create: `StepsTrader/Experiments/DayObjects/Sound/Domain/HappeningSoundRecipe.swift`
- Create: `StepsTrader/Experiments/DayObjects/Sound/Domain/HappeningSoundCatalog.swift`
- Create: `Steps4Tests/HappeningSoundCatalogTests.swift`
- Modify: `Steps4.xcodeproj/project.pbxproj`

**Interfaces:**

```swift
struct HappeningSoundRecipeID: RawRepresentable, Codable, Hashable, Sendable {
    let rawValue: Int // 1...30
}

struct HappeningSampleSource: Equatable, Codable, Sendable {
    let resourceName: String
    let rootMIDI: UInt8
    let sha256: String
}

enum HappeningRecipeFamily: String, Codable, CaseIterable, Sendable {
    case synthPluck, acousticMallet, acousticBell, softOneShot, texture
}

enum HappeningPitchBehavior: Equatable, Codable, Sendable {
    case transpose(rootMIDI: UInt8, preferredRange: ClosedRange<UInt8>)
    case resonantNoise(referenceMIDI: UInt8, preferredRange: ClosedRange<UInt8>)
    case unpitched
}

struct HappeningSoundRecipe: Equatable, Codable, Sendable {
    let id: HappeningSoundRecipeID
    let label: String
    let family: HappeningRecipeFamily
    let sources: [HappeningSampleSource]
    let pitch: HappeningPitchBehavior
    let gainDB: Double
    let attackSeconds: Double
    let releaseSeconds: Double
    let delayMix: Double
    let delayFeedback: Double
    let reverbMix: Double
    let filterStartHz: Double
    let filterEndHz: Double
}
```

- [ ] Write tests asserting IDs `1...30`, labels `01...30`, six recipes per family, unique sample paths and checksums, bounded gains/envelopes/effects, and complete stable ordering. For every tonal recipe, assert the source-root pitch classes cover the octave with nearest distance at most two semitones.
- [ ] Run `xcodebuild test -project Steps4.xcodeproj -scheme Steps4 -destination 'platform=iOS Simulator,name=iPhone 16 Pro' -only-testing:Steps4Tests/HappeningSoundCatalogTests` and confirm compilation/test failure because the catalog does not exist.
- [ ] Implement the types and the 30-entry catalog. Tonal recipes `01...24` each declare four processed roots at pitch classes C, D♯, F♯, and A in their preferred octave; resonant textures `25...27` declare one noise source plus four legal resonator targets; unpitched textures `28...30` declare one source each. Entries `01...06`, `07...12`, `13...18`, `19...24`, `25...30` map to the five families in that order.
- [ ] Add the two source files and one test file to their existing Day Objects and test groups/targets in `project.pbxproj`.
- [ ] Re-run `xcodebuild test -project Steps4.xcodeproj -scheme Steps4 -destination 'platform=iOS Simulator,name=iPhone 16 Pro' -only-testing:Steps4Tests/HappeningSoundCatalogTests` and expect all catalog tests to pass.
- [ ] Commit: `git commit -m "feat: define thirty happening sound recipes" -- StepsTrader/Experiments/DayObjects/Sound/Domain/HappeningSoundRecipe.swift StepsTrader/Experiments/DayObjects/Sound/Domain/HappeningSoundCatalog.swift Steps4Tests/HappeningSoundCatalogTests.swift Steps4.xcodeproj/project.pbxproj`

### Task 2: Build a reproducible, attributed sample bundle

**Files:**

- Create: `scripts/day_objects_audio/build_happening_bank.py`
- Create: `scripts/day_objects_audio/happening-source-map.json`
- Create: `StepsTrader/Experiments/DayObjects/Sound/Resources/AudioLicenses/VCSL-CC0-1.0.txt`
- Create: `StepsTrader/Experiments/DayObjects/Sound/Resources/Happenings/01/*.wav` … `Happenings/30/*.wav`
- Modify: `StepsTrader/Experiments/DayObjects/Sound/Resources/AudioLicenses/SOURCES.json`
- Modify: `StepsTrader/Experiments/DayObjects/Sound/Resources/audio-assets-manifest.json`
- Modify: `Steps4Tests/DayObjectsAudioResourceTests.swift`
- Modify: `Steps4.xcodeproj/project.pbxproj`

**Exact external VCSL inputs:**

```text
07 Idiophones/Struck Idiophones/Vibraphone/Soft Mallets/Vibes_soft_C5_v1_rr1_Main.wav
08 Idiophones/Struck Idiophones/Vibraphone/Soft Mallets/Vibes_soft_F4_v1_rr1_Main.wav
09 Idiophones/Struck Idiophones/Balafon/Soft Mallet/EthnicXylo_softM_C4_vl2_rr1_Mid.wav
10 Idiophones/Struck Idiophones/Balafon/Soft Mallet/EthnicXylo_softM_F4_vl2_rr1_Mid.wav
11 Idiophones/Struck Idiophones/Marimba/Marimba_hit_Outrigger_C4_soft_01.wav
12 Idiophones/Struck Idiophones/Marimba/Marimba_hit_Outrigger_G4_soft_01.wav
13 Idiophones/Struck Idiophones/Glockenspiel/glock_soft_C5_02.wav
14 Idiophones/Struck Idiophones/Glockenspiel/glock_soft_G5_01.wav
15 Idiophones/Struck Idiophones/Vibraphone/Hard Mallets/Vibes_hard_C5_v2_rr1_Main.wav
16 Idiophones/Struck Idiophones/Vibraphone/Hard Mallets/Vibes_hard_F4_v2_rr1_Main.wav
17 Idiophones/Struck Idiophones/Tubular Bells 1/chimes_C4_p_rr1.wav
18 Idiophones/Struck Idiophones/Tubular Bells 1/chimes_D4_p_rr1.wav
```

Recipes `01...06` and `19...30` are rendered offline by the script from deterministic additive/FM/noise definitions in `happening-source-map.json`; seed equals recipe ID. For every tonal recipe, the renderer emits C, D♯, F♯, and A root files; for each VCSL recipe it derives the same four production roots from the exact pinned input and records the offline pitch transform. The result is 96 tonal WAVs plus six texture WAVs, exactly 102 app files. The script must clone or validate VCSL at the pinned revision, render/trim silence, add 5 ms fades, resample to mono 44.1 kHz 16-bit PCM, peak-normalize to -3 dBFS, reject clips, and regenerate original/processed SHA-256 entries.

- [ ] Extend `DayObjectsAudioResourceTests` first to expect `Happenings/` with exactly 102 WAVs, VCSL provenance, original and processed hashes, mono 44.1 kHz PCM, duration `0.12...6.0` seconds, aggregate file size `<= 30 MiB`, and `VCSL-CC0-1.0.txt` in the bundle.
- [ ] Run `xcodebuild test -project Steps4.xcodeproj -scheme Steps4 -destination 'platform=iOS Simulator,name=iPhone 16 Pro' -only-testing:Steps4Tests/DayObjectsAudioResourceTests` and confirm it fails on the missing Happenings inventory.
- [ ] Implement the source map and renderer. Expose `--output-root`, `--vcsl-checkout`, and `--verify-only`; make output byte-for-byte deterministic.
- [ ] Create the pinned source checkout with `git clone --filter=blob:none https://github.com/sgossner/VCSL.git /tmp/day-objects-vcsl && git -C /tmp/day-objects-vcsl checkout c1ea7bcc3c7309650ab0da9d15c9cd1fbc4a4c7e`, then run `python3 scripts/day_objects_audio/build_happening_bank.py --vcsl-checkout /tmp/day-objects-vcsl --output-root StepsTrader/Experiments/DayObjects/Sound/Resources/Happenings`.
- [ ] Update provenance and asset manifests with source key `vcsl` and revision above; generated entries use source key `project-authored` and a renderer-version field in their source record.
- [ ] Add the Happenings folder and VCSL license to the app and test resource phases in `project.pbxproj`.
- [ ] Run `python3 scripts/day_objects_audio/build_happening_bank.py --vcsl-checkout /tmp/day-objects-vcsl --output-root StepsTrader/Experiments/DayObjects/Sound/Resources/Happenings --verify-only`, then `xcodebuild test -project Steps4.xcodeproj -scheme Steps4 -destination 'platform=iOS Simulator,name=iPhone 16 Pro' -only-testing:Steps4Tests/DayObjectsAudioResourceTests`; expect both to pass.
- [ ] Commit: `git commit -m "assets: add attributed happening sample bank" -- scripts/day_objects_audio StepsTrader/Experiments/DayObjects/Sound/Resources Steps4Tests/DayObjectsAudioResourceTests.swift Steps4.xcodeproj/project.pbxproj`

### Task 3: Resolve recipes safely into the current chord

**Files:**

- Modify: `StepsTrader/Experiments/DayObjects/Sound/Playback/HappeningPitchResolver.swift`
- Create: `StepsTrader/Experiments/DayObjects/Sound/Playback/ResolvedHappeningSound.swift`
- Modify: `Steps4Tests/HappeningPitchResolverTests.swift`
- Modify: `Steps4.xcodeproj/project.pbxproj`

**Interface:**

```swift
struct ResolvedHappeningSound: Equatable, Sendable {
    let recipeID: HappeningSoundRecipeID
    let resourceName: String
    let sourceRootMIDI: UInt8?
    let targetMIDI: UInt8?
    let playbackRate: Double
    let resonantFilterHz: Double?
}

static func resolve(
    recipe: HappeningSoundRecipe,
    chord: ChordPlan,
    tonalWorld: TonalWorldPlan
) -> ResolvedHappeningSound
```

- [ ] Add failing tests for nearest allowed chord tone, register bounds, deterministic tie-breaking toward the lower note, playback-rate transposition capped to `-2...+2` semitones, alternative source-root choice when a target would exceed that cap, resonant-noise filter tuning, and unpitched rate `1.0`.
- [ ] Run `xcodebuild test -project Steps4.xcodeproj -scheme Steps4 -destination 'platform=iOS Simulator,name=iPhone 16 Pro' -only-testing:Steps4Tests/HappeningPitchResolverTests` and confirm failures for the new overload.
- [ ] Implement pure resolver logic. Keep the existing MIDI motif overload until the scheduler migration in Task 5 is green.
- [ ] Re-run `xcodebuild test -project Steps4.xcodeproj -scheme Steps4 -destination 'platform=iOS Simulator,name=iPhone 16 Pro' -only-testing:Steps4Tests/HappeningPitchResolverTests` and expect all to pass.
- [ ] Commit: `git commit -m "feat: resolve happening samples into current harmony" -- StepsTrader/Experiments/DayObjects/Sound/Playback/HappeningPitchResolver.swift StepsTrader/Experiments/DayObjects/Sound/Playback/ResolvedHappeningSound.swift Steps4Tests/HappeningPitchResolverTests.swift Steps4.xcodeproj/project.pbxproj`

### Task 4: Add a four-voice sample pool to the single engine graph

**Files:**

- Create: `StepsTrader/Experiments/DayObjects/Sound/Engine/DayObjectsHappeningSamplePool.swift`
- Modify: `StepsTrader/Experiments/DayObjects/Sound/Engine/DayObjectsInstrumentBankProtocol.swift`
- Modify: `StepsTrader/Experiments/DayObjects/Sound/Engine/DayObjectsInstrumentBank.swift`
- Modify: `StepsTrader/Experiments/DayObjects/Sound/Playback/PlaybackWorldBank.swift`
- Create: `Steps4Tests/DayObjectsHappeningSamplePoolTests.swift`
- Modify: `Steps4Tests/DayObjectsInstrumentBankTests.swift`
- Modify: `Steps4Tests/DayObjectsMusicPlaybackEngineTests.swift`
- Modify: `Steps4.xcodeproj/project.pbxproj`

**Interface:**

```swift
@MainActor protocol DayObjectsHappeningSamplePoolProtocol: AnyObject {
    var metrics: HappeningSamplePoolMetrics { get }
    func prepare(recipeIDs: Set<HappeningSoundRecipeID>) throws
    @discardableResult func play(_ sound: ResolvedHappeningSound, gain: Double) throws -> Int
    func applyEffects(_ command: HappeningEffectCommand, rampSeconds: Double)
    func stop(voiceID: Int)
    func releaseAll()
}
```

- [ ] Write failing fake-backed tests for four allocated players, released/oldest-recurring voice stealing, manual audition and birth priority over recurrence, no fifth player allocation, buffer reuse, release-all, per-recipe decode failure isolation, decoded byte accounting, and one instrument-bank engine start.
- [ ] Update world-configuration tests to expect tonal capacities `1 + 4 + 2 + 1 = 8`, piano `2`, drums `10`, Happenings sample players `4`.
- [ ] Run `xcodebuild test -project Steps4.xcodeproj -scheme Steps4 -destination 'platform=iOS Simulator,name=iPhone 16 Pro' -only-testing:Steps4Tests/DayObjectsHappeningSamplePoolTests -only-testing:Steps4Tests/DayObjectsInstrumentBankTests -only-testing:Steps4Tests/DayObjectsMusicPlaybackEngineTests`; confirm failures.
- [ ] Implement four `AudioPlayer` voices feeding a Happening mixer/filter/delay/reverb bus already connected before the bank limiter. Load buffers on preparation, never on the render callback.
- [ ] Remove `.happenings` from `PlaybackWorldBankConfiguration.PoolName`; expose `worldBank.happenings` from the instrument bank.
- [ ] Add internal `PreparationLevel.sampleOnly(Set<HappeningSoundRecipeID>)` and `.fullMusic(DayObjectsInstrumentBankConfiguration)` without adding an engine.
- [ ] Re-run `xcodebuild test -project Steps4.xcodeproj -scheme Steps4 -destination 'platform=iOS Simulator,name=iPhone 16 Pro' -only-testing:Steps4Tests/DayObjectsHappeningSamplePoolTests -only-testing:Steps4Tests/DayObjectsInstrumentBankTests -only-testing:Steps4Tests/DayObjectsMusicPlaybackEngineTests` and verify decoded buffers are `<= 48 MiB` and engine-start count remains one.
- [ ] Commit: `git commit -m "feat: add shared happening sample voices" -- StepsTrader/Experiments/DayObjects/Sound/Engine StepsTrader/Experiments/DayObjects/Sound/Playback/PlaybackWorldBank.swift Steps4Tests/DayObjectsHappeningSamplePoolTests.swift Steps4Tests/DayObjectsInstrumentBankTests.swift Steps4Tests/DayObjectsMusicPlaybackEngineTests.swift Steps4.xcodeproj/project.pbxproj`

### Task 5: Route automatic births and recurrence through recipes

**Files:**

- Modify: `StepsTrader/Experiments/DayObjects/Sound/Director/HappeningMusicPlan.swift`
- Modify: `StepsTrader/Experiments/DayObjects/Sound/Director/HappeningMusicPlanner.swift`
- Modify: `StepsTrader/Experiments/DayObjects/Sound/Playback/ActiveHappeningState.swift`
- Modify: `StepsTrader/Experiments/DayObjects/Sound/Playback/HappeningScheduler.swift`
- Modify: `Steps4Tests/HappeningMusicPlannerTests.swift`
- Modify: `Steps4Tests/HappeningSchedulerTests.swift`

**Contract change:** replace `instrumentID` in `HappeningMusicPlan` with `recipeID`. Deterministically assign active Happenings without replacement from a Remix-seeded permutation, preferring a different family until all available families are represented.

- [ ] Add failing planner tests: counts `0...10`, unique recipe IDs, stable same-seed output, changed Remix seed, at least four families for counts `>= 4`, at least six source identities at count 10, and no adjacent same-family births when another compatible family is available.
- [ ] Add failing scheduler tests showing birth and recurrence both call `samplePool.play` with the same recipe/effect metadata and current chord, while manual audition/birth outrank recurrence under four-voice pressure and the per-beat attack cap and bounded recurrence horizon remain intact.
- [ ] Run `xcodebuild test -project Steps4.xcodeproj -scheme Steps4 -destination 'platform=iOS Simulator,name=iPhone 16 Pro' -only-testing:Steps4Tests/HappeningMusicPlannerTests -only-testing:Steps4Tests/HappeningSchedulerTests` and confirm failures.
- [ ] Migrate plan, state, scheduler metrics, and attack records from instrument IDs/MIDI notes to recipe/resolved-sound data.
- [ ] Delete the obsolete MIDI-only resolver overload after all call sites compile.
- [ ] Re-run `xcodebuild test -project Steps4.xcodeproj -scheme Steps4 -destination 'platform=iOS Simulator,name=iPhone 16 Pro' -only-testing:Steps4Tests/HappeningMusicPlannerTests -only-testing:Steps4Tests/HappeningSchedulerTests -only-testing:Steps4Tests/HappeningScheduleAllocatorTests`; expect all to pass.
- [ ] Commit: `git commit -m "feat: schedule recurring happening recipes" -- StepsTrader/Experiments/DayObjects/Sound/Director/HappeningMusicPlan.swift StepsTrader/Experiments/DayObjects/Sound/Director/HappeningMusicPlanner.swift StepsTrader/Experiments/DayObjects/Sound/Playback/ActiveHappeningState.swift StepsTrader/Experiments/DayObjects/Sound/Playback/HappeningScheduler.swift StepsTrader/Experiments/DayObjects/Sound/Playback/HappeningPitchResolver.swift Steps4Tests/HappeningMusicPlannerTests.swift Steps4Tests/HappeningSchedulerTests.swift Steps4Tests/HappeningScheduleAllocatorTests.swift`

### Task 6: Add non-mutating manual audition to the main playback boundary

**Files:**

- Modify: `StepsTrader/Experiments/DayObjects/Sound/Playback/DayObjectsMusicPlaybackProtocol.swift`
- Modify: `StepsTrader/Experiments/DayObjects/Sound/Playback/DayObjectsMusicPlaybackEngine.swift`
- Modify: `StepsTrader/Experiments/DayObjects/Sound/Lab/DayObjectsMusicLabController.swift`
- Modify: `Steps4Tests/DayObjectsMusicPlaybackEngineTests.swift`
- Modify: `Steps4Tests/DayObjectsMusicLabControllerTests.swift`

**Interface:**

```swift
func auditionHappening(_ recipeID: HappeningSoundRecipeID) async throws
```

- [ ] Add failing controller tests proving a pad tap leaves `state`, `currentPlan`, Happenings IDs, Remix seed, and playback scheduling metrics unchanged.
- [ ] Add failing engine tests: when music is on, audition resolves against the currently sounding chord; when off, it starts sample-only preparation and uses C4 reference harmony; repeated cold taps coalesce into one preparation task; full start upgrades the same engine instead of creating a second one.
- [ ] Run `xcodebuild test -project Steps4.xcodeproj -scheme Steps4 -destination 'platform=iOS Simulator,name=iPhone 16 Pro' -only-testing:Steps4Tests/DayObjectsMusicPlaybackEngineTests -only-testing:Steps4Tests/DayObjectsMusicLabControllerTests` and confirm failures.
- [ ] Implement runtime state `.stopped`, `.preparingSamples`, `.sampleOnly`, `.fullMusic`; serialize transitions on `@MainActor`. Preserve public `soundState == .off` during sample-only audition.
- [ ] Ensure cancellation on view disappearance/interruption releases audition voices and deactivates the audio session when no full composition is running.
- [ ] Re-run `xcodebuild test -project Steps4.xcodeproj -scheme Steps4 -destination 'platform=iOS Simulator,name=iPhone 16 Pro' -only-testing:Steps4Tests/DayObjectsMusicPlaybackEngineTests -only-testing:Steps4Tests/DayObjectsMusicLabControllerTests`; expect all to pass.
- [ ] Commit: `git commit -m "feat: audition happening recipes through canvas engine" -- StepsTrader/Experiments/DayObjects/Sound/Playback/DayObjectsMusicPlaybackProtocol.swift StepsTrader/Experiments/DayObjects/Sound/Playback/DayObjectsMusicPlaybackEngine.swift StepsTrader/Experiments/DayObjects/Sound/Lab/DayObjectsMusicLabController.swift Steps4Tests/DayObjectsMusicPlaybackEngineTests.swift Steps4Tests/DayObjectsMusicLabControllerTests.swift`

### Task 7: Add the `01`–`30` pad grid below the music controls

**Files:**

- Create: `StepsTrader/Experiments/DayObjects/Sound/Lab/HappeningSoundPadGrid.swift`
- Modify: `StepsTrader/Experiments/DayObjects/DayObjectsLabView.swift`
- Modify: `Steps4UITests/DayObjectsLabUITests.swift`
- Modify: `Steps4.xcodeproj/project.pbxproj`

- [ ] Add failing UI tests that scroll to `dayObjects.happeningPads`, find exactly 30 buttons `dayObjects.happeningPad.01` … `.30`, tap `01` with Sound off and `30` with Sound on, and confirm Happenings slider/readout does not change.
- [ ] Run `xcodebuild test -project Steps4.xcodeproj -scheme Steps4 -destination 'platform=iOS Simulator,name=iPhone 16 Pro' -only-testing:Steps4UITests/DayObjectsLabUITests` and confirm failure because the grid is absent.
- [ ] Implement a five-column adaptive grid under Spent colors and above Remix. Display two-digit labels and a brief pressed/loading state. A recipe that fails decoding stays disabled with the accessible reason `Sound unavailable`; other pads, Remix, and sliders remain usable.
- [ ] Add accessibility label `Happening sound 01, synth pluck` and hint `Plays this sound without adding a figure` for each pad.
- [ ] Re-run `xcodebuild test -project Steps4.xcodeproj -scheme Steps4 -destination 'platform=iOS Simulator,name=iPhone 16 Pro' -only-testing:Steps4UITests/DayObjectsLabUITests -only-testing:Steps4Tests/DayObjectsMusicLabControllerTests`; expect all to pass.
- [ ] Commit: `git commit -m "feat: add thirty happening audition pads" -- StepsTrader/Experiments/DayObjects/Sound/Lab/HappeningSoundPadGrid.swift StepsTrader/Experiments/DayObjects/DayObjectsLabView.swift Steps4UITests/DayObjectsLabUITests.swift Steps4.xcodeproj/project.pbxproj`

### Task 8: Verify Phase 1 on simulator and iPhone

**Files:**

- Inspect: `StepsTrader/Experiments/DayObjects/Sound/Engine/DayObjectsHappeningSamplePool.swift`
- Leave the user-owned `docs/day-objects-instrument-bank-listening-checklist.md` untouched; record measurements in the final handoff.

- [ ] Run all selected audio tests:

```bash
xcodebuild test -project Steps4.xcodeproj -scheme Steps4 \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro' \
  -only-testing:Steps4Tests/DayObjectsAudioResourceTests \
  -only-testing:Steps4Tests/HappeningSoundCatalogTests \
  -only-testing:Steps4Tests/HappeningPitchResolverTests \
  -only-testing:Steps4Tests/DayObjectsHappeningSamplePoolTests \
  -only-testing:Steps4Tests/HappeningMusicPlannerTests \
  -only-testing:Steps4Tests/HappeningSchedulerTests \
  -only-testing:Steps4Tests/DayObjectsMusicPlaybackEngineTests \
  -only-testing:Steps4Tests/DayObjectsMusicLabControllerTests
```

- [ ] Run `xcodebuild test -project Steps4.xcodeproj -scheme Steps4 -destination 'platform=iOS Simulator,name=iPhone 16 Pro' -only-testing:Steps4UITests/DayObjectsLabUITests`; expect zero failures.
- [ ] Build for device UDID `00008130-001E3CE622C0001C`, install without merging, and launch when the phone is unlocked.
- [ ] Measure cold sample-only tap `<= 1.5 s`, warm retrigger `<= 100 ms`, full Canvas ready `<= 8 s`, no second engine, decoded buffers `<= 48 MiB`, and new bundle audio `<= 30 MiB`.
- [ ] Listen to all 30 pads once over music and once with music off; verify each pitched recipe stays consonant and automatic Happenings audibly recur at count 10.
- [ ] If any threshold fails, add a failing regression test before tuning buffers/preload; repeat the full verification.
- [ ] Commit measurement-only fixes, if any: `git commit -m "perf: bound happening audition resources" -- StepsTrader/Experiments/DayObjects/Sound/Engine/DayObjectsHappeningSamplePool.swift Steps4Tests`
