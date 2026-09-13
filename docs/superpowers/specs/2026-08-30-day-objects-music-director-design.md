# Day Objects Deterministic Music Director Design

**Date:** 2026-08-30

**Parent:** [Day Objects Generative Music System](2026-08-30-day-objects-generative-music-system-design.md)

**Depends on:** [Native Instrument Bank](2026-08-30-day-objects-native-instrument-bank-design.md)

## Goal

Create a pure deterministic composer that translates normalized day state and
a Remix seed into a complete, bounded musical plan. It must not import
AudioKit, AVFoundation, SwiftUI, HealthKit, or Metal.

This subproject is complete when plans can be generated and exhaustively
tested without starting an audio device.

## Input

~~~swift
struct DayMusicInput: Equatable, Sendable {
    let countedSteps: Double
    let stepGoal: Double
    let countedSleepHours: Double
    let sleepGoalHours: Double
    let happeningIDs: [String]
    let spentColors: Int
}
~~~

Rules:

- deduplicate Happening IDs while preserving first insertion order;
- keep at most ten Happenings;
- negative or non-finite counted values become zero with a diagnostic;
- non-positive or non-finite goals yield zero progress with a diagnostic;
- progress clamps to 0...1;
- spentColors clamps to 0...100.

The normalized form contains:

~~~swift
struct NormalizedDayMusicInput: Equatable, Sendable {
    let stepsProgress: Double
    let sleepProgress: Double
    let happeningIDs: [String]
    let glitchProgress: Double
    let motionEnergy: Double
    let visualClarity: Double
    let diagnostics: [DayMusicDiagnostic]
}
~~~

Exact visual mappings:

~~~swift
motionEnergy = 0.25 + 0.75 * stepsProgress
visualClarity = 0.35 + 0.55 * sleepProgress
glitchProgress = pow(Double(spentColors) / 100, 2)
~~~

## Determinism

The director accepts a 64-bit Remix seed. Every random decision uses a
domain-separated deterministic generator:

~~~text
world.key
world.mode
world.progression
rhythm.family
rhythm.pattern
rhythm.humanization
harmony.instruments
happening.<stable ID>.identity
happening.<stable ID>.schedule
effects
~~~

Adding or removing one Happening may not change the identities of other
Happenings under the same Remix seed. Array position is not used as the only
event seed.

No wall clock, device identifier, Swift randomized Hashable seed, or global
random generator enters the plan.

## Output

~~~swift
struct DayMusicPlan: Equatable, Sendable {
    let seed: UInt64
    let input: NormalizedDayMusicInput
    let world: TonalWorldPlan
    let rhythm: RhythmPlan
    let harmony: HarmonyPlan
    let happenings: [HappeningMusicPlan]
    let lead: LeadPlan
    let glitch: GlitchPlan
    let mix: LayerMixPlan
}
~~~

The top-level API is:

~~~swift
enum DeterministicMusicDirector {
    static func makePlan(
        input: DayMusicInput,
        remixSeed: UInt64
    ) -> DayMusicPlan
}
~~~

## Tonal world

Tonal centers are pitch classes C, D, E, F, G, and A.

Modes:

~~~text
Dorian:           0, 2, 3, 5, 7, 9, 10
Aeolian:          0, 2, 3, 5, 7, 8, 10
Mixolydian:       0, 2, 4, 5, 7, 9, 10
Major Pentatonic: 0, 2, 4, 7, 9
~~~

Progression templates are modal degree sequences:

~~~text
Dorian:
  [i]
  [i, IV]
  [i, bVII, IV]
  [i, bIII, bVII, IV]

Aeolian:
  [i]
  [i, bVI]
  [i, bVII, bVI]
  [i, bVI, bIII, bVII]

Mixolydian:
  [I]
  [I, bVII]
  [I, v, bVII]
  [I, bVII, IV, I]

Major Pentatonic:
  [I5]
  [I5, IVsus2]
  [I5, vi7(no3), IVsus2]
  [I5, vi7(no3), IVsus2, Vsus]
~~~

The selected Sleep band determines maximum template length. Remix chooses
among compatible templates of that length and chooses voicings separately.

Every chord publishes:

- root;
- chord tones;
- safe mode tones;
- voiced MIDI notes;
- duration in bars.

Voice leading searches inversions within the category register and minimizes
total semitone movement from the preceding chord. Repeated notes are allowed.
Parallel fifth avoidance is not required for this ambient system.

## Continuous activation helper

Layer gains and probabilities use:

~~~swift
smoothActivation(value, start, end)
~~~

It returns zero at or below start, one at or above end, and a cubic smoothstep
between them. This prevents audible jumps around density boundaries.

Structural progression length changes only at a harmonic-cycle boundary and
uses playback crossfade; it never replaces active chords immediately because
a slider crossed a boundary.

## Rhythm plan

Each Remix selects baseTempoBPM in 58...82. Exact tempo:

~~~swift
tempoBPM = baseTempoBPM + 20 * stepsProgress
~~~

It caps at 102 BPM.

Rhythm activation:

| Voice | Start | Full |
|---|---:|---:|
| low pulse | 0.00 | 0.20 |
| half-time kick | 0.10 | 0.35 |
| closed hat | 0.30 | 0.60 |
| shaker | 0.38 | 0.68 |
| kick variation | 0.45 | 0.72 |
| organic percussion | 0.55 | 0.85 |
| syncopated ghost layer | 0.65 | 0.92 |
| fills | 0.82 | 1.00 |

Each voice plan contains semantic instrument ID, 16-step probability mask,
velocity range, microtiming range, room send, and whether Glitch may affect it.

The primary kick is marked timingAnchor and always receives zero pitch drift,
zero dropout probability, and no delay instability.

The director caps:

- simultaneous drum attacks at three;
- fills at one per eight bars;
- microtiming at plus/minus 18 ms;
- velocity humanization at plus/minus 0.08;
- harmony ducking at 2.5 dB.

## Harmony plan

Sleep bands determine structure:

| Progress | Chords | Active roles |
|---|---:|---|
| 0...0.35 | 1 | drone, open fifth |
| above 0.35 through 0.70 | 2 | primary pad |
| above 0.70 below 1.00 | 3 | primary pad, secondary pad/keys |
| exactly 1.00 | 3 or 4 | two complementary roles, rare piano/keys |

Numeric gains are continuous:

| Role | Start | Full |
|---|---:|---:|
| drone | 0.00 | 0.20 |
| primary pad | 0.20 | 0.55 |
| secondary pad/keys | 0.58 | 0.88 |
| piano/keys accents | 0.72 | 1.00 |
| inner motion | 0.82 | 1.00 |

The director chooses compatible stable IDs from the instrument manifest. It
does not know AudioKit node classes.

Harmonic cycle duration is 8, 12, or 16 bars. Low Sleep favors 16; higher
Sleep permits 8 or 12. More Sleep adds harmonic information without forcing a
faster tempo.

## Happening plans

Every Happening plan contains:

~~~swift
struct HappeningMusicPlan: Equatable, Sendable {
    let happeningID: String
    let family: HappeningSoundFamily
    let instrumentID: String
    let motifScaleDegrees: [Int]
    let octave: Int
    let pan: Double
    let gain: Double
    let delaySend: Double
    let reverbSend: Double
    let recurrence: HappeningRecurrencePlan
}
~~~

Families are Pluck, Mallet, Bell, Soft One-shot, and Texture. Instrument IDs
may reuse a base preset with a bounded envelope/effect variant.

Recurrence interval bounds by count:

~~~text
1...2 events: 2...4 bars
3...6 events: 6...12 bars
7...10 events: 12...24 bars
~~~

The exact interval is deterministic per Happening and cycle. At least 35
percent and at most 60 percent of active events use grid-aligned recurrence;
the rest use a deterministic floating offset capped at half a beat.

The aggregate plan enforces:

- minimum quarter-beat attack separation;
- at most two Happening attacks per beat;
- every active event scheduled once within the first full cycle after start;
- no event starved for more than its maximum recurrence interval.

Motifs contain one to three mode degrees. On each occurrence, the renderer
maps the degree to the nearest allowed current-chord or passing tone.

## Lead plan

The director selects one Lead instrument and defines:

- lowest and highest MIDI note;
- 21 horizontal pitch regions;
- chord-tone preference for strong regions;
- mode-tone passing regions;
- cutoff range;
- portamento in 60...160 ms;
- attack and release bounds;
- base expression depth;
- delay/reverb sends.

The plan provides a pure function for the nearest compatible note during a
chord change. It does not process touch events.

## Glitch plan

glitchProgress is already quadratic. The plan derives:

| Parameter | Maximum at input 100 |
|---|---:|
| pad pitch drift | 14 cents |
| Happening pitch drift | 10 cents |
| Lead pitch drift | 8 cents |
| wow/flutter depth | 0.18 |
| delay-time instability | 8 percent |
| stereo separation addition | 0.22 |
| soft dropout probability | 0.06 per eligible event |
| percussion drift | 3 cents |
| timing-anchor kick drift/dropout | 0 |

Every parameter is multiplied by glitchProgress. No secondary threshold makes
small values suddenly audible.

## Mix plan

The plan sets role-level target gains and ducking, not final device volume.
Conservative defaults:

~~~text
rhythm:    -12 dB
harmony:  -16 dB
happenings:-18 dB aggregate
lead:     -15 dB
master:    -6 dB before limiter
~~~

The happening aggregate gain compensates for count so ten events do not sum
ten full-level voices.

## Remix operation

The pure director has no live transition. It produces a complete next plan.
Playback is responsible for:

- retaining current input;
- incrementing or replacing Remix seed;
- scheduling next plan at a bar boundary;
- discarding older pending Remix plans;
- crossfading old and new players.

## Testing

Input tests:

- invalid goals yield zero progress and diagnostics;
- negative/non-finite values are safe;
- progress caps at one;
- 5,000/5,000 equals 10,000/10,000;
- more than ten Happenings is truncated deterministically.

Determinism tests:

- same input and seed yields an equal complete plan;
- different seed changes world decisions;
- adding one Happening preserves all other event identities;
- no randomized Swift hash affects the result.

Music tests:

- mode pitch sets are exact;
- every chord and motif degree belongs to the selected world;
- voice leading stays within configured registers;
- tempo stays in 58...102;
- activation curves are monotonic and continuous;
- structural harmony richness never decreases with Sleep;
- rhythm richness never decreases with Steps;
- kick remains a Glitch-exempt timing anchor;
- aggregate event rules hold at counts 0 through 10;
- Glitch values equal the quadratic formula and maxima.

Snapshot tests cover representative inputs:

~~~text
Steps: 0, 15, 35, 60, 85, 100 percent
Sleep: 0, 35, 70, 99, 100 percent
Happenings: 0, 1, 5, 10
Spent colors: 0, 10, 25, 50, 100
At least four Remix seeds
~~~

## Acceptance criteria

- A complete plan is pure, deterministic, finite, and bounded.
- Goal-relative semantics are exact and capped.
- Steps, Sleep, Happenings, Lead, and Glitch plans follow the approved roles.
- Every tonal decision shares one world.
- The director can be tested without AudioKit or an audio session.
- The plan exposes enough information for playback without exposing player internals.
