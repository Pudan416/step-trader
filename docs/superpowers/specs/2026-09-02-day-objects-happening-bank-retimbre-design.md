# Day Objects Happening Bank Retimbre Design

**Date:** 2026-09-02

**Parent:** [Day Objects Expanded Sound Palette](2026-09-01-day-objects-expanded-sound-palette-design.md)

## Goal

Replace the pre-release Happening sample bank with thirty perceptually distinct,
musically useful ambient one-shots. Each pad must sound like a different small
instrument or event, not like another note from the same piano, mallet, FM, or
noise generator.

The work is a retimbre of the existing numbered bank. It does not change the
meaning of Steps, Sleep, Happenings, Spent colors, Lead gestures, or Remix, and
it does not add another audio engine or another sample-player pool.

## Listening diagnosis

Physical-iPhone listening rejected the first bank with this grouping:

- `01–06` sounded identical;
- `07–08` sounded identical, sharp, and much too loud;
- `09–12` were musically useful but shared an obvious piano/mallet-like body;
- `13–16` sounded identical and much too loud;
- `17–18` needed less high-frequency energy;
- `19–24` sounded identical;
- `25–27` sounded identical;
- `28–30` sounded like unattractive noise.

The implementation explains the report. `01–06`, `19–24`, `25–27`, and
`28–30` each use one generator algorithm with parameter-only variations.
`07–18` are close pairs of related mallet or bell recordings. Every processed
file is independently peak-normalized to `-3 dBFS`, while the runtime adds the
same plate and fixed-time delay topology. Peak normalization does not equalize
perceived loudness, and the common effects collapse otherwise different
attacks into related tails.

The pre-release promise that numbered identities would remain sonically stable
starts only after this physical-listening acceptance. The user explicitly
rejected the current sounds, so this retimbre keeps IDs and UI references but
replaces their unaccepted audio identities.

## Chosen approach

Use a hybrid bank:

- ten distinctly synthesized short instruments;
- ten organic or acoustic one-shots;
- ten hybrid sounds combining an organic or synthesized attack with a rendered
  ambient tail.

External recordings remain restricted to the already pinned VCSL CC0 source.
Project-authored synthesis remains deterministically rendered from checked-in
recipes. Account-bound libraries and unclear redistribution licenses remain
excluded.

No recipe may qualify as unique merely by changing decay, brightness,
modulation index, random seed, pitch, or wet amount on an otherwise identical
renderer. A distinct recipe needs a distinct source recording, a distinct
synthesis topology, or a materially different layered attack/body/tail
construction.

## Exact numbered palette

All sounds are monophonic events. Tonal entries retain four prepared roots and
resolve to the current chord through the existing pitch resolver. Unpitched
material must remain spectrally subordinate and may not become a sustained
noise bed.

| ID | Working identity | Construction | Audible role |
|---:|---|---|---|
| 01 | Warm analog ping | band-limited triangle plus sine, closing low-pass envelope, short tape echo | round, compact high-mid punctuation |
| 02 | Glass FM droplet | two-operator FM with a falling modulation envelope and dark diffusion tail | clear droplet without a metallic spike |
| 03 | Muted pulse pluck | narrow pulse body, low-pass impulse, short room tail | dry synthetic tick with pitch |
| 04 | Hollow string | Karplus–Strong/waveguide excitation with damped feedback | woody synthetic pluck |
| 05 | Air reed blip | sine body plus band-passed breath transient and soft pitch settling | airy but tonal one-shot |
| 06 | Reverse pluck bloom | rendered reverse swell terminating in a small plucked body | directional ambient accent |
| 07 | Wooden kalimba | VCSL or project-recorded soft thumb/wood attack with transient damping | low-volume organic click and tone |
| 08 | Ceramic knock | project-authored modal ceramic body with two inharmonic modes | round object impact, not vibraphone |
| 09 | Soft marimba | one retained soft VCSL marimba source, darkened and shortened | warm mallet reference |
| 10 | Balafon brush | one retained soft VCSL balafon source with a dry wooden tail | brighter organic reference |
| 11 | Muted vibraphone | VCSL soft vibe with motor-like tail removed and a dark chorus tail rendered offline | soft floating metal, no common plate body |
| 12 | Felt key | project-authored felt attack plus a short sine/string body | the only deliberately piano-adjacent event |
| 13 | Soft metal bowl | modal resonator excited by a damped impulse, high modes attenuated | dark metallic bloom |
| 14 | Glass tap bloom | tiny glass attack followed by a reversed, filtered harmonic tail | bright identity with bounded transient |
| 15 | Chorus kalimba | plucked tine body with a rendered micro-detuned stereo-to-mono chorus tail | wider thumb-pluck character |
| 16 | Nylon pizzicato | short waveguide/string attack with dark room decay | soft string punctuation |
| 17 | Dark tubular bell | retained bell identity, transient softened, high shelf reduced, low-pass tail | distant bell |
| 18 | Distant chime | retained chime identity with slower attack and stronger high-frequency damping | lighter companion to 17, never piercing |
| 19 | Sub bloom | sine/sub impulse with a quiet upper harmonic and slow 250 ms opening | low, soft tonal arrival |
| 20 | Analog filter ping | resonant low-pass self-ring excited by an impulse | rounded electronic drop |
| 21 | Vocal droplet | two-formant resonator over a short sine excitation | small vowel-like one-shot |
| 22 | Phase-distortion bead | phase-distorted oscillator with rapidly decaying index | compact synthetic bead |
| 23 | Rubber FM bubble | low-ratio FM with downward pitch settling | elastic, playful low-mid accent |
| 24 | Bowed harmonic stab | band-limited harmonic stack with slow 30 ms onset and abrupt damped body | brief bowed synthetic gesture |
| 25 | Breath resonator | filtered breath impulse exciting one chord-aware resonator | tonal air event, not noise bed |
| 26 | Bowed glass cloud | three bounded modal partials with a rendered moving tail | smooth spectral bloom |
| 27 | Granular shimmer | deterministic micro-grains from a pitched authored source, dark windowed tail | sparkling but consonant event |
| 28 | Reverse glass gesture | filtered reversed glass-like partials dissolving before a stable pitch forms | clear nonpitched reverse gesture |
| 29 | Soft dust impact | very short filtered particulate attack plus a low modal tail | the only intentionally noisy attack, under 120 ms |
| 30 | Airy exhale | breath transient crossfading into a filtered formant tail | soft discrete event without a stable pitch |

This gives at least twelve distinct source or synthesis topologies across the
bank. No run of three adjacent IDs may share a renderer kind, and no pair may
share both its attack construction and tail construction.

## Attack, body, and tail model

Every recipe is authored as three explicit stages:

1. **Attack:** the identifying transient, normally `3–80 ms` and never an
   uncontrolled full-band spike.
2. **Body:** the pitched or modal identity, normally `80–700 ms`.
3. **Tail:** a recipe-specific rendered decay, normally ending within
   `0.8–4.5 s`.

The distinctive tail is rendered into the processed WAV. Tail types include
tape echo, dark diffusion, short room, filtered reverse bloom, chorus decay,
modal decay, and dry damping. The existing shared runtime delay and plate are
reduced to conservative glue and are not responsible for differentiating the
recipes. This allows four simultaneous Happening voices to retain independent
characters without allocating per-recipe live effects graphs.

The processed asset remains mono because the current pool is mono. Motion and
placement remain runtime responsibilities. Offline chorus or diffusion must
survive a mono compatibility check and may not depend on stereo cancellation.

## Loudness and brightness contract

The renderer removes unconditional per-file peak normalization. It measures
the rendered event after trimming and applies a bounded gain toward a
family-aware loudness target, followed by a sample-peak ceiling.

Processed-file gates:

- sample peak at or below `-6 dBFS`;
- tonal and organic event RMS between `-22` and `-18 dBFS` over the audible
  event, excluding digital silence;
- texture event RMS between `-26` and `-21 dBFS`;
- maximum 50 ms onset RMS at or below `-15 dBFS` for mallet, bell, glass, and
  impact identities;
- no peak-normalization gain may exceed `+12 dB`;
- no non-finite sample, clipping, DC offset above `-50 dBFS`, or discontinuous
  start/end boundary;
- `07–08` and `13–16` must be perceived no louder than the accepted `09–12`
  reference range on the target phone speaker;
- `17–18` receive a rendered high shelf reduction of at least `4 dB` above
  `5.5 kHz` and a low-pass ceiling no higher than `7.5 kHz`;
- `28–30` must contain a time-localized event and an identifiable decay; a
  stationary or continuously pulsing noise bed is rejected.

Runtime `gainDB` remains a small final mix trim, not a repair for a badly
mastered asset. The difference between the loudest and quietest manual pad at
the same reference pitch must be small enough that the listener never changes
the phone volume between pads.

## Harmonic behavior

The existing chord-aware resolver remains authoritative. New tonal and hybrid
recipes provide roots sufficient to keep runtime transposition within two
semitones. A rendered tail must be derived from the same pitch center as its
body, or from chord-safe partials, so pitch-shifting cannot expose an unrelated
fixed harmony.

`25–27` are resonant or pitched textures and retune to a current chord tone.
`28–30` are short unpitched events without a stable pitch center; filtering and
modal balance keep them subordinate to the harmony. With Canvas Sound off, all
pitched pads use their reference note; with Sound on, they use the current
chord exactly as automatic Happenings do.

The Harmony/Piano layer is never baked into a Happening file. A pad must remain
recognizable when auditioned alone. When heard over Canvas music, its tail may
share space but must not become indistinguishable from the felt-piano or keys
layer.

## Generator and source changes

The deterministic asset generator gains separate implementations for the
named synthesis topologies instead of four broad families. Each implementation
declares attack, body, tail, pitch behavior, and mastering inputs in the source
map. Render identity and checksums continue to include every sound-defining
parameter and the renderer implementation hash.

Current VCSL material is retained only for `09–11`, `17`, and `18` after the
specified processing. Any new acoustic source must come from the same pinned
VCSL revision and carry its exact original checksum and path. All other sounds
are project-authored deterministic renders.

The app still ships exactly thirty recipes and 102 processed assets: four roots
for each tonal ID `01–24`, plus one source asset for each texture ID `25–30`.
The existing resonator or pitch-processing path retunes `25–27`; `28–30`
remain unpitched. The bank must remain inside the existing 30 MiB bundle and
48 MiB decoded-buffer limits.

## Runtime behavior

The runtime architecture does not change:

- one `DayObjectsAudioRuntime`;
- one final limiter;
- one shared four-voice Happening pool;
- the same manual and automatic pitch resolver;
- the same birth, recurrence, priority, and voice-stealing semantics;
- the same sample-only to full-music ownership transitions.

Recipe-level delay and reverb values are recalibrated downward because the
assets now carry their identifying tails. Concurrent recipes continue to share
one bounded bus; active recipes contribute only conservative glue values, and
no recipe may raise feedback or wet mix enough to mask the next event.

## Audition and review workflow

The existing `01–30` grid remains the listening surface. The debug pad exposes
the working identity in its accessibility label and loading state but retains
the two-digit visible label.

Delivery uses a listening build installed directly on `iPhone Costa`, without
merging to main. Evaluation happens in two passes:

1. Canvas Sound off: identity, loudness, attack, brightness, and tail of every
   pad in isolation.
2. Canvas Sound on: consonance, separation from Harmony/Piano, and behavior of
   each pad in the composition.

The old rejected bank is not kept as a production toggle. Git history is the
rollback mechanism; an A/B switch would duplicate assets and make the memory
and bundle gates less representative.

## Automated tests

Asset and catalog tests require:

- exactly thirty stable IDs and the expected processed root inventory;
- the exact working identity and topology assigned to every ID;
- at least twelve distinct topology names;
- no three adjacent IDs with the same topology;
- no pair sharing both attack and tail topology;
- complete source provenance, deterministic render identities, and checksums;
- the loudness, peak, onset, DC, boundary, duration, and spectral gates above;
- generated sound fingerprints that reject accidental byte-identical files and
  flag near-clone envelopes/spectra within a topology for explicit review;
- tonal roots and rendered tails consistent with resolver pitch behavior;
- bundle and decoded-memory limits.

Runtime regression tests require that the retimbre changes no allocation,
engine, limiter, priority, pitch-resolution, lifecycle, or scene-mutation
contract. Existing controller and UI tests continue to cover Sound-off and
Sound-on pad audition.

Automated fingerprints are guardrails, not proof of musical quality. A sound
can pass metrics and still fail physical listening.

## Physical-iPhone acceptance

Using both the phone speaker and headphones:

- each of `01–30` is identifiable without looking at the number;
- no reported group above collapses into one perceived instrument;
- `07–08` and `13–16` do not cause a volume flinch;
- `09–12` retain their musical usefulness but no longer share one obvious
  body/tail;
- `17–18` remain bell-like without painful upper harmonics;
- `28–30` read as discrete ambient events rather than unattractive noise;
- every pitched sound remains consonant over at least three different Remix
  harmonic worlds;
- ten active automatic Happenings remain separable and recurring;
- rapid pad presses do not clip, overload, accumulate an unbounded tail, or
  freeze the interface.

Acceptance feedback is recorded by pad number. Failed pads are revised without
reassigning the accepted identities of unrelated numbers.

## Delivery boundaries

- Do not merge, publish, or replace main as part of the retimbre pass.
- Do not import Splice, account-bound downloads, or unverified recordings.
- Do not expand the live graph to obtain timbral variety.
- Do not change Steps, Sleep, Happenings, Spent colors, Lead, or Remix product
  mappings.
- Do not declare the bank complete from metrics alone; physical listening is a
  release gate.

## Acceptance criteria

- The exact hybrid palette and uniqueness constraints are implemented.
- Loudness and transient gates prevent the previously reported harsh groups.
- Recipe-specific rendered tails remove the common plate/piano-like basis.
- Tonal events remain chord-aware and textures become discrete musical events.
- The existing one-engine, four-player, bounded-memory architecture remains
  unchanged.
- Automated suites pass and the user accepts all thirty pads on the physical
  iPhone before any integration decision.
