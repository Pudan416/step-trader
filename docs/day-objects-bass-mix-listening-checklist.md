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
- Compare BB Röy’s Phaser directly with Analog Boom, Hey Jakob, and JEC Hollores 2 on both headphones and a speaker: the measured safety trim must not make BB Röy subjectively disappear or lose useful Bass presence.

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
- Ordinary scenarios show less than 2 dB maximum estimated required peak attenuation and no audible pumping. This offline proxy is an acceptance gate, not observed limiter gain reduction.
- The stress case stays at or below -1 dBTP, remains finite, and does not crackle or flatten into sustained limiting.

## Translation checks

- **Mono:** kick, bass fundamental, and central harmony remain stable; ambience narrows gracefully.
- **Small speaker:** rhythm and bass articulation remain understandable even when the lowest octave disappears.
- **Headphones:** no extreme pan jump, piercing Lead resonance, or isolated tail on one side.
- **Low level:** melody, timing anchor, and overall density remain identifiable.

## Record and gate

For every issue, record scenario ID, timestamp, device, severity, and whether it repeats. Stop the release for any non-finite sample, true peak above -1 dBTP, representative render outside -18 to -16 LUFS-I, routine maximum estimated required peak attenuation at or above 2 dB, role-spread/glitch failure, repeatable click, or audible distortion.

Analyze any exported PCM file or directory with:

```sh
Scripts/day_objects_audio/analyze_day_objects_mix.swift path/to/render-or-directory
```

Use `--output report.json` to retain JSON. The command exits nonzero when a file misses the configured LUFS or true-peak limits; use `--help` for override flags. Commit reports, not rendered audio.

Simulator note: Core Audio may log missing default I/O or AudioKit parameter diagnostics even though AVAudioEngine manual rendering succeeds. Treat the PCM report and tests as the offline result; complete this listening checklist on real output hardware.

## Automated calibration record — 2026-09-05, corrected true peak

The checked-in JSON contains 31 sequential 60-second, 48 kHz captures made
through the production instrument bank, players, injected transport clock,
five role buses, master processors, limiter, and final output gain. All
captures are finite and exactly 60 seconds. No generated audio is checked in.

True peak uses all four ITU-R BS.1770-5 Annex 2 phases at every input clock,
with eleven zero samples before the file and an eleven-sample zero-padded tail.
There is no raw-peak shortcut for short files. Captures shorter than one full
400 ms loudness-gating block are rejected rather than assigned a misleading
integrated value. Planar and interleaved Float32 mono/stereo PCM are supported.

`R/B/H/X/L` below is source-bus RMS for Rhythm, Bass, Harmony, Happenings, and
Lead. `-120` is the analyzer silence floor. These taps are upstream of the
direct/send path gains; output silence, not tap RMS, is the isolation gate.
`Est.` means `maximumEstimatedLimiterReductionDB`: the offline maximum required
peak-attenuation estimate used as a conservative gate, not measured limiter
gain reduction and not the Task 7 time-aligned runtime metric.

### Protected constants

- Physical pre-limiter master trim: exactly -6.00 dB before and after; no hidden offset.
- Glue compressor: -4.5 dB threshold and 1.5:1 ratio, unchanged.
- Production topology and processor behavior: unchanged.
- Authored one-shot/tail cap: 4.5 seconds, unchanged.

### Batch A — co-dependent production calibration

This approved batch was rendered twice from controlled constants: the exact
pre-Task-9 state, then the complete calibration below with BB Röy held at 0 dB.
Every changed constant in the batch is enumerated here.

| Calibration point | Before | Batch A after |
|---|---:|---:|
| Rhythm path calibration | 0 dB | +10.40 dB |
| Bass path calibration | 0 dB | +10.40 dB |
| Harmony path calibration | 0 dB | +10.40 dB |
| Happenings path calibration | 0 dB | +10.40 dB |
| Lead path calibration | 0 dB | +10.40 dB |
| Final output gain/ceiling | -1.00 dB | -1.35 dB |
| Rhythm return multiplier | 1.0x | 8.0x |
| Harmony return multiplier | 1.0x | 2.0x |
| Happenings return multiplier | 1.0x | 3.4x |
| Rhythm role target | -10 dB | 0 dB |
| Bass role target | -12 dB | 0 dB |
| Harmony role target | -10 dB | 0 dB |
| Happenings aggregate target | -8 dB | -3.3 dB |
| Happenings one/two/four-plus voice target | -8/-11/-14 dB | -3.3/-6.3/-9.3 dB |
| Lead role target | -9 dB | -3.1 dB |
| `pad.interstellar` trim | -13.15 dB | 0 dB |
| `pad.whispering-sands` trim | -12.40 dB | 0 dB |
| `pad.forgotten-stories` trim | -14.89 dB | 0 dB |
| `bass.analog-boom` trim | -14.89 dB | -15.65 dB |
| `bass.hey-jakob` trim | -18.00 dB | -9.18 dB |
| `bass.bb-roys-phaser` trim | -15.92 dB | 0 dB |
| `bass.jec-hollores-2` trim | -17.08 dB | -23.45 dB |
| `lead.verbacious` trim | -17.08 dB | 0 dB |
| `keys.maschinenmensch` trim | -14.89 dB | 0 dB |
| `keys.bb-slow-poly` trim | -14.89 dB | 0 dB |
| `keys.jec-polaroids-2` trim | -14.89 dB | 0 dB |
| `kickSoft` drum trim | -8 dB | 0 dB |
| `kickFull` drum trim | -6 dB | 0 dB |
| `shaker` drum trim | -10 dB | 0 dB |
| `hatClosed`, `hatOpen`, `clapSoft`, `stick`, `organicHigh`, `organicLow` trims | -12 dB each | 0 dB each |

Bass and Lead return multipliers remained 1.0x. Unlisted descriptors retained
their prior trims. The -1.35 dB fixed output is a stricter implementation of
the required `<= -1 dBTP` ceiling, chosen for measured inter-sample margin.

All values below are direct outputs from the matched probe. Each cell is
`LUFS-I / dBTP / R/B/H/X/L dBFS / Est. dB`.

| Scenario | Batch A before | Batch A after |
|---|---|---|
| `steps-50` | -42.3496033274 / -24.6965355381 / -29.4221862533/-120/-41.9504469591/-44.4489745208/-120 / 0 | -17.9674313262 / -1.3059508361 / -21.3894941581/-120/-35.1149854659/-44.4489745208/-120 / 1.0653505681 |
| `sleep-mid` | -42.3496584920 / -24.6971295481 / -29.4221862533/-120/-41.9512967270/-44.4489745208/-120 / 0 | -17.9671020842 / -1.3058449346 / -21.3894941581/-120/-35.1148584357/-44.4489745208/-120 / 1.0678149555 |
| `happenings-1` | -41.9350339070 / -24.4414654053 / -29.4221862533/-120/-41.9503494587/-41.1600480872/-120 / 0 | -17.8785377042 / -1.3227001102 / -21.3894941581/-120/-35.1141591498/-41.1600480872/-120 / 1.2375415851 |
| `glitch-25` | -42.3493948057 / -24.6971295481 / -29.4221862533/-120/-41.9501379481/-44.4489745208/-120 / 0 | -17.9743902503 / -1.3057498651 / -21.3894941581/-120/-35.1150958769/-44.4489745208/-120 / 1.0671721392 |
| `groove-percussion` | -39.6653796837 / -15.9428971941 / -29.5486845303/-120/-41.1468004963/-38.6330895837/-120 / 0 | -16.7122561603 / -1.3062727604 / -21.5115011435/-120/-32.3823727491/-38.6330895837/-120 / 1.8339009703 |
| `groove-bass-pulse` | -37.7916277246 / -16.7507192660 / -29.5565539083/-23.1774751025/-43.9910203524/-37.5720667745/-120 / 0 | -16.8264908297 / -1.2425661904 / -21.5348392783/-23.7950224425/-36.2795868136/-37.5720667745/-120 / 0.6632391590 |
| `groove-bass-arp` | -39.8731434578 / -16.0867605930 / -31.5629612572/-41.7645519167/-40.8286931155/-41.8204526213/-120 / 0 | -16.9534858586 / -1.2856275859 / -23.5368149998/-32.2126440226/-32.2150583193/-41.8204526213/-120 / 1.9204454750 |
| `groove-bass-bed` | -33.4263021778 / -9.3780734795 / -31.3083663594/-17.7030968780/-40.9230457387/-49.2786751582/-120 / 0 | -16.4390704154 / -1.2632073429 / -23.2759495407/-23.3284486328/-32.0781514948/-49.2786751582/-120 / 1.2228460453 |

### Batch B — BB Röy-only safety trim

Every Batch A after-constant was held fixed. The controlled BB Röy row at
0 dB measured -16.9247261214 LUFS-I / -1.2856275859 dBTP /
-23.5368149998/-32.2241208540/-31.9145591838/-41.8204526213/-120 dBFS /
2.0366382269 dB Est. The initial guard-passing candidate, -0.75 dB, measured
-16.9413872390 / -1.2856269856 /
-23.5368149998/-32.2453134369/-32.1803584610/-41.8204526213/-120 /
1.9055932226.

A fresh full-matrix instance at -0.75 dB then exposed Audio Unit phase/run
variation: its arp row measured -16.9575217219 LUFS-I / -1.2856263853 dBTP /
-23.5368149998/-32.1884054974/-32.2218342943/-41.8204526213/-120 dBFS /
2.0414150537 dB Est., missing the normal `<2 dB` gate by 0.0414150537 dB.
The -1.00 dB narrow retry was also variable: -16.9666418895 LUFS-I /
-1.2781329446 dBTP /
-23.5368149998/-32.200801/-32.056458/-41.8204526213/-120 dBFS /
2.2257795682 dB Est. in 48.229 seconds. No failed command was repeated
unchanged.

The approved Batch B extension changes only `bass.bb-roys-phaser` from
-0.75 dB to the final -3.00 dB. Its clean single-Arp guard measured
-16.9619914429 LUFS-I / -1.2856275859 dBTP /
-23.5368149998/-32.2032899136/-32.2040890857/-41.8204526213/-120 dBFS /
1.9575108338 dB Est. in 48.0319903333 seconds. The fresh final-matrix arp row
measured -16.9574396408 / -1.1402764016 /
-23.5368149998/-32.1065983665/-32.1446138067/-41.8204526213/-120 /
1.7057571669 in 46.0648424583 seconds. The larger descriptor margin is
measurement-driven protection against observed phase variability; subjective
parity/presence versus all three other Bass presets remains a required human gate.

### Final automated gates

| Gate | Corrected measurement | Result |
|---|---:|---|
| Scenario count / duration | 31 / 60 s each | pass |
| Representative LUFS-I range | -17.9746638139 to -16.6096452011 | pass |
| Maximum true peak, all scenarios | -1.1402764016 dBTP (`groove-bass-arp`) | pass |
| Maximum normal estimated required peak attenuation | 1.9305114176 dB (`groove-percussion`) | pass |
| Glitch 0→100 loudness difference | 0.1514006402 LU | pass |
| Isolated Harmony/Happenings/Lead spread | 0.8072180411 LU | pass |
| Isolated Bass with no source | -120 LUFS-I / -120 dBTP / 0 dB Est. | pass; true silence |
| Worst-case overlap | -14.1439393416 LUFS-I / -1.1791212622 dBTP / 2.7164646395 dB Est. | pass; stress exemption |
| Worst-case shared-time proof | 8 records at host time 1.0 s | pass: kickSoft, Bass, chord transition, held Lead, four Happenings |
| Slowest render | 51.6410653333 s (`worst-case-overlap`) | pass |

## Physical acceptance record

A signed Debug bundle `personal-project.StepsTrader` built successfully on
2026-09-05. Paired **iPhone Costa** (iPhone 15 Pro, iOS 26.6.1) was unavailable
when the corrected build was ready, so the current bundle was not installed.
Every acoustic row remains pending; no automated measurement is represented as
physical acceptance.

| Required check | Headphones | Speaker | Notes |
|---|---|---|---|
| Bass: Analog Boom isolated | pending | pending | comparison reference |
| Bass: Hey Jakob isolated | pending | pending | comparison reference |
| Bass: BB Röy’s Phaser isolated | pending | pending | must retain perceived parity/presence after -3.00 dB safety trim |
| Bass: JEC Hollores 2 isolated | pending | pending | comparison reference |
| BB Röy vs all three other Bass presets | pending | pending | explicit A/B; fail if BB Röy subjectively disappears |
| Groove percussion, Steps 25/50/100 | pending | pending | three states required |
| Groove bass pulse, Steps 25/50/100 | pending | pending | three states required |
| Groove bass arp, Steps 25/50/100 | pending | pending | three states required |
| Groove bass bed, Steps 25/50/100 | pending | pending | three states required |
| Sleep low/full | pending | pending | both states required |
| Happenings 1/10 | pending | pending | both densities required |
| Glitch 0/100 | pending | pending | compare texture vs loudness |
| Lead slow/fast | pending | pending | check upper-mid harshness |
| Worst-case overlap | pending | pending | check crackle/pumping |
