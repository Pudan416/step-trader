# Day Objects Native Instrument Bank Design

**Date:** 2026-08-30

**Parent:** [Day Objects Generative Music System](2026-08-30-day-objects-generative-music-system-design.md)

## Goal

Build and audition the reusable native voices required by the generative
system before scheduling or day-data mappings are implemented.

This subproject produces a stable instrument bank, not automatic music.

## Dependency decision

Use modern AudioKit and SoundpipeAudioKit through exact Swift Package pins.
Convert a bounded subset of official AudioKit Synth One preset JSON. Do not
embed the legacy Synth One project, CocoaPods graph, UI, sequencer, or tuning
system.

Initial exact package pins:

- AudioKit 5.7.2;
- SoundpipeAudioKit 5.7.4.

The converted timbre should remain recognizable but need not be
sample-identical to Synth One.

## Synth One source

Preset records come from AudioKitSynthOne revision:

~~~text
6466a3715c96b7ecf1dd255a218cbd571408a314
~~~

Bundle only selected objects, their bank/source metadata, and the complete
upstream MIT notice.

## Exact tonal shortlist

### Pad

| Stable ID | Bank | Preset | Source UID |
|---|---|---|---|
| pad.interstellar | Bonus | Interstellar | 39529417-FBC1-41D5-B1D1-0DED9E38F164 |
| pad.whispering-sands | Bonus | Whispering Sands | 96F9F71C-1D6C-41FC-8192-E4B550562357 |
| pad.forgotten-stories | Electronisounds | PAD - Forgotten Stories | 9BF89CC8-5AD5-46D8-9640-C3FE335C65D9 |

### Pluck

| Stable ID | Bank | Preset | Source UID |
|---|---|---|---|
| pluck.play-something-sad | Electronisounds | PLK - Play Something Sad | E9AFAF33-21A5-4A1B-80BF-74BFB333E86D |
| pluck.jec-ambient-pizz-2 | JEC | JEC Ambient Pizz 2 | 88335303-C675-4D14-907E-2D80823C2BCA |
| pluck.spider-filter-pluck | Spidericemidas | 🕷- Filter Pluck | 8FC6202C-DAE8-4651-98DE-F3BEBB07E6BF |

### Bass

| Stable ID | Bank | Preset | Source UID |
|---|---|---|---|
| bass.analog-boom | Bonus | Analog Boom Bass | C2958050-CDCA-4C64-AF92-3217539CE60A |
| bass.bb-roys-phaser | Brice Beasley | BB Röy’s Phaser Bass | 4131C811-FBB8-4E15-B238-8986645A62D3 |
| bass.jec-hollores-2 | JEC | JEC Hollores Bass 2 | FA16AF16-3033-485F-A183-4DAAB7025B52 |

### Lead

| Stable ID | Bank | Preset | Source UID |
|---|---|---|---|
| lead.verbacious | Red Sky Lullaby | Verbacious Lead | 9BDE3DCB-219D-4D70-A067-C1057B557F19 |
| lead.jec-softwah-2 | JEC | JEC Softwah Lead 2 | 2B6BCC6D-8526-4CAD-8230-EF3C84A26E9F |
| lead.bb-silver-screen | Brice Beasley | BB The Silver Screen Lead | BB74B6AD-9076-464C-B373-F2E968BBD2BE |

### Poly / Keys

| Stable ID | Bank | Preset | Source UID |
|---|---|---|---|
| keys.maschinenmensch | Bonus | Maschinenmensch Keys | AA903CDB-938B-4FC7-8E01-050DB95EFDE7 |
| keys.bb-slow-poly | Brice Beasley | BB Slow Keys Poly | 6A4C11CA-2CF9-4153-B5D3-A67F28E465A1 |
| keys.jec-polaroids-2 | JEC | JEC Gentlemen Take Polaroids 2 | 9F2D32B0-ED71-4127-A4C5-F51209656AF7 |

All selected presets have source arpeggiator and hold mode disabled. Sequencer
behavior is never required to hear their identity.

## Converted preset model

The normalized voice describes:

- two morphing oscillators;
- levels, balance, semitone offsets, fine detune;
- sine/square sub oscillator and noise;
- amplitude ADSR and glide;
- low-, band-, or high-pass filter, resonance, ADSR, and envelope mix;
- one selected LFO route: pitch, filter, or amplitude;
- delay time, feedback, and mix;
- reverb feedback/decay approximation, wet high-pass, and mix;
- phaser rate, feedback, and mix;
- autopan/stereo motion;
- safe output trim;
- reference note and chord;
- attribution and adapter diagnostics.

Source numbers are finite and clamped before reaching nodes. Supported range
limits live in the normalized model and are tested.

Unsupported families produce diagnostics rather than silently changing an
unrelated parameter:

- arpeggiator and sequencer;
- hold;
- custom tuning and MIDI mappings;
- bit-crush;
- FM paths not represented by the selected voice;
- additional modulation matrix routes;
- compressor internals;
- delay input tracking and other unsupported routing.

## Tonal voice graph

Each voice owns:

~~~text
oscillator 1 ─┐
oscillator 2 ─┤
sub ──────────┼─ source mixer ─ filter branches ─ envelope ─ voice output
noise ────────┘
~~~

Six live tonal voices are sufficient for a four-note chord, one Lead, and
release overlap. Voice stealing releases the oldest non-Lead audition voice
first.

All parameter and preset changes use ramps. A preset switch fades through the
configured 120 ms transition and cannot leave old gates attached.

## Hybrid percussion bank

The first prototype may bundle these exact MIT-licensed AudioKit Cookbook
samples:

- bass_drum_C1.wav;
- closed_hi_hat_F#1.wav;
- open_hi_hat_A#1.wav;
- clap_D#1.wav;
- snare_D1.wav;
- cheeb-stick.wav;
- cheeb-hat.wav;
- cheeb-ch.wav.

Source repository:

~~~text
https://github.com/AudioKit/Cookbook
revision c37d41daedf161b47315b7ae24b07f41213b73be
~~~

The complete Cookbook MIT notice and source revision are bundled. A listening
pass may reject a prototype sample, but no replacement enters the project
without explicit redistributable provenance.

The kick layers:

1. a synthesized sine pitch-drop body;
2. a filtered short sample attack;
3. a bounded transient shaper;
4. conservative saturation and limiting.

Hats and percussion use samples with velocity variation, small pitch
variation, room send, and timing humanization. Shaker is synthesized from
filtered noise plus an amplitude contour so it does not require an unresolved
asset.

The drum bank exposes semantic voices rather than filenames:

~~~text
kickSoft, kickFull, hatClosed, hatOpen, shaker,
clapSoft, stick, organicHigh, organicLow
~~~

## Felt piano asset gate

The felt-piano voice is a compact multisample instrument, not a stretched
music loop. Before its audio is checked in, its manifest must record:

- creator/source;
- exact license text;
- redistribution and modification rights;
- source URL or original-recording statement;
- original checksums;
- edited checksums;
- root note and velocity layer for every sample.

Accepted licensing is original project-owned audio, CC0, or an equivalently
explicit license permitting App Store redistribution. Attribution-only audio
is accepted only when its exact notice is bundled. Non-commercial,
share-alike, unclear, or account-bound sample libraries are rejected.

The bank is not considered complete until either a compliant felt-piano
multisample passes device listening or the product owner explicitly removes
felt piano from scope. The three Synth One Keys remain independently usable.

## Audition lab

Day Objects Lab provides:

- category: Pad, Pluck, Bass, Lead, Keys, Drums, Piano;
- preset/voice menu;
- Note;
- Chord for tonal categories;
- Hit for drum voices;
- explicit Sound On/Off;
- source/bank attribution;
- adapter diagnostics in debug presentation;
- existing single-canvas XY audition for Lead evaluation.

Sound begins off. Audition controls do not create automatic transport,
progressions, or recurring events in this subproject.

## Gain and effect safety

- Every manifest entry has a measured trim.
- Chords are quieter per voice than notes.
- Drum and tonal buses have separate conservative headroom.
- A peak limiter protects the final audition output.
- Delay feedback is capped below self-oscillation.
- Reverb mix and feedback remain bounded.
- Selecting, stopping, backgrounding, and interruption cannot leave a tone.

## Testing

Pure tests:

- exactly three unique entries per tonal category;
- all fifteen selected UIDs decode once;
- source attribution is present;
- deterministic conversion;
- explicit defaults;
- finite values and range clamping;
- deterministic unsupported-feature diagnostics.

Engine tests:

- fixed node/voice counts over repeated starts;
- idempotent start;
- full release before stop;
- bounded chord and Lead polyphony;
- no stale gate after preset selection;
- missing optional sample disables only its semantic voice;
- all effect feedback and output values remain safe.

UI tests:

- Sound starts off;
- all categories and exact counts are visible;
- Note/Chord/Hit enable only when valid;
- source bank is announced;
- Grid does not enable Lead touch.

Physical-iPhone listening:

- every tonal preset is distinguishable;
- every drum voice has body and avoids an eight-bit character;
- the kick works on headphones and speaker;
- Keys and felt piano sit behind pads without masking them;
- Lead presets remain soft under fast gesture motion;
- no click or stuck note during rapid switching.

## Acceptance criteria

- Fifteen attributed Synth One-derived tonal candidates are auditionable.
- Hybrid drum voices are ready for the Music Director.
- A compliant felt-piano bank is present or explicitly removed by product decision.
- The reusable engine is independent of SwiftUI, Metal, HealthKit, and production stores.
- All voices are normalized, lifecycle-safe, and usable on a physical iPhone.
- No automatic composition is introduced before the next subproject.
