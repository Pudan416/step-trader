# Task 9 report — offline mix calibration, Fix Rounds 1–2

Date: 2026-09-05
Worktree: `day-objects-generative-audio`

## Status

Fix Rounds 1 and 2 are complete. The corrected ITU-R BS.1770-5 analyzer,
process-wide live/offline playback exclusion, frame-zero isolation, truthfully
named attenuation estimate, real-transport worst-case proof, deterministic Bass
release, bounded plan-aware crest calibration, controlled ledgers, and final
31 × 60-second evidence are implemented. The matrix passes every prescribed
gate and every scenario rendered in less than 60 seconds.

Unsigned and signed generic iOS builds succeeded. The paired phone appeared in
the device list but needed to be unlocked for Xcode preparation, so the current
bundle was not installed. Headphone/speaker listening—including the required
BB Röy comparison—remains explicitly pending.

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
  throws if the audition cannot schedule kickSoft, Bass, a real Harmony chord
  transition, held Lead, and four distinct Happenings. Fix Round 2 removes the
  synthetic future transport event: all eight activities originate at actual
  production subdivision `48`, host time `10.113924050632907` seconds. Harmony
  reports first positive crossfade progress at subdivision `49`, host time
  `10.303797468354425`; the diagnostic Bass release is scheduled and observed
  at `10.333924050632907`, with zero active Bass voices afterward. No wall-clock
  task is used and transport progression stays monotonic.
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
- Fix Round 2 RED proved the old worst-case implementation labeled a future
  subdivision with the current host time and appended synthetic transition
  evidence. GREEN waits for the real second-chord boundary, records production
  Harmony schedule/progress, and releases Bass on virtual transport time.
- Plan-aware calibration RED covered exact groove mappings, finite/capped Steps
  endpoints, continuity, role ownership, the 250 ms ramp, and continuous
  differ/runtime behavior without allocation or structural restart. The first
  bounded candidate was rejected by a third fresh Arp phase at `2.0470997704 dB`
  estimated attenuation; the approved v2 mapping passed three new phases at
  `0.4240340887/0.8692114159/0.3463445901 dB`.

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
- Plan-aware continuous adjustments use finite Steps density `d` clamped to
  `0...1` and smoothstep `s=d²(3-2d)`: percussion `R/B/H/X/L=0/0/0/0/0`;
  Bass pulse `R=-0.35-0.20s dB`; Bass arp `R/B/H=-1.00/-0.50/-0.50 dB`;
  Bass bed `R=-0.30-0.20s dB`; all unlisted role adjustments are `0 dB`.
  Direct and existing spatial-send controls receive the same adjustment through
  the established 250 ms ramp. Timing, density, topology, and processors do not
  change.

No static calibration constant changed in Fix Round 2. The complete approved
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

The Fix Round 1 matrix arp improved to `1.7057571669 dB`. The `-3.00 dB` value
is therefore a measurement-driven safety margin for observed run variability.
Because this scalar safety trim could affect perception despite stable program
loudness, headphones/speaker comparison against all other Bass presets is a
mandatory pending human gate.

### Controlled Batch C plan-aware calibration

Static values remained at the approved baseline. Batch C added only bounded
continuous direct/send adjustments through the existing mix controller. The
first candidate (Arp Rhythm `-1.00 dB`, Happenings/Harmony/Lead support
`+0.15 dB`) was rejected after fresh Arp phase 3 measured
`-17.4566120034 LUFS-I / -1.3678789145 dBTP / 2.0470997704 dB` estimated
attenuation in `46.1562080833 seconds`; isolation and matrix rendering did not
start from that failure.

The accepted Arp-specific adjustment is Rhythm/Bass/Harmony
`-1.00/-0.50/-0.50 dB`, with Happenings/Lead unchanged. Three fresh guards
measured:

| Phase | LUFS-I | dBTP | Max estimated required peak attenuation | Wall |
|---|---:|---:|---:|---:|
| 1 | -17.4694864832 | -1.3384633865 | 0.4240340887 dB | 46.2179845417 s |
| 2 | -17.4861938602 | -1.3130822988 | 0.8692114159 dB | 46.4536765417 s |
| 3 | -17.4672113672 | -1.2738191085 | 0.3463445901 dB | 46.1708956667 s |

The complete four-groove matched pre/post ledger, including all five role-bus
RMS values, is in the listening checklist. The accepted matrix Arp row moved
from `-16.9164679419 LUFS-I / -1.2799025129 dBTP / 1.4155779795 dB` estimate
to `-17.4952783082 / -1.2797309389 / 1.1900997990`; the loudness remains inside
the representative range with meaningful estimate margin.

## Final 31 × 60-second matrix

The final matrix ran sequentially from a stopped state after Steps,
percussion, three fresh Arp phases, isolation, and the exact worst-case guard
passed. Result: 31/31 scenarios passed in 1,447.599 seconds.
Every individual render stayed below 60 seconds; slowest was
`worst-case-overlap` at `51.7031045833 seconds`; the slowest normal scenario
was `lead-fast` at `49.1107215000 seconds`.

| Gate | Corrected measurement | Result |
|---|---:|---|
| Representative range | -17.9671539227 to -16.6914186346 LUFS-I | pass |
| Maximum true peak, all scenarios | -1.1836861452 dBTP (`glitch-100`) | pass |
| Maximum normal estimated required peak attenuation | 1.5657671749 dB (`groove-percussion`) | pass |
| Glitch 0→100 delta | 0.1505796141 LU | pass |
| Isolated Harmony/Happenings/Lead spread | 0.7357630853 LU | pass |
| Isolated Bass/no source | -120 LUFS-I / -120 dBTP / 0 dB estimate | pass |
| Worst case | -14.1389113374 LUFS-I / -1.2294584654 dBTP / 2.8161689303 dB estimate | pass; stress exemption |
| Worst-case activity | 8 records at subdivision 48 / 10.1139240506 s | pass |
| Actual Harmony progress | subdivision 49 / 10.3037974684 s; max progress 1.0 | pass |
| Bass release | scheduled = actual 10.3339240506 s; active voices 0 | pass |

Final representative scenarios:

| Scenario | LUFS-I | dBTP | Max estimated required peak attenuation |
|---|---:|---:|---:|
| `steps-50` | -17.9671539227 | -1.3059827271 | 1.0684256784 dB |
| `sleep-mid` | -17.9669406890 | -1.3059664807 | 1.0675594829 dB |
| `happenings-1` | -17.8787726966 | -1.3227055361 | 1.2412824954 dB |
| `glitch-25` | -17.9669289844 | -1.3059057075 | 1.0675649770 dB |
| `groove-percussion` | -16.7036691167 | -1.2790782691 | 1.5657671749 dB |
| `groove-bass-pulse` | -17.0830949216 | -1.2978885687 | 0.2503473095 dB |
| `groove-bass-arp` | -17.4952783082 | -1.2797309389 | 1.1900997990 dB |
| `groove-bass-bed` | -16.6914186346 | -1.2628145634 | 0.8167629127 dB |

Exact per-scenario values, role RMS/peaks/voice counts, stress timestamps,
seeds, presets, and wall times are in
`docs/day-objects-mix-scenario-report.json` (schema 3).

## Verification and environment limits

- Corrected analyzer: 9 tests, 0 failures, 0.548 seconds.
- Renderer/scenario group without opt-in long renders: 12 tests, 0 failures,
  2 intentional skips, 58.215 seconds.
- Focused analyzer/mix/differ/runtime/Harmony/transport/lease/isolation/Bass
  release verification: 35 tests, 0 failures, 17.247 seconds.
- Final plan-aware mapping/controller suite: 10 tests, 0 failures, 0.019
  seconds; the initial six-test RED selection failed to compile on the missing
  Bass/Harmony mapping fields as intended.
- Generic iOS Debug build with signing disabled: succeeded.
- Signed generic iOS Debug build with Apple Development provisioning:
  succeeded.
- Paired iPhone Costa was listed, but the device-targeted build timed out because
  the phone needed to be unlocked to recover from Xcode preparation errors.
  The failed command was not repeated unchanged; no install was attempted.
  Physical listening remains pending in the checklist.
- No Python process was used. No process exceeded the 60-second per-scenario
  limit. No merge, push, PR, destructive command, or visual suite was run.

## Evidence paths

- Public matrix: `docs/day-objects-mix-scenario-report.json`
- Listening checklist and complete calibration ledger:
  `docs/day-objects-bass-mix-listening-checklist.md`
- This report:
  `.superpowers/sdd/2026-09-04-day-objects-bass-mixing-mastering/task-9-report.md`
