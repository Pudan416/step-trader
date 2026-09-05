# Day Objects Bass, Mixing, and Mastering Design

**Date:** 2026-09-04
**Status:** Approved
**Scope:** Day Objects internal/debug audio experience

## Goal

Extend the existing Day Objects generative composition with a dedicated bass
layer while correcting the mix-routing and gain-staging problems found during
the technical audio review. The result should remain an ambient instrument:
some Remixes have no bass, and bass-enabled Remixes replace much of the drum
density with a pulse, a sparse arpeggio, or a sustained harmonic bed.

This work also completes one coherent mixing and mastering pass. Rhythm, bass,
harmony, Happenings, and Lead must reach one measurable master path with
independent balance and spatial control.

## Existing musical ownership

The established mapping remains unchanged:

- Steps controls rhythmic density and reaches maximum complexity at 100%.
- Sleep controls harmonic richness and the chord progression.
- Happenings adds up to ten recurring seeded one-shots and textures.
- Touch movement controls one monophonic Lead voice.
- Spent Colors controls the bounded Glitch treatment.
- Remix changes deterministic musical choices while preserving the current
  Steps, Sleep, Happenings count, and Spent Colors values.

Bass belongs to the rhythmic arrangement but receives its playable notes from
the current harmony. Happenings and touch gestures never decide whether bass
is present.

## Problems addressed by this design

The current runtime has several structural mix problems:

1. A Happening `reverbSend` value can become the feedback value of the common
   program reverb, changing the tails of drums and harmony.
2. Happenings enter the persistent output mixer separately from the musical
   world and therefore do not pass through the same program master trim.
3. Happening aggregate and per-voice gains remain constant as active voice
   count changes.
4. The planned Happening pan is not applied to playback voices.
5. Drum samples have materially different peak and RMS levels but do not have
   calibrated per-voice output trims.
6. Drums and tonal voices pass through a serial program delay and reverb even
   though the voices already own role-specific spatial effects.
7. The final default peak limiter is a safety device, but there is no complete
   loudness, true-peak, bus-level, or limiter-reduction measurement path.
8. Imported Synth One compressor and source master-volume values are
   intentionally unsupported, so every retained tonal preset needs native
   output calibration.

The raw assets inspected for this design do not contain clipped samples. The
102 Happening variants already have a strong runtime attack normalization: the
first 250 ms remain within approximately 0.68 dB after the existing conservative
headroom attenuation. That normalization is retained.

## Arrangement modes

Each Remix maps its stable seed into exactly one arrangement mode:

| Seed share | Mode | Bass | Drum behavior |
|---:|---|---|---|
| 40% | Percussion | Off | Full Steps-driven drum arrangement |
| 25% | Bass Pulse | Short rhythmic notes | Rare soft anchor kick; reduced percussion |
| 20% | Bass Arp | Sparse tonal pattern | Kick marks structure; minimal auxiliary percussion |
| 15% | Bass Bed | Sustained chord-following notes | Rare optional anchor kick |

The distribution uses stable seed buckets, not nondeterministic probability.
The same Remix seed and day input always select the same mode.

### Steps behavior

Steps controls the activation of pre-authored candidate events. Every event has
a stable threshold, so increasing Steps may add events but may not reshuffle or
remove previously active events. Values above 100% are clamped and never add
more complexity.

- At low Steps, Pulse produces occasional roots, Arp leaves wide rests, and Bed
  changes only with important harmonic boundaries.
- At medium Steps, Pulse gains syncopated accents, Arp introduces additional
  chord tones, and Bed may use a quiet approach note.
- At 100% Steps, the bass remains restrained: Pulse does not become a continuous
  sixteenth-note line, Arp retains rests, and Bed stays predominantly sustained.

### Sleep and tonal safety

Sleep continues to own the harmonic plan. Bass selects from the current chord
root, fifth, other chord tones, and the already-published safe passing tones.
The normal bass register is MIDI 29...52. Notes below the supported range of a
selected preset are moved by octaves rather than freely transposed.

Pulse prioritizes roots and fifths. Arp may traverse two or three chord tones
but avoids rapid octave jumps. Bed normally sustains the root and may move to a
nearby chord tone when that produces smoother voice leading.

### Drum simplification

Percussion mode preserves the existing Rhythm plan. Bass-enabled modes apply a
mode-specific thinning mask after the stable Rhythm events have been realized:

- the timing-anchor kick remains on the grid and is limited to one or two hits
  per bar;
- two kick voices may not attack at the same musical position;
- auxiliary percussion density is reduced by approximately 35...60%;
- hats and organic percussion retain controlled humanization;
- the timing-anchor kick remains ineligible for Glitch timing and pitch drift.

## Bass instrument palette

The Bass layer uses four attributed Synth One-derived presets:

| Native ID | Source preset | Primary use |
|---|---|---|
| `bass.analog-boom` | Analog Boom Bass | Dense but soft Pulse |
| `bass.hey-jakob` | BASS - Hey Jakob! | Dub Pulse and sustained background notes |
| `bass.bb-roys-phaser` | BB Röy’s Phaser Bass | Moving Arp |
| `bass.jec-hollores-2` | JEC Hollores Bass 2 | Dark Bed and occasional soft Pulse |

`BASS - Hey Jakob!` is imported from the official Synth One `BankA` record with
UID `E2D8B458-C727-4388-A0EA-28802B605796`. Its source is monophonic, uses two
oscillators one octave down plus a sub oscillator, has a roughly 2.9 kHz filter,
a near-instant attack, and an approximately one-second release. Its built-in
arpeggiator is disabled. The native Bass Planner may still sequence it sparsely
in an Arp Remix.

The original Synth One master volume and compressor are not copied. Every bass
receives a conservative initial native trim and must pass isolated physical
calibration before its final `outputTrimDB` is accepted.

## Director architecture

The pure music plan gains these concepts:

- `GrooveMode`: `percussion`, `bassPulse`, `bassArp`, or `bassBed`;
- `GroovePlan`: the shared arrangement decision and drum-thinning constraints;
- `BassPlan`: instrument, register, scheduled notes, articulation, filter
  motion, glide, bus target, and ducking parameters;
- a Bass target in `LayerMixPlan`.

`DeterministicMusicDirector` creates the tonal world first, then `GroovePlanner`.
`RhythmPlanner` and `BassPlanner` both consume the resulting `GroovePlan`.
This prevents independent planners from selecting conflicting kick and bass
behavior.

All Bass choices use a dedicated seed domain. Adding or removing a Happening
must not alter the selected bass mode, instrument, or note schedule.

## Playback architecture

`BassPlayer` owns one preallocated tonal voice and never overlaps two active
bass notes. It consumes transport subdivisions in the same way as Rhythm and
Harmony players. Note releases and filter changes are ramped.

On a structural Remix boundary:

1. the previous BassPlayer stops scheduling attacks;
2. its held note releases quickly and smoothly;
3. the replacement plan begins at the next valid phrase boundary;
4. two sub-bass notes never crossfade concurrently.

If the selected bass preset is unavailable, the planner chooses the next
compatible approved preset deterministically. If no bass preset is available,
the runtime falls back to Percussion mode without stopping the composition.

## Kick-to-bass ducking

The timing-anchor kick is the only sidechain source. `BassDucker` uses the same
scheduled host-time event as the kick to apply a deterministic gain envelope to
the Bass bus. It does not inspect microphone or rendered audio levels.

The bounded envelope is:

- 2.5...5 dB maximum attenuation, scaled by kick velocity and Remix character;
- approximately 3...8 ms attack;
- approximately 30...60 ms hold;
- 120...220 ms release;
- no cumulative attenuation from coincident duplicate kick requests.

The release is long enough to separate kick and bass fundamentals but short
enough to avoid conspicuous dance-music pumping. Bed mode uses the shallowest
range; Pulse may use the deepest range.

## Mix graph

All roles enter independent buses before one shared master:

```text
Rhythm ---- Rhythm Bus -------+
Bass ------ Bass Bus ---------+
Harmony --- Harmony Bus ------+
Happenings  Happening Bus ----+---- Master Bus ---- Limiter ---- Output
Lead ------- Lead Bus --------+
```

Role buses own their gain, corrective filtering, dynamics, pan policy, and
effect sends. Spatial processors return in parallel to the Master bus. There is
no mandatory serial delay/reverb across the combined drums and tonal program.

### Rhythm bus

- Apply measured per-voice trims before common Rhythm gain.
- Remove unnecessary low frequencies from hats, clap, stick, shaker, and high
  organic percussion.
- Preserve kick fundamentals while removing unusable infrasonic energy.
- Use a short room return and gentle bus compression around 2:1 with a slow
  enough attack to retain transients.
- Normal operation should produce no more than about 1...2 dB gain reduction.

### Bass bus

- High-pass only unusable energy near 25...30 Hz.
- Keep content below approximately 120...150 Hz mono-compatible.
- Bound upper harmonics per preset so the bass supports rather than masks Lead
  and Happenings.
- Apply mild saturation and compression with loudness compensation.
- Apply `BassDucker` after tone shaping and before the spatial send.
- Keep Bass reverb minimal and high-pass its return.

### Harmony bus

- Remove sub-bass that conflicts with the dedicated Bass bus.
- Calibrate Pad, Keys, and felt-piano presets to matched perceived loudness.
- Preserve the current Steps-driven harmony ducking, bounded to 1...2.5 dB.
- Use a dark long Hall return independent of Happening space.

### Happening bus

- Keep the existing 250 ms attack normalization and 4.5 dB safety attenuation.
- Route Happenings through the same Master bus as every other role.
- Apply the planned pan with constant-power panning per active voice.
- Compensate active-voice summation by approximately 3 dB per doubling, capped
  at the four-voice pool limit.
- Separate direct level, reverb send, wet return, and reverb decay controls.
- Use a dark long Cathedral return with controlled high-frequency decay.
- Preserve a quiet direct component so identity remains audible without a
  bright foreground attack.

### Lead bus

- Calibrate every retained Lead preset to matched perceived loudness.
- Soften excessive upper-mid and high-frequency energy during fast gestures.
- Retain expression and timbral movement with bounded bus compression.
- Use dedicated delay and reverb sends rather than the Happening Cathedral.

### Relative balance

Isolated Harmony, Happening, and Lead auditions target matched perceived
loudness within approximately 1.5 LU. In composition:

- Harmony is the stable reference bed.
- A held Lead is approximately equal to or at most 1 dB more prominent than
  Harmony.
- A Happening attack sits approximately 2...4 dB behind Lead, with its tail
  receding further into the spatial return.
- Bass remains perceptible without masking the kick or harmonic bed.
- Rhythm is clear but does not become the permanent foreground.

Glitch processing includes output compensation. Increasing saturation should
change texture without changing perceived role loudness by more than about
1 dB. Glitch is not applied as broadband master distortion.

## Mastering chain

The Master bus contains only common corrective and safety processing:

1. an infrasonic high-pass around 20...25 Hz;
2. gentle glue compression around 1.5:1...2:1;
3. nominal compression reduction no greater than 1...1.5 dB;
4. approximately 6 dB working headroom before final limiting;
5. a final limiter and output trim calibrated to no more than -1 dBTP.

The target for representative 60-second compositions is -18...-16 LUFS-I.
Normal limiter reduction should remain below 1...2 dB. The master must not rely
on the limiter to repair role balance or uncontrolled effect feedback.

## Metering and diagnostics

Development diagnostics expose per-bus peak, RMS, and active-voice information,
plus master peak and limiter activity. Longer captures calculate short-term and
integrated loudness away from the real-time audio thread. Offline verification
calculates true peak with oversampling.

The existing Instrumental Diagnostics surface gains:

- isolated audition for each Bass preset;
- isolated audition for each bus;
- a kick-and-bass sidechain demonstration;
- read-only level and gain-reduction values;
- a full-composition comparison mode.

Metering must not allocate, decode assets, or perform loudness integration on
the real-time render thread.

## Verification

### Pure planning tests

- Stable seeds produce stable Groove and Bass plans.
- Seed buckets implement the exact 40/25/20/15 distribution.
- Bass events remain in range and are compatible with the current harmony.
- Increasing Steps activates events monotonically and clamps at 100%.
- Bass modes thin percussion and retain the timing-anchor kick rules.
- Happening changes do not perturb Bass decisions.

### Playback and graph tests

- Bass remains monophonic and releases safely across Remix.
- Kick host times produce one bounded Bass duck envelope.
- Missing bass resources fall back without stopping playback.
- Every role reaches the common Master bus.
- Happening spatial values cannot mutate Harmony or Rhythm effect feedback.
- Happening pan and active-voice gain compensation are applied.
- Fixed node and voice counts do not grow during playback.

### Asset and loudness checks

- Import and attribution checks cover `BASS - Hey Jakob!` and all retained
  presets.
- Drum assets receive explicit accepted per-voice trims.
- Tonal preset calibration checks cover isolated note, chord, and gesture cases.
- Representative 60-second scenes remain within -18...-16 LUFS-I and at or
  below -1 dBTP.
- Normal master limiter reduction remains below 2 dB.
- Isolated Harmony, Happening, and Lead references remain within 1.5 LU.

### Scenario matrix

At minimum, verify Steps at 0/25/50/75/100%, Sleep at low/mid/full, zero/one/ten
Happenings, Glitch at 0/25/50/100%, every bass preset, every Groove mode, and
slow/fast Lead gestures. Include worst-case scenes with four overlapping
Happening tails, a kick, a bass attack, a chord transition, and an active Lead.

### Physical acceptance

After automated checks and generic device builds pass, install the build on the
paired iPhone. Listen through both headphones and the built-in speaker. Final
per-preset and per-drum trims require explicit human acceptance; automated
checks alone do not complete the tonal review.

## Non-goals

- Reimplementing the Synth One arpeggiator or sequencer.
- Adding an editable bass interface to production UI.
- Allowing Bass to exceed one simultaneous note.
- Making every Remix contain Bass.
- Applying dance-style master loudness or obvious pumping compression.
- Merging, pushing, or shipping this internal/debug feature as part of this
  design phase.

## Completion criteria

This work is complete when the four bass presets are available, the four Groove
modes follow their deterministic distribution, kick and bass coexist without
low-frequency masking, all five musical roles share the corrected measurable
master graph, automated routing and loudness checks pass, generic device builds
succeed, and the installed iPhone build is ready for the final listening and
trim-acceptance pass.
