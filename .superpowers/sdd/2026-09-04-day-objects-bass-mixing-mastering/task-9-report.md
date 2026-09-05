# Task 9 report — offline mix calibration, Fix Round 1

Date: 2026-09-05
Worktree: `day-objects-generative-audio`

## Status

Fix Round 1 is complete. The corrected ITU-R BS.1770-5 true-peak analyzer,
process-wide live/offline playback exclusion, frame-zero diagnostic isolation,
truthfully named offline attenuation estimate, deterministic worst-case
scheduling proof, controlled calibration ledger, and corrected 31 × 60-second
evidence are implemented. The full matrix passes all prescribed gates and every
scenario rendered in less than 60 seconds.

The signed app built successfully. The paired phone was unavailable at the
final installation step, so listening on headphones and a speaker—including
the required BB Röy comparison—is explicitly pending.

## Fix Round 1 implementation

### Standards-conformant analysis

- True peak evaluates all four ITU-R BS.1770-5 Annex 2 FIR phases for every
  input clock with eleven zero-valued history samples and an eleven-sample
  zero-padded file tail. The short-file/raw-peak shortcut is gone.
- Conformance fixtures cover `[1, 1]` (`1.244873046875` expected amplitude),
  leading-edge and trailing-edge impulses (`0.97216796875`), and ordinary
  inter-sample overshoot.
- Integrated-loudness analysis rejects captures shorter than one complete
  400 ms gating block with `insufficientDuration`.
- The PCM adapter accepts one- or two-channel Float32 planar and interleaved
  `AVAudioPCMBuffer` data and rejects unsupported layouts/formats.

### Production-graph safety and diagnostics

- One process-wide `@MainActor` playback lease now guards all live-start and
  offline begin/end paths. Separate bank/runtime instances cannot start live
  and offline playback concurrently. Throwing, cancelled, and completed paths
  release ownership.
- Diagnostic `-60 dB` isolation hard-zeros a muted role's direct and send
  gains before frame zero. It does not alter full-composition sends. A
  production-path isolated Bass render with no Bass source is exactly silent:
  `-120 LUFS-I`, `-120 dBTP`, estimate `0 dB`.
- The offline field and JSON key are
  `maximumEstimatedLimiterReductionDB`. It is a maximum required peak-
  attenuation estimate used as a conservative offline acceptance gate, not
  observed limiter gain reduction. Task 7's aligned runtime estimator is
  unchanged.
- Worst-case scheduling uses the injected offline transport clock. Rendering
  throws if the audition cannot schedule kickSoft, Bass, chord transition,
  held Lead, and four distinct Happenings. The final evidence contains eight
  activity records, all at host time `1.0` second. No wall-clock sleep is used.
- Rendering remains on the production instrument bank, players, transport,
  role buses, master processors, limiter, and final gain. No graph was
  duplicated and topology/processor behavior did not change.

## Strict TDD evidence

Focused tests were added before each implementation change:

- Analyzer RED exposed boundary-state/short-input true-peak errors, accepted
  sub-400 ms content, and missing interleaved-buffer support. Analyzer GREEN is
  9 tests, 0 failures, 0.537 seconds.
- Playback-lease RED showed distinct live/offline instances could overlap and
  ownership was not process-wide. GREEN covers live-blocks-offline,
  offline-blocks-live, start failure, completion, error, and cancellation.
- Isolation RED showed muted sends/direct ramps could contribute before frame
  zero. GREEN proves immediate direct/send zero, retained selected-role space,
  and true silence when the selected production role has no source.
- Offline-proxy RED changed assertions/JSON to require the estimated name and
  reject the old key; GREEN preserved the Task 7 estimator.
- Worst-case RED required complete, shared-time activity and an error on failed
  scheduling. GREEN records and validates all eight components at one time.
- BB Röy manifest RED expected the approved `-3.00 dB`; the old `-0.75 dB`
  value failed, then the focused manifest and single-Arp guards passed.

## Accepted calibration

The physical pre-limiter master is exactly `-6.00 dB`; there is no hidden
offset. The glue compressor remains `-4.5 dB`, `1.5:1`. The authored resource
cap remains 4.5 seconds.

- Rhythm, Bass, Harmony, Happenings, Lead path calibration: `+10.40 dB` each.
- Final output ceiling/gain: `-1.35 dB`, a stricter implementation of the
  required `<= -1 dBTP` ceiling.
- Return multipliers R/B/H/X/L: `8.0/1.0/2.0/3.4/1.0x`.
- Role targets R/B/H/X/L: `0/0/0/-3.3/-3.1 dB`; Happenings one/two/four-plus
  voice targets: `-3.3/-6.3/-9.3 dB`.
- Descriptor trims: pads Interstellar/Whispering Sands/Forgotten Stories
  `0/0/0`; Bass Analog Boom/Hey Jakob/BB Röy/JEC Hollores
  `-15.65/-9.18/-3.00/-23.45`; Lead Verbacious `0`; keys
  Maschinenmensch/BB Slow Poly/JEC Polaroids `0/0/0 dB`.
- Drum trims: kickSoft, kickFull, shaker, hatClosed, hatOpen, clapSoft, stick,
  organicHigh, and organicLow are all `0 dB`.

No other calibration constant changed in Fix Round 1. The complete approved
Batch A constant enumeration and all eight matched before/after rows—including
LUFS-I, corrected dBTP, all five role-bus RMS values, and
`maximumEstimatedLimiterReductionDB`—are in
`docs/day-objects-bass-mix-listening-checklist.md`.

### Controlled Batch A summary

Batch A compared the exact pre-Task-9 constants with the complete co-dependent
source/drum/role/return/ceiling calibration while BB Röy was fixed at `0 dB`.
The eight after rows measured:

| Scenario | LUFS-I | dBTP | Max estimated required peak attenuation |
|---|---:|---:|---:|
| `steps-50` | -17.9674313262 | -1.3059508361 | 1.0653505681 dB |
| `sleep-mid` | -17.9671020842 | -1.3058449346 | 1.0678149555 dB |
| `happenings-1` | -17.8785377042 | -1.3227001102 | 1.2375415851 dB |
| `glitch-25` | -17.9743902503 | -1.3057498651 | 1.0671721392 dB |
| `groove-percussion` | -16.7122561603 | -1.3062727604 | 1.8339009703 dB |
| `groove-bass-pulse` | -16.8264908297 | -1.2425661904 | 0.6632391590 dB |
| `groove-bass-arp` | -16.9534858586 | -1.2856275859 | 1.9204454750 dB |
| `groove-bass-bed` | -16.4390704154 | -1.2632073429 | 1.2228460453 dB |

### Controlled Batch B and final BB Röy margin

With every other accepted constant fixed, the BB Röy `0 dB` controlled row was
`-16.9247261214 LUFS-I / -1.2856275859 dBTP / 2.0366382269 dB` estimated
attenuation. The `-0.75 dB` controlled row was `-16.9413872390 /
-1.2856269856 / 1.9055932226`.

A subsequent fresh full-matrix process at `-0.75 dB` measured the arp estimate
at `2.0414150537 dB`, a `0.0414150537 dB` normal-gate miss. A narrow `-1.00 dB`
retry also demonstrated Audio Unit phase/run variability at `2.2257795682 dB`.
That `-1.00 dB` row was `-16.9666418895 LUFS-I / -1.2781329446 dBTP /
-23.5368149998/-32.200801/-32.056458/-41.8204526213/-120 dBFS` in
`48.229 seconds`. The approved `-3.00 dB` descriptor trim changed no other
constant. Its clean single-Arp guard was:

- LUFS-I: `-16.9619914429`
- true peak: `-1.2856275859 dBTP`
- R/B/H/X/L RMS: `-23.5368149998/-32.2032899136/-32.2040890857/-41.8204526213/-120 dBFS`
- maximum estimated required peak attenuation: `1.9575108338 dB`
- render wall time: `48.0319903333 seconds`

The final fresh matrix arp improved to `1.7057571669 dB`. The `-3.00 dB` value
is therefore a measurement-driven safety margin for observed run variability.
Because this scalar safety trim could affect perception despite stable program
loudness, headphones/speaker comparison against all other Bass presets is a
mandatory pending human gate.

## Final 31 × 60-second matrix

The final matrix ran sequentially from a stopped state after the `-3.00 dB`
single-Arp guard passed. Result: 31/31 scenarios passed in 1,475.010 seconds.
Every individual render stayed below 60 seconds; slowest was
`worst-case-overlap` at `51.6410653333 seconds`.

| Gate | Corrected measurement | Result |
|---|---:|---|
| Representative range | -17.9746638139 to -16.6096452011 LUFS-I | pass |
| Maximum true peak, all scenarios | -1.1402764016 dBTP (`groove-bass-arp`) | pass |
| Maximum normal estimated required peak attenuation | 1.9305114176 dB (`groove-percussion`) | pass |
| Glitch 0→100 delta | 0.1514006402 LU | pass |
| Isolated Harmony/Happenings/Lead spread | 0.8072180411 LU | pass |
| Isolated Bass/no source | -120 LUFS-I / -120 dBTP / 0 dB estimate | pass |
| Worst case | -14.1439393416 LUFS-I / -1.1791212622 dBTP / 2.7164646395 dB estimate | pass; stress exemption |
| Worst-case activity | 8 records at host time 1.0 s | pass |

Final representative scenarios:

| Scenario | LUFS-I | dBTP | Max estimated required peak attenuation |
|---|---:|---:|---:|
| `steps-50` | -17.9746638139 | -1.3055663477 | 1.0699847957 dB |
| `sleep-mid` | -17.9745358809 | -1.3056927035 | 1.0685025880 dB |
| `happenings-1` | -17.8789865464 | -1.3226928757 | 1.2485442560 dB |
| `glitch-25` | -17.9670454603 | -1.3058274851 | 1.0680914800 dB |
| `groove-percussion` | -16.7105926679 | -1.2359024157 | 1.9305114176 dB |
| `groove-bass-pulse` | -16.8293500992 | -1.2491926378 | 0.6685214743 dB |
| `groove-bass-arp` | -16.9574396408 | -1.1402764016 | 1.7057571669 dB |
| `groove-bass-bed` | -16.6096452011 | -1.2626127918 | 1.1823371702 dB |

Exact per-scenario values, role RMS/peaks/voice counts, stress timestamps,
seeds, presets, and wall times are in
`docs/day-objects-mix-scenario-report.json` (schema 2).

## Verification and environment limits

- Corrected analyzer: 9 tests, 0 failures, 0.537 seconds.
- Renderer/scenario group without opt-in long renders: 12 tests, 0 failures,
  2 intentional skips, 43.589 seconds.
- Instrument-bank lease/isolation/calibration guards: 4 tests, 0 failures,
  0.104 seconds.
- BassPlayer held-audition regressions: 10 tests, 0 failures, 0.761 seconds.
- Instrument manifest: 5 tests, 0 failures, 0.014 seconds.
- Generic iOS Debug build with signing disabled: succeeded.
- Signed generic iOS Debug build with Apple Development provisioning:
  succeeded.
- Full live `DayObjectsMusicPlaybackEngineTests` could not complete in this
  simulator: Core Audio reported no system object, `Default-InputOutput`
  `-66680`, then `AURemoteIO -10851`; the existing forced player access after
  preparation failure crashed the test host. The unchanged retry was not run.
  Manual offline rendering and all focused regressions above are unaffected.
- Paired iPhone Costa was listed but unavailable at final install time; the
  device-targeted build returned 70 because Xcode could not resolve that
  destination. The corrected signed generic bundle was not installed.
  Physical listening remains pending and is recorded in the checklist.
- No Python process was used. No process exceeded the 60-second per-scenario
  limit. No merge, push, PR, destructive command, or visual suite was run.

## Evidence paths

- Public matrix: `docs/day-objects-mix-scenario-report.json`
- Listening checklist and complete calibration ledger:
  `docs/day-objects-bass-mix-listening-checklist.md`
- This report:
  `.superpowers/sdd/2026-09-04-day-objects-bass-mixing-mastering/task-9-report.md`
