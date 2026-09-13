# Day Objects Four Sound Worlds Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (- [ ]) syntax for tracking.

**Goal:** Build four recognizably different Canvas sound worlds with three moods each, a unified visual/music Remix, curated synth combinations, automated mix checks, and a numbered 12-render audition pack.

**Architecture:** Keep one live mobile playback graph and derive world, mood, guest, art, and music deterministically from one Remix seed. Load portable synth recipes and compatibility groups from versioned JSON into the existing planners and instrument bank. Persist the unified Remix identity on DayCanvas and render acceptance audio through the real AVAudioEngine graph.

**Tech Stack:** Swift, SwiftUI, AVFAudio manual rendering, XCTest, versioned JSON resources, the existing AudioKit-based tonal engine, and the existing happening sample bank.

**Spec:** docs/superpowers/specs/2026-09-06-day-objects-four-sound-worlds-design.md

## Global Constraints

- Audio remains under DEBUG || INTERNAL_BUILD.
- Do not ship Synth One, Ableton, VST, Audio Unit, or an offline-only DSP dependency.
- Preserve mappings: steps → rhythm/bass, sleep → harmony, happenings → sparse identities, touch → lead, spent colors → bounded glitch.
- Preserve health values, happening identities, and the ten-happening maximum across Remix.
- One seed must reproduce art, world, mood, harmony, instruments, and schedules.
- Keep one complete mobile playback world active, never four simultaneous graphs.
- Guest probability is 15%; a guest must be adjacent and may occupy at most one non-foundational role.
- Accepted previews must use only processing reproducible by the iOS runtime.
- Generated happening audio remains capped at 4.5 seconds before allocation.
- If asset Python is touched: one process, 500 MB RSS, 60 seconds, no automatic retry after a stop.
- Generated audition WAV files stay untracked; commit their manifest and report.

---

### Task 1: Four-world and three-mood domain

**Files:**
- Create: StepsTrader/Experiments/DayObjects/Sound/Director/DayObjectsSoundWorld.swift
- Create: StepsTrader/Experiments/DayObjects/Sound/Director/DayObjectsSoundMood.swift
- Create: StepsTrader/Experiments/DayObjects/Sound/Director/DayObjectsWorldSelector.swift
- Modify: StepsTrader/Experiments/DayObjects/Sound/Director/DayMusicPlan.swift
- Modify: StepsTrader/Experiments/DayObjects/Sound/Director/MusicSeedDomain.swift
- Modify: StepsTrader/Experiments/DayObjects/Sound/Playback/DayObjectsLabMusicState.swift
- Modify: Steps4.xcodeproj/project.pbxproj
- Test: Steps4Tests/DayObjectsWorldSelectorTests.swift
- Test: Steps4Tests/DayMusicPlanSnapshotTests.swift

**Interfaces:**
- Produces DayObjectsSoundWorld, DayObjectsSoundMood, DayObjectsWorldSelection.
- Produces DayObjectsWorldSelector.makeSelection(remixSeed:forcedWorld:forcedMood:).

- [ ] **Step 1: Write failing domain and determinism tests**

    func testWorldAndMoodCasesStayStable() {
        XCTAssertEqual(DayObjectsSoundWorld.allCases, [
            .feltAndWood, .livingField, .metalAndCurrent, .electricDream,
        ])
        XCTAssertEqual(DayObjectsSoundMood.allCases, [.sparse, .moving, .strange])
        XCTAssertEqual(DayObjectsSoundWorld.feltAndWood.displayName, "Acoustic Oddities")
        XCTAssertEqual(DayObjectsSoundWorld.metalAndCurrent.displayName, "Industrial Ritual")
    }

    func testSelectionIsDeterministicAndGuestIsAdjacent() {
        for seed in UInt64(0)..<512 {
            let value = DayObjectsWorldSelector.makeSelection(remixSeed: seed)
            XCTAssertEqual(value, DayObjectsWorldSelector.makeSelection(remixSeed: seed))
            XCTAssertTrue(value.guestWorld.map(value.world.guestNeighbors.contains) ?? true)
        }
    }

- [ ] **Step 2: Run RED**

    xcodebuild test -quiet -project Steps4.xcodeproj -scheme Steps4 \
      -destination 'platform=iOS Simulator,name=iPhone 16e' \
      -only-testing:Steps4Tests/DayObjectsWorldSelectorTests

Expected: compile failure because the mood and selector do not exist.

- [ ] **Step 3: Implement the domain**

    enum DayObjectsSoundWorld: String, Codable, CaseIterable, Sendable {
        case feltAndWood, livingField, metalAndCurrent, electricDream
    }

    enum DayObjectsSoundMood: String, Codable, CaseIterable, Sendable {
        case sparse, moving, strange
    }

    struct DayObjectsWorldSelection: Equatable, Codable, Sendable {
        let world: DayObjectsSoundWorld
        let mood: DayObjectsSoundMood
        let guestWorld: DayObjectsSoundWorld?
    }

Keep feltAndWood and metalAndCurrent raw values for saved-state compatibility. Display them as Acoustic Oddities and Industrial Ritual. Define neighbors exactly as Acoustic ↔ Living, Living ↔ Electric, Electric ↔ Industrial, and Industrial ↔ Acoustic. Use independent seed domains world.style, world.mood, and world.guest. Guest chance is exactly 0.15.

Move the old enum out of DayMusicPlan.swift. Add mood and guestWorld to DayMusicPlan and DayObjectsLabMusicState; legacy entry points default to moving and nil.

- [ ] **Step 4: Run GREEN**

Run the Step 2 command plus DayMusicPlanSnapshotTests. Expect all tests to pass with legacy snapshots unchanged.

- [ ] **Step 5: Commit**

    git add StepsTrader/Experiments/DayObjects/Sound/Director \
      StepsTrader/Experiments/DayObjects/Sound/Playback/DayObjectsLabMusicState.swift \
      Steps4Tests/DayObjectsWorldSelectorTests.swift Steps4Tests/DayMusicPlanSnapshotTests.swift \
      Steps4.xcodeproj/project.pbxproj
    git commit -m "feat: define four day objects sound worlds"

### Task 2: Portable synth recipes and compatibility groups

**Files:**
- Create: StepsTrader/Experiments/DayObjects/Sound/Domain/DayObjectsSynthRecipe.swift
- Create: StepsTrader/Experiments/DayObjects/Sound/Domain/DayObjectsSoundWorldCatalog.swift
- Create: StepsTrader/Experiments/DayObjects/Sound/Resources/SoundWorlds/synth-recipes-v1.json
- Create: StepsTrader/Experiments/DayObjects/Sound/Resources/SoundWorlds/world-groups-v1.json
- Modify: StepsTrader/Experiments/DayObjects/Sound/Domain/DayObjectsInstrumentManifest.swift
- Modify: StepsTrader/Experiments/DayObjects/Sound/Domain/SynthOnePresetAdapter.swift
- Modify: StepsTrader/Experiments/DayObjects/Sound/Engine/DayObjectsInstrumentBank.swift
- Modify: Steps4.xcodeproj/project.pbxproj
- Test: Steps4Tests/DayObjectsSoundWorldCatalogTests.swift
- Test: Steps4Tests/SynthOnePresetAdapterTests.swift
- Test: Steps4Tests/DayObjectsInstrumentBankTests.swift

**Interfaces:**
- Produces DayObjectsSoundWorldCatalog.load(from:).
- Produces DayObjectsSynthRecipe.resolvedVoice(mood:sourceVoices:).
- Produces DayObjectsSynthRecipe.fingerprint(mood:sourceVoices:) as a canonical
  SHA-256 of all resolved NormalizedSynthVoice scalar fields.
- Produces DayObjectsCompatibilityGroup for Tasks 3 and 4.

The catalog contains four families per role and world:

| World | Harmony | Bass | Lead |
|---|---|---|---|
| Acoustic | felt-haze, muted-strings, prepared-mallet, air-reed | round-felt-sub, hollow-wood, muted-string, soft-reed | breath-reed, tape-whistle, bowed-thread, soft-wah |
| Living | wind-canopy, water-drone, moss-choir, bell-mist | earth-sub, root-pulse, tide-bed, hollow-stone | bird-reed, leaf-flute, dew-bell, water-whistle |
| Industrial | bowed-steel, machine-choir, current-drone, cold-plate | deep-current, bassliner, low-motor, sine-foundry | silver-wire, diode-cry, current-needle, resonant-metal |
| Electric | analog-cloud, neon-poly, fm-haze, arpeggio-bed | round-analog, electric-pulse, fm-sub, velvet-sequence | verbacious, prism-fm, soft-sync, neon-wah |

- [ ] **Step 1: Write failing catalog tests**

    func testCatalogHasFourFamiliesPerWorldAndRole() throws {
        let catalog = try DayObjectsSoundWorldCatalog.load(from: Bundle(for: type(of: self)))
        for world in DayObjectsSoundWorld.allCases {
            for role in DayObjectsSynthRole.allCases {
                XCTAssertEqual(catalog.recipes(world: world, role: role).count, 4)
            }
        }
    }

    func testRecipesResolveToDistinctFiniteVoices() throws {
        let catalog = try DayObjectsSoundWorldCatalog.load(from: Bundle(for: type(of: self)))
        try catalog.validate()
        for world in DayObjectsSoundWorld.allCases {
            for role in DayObjectsSynthRole.allCases {
                let voices = try catalog.resolvedVoices(world: world, role: role)
                XCTAssertEqual(Set(voices.map(\.stableFingerprint)).count, 4)
            }
        }
    }

- [ ] **Step 2: Run RED**

    xcodebuild test -quiet -project Steps4.xcodeproj -scheme Steps4 \
      -destination 'platform=iOS Simulator,name=iPhone 16e' \
      -only-testing:Steps4Tests/DayObjectsSoundWorldCatalogTests

Expected: missing catalog types/resources.

- [ ] **Step 3: Implement the recipe schema**

    enum DayObjectsSynthRole: String, Codable, CaseIterable, Sendable {
        case harmony, bass, lead
    }

    struct DayObjectsSynthPatch: Codable, Equatable, Sendable {
        let oscillator1WaveOffset: Double
        let oscillator2WaveOffset: Double
        let oscillatorBalanceOffset: Double
        let subLevelOffset: Double
        let noiseLevelOffset: Double
        let cutoffMultiplier: Double
        let resonanceOffset: Double
        let attackMultiplier: Double
        let releaseMultiplier: Double
        let lfoRateMultiplier: Double
        let lfoDepthMultiplier: Double
        let delayMixOffset: Double
        let reverbMixOffset: Double
    }

    struct DayObjectsSynthRecipe: Codable, Equatable, Sendable {
        let id: DayObjectsInstrumentID
        let world: DayObjectsSoundWorld
        let role: DayObjectsSynthRole
        let family: String
        let sourceInstrumentID: DayObjectsInstrumentID
        let basePatch: DayObjectsSynthPatch
        let moodPatches: [DayObjectsMoodPatch]
        let referenceMIDI: UInt8
        let outputTrimDB: Double
    }

    struct DayObjectsMoodPatch: Codable, Equatable, Sendable {
        let mood: DayObjectsSoundMood
        let patch: DayObjectsSynthPatch
    }

    struct DayObjectsCompatibilityGroup: Codable, Equatable, Sendable {
        let id: String
        let world: DayObjectsSoundWorld
        let mood: DayObjectsSoundMood
        let harmonyRecipeIDs: [DayObjectsInstrumentID]
        let bassRecipeIDs: [DayObjectsInstrumentID]
        let leadRecipeIDs: [DayObjectsInstrumentID]
        let drumKitID: String
        let happeningRecipeIDs: [HappeningSoundRecipeID]
        let guestRecipeIDs: [DayObjectsInstrumentID]
    }

Reject schema versions other than 1, duplicate IDs, missing mood patches, unknown source instruments, non-finite values, trims outside -30...6 dB, missing references, or more than one guest.
Implement stableFingerprint by writing every resolved oscillator, envelope,
filter, LFO, effect, and gain scalar in declaration order as little-endian
Float64 bytes and hashing them with CryptoKit SHA256.

- [ ] **Step 4: Populate the JSON tables**

Create 48 base recipes using the exact family IDs above. Each points to one of the 16 licensed selected preset records, but oscillator, envelope, filter, LFO, noise/sub balance, and sends must create a distinct normalized voice. Add 12 world/mood groups and these kit IDs:

    acoustic.skin-and-wood, acoustic.brushed-room, acoustic.prepared-table
    living.seed-shaker, living.rain-pulse, living.stone-breath
    industrial.plate-and-piston, industrial.foundry-pulse, industrial.wire-ritual
    electric.soft-machine, electric.neon-drum, electric.circuit-dust

- [ ] **Step 5: Load recipes into the existing instrument bank**

Convert the 16 source records once, apply recipe/mood patches, clamp with DayObjectsAudioParameters.clamped, and add recipe IDs to the existing voice dictionary. Expand descriptors from recipe metadata. Do not create another engine, graph, or pool.

- [ ] **Step 6: Run GREEN**

Run DayObjectsSoundWorldCatalogTests, SynthOnePresetAdapterTests, and DayObjectsInstrumentBankTests. Expect 48 recipes, 12 valid groups, and distinct within-world role fingerprints.

- [ ] **Step 7: Commit**

    git add StepsTrader/Experiments/DayObjects/Sound/Domain \
      StepsTrader/Experiments/DayObjects/Sound/Resources/SoundWorlds \
      StepsTrader/Experiments/DayObjects/Sound/Engine/DayObjectsInstrumentBank.swift \
      Steps4Tests/DayObjectsSoundWorldCatalogTests.swift \
      Steps4Tests/SynthOnePresetAdapterTests.swift Steps4Tests/DayObjectsInstrumentBankTests.swift \
      Steps4.xcodeproj/project.pbxproj
    git commit -m "feat: add portable sound world synth catalog"

### Task 3: World-specific harmony and voicing

**Files:**
- Create: StepsTrader/Experiments/DayObjects/Sound/Director/DayObjectsHarmonyGrammar.swift
- Modify: StepsTrader/Experiments/DayObjects/Sound/Director/TonalWorldPlan.swift
- Modify: StepsTrader/Experiments/DayObjects/Sound/Director/TonalWorldPlanner.swift
- Modify: StepsTrader/Experiments/DayObjects/Sound/Director/AmbientVoiceLeading.swift
- Modify: StepsTrader/Experiments/DayObjects/Sound/Director/HarmonyPlanner.swift
- Modify: StepsTrader/Experiments/DayObjects/Sound/Director/DeterministicMusicDirector.swift
- Modify: Steps4.xcodeproj/project.pbxproj
- Test: Steps4Tests/TonalWorldPlannerTests.swift
- Test: Steps4Tests/AmbientVoiceLeadingTests.swift
- Test: Steps4Tests/HarmonyPlannerTests.swift
- Test: Steps4Tests/DeterministicMusicDirectorTests.swift

**Interfaces:**
- Produces DayObjectsHarmonyGrammar.for(world:mood:).
- Produces TonalWorldPlanner.makePlan(input:remixSeed:world:mood:).
- Adds TonalWorldPlan.musicalFingerprint, built from mode, modal degrees,
  voiced MIDI notes, and duration bars.

- [ ] **Step 1: Write failing contrast and monotonic sleep tests**

    func testEqualInputWorldsDifferInProgressionOrVoicing() {
        let plans = DayObjectsSoundWorld.allCases.map {
            makeTonalPlan(world: $0, mood: .moving, seed: 77, sleep: 1)
        }
        XCTAssertEqual(Set(plans.map(\.musicalFingerprint)).count, 4)
    }

    func testSleepStillAddsInformationForEveryWorldAndMood() {
        for world in DayObjectsSoundWorld.allCases {
            for mood in DayObjectsSoundMood.allCases {
                XCTAssertGreaterThan(
                    makeHarmony(world, mood, sleep: 1).harmonicInformationScore,
                    makeHarmony(world, mood, sleep: 0.2).harmonicInformationScore
                )
            }
        }
    }

- [ ] **Step 2: Run RED**

Run TonalWorldPlannerTests, AmbientVoiceLeadingTests, HarmonyPlannerTests, and DeterministicMusicDirectorTests. Expect missing world/mood arguments.

- [ ] **Step 3: Implement harmonic grammar**

    struct DayObjectsHarmonyGrammar: Equatable, Sendable {
        let allowedModes: [DayMusicMode]
        let progressionTemplates: [[Int]]
        let allowedExtensions: [Int]
        let register: ClosedRange<UInt8>
        let maximumChordTones: Int
        let cycleBarChoices: [Int]
    }

Acoustic uses Dorian/Aeolian suspended close voicings and 12/16 bars. Living uses pentatonic/Dorian open fifths/sixths and favors 16 bars. Industrial uses Aeolian/Dorian low drones, fifths, and restrained upper minor seconds over 8/12 bars. Electric uses Mixolydian/Dorian/pentatonic sevenths/ninths and moving inversions over 8/12 bars. Mood orders templates and durations; sleep still determines chord count and role activation.

- [ ] **Step 4: Run GREEN**

Run the Step 2 suites. Expect deterministic fingerprints, four-way contrast, and monotonic sleep behavior.

- [ ] **Step 5: Commit**

    git add StepsTrader/Experiments/DayObjects/Sound/Director \
      Steps4Tests/TonalWorldPlannerTests.swift Steps4Tests/AmbientVoiceLeadingTests.swift \
      Steps4Tests/HarmonyPlannerTests.swift Steps4Tests/DeterministicMusicDirectorTests.swift \
      Steps4.xcodeproj/project.pbxproj
    git commit -m "feat: give sound worlds distinct harmony grammar"

### Task 4: World/mood arrangement and role routing

**Files:**
- Create: StepsTrader/Experiments/DayObjects/Sound/Director/DayObjectsArrangementProfile.swift
- Modify: StepsTrader/Experiments/DayObjects/Sound/Director/GroovePlanner.swift
- Modify: StepsTrader/Experiments/DayObjects/Sound/Director/RhythmPlan.swift
- Modify: StepsTrader/Experiments/DayObjects/Sound/Director/RhythmPlanner.swift
- Modify: StepsTrader/Experiments/DayObjects/Sound/Director/BassPlanner.swift
- Modify: StepsTrader/Experiments/DayObjects/Sound/Director/HarmonyPlanner.swift
- Modify: StepsTrader/Experiments/DayObjects/Sound/Director/LeadPlanner.swift
- Modify: StepsTrader/Experiments/DayObjects/Sound/Director/HappeningMusicPlanner.swift
- Modify: StepsTrader/Experiments/DayObjects/Sound/Director/LayerMixPlanner.swift
- Modify: StepsTrader/Experiments/DayObjects/Sound/Director/DeterministicMusicDirector.swift
- Modify: StepsTrader/Experiments/DayObjects/Sound/Engine/DayObjectsDrumBank.swift
- Test: Steps4Tests/GroovePlannerTests.swift
- Test: Steps4Tests/RhythmPlannerTests.swift
- Test: Steps4Tests/BassPlannerTests.swift
- Test: Steps4Tests/HarmonyPlannerTests.swift
- Test: Steps4Tests/LeadPlannerTests.swift
- Test: Steps4Tests/HappeningMusicPlannerTests.swift
- Test: Steps4Tests/LayerMixPlannerTests.swift
- Test: Steps4Tests/DayMusicPlanDifferTests.swift

**Interfaces:**
- Consumes world selection, compatibility group, synth recipes, tonal plan, and health progress.
- Produces existing layer plans with distinct instrument IDs, kit IDs, densities, and processing.

- [ ] **Step 1: Write failing layer-density and guest tests**

    func testMoodLayerLimits() {
        XCTAssertTrue(makePlan(.sparse).activeLayerRoleCount <= 4)
        XCTAssertTrue((5...6).contains(makePlan(.moving).activeLayerRoleCount))
        XCTAssertTrue(makePlan(.strange).activeLayerRoleCount <= 7)
    }

    func testWorldsChooseDifferentSourcesAtEqualInput() {
        let plans = DayObjectsSoundWorld.allCases.map { makePlan(world: $0) }
        XCTAssertEqual(Set(plans.map(\.lead.instrumentID)).count, 4)
        XCTAssertEqual(Set(plans.map(\.rhythm.kitID)).count, 4)
    }

    func testGuestNeverReplacesBassAndPrimaryHarmonyTogether() {
        for seed in UInt64(0)..<1024 {
            let plan = makePlan(seed: seed)
            XCTAssertFalse(plan.bassIsGuest && plan.primaryHarmonyIsGuest)
        }
    }

- [ ] **Step 2: Run RED**

Run all eight affected test suites. Expect missing kit, density, and compatibility routing.

- [ ] **Step 3: Implement profiles and routing**

    struct DayObjectsArrangementProfile: Equatable, Sendable {
        let activeRoleRange: ClosedRange<Int>
        let rhythmicDensityMultiplier: Double
        let happeningDensityMultiplier: Double
        let maximumConcurrentHappenings: Int
        let harmonyReleaseMultiplier: Double
        let bassArticulationWeights: [BassArticulation: Double]
        let leadGestureSmoothingMultiplier: Double
    }

Use sparse 3...4, moving 5...6, strange 5...7. Apply world behavior only after health normalization: Living is sparsest with longest tails, Industrial has the clearest pulse, Acoustic has most timing humanization, Electric has the highest arpeggio probability. Mood cannot activate a layer below its health threshold.

Add kitID to RhythmPlan and resolve it inside the existing drum bank. Select role recipe IDs from one compatibility group. Restrict happenings to that group, preserve stable IDs, and retain current concurrency safeguards.

Add these diagnostics to DayMusicPlan so tests and the export manifest do not
infer ownership from string prefixes:

    var activeLayerRoleCount: Int {
        var count = rhythm.rhythmicRichness > 0 ? 1 : 0
        count += bass == nil ? 0 : 1
        count += harmony.activeRoleCount
        count += happenings.isEmpty ? 0 : 1
        count += 1
        return count
    }
    var bassIsGuest: Bool { bass.map { guestInstrumentIDs.contains($0.instrumentID) } ?? false }
    var primaryHarmonyIsGuest: Bool {
        guard let role = harmony.role(for: .primaryPad) else { return false }
        guard case let .tonal(id) = role.instrumentTarget else { return false }
        return guestInstrumentIDs.contains(id)
    }
    let guestInstrumentIDs: Set<DayObjectsInstrumentID>

activeLayerRoleCount counts audible rhythm, bass, each active harmony role, the
aggregate happening layer, and lead, then clamps only through the selected
arrangement profile.

- [ ] **Step 4: Run GREEN**

Run the eight planner suites plus DayObjectsMusicPlaybackEngineTests. Expect world/mood/kit changes to be structural and health-only updates to keep existing transitions.

- [ ] **Step 5: Commit**

    git add StepsTrader/Experiments/DayObjects/Sound/Director \
      StepsTrader/Experiments/DayObjects/Sound/Engine/DayObjectsDrumBank.swift \
      Steps4Tests/GroovePlannerTests.swift Steps4Tests/RhythmPlannerTests.swift \
      Steps4Tests/BassPlannerTests.swift Steps4Tests/HarmonyPlannerTests.swift \
      Steps4Tests/LeadPlannerTests.swift Steps4Tests/HappeningMusicPlannerTests.swift \
      Steps4Tests/LayerMixPlannerTests.swift Steps4Tests/DayMusicPlanDifferTests.swift
    git commit -m "feat: arrange distinct sound world moods"

### Task 5: Unified visual and musical Remix

**Files:**
- Create: StepsTrader/Models/CanvasUnifiedRemix.swift
- Modify: StepsTrader/Models/DayCanvas.swift
- Modify: StepsTrader/Models/CanvasRemix.swift
- Modify: StepsTrader/Models/DayComposition.swift
- Modify: StepsTrader/Experiments/DayObjects/Sound/Lab/DayObjectsMusicLabController.swift
- Modify: StepsTrader/Views/GalleryView.swift
- Modify: StepsTrader/Views/Gallery/CanvasFullScreenDock.swift
- Test: Steps4Tests/CanvasRemixTests.swift
- Test: Steps4Tests/CanvasPersistenceRegressionTests.swift
- Test: Steps4Tests/DayObjectsMusicLabControllerTests.swift
- Test: Steps4Tests/CanvasPresentationStateTests.swift

**Interfaces:**
- Produces CanvasUnifiedRemix.next(canvas:allowedShapes:at:).
- Produces CanvasUnifiedRemix.restore(_:into:).

- [ ] **Step 1: Write failing atomic Remix tests**

    func testUnifiedRemixPreservesDataButRerollsArtAndMusic() {
        let before = makeCanvas()
        let result = CanvasUnifiedRemix.next(canvas: before, at: fixedDate)
        XCTAssertEqual(result.canvas.stepsPoints, before.stepsPoints)
        XCTAssertEqual(result.canvas.sleepPoints, before.sleepPoints)
        XCTAssertEqual(result.canvas.inkSpent, before.inkSpent)
        XCTAssertEqual(result.canvas.elements.map(\.id), before.elements.map(\.id))
        XCTAssertNotEqual(result.canvas.elements.map(\.basePosition), before.elements.map(\.basePosition))
        XCTAssertEqual(
            result.musicSelection,
            DayObjectsWorldSelector.makeSelection(remixSeed: result.seed)
        )
    }

    func testRemixControlIsFullScreenOnly() {
        XCTAssertFalse(CanvasFullScreenRemixPresentation.isVisible(in: .canvas))
        XCTAssertTrue(CanvasFullScreenRemixPresentation.isVisible(in: .fullScreen))
        XCTAssertFalse(CanvasFullScreenRemixPresentation.isVisible(in: .editing))
    }

- [ ] **Step 2: Run RED**

Run CanvasRemixTests, CanvasPersistenceRegressionTests, DayObjectsMusicLabControllerTests, and CanvasPresentationStateTests. Expect failure because art/music remixes are separate.

- [ ] **Step 3: Persist backward-compatible identity**

Add optional remixSeed, soundWorldRaw, soundMoodRaw, and guestSoundWorldRaw fields to DayCanvas. Missing fields resolve from the legacy day seed. Add remixSeed to DayComposition.forDay. Derive palette, background, material, position, shape, size, and motion from stable seed subdomains. Preserve element IDs, option IDs, labels, dates, and all day metrics.

- [ ] **Step 4: Add atomic snapshot and coordinator**

    struct CanvasRemixSnapshot {
        let seed: UInt64
        let elements: [CanvasElement]
        let gradientStyle: String?
        let gradientPalette: String?
        let overlayStyle: String?
        let textureRaw: String?
        let soundWorldRaw: String?
        let soundMoodRaw: String?
        let guestSoundWorldRaw: String?
    }

    struct CanvasUnifiedRemixResult {
        let canvas: DayCanvas
        let previous: CanvasRemixSnapshot
        let musicSelection: DayObjectsWorldSelection
        let seed: UInt64
    }

GalleryView owns at most 10 snapshots. One action creates the next seed, replaces/persists DayCanvas once, and calls musicController.applyRemix(seed:selection:). Undo restores/persists one snapshot and applies its musical selection.

- [ ] **Step 5: Integrate the full-screen UI**

Add onRemix, onUndoRemix, and canUndoRemix to CanvasFullScreenDock. Remove the temporary world menu and music-only Remix controls from wideCanvasOverlay. Keep Sound separate. Do not add Remix to collapsed Canvas. Show the world/mood name for two seconds after Remix.

    enum CanvasFullScreenRemixPresentation {
        static func isVisible(in state: CanvasPresentationState) -> Bool {
            state == .fullScreen
        }
    }

- [ ] **Step 6: Run GREEN**

Run the Step 2 suites. Expect legacy fixtures to decode and atomic Remix/Undo to pass.

- [ ] **Step 7: Commit**

    git add StepsTrader/Models/CanvasUnifiedRemix.swift StepsTrader/Models/DayCanvas.swift \
      StepsTrader/Models/CanvasRemix.swift StepsTrader/Models/DayComposition.swift \
      StepsTrader/Experiments/DayObjects/Sound/Lab/DayObjectsMusicLabController.swift \
      StepsTrader/Views/GalleryView.swift StepsTrader/Views/Gallery/CanvasFullScreenDock.swift \
      Steps4Tests/CanvasRemixTests.swift Steps4Tests/CanvasPersistenceRegressionTests.swift \
      Steps4Tests/DayObjectsMusicLabControllerTests.swift Steps4Tests/CanvasPresentationStateTests.swift
    git commit -m "feat: unify canvas visual and music remix"

### Task 6: Automatic mix-quality analysis

**Files:**
- Create: StepsTrader/Experiments/DayObjects/Sound/Diagnostics/DayObjectsMixQualityAnalyzer.swift
- Create: StepsTrader/Experiments/DayObjects/Sound/Diagnostics/DayObjectsMixQualityReport.swift
- Modify: StepsTrader/Experiments/DayObjects/Sound/Diagnostics/DayObjectsLoudnessAnalyzer.swift
- Modify: Scripts/day_objects_audio/analyze_day_objects_mix.swift
- Test: Steps4Tests/DayObjectsMixQualityAnalyzerTests.swift
- Test: Steps4Tests/DayObjectsLoudnessAnalyzerTests.swift

**Interfaces:**
- Produces DayObjectsMixQualityAnalyzer.analyze(fullMix:stems:), where stems
  is [DayObjectsMixRole: AVAudioPCMBuffer].
- Produces codable DayObjectsMixQualityReport and bounded DayObjectsMixSuggestion values.

- [ ] **Step 1: Write failing synthetic-signal tests**

    func testFlagsDCOffsetBrightnessAndClipping() throws {
        let report = try analyzer.analyze(fullMix: brightOffsetBuffer, stems: [:])
        XCTAssertTrue(report.issues.contains(.dcOffset))
        XCTAssertTrue(report.issues.contains(.excessiveBrightness))
        XCTAssertTrue(report.issues.contains(.truePeak))
    }

    func testKickBassSuggestionIsBounded() throws {
        let report = try analyzer.analyze(
            fullMix: mixBuffer,
            stems: [.rhythm: lowPulse, .bass: lowPulse]
        )
        let value = try XCTUnwrap(report.suggestions.first { $0.role == .bass })
        XCTAssertTrue((-3.0 ... 0.0).contains(value.gainAdjustmentDB))
        XCTAssertTrue((0.0 ... 4.0).contains(value.additionalDuckingDB))
    }

- [ ] **Step 2: Run RED**

Run DayObjectsMixQualityAnalyzerTests and DayObjectsLoudnessAnalyzerTests. Expect missing quality analyzer types.

- [ ] **Step 3: Implement deterministic analysis**

    struct DayObjectsMixQualityReport: Codable, Equatable, Sendable {
        let integratedLUFS: Double
        let truePeakDBTP: Double
        let maximumAbsoluteDCOffset: Double
        let crestFactorDB: Double
        let lowBandEnergyRatio: Double
        let midBandEnergyRatio: Double
        let highBandEnergyRatio: Double
        let layerAudibilityDB: [String: Double]
        let issues: [DayObjectsMixIssue]
        let suggestions: [DayObjectsMixSuggestion]
    }

    enum DayObjectsMixRole: String, Codable, CaseIterable, Sendable {
        case rhythm, bass, harmony, happenings, lead
    }

    struct DayObjectsMixSuggestion: Codable, Equatable, Sendable {
        let role: DayObjectsMixRole
        let gainAdjustmentDB: Double
        let additionalDuckingDB: Double
        let cutoffMultiplier: Double
        let reverbSendAdjustment: Double
    }

Use the existing EBU loudness implementation. Add deterministic FFT/band-energy analysis for 20...160 Hz, 160...4000 Hz, and 4000...20000 Hz; DC mean; peak/RMS crest factor; stem-to-mix audibility; and normalized low-band correlation for kick/bass masking. Thresholds: -18...-16 LUFS, at most -1 dBTP, absolute DC at most 0.01, high-band ratio at most 0.45, and every intentionally active stem above -42 dB relative to full mix.

Suggestions are limited to gain -3...0 dB, extra ducking 0...4 dB, cutoff multiplier 0.75...1, and reverb-send change -0.15...0. Do not apply them live. Serialize them for review and manually accept values into world-groups-v1.json.

- [ ] **Step 4: Extend the command-line report and run GREEN**

The analyzer accepts --stems-directory, matches rhythm.wav, bass.wav, harmony.wav, happenings.wav, and lead.wav, and writes the quality report as JSON. Run both analyzer test suites and expect every synthetic issue to be classified.

- [ ] **Step 5: Commit**

    git add StepsTrader/Experiments/DayObjects/Sound/Diagnostics \
      Scripts/day_objects_audio/analyze_day_objects_mix.swift \
      Steps4Tests/DayObjectsMixQualityAnalyzerTests.swift \
      Steps4Tests/DayObjectsLoudnessAnalyzerTests.swift
    git commit -m "feat: analyze day objects mix quality"

### Task 7: Twelve-variant blind audition exporter

**Files:**
- Create: StepsTrader/Experiments/DayObjects/Sound/Diagnostics/DayObjectsAuditionPackExporter.swift
- Create: Scripts/day_objects_audio/export_sound_world_auditions.swift
- Modify: StepsTrader/Experiments/DayObjects/Sound/Diagnostics/DayObjectsOfflineMixRenderer.swift
- Modify: StepsTrader/Experiments/DayObjects/Sound/Lab/DayObjectsInstrumentAuditionView.swift
- Modify: Steps4.xcodeproj/project.pbxproj
- Test: Steps4Tests/DayObjectsAuditionPackExporterTests.swift
- Test: Steps4Tests/DayObjectsMixScenarioTests.swift

**Interfaces:**
- Produces DayObjectsAuditionPackExporter.export(input:seed:directory:).
- Produces audition-manifest.json and mix-quality.json.

- [ ] **Step 1: Write failing pack-shape tests**

    func testPackContainsTwelveAnonymousMixesAndFiveStemsEach() async throws {
        let result = try await exporter.export(input: input, seed: 99, directory: temporaryURL)
        XCTAssertEqual(result.entries.count, 12)
        XCTAssertEqual(Set(result.entries.map(\.publicNumber)), Set(1...12))
        XCTAssertTrue(result.entries.allSatisfy { $0.mixPath.hasPrefix("preview-") })
        XCTAssertTrue(result.entries.allSatisfy { $0.stemPaths.count == 5 })
    }

    func testManifestPrivatelyMapsEveryNumberToWorldMoodAndRecipes() async throws {
        let result = try await exporter.export(input: input, seed: 99, directory: temporaryURL)
        XCTAssertEqual(Set(result.entries.map { [$0.world.rawValue, $0.mood.rawValue] }).count, 12)
        XCTAssertTrue(result.entries.allSatisfy { !$0.instrumentRecipeIDs.isEmpty })
    }

- [ ] **Step 2: Run RED**

Run DayObjectsAuditionPackExporterTests. Expect missing exporter.

- [ ] **Step 3: Implement export through the app graph**

For each world/mood pair, force only world and mood while holding health input and base seed constant. Render a 24-second full mix and five isolated buses through DayObjectsOfflineMixRenderer. Name public mixes preview-01.wav through preview-12.wav after a seed-deterministic shuffle. Put stems in private/NN/rhythm.wav, bass.wav, harmony.wav, happenings.wav, and lead.wav. The manifest records number, seed, world, mood, guest, progression, kit, recipe IDs, paths, and SHA-256.

    struct DayObjectsAuditionPackEntry: Codable, Equatable, Sendable {
        let publicNumber: Int
        let seed: UInt64
        let world: DayObjectsSoundWorld
        let mood: DayObjectsSoundMood
        let guestWorld: DayObjectsSoundWorld?
        let mixPath: String
        let stemPaths: [String: String]
        let instrumentRecipeIDs: [DayObjectsInstrumentID]
        let progressionDegrees: [Int]
        let kitID: String
        let sha256: String
    }

    struct DayObjectsAuditionPackResult: Equatable, Sendable {
        let entries: [DayObjectsAuditionPackEntry]
        let manifestURL: URL
        let qualityReportURL: URL
    }

Run DayObjectsMixQualityAnalyzer for every entry. If any render fails, report number/seed/layer and exit once; do not retry automatically.

- [ ] **Step 4: Add diagnostic export trigger**

Expose Export 12 previews under Instrument diagnostics only. Keep it absent from normal Canvas UI. Display progress 0...12 and the final directory path.

- [ ] **Step 5: Run GREEN**

Run DayObjectsAuditionPackExporterTests and DayObjectsMixScenarioTests. Expect 12 mixes, 60 stems, deterministic hashes, finite samples, and complete reports.

- [ ] **Step 6: Commit**

    git add StepsTrader/Experiments/DayObjects/Sound/Diagnostics \
      StepsTrader/Experiments/DayObjects/Sound/Lab/DayObjectsInstrumentAuditionView.swift \
      Scripts/day_objects_audio/export_sound_world_auditions.swift \
      Steps4Tests/DayObjectsAuditionPackExporterTests.swift Steps4Tests/DayObjectsMixScenarioTests.swift \
      Steps4.xcodeproj/project.pbxproj
    git commit -m "feat: export blind sound world audition packs"

### Task 8: Verification, calibration report, and device build

**Files:**
- Modify: docs/day-objects-bass-mix-listening-checklist.md
- Modify: docs/superpowers/plans/2026-09-06-day-objects-four-sound-worlds.md
- Create after export: artifacts/day-objects-four-worlds/audition-manifest.json
- Create after export: artifacts/day-objects-four-worlds/mix-quality.json

**Interfaces:**
- Consumes all prior tasks.
- Produces a reviewable commit series, 12 local WAVs, reports, and an installable Debug device build.

- [x] **Step 1: Run focused domain/planner/UI tests**

    xcodebuild test -quiet -project Steps4.xcodeproj -scheme Steps4 \
      -destination 'platform=iOS Simulator,name=iPhone 16e' \
      -only-testing:Steps4Tests/DayObjectsWorldSelectorTests \
      -only-testing:Steps4Tests/DayObjectsSoundWorldCatalogTests \
      -only-testing:Steps4Tests/TonalWorldPlannerTests \
      -only-testing:Steps4Tests/DeterministicMusicDirectorTests \
      -only-testing:Steps4Tests/CanvasRemixTests \
      -only-testing:Steps4Tests/CanvasPresentationStateTests

Expected: zero failures.

- [x] **Step 2: Export exactly one audition pack**

    DAY_OBJECTS_AUDITION_PACK=1 \
      Scripts/day_objects_audio/export_sound_world_auditions.swift \
      --directory artifacts/day-objects-four-worlds --seed 99 \
      --destination 'platform=iOS Simulator,name=iPhone 16e'

The app-owned schedule fixes every mix/stem at 24 seconds and 48 kHz (22 seconds
of scheduled music plus two seconds of release). The CLI injects the opt-in into
the app-hosted test. Add `--xctestrun PATH` to reuse a freshly built test product;
otherwise the CLI builds the app/tests in a new temporary directory. The only
supported options are `--directory`, `--seed`, `--destination`, and `--xctestrun`.

Do not run another export concurrently. Confirm the exporter process ends before analysis.

Execution exception, explicitly approved during Task 8: the initial CLI was
rejected before any test/app startup or WAV creation (`-test-iterations 1` is
invalid). Its scoped fix uses the default single pass. The first real pack then
completed normally but failed quality. A measured catalog/runtime calibration
was approved, implemented in `e71047f`, passed 174 focused tests and an independent
15-test review, and one second/final real pack was authorized after review.
The first pack was recoverably renamed to
`artifacts/day-objects-four-worlds-rejected-1`; the canonical second pack completed
normally in 37m28s. No exports ran concurrently; all exporter/app processes ended
before external analysis. No third export is authorized.

- [ ] **Step 3: Validate reports and inspect resource cost**

Confirm 12 mixes and 60 stems, no duplicate full-mix hashes, all finite samples, at most -1 dBTP, and full mixes within -18...-16 LUFS after accepted bounded calibration. Record directory size and the app's peak resident memory during one sequential render. Do not commit the WAVs.

Validation was performed, but full acceptance remains unmet, so this step is
not checked off. The final pack has 12 mixes / 60 stems, 12 unique mix hashes,
72 finite float32 PCM files with matching hashes, correct metadata/schedule,
and exact committed calibration values. True peak passes 12/12; loudness passes
11/12; all quality gates pass only 3/12 (03, 09, 11). Nine previews retain excessive
tails and 08 is -20.091 LUFS. See the listening checklist and private JSON mapping
for the exact rejected groups. No further calibration, analyzer change, or
export was attempted. Size: 663,888,885 logical bytes (633.134 MiB). Peak app RSS:
721.078 MiB overall; 553.703 MiB during the first sequential full-mix render.
No separate render was launched for memory measurement.

- [x] **Step 4: Run broader audio regression suites**

Run resource, instrument-bank, playback-engine, scheduler, plan-differ, loudness, mix-quality, and scenario tests in one xcodebuild process. If simulator bootstrap fails without a test assertion, preserve the result bundle and report the infrastructure failure; do not loop indefinitely.

Executed once: 240 selected, 235 passed, four expected opt-in skips, one
diagnostic fake-clock failure. The authorized fixture-only correction retained
the 1 µs assertion tolerance and passed the exact live/mobile cases and ten
related timing tests (12/12). The original broad result remains preserved;
the complete suite was not rerun or represented as a clean pass.

- [x] **Step 5: Build simulator and physical-device Debug products**

    xcodebuild build -quiet -project Steps4.xcodeproj -scheme Steps4 \
      -configuration Debug -destination 'generic/platform=iOS Simulator' \
      CODE_SIGNING_ALLOWED=NO

    xcodebuild build -quiet -project Steps4.xcodeproj -scheme Steps4 \
      -configuration Debug -destination 'generic/platform=iOS'

Expected: both builds succeed. Installation and subjective listening require the connected, trusted iPhone.

Both generic Debug builds passed again on calibrated HEAD `e71047f`. The signed
Debug app was installed on paired, available iPhone Costa (iPhone 15 Pro) without
launching. Phone-speaker and headphone listening remain pending.

- [x] **Step 6: Update checklist and plan progress**

Record test counts, build outcomes, report thresholds, memory, artifact paths, manual listening still required, and any rejected combination IDs. Add phone-speaker and headphone ratings for previews 01...12 without revealing the manifest mapping until ratings are complete.

Recorded all automated evidence and a blind numbered rating table. Human ratings
remain explicitly pending; none are inferred from automated results. Task 8 is
not claimed accepted or complete while Step 3 quality gates and listening remain
unmet.

- [x] **Step 7: Commit reports and documentation**

    git add artifacts/day-objects-four-worlds/audition-manifest.json \
      artifacts/day-objects-four-worlds/mix-quality.json \
      docs/day-objects-bass-mix-listening-checklist.md \
      docs/superpowers/plans/2026-09-06-day-objects-four-sound-worlds.md
    git commit -m "docs: record four-world audio verification"

- [x] **Step 8: Review the final branch**

    git diff --check
    git status --short
    git log --oneline --decorate -12

Expected: only intentionally untracked audition WAVs and the preserved rejected
pack remain. The final documentation commit contains only the canonical JSON
manifest/quality report and these two documents, never WAVs. `git diff --check`,
status, log, exact integration ancestry, and the absence of new merge commits
were checked. Do not merge, force-push, or overwrite unrelated user work.
