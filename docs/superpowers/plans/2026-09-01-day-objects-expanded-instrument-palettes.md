# Day Objects Expanded Instrument Palettes Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Expand the current composition to six coherent harmony palettes, ten touch-lead presets, four full drum kits, and richer sleep/steps behavior while preserving deterministic Remix and the existing Day Objects controls.

**Architecture:** Extend the immutable instrument manifest, then introduce palette/profile IDs into the pure director plans. Runtime players continue to receive semantic plans and use the current fixed voice/player budgets; Remix chooses a palette and kit, while Steps and Sleep only control musical complexity inside that chosen world.

**Tech Stack:** Swift 6, AudioKit 5, AVFAudio, XCTest, JSON asset manifests, Python 3 deterministic audio import, Xcode project resources.

**Spec:** `docs/superpowers/specs/2026-09-01-day-objects-expanded-sound-palette-design.md`

## Global Constraints

- Begin only after `2026-09-01-day-objects-happening-sample-bank.md` is green on simulator and device.
- Work only in `.worktrees/day-objects-generative-audio`; do not merge to `main`.
- Preserve mappings: Steps controls rhythm and percussion; Sleep controls harmony; Happenings and touch lead retain their Phase 1 paths.
- Normalize Steps by `stepGoal` and Sleep by `sleepGoalHours`; clamp each to `0...1`. Values above goal must not add complexity.
- Preserve one engine, final limiter, eight tonal voices, two piano voices, ten drum players, and four Happening sample voices.
- Catalog totals after this plan: 8 pads, 6 keys, 3 felt-piano treatments, 10 leads, 4 drum kits.
- Structural palette/kit changes happen only on a safe bar boundary. Slider changes remain continuous or subdivision-safe.
- Run every behavior test-first and keep commits task-scoped.

---

### Task 1: Import the exact additional Synth One presets

**Files:**

- Modify: `StepsTrader/Experiments/DayObjects/Sound/Domain/DayObjectsInstrumentManifest.swift`
- Modify: `StepsTrader/Experiments/DayObjects/Sound/Resources/SynthOnePresets/selected-presets.json`
- Modify: `StepsTrader/Experiments/DayObjects/Sound/Resources/audio-assets-manifest.json`
- Modify: `StepsTrader/Experiments/DayObjects/Sound/Resources/AudioLicenses/SOURCES.json`
- Modify: `Steps4Tests/DayObjectsInstrumentManifestTests.swift`
- Modify: `Steps4Tests/DayObjectsAudioResourceTests.swift`

**Approved additions from AudioKitSynthOne revision `6466a3715c96b7ecf1dd255a218cbd571408a314`:**

```text
pad.myoclonic — Myoclonic Pad — 83E87A5F-3238-4070-AB63-E599A4C07502
pad.bb-ambibrass — BB AmbiBrass Pad — F6ADF77E-7144-472A-9246-9940508F4831
pad.bb-descenders — BB The Descenders Pad — 00A3968F-070F-44BD-ADB1-4F015BFB6827
pad.jec-resopad — JEC Resopad — C42EA9C7-5A7F-470E-B988-83C282846759
pad.deeper-space — Deeper Space Pad — A171AADF-39EC-48C3-90A0-3F1E0A893FEB
keys.synth-dream-piano — Synth Dream Piano — 0DDA2D69-347D-476E-B949-E7BE7343F041
keys.80s-poly — 80s Poly Synth — 11C31C9C-2C9E-4C0E-BD70-3B92E0680188
keys.vintage-bells — Vintage Bells — 0415A79B-22D6-472C-B785-A1FDCE480DC7
lead.cosmic — Cosmic Lead — D90C3C61-A6C5-4D82-9353-847D72A0267C
lead.bb-wildchild — BB Wildchild Singers Lead — 61E19236-C92F-42B7-A114-35A802047AAB
lead.jec-atmosquare — JEC Atmosquare Lead 2 — 33F1CAB3-C097-4253-841B-C6F9DBDE086E
lead.jec-shimmer — JEC Shimmer Me Lead 2 — 61888FD2-8EAE-4990-AAC0-E47EA7AD9B3B
lead.jec-res-ohh — JEC Res Ohh Lead 2 — A4399103-855C-4B4F-BEFA-2902C38FE71E
lead.mello-flute — Mello Flute — 87A3523F-0595-4EA3-B240-23F80DFBDF73
lead.slide-and-glide — Slide and Glide Lead — 684901A1-C4CF-4A05-B3A7-E6E11265CEFE
```

- [ ] Update manifest tests first to expect 8 pads, 3 existing plucks, 3 existing basses, 10 leads, and 6 keys; assert all 30 Synth One UIDs are unique and ordered.
- [ ] Update resource tests to expect exactly those 30 records in `selected-presets.json` and the new SHA-256.
- [ ] Run `xcodebuild test -project Steps4.xcodeproj -scheme Steps4 -destination 'platform=iOS Simulator,name=iPhone 16 Pro' -only-testing:Steps4Tests/DayObjectsInstrumentManifestTests -only-testing:Steps4Tests/DayObjectsAudioResourceTests`; confirm count/UID failures.
- [ ] Extract exact records from the pinned upstream bank JSON, preserving every source field. Append descriptors with bounded reference MIDI, audition chord, and conservative initial trim: pads `-18 dB`, keys `-16 dB`, leads `-19 dB`.
- [ ] Re-run `xcodebuild test -project Steps4.xcodeproj -scheme Steps4 -destination 'platform=iOS Simulator,name=iPhone 16 Pro' -only-testing:Steps4Tests/DayObjectsInstrumentManifestTests -only-testing:Steps4Tests/DayObjectsAudioResourceTests`; expect all to pass and no unapproved UID.
- [ ] Commit: `git commit -m "assets: expand Synth One palette catalog" -- StepsTrader/Experiments/DayObjects/Sound/Domain/DayObjectsInstrumentManifest.swift StepsTrader/Experiments/DayObjects/Sound/Resources/SynthOnePresets/selected-presets.json StepsTrader/Experiments/DayObjects/Sound/Resources/audio-assets-manifest.json StepsTrader/Experiments/DayObjects/Sound/Resources/AudioLicenses/SOURCES.json Steps4Tests/DayObjectsInstrumentManifestTests.swift Steps4Tests/DayObjectsAudioResourceTests.swift`

### Task 2: Define six curated harmony palettes

**Files:**

- Create: `StepsTrader/Experiments/DayObjects/Sound/Director/HarmonyPalette.swift`
- Modify: `StepsTrader/Experiments/DayObjects/Sound/Director/HarmonyPlan.swift`
- Modify: `StepsTrader/Experiments/DayObjects/Sound/Director/HarmonyPlanner.swift`
- Modify: `Steps4Tests/HarmonyPlannerTests.swift`
- Create: `Steps4Tests/HarmonyPaletteTests.swift`
- Modify: `Steps4.xcodeproj/project.pbxproj`

**Interface and exact palette makeup:**

```swift
enum HarmonyPaletteID: String, CaseIterable, Codable, Sendable {
    case violetAir, warmOrbit, submergedKeys, glassNight, feltDawn, distantChoir
}

struct HarmonyPalette: Equatable, Sendable {
    let id: HarmonyPaletteID
    let primaryPads: [DayObjectsInstrumentID]
    let secondaryPadsOrKeys: [DayObjectsInstrumentID]
    let feltTreatment: FeltPianoTreatmentID
    let brightnessRange: ClosedRange<Double>
}

enum FeltPianoTreatmentID: String, CaseIterable, Codable, Sendable {
    case closeMuted, wideBloom, reverseShadow
}
```

```text
violetAir: interstellar + whispering-sands / jec-polaroids-2 / wideBloom
warmOrbit: forgotten-stories + bb-ambibrass / synth-dream-piano / closeMuted
submergedKeys: deeper-space + jec-resopad / bb-slow-poly / reverseShadow
glassNight: myoclonic + interstellar / vintage-bells / wideBloom
feltDawn: whispering-sands + bb-descenders / maschinenmensch / closeMuted
distantChoir: bb-ambibrass + deeper-space / 80s-poly / reverseShadow
```

- [ ] Add failing palette tests for six IDs, no missing descriptor, at least two pads and one key per palette, all three felt treatments represented twice, and deterministic seed selection.
- [ ] Add failing HarmonyPlanner tests at Sleep `0`, `0.25`, `0.5`, `0.75`, `1.0`, and `1.5`; verify `1.0 == 1.5`, but each lower level progressively adds voices, upper chord tones, filter brightness, and piano accents without changing palette ID.
- [ ] Run `xcodebuild test -project Steps4.xcodeproj -scheme Steps4 -destination 'platform=iOS Simulator,name=iPhone 16 Pro' -only-testing:Steps4Tests/HarmonyPaletteTests -only-testing:Steps4Tests/HarmonyPlannerTests`; confirm missing-type/behavior failures.
- [ ] Implement the catalog and add `paletteID` plus `feltTreatment` to `HarmonyPlan`. Keep the existing ambient progression and voice-leading code; do not derive palette from Sleep.
- [ ] Implement felt treatments only as player commands: closeMuted = short release/low send, wideBloom = longer release/high reverb, reverseShadow = delayed soft entrance/filtered send. Do not duplicate piano samples.
- [ ] Re-run `xcodebuild test -project Steps4.xcodeproj -scheme Steps4 -destination 'platform=iOS Simulator,name=iPhone 16 Pro' -only-testing:Steps4Tests/HarmonyPaletteTests -only-testing:Steps4Tests/HarmonyPlannerTests`; expect all pass.
- [ ] Commit: `git commit -m "feat: add six ambient harmony palettes" -- StepsTrader/Experiments/DayObjects/Sound/Director/HarmonyPalette.swift StepsTrader/Experiments/DayObjects/Sound/Director/HarmonyPlan.swift StepsTrader/Experiments/DayObjects/Sound/Director/HarmonyPlanner.swift Steps4Tests/HarmonyPlannerTests.swift Steps4Tests/HarmonyPaletteTests.swift Steps4.xcodeproj/project.pbxproj`

### Task 3: Render palette changes in the fixed harmony voice budget

**Files:**

- Modify: `StepsTrader/Experiments/DayObjects/Sound/Playback/HarmonyPlayer.swift`
- Modify: `StepsTrader/Experiments/DayObjects/Sound/Playback/PlaybackWorldBank.swift`
- Modify: `Steps4Tests/HarmonyPlayerTests.swift`
- Modify: `Steps4Tests/DayObjectsInstrumentBankTests.swift`

- [ ] Add failing player tests proving primary/secondary/piano roles use the selected palette, voice count never exceeds seven harmony tonal voices plus two piano voices, palette replacement waits for bar boundary, and a sleep-only update does not re-prepare a different instrument.
- [ ] Run `xcodebuild test -project Steps4.xcodeproj -scheme Steps4 -destination 'platform=iOS Simulator,name=iPhone 16 Pro' -only-testing:Steps4Tests/HarmonyPlayerTests -only-testing:Steps4Tests/DayObjectsInstrumentBankTests` and confirm failures.
- [ ] Implement palette-aware preparation before structural activation, crossfade current/new assignments within the existing pools, and apply felt treatment commands to the two piano players.
- [ ] Keep the lead's single reserved tonal voice isolated from harmony allocation.
- [ ] Re-run `xcodebuild test -project Steps4.xcodeproj -scheme Steps4 -destination 'platform=iOS Simulator,name=iPhone 16 Pro' -only-testing:Steps4Tests/HarmonyPlayerTests -only-testing:Steps4Tests/DayObjectsInstrumentBankTests` and confirm zero extra tonal voices or piano players.
- [ ] Commit: `git commit -m "feat: render expanded harmony palettes" -- StepsTrader/Experiments/DayObjects/Sound/Playback/HarmonyPlayer.swift StepsTrader/Experiments/DayObjects/Sound/Playback/PlaybackWorldBank.swift Steps4Tests/HarmonyPlayerTests.swift Steps4Tests/DayObjectsInstrumentBankTests.swift`

### Task 4: Define ten bounded touch-lead profiles

**Files:**

- Create: `StepsTrader/Experiments/DayObjects/Sound/Director/LeadProfile.swift`
- Modify: `StepsTrader/Experiments/DayObjects/Sound/Director/LeadPlan.swift`
- Modify: `StepsTrader/Experiments/DayObjects/Sound/Director/LeadPlanner.swift`
- Modify: `Steps4Tests/LeadPlannerTests.swift`
- Create: `Steps4Tests/LeadProfileTests.swift`
- Modify: `Steps4.xcodeproj/project.pbxproj`

**Exact profile assignment:**

```text
airy: verbacious, mello-flute
analog: cosmic, slide-and-glide
glassy: bb-silver-screen, jec-shimmer
vocalSoftwah: jec-softwah-2, bb-wildchild
brightBounded: jec-atmosquare, jec-res-ohh
```

Each profile stores gesture smoothing, portamento, filter min/max, velocity curve, delay/reverb sends, and output trim. Bright-bounded profiles cap filter at 7.5 kHz and resonance at 0.35.

- [ ] Add failing tests for ten unique lead instruments, two per family, deterministic selection by Remix seed, and safe parameter bounds.
- [ ] Add failing tests proving Steps, Sleep, Happenings, and Spent colors changes do not change the selected lead profile until Remix.
- [ ] Run `xcodebuild test -project Steps4.xcodeproj -scheme Steps4 -destination 'platform=iOS Simulator,name=iPhone 16 Pro' -only-testing:Steps4Tests/LeadProfileTests -only-testing:Steps4Tests/LeadPlannerTests`; confirm failures.
- [ ] Implement `LeadProfileID`, catalog, and `profileID` in `LeadPlan`; keep scale/chord quantization in `LeadGestureMapper`.
- [ ] Re-run `xcodebuild test -project Steps4.xcodeproj -scheme Steps4 -destination 'platform=iOS Simulator,name=iPhone 16 Pro' -only-testing:Steps4Tests/LeadProfileTests -only-testing:Steps4Tests/LeadPlannerTests`; expect all pass.
- [ ] Commit: `git commit -m "feat: define ten touch lead profiles" -- StepsTrader/Experiments/DayObjects/Sound/Director/LeadProfile.swift StepsTrader/Experiments/DayObjects/Sound/Director/LeadPlan.swift StepsTrader/Experiments/DayObjects/Sound/Director/LeadPlanner.swift Steps4Tests/LeadPlannerTests.swift Steps4Tests/LeadProfileTests.swift Steps4.xcodeproj/project.pbxproj`

### Task 5: Apply lead profiles without clicks or harsh filter jumps

**Files:**

- Modify: `StepsTrader/Experiments/DayObjects/Sound/Playback/LeadPlayer.swift`
- Modify: `StepsTrader/Experiments/DayObjects/Sound/Playback/LeadGestureMapper.swift`
- Modify: `Steps4Tests/LeadPlayerTests.swift`
- Modify: `Steps4Tests/LeadGestureMapperTests.swift`

- [ ] Add failing tests for first-touch 20 ms fade-in, note glide `40...180 ms`, filter smoothing `>= 80 ms`, bounded velocity, and profile replacement only after finger release or bar boundary.
- [ ] Run `xcodebuild test -project Steps4.xcodeproj -scheme Steps4 -destination 'platform=iOS Simulator,name=iPhone 16 Pro' -only-testing:Steps4Tests/LeadPlayerTests -only-testing:Steps4Tests/LeadGestureMapperTests`; confirm failures.
- [ ] Implement profile commands on the existing single lead voice. If Remix lands during a held gesture, keep the old instrument until `endLead`, then prepare the new profile.
- [ ] Re-run `xcodebuild test -project Steps4.xcodeproj -scheme Steps4 -destination 'platform=iOS Simulator,name=iPhone 16 Pro' -only-testing:Steps4Tests/LeadPlayerTests -only-testing:Steps4Tests/LeadGestureMapperTests`; expect no discontinuous gain/filter commands.
- [ ] Commit: `git commit -m "feat: render varied smooth touch leads" -- StepsTrader/Experiments/DayObjects/Sound/Playback/LeadPlayer.swift StepsTrader/Experiments/DayObjects/Sound/Playback/LeadGestureMapper.swift Steps4Tests/LeadPlayerTests.swift Steps4Tests/LeadGestureMapperTests.swift`

### Task 6: Import the acoustic sources for four complete drum kits

**Files:**

- Create: `scripts/day_objects_audio/build_drum_kits.py`
- Create: `scripts/day_objects_audio/drum-source-map.json`
- Create: `StepsTrader/Experiments/DayObjects/Sound/Resources/DrumKits/*.wav`
- Modify: `StepsTrader/Experiments/DayObjects/Sound/Resources/audio-assets-manifest.json`
- Modify: `StepsTrader/Experiments/DayObjects/Sound/Resources/AudioLicenses/SOURCES.json`
- Modify: `Steps4Tests/DayObjectsAudioResourceTests.swift`
- Modify: `Steps4.xcodeproj/project.pbxproj`

**Exact new VCSL inputs at the pinned VCSL revision:**

```text
organic.low: Membranophones/Struck Membranophones/Frame Drum/HDrumL_Hit_v2_rr1_Sum.wav
organic.high: Membranophones/Struck Membranophones/Frame Drum/HDrumS_Hit_v2_rr1_Sum.wav
organic.shaker: Idiophones/Struck Idiophones/Shaker, Small/Mid_ShakerLowFaster_Down_rr1.wav
organic.accent: Idiophones/Struck Idiophones/Tambourine 1/Tamb1_Hit_v1_rr1_Mid.wav
wood.low: Idiophones/Struck Idiophones/Cajon/Cajon_hit2_mp_rr1.wav
wood.high: Membranophones/Struck Membranophones/Bongos/BongoH_Hit1_v1_rr1_Mid.wav
wood.tick: Idiophones/Struck Idiophones/Woodblock/wood_click_mp.wav
wood.accent: Idiophones/Struck Idiophones/Claves/Claves1_Hit_v2_rr1_Mid.wav
```

Soft Electronic uses the current Cookbook samples. Dusty is a deterministic offline resample of `bass_drum_C1.wav`, `snare_D1.wav`, `cheeb-ch.wav`, and `cheeb-stick.wav` with 12-bit quantization, 18 kHz low-pass, -2 dBFS peak, and 5 ms fades; runtime glitch remains separate.

- [ ] Extend asset tests first for the exact 12 new files (8 VCSL + 4 dusty renders), pinned provenance, mono 44.1 kHz PCM, hashes, and total new-audio budget shared with Happenings.
- [ ] Run `xcodebuild test -project Steps4.xcodeproj -scheme Steps4 -destination 'platform=iOS Simulator,name=iPhone 16 Pro' -only-testing:Steps4Tests/DayObjectsAudioResourceTests` and confirm failure.
- [ ] Implement deterministic import/render script and source map; add files, manifests, licenses, and resource-phase entries.
- [ ] Run `python3 scripts/day_objects_audio/build_drum_kits.py --vcsl-checkout /tmp/day-objects-vcsl --output-root StepsTrader/Experiments/DayObjects/Sound/Resources/DrumKits --verify-only`, then `xcodebuild test -project Steps4.xcodeproj -scheme Steps4 -destination 'platform=iOS Simulator,name=iPhone 16 Pro' -only-testing:Steps4Tests/DayObjectsAudioResourceTests`; expect both to pass.
- [ ] Commit: `git commit -m "assets: add organic dusty and wood drum sources" -- scripts/day_objects_audio StepsTrader/Experiments/DayObjects/Sound/Resources Steps4Tests/DayObjectsAudioResourceTests.swift Steps4.xcodeproj/project.pbxproj`

### Task 7: Define semantic drum kits and Steps complexity

**Files:**

- Create: `StepsTrader/Experiments/DayObjects/Sound/Domain/DayObjectsDrumKit.swift`
- Modify: `StepsTrader/Experiments/DayObjects/Sound/Director/RhythmPlan.swift`
- Modify: `StepsTrader/Experiments/DayObjects/Sound/Director/RhythmPlanner.swift`
- Modify: `Steps4Tests/RhythmPlannerTests.swift`
- Create: `Steps4Tests/DayObjectsDrumKitTests.swift`
- Modify: `Steps4.xcodeproj/project.pbxproj`

**Interface:**

```swift
enum DayObjectsDrumKitID: String, CaseIterable, Codable, Sendable {
    case softElectronic, organic, dusty, woodPercussion
}

struct DayObjectsDrumKit: Equatable, Sendable {
    let id: DayObjectsDrumKitID
    let sampleByVoice: [DayObjectsDrumVoice: String]
    let trimDBByVoice: [DayObjectsDrumVoice: Double]
    let swing: Double
    let roomSend: Double
}
```

- [ ] Add failing kit tests for four complete semantic maps and no missing resource.
- [ ] Add failing RhythmPlanner table tests at Steps `0`, `0.1`, `0.25`, `0.5`, `0.75`, `1.0`, `1.5`: silence/pulse, kick, closed percussion, backbeat, open/organic accents, fills; assert `1.0 == 1.5` and kit ID unchanged by Steps.
- [ ] Assert tempo remains in the ambient band declared by the current spec and grows monotonically with normalized Steps.
- [ ] Run `xcodebuild test -project Steps4.xcodeproj -scheme Steps4 -destination 'platform=iOS Simulator,name=iPhone 16 Pro' -only-testing:Steps4Tests/DayObjectsDrumKitTests -only-testing:Steps4Tests/RhythmPlannerTests`; confirm failures.
- [ ] Implement kit catalog and add `kitID` to `RhythmPlan`. Keep pattern probabilities semantic, not filename-based.
- [ ] Re-run `xcodebuild test -project Steps4.xcodeproj -scheme Steps4 -destination 'platform=iOS Simulator,name=iPhone 16 Pro' -only-testing:Steps4Tests/DayObjectsDrumKitTests -only-testing:Steps4Tests/RhythmPlannerTests`; expect all pass.
- [ ] Commit: `git commit -m "feat: add four semantic drum kits" -- StepsTrader/Experiments/DayObjects/Sound/Domain/DayObjectsDrumKit.swift StepsTrader/Experiments/DayObjects/Sound/Director/RhythmPlan.swift StepsTrader/Experiments/DayObjects/Sound/Director/RhythmPlanner.swift Steps4Tests/RhythmPlannerTests.swift Steps4Tests/DayObjectsDrumKitTests.swift Steps4.xcodeproj/project.pbxproj`

### Task 8: Render varied kits in the existing ten-player pool

**Files:**

- Modify: `StepsTrader/Experiments/DayObjects/Sound/Engine/DayObjectsDrumBank.swift`
- Modify: `StepsTrader/Experiments/DayObjects/Sound/Playback/RhythmPlayer.swift`
- Modify: `Steps4Tests/DayObjectsDrumBankTests.swift`
- Modify: `Steps4Tests/RhythmPlayerTests.swift`

- [ ] Add failing tests proving kit samples load before activation, no more than ten players allocate, semantic overlap limits remain valid, and kit replacement waits for bar boundary.
- [ ] Add a regression test that the timing-anchor kick bypasses destructive dropout/stutter commands and remains audible at all Spent colors values.
- [ ] Run `xcodebuild test -project Steps4.xcodeproj -scheme Steps4 -destination 'platform=iOS Simulator,name=iPhone 16 Pro' -only-testing:Steps4Tests/DayObjectsDrumBankTests -only-testing:Steps4Tests/RhythmPlayerTests`; confirm failures.
- [ ] Implement sample-set switching inside the existing semantic players. Use velocity round-robin between overlap players, small deterministic `±7 ms` organic timing only for non-anchor percussion, and kit-specific room sends.
- [ ] Re-run `xcodebuild test -project Steps4.xcodeproj -scheme Steps4 -destination 'platform=iOS Simulator,name=iPhone 16 Pro' -only-testing:Steps4Tests/DayObjectsDrumBankTests -only-testing:Steps4Tests/RhythmPlayerTests`; expect all pass and allocated player count `10`.
- [ ] Commit: `git commit -m "feat: render four full drum kit characters" -- StepsTrader/Experiments/DayObjects/Sound/Engine/DayObjectsDrumBank.swift StepsTrader/Experiments/DayObjects/Sound/Playback/RhythmPlayer.swift Steps4Tests/DayObjectsDrumBankTests.swift Steps4Tests/RhythmPlayerTests.swift`

### Task 9: Select coherent palettes in the deterministic director

**Files:**

- Modify: `StepsTrader/Experiments/DayObjects/Sound/Director/MusicSeedDomain.swift`
- Modify: `StepsTrader/Experiments/DayObjects/Sound/Director/DeterministicMusicDirector.swift`
- Modify: `StepsTrader/Experiments/DayObjects/Sound/Director/DayMusicPlan.swift`
- Modify: `StepsTrader/Experiments/DayObjects/Sound/Playback/DayObjectsMusicPlaybackEngine.swift`
- Modify: `Steps4Tests/DeterministicMusicDirectorTests.swift`
- Modify: `Steps4Tests/DayObjectsMusicPlaybackEngineTests.swift`
- Modify: `Steps4Tests/DayMusicPlanSnapshotTests.swift`

**World selection:** one Remix seed independently derives `harmonyPalette`, `leadProfile`, `drumKit`, and the Phase 1 Happening permutation using separate seed domains. Continuous inputs never participate in these selections. The new Spent colors character is deliberately added in the third plan so this phase remains independently compilable.

- [ ] Add failing tests for same-seed equality, different-seed variety across all four catalogs, slider stability, and internal harmonic compatibility.
- [ ] Update snapshot fixtures to include palette/profile/kit IDs.
- [ ] Run `xcodebuild test -project Steps4.xcodeproj -scheme Steps4 -destination 'platform=iOS Simulator,name=iPhone 16 Pro' -only-testing:Steps4Tests/DeterministicMusicDirectorTests -only-testing:Steps4Tests/DayObjectsMusicPlaybackEngineTests -only-testing:Steps4Tests/DayMusicPlanSnapshotTests`; confirm failures.
- [ ] Implement the seed domains and carry IDs through `DayMusicPlan`; schedule changed IDs structurally at a bar boundary.
- [ ] Re-run `xcodebuild test -project Steps4.xcodeproj -scheme Steps4 -destination 'platform=iOS Simulator,name=iPhone 16 Pro' -only-testing:Steps4Tests/DeterministicMusicDirectorTests -only-testing:Steps4Tests/DayObjectsMusicPlaybackEngineTests -only-testing:Steps4Tests/DayMusicPlanSnapshotTests`; expect all pass.
- [ ] Commit: `git commit -m "feat: direct coherent instrument worlds" -- StepsTrader/Experiments/DayObjects/Sound/Director/MusicSeedDomain.swift StepsTrader/Experiments/DayObjects/Sound/Director/DeterministicMusicDirector.swift StepsTrader/Experiments/DayObjects/Sound/Director/DayMusicPlan.swift StepsTrader/Experiments/DayObjects/Sound/Playback/DayObjectsMusicPlaybackEngine.swift Steps4Tests/DeterministicMusicDirectorTests.swift Steps4Tests/DayObjectsMusicPlaybackEngineTests.swift Steps4Tests/DayMusicPlanSnapshotTests.swift`

### Task 10: Verify Phase 2 as a listenable device build

**Files:**

- Inspect: `StepsTrader/Experiments/DayObjects/Sound/Playback/HarmonyPlayer.swift`
- Inspect: `StepsTrader/Experiments/DayObjects/Sound/Playback/LeadPlayer.swift`
- Inspect: `StepsTrader/Experiments/DayObjects/Sound/Playback/RhythmPlayer.swift`
- Inspect: `StepsTrader/Experiments/DayObjects/Sound/Playback/DayObjectsMusicPlaybackEngine.swift`

- [ ] Run `xcodebuild test -project Steps4.xcodeproj -scheme Steps4 -destination 'platform=iOS Simulator,name=iPhone 16 Pro' -only-testing:Steps4Tests/HarmonyPaletteTests -only-testing:Steps4Tests/HarmonyPlannerTests -only-testing:Steps4Tests/HarmonyPlayerTests -only-testing:Steps4Tests/LeadProfileTests -only-testing:Steps4Tests/LeadPlannerTests -only-testing:Steps4Tests/LeadPlayerTests -only-testing:Steps4Tests/LeadGestureMapperTests -only-testing:Steps4Tests/DayObjectsDrumKitTests -only-testing:Steps4Tests/RhythmPlannerTests -only-testing:Steps4Tests/RhythmPlayerTests -only-testing:Steps4Tests/DayObjectsDrumBankTests -only-testing:Steps4Tests/DayObjectsInstrumentManifestTests -only-testing:Steps4Tests/DayObjectsAudioResourceTests -only-testing:Steps4Tests/DeterministicMusicDirectorTests -only-testing:Steps4Tests/DayObjectsRemixCoordinatorTests -only-testing:Steps4Tests/DayObjectsMusicPlaybackEngineTests -only-testing:Steps4Tests/HappeningSoundCatalogTests -only-testing:Steps4Tests/HappeningPitchResolverTests -only-testing:Steps4Tests/HappeningMusicPlannerTests -only-testing:Steps4Tests/HappeningSchedulerTests`.
- [ ] Run `xcodebuild test -project Steps4.xcodeproj -scheme Steps4 -destination 'platform=iOS Simulator,name=iPhone 16 Pro' -only-testing:Steps4UITests/DayObjectsLabUITests`; expect zero failures and all 30 pads retained.
- [ ] Build and install on iPhone UDID `00008130-001E3CE622C0001C` without merging.
- [ ] Listen to at least 12 Remixes, recording observed palette/lead/kit signatures. Confirm all six harmony palettes, all five lead families, and all four kits occur under deterministic test seeds.
- [ ] At Steps 0/25/50/75/100%, verify audible rhythmic growth with no extra growth above 100%. At Sleep 0/25/50/75/100%, verify audible harmonic growth with no palette change and no extra growth above 100%.
- [ ] Verify finger lead is smooth for every family, timing anchor remains clear, and count-10 Happenings remain audible over every drum kit.
- [ ] If balance changes are required, add a failing peak/mix assertion before editing trims, then repeat the entire focused suite.
