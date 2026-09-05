# Canvas Sound Lab Design

## Purpose

Build a separate, phone-first browser demo for testing whether a day's activity data, added happenings, remixing, and direct touch performance can form a coherent ambient instrument. The demo is independent of the Nowhere iOS app and does not access HealthKit or personal data.

## Product surface

The experience is a single full-viewport page designed primarily for iPhone Safari. Its central surface is both a reactive abstract background and an XY performance instrument. Compact controls expose Sound, Steps, Sleep, Glitch, Happening, Undo, Remix, and Reset.

Audio never starts automatically. The user must press Sound before the Web Audio context starts. Audio stops or suspends when the page becomes hidden and resumes only through an explicit user action when iOS requires it.

## Music model

The composition has three layers:

1. A persistent background layer derived from Steps, Sleep, Glitch, and the current global music seed.
2. Up to ten happening layers, each derived from an independent seed created when Happening is pressed.
3. A monophonic lead controlled by finger movement across the main surface.

The global music seed determines the scale, root note, tempo family, synth palette, patterns, and effects. All generated notes are constrained to the same scale so the layers and lead remain harmonically compatible.

### Steps

Steps range from 0 to 20,000 in the demo. They primarily control pulse rate, tempo, movement, and event density. The mapping is smoothed so low values produce spacious music rather than an unusably slow metronome.

### Sleep

Sleep ranges from 0 to 10 hours. It controls harmonic stability, filter openness, stereo width, envelope length, and reverb clarity. Low sleep remains aesthetically intentional: darker, less stable, and more suspended rather than simply worse.

### Glitch

Glitch ranges from 0 to 100. It progressively adds detune, timing jitter, bit reduction, noise, stutter probability, and delay instability. At 100 the sound is heavily degraded but retains pitch and safe output gain. The visual background receives corresponding displacement, flicker, scan-line, and color-separation effects.

### Happenings

Pressing Happening creates one sound seed, immediately auditions it, and folds a recurring motif, texture, pulse, or accent into the composition. The interface shows a count from 0/10 to 10/10. At ten, the add control is disabled. Undo removes the most recent seed and restores capacity.

The demo does not associate happening seeds with visual objects or semantic labels. To protect clarity and performance, the arranger assigns the ten seeds across a bounded voice pool instead of creating an unlimited audio graph.

### Remix

Remix keeps Steps, Sleep, Glitch, and the number of happenings. It creates a new global music seed and deterministically reinterprets every happening seed with a new scale, patch assignment, rhythm, and effects configuration. The old and new settings transition smoothly without an abrupt audio stop.

### Touch lead

Touching or dragging on the main performance surface plays one lead voice. Horizontal position selects pitch within the current scale; vertical position controls filter brightness and timbre. Movement speed adds expression through vibrato and saturation. Releasing the touch ends the note with a delay and reverb tail. Pointer Events provide a unified implementation for touch, pen, and mouse.

## Visual design

The page uses a dark, tactile, poster-like direction suited to Nowhere without copying the production canvas. A slowly moving multi-field gradient represents the base composition. Steps increase motion, Sleep changes depth and clarity, and Glitch progressively destabilizes the image.

The performance surface shows only a restrained luminous touch trace and small seed indicators. It deliberately avoids visual happening shapes so the prototype tests the musical concept in isolation.

Controls must remain reachable with one thumb, respect iPhone safe areas, and use touch targets at least 44 points high. The interface should remain legible in portrait and usable in landscape and desktop browsers.

## Technical architecture

The demo is a static client-only site using React, TypeScript, CSS, Canvas 2D, and the Web Audio API. It has no server data, authentication, analytics, or external audio files.

Audio work is divided into focused modules:

- music theory and seeded generation;
- the audio graph and voice scheduling;
- application state and user actions;
- background and touch-trace rendering;
- the mobile interface.

Audio parameters are ramped rather than assigned abruptly. The master chain includes filtering, delay, convolution-free reverb, compression, and a conservative output gain. Active oscillators and scheduled events are bounded, and timers stop when sound is off or the document is hidden.

## Accessibility and fallback behavior

All controls have visible labels and accessible names. Current values and the happening count are available to assistive technology. The page supports keyboard operation on desktop. Reduced Motion disables nonessential visual drift while preserving audio behavior.

If Web Audio is unavailable, controls and visuals continue to work and the page explains that sound is unsupported. iOS audio-context suspension is surfaced through the Sound control rather than treated as a fatal error.

## Acceptance criteria

- The deployed page opens and fits correctly in iPhone Safari.
- Sound begins only after pressing Sound.
- Steps, Sleep, and Glitch audibly and visibly change the composition.
- Happening adds a distinct seeded sound and recurring layer up to exactly ten.
- The eleventh addition is impossible until Undo or Reset removes a seed.
- Remix changes the musical result while preserving all four user-set inputs and happening count.
- Touching and dragging the performance surface produces an in-scale lead with expressive X/Y control.
- Sound is bounded, click-free under normal interaction, and free of large gain spikes.
- Reset returns all controls and seeds to their initial state.
- The production iOS app and its data remain untouched.
