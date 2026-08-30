# Day Objects Synth One Preset Lab Design

**Date:** 2026-08-30

## Goal

Add a native sound-audition layer to the existing Day Objects experimental lab so selected AudioKit Synth One presets can be evaluated on a real iPhone before any generative audio system is connected to the production Canvas.

The lab must exercise the same native synthesis code that can later be used by the production app. It is not another browser approximation, a clone of the Synth One application, or a production feature.

## Product decision

Use a modern AudioKit engine and a bounded adapter for selected Synth One preset JSON. Do not embed the legacy Synth One application or its UI, and do not render the presets to fixed audio samples.

This gives the lab reusable native voices while avoiding a dependency on Synth One's historical CocoaPods project and older AudioKit internals. A converted preset is expected to preserve its recognizable oscillator, envelope, filter, modulation, and effect character, but it is not required to be sample-identical to the original Synth One build.

## Scope

The first implementation remains inside the existing Day Objects debug/internal lab.

Included:

- modern AudioKit added as a pinned Swift Package dependency;
- a UI-independent native sound engine with explicit lifecycle control;
- a decoder for the supported subset of Synth One preset JSON;
- a curated manifest of exactly twelve official presets: three Pad, three Pluck, three Bass, and three Lead;
- manual category and preset selection;
- explicit Sound On/Off control;
- Note and Chord audition actions;
- monophonic XY performance over the unobstructed Day Objects surface;
- gain normalization and click-free preset changes;
- unit, lifecycle, and lab UI tests;
- AudioKit/Synth One attribution and the MIT license notice.

Not included:

- automatic music, chord progressions, rhythms, or happening scheduling;
- percussion or a drum preset bank;
- Steps, Sleep, Glitch, or Remix audio mappings;
- production Canvas integration;
- HealthKit reads or user data;
- copying the Synth One interface, graphics, navigation, or full application engine;
- exact emulation of every Synth One parameter;
- background audio or playback while the app is suspended.

## Existing lab integration

`DayObjectsLabView` remains the root of the experiment. The current Day Objects rendering, controls, grid mode, stable fixture happenings, and accessibility identifiers remain intact.

The sound layer compiles only when the Day Objects experimental surface is available. It is reachable through the current debug launch route (`-uiLab dayObjects`) and the existing internal-build Settings link. Release builds with `ExperimentalFeatures.dayObjectsLab == false` do not expose the lab.

The audio engine does not depend on `DayObjectScene`, Metal rendering, SwiftUI view state, app stores, HealthKit, or production Canvas models. `DayObjectsLabView` owns one controller and translates UI actions into a small command surface.

## User experience

### Sound control

Sound starts disabled on every lab presentation. A circular Sound button remains visible above the Day Objects scene and exposes four states:

- `off` — audio session and engine are inactive;
- `starting` — the button is temporarily disabled and shows progress;
- `on` — audition and XY controls are enabled;
- `error` — the button remains retryable and shows a short local explanation.

Pressing Sound while off activates an `AVAudioSession` with category `.playback`, starts the AudioKit engine, and loads the selected preset. Pressing it while on releases all notes and effect tails, stops the engine, and deactivates the session. Audio never begins because the view appeared or because a preset was selected.

The engine also stops when the lab disappears, the application resigns active state, or an interruption begins. Returning to the foreground never resumes sound automatically; the user presses Sound again.

### Preset browser

When Sound is on, the existing control card gains a compact audition section:

1. a segmented category selector: Pad, Pluck, Bass, Lead;
2. a menu containing the three manifest presets in that category;
3. Note and Chord buttons;
4. the selected preset name and source bank.

Changing category selects that category's first preset. Changing preset performs a short release and crossfade rather than replacing active nodes abruptly.

`Note` plays a category-appropriate reference note with a finite hold and release. `Chord` plays a fixed open voicing from the lab's reference scale. Bass remains in a low register, Pad in a mid register, and Pluck/Lead in a mid-high register so comparisons do not confuse timbre with an unsuitable octave.

### XY performance

Touching or dragging the Day Objects canvas outside the lab control exclusion region starts one monophonic voice using the selected preset.

- horizontal position quantizes pitch to the fixed reference scale;
- vertical position controls a bounded filter-cutoff offset;
- movement speed adds a small bounded modulation-depth offset;
- lifting or cancelling the touch releases the voice.

The XY layer never creates more than one live performance voice. It does not alter Day Objects choreography or consume taps inside buttons, sliders, navigation chrome, or the existing lab control card.

Grid mode disables XY performance because fifteen visual canvases do not represent fifteen audio instruments. Preset audition buttons remain available in grid mode.

## Preset source and curation

Preset data comes only from JSON files bundled in the official `AudioKit/AudioKitSynthOne` repository. The repository's MIT license and copyright notice are copied into the app's third-party notices. The lab includes a visible “Preset source: AudioKit Synth One” line in its audition section.

The implementation maintains a small checked-in `DayObjectsPresetManifest` rather than shipping every Synth One bank. The manifest contains exactly twelve entries and records:

- stable preset ID;
- original name;
- original bank and author text when supplied;
- one of the four supported lab categories;
- source JSON resource;
- reference MIDI note and optional reference chord voicing;
- normalization trim measured for the converted voice.

Selection is a deliberate curation task. Each category must contain three audibly distinct envelope/timbre profiles. Presets that require the Synth One sequencer, arpeggiator, non-12-tone tuning, hold mode, or unsupported destructive effects to establish their identity are excluded from the first manifest. The imported source JSON is reduced to the selected preset objects, not the full original banks.

## Preset model and adapter

The source DTO decodes only named values required by the adapter while tolerating additional keys in the original JSON. Missing supported fields receive documented Synth One-compatible defaults; malformed, non-finite, or out-of-range values are clamped or rejected before reaching AudioKit nodes.

The normalized native model contains:

```swift
struct DayObjectsSynthPreset: Equatable, Sendable {
    let id: String
    let name: String
    let category: DayObjectsPresetCategory
    let oscillators: DayObjectsOscillatorPlan
    let amplitudeEnvelope: DayObjectsEnvelope
    let filter: DayObjectsFilterPlan
    let filterEnvelope: DayObjectsEnvelope
    let modulation: DayObjectsModulationPlan
    let effects: DayObjectsEffectPlan
    let performance: DayObjectsPerformancePlan
    let outputTrim: AUValue
}
```

The first adapter supports:

- two Synth One oscillator wave positions mapped to the closest supported AudioKit oscillator/table representation;
- oscillator volumes, balance, semitone offsets, fine detune, sub oscillator, and noise;
- amplitude attack, decay, sustain, release, and glide;
- filter type where compatible, cutoff, resonance, filter ADSR, and envelope mix;
- one bounded pitch/filter/amplitude LFO path per converted preset;
- delay time, feedback, and mix;
- reverb mix, feedback/decay approximation, and high-pass;
- phaser mix/rate/feedback where a compatible modern node is available;
- stereo widening or autopan as a bounded final-stage modulation.

The adapter explicitly reports unsupported source features in development diagnostics. Sequencer/arpeggiator data, custom tuning tables, MIDI mappings, bit-crush routing, compressor internals, and modulation matrix combinations outside the supported paths do not silently change unrelated parameters.

## Audio engine

`DayObjectsSoundEngine` is an actor-isolated or main-actor-owned service with this conceptual interface:

```swift
protocol DayObjectsSoundEngineProtocol: AnyObject {
    var state: DayObjectsSoundEngineState { get }
    func start() async throws
    func stop() async
    func selectPreset(_ preset: DayObjectsSynthPreset) async throws
    func auditionNote(midi: MIDINoteNumber)
    func auditionChord(_ notes: [MIDINoteNumber])
    func beginXY(note: MIDINoteNumber, filterOffset: AUValue)
    func updateXY(note: MIDINoteNumber, filterOffset: AUValue, expression: AUValue)
    func endXY()
}
```

The concrete graph has bounded polyphony sufficient for one four-note audition chord plus one monophonic XY voice during release overlap. Voice stealing always releases the oldest non-XY audition voice first. The graph owns oscillator, filter, envelope, delay, reverb, phaser, stereo, limiter, and master nodes; the SwiftUI view never holds AudioKit nodes.

Parameter changes use ramps. Preset changes release active voices, prepare the replacement graph or voice configuration off the audible path, then crossfade over 80–160 milliseconds. A conservative limiter and master trim protect against the original presets' widely different master-volume values.

The controller treats AudioKit and audio-session failures as recoverable lab errors. It never crashes or blocks Day Objects rendering when audio is unavailable.

## State and data flow

```text
Official selected preset JSON resources
                ↓
       SynthOnePresetDTO decoder
                ↓
       SynthOnePresetAdapter
                ↓
       DayObjectsSynthPreset catalog
                ↓
 DayObjectsLabSoundController (@Observable)
                ↓
       DayObjectsSoundEngine
                ↓
             AudioKit
```

The controller owns selected category, selected preset ID, engine state, and the last recoverable error. The catalog and adapter are pure and deterministic. AudioKit execution remains behind the engine protocol so model tests do not require an audio device.

No selection is persisted in the first version. Reopening the lab returns to the first Pad preset with Sound off.

## Accessibility and interaction safety

- Sound, category, preset, Note, and Chord expose stable accessibility identifiers.
- Sound announces starting, on, off, and error states.
- The preset menu announces original preset and bank names.
- XY performance is supplemental; every preset can be evaluated with Note and Chord controls.
- VoiceOver exploration over the canvas does not start notes.
- Reduce Motion affects only Day Objects visuals and does not alter audio envelopes.
- Grid mode clearly announces that touch performance is unavailable.

## Testing strategy

### Pure preset tests

- all twelve manifest entries decode and convert;
- the manifest contains exactly three unique presets per supported category;
- IDs are unique and original attribution is present;
- missing optional fields use explicit defaults;
- non-finite and out-of-range source values never reach the normalized model;
- all normalized gains, times, frequencies, feedback values, and modulation depths stay inside defined engine ranges;
- unsupported features produce deterministic diagnostics;
- identical source JSON always produces an equal normalized preset.

### Engine lifecycle tests

A narrow engine seam or test audio backend verifies:

- start is idempotent;
- Sound Off releases all audition and XY voices before stopping;
- view disappearance, interruption, and backgrounding use the same release path;
- selecting a preset cannot leave voices attached to the previous graph;
- repeated Sound On/Off cycles do not increase tracked nodes or voices;
- polyphony and voice stealing remain bounded;
- XY cancellation always ends its voice;
- failures leave the controller retryable.

### Lab UI tests

- the existing Day Objects controls and tests remain valid;
- Sound is visible and off at launch;
- preset controls are unavailable until Sound is on;
- each category exposes three presets;
- Note and Chord invoke audition while Sound is on;
- Sound Off disables audition;
- grid mode disables XY without disabling Note and Chord;
- the existing Day Objects control exclusion region still receives its gestures.

### Real-device listening pass

The lab is evaluated on a physical iPhone using headphones and the built-in speaker:

- all twelve presets are audibly distinct;
- at least one preset from each category is worth retaining for future Canvas integration;
- Note, Chord, and XY begin without distracting latency;
- preset changes and Sound Off are free of clicks and stuck notes;
- repeated background/foreground and interruption cycles recover through the Sound button;
- output remains conservative across all presets and chord audition;
- Metal animation remains smooth while audio is active.

## Acceptance criteria

- Day Objects Lab opens unchanged with Sound off.
- Pressing Sound explicitly starts native AudioKit playback and pressing it again fully stops playback.
- Exactly twelve attributed Synth One-derived presets are browsable as three Pad, three Pluck, three Bass, and three Lead entries.
- Every preset can be compared with fixed Note and Chord actions.
- Dragging the unobstructed single-canvas surface performs one expressive preset voice with bounded pitch, filter, and expression mappings.
- Preset changes, gesture release, backgrounding, interruptions, and Sound Off do not leave clicks or stuck notes.
- The original Day Objects controls, choreography, Metal renderer, grid mode, and existing UI tests remain operational.
- The audio layer is isolated from production app models and can later be called by the Canvas without rewriting preset conversion or synthesis.
- Release builds do not expose the experimental lab.
- No production Canvas integration, automatic composition, or percussion is introduced in this phase.

## Follow-up phase

After the listening pass, retained presets become the native voice bank for a second design phase. That phase will map Day Objects happenings, Steps, Sleep, Remix, and touch performance to the selected voices and add a separate percussion strategy. Rejected presets and unsupported conversion work are removed rather than carried into production.

## Source references

- AudioKit Synth One repository: <https://github.com/AudioKit/AudioKitSynthOne>
- Synth One preset data: <https://github.com/AudioKit/AudioKitSynthOne/tree/master/AudioKitSynthOne/Presets/Data>
- Synth One MIT license: <https://github.com/AudioKit/AudioKitSynthOne/blob/master/LICENSE>
