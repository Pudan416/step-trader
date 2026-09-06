# Day Objects: four sound worlds and unified Remix

## Purpose

Make successive Canvas remixes feel like genuinely different musical places,
not the same harmony and synthesizers with different effects. The feature keeps
the existing health-data mappings while expanding timbral variety, musical
behavior, and automatic mix validation.

## Product behavior

The full-screen Canvas exposes one Music/Sound toggle, one Remix action, and a
compact Undo action. Remix is not shown in the collapsed Canvas.

One Remix changes the whole generated entity at once:

- visual composition, objects, and background;
- sound world and mood;
- harmonic progression and voicings;
- rhythm, bass, harmony, lead, and happening selections;
- deterministic variation seed.

Steps, sleep, happening count, and spent colors remain unchanged. Undo restores
the complete previous visual and musical state. Reusing the same seed and input
must reproduce the same result.

The normal Canvas does not expose a preset browser or permanent world selector.
After a remix, the selected world and mood may appear briefly as lightweight
feedback. Diagnostic builds retain direct world, mood, layer, and instrument
audition controls.

## Health-data mappings

The four worlds change style, never the meaning of the Canvas inputs:

- steps control rhythmic density, percussion complexity, and the permitted
  kick/bass activity, reaching maximum complexity at the user's step goal;
- sleep controls harmonic richness, voicing openness, pad/piano layering, and
  progression movement, reaching maximum richness at the user's sleep goal;
- happenings create stable musical identities and schedule sparse tonal
  one-shots, plucks, textures, or responses;
- touch controls a monophonic lead whose pitch, expression, and filter follow
  the gesture;
- spent colors controls bounded glitch/distortion intensity without changing
  the selected world.

## Sound worlds

### Acoustic Oddities

Prepared/felt piano, muted strings, wood knocks, skin percussion, breath and
small mechanical-acoustic details. Timing is slightly humanized, attacks are
soft, and harmony can use unusual suspended voicings without becoming harsh.

### Living Field

Air, water-like motion, organic drones, soft bells, rustles, and sparse natural
percussion. It has the fewest simultaneous layers, the longest spaces, and the
widest reverb tails.

### Industrial Ritual

Metal resonators, restrained machinery, low impacts, electrical pulses, bowed
metal, and a deep controlled sub. It is the most rhythmic world, but avoids
bright brittle transients and constant distortion.

### Electric Dream

Warm analog pads, FM/pluck colors, evolving arpeggios, rounded electronic
basses, and expressive synthetic leads. It is the most melodic world and may
use the most obvious tonal motion.

## Moods and layer density

Every world has three moods selected by Remix:

1. `sparse`: approximately 3–4 active layer roles, long gaps, minimal rhythm;
2. `moving`: approximately 5–6 roles, clearer pulse and harmonic movement;
3. `strange`: up to 7 roles, more unusual motifs and modulation, with the same
   loudness and concurrency limits as the other moods.

The mood is not a replacement for health data. It defines the arrangement
grammar; normalized health inputs define how far that grammar is developed.

## Instrument families and combinations

Each world provides four curated families for harmony, bass, and lead. Each
family has three bounded parameter variants aligned with the three moods. Drum
and percussion selection uses two or three world-specific kits. Happenings use
world-specific pools drawn from the existing authored bank plus any new sounds
needed to make the four palettes distinct.

The three variants are parameter recipes for the runtime synthesizers, not 48
new sampled instruments per role. New checked-in audio is added only for
happening or percussion characters that the runtime synthesis cannot express.

The system stores synthesizer choices as portable parameter recipes rather than
opaque Ableton-only presets. A recipe identifies oscillator/wavetable choices,
envelopes, filters, modulation, articulation, effects sends, gain, and allowed
register. This keeps the auditioned sound reproducible in the iOS engine.

The music director selects from curated compatibility groups. It does not freely
combine every bass, pad, lead, and kit. Each group defines safe register,
spectral space, transient density, and effect-send ranges.

## Cross-world echoes

At least 80% of the active palette belongs to the selected world. A remix may
select one guest element from a compatible neighboring world with a probability
between 10% and 20%. Guest elements must follow the current scale, register,
concurrency, and mix constraints. Harmony and bass foundations never both come
from another world.

Allowed affinities are:

- Acoustic Oddities ↔ Living Field;
- Living Field ↔ Electric Dream;
- Electric Dream ↔ Industrial Ritual;
- Industrial Ritual ↔ Acoustic Oddities.

## Harmony and musical identity

World selection changes more than processing. Each world has its own progression
templates, chord-extension limits, voicing rules, harmonic rhythm, and cadence
behavior. Sleep still controls richness inside those rules. Two equal-input
renders from different worlds must differ in harmony or voicing as well as in
instrument palette and processing.

Remix selects a progression template, compatible instrument group, arrangement
shape, and seed. Repeated events remain deterministic, sparse, and distributed
instead of auditioning every available sound sequentially at startup.

## Offline audition and automatic mix checks

The app's actual `AVAudioEngine` graph is the source of truth. A diagnostic
offline renderer exports the same plan through the same instrument and effect
paths used on device.

For each acceptance run it exports:

- 12 numbered full-mix WAV files: four worlds × three moods;
- stems for rhythm, bass, harmony, happenings, and lead;
- a JSON manifest mapping hidden audition numbers to seed, world, mood,
  instruments, progression, and parameter recipes;
- a machine-readable analysis report.

The user-facing audition files are numbered so they can be evaluated without
being biased by style labels. The mapping remains available after the listening
notes are recorded.

Automated analysis checks:

- integrated loudness and true peak;
- silence, non-finite samples, clipping, and abnormal DC offset;
- low/mid/high-band energy and excessive high-frequency brightness;
- crest factor and transient density;
- bass/kick low-frequency overlap;
- harmony/lead and happening/lead spectral masking;
- per-layer audibility and excessive reverb-tail accumulation.

The development pipeline may apply only bounded corrections that the runtime
can reproduce: gain, filter cutoff, effect sends, sidechain/ducking, and limited
compressor or limiter settings. Accepted corrections are written back to the
versioned recipe catalog; analysis never changes a user's mix unpredictably at
runtime. The pipeline rejects combinations that remain unsafe. External offline
effects must not appear in an accepted preview unless the same processing exists
in the iOS runtime.

Automated metrics are a safety and consistency gate, not a substitute for human
listening. Final palette approval comes from the numbered audition set on phone
speaker and headphones.

## Failure handling and compatibility

- Missing or invalid recipes fall back to a compatible instrument in the same
  world; they do not silently switch the whole arrangement to another world.
- If a guest element is unavailable, the remix remains pure to its selected
  world.
- A failed offline render reports its seed and layer instead of retrying
  indefinitely.
- Rendering keeps the existing duration and memory guards for generated
  happening assets.
- Existing `feltAndWood` states retain their stored raw value and display as
  Acoustic Oddities. Existing `metalAndCurrent` states retain their raw value
  and display as Industrial Ritual. Living Field and Electric Dream are added as
  new values. Legacy deterministic entry points keep their current snapshots.
- Audio remains limited to `DEBUG` and `INTERNAL_BUILD` unless a separate
  release-gate decision is made.

## Acceptance criteria

- Four worlds and three moods are deterministic and individually selectable in
  diagnostics.
- The full-screen Remix atomically changes visual and musical state; Undo
  restores both.
- Normal Canvas UI has no manual instrument-selection workflow.
- Equal-input world renders differ in source instruments and harmony/voicing,
  not only effects.
- Compatibility rules prevent unrestricted random combinations.
- All 12 numbered previews and stems render through the iOS playback graph and
  pass automated safety thresholds.
- No startup cascade auditions the full happening bank.
- Existing health mappings and the ten-happening limit remain intact.
- The final choice is verified manually on an iPhone and headphones.

## Non-goals

- Importing the complete AudioKit Synth One application or preset browser.
- Shipping Ableton, VST, or Audio Unit dependencies inside the iOS app.
- Fully automatic artistic mastering without human approval.
- Expanding beyond four worlds or three moods in this iteration.
