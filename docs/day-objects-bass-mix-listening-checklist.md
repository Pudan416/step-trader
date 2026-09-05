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
-0.75 dB to -3.00 dB. Its clean single-Arp guard measured
-16.9619914429 LUFS-I / -1.2856275859 dBTP /
-23.5368149998/-32.2032899136/-32.2040890857/-41.8204526213/-120 dBFS /
1.9575108338 dB Est. in 48.0319903333 seconds. The Fix Round 1 matrix arp row
measured -16.9574396408 / -1.1402764016 /
-23.5368149998/-32.1065983665/-32.1446138067/-41.8204526213/-120 /
1.7057571669 in 46.0648424583 seconds. The larger descriptor margin is
measurement-driven protection against observed phase variability; subjective
parity/presence versus all three other Bass presets remains a required human gate.

### Batch C — bounded plan-aware crest calibration

Fresh Audio Unit instances still showed a normal-path crest miss after the
static calibration: the unmodified Fix Round 1 baseline produced a
`2.0118004800 dB` BB Röy estimate in one matrix. Static drum, role-path, return,
master, ceiling, and descriptor constants remain exactly as listed above.
Batch C changes only continuous mix targets and their already-existing spatial
sends, through the existing 250 ms mix ramp; it does not change topology,
processor settings, scheduling, density, or source ownership.

For finite Steps density `d` clamped to `0...1`, let
`s = d*d*(3 - 2*d)`. Exact R/B/H/X/L adjustments are:

| Groove mode | Rhythm | Bass | Harmony | Happenings | Lead |
|---|---:|---:|---:|---:|---:|
| Percussion | 0 dB | 0 dB | 0 dB | 0 dB | 0 dB |
| Bass pulse | `-0.35 - 0.20*s` dB | 0 dB | 0 dB | 0 dB | 0 dB |
| Bass arp | -1.00 dB | -0.50 dB | -0.50 dB | 0 dB | 0 dB |
| Bass bed | `-0.30 - 0.20*s` dB | 0 dB | 0 dB | 0 dB | 0 dB |

Every value is deterministic, finite, and bounded to `-1...0 dB`. Pure
endpoint/continuity tests and runtime tests prove these are continuous typed
mix updates, not structural restarts. An initial bounded candidate with Rhythm
`-1.00 dB` and sustained H/X/L support `+0.15 dB` was rejected after its third
fresh Arp instance measured `-17.4566120034 LUFS-I / -1.3678789145 dBTP /
2.0470997704 dB Est.` in `46.1562080833 seconds`. No matrix was started from
that failed guard.

The approved Bass-Arp mapping then passed three new processes. Each row is
`LUFS-I / dBTP / R/B/H/X/L dBFS / Est. dB / wall seconds`:

| Fresh phase | Measurement |
|---|---|
| 1 | -17.4694864832 / -1.3384633865 / -23.5368149998/-32.1810459355/-32.1886860510/-41.8204526213/-120 / 0.4240340887 / 46.2179845417 |
| 2 | -17.4861938602 / -1.3130822988 / -23.5368149998/-32.1979306038/-32.1759504242/-41.8204526213/-120 / 0.8692114159 / 46.4536765417 |
| 3 | -17.4672113672 / -1.2738191085 / -23.5368149998/-32.1843836725/-32.1465248807/-41.8204526213/-120 / 0.3463445901 / 46.1708956667 |

The matched pre/post Batch C matrix rows below retain all five source-bus RMS
values. These taps are upstream of the adjusted direct/send controls, so their
near-equality is expected; the output loudness/true-peak/estimate columns are
the calibration result. Each cell is `LUFS-I / dBTP / R/B/H/X/L dBFS / Est.`:

| Scenario | Before Batch C | After Batch C |
|---|---|---|
| `groove-percussion` | -16.7135542883 / -1.2359394225 / -21.5115011435/-120/-32.3756485503/-38.6330895837/-120 / 1.9313412916 | -16.7036691167 / -1.2790782691 / -21.5115011435/-120/-32.3747295334/-38.6330895837/-120 / 1.5657671749 |
| `groove-bass-pulse` | -16.8733791663 / -1.2447605031 / -21.5348392783/-23.9713873271/-36.6134598119/-37.5720667745/-120 / 0.6667092771 | -17.0830949216 / -1.2978885687 / -21.5348392783/-23.8252834932/-36.6151637791/-37.5720667745/-120 / 0.2503473095 |
| `groove-bass-arp` | -16.9164679419 / -1.2799025129 / -23.5368149998/-32.1420325209/-31.9456984465/-41.8204526213/-120 / 1.4155779795 | -17.4952783082 / -1.2797309389 / -23.5368149998/-32.1344606251/-32.1690609607/-41.8204526213/-120 / 1.1900997990 |
| `groove-bass-bed` | -16.5226345078 / -1.2563554102 / -23.2759495407/-23.3317398245/-32.2290908693/-49.2786751582/-120 / 0.7266063756 | -16.6914186346 / -1.2628145634 / -23.2759495407/-23.3366633770/-32.7517791520/-49.2786751582/-120 / 0.8167629127 |

### Final automated gates

| Gate | Corrected measurement | Result |
|---|---:|---|
| Scenario count / duration | 31 / 60 s each | pass |
| Representative LUFS-I range | -17.9671539227 to -16.6914186346 | pass |
| Maximum true peak, all scenarios | -1.1836861452 dBTP (`glitch-100`) | pass |
| Maximum normal estimated required peak attenuation | 1.5657671749 dB (`groove-percussion`) | pass |
| Glitch 0→100 loudness difference | 0.1505796141 LU | pass |
| Isolated Harmony/Happenings/Lead spread | 0.7357630853 LU | pass |
| Isolated Bass with no source | -120 LUFS-I / -120 dBTP / 0 dB Est. | pass; true silence |
| Worst-case overlap | -14.1389113374 LUFS-I / -1.2294584654 dBTP / 2.8161689303 dB Est. | pass; stress exemption |
| Worst-case shared-time proof | 8 records at real subdivision 48 / host 10.1139240506 s | pass: kickSoft, Bass, chord transition, held Lead, four Happenings |
| Harmony crossfade proof | first audible progress at subdivision 49 / 10.3037974684 s; max progress 1.0 | pass |
| Bass diagnostic release | scheduled/actual 10.3339240506 s; active voices after release 0 | pass |
| Slowest render | 51.7031045833 s (`worst-case-overlap`) | pass |

## Final regression record — 2026-09-05

After the Fix Round 1 lifecycle, lease, expectation, and UI repairs, the
required full `Steps4Tests` invocation completed on an iPhone 17 simulator
running iOS 26.3.1. The durable result bundle records 1,486 tests: 1,448 passed,
31 skipped, and exactly 7 failed tests. All seven are the proven pre-branch
`DayObjectRenderFrameTests` baseline waiver: the two committed-signature tests,
visible-actor fixture, lightest-palette grain, bounded post-grain, high-resolution
scallop coverage, and static-radial Metal ABI test. Xcode's console counted 11
failed assertions inside those 7 tests. There were no additional failed tests,
no test-host crash, and no lease cascade. Live-output fixtures on this simulator
now report precise skips for Core Audio `-10851`; explicit production manual-
render fixtures remain enabled. Durable bundle:
`.superpowers/sdd/2026-09-04-day-objects-bass-mixing-mastering/xcresults/fix-round-1-final-unit-2.xcresult`.

The required `DayObjectsLabUITests` invocation passed: 8 tests, 7 passed,
1 skipped, 0 failed. The skipped method first proved the sound-off Happening
pad safe, then reported that the simulator had no valid Core Audio output when
the Sound-on half was attempted. The original crash diagnosis is corrected:
the first pad tap crashed **before** the Sound control was tapped, during
sample-only preparation cleanup; it was not a Sound-on crash. Catalog-derived
Happening labels, the scoped/hittable category menu, and Sound-dependent
Timeline activity all passed. Durable bundle:
`.superpowers/sdd/2026-09-04-day-objects-bass-mixing-mastering/xcresults/fix-round-1-final-ui.xcresult`.

Both required compile gates passed with exit 0 and `BUILD SUCCEEDED`: Debug for
the iPhone 17 simulator and Debug for generic iOS, each with code signing
disabled. Their durable bundles are `fix-round-1-final-simulator-build.xcresult`
and `fix-round-1-final-device-build.xcresult` in the same evidence directory.
The last-ten-commits whitespace audit passed with no output. At audit time, the
only unrelated workspace changes remained the pre-existing modified native
instrument-bank design spec and the separate untracked instrument-bank
listening checklist; neither belongs to this acceptance record.

## Physical acceptance record

A signed generic Debug bundle `personal-project.StepsTrader` built successfully
on 2026-09-05. The final single device check found paired **iPhone Costa**
(iPhone 15 Pro, iPhone16,1) in the `unavailable` state. The current bundle was
not installed. Every acoustic row remains pending; no automated measurement is
represented as physical acceptance.

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
