# Day Objects Generative Playback Design

**Date:** 2026-08-30

**Parent:** [Day Objects Generative Music System](2026-08-30-day-objects-generative-music-system-design.md)

**Depends on:**

- [Native Instrument Bank](2026-08-30-day-objects-native-instrument-bank-design.md)
- [Deterministic Music Director](2026-08-30-day-objects-music-director-design.md)

## Goal

Render DayMusicPlan through native AudioKit layers inside Day Objects Lab,
connect the approved lab controls to both visuals and music, and make every
transition lifecycle-safe on a physical iPhone.

This subproject remains an internal/debug experiment. Production Canvas and
HealthKit integration require a later design.

## Compile and product boundary

New audio and lab integration sources are guarded by:

~~~swift
#if DEBUG || INTERNAL_BUILD
#endif
~~~

Release builds do not expose the lab. No production model imports a playback
type.

The Metal scene receives only existing DayObjectSceneInput values. Audio does
not own, mutate, or query renderer nodes.

## Controller input

The lab controller owns:

~~~swift
struct DayObjectsLabMusicState: Equatable {
    var steps: Double
    var stepGoal: Double
    var sleepHours: Double
    var sleepGoalHours: Double
    var happeningCount: Int
    var spentColors: Int
    var remixSeed: UInt64
}
~~~

Initial lab values:

- Steps 10,000 of 10,000;
- Sleep 8 of 8 hours;
- Happenings 8;
- Spent colors 0;
- a fixed checked-in initial Remix seed;
- Sound off.

Changing sliders rebuilds a pure DayMusicPlan. Visual mapping applies
immediately. Rhythm structure is queued to the next bar, harmony structure to
the next harmonic-cycle boundary, and continuous gains/effects ramp in place.

## UI

The primary control card displays:

1. Steps slider, 0...10,000, readout including 10,000 goal;
2. Sleep slider, 0...8 hours, readout including 8-hour goal;
3. Happenings slider, 0...10;
4. Spent colors slider and existing step/preset shortcuts;
5. Remix button and current world summary;
6. optional collapsed Instrument diagnostics.

The current Motion and Focus controls move into collapsed Fine tuning. In
normal use, derived values are:

~~~swift
motionEnergy = 0.25 + 0.75 * stepsProgress
visualClarity = 0.35 + 0.55 * sleepProgress
~~~

Sound remains a circular always-visible button outside the collapsible card.
Its states are off, starting, on, and retryable error.

Remix is enabled with Sound off or on. With Sound off it changes the pending
plan and visible world summary. With Sound on it schedules a bar-boundary
transition.

## Playback protocol

~~~swift
@MainActor
protocol DayObjectsMusicPlaybackProtocol: AnyObject {
    var state: DayObjectsSoundState { get }
    var metrics: DayObjectsPlaybackMetrics { get }

    func start(plan: DayMusicPlan) async throws
    func stop() async
    func applyContinuous(_ plan: DayMusicPlan)
    func scheduleStructuralPlan(_ plan: DayMusicPlan)

    func addHappening(_ plan: HappeningMusicPlan, playBirth: Bool)
    func removeHappening(id: String)

    func beginLead(_ gesture: LeadGestureSample)
    func updateLead(_ gesture: LeadGestureSample)
    func endLead()
}
~~~

The SwiftUI view talks only to the controller. The controller owns plan
comparison and chooses continuous, structural, add, and remove commands.

## Transport

One monotonic transport owns tempo, beat, bar, and harmonic-cycle position.
No layer creates its own timer.

Transport events are delivered through one actor-isolated scheduler:

~~~text
subdivision tick
beat
bar boundary
harmonic-cycle boundary
~~~

The transport uses host time/audio render timing rather than repeated
main-thread Timer callbacks. UI updates may sample transport state but never
drive audio scheduling.

Tempo ramps over one bar when Steps changes. It does not jump mid-beat.

## Rhythm player

RhythmPlayer consumes RhythmPlan and semantic drum voices from the instrument
bank.

At each step it applies:

- deterministic probability;
- planned velocity;
- bounded microtiming;
- semantic sample/synth selection;
- room send;
- timing-anchor protection.

The kick body and sample attack trigger as one logical voice. Hats and
percussion use voice pools rather than creating new players.

High Steps may apply at most 2.5 dB harmony ducking. The player never exposes
the kick as a full-band saw or unfiltered noise source.

## Harmony player

HarmonyPlayer owns:

- drone voice pool;
- primary and secondary pad pools;
- Keys pool;
- felt-piano sampler pool;
- current voiced chord;
- scheduled next chord;
- per-role effect sends.

Chord changes crossfade voices and use the director's nearest voicing. A
slider change cannot cut an active long pad. If Sleep drops, removed roles
finish a bounded release and do not begin new notes.

Harmonic cycle changes occur only at a cycle boundary. Continuous layer gains
ramp over one bar.

## Happening scheduler

HappeningScheduler owns one state record per stable Happening ID:

~~~swift
struct ActiveHappeningState {
    let plan: HappeningMusicPlan
    var nextOccurrence: MusicalPosition
    var didPlaySinceStart: Bool
    var activeVoiceIDs: Set<Int>
}
~~~

Adding while Sound is on:

1. creates state;
2. resolves a current compatible pitch;
3. plays one birth gesture;
4. schedules deterministic recurrence.

Adding while Sound is off only changes the pending plan. On the next start,
the first-cycle guarantee schedules all active events without placing more
than two attacks on one beat.

Removing cancels future occurrences and releases only that event's voices.

On each occurrence, the motif is resolved against the current chord. Floating
events keep deterministic sub-beat offsets; grid events use their planned
subdivision.

The scheduler enforces the director's global minimum attack separation even
after live additions.

## Lead player

The transparent gesture layer exists only above the unobstructed single
canvas and below control chrome.

Touch mapping:

- horizontal position -> one of 21 plan regions;
- vertical position -> bounded filter multiplier;
- speed -> 0...0.25 expression;
- end/cancel -> release.

LeadPlayer owns exactly one live voice. Moving between pitch regions ramps
frequency using planned portamento and does not reopen the amplitude
envelope. Filter and expression updates are smoothed.

When harmony changes, the held pitch glides to the nearest compatible note.
VoiceOver removes the gesture recognizer. Grid disables it and ends any
active Lead.

## Glitch processor

Glitch is applied by role, not as one destructive master insert:

- Harmony: pitch drift, wow/flutter, stereo, delay instability;
- Happenings: smaller pitch drift, delay variation, rare soft dropout;
- Lead: bounded drift and saturation;
- Percussion: light stereo/timing texture only;
- timing-anchor kick: no pitch drift, dropout, or delay instability.

Every parameter equals its DayMusicPlan maximum multiplied by the already
quadratic glitchProgress. Values ramp over 250 ms when Spent colors moves.

At zero, Glitch nodes are bypassed or neutral and must null-test as clean
within implementation tolerance.

## Remix transition

The controller generates the next complete plan immediately. Playback stores
one pending structural plan.

At the next bar:

1. discard any older pending plan;
2. stop scheduling old rhythm and Happening attacks;
3. begin old-world release;
4. configure the inactive world/player bank;
5. start the new rhythm at the boundary;
6. crossfade harmony/effects over two bars;
7. reassign existing Happenings and schedule their new first-cycle entries;
8. retain the current held Lead only by gliding it into the new world, or
   release/restart it when no safe common pitch exists.

The old bank is recycled only after its tails end. Tracked bank/node counts
remain constant across Remixes.

## Plan-change classification

Continuous changes:

- Steps/Sleep-derived role gains;
- Glitch parameters;
- visual Motion/Focus values;
- filter/effect amounts;
- tempo target.

Structural changes:

- tonal center or mode;
- progression/template length;
- instrument IDs;
- rhythm pattern/family;
- Happening identity;
- Remix seed.

Happening additions/removals use their dedicated commands and do not rebuild
unrelated layers.

## Audio session and lifecycle

Sound On:

1. set AVAudioSession category playback;
2. activate session;
3. load current plan into fixed player banks;
4. start AudioKit and transport;
5. fade master to conservative level.

Sound Off, disappearance, inactive/background, or interruption-began:

1. stop scheduling;
2. end Lead;
3. cancel pending Remix;
4. release rhythm, harmony, and Happening voices;
5. stop transport and effect tasks;
6. drain bounded tails;
7. stop engine;
8. deactivate session with notifyOthersOnDeactivation.

Foregrounding and interruption-ended never restart.

Missing optional sample:

- log/report exact semantic voice;
- substitute a declared safe fallback only when the manifest permits it;
- otherwise disable that role;
- keep visuals and other layers running.

Audio engine failure:

- transition Sound to retryable error;
- tear down partial state;
- preserve current lab inputs and Remix seed.

## Performance budgets

- fixed player/node banks allocated before start;
- one transport;
- one Happening scheduler;
- one pending Remix;
- ten active Happening state records;
- one Lead voice;
- bounded tonal and drum voice pools;
- no node creation from a render tick or touch update;
- no JSON decoding on the audio scheduling path;
- Metal frame rate remains visually unchanged.

## Accessibility

Stable identifiers cover:

- Sound;
- Steps;
- Sleep;
- Happenings;
- Spent colors;
- Remix;
- world summary;
- Fine tuning disclosure;
- Lead surface state.

All musical controls have text alternatives. Lead is supplemental. Grid
announces touch performance unavailable. Sound state announces off, starting,
on, and error.

## Testing

Controller tests:

- explicit Sound start only;
- retry after failure;
- input normalization and visual mapping;
- continuous versus structural plan classification;
- Remix replaces older pending Remix;
- live Happening add/remove emits only dedicated commands;
- scene lifecycle calls one stop path;
- reopening resets Sound off.

Transport/player tests with a fake backend:

- single transport;
- tempo ramp at bar boundary;
- deterministic drum triggers;
- stable kick under maximum Glitch;
- harmonic changes at cycle boundaries;
- removed harmony roles release;
- first-cycle guarantee for 1, 5, and 10 Happenings;
- global attack cap and no starvation;
- one Lead voice through hundreds of updates;
- Grid/VoiceOver cancellation;
- constant node/task metrics over start/stop and Remix loops.

UI tests:

- fixed 10,000-step and 8-hour goals;
- Steps changes visual Motion value;
- Sleep changes visual Clarity value;
- Happenings changes actor count;
- Spent colors changes existing visual damage;
- Sound stays off until pressed;
- Remix changes world summary but not input values;
- Grid preserves music and disables Lead;
- existing Day Objects controls and screenshots remain valid after intentional
  label updates.

Physical-iPhone matrix:

~~~text
Steps: 0 / 15 / 35 / 60 / 85 / 100 percent
Sleep: 0 / 35 / 70 / 99 / 100 percent
Happenings: 0 / 1 / 5 / 10
Glitch: 0 / 10 / 25 / 50 / 100
Remix: at least four seeds at one fixed day input
~~~

Listen on headphones and speaker for balance, click-free transitions, stuck
notes, drum fullness, harmonic motion, event audibility, Lead harshness, and
Glitch onset. Repeat interruption and background cycles.

## Acceptance criteria

- Lab controls drive the approved visual and musical mappings.
- Rhythm, harmony, Happenings, and Lead remain distinct and balanced.
- Remix is deterministic, bar-aligned, and click-free.
- Glitch is genuinely subtle at low values and never destabilizes the kick.
- Every Happening is heard without unbounded aggregate density.
- One Lead voice remains responsive and soft.
- Lifecycle operations leave no transport, task, node growth, or stuck voice.
- Existing Day Objects animation remains smooth.
- The playback implementation does not leak into production Canvas.

## Verification status — 2026-09-01

Verified in the iPhone 17 Pro simulator:

- the exact final playback suite passed 152/152 and the exact Day Objects Lab UI
  suite passed 6/6;
- deterministic load gates passed for 25 Sound cycles, 10 background and 10
  interruption stops, Happenings 0↔10 loops, 100 Remixes, 1,000 Lead updates,
  1,000 harmony changes, 10,000 rhythm subdivisions, and 10,000 transport bars;
- fixed-bank/node/task/token assertions converge without a stuck deterministic
  token after teardown;
- Grid and VoiceOver held-Lead cancellation tests pass;
- a fresh Release simulator build succeeds, the Release app binary contains no
  audited playback symbols, and production Canvas/store/model/service paths do
  not reference playback types.

Not yet verified:

- the complete physical-iPhone speaker/headphone matrix;
- physical CPU, memory, thermal, render-underrun, and audio-glitch behavior;
- perceptual balance, harmonic motion, every Happening's birth/recurrence,
  Lead softness, low-Glitch onset, click-free Remix, and physical Metal frame
  pacing.

Therefore the automated portion is accepted, but the phase completion gate
remains open. The pending rows are tracked in
`docs/day-objects-generative-playback-listening-checklist.md`; observed
simulator/build evidence is recorded in
`docs/day-objects-generative-playback-performance.md`.
