# Day Objects Synth One Preset Lab Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (- [ ]) syntax for tracking.

**Goal:** Build a native, debug-only Day Objects sound lab that lets a person compare twelve selected AudioKit Synth One-derived Pad, Pluck, Bass, and Lead voices with Note, Chord, and expressive XY controls on an iPhone.

**Architecture:** Keep preset decoding and normalization pure, place all AudioKit nodes behind a main-actor engine protocol, and let one observable lab controller translate SwiftUI actions and lifecycle events into engine commands. The existing Day Objects renderer remains unchanged; the lab adds an always-visible Sound button, a compact audition panel, and one transparent XY gesture surface only in single-canvas mode.

**Tech Stack:** SwiftUI, Observation, AVFoundation, AudioKit 5.7.2, SoundpipeAudioKit 5.7.4, XCTest, XCUITest, Xcode Swift Package Manager.

**Spec:** docs/superpowers/specs/2026-08-30-day-objects-synth-one-preset-lab-design.md

## Global Constraints

- The feature remains inside the existing Day Objects debug/internal lab; release builds must not expose it.
- Wrap every new Sound source and every DayObjectsLabView sound reference in #if DEBUG || INTERNAL_BUILD so the audio layer is absent when the experimental surface is unavailable.
- Sound is off on every presentation and starts only after an explicit press.
- Do not add automatic music, chord progressions, rhythms, percussion, happening scheduling, Steps, Sleep, Glitch, Remix, HealthKit reads, production Canvas integration, or background audio.
- Do not copy the Synth One application UI, navigation, graphics, or legacy engine.
- Bundle exactly twelve official presets: three Pad, three Pluck, three Bass, and three Lead.
- Source the selected JSON from AudioKitSynthOne commit 6466a3715c96b7ecf1dd255a218cbd571408a314 and preserve the upstream MIT notice.
- Pin AudioKit to exact version 5.7.2 and SoundpipeAudioKit to exact version 5.7.4.
- The normalized engine ranges are: envelope times 0.001...8 seconds, oscillator gains 0...1, cutoff 20...18,000 Hz, resonance 0...0.95, effect mix 0...0.85, delay feedback 0...0.90, reverb feedback 0.30...0.92, and final output trim 0.05...0.50.
- The engine owns at most six live voices: one XY voice and up to five audition/release voices. When full, steal the oldest non-XY audition voice.
- Preset replacement releases current voices and crossfades over 0.12 seconds.
- XY uses D Dorian intervals [0, 2, 3, 5, 7, 9, 10] relative to MIDI root 50, maps vertical position to a filter multiplier of 0.35...2.4, and limits movement expression to 0...0.25.
- Use the existing simulator destination platform=iOS Simulator,name=iPhone 17 Pro for automated checks.
- Preserve unrelated working-tree changes. Stage and commit only files named by the current task.

## File Structure

Create the sound feature under StepsTrader/Experiments/DayObjects/Sound so it changes with the Day Objects lab and remains isolated from production models.

- StepsTrader/Experiments/DayObjects/Sound/DayObjectsSynthPreset.swift — normalized domain values, ranges, categories, diagnostics, and manifest entry types.
- StepsTrader/Experiments/DayObjects/Sound/SynthOnePresetDTO.swift — tolerant decoding of the supported upstream JSON keys.
- StepsTrader/Experiments/DayObjects/Sound/SynthOnePresetAdapter.swift — pure source-to-native conversion and deterministic diagnostics.
- StepsTrader/Experiments/DayObjects/Sound/DayObjectsPresetManifest.swift — the exact twelve entries, reference notes/chords, attribution, and conservative trims.
- StepsTrader/Experiments/DayObjects/Sound/DayObjectsPresetCatalog.swift — loads the bundled JSON, joins it to the manifest by upstream UID, and returns converted presets.
- StepsTrader/Experiments/DayObjects/Sound/DayObjectsSoundEngineProtocol.swift — engine state and the UI-independent command seam.
- StepsTrader/Experiments/DayObjects/Sound/DayObjectsVoiceAllocator.swift — pure bounded allocation and stealing policy.
- StepsTrader/Experiments/DayObjects/Sound/DayObjectsXYMapping.swift — pure touch-to-note/filter/expression mapping.
- StepsTrader/Experiments/DayObjects/Sound/AudioKitDayObjectsVoice.swift — one two-oscillator/sub/noise voice and its envelopes/filter ramps.
- StepsTrader/Experiments/DayObjects/Sound/AudioKitDayObjectsSoundEngine.swift — AVAudioSession, graph, shared effects, lifecycle, polyphony, crossfade, and limiter.
- StepsTrader/Experiments/DayObjects/Sound/NoopDayObjectsSoundEngine.swift — deterministic test engine selected only by the UI-test launch argument.
- StepsTrader/Experiments/DayObjects/Sound/DayObjectsLabSoundController.swift — observable lab state and recoverable command handling.
- StepsTrader/Experiments/DayObjects/Sound/DayObjectsSoundControls.swift — Sound, category, preset, Note, Chord, source, error, and grid-state UI.
- StepsTrader/Experiments/DayObjects/Sound/DayObjectsXYSurface.swift — single-touch SwiftUI gesture adapter with control exclusion and VoiceOver safety.
- StepsTrader/Experiments/DayObjects/Sound/Resources/SynthOneSelectedPresets.json — original JSON objects for the exact twelve UIDs.
- StepsTrader/Experiments/DayObjects/Sound/Resources/AudioKitSynthOne-LICENSE.txt — unmodified upstream MIT license.
- StepsTrader/Experiments/DayObjects/Sound/Resources/AudioKitThirdPartyNotices.md — source commit, selected banks, and package notices.
- StepsTrader/Experiments/DayObjects/DayObjectsLabView.swift — owns the controller and layers controls/XY without changing rendering inputs.
- Steps4Tests/DayObjectsPresetCatalogTests.swift — manifest and resource invariants.
- Steps4Tests/SynthOnePresetAdapterTests.swift — defaults, clamping, rejection, diagnostics, and determinism.
- Steps4Tests/DayObjectsVoiceAllocatorTests.swift — voice cap, XY uniqueness, and stealing order.
- Steps4Tests/DayObjectsXYMappingTests.swift — scale quantization and bounded continuous values.
- Steps4Tests/DayObjectsLabSoundControllerTests.swift — lifecycle, retry, selection, audition, and cancellation behavior.
- Steps4UITests/DayObjectsLabUITests.swift — user-visible sound states, categories, presets, grid behavior, and regression coverage.
- Steps4.xcodeproj/project.pbxproj — package references, products, new source files, test files, and resources.
- Steps4.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved — exact resolved dependency revisions generated by Xcode.

---

### Task 1: Pin AudioKit and Check In the Licensed Preset Source

**Files:**
- Modify: Steps4.xcodeproj/project.pbxproj
- Create: Steps4.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved
- Create: StepsTrader/Experiments/DayObjects/Sound/Resources/SynthOneSelectedPresets.json
- Create: StepsTrader/Experiments/DayObjects/Sound/Resources/AudioKitSynthOne-LICENSE.txt
- Create: StepsTrader/Experiments/DayObjects/Sound/Resources/AudioKitThirdPartyNotices.md

**Interfaces:**
- Consumes: AudioKitSynthOne commit 6466a3715c96b7ecf1dd255a218cbd571408a314.
- Produces: app-target imports AudioKit and SoundpipeAudioKit; Bundle.main resources named SynthOneSelectedPresets.json and AudioKitSynthOne-LICENSE.txt.

- [ ] **Step 1: Add the exact package products**

In Xcode, open Steps4.xcodeproj and add these package dependencies with Dependency Rule set to Exact Version:

~~~text
https://github.com/AudioKit/AudioKit.git
Exact Version: 5.7.2
Product on Steps4 target: AudioKit

https://github.com/AudioKit/SoundpipeAudioKit.git
Exact Version: 5.7.4
Product on Steps4 target: SoundpipeAudioKit
~~~

Do not add either product to app-extension targets. Let Xcode write Package.resolved, then confirm it contains AudioKit 5.7.2 and SoundpipeAudioKit 5.7.4 rather than a branch revision or open version range.

- [ ] **Step 2: Extract only the twelve approved upstream objects**

Use a temporary clone pinned to the approved commit. Generate the resource by UID so renamed files or duplicate display names cannot change the selection.

~~~bash
source_dir=$(mktemp -d /tmp/day-objects-synth-one.XXXXXX)
git clone https://github.com/AudioKit/AudioKitSynthOne.git "$source_dir/AudioKitSynthOne"
git -C "$source_dir/AudioKitSynthOne" checkout 6466a3715c96b7ecf1dd255a218cbd571408a314

jq -s '
  [
    .[][] |
    select(.uid as $uid | [
      "39529417-FBC1-41D5-B1D1-0DED9E38F164",
      "96F9F71C-1D6C-41FC-8192-E4B550562357",
      "9BF89CC8-5AD5-46D8-9640-C3FE335C65D9",
      "E9AFAF33-21A5-4A1B-80BF-74BFB333E86D",
      "88335303-C675-4D14-907E-2D80823C2BCA",
      "8FC6202C-DAE8-4651-98DE-F3BEBB07E6BF",
      "C2958050-CDCA-4C64-AF92-3217539CE60A",
      "4131C811-FBB8-4E15-B238-8986645A62D3",
      "FA16AF16-3033-485F-A183-4DAAB7025B52",
      "9BDE3DCB-219D-4D70-A067-C1057B557F19",
      "2B6BCC6D-8526-4CAD-8230-EF3C84A26E9F",
      "BB74B6AD-9076-464C-B373-F2E968BBD2BE"
    ] | index($uid))
  ] | sort_by(.uid)
' \
  "$source_dir/AudioKitSynthOne/AudioKitSynthOne/Presets/Data/Bonus.json" \
  "$source_dir/AudioKitSynthOne/AudioKitSynthOne/Presets/Data/Brice Beasley.json" \
  "$source_dir/AudioKitSynthOne/AudioKitSynthOne/Presets/Data/Electronisounds.json" \
  "$source_dir/AudioKitSynthOne/AudioKitSynthOne/Presets/Data/JEC.json" \
  "$source_dir/AudioKitSynthOne/AudioKitSynthOne/Presets/Data/Red Sky Lullaby.json" \
  "$source_dir/AudioKitSynthOne/AudioKitSynthOne/Presets/Data/Spidericemidas.json" \
  > StepsTrader/Experiments/DayObjects/Sound/Resources/SynthOneSelectedPresets.json

cp "$source_dir/AudioKitSynthOne/LICENSE" \
  StepsTrader/Experiments/DayObjects/Sound/Resources/AudioKitSynthOne-LICENSE.txt
~~~

Verify the generated array has exactly twelve unique UIDs:

~~~bash
jq 'length, ([.[].uid] | unique | length)' \
  StepsTrader/Experiments/DayObjects/Sound/Resources/SynthOneSelectedPresets.json
~~~

Expected output is 12 on both lines.

- [ ] **Step 3: Add an explicit notice**

Create AudioKitThirdPartyNotices.md with this exact factual content, followed by the unmodified license text in the separate license resource:

~~~markdown
# Audio sources used by Day Objects Lab

The twelve experimental preset parameter records in this lab are derived from
AudioKit Synth One by the AudioKit contributors:
https://github.com/AudioKit/AudioKitSynthOne

Source revision:
6466a3715c96b7ecf1dd255a218cbd571408a314

Selected source banks: Bonus, Brice Beasley, Electronisounds, JEC,
Red Sky Lullaby, and Spidericemidas.

AudioKit and SoundpipeAudioKit are used under their MIT licenses.
The AudioKit Synth One license is bundled as AudioKitSynthOne-LICENSE.txt.
~~~

- [ ] **Step 4: Add the resources to the app target and resolve**

Add the Resources directory as individual file references under the DayObjects/Sound group. Ensure all three resources belong only to the Steps4 target and appear once in Copy Bundle Resources.

Run:

~~~bash
xcodebuild -resolvePackageDependencies \
  -project Steps4.xcodeproj \
  -scheme Steps4
~~~

Expected: resolution succeeds and reports AudioKit 5.7.2 and SoundpipeAudioKit 5.7.4.

- [ ] **Step 5: Verify the unchanged app still builds**

Run:

~~~bash
xcodebuild build \
  -project Steps4.xcodeproj \
  -scheme Steps4 \
  -configuration Debug \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
~~~

Expected: BUILD SUCCEEDED.

- [ ] **Step 6: Commit the dependency and source provenance**

~~~bash
git add \
  Steps4.xcodeproj/project.pbxproj \
  Steps4.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved \
  StepsTrader/Experiments/DayObjects/Sound/Resources
git commit -m "build: add native Day Objects audio dependencies"
~~~

---

### Task 2: Define and Validate the Twelve-Preset Catalog

**Files:**
- Create: StepsTrader/Experiments/DayObjects/Sound/DayObjectsSynthPreset.swift
- Create: StepsTrader/Experiments/DayObjects/Sound/SynthOnePresetDTO.swift
- Create: StepsTrader/Experiments/DayObjects/Sound/SynthOnePresetAdapter.swift
- Create: StepsTrader/Experiments/DayObjects/Sound/DayObjectsPresetManifest.swift
- Create: StepsTrader/Experiments/DayObjects/Sound/DayObjectsPresetCatalog.swift
- Create: Steps4Tests/DayObjectsPresetCatalogTests.swift
- Create: Steps4Tests/SynthOnePresetAdapterTests.swift
- Modify: Steps4.xcodeproj/project.pbxproj

**Interfaces:**
- Consumes: Bundle.main/SynthOneSelectedPresets.json from Task 1.
- Produces: DayObjectsPresetCatalog.load(bundle:) throws -> DayObjectsPresetCatalog; DayObjectsPresetCatalog.unavailable; isAvailable; presets(in:); preset(id:); SynthOnePresetAdapter.convert(_:manifest:) throws -> DayObjectsPresetConversion.

- [ ] **Step 1: Write failing manifest and catalog tests**

Create DayObjectsPresetCatalogTests.swift:

~~~swift
import AVFoundation
import XCTest
@testable import Steps4

final class DayObjectsPresetCatalogTests: XCTestCase {
    func testManifestHasExactlyThreeUniqueEntriesPerCategory() throws {
        let entries = DayObjectsPresetManifest.entries
        XCTAssertEqual(entries.count, 12)
        XCTAssertEqual(Set(entries.map(\.id)).count, 12)
        XCTAssertEqual(Set(entries.map(\.sourceUID)).count, 12)

        for category in DayObjectsPresetCategory.allCases {
            XCTAssertEqual(entries.filter { $0.category == category }.count, 3)
        }
    }

    func testBundledCatalogLoadsEveryAttributedManifestEntry() throws {
        let catalog = try DayObjectsPresetCatalog.load(bundle: .main)
        XCTAssertEqual(catalog.allPresets.count, 12)

        for entry in DayObjectsPresetManifest.entries {
            let preset = try XCTUnwrap(catalog.preset(id: entry.id))
            XCTAssertEqual(preset.name, entry.name)
            XCTAssertEqual(preset.category, entry.category)
            XCTAssertFalse(entry.sourceBank.isEmpty)
        }
    }

    func testCategoryOrderingIsStable() throws {
        let catalog = try DayObjectsPresetCatalog.load(bundle: .main)
        XCTAssertEqual(
            catalog.presets(in: .pad).map(\.id),
            ["pad.interstellar", "pad.whispering-sands", "pad.forgotten-stories"]
        )
    }
}
~~~

- [ ] **Step 2: Run the catalog tests and confirm failure**

~~~bash
xcodebuild test \
  -project Steps4.xcodeproj \
  -scheme Steps4 \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:Steps4Tests/DayObjectsPresetCatalogTests
~~~

Expected: compilation fails because DayObjectsPresetManifest and DayObjectsPresetCatalog do not exist.

- [ ] **Step 3: Define normalized types and finite range helpers**

In DayObjectsSynthPreset.swift define:

~~~swift
import AVFoundation
import Foundation

enum DayObjectsPresetCategory: String, CaseIterable, Codable, Sendable {
    case pad = "Pad"
    case pluck = "Pluck"
    case bass = "Bass"
    case lead = "Lead"
}

struct DayObjectsEnvelope: Equatable, Sendable {
    let attack: AUValue
    let decay: AUValue
    let sustain: AUValue
    let release: AUValue
}

struct DayObjectsOscillatorPlan: Equatable, Sendable {
    let wavePosition1: AUValue
    let wavePosition2: AUValue
    let level1: AUValue
    let level2: AUValue
    let balance: AUValue
    let semitone1: Int
    let semitone2: Int
    let fineDetune: AUValue
    let subLevel: AUValue
    let subIsSquare: Bool
    let noiseLevel: AUValue
}

enum DayObjectsFilterKind: Int, Equatable, Sendable {
    case lowPass
    case bandPass
    case highPass
}

struct DayObjectsFilterPlan: Equatable, Sendable {
    let kind: DayObjectsFilterKind
    let cutoff: AUValue
    let resonance: AUValue
    let envelope: DayObjectsEnvelope
    let envelopeMix: AUValue
}

enum DayObjectsModulationTarget: String, Equatable, Sendable {
    case none
    case pitch
    case filter
    case amplitude
}

struct DayObjectsModulationPlan: Equatable, Sendable {
    let target: DayObjectsModulationTarget
    let rateHz: AUValue
    let depth: AUValue
}

struct DayObjectsEffectPlan: Equatable, Sendable {
    let delayTime: AUValue
    let delayFeedback: AUValue
    let delayMix: AUValue
    let reverbFeedback: AUValue
    let reverbHighPass: AUValue
    let reverbMix: AUValue
    let phaserRate: AUValue
    let phaserFeedback: AUValue
    let phaserMix: AUValue
    let autoPanRate: AUValue
    let autoPanDepth: AUValue
    let stereoWidth: AUValue
}

struct DayObjectsPerformancePlan: Equatable, Sendable {
    let glide: AUValue
    let isMonophonic: Bool
}

struct DayObjectsSynthPreset: Equatable, Sendable {
    let id: String
    let name: String
    let category: DayObjectsPresetCategory
    let oscillators: DayObjectsOscillatorPlan
    let amplitudeEnvelope: DayObjectsEnvelope
    let filter: DayObjectsFilterPlan
    let modulation: DayObjectsModulationPlan
    let effects: DayObjectsEffectPlan
    let performance: DayObjectsPerformancePlan
    let outputTrim: AUValue
}

struct DayObjectsPresetManifestEntry: Equatable, Sendable {
    let id: String
    let sourceUID: String
    let name: String
    let sourceBank: String
    let author: String?
    let category: DayObjectsPresetCategory
    let referenceNote: UInt8
    let referenceChord: [UInt8]
    let outputTrim: AUValue
}

enum SynthOnePresetDiagnostic: Equatable, Sendable {
    case ignored(String)
    case defaulted(String)
    case clamped(String, original: AUValue, result: AUValue)
}

struct DayObjectsPresetConversion: Equatable, Sendable {
    let preset: DayObjectsSynthPreset
    let diagnostics: [SynthOnePresetDiagnostic]
}
~~~

Add one internal helper that rejects non-finite required values and clamps optional source values to the Global Constraints. Do not use force unwraps in the decoder or adapter.

- [ ] **Step 4: Add the exact manifest**

In DayObjectsPresetManifest.swift define entries in this exact order:

~~~swift
enum DayObjectsPresetManifest {
    static let entries: [DayObjectsPresetManifestEntry] = [
        .init(id: "pad.interstellar", sourceUID: "39529417-FBC1-41D5-B1D1-0DED9E38F164",
              name: "Interstellar", sourceBank: "Bonus", author: nil,
              category: .pad, referenceNote: 62, referenceChord: [50, 57, 64, 69], outputTrim: 0.22),
        .init(id: "pad.whispering-sands", sourceUID: "96F9F71C-1D6C-41FC-8192-E4B550562357",
              name: "Whispering Sands", sourceBank: "Bonus", author: nil,
              category: .pad, referenceNote: 62, referenceChord: [50, 57, 64, 69], outputTrim: 0.24),
        .init(id: "pad.forgotten-stories", sourceUID: "9BF89CC8-5AD5-46D8-9640-C3FE335C65D9",
              name: "PAD - Forgotten Stories", sourceBank: "Electronisounds", author: nil,
              category: .pad, referenceNote: 62, referenceChord: [50, 57, 64, 69], outputTrim: 0.18),

        .init(id: "pluck.play-something-sad", sourceUID: "E9AFAF33-21A5-4A1B-80BF-74BFB333E86D",
              name: "PLK - Play Something Sad", sourceBank: "Electronisounds", author: nil,
              category: .pluck, referenceNote: 74, referenceChord: [62, 69, 76, 81], outputTrim: 0.22),
        .init(id: "pluck.jec-ambient-pizz-2", sourceUID: "88335303-C675-4D14-907E-2D80823C2BCA",
              name: "JEC Ambient Pizz 2", sourceBank: "JEC", author: nil,
              category: .pluck, referenceNote: 74, referenceChord: [62, 69, 76, 81], outputTrim: 0.18),
        .init(id: "pluck.spider-filter-pluck", sourceUID: "8FC6202C-DAE8-4651-98DE-F3BEBB07E6BF",
              name: "🕷- Filter Pluck", sourceBank: "Spidericemidas", author: nil,
              category: .pluck, referenceNote: 74, referenceChord: [62, 69, 76, 81], outputTrim: 0.22),

        .init(id: "bass.analog-boom", sourceUID: "C2958050-CDCA-4C64-AF92-3217539CE60A",
              name: "Analog Boom Bass", sourceBank: "Bonus", author: nil,
              category: .bass, referenceNote: 38, referenceChord: [38, 45, 52, 57], outputTrim: 0.18),
        .init(id: "bass.bb-roys-phaser", sourceUID: "4131C811-FBB8-4E15-B238-8986645A62D3",
              name: "BB Röy’s Phaser Bass", sourceBank: "Brice Beasley", author: nil,
              category: .bass, referenceNote: 38, referenceChord: [38, 45, 52, 57], outputTrim: 0.16),
        .init(id: "bass.jec-hollores-2", sourceUID: "FA16AF16-3033-485F-A183-4DAAB7025B52",
              name: "JEC Hollores Bass 2", sourceBank: "JEC", author: nil,
              category: .bass, referenceNote: 38, referenceChord: [38, 45, 52, 57], outputTrim: 0.14),

        .init(id: "lead.verbacious", sourceUID: "9BDE3DCB-219D-4D70-A067-C1057B557F19",
              name: "Verbacious Lead", sourceBank: "Red Sky Lullaby", author: nil,
              category: .lead, referenceNote: 69, referenceChord: [57, 64, 71, 76], outputTrim: 0.14),
        .init(id: "lead.jec-softwah-2", sourceUID: "2B6BCC6D-8526-4CAD-8230-EF3C84A26E9F",
              name: "JEC Softwah Lead 2", sourceBank: "JEC", author: nil,
              category: .lead, referenceNote: 69, referenceChord: [57, 64, 71, 76], outputTrim: 0.18),
        .init(id: "lead.bb-silver-screen", sourceUID: "BB74B6AD-9076-464C-B373-F2E968BBD2BE",
              name: "BB The Silver Screen Lead", sourceBank: "Brice Beasley", author: nil,
              category: .lead, referenceNote: 69, referenceChord: [57, 64, 71, 76], outputTrim: 0.18),
    ]
}
~~~

- [ ] **Step 5: Write failing adapter tests**

Create SynthOnePresetAdapterTests.swift with fixtures made from the DTO initializer:

~~~swift
import XCTest
@testable import Steps4

final class SynthOnePresetAdapterTests: XCTestCase {
    func testMissingOptionalValuesUseDocumentedDefaults() throws {
        let conversion = try SynthOnePresetAdapter.convert(
            SynthOnePresetDTO(uid: "fixture", name: "Fixture"),
            manifest: Self.entry
        )
        XCTAssertEqual(conversion.preset.amplitudeEnvelope,
                       .init(attack: 0.05, decay: 0.20, sustain: 0.80, release: 0.40))
        XCTAssertTrue(conversion.diagnostics.contains(.defaulted("attackDuration")))
    }

    func testUnsafeValuesAreFiniteAndClamped() throws {
        var source = SynthOnePresetDTO(uid: "fixture", name: "Fixture")
        source.cutoff = 100_000
        source.resonance = 5
        source.delayFeedback = 4
        let result = try SynthOnePresetAdapter.convert(source, manifest: Self.entry).preset
        XCTAssertEqual(result.filter.cutoff, 18_000)
        XCTAssertEqual(result.filter.resonance, 0.95)
        XCTAssertEqual(result.effects.delayFeedback, 0.90)
    }

    func testUnsupportedFeaturesProduceStableDiagnostics() throws {
        var source = SynthOnePresetDTO(uid: "fixture", name: "Fixture")
        source.isArpMode = 1
        source.bitcrushLFO = 0.7
        let first = try SynthOnePresetAdapter.convert(source, manifest: Self.entry)
        let second = try SynthOnePresetAdapter.convert(source, manifest: Self.entry)
        XCTAssertEqual(first, second)
        XCTAssertTrue(first.diagnostics.contains(.ignored("arpeggiator")))
        XCTAssertTrue(first.diagnostics.contains(.ignored("bitcrush")))
    }

    func testNonFiniteValuesAreRejected() {
        var source = SynthOnePresetDTO(uid: "fixture", name: "Fixture")
        source.cutoff = .infinity
        XCTAssertThrowsError(try SynthOnePresetAdapter.convert(source, manifest: Self.entry))
    }

    private static let entry = DayObjectsPresetManifestEntry(
        id: "fixture", sourceUID: "fixture", name: "Fixture",
        sourceBank: "Tests", author: nil, category: .pad,
        referenceNote: 60, referenceChord: [48, 55, 62, 67], outputTrim: 0.2
    )
}
~~~

- [ ] **Step 6: Implement the tolerant DTO and deterministic adapter**

SynthOnePresetDTO must decode uid and name, plus only these supported source keys:

~~~text
waveform1, waveform2, vco1Volume, vco2Volume, vcoBalance,
vco1Semitone, vco2Semitone, vco2Detuning, subVolume,
subOscSquareToggled, noiseVolume, attackDuration, decayDuration,
sustainLevel, releaseDuration, glide, isMono, filterType, cutoff,
resonance, filterAttack, filterDecay, filterSustain, filterRelease,
filterADSRMix, lfoAmplitude, lfoRate, pitchLFO, cutoffLFO,
tremoloLFO, delayToggled, delayTime, delayFeedback, delayMix,
reverbToggled, reverbFeedback, reverbHighPass, reverbMix,
phaserRate, phaserFeedback, phaserMix, autoPanFrequency,
autoPanAmount, widen
~~~

Also decode these fields solely for diagnostics:

~~~text
isArpMode, arpIsSequencer, isHoldMode, bitcrushLFO, crushFreq,
fmAmount, fmVolume, fmLFO, oscMixLFO, noiseLFO, resonanceLFO,
filterEnvLFO, detuneLFO, decayLFO, reverbMixLFO,
compressorMasterAttack, compressorMasterMakeupGain,
compressorMasterRatio, compressorMasterRelease, compressorMasterThreshold,
compressorReverbInputAttack, compressorReverbInputMakeupGain,
compressorReverbInputRatio, compressorReverbInputRelease,
compressorReverbInputThreshold, compressorReverbWetAttack,
compressorReverbWetMakeupGain, compressorReverbWetRatio,
compressorReverbWetRelease, compressorReverbWetThreshold,
delayInputCutoffTrackingRatio, delayInputResonance,
frequencyA4, midiBendRange, pitchbendMaxSemitones,
pitchbendMinSemitones, modWheelRouting, seqNoteOn,
seqOctBoost, seqPatternNote
~~~

Map source waveform positions from 0...1 to the MorphingOscillator table index 0...3 only when building nodes; retain normalized 0...1 positions in DayObjectsSynthPreset. Pick one modulation route deterministically in this priority order: pitchLFO, cutoffLFO, tremoloLFO, none. If multiple non-zero routes exist, report each lower-priority route as ignored rather than folding it into another target.

Give SynthOnePresetDTO an internal memberwise initializer whose optional fields all default to nil, so tests can construct a minimal DTO with only uid and name. Emit one deterministic ignored diagnostic for each active unsupported family: arpeggiator/sequencer, hold, bitcrush, FM, extra modulation route, compressor, custom tuning, and MIDI mapping.

DayObjectsPresetCatalog.load(bundle:) must:

1. decode the array;
2. reject duplicate source UIDs;
3. require exactly one DTO for every manifest UID;
4. convert entries in manifest order;
5. expose immutable allPresets, presets(in:), manifestEntry(id:), and preset(id:).

DayObjectsPresetCatalog.unavailable contains one silent internal preset named "Unavailable", returns false from isAvailable, and is never counted by manifest tests or shown as a source preset. It exists only to let the visual lab survive a missing/corrupt resource while a later Sound press retries load(bundle:).

Wrap every new app source in this compile guard, including imports:

~~~swift
#if DEBUG || INTERNAL_BUILD
// implementation
#endif
~~~

- [ ] **Step 7: Run pure catalog and adapter tests**

~~~bash
xcodebuild test \
  -project Steps4.xcodeproj \
  -scheme Steps4 \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:Steps4Tests/DayObjectsPresetCatalogTests \
  -only-testing:Steps4Tests/SynthOnePresetAdapterTests
~~~

Expected: all tests pass.

- [ ] **Step 8: Commit the pure preset pipeline**

~~~bash
git add \
  StepsTrader/Experiments/DayObjects/Sound/DayObjectsSynthPreset.swift \
  StepsTrader/Experiments/DayObjects/Sound/SynthOnePresetDTO.swift \
  StepsTrader/Experiments/DayObjects/Sound/SynthOnePresetAdapter.swift \
  StepsTrader/Experiments/DayObjects/Sound/DayObjectsPresetManifest.swift \
  StepsTrader/Experiments/DayObjects/Sound/DayObjectsPresetCatalog.swift \
  Steps4Tests/DayObjectsPresetCatalogTests.swift \
  Steps4Tests/SynthOnePresetAdapterTests.swift \
  Steps4.xcodeproj/project.pbxproj
git commit -m "feat: add Synth One preset conversion catalog"
~~~

---

### Task 3: Make Voice Allocation and XY Mapping Pure and Bounded

**Files:**
- Create: StepsTrader/Experiments/DayObjects/Sound/DayObjectsVoiceAllocator.swift
- Create: StepsTrader/Experiments/DayObjects/Sound/DayObjectsXYMapping.swift
- Create: Steps4Tests/DayObjectsVoiceAllocatorTests.swift
- Create: Steps4Tests/DayObjectsXYMappingTests.swift
- Modify: Steps4.xcodeproj/project.pbxproj

**Interfaces:**
- Consumes: UInt8 MIDI note values and normalized touch samples.
- Produces: DayObjectsVoiceAllocator.acquire(role:note:) -> DayObjectsVoiceAllocation; release; releaseAll; DayObjectsXYMapping.sample(location:previous:time:previousTime:size:) -> DayObjectsXYSample.

- [ ] **Step 1: Write failing allocator tests**

~~~swift
import XCTest
@testable import Steps4

final class DayObjectsVoiceAllocatorTests: XCTestCase {
    func testNeverExceedsSixVoices() {
        var allocator = DayObjectsVoiceAllocator(capacity: 6)
        for note in UInt8(40)...UInt8(60) {
            _ = allocator.acquire(role: .audition, note: note)
        }
        XCTAssertEqual(allocator.active.count, 6)
    }

    func testFullAllocatorStealsOldestAuditionBeforeXY() {
        var allocator = DayObjectsVoiceAllocator(capacity: 3)
        let oldest = allocator.acquire(role: .audition, note: 60)
        let xy = allocator.acquire(role: .xy, note: 62)
        _ = allocator.acquire(role: .audition, note: 64)
        let replacement = allocator.acquire(role: .audition, note: 65)
        XCTAssertEqual(replacement.stolenID, oldest.id)
        XCTAssertTrue(allocator.active.contains { $0.id == xy.id })
    }

    func testBeginningNewXYReusesSingleXYRole() {
        var allocator = DayObjectsVoiceAllocator(capacity: 6)
        let first = allocator.acquire(role: .xy, note: 60)
        let second = allocator.acquire(role: .xy, note: 67)
        XCTAssertEqual(second.id, first.id)
        XCTAssertEqual(allocator.active.filter { $0.role == .xy }.count, 1)
    }
}
~~~

- [ ] **Step 2: Write failing XY mapping tests**

~~~swift
import CoreGraphics
import XCTest
@testable import Steps4

final class DayObjectsXYMappingTests: XCTestCase {
    func testHorizontalPositionsStayInDDorian() {
        let notes = stride(from: 0.0, through: 1.0, by: 0.05).map {
            DayObjectsXYMapping.note(normalizedX: $0)
        }
        XCTAssertTrue(notes.allSatisfy {
            [0, 2, 3, 5, 7, 9, 10].contains((Int($0) - 50) % 12)
        })
    }

    func testVerticalFilterAndVelocityExpressionAreBounded() {
        let sample = DayObjectsXYMapping.sample(
            location: CGPoint(x: 390, y: -100),
            previous: CGPoint(x: 0, y: 800),
            time: 1.001,
            previousTime: 1,
            size: CGSize(width: 390, height: 844)
        )
        XCTAssertTrue((0.35...2.4).contains(sample.filterMultiplier))
        XCTAssertTrue((0...0.25).contains(sample.expression))
    }
}
~~~

- [ ] **Step 3: Run tests and confirm missing-type failures**

~~~bash
xcodebuild test \
  -project Steps4.xcodeproj \
  -scheme Steps4 \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:Steps4Tests/DayObjectsVoiceAllocatorTests \
  -only-testing:Steps4Tests/DayObjectsXYMappingTests
~~~

- [ ] **Step 4: Implement allocation as value semantics**

Use monotonic integer IDs and sequence counters; do not use wall-clock time:

~~~swift
enum DayObjectsVoiceRole: Equatable, Sendable {
    case audition
    case xy
}

struct DayObjectsVoiceLease: Equatable, Sendable {
    let id: Int
    var role: DayObjectsVoiceRole
    var note: UInt8
    var sequence: UInt64
}

struct DayObjectsVoiceAllocation: Equatable, Sendable {
    let id: Int
    let stolenID: Int?
}

struct DayObjectsVoiceAllocator: Equatable, Sendable {
    let capacity: Int
    private(set) var active: [DayObjectsVoiceLease] = []

    mutating func acquire(role: DayObjectsVoiceRole, note: UInt8) -> DayObjectsVoiceAllocation
    mutating func release(id: Int)
    mutating func releaseAll()
}
~~~

When role is .xy and a lease already exists, update and return that lease. Otherwise use a free ID in 0..<capacity. When full, choose min sequence among .audition; only fall back to the oldest lease if no audition exists.

- [ ] **Step 5: Implement deterministic XY mapping**

~~~swift
struct DayObjectsXYSample: Equatable, Sendable {
    let note: UInt8
    let filterMultiplier: Float
    let expression: Float
}

enum DayObjectsXYMapping {
    static let scale = [0, 2, 3, 5, 7, 9, 10]
    static func note(normalizedX: Double) -> UInt8
    static func sample(
        location: CGPoint,
        previous: CGPoint?,
        time: TimeInterval,
        previousTime: TimeInterval?,
        size: CGSize
    ) -> DayObjectsXYSample
}
~~~

Clamp normalized X/Y before mapping. Spread twenty-one notes from MIDI 50 across three D Dorian octaves. Compute points-per-second from successive touch samples, normalize 0...1 over 0...1,200 points/second, then multiply by 0.25.

- [ ] **Step 6: Run tests**

Run the Task 3 test command again. Expected: all allocator and mapping tests pass.

- [ ] **Step 7: Commit pure performance policies**

~~~bash
git add \
  StepsTrader/Experiments/DayObjects/Sound/DayObjectsVoiceAllocator.swift \
  StepsTrader/Experiments/DayObjects/Sound/DayObjectsXYMapping.swift \
  Steps4Tests/DayObjectsVoiceAllocatorTests.swift \
  Steps4Tests/DayObjectsXYMappingTests.swift \
  Steps4.xcodeproj/project.pbxproj
git commit -m "feat: define bounded Day Objects performance policies"
~~~

---

### Task 4: Build the Controller Contract and Lifecycle with a Fake Engine

**Files:**
- Create: StepsTrader/Experiments/DayObjects/Sound/DayObjectsSoundEngineProtocol.swift
- Create: StepsTrader/Experiments/DayObjects/Sound/NoopDayObjectsSoundEngine.swift
- Create: StepsTrader/Experiments/DayObjects/Sound/DayObjectsLabSoundController.swift
- Create: Steps4Tests/DayObjectsLabSoundControllerTests.swift
- Modify: Steps4.xcodeproj/project.pbxproj

**Interfaces:**
- Consumes: DayObjectsPresetCatalog and DayObjectsSynthPreset from Task 2.
- Produces: @MainActor DayObjectsSoundEngineProtocol and @Observable DayObjectsLabSoundController used by the concrete engine and SwiftUI.

- [ ] **Step 1: Define the exact engine seam**

~~~swift
import AVFoundation

enum DayObjectsSoundEngineState: Equatable, Sendable {
    case off
    case starting
    case on
    case error(String)
}

@MainActor
protocol DayObjectsSoundEngineProtocol: AnyObject {
    var state: DayObjectsSoundEngineState { get }
    func start() async throws
    func stop() async
    func selectPreset(_ preset: DayObjectsSynthPreset) async throws
    func auditionNote(midi: UInt8)
    func auditionChord(_ notes: [UInt8])
    func beginXY(note: UInt8, filterMultiplier: AUValue)
    func updateXY(note: UInt8, filterMultiplier: AUValue, expression: AUValue)
    func endXY()
}
~~~

- [ ] **Step 2: Write failing controller lifecycle tests**

Use a recording fake local to the test file:

~~~swift
import AVFoundation
import XCTest
@testable import Steps4

@MainActor
final class RecordingDayObjectsSoundEngine: DayObjectsSoundEngineProtocol {
    var state: DayObjectsSoundEngineState = .off
    var commands: [String] = []
    var startError: Error?

    func start() async throws {
        commands.append("start")
        if let startError { throw startError }
        state = .on
    }
    func stop() async { commands.append("stop"); state = .off }
    func selectPreset(_ preset: DayObjectsSynthPreset) async throws {
        commands.append("preset:\(preset.id)")
    }
    func auditionNote(midi: UInt8) { commands.append("note:\(midi)") }
    func auditionChord(_ notes: [UInt8]) { commands.append("chord:\(notes)") }
    func beginXY(note: UInt8, filterMultiplier: AUValue) { commands.append("xy-begin") }
    func updateXY(note: UInt8, filterMultiplier: AUValue, expression: AUValue) { commands.append("xy-update") }
    func endXY() { commands.append("xy-end") }
}
~~~

Test these exact scenarios:

~~~swift
func testStartsOnlyAfterExplicitToggle() async throws
func testStartFailureLeavesRetryableErrorAndSecondToggleRetries() async throws
func testSelectingCategoryPicksItsFirstPreset() async throws
func testNoteAndChordAreIgnoredWhileOff() async throws
func testSoundOffEndsXYBeforeStopping() async throws
func testInactiveAndBackgroundStopWithoutAutoResume() async throws
func testGridModeEndsXYButLeavesAuditionAvailable() async throws
~~~

For each test, load the real pure catalog, inject RecordingDayObjectsSoundEngine, then assert the exact command order. The stop assertions must be ["xy-end", "stop"], not only the final state.

- [ ] **Step 3: Run and confirm controller tests fail**

~~~bash
xcodebuild test \
  -project Steps4.xcodeproj \
  -scheme Steps4 \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:Steps4Tests/DayObjectsLabSoundControllerTests
~~~

- [ ] **Step 4: Implement the observable controller**

~~~swift
import Observation
import SwiftUI

@MainActor
@Observable
final class DayObjectsLabSoundController {
    private(set) var state: DayObjectsSoundEngineState = .off
    private(set) var lastError: String?
    private(set) var isGridMode = false
    var selectedCategory: DayObjectsPresetCategory
    var selectedPresetID: String

    private(set) var catalog: DayObjectsPresetCatalog
    private let engine: DayObjectsSoundEngineProtocol
    private let catalogLoader: () throws -> DayObjectsPresetCatalog

    var selectedPreset: DayObjectsSynthPreset { get }
    var selectedManifestEntry: DayObjectsPresetManifestEntry { get }
    var presetsInSelectedCategory: [DayObjectsSynthPreset] { get }
    var auditionEnabled: Bool { state == .on }
    var xyEnabled: Bool { state == .on && !isGridMode }

    init(
        catalog: DayObjectsPresetCatalog,
        engine: DayObjectsSoundEngineProtocol,
        catalogLoader: @escaping () throws -> DayObjectsPresetCatalog,
        initialError: String? = nil
    )
    func toggleSound() async
    func selectCategory(_ category: DayObjectsPresetCategory) async
    func selectPreset(id: String) async
    func auditionNote()
    func auditionChord()
    func beginXY(_ sample: DayObjectsXYSample)
    func updateXY(_ sample: DayObjectsXYSample)
    func endXY()
    func setGridMode(_ enabled: Bool)
    func handleScenePhase(_ phase: ScenePhase) async
    func handleInterruptionBegan() async
}
~~~

Initialize with the first Pad preset and never persist selection. If initialError is non-nil, initialize state as .error(initialError); otherwise initialize it as .off. toggleSound transitions off/error -> starting -> select selected preset -> on. A second press in on ends XY and awaits stop. Every thrown error becomes .error with a short localizedDescription and remains toggleable.

If catalog.isAvailable is false, toggleSound calls catalogLoader first. A successful retry replaces catalog and resets selection to its first Pad; a failed retry stays in error and never asks the engine to start. Tests pass { catalog } as catalogLoader; makeDefault passes { try .load(bundle: .main) }.

- [ ] **Step 5: Implement the UI-test no-op engine**

NoopDayObjectsSoundEngine must mirror state transitions and accept all commands without creating AVAudioSession or AudioKit nodes. It is selected only when ProcessInfo arguments contain -dayObjectsFakeAudio. Do not let this argument affect any non-lab route.

- [ ] **Step 6: Run controller tests**

Run the Task 4 test command. Expected: all lifecycle and retry tests pass.

- [ ] **Step 7: Commit the lifecycle seam**

~~~bash
git add \
  StepsTrader/Experiments/DayObjects/Sound/DayObjectsSoundEngineProtocol.swift \
  StepsTrader/Experiments/DayObjects/Sound/NoopDayObjectsSoundEngine.swift \
  StepsTrader/Experiments/DayObjects/Sound/DayObjectsLabSoundController.swift \
  Steps4Tests/DayObjectsLabSoundControllerTests.swift \
  Steps4.xcodeproj/project.pbxproj
git commit -m "feat: add Day Objects sound lifecycle controller"
~~~

---

### Task 5: Implement the Native AudioKit Voice Graph

**Files:**
- Create: StepsTrader/Experiments/DayObjects/Sound/AudioKitDayObjectsVoice.swift
- Create: StepsTrader/Experiments/DayObjects/Sound/AudioKitDayObjectsSoundEngine.swift
- Create: Steps4Tests/AudioKitDayObjectsSoundEngineTests.swift
- Modify: Steps4.xcodeproj/project.pbxproj

**Interfaces:**
- Consumes: DayObjectsSoundEngineProtocol, DayObjectsVoiceAllocator, and DayObjectsSynthPreset.
- Produces: AudioKitDayObjectsSoundEngine, the default real engine for DayObjectsLabView.

- [ ] **Step 1: Write failing graph-state tests around a backend seam**

Expose an internal backend seam and debug metrics without exposing AudioKit nodes:

~~~swift
struct DayObjectsSoundEngineMetrics: Equatable {
    let isRunning: Bool
    let activeVoiceCount: Int
    let graphGeneration: Int
}

@MainActor
protocol DayObjectsAudioBackendProtocol: AnyObject {
    var isRunning: Bool { get }
    var configuredVoiceCount: Int { get }
    var graphGeneration: Int { get }

    func start() async throws
    func stop() async
    func configure(_ preset: DayObjectsSynthPreset, crossfade: Duration) async throws
    func gateOn(
        voiceID: Int,
        note: UInt8,
        filterMultiplier: AUValue,
        expression: AUValue
    )
    func update(
        voiceID: Int,
        note: UInt8,
        filterMultiplier: AUValue,
        expression: AUValue
    )
    func gateOff(voiceID: Int)
    func releaseAll(maximumWait: Duration) async
}
~~~

Add tests:

~~~swift
import AVFoundation
import XCTest
@testable import Steps4

@MainActor
final class AudioKitDayObjectsSoundEngineTests: XCTestCase {
    func testStartIsIdempotent() async throws
    func testStopReleasesAllVoicesAndStopsBackend() async throws
    func testRepeatedStartStopDoesNotGrowVoicePool() async throws
    func testPresetSelectionReleasesPreviousGeneration() async throws
    func testAuditionAndXYNeverExceedSixVoices() async throws
    func testXYCancellationLeavesNoXYLease() async throws
}
~~~

Inject a DayObjectsAudioBackendProtocol test backend that records session activation, graph start/stop, configure calls, voice gates, and graph generation. AudioKitDayObjectsSoundEngine owns the allocator and timed audition tasks; the backend owns AVAudioSession plus the fixed graph. This test backend must not touch an audio device.

AudioKitDayObjectsSoundEngine exposes an internal read-only metrics property assembled from backend state plus allocator.active.count. Note and Chord call gateOn with filterMultiplier 1 and expression 0; beginXY passes the first touch's filterMultiplier immediately.

- [ ] **Step 2: Run and confirm engine tests fail**

~~~bash
xcodebuild test \
  -project Steps4.xcodeproj \
  -scheme Steps4 \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:Steps4Tests/AudioKitDayObjectsSoundEngineTests
~~~

- [ ] **Step 3: Build one reusable AudioKit voice**

AudioKitDayObjectsVoice owns:

~~~text
MorphingOscillator 1 ─┐
MorphingOscillator 2 ─┤
MorphingOscillator sub ┼─ source Mixer ─┬─ low-pass ──┐
WhiteNoise ───────────┘
                                    ├─ band-pass ─┼─ filter Mixer
                                    └─ high-pass ─┘
                                                   ↓
                                      AmplitudeEnvelope
                                                   ↓
                                             voice Mixer
~~~

Use these AudioKit/Soundpipe nodes:

~~~swift
import AudioKit
import SoundpipeAudioKit

let tables = [Table(.sine), Table(.triangle), Table(.sawtooth), Table(.square)]
let oscillator1 = MorphingOscillator(waveformArray: tables)
let oscillator2 = MorphingOscillator(waveformArray: tables)
let sub = MorphingOscillator(waveformArray: tables)
let noise = WhiteNoise()
let sourceMixer = Mixer(oscillator1, oscillator2, sub, noise)
let lowPass = MoogLadder(sourceMixer)
let bandPass = BandPassButterworthFilter(sourceMixer)
let highPass = HighPassButterworthFilter(sourceMixer)
let filterMixer = Mixer(lowPass, bandPass, highPass)
let envelope = AmplitudeEnvelope(filterMixer)
let output = Mixer(envelope)
~~~

Map normalized wavePosition * 3 to each MorphingOscillator index. Select sine or square on the sub by setting index to 0 or 3. Apply oscillator levels, balance, sub level, and noise level directly from the normalized plan. Apply oscillator semitone and fine detune as frequency multipliers; note changes ramp over performance.glide, clamped to 0...0.5 seconds. Set exactly one filter branch mixer volume to one and the others to zero while the voice is silent. Use the filter envelope to ramp the active branch cutoff from its bounded start to peak during attack, toward sustain during decay, and back toward start on release. Use Parameter.ramp(to:duration:) for audible changes. Gate and release every node; stop generators only after the preset release duration has elapsed.

Never reinterpret an unsupported filter as extra resonance.

Implement the one normalized LFO path as a single engine-owned control-rate task. At 30 Hz it computes a sine phase from modulation.rateHz and ramps the selected target over the next 1/30 second: oscillator frequency for pitch, the active branch cutoff for filter, or voice output volume for amplitude. Cancel and replace this task on preset selection and stop. Base depth comes from the preset; XY expression may add at most 0.25 and must not change an inactive target.

- [ ] **Step 4: Build the fixed six-voice shared graph**

Create all six voices before starting the engine. Do not add or remove mixer inputs while AudioEngine is running.

~~~text
6 voice outputs
      ↓
voice Mixer
      ↓
Phaser
      ↓
VariableDelay
      ↓
 ┌──────────────────── dry ────────────────────┐
 └─ CostelloReverb (100% wet) ─ HighPass ─────┤
                                               ↓
                                         reverb Mixer
      ↓
AutoPanner
      ↓
PeakLimiter (preGain -8 dB)
      ↓
master Mixer (preset outputTrim)
      ↓
AudioEngine.output
~~~

The concrete graph uses:

~~~swift
let voiceMixer = Mixer(voices.map(\.output))
let phaser = Phaser(voiceMixer)
let delay = VariableDelay(phaser, maximumTime: 2)
let reverb = CostelloReverb(delay, balance: 1)
let reverbHighPass = HighPassButterworthFilter(reverb)
let reverbMixer = Mixer(delay, reverbHighPass)
let autoPanner = AutoPanner(reverbMixer)
let limiter = PeakLimiter(autoPanner, attackTime: 0.003, decayTime: 0.04, preGain: -8)
let master = Mixer(limiter)
engine.output = master
~~~

Set dry and wet reverbMixer input volumes to 1 - reverbMix and reverbMix, and map reverbHighPass to the wet branch only. Treat widen as a bounded addition to AutoPanner depth; do not create a second stereo processor. Apply the selected preset's shared effect parameters with 0.12-second ramps.

- [ ] **Step 5: Implement session and engine lifecycle**

On start:

~~~swift
try session.setCategory(.playback, mode: .default, options: [])
try session.setActive(true)
try engine.start()
~~~

On stop, interruption, disappearance, or background:

1. end XY;
2. close every envelope gate;
3. wait only for the longest bounded release still active, capped at 0.8 seconds;
4. stop generators and AudioEngine;
5. deactivate with .notifyOthersOnDeactivation;
6. reset allocator and metrics.

The SwiftUI lab owns the AVAudioSession interruption subscription and forwards interruption-began through the controller. The concrete engine does not register a second observer and never auto-restarts on interruption-ended.

For Note, gate one lease for 0.55 seconds. For Chord, gate four notes for 0.8 seconds. Store cancellation tasks per lease so stolen/released voices cannot be closed later by a stale task.

- [ ] **Step 6: Implement click-free preset selection**

When running, selectPreset must:

1. close active gates;
2. ramp master to zero over 0.06 seconds;
3. apply the new voice and shared-effect parameters;
4. increment graphGeneration;
5. ramp master to outputTrim over 0.06 seconds.

When off, store the preset without activating the session or engine.

- [ ] **Step 7: Run engine and pure tests**

~~~bash
xcodebuild test \
  -project Steps4.xcodeproj \
  -scheme Steps4 \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:Steps4Tests/AudioKitDayObjectsSoundEngineTests \
  -only-testing:Steps4Tests/DayObjectsVoiceAllocatorTests \
  -only-testing:Steps4Tests/SynthOnePresetAdapterTests
~~~

Expected: all tests pass and the test backend reports a fixed pool of six voices after repeated cycles.

- [ ] **Step 8: Run a real AudioKit smoke launch**

Launch the app on the simulator with:

~~~text
-uiLab dayObjects
~~~

Press Sound, Note, Chord, Sound. Expected: no crash, no stuck tone, and the system log contains no AVAudioEngine graph error.

- [ ] **Step 9: Commit the native engine**

~~~bash
git add \
  StepsTrader/Experiments/DayObjects/Sound/AudioKitDayObjectsVoice.swift \
  StepsTrader/Experiments/DayObjects/Sound/AudioKitDayObjectsSoundEngine.swift \
  Steps4Tests/AudioKitDayObjectsSoundEngineTests.swift \
  Steps4.xcodeproj/project.pbxproj
git commit -m "feat: implement native Day Objects preset engine"
~~~

---

### Task 6: Add Sound and Preset Controls to Day Objects Lab

**Files:**
- Create: StepsTrader/Experiments/DayObjects/Sound/DayObjectsSoundControls.swift
- Modify: StepsTrader/Experiments/DayObjects/DayObjectsLabView.swift
- Modify: Steps4UITests/DayObjectsLabUITests.swift
- Modify: Steps4.xcodeproj/project.pbxproj

**Interfaces:**
- Consumes: DayObjectsLabSoundController and AudioKitDayObjectsSoundEngine.
- Produces: stable accessibility IDs dayObjects.sound.toggle, dayObjects.sound.category, dayObjects.sound.preset, dayObjects.sound.note, dayObjects.sound.chord, and dayObjects.sound.source.

- [ ] **Step 1: Add failing UI coverage using fake audio**

Every sound UI test launches with:

~~~swift
app.launchArguments = [
    "-uiLab", "dayObjects",
    "-dayObjectsFakeAudio",
    "-AppleLanguages", "(en)",
    "-AppleLocale", "en_US",
]
~~~

Add:

~~~swift
func testSoundStartsOffAndEnablesAuditionAfterExplicitTap() throws {
    let app = launchDayObjectsLab()
    let sound = app.buttons["dayObjects.sound.toggle"]
    XCTAssertTrue(sound.waitForExistence(timeout: 5))
    XCTAssertEqual(sound.value as? String, "Off")
    XCTAssertFalse(app.buttons["dayObjects.sound.note"].isEnabled)
    sound.tap()
    XCTAssertEqual(sound.value as? String, "On")
    XCTAssertTrue(app.buttons["dayObjects.sound.note"].isEnabled)
    XCTAssertTrue(app.buttons["dayObjects.sound.chord"].isEnabled)
}

func testEachCategoryExposesThreePresets() throws
func testSoundOffDisablesNoteAndChord() throws
func testGridKeepsAuditionButtonsEnabled() throws
~~~

Use accessibility values such as "Pad, 3 presets" and "Interstellar, Bonus" so the tests do not need to scrape visual text.

- [ ] **Step 2: Run the new UI test and confirm failure**

~~~bash
xcodebuild test \
  -project Steps4.xcodeproj \
  -scheme Steps4 \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:Steps4UITests/DayObjectsLabUITests/testSoundStartsOffAndEnablesAuditionAfterExplicitTap
~~~

- [ ] **Step 3: Build the compact control view**

DayObjectsSoundControls renders:

~~~text
[Pad | Pluck | Bass | Lead]
[Interstellar ▾] [Note] [Chord]
Preset source: AudioKit Synth One · Bonus
~~~

Requirements:

- category is a segmented Picker;
- preset is a Menu containing exactly the selected category's three manifest names;
- Note and Chord remain visible but disabled unless state is on;
- an inline error uses the controller's short message and tells the user to press Sound to retry;
- grid mode adds "Touch performance unavailable in Grid";
- the source line always names AudioKit Synth One and the selected source bank;
- all six accessibility identifiers are stable.

- [ ] **Step 4: Own one controller in DayObjectsLabView**

Add a designated initializer for tests/previews and a default factory:

~~~swift
@State private var soundController: DayObjectsLabSoundController

init(soundController: DayObjectsLabSoundController? = nil) {
    let controller = soundController ?? DayObjectsLabSoundController.makeDefault()
    _soundController = State(initialValue: controller)
}
~~~

makeDefault loads the catalog and chooses NoopDayObjectsSoundEngine only for -dayObjectsFakeAudio; otherwise it creates AudioKitDayObjectsSoundEngine. Add DayObjectsPresetCatalog.unavailable, containing one silent internal fallback preset not exposed as a valid manifest entry. A catalog loading failure uses that fallback, sets the controller to a non-playing error state, and keeps Day Objects rendering; pressing Sound retries the bundle load before it attempts to start audio.

Keep the entire @State controller property, initializer, controls, Sound button, XY layer, lifecycle handlers, and AVFoundation import inside #if DEBUG || INTERNAL_BUILD branches. The existing release form of DayObjectsLabView remains the current visual-only implementation.

Add the sound section to the existing material control card without removing or renaming any current controls. Call setGridMode whenever showsGrid changes.

- [ ] **Step 5: Add the always-visible circular Sound button**

Place it at top-left, symmetrical with the existing top-right controls-toggle button. It must remain visible when showControls is false.

State presentation:

~~~text
off      speaker.slash.fill     value "Off"       enabled
starting waveform               value "Starting"  disabled
on       speaker.wave.2.fill    value "On"        enabled
error    exclamationmark.waveform value "Error"   enabled
~~~

The tap starts one Task that awaits soundController.toggleSound(). Do not start sound in onAppear.

- [ ] **Step 6: Wire lifecycle stops**

Add scenePhase and interruption handling:

~~~swift
.onDisappear {
    Task { await soundController.handleScenePhase(.background) }
}
.onChange(of: scenePhase) { _, phase in
    Task { await soundController.handleScenePhase(phase) }
}
.onReceive(
    NotificationCenter.default.publisher(
        for: AVAudioSession.interruptionNotification
    )
) { notification in
    guard DayObjectsAudioInterruption.isBegan(notification) else { return }
    Task { await soundController.handleInterruptionBegan() }
}
~~~

Do not react to .active by starting sound.

- [ ] **Step 7: Run UI and existing Day Objects regression tests**

~~~bash
xcodebuild test \
  -project Steps4.xcodeproj \
  -scheme Steps4 \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:Steps4UITests/DayObjectsLabUITests \
  -only-testing:Steps4Tests/DayObjectSceneTests \
  -only-testing:Steps4Tests/DayObjectsLabSoundControllerTests
~~~

Expected: old choreography/spent-colors tests and all new sound-control tests pass.

- [ ] **Step 8: Commit the audition controls**

~~~bash
git add \
  StepsTrader/Experiments/DayObjects/Sound/DayObjectsSoundControls.swift \
  StepsTrader/Experiments/DayObjects/DayObjectsLabView.swift \
  Steps4UITests/DayObjectsLabUITests.swift \
  Steps4.xcodeproj/project.pbxproj
git commit -m "feat: add sound controls to Day Objects lab"
~~~

---

### Task 7: Add Safe Single-Canvas XY Performance

**Files:**
- Create: StepsTrader/Experiments/DayObjects/Sound/DayObjectsXYSurface.swift
- Modify: StepsTrader/Experiments/DayObjects/DayObjectsLabView.swift
- Modify: Steps4Tests/DayObjectsXYMappingTests.swift
- Modify: Steps4UITests/DayObjectsLabUITests.swift
- Modify: Steps4.xcodeproj/project.pbxproj

**Interfaces:**
- Consumes: DayObjectsXYMapping, DayObjectsLabSoundController.xyEnabled, and DayObjectsLabView.uiExclusionRegion.
- Produces: one begin/update/end sequence for a single touch outside controls.

- [ ] **Step 1: Add failing exclusion and cancellation tests**

Extend DayObjectsXYMappingTests:

~~~swift
func testLabControlRegionRejectsTouchesInBottomFortyTwoPercent() {
    let size = CGSize(width: 390, height: 844)
    XCTAssertFalse(DayObjectsXYMapping.isPlayable(
        location: CGPoint(x: 195, y: 700),
        size: size,
        exclusion: .dayObjectsLabControls
    ))
    XCTAssertTrue(DayObjectsXYMapping.isPlayable(
        location: CGPoint(x: 195, y: 200),
        size: size,
        exclusion: .dayObjectsLabControls
    ))
}
~~~

Extend the UI test to assert dayObjects.xy.surface exists in single mode, has value "Sound off" before Sound, value "Ready" after Sound, and value "Unavailable in Grid" after toggling Grid.

- [ ] **Step 2: Run the focused tests and confirm failure**

~~~bash
xcodebuild test \
  -project Steps4.xcodeproj \
  -scheme Steps4 \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:Steps4Tests/DayObjectsXYMappingTests \
  -only-testing:Steps4UITests/DayObjectsLabUITests/testGridKeepsAuditionButtonsEnabled
~~~

- [ ] **Step 3: Implement the transparent gesture adapter**

DayObjectsXYSurface accepts enabled, exclusion, onBegin, onUpdate, and onEnd. Use DragGesture(minimumDistance: 0) and store the prior location/time in @State.

Rules:

- ignore touches while disabled;
- ignore touches whose normalized location is inside the exclusion region;
- begin only once per gesture;
- update the existing XY voice, never allocate another;
- call end on gesture end, cancellation, transition to disabled, disappearance, or grid-mode change;
- expose accessibilityIdentifier dayObjects.xy.surface;
- accessibilityValue is Sound off, Ready, or Unavailable in Grid;
- when accessibilityVoiceOverEnabled is true, do not attach the drag gesture.

- [ ] **Step 4: Layer XY without intercepting controls**

In the single-canvas branch, layer in this order:

~~~text
DayObjectsView
DayObjectsXYSurface
material control card
top-left Sound button
top-right controls toggle
~~~

The control card and buttons remain above the gesture surface. Keep uiExclusionRegion equal to .dayObjectsLabControls; do not change DayObjectScene input or choreography.

- [ ] **Step 5: Run mapping, controller, UI, and scene regression tests**

~~~bash
xcodebuild test \
  -project Steps4.xcodeproj \
  -scheme Steps4 \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:Steps4Tests/DayObjectsXYMappingTests \
  -only-testing:Steps4Tests/DayObjectsLabSoundControllerTests \
  -only-testing:Steps4Tests/DayObjectSceneTests \
  -only-testing:Steps4UITests/DayObjectsLabUITests
~~~

Expected: all pass. The grid retains Note and Chord but reports XY unavailable.

- [ ] **Step 6: Commit XY performance**

~~~bash
git add \
  StepsTrader/Experiments/DayObjects/Sound/DayObjectsXYSurface.swift \
  StepsTrader/Experiments/DayObjects/DayObjectsLabView.swift \
  Steps4Tests/DayObjectsXYMappingTests.swift \
  Steps4UITests/DayObjectsLabUITests.swift \
  Steps4.xcodeproj/project.pbxproj
git commit -m "feat: add expressive Day Objects touch performance"
~~~

---

### Task 8: Calibrate on iPhone and Complete Verification

**Files:**
- Modify if calibration requires it: StepsTrader/Experiments/DayObjects/Sound/DayObjectsPresetManifest.swift
- Modify if a conversion defect is found: StepsTrader/Experiments/DayObjects/Sound/SynthOnePresetAdapter.swift
- Modify if a graph defect is found: StepsTrader/Experiments/DayObjects/Sound/AudioKitDayObjectsSoundEngine.swift
- Modify if tests expose it: Steps4Tests/DayObjectsPresetCatalogTests.swift
- Modify if tests expose it: Steps4Tests/SynthOnePresetAdapterTests.swift
- Modify if tests expose it: Steps4Tests/DayObjectsVoiceAllocatorTests.swift
- Modify if tests expose it: Steps4Tests/DayObjectsXYMappingTests.swift
- Modify if tests expose it: Steps4Tests/DayObjectsLabSoundControllerTests.swift
- Modify if tests expose it: Steps4Tests/AudioKitDayObjectsSoundEngineTests.swift

**Interfaces:**
- Consumes: complete lab from Tasks 1–7.
- Produces: listening-approved trims, clean lifecycle behavior, full automated verification, and a device QA record in the commit message/body.

- [ ] **Step 1: Run the complete automated suite**

~~~bash
xcodebuild test \
  -project Steps4.xcodeproj \
  -scheme Steps4 \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
~~~

Expected: TEST SUCCEEDED. If unrelated pre-existing tests fail, record their exact names and separately demonstrate every new/modified Day Objects test passes.

- [ ] **Step 2: Verify release isolation**

~~~bash
xcodebuild build \
  -project Steps4.xcodeproj \
  -scheme Steps4 \
  -configuration Release \
  -destination 'generic/platform=iOS Simulator'
~~~

Expected: BUILD SUCCEEDED, ExperimentalFeatures.dayObjectsLab is false, no production view links to DayObjectsLabView, and the new Sound sources compile to no declarations because DEBUG and INTERNAL_BUILD are both absent.

- [ ] **Step 3: Install and audition on a physical iPhone**

Use headphones first at a low hardware volume, then the built-in speaker. Open Settings -> Appearance -> Day Objects in an internal/debug build.

For every preset:

1. press Note twice;
2. press Chord once;
3. drag slowly left-to-right in the upper 58% of the canvas;
4. make one faster vertical movement;
5. switch to the next preset while a release tail is audible;
6. mark audible character, relative level, latency, click, and stuck-note status.

The exact acceptance grid is:

~~~text
Pad:   Interstellar / Whispering Sands / PAD - Forgotten Stories
Pluck: PLK - Play Something Sad / JEC Ambient Pizz 2 / 🕷- Filter Pluck
Bass:  Analog Boom Bass / BB Röy’s Phaser Bass / JEC Hollores Bass 2
Lead:  Verbacious Lead / JEC Softwah Lead 2 / BB The Silver Screen Lead
~~~

Keep the initial trims from Task 2 unless a preset is clearly outside the group. If adjustment is required, change only outputTrim in 0.02 increments, remain inside 0.05...0.50, rerun all twelve, and add a unit assertion for the accepted trim.

- [ ] **Step 4: Exercise interruption and teardown**

On the device:

- Sound on -> lock screen -> unlock: sound remains off until pressed;
- Sound on -> Control Center interruption -> return: sound remains off until pressed;
- Sound on -> leave lab -> return: sound is off;
- repeat Sound on/off ten times: no node growth, crash, click, or stuck note;
- Grid while sound is on: Note and Chord work, touching tiles does not play;
- enable VoiceOver: exploring the canvas does not begin XY notes;
- enable Reduce Motion: audio envelopes do not change.

- [ ] **Step 5: Re-run focused verification after calibration**

~~~bash
xcodebuild test \
  -project Steps4.xcodeproj \
  -scheme Steps4 \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:Steps4Tests/DayObjectsPresetCatalogTests \
  -only-testing:Steps4Tests/SynthOnePresetAdapterTests \
  -only-testing:Steps4Tests/DayObjectsVoiceAllocatorTests \
  -only-testing:Steps4Tests/DayObjectsXYMappingTests \
  -only-testing:Steps4Tests/DayObjectsLabSoundControllerTests \
  -only-testing:Steps4Tests/AudioKitDayObjectsSoundEngineTests \
  -only-testing:Steps4UITests/DayObjectsLabUITests
~~~

Expected: all focused tests pass.

- [ ] **Step 6: Inspect the final diff for scope**

~~~bash
git diff --check
git status --short
git diff --stat HEAD~7
~~~

Confirm there is no production Canvas mapping, automatic scheduling, percussion, HealthKit access, copied Synth One UI, or unrelated file staged.

- [ ] **Step 7: Commit only necessary calibration changes**

If calibration changed files:

~~~bash
git add \
  StepsTrader/Experiments/DayObjects/Sound/DayObjectsPresetManifest.swift \
  StepsTrader/Experiments/DayObjects/Sound/SynthOnePresetAdapter.swift \
  StepsTrader/Experiments/DayObjects/Sound/AudioKitDayObjectsSoundEngine.swift \
  Steps4Tests/DayObjectsPresetCatalogTests.swift \
  Steps4Tests/SynthOnePresetAdapterTests.swift \
  Steps4Tests/DayObjectsVoiceAllocatorTests.swift \
  Steps4Tests/DayObjectsXYMappingTests.swift \
  Steps4Tests/DayObjectsLabSoundControllerTests.swift \
  Steps4Tests/AudioKitDayObjectsSoundEngineTests.swift
git commit -m "test: calibrate Day Objects preset lab on iPhone"
~~~

If no calibration change is needed, do not create an empty commit.

## Final Acceptance Checklist

- Day Objects Lab opens with its existing visual behavior and Sound off.
- Sound explicitly starts and fully stops native playback.
- The catalog contains exactly three attributed presets in each of Pad, Pluck, Bass, and Lead.
- Note and Chord audition the selected preset in category-appropriate registers.
- Single-canvas touch produces one bounded expressive voice; Grid and VoiceOver do not.
- Preset switching, gesture end, Sound off, disappearance, backgrounding, and interruption do not click or leave stuck notes.
- Six-voice capacity and oldest-audition stealing remain enforced.
- All new pure, controller, engine, and UI tests pass.
- The full existing Day Objects test coverage remains green.
- A physical-iPhone pass confirms the twelve voices are distinct, conservatively leveled, and usable enough to inform the later generative Canvas phase.
