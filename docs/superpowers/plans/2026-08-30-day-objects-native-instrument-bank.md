# Day Objects Native Instrument Bank Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add an internal-only, auditionable AudioKit instrument bank containing fifteen attributed Synth One-derived tonal voices, a hybrid semantic drum kit, and a compact CC0 felt-piano sampler.

**Architecture:** Keep source conversion and manifests deterministic and testable without an audio device. An AudioKit adapter builds a fixed pool of tonal, percussion, and sampler voices from normalized data; the Day Objects lab gets a manual audition controller only. No transport, progression, recurring Happening scheduler, or day-data mapping is introduced here.

**Tech Stack:** Swift 5, SwiftUI, XCTest, AudioKit 5.7.2, SoundpipeAudioKit 5.7.4, AVFoundation, shell-based pinned asset import, Xcode project resources.

**Spec:** `docs/superpowers/specs/2026-08-30-day-objects-native-instrument-bank-design.md`

## Global Constraints

- Keep every app source in this plan behind `#if DEBUG || INTERNAL_BUILD`; Release must not expose or initialize the lab audio bank.
- Preserve unrelated working-tree changes. Stage only the paths named by the current task.
- Use exact package versions, upstream revisions, licenses, and checksums from this plan. Never add an audio file whose redistribution provenance is missing.
- Audio begins off, never auto-resumes, and always releases voices before engine teardown.
- Allocate bounded pools before start. Do not create nodes in note, chord, hit, or gesture callbacks.
- Run focused tests after each red/green step, then the full Day Objects test set before the final commit.
- Simulator tests prove structure and lifecycle; final gain, transient, and timbre acceptance requires a physical iPhone listening pass.

---

## Task 1: Pin packages and create the licensed resource boundary

**Files:**

- Modify: `Steps4.xcodeproj/project.pbxproj`
- Create: `StepsTrader/Experiments/DayObjects/Sound/Resources/AudioLicenses/AudioKitSynthOne-MIT.txt`
- Create: `StepsTrader/Experiments/DayObjects/Sound/Resources/AudioLicenses/AudioKitCookbook-MIT.txt`
- Create: `StepsTrader/Experiments/DayObjects/Sound/Resources/AudioLicenses/OsirisPiano-CC0-1.0.txt`
- Create: `StepsTrader/Experiments/DayObjects/Sound/Resources/AudioLicenses/SOURCES.json`
- Test: `Steps4Tests/DayObjectsAudioResourceTests.swift`

- [ ] **Step 1: Write a failing package/resource contract test**

Add `DayObjectsAudioResourceTests` that reads the built test bundle and asserts that all three license files and `SOURCES.json` exist. Decode the JSON and assert these exact source pins:

~~~text
AudioKitSynthOne 6466a3715c96b7ecf1dd255a218cbd571408a314
AudioKit/Cookbook c37d41daedf161b47315b7ae24b07f41213b73be
sfzinstruments/Osiris_Piano 18c6afccb60cff458edbf7c394571783e074e1e9
~~~

Run:

~~~bash
xcodebuild test -project Steps4.xcodeproj -scheme Steps4 -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:Steps4Tests/DayObjectsAudioResourceTests
~~~

Expected: FAIL because the resource bundle does not exist.

- [ ] **Step 2: Add exact Swift Package pins**

Add package references and app-target products for:

~~~text
https://github.com/AudioKit/AudioKit.git exact 5.7.2, product AudioKit
https://github.com/AudioKit/SoundpipeAudioKit.git exact 5.7.4, product SoundpipeAudioKit
~~~

Do not add AudioKitUI, AudioKitEX, DunneAudioKit, STKAudioKit, or the legacy Synth One project unless Xcode resolves one transitively.

- [ ] **Step 3: Add licenses and source manifest as Copy Bundle Resources**

Copy the complete upstream license texts. `SOURCES.json` must include project, source URL, revision, license filename, and the exact selected asset/preset paths. Add the files to the app and test bundles so the test reads the same artifact shipped by the internal build.

- [ ] **Step 4: Resolve packages and rerun the test**

Run the focused test, then:

~~~bash
xcodebuild -resolvePackageDependencies -project Steps4.xcodeproj -scheme Steps4
~~~

Expected: PASS and package resolution at exactly 5.7.2/5.7.4.

- [ ] **Step 5: Commit the dependency/resource boundary**

~~~bash
git add Steps4.xcodeproj/project.pbxproj StepsTrader/Experiments/DayObjects/Sound/Resources/AudioLicenses Steps4Tests/DayObjectsAudioResourceTests.swift
git commit -m "build: add Day Objects audio dependencies and licenses"
~~~

## Task 2: Import the exact source assets reproducibly

**Files:**

- Create: `scripts/import_day_objects_audio_assets.sh`
- Create: `StepsTrader/Experiments/DayObjects/Sound/Resources/SynthOnePresets/selected-presets.json`
- Create: `StepsTrader/Experiments/DayObjects/Sound/Resources/Drums/*.wav`
- Create: `StepsTrader/Experiments/DayObjects/Sound/Resources/FeltPiano/*.caf`
- Create: `StepsTrader/Experiments/DayObjects/Sound/Resources/audio-assets-manifest.json`
- Modify: `Steps4.xcodeproj/project.pbxproj`
- Modify: `Steps4Tests/DayObjectsAudioResourceTests.swift`

- [ ] **Step 1: Extend the resource test with the exact inventory**

Assert that the bundle contains one selected Synth One JSON with exactly the fifteen source UIDs from the spec, these drum files, and twelve piano samples:

~~~text
bass_drum_C1.wav
closed_hi_hat_F#1.wav
open_hi_hat_A#1.wav
clap_D#1.wav
snare_D1.wav
cheeb-stick.wav
cheeb-hat.wav
cheeb-ch.wav

felt_C2.caf felt_E2.caf felt_G2.caf
felt_C3.caf felt_E3.caf felt_G3.caf
felt_C4.caf felt_E4.caf felt_G4.caf
felt_C5.caf felt_E5.caf felt_G5.caf
~~~

Assert that every final bundled asset has a SHA-256 and license/source key in `audio-assets-manifest.json`.

Run the focused test. Expected: FAIL on missing assets.

- [ ] **Step 2: Implement a pinned, fail-closed importer**

The script must clone each repository to a `mktemp -d` directory, checkout the exact revision, verify every selected input hash, extract only the fifteen preset records, copy the eight Cookbook samples, convert the twelve FLAC files to mono 44.1-kHz 24-bit CAF with `afconvert`, normalize only by a single declared fixed gain, calculate output SHA-256 values, and write the manifest. Locate Synth One records by the fifteen exact UIDs from the spec and fail unless each UID occurs exactly once. It must abort on revision, input hash, license, conversion, or output mismatch and must never modify files outside the named resource directories.

Use these exact Cookbook paths and source hashes:

| Source path | SHA-256 |
|---|---|
| `Cookbook/CookbookCommon/Sources/CookbookCommon/Samples/bass_drum_C1.wav` | `f682067cb3e717374d27e2c8cdabaa3ea16eb8afe36776f163b46ebed64de5c9` |
| `Cookbook/CookbookCommon/Sources/CookbookCommon/Samples/closed_hi_hat_F#1.wav` | `c9f30ff2b4d73b03f41960e504e03c54e9a59697af666fe4d155bab9cd1ccae6` |
| `Cookbook/CookbookCommon/Sources/CookbookCommon/Samples/open_hi_hat_A#1.wav` | `cde0aec2ca84358067859f52bac7d55b875f30d2baea700923e25e21307803e9` |
| `Cookbook/CookbookCommon/Sources/CookbookCommon/Samples/clap_D#1.wav` | `376429bb81cb48d1f392a11cd066c32ffb7883d445b2488704ea52e46bb08286` |
| `Cookbook/CookbookCommon/Sources/CookbookCommon/Samples/snare_D1.wav` | `d7fa75dff476baaef99de0b251d86c39aa0e0f36a06043db9a97417350fe4439` |
| `Cookbook/Sounds/cheeb-stick.wav` | `2af90d5f8192a71c3caf2746322dee5a593c27256837b0ef7c66e57ec90aa634` |
| `Cookbook/Sounds/cheeb-hat.wav` | `33b9b334fb30d3a467f1c5ff28eb6299f08049cd94627c4cd41aafc8e466ab0d` |
| `Cookbook/Sounds/cheeb-ch.wav` | `6e18c1bd394fe97bea79f0106aa30285d56c16b78fb7ac9311c85fb502bbc106` |

Use these exact Osiris source files from `UC-Sus-noisy/A/`, all velocity layer `vl1`:

| Root | Source SHA-256 |
|---|---|
| C2 | `cce3112e179b2bf20c4b18de67345a4cee8e2f981cdbf58d95e1758d14cc0ef1` |
| E2 | `d52280ab1804cf9ecd1dd93d8fc245a17b801ffdebe0ff47b07d965fb4f5bf45` |
| G2 | `af26a649cf2d3de12cf75ff8d403ede451f5c0c81e4cb0500adabb966b44da28` |
| C3 | `4e509d501311b1fc7e6691cff1127f5a068a2292ec4501f94e68a36183a05e68` |
| E3 | `58c4188910fd6feb1b31561936f146f89f376dfa9d29acfa7e0c574334a97869` |
| G3 | `47a25644da5e4b770fd35ba29e53acded50a267985dad2f0d5e8f5a2698fe6ce` |
| C4 | `f9e1ecef1ae24470796591f09d2d0aed4b320b5a376df8b7abf30c7880628545` |
| E4 | `592a756ccad9242f461a4af0542bc6bfdcbcfb3624e638baa2a0ac15eef773be` |
| G4 | `f66433c9210a9a30544dd9b74c7a6688afc168a6476988b33b6745a21429f7af` |
| C5 | `b402a966e7a9fd5f165d07b92c53d90f06fca9430036c377432d4071de5ae4d5` |
| E5 | `d3f7e471c4b7ad9f45a6aa4451189423eba33d6d849f1a6603a357fa6f201f00` |
| G5 | `f7b14111af1078676f761d6e1ff22ef368baf6b895acbe5cfd1555f74cc84ac2` |

- [ ] **Step 3: Run the importer and add only generated outputs**

Run:

~~~bash
./scripts/import_day_objects_audio_assets.sh
~~~

Inspect the manifest and verify that no upstream repository, `.git` directory, GUI image, PDF, unused preset, or unused piano sample entered the workspace.

- [ ] **Step 4: Add resources to the project and make the test pass**

Add the four resource folders and manifest to Copy Bundle Resources. Rerun `DayObjectsAudioResourceTests`; expected PASS.

- [ ] **Step 5: Commit imported assets and provenance**

~~~bash
git add scripts/import_day_objects_audio_assets.sh StepsTrader/Experiments/DayObjects/Sound/Resources Steps4.xcodeproj/project.pbxproj Steps4Tests/DayObjectsAudioResourceTests.swift
git commit -m "assets: import licensed Day Objects audio bank"
~~~

## Task 3: Define normalized presets and convert Synth One records

**Files:**

- Create: `StepsTrader/Experiments/DayObjects/Sound/Domain/DayObjectsInstrumentID.swift`
- Create: `StepsTrader/Experiments/DayObjects/Sound/Domain/DayObjectsInstrumentManifest.swift`
- Create: `StepsTrader/Experiments/DayObjects/Sound/Domain/NormalizedSynthVoice.swift`
- Create: `StepsTrader/Experiments/DayObjects/Sound/Domain/SynthOnePresetAdapter.swift`
- Test: `Steps4Tests/DayObjectsInstrumentManifestTests.swift`
- Test: `Steps4Tests/SynthOnePresetAdapterTests.swift`

- [ ] **Step 1: Test the public pure model and exact catalog**

Write failing tests for:

~~~swift
struct DayObjectsInstrumentID: RawRepresentable, Hashable, Codable, Sendable {
    let rawValue: String
}

enum DayObjectsInstrumentCategory: String, Codable, CaseIterable, Sendable {
    case pad, pluck, bass, lead, keys, drums, piano
}

struct DayObjectsInstrumentDescriptor: Equatable, Codable, Sendable {
    let id: DayObjectsInstrumentID
    let category: DayObjectsInstrumentCategory
    let displayName: String
    let bankName: String
    let sourceUID: String?
    let referenceMIDI: UInt8
    let auditionChord: [UInt8]
    let outputTrimDB: Double
}
~~~

Assert exactly three unique descriptors in each Synth One tonal category, attribution present, finite trims, and no duplicate stable ID or UID. The complete stable ID -> source UID contract is:

~~~text
pad.interstellar             39529417-FBC1-41D5-B1D1-0DED9E38F164
pad.whispering-sands         96F9F71C-1D6C-41FC-8192-E4B550562357
pad.forgotten-stories        9BF89CC8-5AD5-46D8-9640-C3FE335C65D9
pluck.play-something-sad     E9AFAF33-21A5-4A1B-80BF-74BFB333E86D
pluck.jec-ambient-pizz-2     88335303-C675-4D14-907E-2D80823C2BCA
pluck.spider-filter-pluck    8FC6202C-DAE8-4651-98DE-F3BEBB07E6BF
bass.analog-boom             C2958050-CDCA-4C64-AF92-3217539CE60A
bass.bb-roys-phaser          4131C811-FBB8-4E15-B238-8986645A62D3
bass.jec-hollores-2          FA16AF16-3033-485F-A183-4DAAB7025B52
lead.verbacious              9BDE3DCB-219D-4D70-A067-C1057B557F19
lead.jec-softwah-2           2B6BCC6D-8526-4CAD-8230-EF3C84A26E9F
lead.bb-silver-screen        BB74B6AD-9076-464C-B373-F2E968BBD2BE
keys.maschinenmensch         AA903CDB-938B-4FC7-8E01-050DB95EFDE7
keys.bb-slow-poly            6A4C11CA-2CF9-4153-B5D3-A67F28E465A1
keys.jec-polaroids-2         9F2D32B0-ED71-4127-A4C5-F51209656AF7
~~~

- [ ] **Step 2: Implement the manifest and make catalog tests pass**

Load `selected-presets.json` once outside the scheduling path. Keep the stable IDs exactly as listed in the spec. Expose category filtering without AudioKit types.

- [ ] **Step 3: Test normalization and diagnostics before the adapter**

Define `NormalizedSynthVoice` with two oscillators, sub/noise, amp/filter ADSR, glide, one LFO route, delay, reverb, phaser, autopan, trim, reference note, and audition chord. Write failing tests that feed NaN, infinity, negative durations, excessive feedback, and unsupported source fields. Assert finite clamped output, deterministic defaults, feedback below self-oscillation, and sorted deterministic diagnostics.

- [ ] **Step 4: Implement `SynthOnePresetAdapter`**

Use this pure API:

~~~swift
enum SynthOnePresetAdapter {
    static func convert(_ source: SynthOnePresetRecord) -> SynthOneConversionResult
}

struct SynthOneConversionResult: Equatable, Sendable {
    let voice: NormalizedSynthVoice
    let diagnostics: [SynthOneAdapterDiagnostic]
}
~~~

Explicitly diagnose and ignore arpeggiator/sequencer, hold, custom tuning/MIDI mappings, bit-crush, unsupported FM/modulation routes, compressor internals, and unsupported delay routing. Never map an unsupported number to a semantically unrelated destination.

- [ ] **Step 5: Add a golden conversion test for all fifteen records**

Snapshot stable scalar fields and diagnostic codes into test assertions. Convert the same file twice and assert equality. Expected: PASS.

- [ ] **Step 6: Commit the pure instrument domain**

~~~bash
git add StepsTrader/Experiments/DayObjects/Sound/Domain Steps4Tests/DayObjectsInstrumentManifestTests.swift Steps4Tests/SynthOnePresetAdapterTests.swift Steps4.xcodeproj/project.pbxproj
git commit -m "feat: normalize Synth One voices for Day Objects"
~~~

## Task 4: Build a fixed AudioKit tonal voice pool

**Files:**

- Create: `StepsTrader/Experiments/DayObjects/Sound/Engine/DayObjectsTonalVoice.swift`
- Create: `StepsTrader/Experiments/DayObjects/Sound/Engine/DayObjectsTonalVoicePool.swift`
- Create: `StepsTrader/Experiments/DayObjects/Sound/Engine/DayObjectsAudioParameters.swift`
- Test: `Steps4Tests/DayObjectsTonalVoicePoolTests.swift`

- [ ] **Step 1: Specify the pool through a fake voice test double**

Define a private backend protocol so tests do not start an audio device. Write failing tests for the default six-voice audition pool, oldest non-Lead voice stealing, Lead protection, four-note chord cap, 120-ms preset transition, idempotent release, and no stale gate after 100 preset changes.

- [ ] **Step 2: Implement allocation independently of AudioKit nodes**

Keep allocation state in `DayObjectsTonalVoicePool`; inject a voice factory. A pool owns exactly the capacity supplied before engine start (six for manual audition) and returns typed voice tokens rather than array indexes. Capacity cannot change after preparation; later playback may request several independently named fixed pools before start.

- [ ] **Step 3: Implement the AudioKit graph**

For each voice build two morphing oscillators plus sub/noise into a source mixer, bounded filter branches, amplitude envelope, phaser/autopan, delay/reverb sends, and output trim. Use ramps for frequency, cutoff, gain, effect mix, and preset replacement. Clamp again at the engine boundary.

- [ ] **Step 4: Verify lifecycle and parameter safety**

Run `DayObjectsTonalVoicePoolTests`; add assertions that repeated start/release cycles leave the allocation metrics unchanged and every delay/reverb feedback input is below its declared safety maximum.

- [ ] **Step 5: Commit the tonal engine**

~~~bash
git add StepsTrader/Experiments/DayObjects/Sound/Engine/DayObjectsTonalVoice.swift StepsTrader/Experiments/DayObjects/Sound/Engine/DayObjectsTonalVoicePool.swift StepsTrader/Experiments/DayObjects/Sound/Engine/DayObjectsAudioParameters.swift Steps4Tests/DayObjectsTonalVoicePoolTests.swift Steps4.xcodeproj/project.pbxproj
git commit -m "feat: add fixed Day Objects tonal voice pool"
~~~

## Task 5: Build hybrid semantic drums

**Files:**

- Create: `StepsTrader/Experiments/DayObjects/Sound/Domain/DayObjectsDrumVoice.swift`
- Create: `StepsTrader/Experiments/DayObjects/Sound/Engine/DayObjectsDrumBank.swift`
- Test: `Steps4Tests/DayObjectsDrumBankTests.swift`

- [ ] **Step 1: Write semantic-bank failing tests**

Test this exact inventory:

~~~swift
enum DayObjectsDrumVoice: String, CaseIterable, Sendable {
    case kickSoft, kickFull, hatClosed, hatOpen, shaker
    case clapSoft, stick, organicHigh, organicLow
}
~~~

Assert that every semantic voice resolves to a bounded recipe; `kickSoft` and `kickFull` combine a synthesized sine pitch-drop body with a filtered sample transient; shaker is filtered synthesized noise; missing optional samples disable only their dependent semantic voice or use an explicitly declared fallback.

- [ ] **Step 2: Implement fixed sample pools and synthesized layers**

Preload all eight samples before engine start. Allocate fixed player pools for overlaps. Use small bounded velocity/pitch variation for hats and organic percussion. The main kick path must never contain a saw oscillator, broadband sustained noise, pitch drift, dropout, or unstable delay.

- [ ] **Step 3: Add safety and missing-resource tests**

Inject a resource resolver and verify exact diagnostic IDs, no crash, no silent disabling of unrelated voices, and constant player counts after 1,000 test hits.

- [ ] **Step 4: Commit the drum bank**

~~~bash
git add StepsTrader/Experiments/DayObjects/Sound/Domain/DayObjectsDrumVoice.swift StepsTrader/Experiments/DayObjects/Sound/Engine/DayObjectsDrumBank.swift Steps4Tests/DayObjectsDrumBankTests.swift Steps4.xcodeproj/project.pbxproj
git commit -m "feat: add hybrid Day Objects drum bank"
~~~

## Task 6: Add the compact felt-piano sampler

**Files:**

- Create: `StepsTrader/Experiments/DayObjects/Sound/Domain/FeltPianoManifest.swift`
- Create: `StepsTrader/Experiments/DayObjects/Sound/Engine/DayObjectsFeltPiano.swift`
- Test: `Steps4Tests/DayObjectsFeltPianoTests.swift`

- [ ] **Step 1: Write manifest and key-zone tests**

Decode the twelve samples from `audio-assets-manifest.json`. Assert CC0 provenance, original and edited hashes, root MIDI notes 36/40/43 through 72/76/79, velocity layer 1, non-overlapping nearest-root key zones, and coverage of the playable register C2...B5.

- [ ] **Step 2: Implement the sampler recipe**

Load the compact samples before start, use nearest-root transposition, a soft nonzero attack, bounded release, low-pass shaping, reduced mechanical/noise onset, conservative per-note trim, and shared room/reverb sends. The implementation must fail only the piano role when an asset is missing.

- [ ] **Step 3: Test polyphony and teardown**

Through a fake sampler backend, assert bounded chord polyphony, oldest-note release, no player growth, all-notes-off on stop, and safe handling of missing C4 without disabling tonal Synth One Keys.

- [ ] **Step 4: Commit the felt piano**

~~~bash
git add StepsTrader/Experiments/DayObjects/Sound/Domain/FeltPianoManifest.swift StepsTrader/Experiments/DayObjects/Sound/Engine/DayObjectsFeltPiano.swift Steps4Tests/DayObjectsFeltPianoTests.swift Steps4.xcodeproj/project.pbxproj
git commit -m "feat: add licensed compact felt piano"
~~~

## Task 7: Expose one reusable instrument bank facade

**Files:**

- Create: `StepsTrader/Experiments/DayObjects/Sound/Engine/DayObjectsInstrumentBankProtocol.swift`
- Create: `StepsTrader/Experiments/DayObjects/Sound/Engine/DayObjectsInstrumentBank.swift`
- Test: `Steps4Tests/DayObjectsInstrumentBankTests.swift`

- [ ] **Step 1: Write facade contract tests with fake sub-banks**

Use this boundary. The bank is configured once before start so the later playback phase can request fixed role/world pools without exposing AudioKit nodes:

~~~swift
struct DayObjectsInstrumentBankConfiguration: Equatable, Sendable {
    let tonalPools: [DayObjectsTonalPoolSpecification]
    let pianoVoiceCount: Int
    let drumOverlapCounts: [DayObjectsDrumVoice: Int]
}

protocol DayObjectsTonalVoicePoolProtocol: AnyObject {
    var metrics: DayObjectsTonalPoolMetrics { get }
    func prepareInstrument(_ id: DayObjectsInstrumentID) throws
    func noteOn(_ request: DayObjectsTonalNoteRequest) -> DayObjectsVoiceToken?
    func update(_ token: DayObjectsVoiceToken, with update: DayObjectsVoiceUpdate)
    func noteOff(_ token: DayObjectsVoiceToken)
    func releaseAll()
}

@MainActor
protocol DayObjectsInstrumentBankProtocol: AnyObject {
    var descriptors: [DayObjectsInstrumentDescriptor] { get }
    var metrics: DayObjectsInstrumentBankMetrics { get }
    var drums: DayObjectsDrumBankProtocol { get }
    var piano: DayObjectsPianoPoolProtocol { get }

    func prepare(configuration: DayObjectsInstrumentBankConfiguration) throws
    func tonalPool(named id: String) throws -> DayObjectsTonalVoicePoolProtocol
    func start() throws
    func stop() async
    func releaseAll()
}
~~~

`DayObjectsTonalNoteRequest` contains instrument ID, MIDI note, velocity, role, optional bounded envelope variant, pan, and effect sends. `DayObjectsVoiceUpdate` contains only ramped pitch, cutoff, expression, pan, and sends. Drum and piano protocols expose equivalent typed trigger/release calls. Assert idempotent preparation for an equal configuration, rejection of configuration changes after preparation, category-command validation, fixed metrics, conservative bus gains, and one final peak limiter.

- [ ] **Step 2: Assemble the real graph once**

Join configured tonal pools plus drum and piano sub-banks into separate tonal/drum buses, shared bounded spatial effects, master trim at or below -6 dB, and final limiter. JSON decoding, sample loading, and node allocation happen in `prepare(configuration:)`, never in trigger/update calls.

- [ ] **Step 3: Make failure atomic**

If preparation or engine start fails, release partial state, return an exact diagnostic, keep the bank retryable, and do not leave an active audio session. Verify with injected failures at each preparation stage.

- [ ] **Step 4: Commit the facade**

~~~bash
git add StepsTrader/Experiments/DayObjects/Sound/Engine/DayObjectsInstrumentBankProtocol.swift StepsTrader/Experiments/DayObjects/Sound/Engine/DayObjectsInstrumentBank.swift Steps4Tests/DayObjectsInstrumentBankTests.swift Steps4.xcodeproj/project.pbxproj
git commit -m "feat: assemble Day Objects instrument bank"
~~~

## Task 8: Add manual audition controls to Day Objects Lab

**Files:**

- Create: `StepsTrader/Experiments/DayObjects/Sound/Lab/DayObjectsInstrumentAuditionController.swift`
- Create: `StepsTrader/Experiments/DayObjects/Sound/Lab/DayObjectsInstrumentAuditionView.swift`
- Modify: `StepsTrader/Experiments/DayObjects/DayObjectsLabView.swift`
- Modify: `StepsTrader/Experiments/DayObjects/DayObjectTypes.swift`
- Modify: `Steps4Tests/DayObjectSceneTests.swift`
- Modify: `Steps4UITests/DayObjectsLabUITests.swift`
- Test: `Steps4Tests/DayObjectsInstrumentAuditionControllerTests.swift`

- [ ] **Step 1: Write controller tests against a fake bank**

Assert initial Sound off; state transitions `off -> starting -> on` and `starting -> error -> retry`; Note/Chord/Hit dispatch only for valid categories; changing preset releases old gates; stop/disappear/interruption share one idempotent stop path; no foreground auto-resume.

- [ ] **Step 2: Implement the controller without SwiftUI or Metal ownership**

The controller owns the bank and audition state. It configures `AVAudioSession` as `.playback` only after explicit Sound On and deactivates with `.notifyOthersOnDeactivation` after teardown.

- [ ] **Step 3: Write failing UI assertions**

Update the lab UI test to assert accessibility identifiers for category, preset, Sound, Note, Chord, Hit, attribution, and diagnostics. Assert Sound starts off, tonal categories show exactly three presets, and controls remain outside the Lead-capable canvas region.

- [ ] **Step 4: Add the collapsed Instrument audition UI**

Categories are Pad, Pluck, Bass, Lead, Keys, Drums, Piano. Show bank/source attribution and debug diagnostics. Enable Note/Chord/Hit only for meaningful categories. Keep existing visual controls and Grid behavior intact; this plan does not turn canvas movement into Lead playback.

- [ ] **Step 5: Run focused unit and UI tests**

~~~bash
xcodebuild test -project Steps4.xcodeproj -scheme Steps4 -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:Steps4Tests/DayObjectsInstrumentAuditionControllerTests -only-testing:Steps4Tests/DayObjectSceneTests
xcodebuild test -project Steps4.xcodeproj -scheme Steps4 -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:Steps4UITests/DayObjectsLabUITests
~~~

Expected: PASS; Sound remains explicitly off on every fresh open.

- [ ] **Step 6: Commit the audition lab**

~~~bash
git add StepsTrader/Experiments/DayObjects/Sound/Lab StepsTrader/Experiments/DayObjects/DayObjectsLabView.swift StepsTrader/Experiments/DayObjects/DayObjectTypes.swift Steps4Tests/DayObjectsInstrumentAuditionControllerTests.swift Steps4Tests/DayObjectSceneTests.swift Steps4UITests/DayObjectsLabUITests.swift Steps4.xcodeproj/project.pbxproj
git commit -m "feat: add Day Objects instrument audition lab"
~~~

## Task 9: Calibrate, verify, and document the bank handoff

**Files:**

- Modify: `StepsTrader/Experiments/DayObjects/Sound/Resources/audio-assets-manifest.json`
- Create: `docs/day-objects-instrument-bank-listening-checklist.md`
- Modify: `docs/superpowers/specs/2026-08-30-day-objects-native-instrument-bank-design.md`

- [ ] **Step 1: Run the complete automated verification**

~~~bash
xcodebuild test -project Steps4.xcodeproj -scheme Steps4 -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:Steps4Tests/DayObjectsAudioResourceTests -only-testing:Steps4Tests/DayObjectsInstrumentManifestTests -only-testing:Steps4Tests/SynthOnePresetAdapterTests -only-testing:Steps4Tests/DayObjectsTonalVoicePoolTests -only-testing:Steps4Tests/DayObjectsDrumBankTests -only-testing:Steps4Tests/DayObjectsFeltPianoTests -only-testing:Steps4Tests/DayObjectsInstrumentBankTests -only-testing:Steps4Tests/DayObjectsInstrumentAuditionControllerTests -only-testing:Steps4Tests/DayObjectSceneTests
git diff --check
~~~

Expected: PASS and no whitespace errors.

- [ ] **Step 2: Perform the physical-iPhone listening matrix**

Audition all fifteen tonal candidates, nine semantic drum voices, and piano on headphones and speaker. Record measured/accepted `outputTrimDB` values in the manifest. Reject clicking, stuck notes, harsh fast Lead motion, eight-bit percussion character, weak kick body, and Keys/piano masking pads.

- [ ] **Step 3: Verify lifecycle loops**

On device repeat Sound On/Off 25 times, background/foreground 10 times, interruption once, and rapid preset switching 100 times. Confirm fixed metrics, no auto-resume, no stuck sound, and no growing task/node count.

- [ ] **Step 4: Record exact results, not aspirational claims**

Check off only completed listening rows. If a voice fails, keep its issue open and do not mark the spec accepted. Update the spec with the final asset decision and measured trims.

- [ ] **Step 5: Commit the verified bank**

~~~bash
git add StepsTrader/Experiments/DayObjects/Sound/Resources/audio-assets-manifest.json docs/day-objects-instrument-bank-listening-checklist.md docs/superpowers/specs/2026-08-30-day-objects-native-instrument-bank-design.md
git commit -m "test: verify Day Objects instrument bank"
~~~

## Completion Gate

Proceed to the Music Director only when the fifteen tonal voices, nine semantic drum voices, and compliant felt piano are discoverable through `DayObjectsInstrumentBankProtocol`, all automated tests pass, and the physical-iPhone checklist contains no unresolved blocker. Automatic music must still be absent at this boundary.
