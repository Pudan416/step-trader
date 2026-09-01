# Day Objects Expanded Sound Palette Design

**Date:** 2026-09-01

**Parent designs:**

- [Day Objects Generative Music System](2026-08-30-day-objects-generative-music-system-design.md)
- [Day Objects Native Instrument Bank](2026-08-30-day-objects-native-instrument-bank-design.md)

## Goal

Make every Remix of Day Objects feel like a distinct ambient musical entity
without weakening the existing mapping from the picture to music or returning
the multi-engine overload that previously made the Canvas silent and distorted.

The expanded version provides:

- six curated Harmony palettes;
- ten audibly distinct Lead presets;
- four complete Drum Kits;
- thirty stable, numbered Happening sound recipes;
- three perceptible Spent colors characters;
- one Remix action that selects a new coherent combination;
- a 30-pad Happening audition grid inside Day Objects Lab.

The audition grid is part of the real native runtime. It is not a browser
approximation, a separate website, or a second full audio engine.

## Product mappings that remain fixed

The expanded palette changes timbre, not the meaning of the picture controls:

| Day Objects input | Musical responsibility |
|---|---|
| Steps progress, capped at the user's daily goal | Rhythm density, percussion activation, fills, and tempo movement |
| Sleep progress, capped at the user's sleep goal | Harmony layering, voicing depth, and tonal brightness |
| Zero to ten Happenings | Number of active musical objects, births, and recurring one-shots |
| Spent colors, zero to one hundred | Strength of the selected degradation character |
| Finger position and movement | Monophonic Lead pitch, expression, and filter movement |
| Remix | New coherent instrument palette, progression, patterns, effects character, and deterministic seeds |

Reaching 100% of a goal is the maximum musical complexity. Values above the
goal do not add more layers or density.

Continuous controls never replace instruments while the user drags a slider.
They change the intensity of the currently selected world. Structural changes
occur only on Remix and enter at the next safe musical boundary.

## Expanded palette

### Harmony

The catalog contains eight Pad presets, six Keys presets, and three treatments
of the existing felt-piano multisample. Existing approved presets count toward
these totals.

The Music Director does not combine the catalog without constraints. It selects
one of six curated Harmony palettes. Each palette defines compatible Pad, Keys,
and Piano targets, register ranges, filter behavior, shared-space sends, and
maximum simultaneous layers. This preserves ambient movement while preventing
random combinations from masking one another.

Sleep continues to control how many roles are audible. It does not select the
palette. Each progression contains multiple chords and retains the existing
slow, voice-led ambient movement rather than holding one chord indefinitely.

### Lead

The Lead catalog contains ten presets spanning these perceptual families:

- airy and breath-like;
- round analog;
- glassy and bell-adjacent;
- vocal or soft-wah;
- bright but bounded synthetic.

Each preset has its own safe performance profile: register, attack, release,
portamento, cutoff range, expression depth, delay send, and reverb send. The
same XY gesture therefore feels like a different instrument after Remix rather
than merely changing oscillator parameters behind an identical envelope.

Only one Lead voice is live. Selecting ten presets must not allocate ten live
Lead graphs.

### Drum Kits

The rhythm plan continues to use semantic roles such as timing-anchor kick,
closed hat, shaker, organic percussion, and ghost accent. Remix selects one of
four kits that maps those roles to different samples and synthesis recipes:

1. **Soft Electronic** — rounded synthesized kick, restrained hats, and soft
   electronic transients.
2. **Organic** — recorded skin, shaker, and natural percussion with conservative
   room sends.
3. **Dusty** — filtered and gently saturated attacks with shorter bandwidth and
   looser humanization.
4. **Wood / Percussion** — wood blocks, sticks, mallet-like low pulses, and dry
   high accents.

Steps controls role activation and density inside the selected kit. The kit
does not change as Steps moves. The timing-anchor kick remains stable under
Spent colors so the composition retains a pulse at high degradation.

All four kits reuse a fixed pool of drum players. A kit change swaps prepared
buffers and bounded recipe parameters; it does not attach another drum bank.

## Thirty Happening sound recipes

### Stable identities

The bank exposes exactly thirty stable IDs, displayed as `01` through `30`.
Once introduced, a number is never reassigned to a different recipe. This lets
device-listening feedback refer to a sound unambiguously.

The initial distribution is:

| IDs | Family | Source strategy |
|---|---|---|
| 01–06 | Pluck | Project-authored synthesis and rendered Synth One-derived recipes |
| 07–12 | Mallet | VCSL marimba, xylophone, and vibraphone recordings |
| 13–18 | Bell | VCSL glockenspiel, tubular bell, and selected vibraphone recordings |
| 19–24 | Soft one-shot | Project-authored droplets, muted impacts, and resonant attacks |
| 25–30 | Texture | Project-authored reverse blooms, filtered tails, and tuned resonances |

A recipe is not merely a filename. It records:

- stable ID and display number;
- family and source provenance;
- one or more source buffers and their root MIDI notes;
- preferred register and legal transposition range;
- tonal, resonant, or noise-like pitch behavior;
- envelope, pan range, level trim, delay send, and reverb send;
- birth emphasis and recurrence behavior;
- checksums for all source and processed assets.

Manual audition and automatic playback use the same production recipe.

### Audio sources and provenance

External acoustic material comes only from the Versilian Community Sample
Library at revision:

~~~text
c1ea7bcc3c7309650ab0da9d15c9cd1fbc4a4c7e
~~~

VCSL is distributed under CC0 and explicitly permits use in commercial
software. The repository URL, pinned revision, complete CC0 notice, original
file checksums, processed file checksums, root notes, and edits are stored in
the asset manifest even though attribution is not legally required.

Project-authored sounds are rendered from checked-in synthesis recipes or from
the already pinned, MIT-licensed Synth One conversion source. Their generator
parameters and rendered checksums are retained so an asset is reproducible.

Splice, Freesound, and other account-bound or user-uploaded libraries are not
part of this version. No audio asset enters the app without explicit App Store
redistribution rights and a concrete provenance record.

### Harmonic adaptation

Every tonal recipe declares its real source pitch. When music is running, a
manual or automatic Happening chooses the closest chord tone inside the
recipe's preferred register. The resolver chooses the nearest available root
sample and permits no more than two semitones of playback-rate transposition.
An instrument requiring a wider shift must provide additional root samples or
is rejected from the production manifest.

If the transport is off, a numbered pad plays the recipe's fixed reference
note. A solo tone cannot be harmonically dissonant without another tonal
context, but this mode is intended primarily for evaluating timbre.

Noise-like textures are not pitch-shifted. Resonant textures tune their filter
or resonator to a chord tone. If no current chord is available, playback falls
back to the recipe's reference pitch; it never guesses an arbitrary chromatic
note.

### Automatic births and recurrence

Adding a Happening immediately triggers its birth sound when audio is active.
The same stable recipe then recurs according to its scheduling plan.

Within one Remix, active Happenings select recipes without replacement up to
the ten-Happening limit. At ten active Happenings the director guarantees at
least six source identities and prevents adjacent births from using the same
family when another compatible family is available. As the count increases,
each object may recur less often, but every active Happening remains scheduled
and audible within the bounded recurrence horizon.

Manual presses on `01`–`30` audition the recipe only. They do not add a visual
Happening, change the Happenings slider, advance its recurrence counter, or
mutate the Remix seed.

## Happening pad grid

Day Objects Lab places a five-column by six-row grid directly below the
existing Steps, Sleep, Happenings, and Spent colors controls.

- Buttons are labeled `01` through `30`.
- A tap briefly highlights the pad and triggers that exact recipe.
- With Canvas music running, the recipe is tuned to the current chord and
  plays over the composition.
- With Canvas music stopped, only the recipe plays at its reference pitch.
- The recipe includes its production envelope and spatial sends; "isolated"
  means no automatically added musical layer, not a dry source-file bypass.
- Repeated taps retrigger through bounded voice allocation and cannot create
  an unbounded tail.
- VoiceOver announces the pad number and family. Exploration alone does not
  trigger audio.

The main Sound button continues to mean "Canvas composition on or off." A pad
may activate the audio session for sample-only audition without starting the
transport or changing the Sound button to the composition-on state.

The existing Instrument Diagnostics category browser remains available for
Lead, Harmony, Drum, and Piano comparison. The numbered Happening grid does
not open a second diagnostic audio world.

## Spent colors redesign

The current squared mapping makes middle values too quiet, and its only clear
saturation target is the gesture Lead. The replacement uses a perceptual,
piecewise smooth curve with these fixed anchors:

| Spent colors | Effective amount |
|---:|---:|
| 0 | 0.00 |
| 10 | 0.08 |
| 25 | 0.20 |
| 50 | 0.45 |
| 75 | 0.72 |
| 100 | 1.00 |

Values interpolate monotonically with smoothstep easing between anchors.
Parameter ramps last at least 300 milliseconds, preventing a small slider
change from producing a sharp edge.

Remix selects one of three characters:

- **Worn Tape:** gentle saturation, wow/flutter, bounded pitch wear, and a
  slightly softened high end;
- **Broken Delay:** delay-time instability, filtered repeats, and rare
  non-anchor dropouts;
- **Digital Dust:** short filtered interruptions, stereo displacement, and
  restrained timing/pitch erosion on texture roles.

The effect is audible on sustained Harmony and Happenings even when the user is
not touching the Lead. From zero through fifty it reads primarily as warmth and
wear. Above fifty, dropout and instability become progressively obvious. The
timing-anchor kick never drops out, and all feedback, pitch, timing, and output
limits remain bounded by role.

## Remix behavior

One Remix produces a structural world containing:

- one of six Harmony palettes;
- one of ten Lead presets;
- one of four Drum Kits;
- a without-replacement mapping from active Happening IDs to the 30 recipes;
- one of three Spent colors characters;
- new progression, rhythm, humanization, pan, recurrence, and effect seeds.

The result is deterministic for its generated Remix seed and remains stable
while the user moves day-data controls. Remix preserves Steps, Sleep,
Happenings count, and Spent colors values.

The coordinator rejects an immediately repeated compound signature. Individual
components may recur when required by catalog size, but the complete
Harmony/Lead/Drum/Glitch combination cannot be identical to the previous
Remix. Structural replacement begins at the next bar boundary and uses bounded
release/fade ramps rather than an abrupt graph restart.

## Single-runtime architecture

`DayObjectsAudioRuntime` owns one AudioKit engine and one final limiter. It has
two preparation levels:

1. **Sample-only:** a lightweight master graph, shared spatial sends, and four
   Happening sample-player voices. A numbered pad can start this level without
   constructing the full generative world.
2. **Full music:** the existing bounded Harmony, Lead, Piano, Rhythm, Glitch,
   and transport components attach to the same master graph. Transitioning
   from sample-only may briefly stop and restart the one engine, but a second
   engine never runs concurrently.

The full-music allocation replaces the old synthesized Happening pool with
four shared sample-player voices. Harmony and Lead retain a fixed total of
eight tonal voices, Piano retains two sample voices, and Drums retain the
current ten-player allocation budget. Catalog growth changes preset data and
sample buffers, not live DSP graph multiplicity.

The manual Happening bus and automatic scheduler share the four Happening
voices. Voice stealing prefers the oldest released or lowest-priority recurring
event; a manual audition or new birth outranks a background recurrence. All
Happening voices feed one bounded delay send and one bounded reverb send.

Drum Kit buffers, tonal preset records, and all short Happening buffers are
decoded away from the UI interaction path. Required sample metadata is
validated before the runtime reports ready. The production asset set is
limited to 30 MiB on disk and 48 MiB of decoded Happening buffers. Source
masters may remain larger outside the app bundle.

Canvas and the existing full Instrument Diagnostics world remain mutually
exclusive. The integrated 30-pad grid is an exception because it routes
through the Canvas runtime rather than creating another world.

## Failure behavior

- A build-time manifest validator fails on duplicate IDs, missing root notes,
  absent licenses, bad checksums, illegal transposition ranges, or missing
  required files.
- A required production recipe that fails runtime decoding is marked
  unavailable, its pad is disabled with an accessible explanation, and Remix
  excludes it. The remaining Canvas does not crash.
- If fewer than the required thirty recipes validate in a release candidate,
  the acceptance suite fails; partial availability is a runtime safety path,
  not an acceptable shipped state.
- Audio-session or engine failures leave both the Sound button and pad audition
  retryable.
- Starting Canvas music releases sample-only audition tails before preparing
  the structural world. Stopping Canvas music never leaves transport events or
  held Lead gates alive.
- Backgrounding, interruption, or leaving Day Objects releases all manual and
  scheduled voices and never resumes automatically.

## Test strategy

### Pure model and asset tests

- exact totals: six Harmony palettes, ten Leads, four Drum Kits, thirty
  Happening recipes, and three Spent colors characters;
- unique stable IDs and complete source/license/checksum metadata;
- all VCSL-derived files point to the pinned revision;
- every tonal target belongs to the current chord when one exists;
- nearest-root transposition never exceeds two semitones;
- noise and resonant pitch behaviors take their specified paths;
- ten active Happenings select without replacement and meet family-diversity
  constraints;
- Remix is deterministic per seed and rejects an immediate compound repeat;
- Spent colors anchors, monotonic interpolation, role limits, and exact zero
  neutrality;
- Steps, Sleep, Happenings, Spent colors, Lead, and Remix responsibilities
  remain separate.

### Runtime tests

- sample-only and full-music states use one engine and one final limiter;
- repeated pad taps and repeated Remix operations keep node and player counts
  fixed;
- manual audition does not mutate scene state, Happening count, recurrence
  counters, or seeds;
- manual audition outranks recurrence under four-voice pressure;
- Drum Kit and tonal preset changes reuse existing players/voices;
- starting full music from sample-only releases audition tails safely;
- stopping, interruption, and background cycles converge to silent off;
- ten Happenings, held Lead, maximum rhythm/harmony, and Spent colors 100 do not
  produce sustained render overload or non-finite audio parameters.

### UI tests

- all thirty numbered pads exist in a five-by-six grid;
- tapping with Canvas Sound off starts sample-only audition without starting
  transport;
- tapping with Canvas Sound on uses the current chord and overlays the music;
- pad accessibility labels are stable and VoiceOver exploration is silent;
- the existing sliders, Remix, Sound, canvas gestures, and Diagnostics remain
  usable;
- pad taps never add visual Happenings.

### Physical-iPhone acceptance

On the target iPhone, using both its speaker and headphones:

- all thirty pads are individually identifiable enough for numbered feedback;
- ten automatically active Happenings remain audible as distinct objects;
- all ten Leads feel materially different under the same gesture;
- all four Drum Kits have distinct bodies and avoid an eight-bit character;
- all six Harmony palettes contain audible chord movement;
- Spent colors is clearly distinguishable at 0, 25, 50, 75, and 100 without a
  harsh jump at low values;
- sample-only cold audition becomes audible within 1.5 seconds and warm pad
  retriggers begin within 100 milliseconds;
- full Canvas Sound reaches ready in no more than 8 seconds;
- a ten-second maximum-load run has no sustained audio-overload sequence,
  clipping, stuck gate, or visible interaction freeze.

Human listening remains an acceptance gate. Automated tests can prove routing,
limits, determinism, and signal presence, but cannot declare timbral quality.

## Delivery sequence

1. Add reproducible asset-generation/import tooling and the strict manifest.
2. Produce all thirty Happening recipes and their processed app assets.
3. Add the sample-only runtime level and integrated 30-pad grid.
4. Replace automatic synthesized Happenings with the shared sample bank.
5. Expand and normalize the Harmony and Lead catalogs.
6. Add four buffer-swapping Drum Kits.
7. Implement the three Spent colors characters and perceptual curve.
8. Extend Remix to select a coherent world without immediate repetition.
9. Run focused automated suites, full build verification, overload
   instrumentation, and physical-iPhone listening.

No phase merges to main as part of this work. The completed experimental build
is installed for listening first; integration remains a separate product
decision.

## Acceptance criteria

- The agreed catalog totals and stable numbered audition grid are present.
- Manual and automatic Happenings use the same chord-aware production recipes.
- Every palette expansion preserves the picture-to-music responsibilities.
- Catalog growth does not create concurrent engines or unbounded live graphs.
- Performance, lifecycle, licensing, and physical listening gates pass.
- The user can evaluate every Happening alone or over the current composition
  before any decision to merge the work.
