# Day Objects bass/mix listening checklist

Use this after the automated 60-second render matrix passes. The meters catch level failures; this pass catches masking, pumping, translation, and musical-balance problems that a scalar report cannot.

## Session setup

- Use the same checked-in revision and note the device, OS, output path, and listening level.
- Disable system EQ, spatial audio, Sound Check/loudness normalization, and headphone accommodations.
- Start around 70–75 dB SPL on calibrated monitors. Repeat quietly enough to hold a conversation.
- Listen once on neutral headphones, once on small laptop/phone speakers, and once in mono.
- Do not normalize renders. The hard production ceiling is -1 dBTP, the calibrated fixed output gain is -1.35 dB, and the representative-program target is -18 to -16 LUFS-I.
- Keep the app's authored one-shot/tail limit at 4.5 seconds distinct from these 60-second program captures.

## Required matrix

Check the JSON report before listening. It must contain 60-second captures at 48 kHz for:

- Steps: 0%, 25%, 50%, 75%, 100%.
- Sleep: low, mid, full.
- Happenings: 0, 1, 10.
- Glitch: 0%, 25%, 50%, 100%.
- Groove: percussion, bass pulse, bass arp, bass bed.
- Bass presets: Analog Boom, Hey Jakob, BB Röy’s Phaser, JEC Hollores 2.
- Lead: slow and fast gestures.
- Stress case: four Happening tails with a kick/bass attack, chord boundary, and held Lead.
- Isolated Rhythm, Bass, Harmony, Happenings, and Lead buses.

## Listening passes

### Low end and kick/bass handoff

- The kick remains the timing anchor; its onset is audible without a brittle click.
- Bass weight is centered and survives mono without an obvious level collapse.
- The 27 Hz bass cleanup removes unusable rumble without thinning supported notes.
- Ducking reads as separation, not a hole, tremolo, or audible gain pump.
- Bass pulse, arp, and bed remain comparable in perceived weight across all four presets.

### Role balance

- Rhythm supplies motion without pulling focus from Harmony.
- Harmony remains continuous through dense passages and chord changes without clouding the bass.
- One Happening is clearly present; ten Happenings do not become a level jump or a wash.
- Slow and fast Lead gestures sit forward enough to play, without harsh upper-mid buildup.
- The isolated Harmony, Happenings, and Lead captures are within 1.5 LU; confirm they also feel comparable rather than merely measuring alike.

### Space, glitch, and dynamics

- Reverb and delay tails are audible but do not blur the next kick or chord.
- Glitch 0% to 100% changes texture more than loudness; role-level change stays within 1 LU.
- No click, zipper noise, unexpected dropout, or stereo lurch appears at event or chord boundaries.
- Ordinary scenarios show less than 2 dB estimated limiter reduction and no audible pumping.
- The stress case stays at or below -1 dBTP, remains finite, and does not crackle or flatten into sustained limiting.

## Translation checks

- **Mono:** kick, bass fundamental, and central harmony remain stable; ambience narrows gracefully.
- **Small speaker:** rhythm and bass articulation remain understandable even when the lowest octave disappears.
- **Headphones:** no extreme pan jump, piercing Lead resonance, or isolated tail on one side.
- **Low level:** melody, timing anchor, and overall density remain identifiable.

## Record and gate

For every issue, record scenario ID, timestamp, device, severity, and whether it repeats. Stop the release for any non-finite sample, true peak above -1 dBTP, representative render outside -18 to -16 LUFS-I, routine limiter reduction at or above 2 dB, role-spread/glitch failure, repeatable click, or audible distortion.

Analyze any exported PCM file or directory with:

```sh
Scripts/day_objects_audio/analyze_day_objects_mix.swift path/to/render-or-directory
```

Use `--output report.json` to retain JSON. The command exits nonzero when a file misses the configured LUFS or true-peak limits; use `--help` for override flags. Commit reports, not rendered audio.

Simulator note: Core Audio may log missing default I/O or AudioKit parameter diagnostics even though AVAudioEngine manual rendering succeeds. Treat the PCM report and tests as the offline result; complete this listening checklist on real output hardware.

## Automated calibration record — 2026-09-05

The checked-in JSON contains 31 sequential 60-second, 48 kHz captures made
through the production instrument bank, players, transport, five role buses,
master processors, limiter, and final output gain. All captures are finite and
exactly 60 seconds. No generated audio is checked in.

`R/B/H/X/L` below means the measured source-bus RMS for Rhythm, Bass, Harmony,
Happenings, and Lead. `-120` is the analyzer's silence floor. These taps are
upstream of the direct/send path gains, so a role-path-only change correctly
leaves their readings unchanged while changing LUFS-I, dBTP, and limiting.

### Final calibration points

| Point | Before | Accepted measured value |
|---|---:|---:|
| Physical pre-limiter master trim | -6.00 dB | -6.00 dB |
| Rhythm/Bass/Harmony/Happenings/Lead path calibration | 0 dB each | +10.40 dB each |
| Final output gain | -1.00 dB | -1.35 dB |
| Rhythm return multiplier | 1.0x | 8.0x |
| Harmony return multiplier | 1.0x | 2.0x |
| Happenings return multiplier | 1.0x | 3.4x |
| Bass/Lead return multiplier | 1.0x | 1.0x |
| Rhythm / Bass / Harmony role target | -10 / -12 / -10 dB | 0 / 0 / 0 dB |
| Happenings aggregate / Lead target | -8 / -9 dB | -3.3 / -3.1 dB |
| Happenings per-voice target (1/2/4+ voices) | -8 / -11 / -14 dB | -3.3 / -6.3 / -9.3 dB |

The master glue remains at its existing -4.5 dB threshold and 1.5:1 ratio.
No compressor ratio, topology, or processor behavior was changed. The final
-1.35 dB output gain is a deliberately stricter implementation of the
`<= -1 dBTP` requirement; the extra 0.35 dB accommodates measured inter-sample
reconstruction overshoot while the physical master trim remains exactly -6 dB.

### Source trim changes

| Descriptor | Before | Accepted measured trim |
|---|---:|---:|
| `pad.interstellar` | -13.15 dB | 0 dB |
| `pad.whispering-sands` | -12.40 dB | 0 dB |
| `pad.forgotten-stories` | -14.89 dB | 0 dB |
| `bass.analog-boom` | -14.89 dB | -15.65 dB |
| `bass.hey-jakob` | -18.00 dB | -9.18 dB |
| `bass.bb-roys-phaser` | -15.92 dB | -0.75 dB |
| `bass.jec-hollores-2` | -17.08 dB | -23.45 dB |
| `lead.verbacious` | -17.08 dB | 0 dB |
| `keys.maschinenmensch` | -14.89 dB | 0 dB |
| `keys.bb-slow-poly` | -14.89 dB | 0 dB |
| `keys.jec-polaroids-2` | -14.89 dB | 0 dB |

Kick trims changed from -8/-6 dB to 0 dB, shaker from -10 dB to 0 dB,
and the remaining sample-drum recipes from -12 dB to 0 dB. Unlisted
descriptors retain their prior trims.

### Before/after measurement ledger

The original matrix established the under-level baseline: `steps-50` was
-42.349522 LUFS-I / -24.715689 dBTP, `happenings-1` -41.935044 / -24.460287,
`groove-percussion` -39.679180 / -15.939283, `groove-bass-pulse` -37.822897 /
-16.764410, `groove-bass-arp` -39.879223 / -16.100018, and
`groove-bass-bed` -33.309769 / -9.649707; all reported 0 dB limiter reduction.
That first report format did not retain role RMS, so none is invented here.
The earliest complete quartet is the pre-role-path candidate below.

| Scenario | Before role-path: LUFS-I / dBTP / R/B/H/X/L RMS / max GR | Final: LUFS-I / dBTP / R/B/H/X/L RMS / max GR |
|---|---|---|
| `steps-50` | -26.415541 / -9.601273 / -21.389494/-120/-35.119141/-44.448975/-120 / 0 | -17.966954 / -1.157965 / -21.389494/-120/-35.114476/-44.448975/-120 / 1.069786 |
| `sleep-mid` | -26.415089 / -9.582728 / -21.389494/-120/-35.117080/-44.448975/-120 / 0 | -17.967028 / -1.158026 / -21.389494/-120/-35.114827/-44.448975/-120 / 1.066580 |
| `happenings-1` | -26.192738 / -9.253336 / -21.389494/-120/-35.118575/-41.160048/-120 / 0 | -17.878735 / -1.158107 / -21.389494/-120/-35.114648/-41.160048/-120 / 1.245446 |
| `glitch-25` | -26.415310 / -9.582751 / -21.389494/-120/-35.118126/-44.448975/-120 / 0 | -17.967071 / -1.157368 / -21.389494/-120/-35.114817/-44.448975/-120 / 1.068388 |
| `groove-percussion` | -25.041250 / -8.630791 / -21.511501/-120/-32.373816/-38.633090/-120 / 0 | -16.695124 / -1.142764 / -21.511501/-120/-32.382854/-38.633090/-120 / 1.677567 |
| `groove-bass-pulse` | -24.458069 / -9.245117 / -21.534839/-23.871337/-36.257762/-37.572067/-120 / 0 | -16.815603 / -1.120025 / -21.534839/-23.771874/-36.615691/-37.572067/-120 / 0.657144 |
| `groove-bass-arp` | -25.316436 / -9.253040 / -23.536815/-32.270667/-32.221904/-41.820453/-120 / 0 | -17.007618 / -1.237306 / -23.536815/-32.183459/-32.232068/-41.820453/-120 / 1.888281 |
| `groove-bass-bed` | -25.092602 / -9.031049 / -23.275950/-23.271874/-32.177136/-49.278675/-120 / 0 | -16.543746 / -1.204175 / -23.275950/-23.353266/-32.204992/-49.278675/-120 / 1.035582 |

The final 0.75 dB reduction of `bass.bb-roys-phaser` changed its arp scenario
from -17.008499 LUFS-I / -1.237300 dBTP / 2.406402 dB maximum limiter reduction
to -17.007618 / -1.237306 / 1.888281. The interrupted pre-trim report did not
persist its role-RMS dictionary; the accepted post-trim R/B/H/X/L measurement
is -23.536815/-32.183459/-32.232068/-41.820453/-120 dBFS. This was the only
normal scenario above the 2 dB rejection gate, and the trim brought it below
the gate without moving program loudness.

The final +10.40 dB role paths and -1.35 dB output were selected after a
+10.35/-1.30 guard measured `steps-50` at -17.954138 LUFS-I, -1.155682 dBTP,
1.024018 dB reduction and `groove-percussion` at -16.699906, -1.055146,
1.883009. The accepted values measured -17.966954, -1.157965, 1.069786 and
-16.695124, -1.142764, 1.677567 respectively; their source-bus RMS values are
shown above and were unchanged within meter-window variance.

### Final automated gates

| Gate | Measured | Result |
|---|---:|---|
| Representative LUFS-I range | -17.967071 to -16.543746 | pass |
| Maximum true peak, all scenarios | -1.036720 dBTP (`glitch-100`) | pass |
| Maximum normal limiter reduction | 1.888281 dB (`groove-bass-arp`) | pass |
| Glitch 0→100 loudness difference | 0.151907 LU | pass |
| Isolated Harmony/Happenings/Lead spread | 0.735446 LU | pass |
| Worst-case overlap | -14.101134 LUFS-I / -1.093558 dBTP / 2.548300 dB GR | pass; stress exemption |
| Slowest render | 51.151062 s (`worst-case-overlap`) | pass |

## Physical acceptance record

Signed Debug bundle `personal-project.StepsTrader` was built and installed on
paired **iPhone Costa**, iPhone 15 Pro, iOS 26.6.1, on 2026-09-05. A human
listener was not available in this non-interactive run, so every acoustic row
remains pending; no automated result is represented as physical acceptance.

| Required check | Headphones | Built-in speaker | Notes |
|---|---|---|---|
| Bass: Analog Boom isolated | pending | pending | installed build ready |
| Bass: Hey Jakob isolated | pending | pending | installed build ready |
| Bass: BB Röy’s Phaser isolated | pending | pending | installed build ready |
| Bass: JEC Hollores 2 isolated | pending | pending | installed build ready |
| Groove percussion, Steps 25/50/100 | pending | pending | three states required |
| Groove bass pulse, Steps 25/50/100 | pending | pending | three states required |
| Groove bass arp, Steps 25/50/100 | pending | pending | three states required |
| Groove bass bed, Steps 25/50/100 | pending | pending | three states required |
| Sleep low/full | pending | pending | both states required |
| Happenings 1/10 | pending | pending | both densities required |
| Glitch 0/100 | pending | pending | compare texture vs loudness |
| Lead slow/fast | pending | pending | check upper-mid harshness |
| Worst-case overlap | pending | pending | check crackle/pumping |
