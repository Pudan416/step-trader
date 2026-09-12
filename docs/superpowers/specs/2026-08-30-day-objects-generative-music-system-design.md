# Day Objects Generative Music System Design

**Date:** 2026-08-30

## Status

Approved in conversation. This document replaces the earlier assumption that
Day Objects audio is only a twelve-preset audition lab.

Implementation is intentionally split into three independently testable
subprojects:

1. [Native Instrument Bank](2026-08-30-day-objects-native-instrument-bank-design.md)
2. [Deterministic Music Director](2026-08-30-day-objects-music-director-design.md)
3. [Generative Playback](2026-08-30-day-objects-generative-playback-design.md)

Each subproject receives its own implementation plan after this written design
is reviewed. The subprojects are implemented in the listed order.

## Goal

Turn the existing native Day Objects Lab into a deterministic ambient
instrument whose visual and musical behavior responds to Steps, Sleep,
Happenings, Spent colors, Remix, and finger movement.

The lab is the proving ground for production-native audio. It is not another
browser approximation and does not read HealthKit or production user data.

## Product model

| Input | Visual role | Musical role |
|---|---|---|
| Steps progress | Motion energy | Tempo range, kick, hats, percussion density, syncopation, fills |
| Sleep progress | Clarity and calm | Harmonic richness, progression length, pads, keys, piano |
| Happenings, 0...10 | Number of Day Objects | Recurring plucks, mallets, bells, one-shots, textures |
| Finger movement | Supplemental gesture | Monophonic expressive Lead |
| Spent colors, 0...100 | Existing visual damage | Smooth global audio Glitch |
| Remix | No health-value mutation | New tonal world, progression, instruments, rhythm, and event seeds |

All musical layers share one tonal world. A Happening or Lead note may not
choose pitches independently of the current mode and chord.

## Normalized day inputs

The music system consumes progress toward the person's configured goals, not
absolute universal thresholds:

~~~swift
stepsProgress = min(max(countedSteps / stepGoal, 0), 1)
sleepProgress = min(max(countedSleep / sleepGoal, 0), 1)
~~~

The lab uses fixed defaults:

- step goal: 10,000;
- sleep goal: 8 hours;
- Steps slider: 0...10,000;
- Sleep slider: 0...8 hours.

Production integration later supplies the person's configured goals. Thus
5,000 of a 5,000-step goal and 10,000 of a 10,000-step goal both produce
100 percent musical complexity.

Progress never exceeds one. Goal completion is the maximum. Extra steps or
sleep do not add musical layers, tempo, rewards, or Glitch.

## Deterministic Remix world

A Remix seed selects:

- one tonal center from C, D, E, F, G, or A;
- one mode: Dorian, Aeolian, Mixolydian, or Major Pentatonic;
- a compatible ambient chord progression;
- one instrument choice for each active layer;
- a rhythm family and humanization profile;
- one identity for each existing Happening;
- effect variations inside safe ranges.

Steps, Sleep, Happening count, and Spent colors remain unchanged when Remix is
pressed. The same seed and the same normalized inputs always produce the same
composition plan.

The system is not fixed to D Dorian. D Dorian remains only one possible tonal
world.

Remix waits for the next bar boundary, releases incompatible voices, and
crossfades the old and new worlds. Repeated presses before the boundary keep
only the newest requested seed.

## Rhythm from Steps

The transport always exists so harmony and events share timing. Audible drums
become denser with Steps:

- 0...15 percent: an occasional soft pulse or low hit;
- 15...35 percent: a simple half-time kick;
- 35...60 percent: closed hat, shaker, and kick variation;
- 60...85 percent: organic percussion, syncopation, and ghost notes;
- 85...100 percent: the fullest groove, accents, and rare fills.

These are density regions, not hard switches. Each voice fades in through
probability and velocity curves.

Each Remix chooses a base tempo in 58...82 BPM. Steps may add up to 20 BPM.
The audible tempo therefore remains in 58...102 BPM. Density, subdivision,
velocity, and orchestration carry more of the progress than tempo.

Drums are hybrid:

- a synthesized sine-based kick body;
- a short sample attack for the kick;
- sample-based hats, clap, stick, and organic percussion;
- synthesized noise shaker;
- small velocity and timing humanization;
- room processing;
- mild harmony ducking only at high Steps progress.

The main kick remains a stable timing anchor even at maximum Glitch.

## Harmony from Sleep

Sleep controls harmonic fullness rather than overall loudness:

- 0...35 percent: tonic drone and an open fifth, almost no chord changes;
- 35...70 percent: a slow two-chord progression and one pad;
- 70...99 percent: three chords, smooth inversions, a second timbre, and rare keys;
- 100 percent: a three- or four-chord cycle, two complementary layers, and subtle inner motion.

Transitions are continuous. Low Sleep stays musical; it sounds sparse and
fragile rather than dissonant or punitive.

Chord voices use nearest inversions so they move by small intervals. Harmony
uses Synth One-derived Pad and Poly/Keys voices plus a compact legally
redistributable felt-piano sampler.

The current chord publishes its chord tones and safe scale tones to the
Happenings and Lead layers.

## Happenings

The lab supports zero through ten Happenings. Every Happening receives a
stable identity for the current Remix:

- family: Pluck, Mallet, Bell, Soft One-shot, or Texture;
- instrument;
- one- to three-note motif;
- octave;
- stereo position;
- envelope and effect send;
- rhythmic or floating recurrence profile.

If Sound is on, adding a Happening plays its birth sound immediately. If it
was added while Sound was off, the scheduler guarantees that it appears
within the first musical cycle after Sound starts.

Approximate recurrence:

- one or two Happenings: each every 2...4 bars;
- five Happenings: each every 6...12 bars;
- ten Happenings: each every 12...24 bars.

The scheduler separates attacks and caps global event density. Ten
Happenings must not sound ten times busier than one.

Removing a Happening fades and removes only its layer. Remix reassigns musical
identities to the existing Happenings. The first version does not map visual
shape, size, fill, or gradient to audio.

## Lead gesture

Single-canvas touch controls one monophonic Lead:

- horizontal position chooses pitch;
- vertical position opens or closes a bounded filter;
- movement speed adds at most 25 percent expression, vibrato, and saturation;
- touch release starts a smooth release.

Strong horizontal regions select current chord tones. Intermediate regions
select safe passing tones from the current mode. A sustained note follows a
chord change by gliding to the nearest compatible pitch.

The Lead uses a dedicated soft preset bank, 60...160 ms portamento, a
non-zero attack, smoothed parameter changes, delay/reverb sends, and one live
voice. Coordinate updates do not retrigger its envelope.

Grid mode, controls, navigation chrome, and VoiceOver exploration never start
Lead notes.

## Glitch from Spent colors

The existing Spent colors value is the single visual and audio Glitch input.
No duplicate Glitch slider is added.

~~~swift
audioGlitch = pow(spentColors / 100, 2)
~~~

This makes low values subtle:

- 10 percent becomes 1 percent audio effect;
- 25 percent becomes 6.25 percent;
- 50 percent becomes 25 percent;
- 100 percent becomes maximum musical degradation.

The effect palette is bounded pitch drift, wow/flutter, delay instability,
stereo separation, and rare soft dropouts. It avoids sudden bit-crush,
full-band noise, and harsh saw layers.

Pads, Happenings, and Lead receive the strongest treatment. Percussion is
lighter, and the main kick remains stable.

## Lab controls and visual mapping

The primary Day Objects control card becomes:

- Steps, 0...10,000, goal 10,000;
- Sleep, 0...8 hours, goal 8 hours;
- Happenings, 0...10;
- Spent colors, 0...100;
- Remix;
- preset/source diagnostics in a collapsed debug section.

Sound On/Off remains an explicit always-visible button. Sound is off every
time the lab opens and never starts from a slider movement.

The direct Motion and Focus sliders leave the primary card because they would
conflict with Steps and Sleep:

~~~swift
motionEnergy = 0.25 + 0.75 * stepsProgress
visualClarity = 0.35 + 0.55 * sleepProgress
~~~

Fine Motion and Focus controls may remain only in a collapsed debug section.

Happenings continues to determine the visible actor count. Spent colors
continues to drive the existing visual damage system.

## Audio lifecycle

- Sound On activates AVAudioSession category playback and starts AudioKit.
- Sound Off releases voices and effect tails, stops the engine, and
  deactivates the session.
- View disappearance, inactive/background scene phase, and interruption-began
  use the same stop path.
- Foregrounding and interruption-ended never resume automatically.
- Start failures show a retryable local error and do not block Metal rendering.
- A missing optional sample disables its voice family and reports the asset;
  it does not crash the visual lab.

## Layered architecture

~~~text
Lab controls / later production day snapshot
                    ↓
          NormalizedDayMusicInput
                    ↓
          DeterministicMusicDirector
                    ↓
              DayMusicPlan
   ┌────────────────┼──────────────────┐
   ↓                ↓                  ↓
RhythmPlayer   HarmonyPlayer    HappeningScheduler
   └────────────────┼──────────────────┘
                    ↓
               LeadPlayer
                    ↓
            Layer mixer + Glitch
                    ↓
             limiter + output
~~~

The director is pure and does not import AudioKit. Players consume plans and
do not read SwiftUI, app stores, HealthKit, or Metal scene objects.

## Testing

Pure tests verify:

- progress clamps to 0...1;
- equivalent goal ratios create equivalent complexity;
- same seed and input create an equal plan;
- different Remix seeds change the musical world without changing inputs;
- all planned notes belong to the current chord or allowed mode tones;
- rhythm and harmony curves are monotonic and have no threshold jumps;
- event density remains bounded at ten Happenings;
- Glitch uses the quadratic curve exactly.

Playback tests verify:

- one transport and bounded voices;
- stable kick under Glitch;
- Remix occurs at a bar boundary and cancels older pending Remix requests;
- adding/removing Happenings does not leave tasks or voices;
- one Lead voice survives coordinate updates and ends on every cancellation;
- repeated Sound cycles do not grow tracked nodes or tasks;
- backgrounding, interruptions, and disappearance stop the same resources.

UI tests verify the new controls, fixed lab goals, Sound state, Remix, Grid,
VoiceOver-safe touch behavior, and existing Day Objects rendering.

A physical-iPhone listening pass evaluates:

- drum fullness across five Steps levels;
- harmonic development across four Sleep levels;
- recognizability of all Happenings at counts 1, 5, and 10;
- Lead latency and softness;
- low-value Glitch subtlety;
- at least four Remix worlds at fixed inputs;
- output balance on headphones and the built-in speaker;
- Metal smoothness while all layers run.

## Acceptance criteria

- Steps and Sleep are interpreted relative to their goals and cap at 100 percent.
- Steps audibly develops a full hybrid rhythm without leaving ambient tempo.
- Sleep audibly develops harmony from sparse drone to a moving ambient cycle.
- Every active Happening is heard and recurs without unbounded density.
- Finger movement performs a smooth dedicated Lead in the shared harmonic world.
- Spent colors creates gradual musical Glitch with no abrupt low-value effect.
- Remix changes the musical interpretation while preserving day inputs.
- The same seed and inputs reproduce the same plan.
- Visual and musical mappings use the same normalized inputs.
- Sound remains explicit and lifecycle-safe.
- The system remains confined to Day Objects Lab until a separate production
  integration design is approved.

## Out of scope

- HealthKit reads inside the audio layer;
- production Canvas integration;
- background playback;
- mapping visual shape/fill/size to timbre;
- online sample downloads at runtime;
- copying the Synth One app or legacy engine;
- steps or sleep beyond goal increasing complexity;
- exact sample-identical Synth One emulation.
