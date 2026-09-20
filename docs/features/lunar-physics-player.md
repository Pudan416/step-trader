# Lunar physics player

Status: implemented prototype in the Canvas player. The code remains authoritative.

## Product intent

Play turns the saved daily composition into a small living ecosystem. The figures keep
their musical identities, but weak physical gravity makes the composition tactile and
slightly unpredictable. The result should feel calm and absorbing, not like a physics toy
or an arcade mode.

Before Play, the artwork is static. Starting sound activates the simulation only after
the audio controller reaches `on`; loading or failed playback must not move the figures.
Stopping sound disables gravity and returns every figure to the current saved composition.
The physical result is never persisted.

## Motion model

- `CMDeviceMotion.gravity` supplies real gravity projected into portrait canvas space.
- There is no Play-time calibration point: holding the phone upright naturally pulls the
  figures down, while tilting it changes the direction of the field.
- Acceleration is deliberately weak, with moderate drag and a restitution near `0.7`, so
  motion reads as low-gravity movement rather than ordinary falling.
- Figures collide with the four screen walls only. They can overlap and pass through one
  another; object-to-object collision would create visual and musical clutter.
- Each figure is bounded using its rendered half-size, so its visible body stays inside
  the canvas.
- Large delayed frames are capped and integrated in small steps. Non-finite motion input
  becomes zero gravity.
- Weak resting contacts are silent, and per-object cooldowns prevent edge chatter.

The pure simulation is `DayObjectLunarPhysicsEngine`. It works in the Metal renderer's
aspect-aware short-side canvas coordinates, so it does not force SwiftUI state changes every frame.
`DayObjectMotionInputProvider` owns Core Motion and exposes only the latest safe sample.

## Sound layers

The player retains three distinct layers:

1. Regular happening one-shots remain the autonomous musical voices of the figures.
2. Smudge remains the directly played Lead voice.
3. A sufficiently energetic wall contact may add a quiet, long-tailed material resonance.

Collision sounds are not another instrument family chosen by the user. Their material is
derived from the selected sound world and remains subordinate to the existing arrangement:

| Sound world | Prototype materials |
| --- | --- |
| Felt and Wood | felt kalimba whisper / cedar knock |
| Living Field | water pearl / bamboo air pluck |
| Metal and Current | current metal pluck / brushed resonator |
| Electric Dream | frost glass tap / glass sustain bloom |

The actor's stable event ID and member index select one of the two variants. A global throttle and the
physics contact cooldown keep resonances rare. The bundled recipes already carry restrained
gain and reverb tails. Resonances use a reserved fifth Happening voice. A new collision may
replace the previous resonance, but a
collision can never displace one of the four musical voices and regular one-shots can never
make the collision path unavailable. Regular one-shots are not rescheduled by collisions.

## Smudge and Lead

Smudge keeps immediate full-canvas input and continues to drive Lead exactly as before.
While Play is active, the same gesture is also published to a small interaction field. A
figure crossed by the gesture receives a bounded impulse in the gesture direction. Distant
figures are untouched. This physical response must never delay or gate Lead audio.

The prototype does not retune or replace the next autonomous one-shot. A later listening
iteration may let the next one-shot answer the Lead harmonically, but that requires its own
musical acceptance criteria rather than being hidden inside the physics layer.

## Playback interface

The Canvas remains portrait-only. Landscape is not a separate clean-view mode.

When Play is requested, full-screen controls remain visible while audio starts. Once sound
is actually on, a 2.5-second idle timer fades the dock, its scrim and system chrome. A small persistent
folded-corner affordance remains flush with the physical lower-right corner. Pressing it restores
the playback/remix dock and starts the idle timer again.

The corner owns only a 56 by 56 point hit area. Smudge remains immediate everywhere else;
Smudge gestures do not reveal the interface. Stop, an audio error, leaving Canvas, or closing
full screen restores the ordinary visible interface.

## Lifecycle and failure rules

- Motion sampling starts only while sound is `on` and stops with playback.
- Audio interruption or failure follows the same path as Stop.
- Return-to-composition runs for roughly 0.72 seconds. The Metal renderer signals actual
  completion; only then may the Canvas leave full screen and pause. No independent UI timer
  is allowed to truncate the return.
- Adding/removing actors during playback synchronizes bodies by stable actor ID.
- Palette rendering never runs lunar physics.
- The simulator uses a small downward fallback vector because Core Motion is unavailable;
physical-device verification is still required for tilt behavior.

## Acceptance criteria

- No figure moves before audio reaches `on`.
- Upright portrait playback visibly pulls figures toward the bottom over several seconds.
- Tilting a physical phone changes their acceleration smoothly.
- Figures bounce from every edge and never escape the visible canvas.
- Figures pass through one another.
- A strong wall hit can produce a rare world-appropriate resonance; resting contact cannot
  produce rapid repeats.
- Smudge still produces immediate Lead and can nudge a crossed moving figure.
- The dock hides automatically, its folded corner restores it, and the corner alone blocks the
  underlying Smudge hit area.
- Rotation does not enter a landscape Canvas mode.
- Stop returns figures to the current composition and does not save physical positions.

## Verification

Automated tests cover the pure physics boundary, bounce/cooldown behavior, no object-object
collision, exact Stop return, Smudge intersection and world-to-material mapping. UI coverage
checks dock auto-hide, reveal and portrait locking.

Before merging, verify on a physical iPhone: gravity axes in all portrait hand positions,
slow and fast tilt, repeated Play/Stop, Smudge at the folded-corner boundary, collision-tail
density in all four sound worlds, audio interruptions, Reduce Motion, VoiceOver and sustained
CPU/GPU/audio performance.
