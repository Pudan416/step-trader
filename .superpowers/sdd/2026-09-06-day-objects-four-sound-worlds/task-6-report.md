# Task 6 — Automatic mix-quality analysis

Base: `4d37260` on `codex/day-objects-sound-worlds`.

## Result

The diagnostic-only mix analyzer now combines the existing BS.1770 integrated
loudness and four-times true-peak implementation with deterministic 4,096-point
FFT energy ratios for 20…160 Hz, 160…4,000 Hz, and 4,000…20,000 Hz. It also
reports maximum channel DC mean, sample-peak/RMS crest factor, stem-to-mix RMS
audibility, and normalized 20…160 Hz rhythm/bass correlation.

The fixed gates are `-18...-16 LUFS-I`, `<= -1 dBTP`, absolute DC `<= 0.01`,
high-band ratio `<= 0.45`, and provided/intentionally active stems `> -42 dB`
relative to the full mix. Issues and suggestions use stable enum order. Silent
measurements use finite `-120 dB` floors, and empty, non-finite, unsupported,
sample-rate-mismatched, or frame-count-mismatched buffers fail explicitly.

Kick/bass overlap produces a review-only Bass suggestion clamped to gain
`-3...0 dB`, additional ducking `0...4 dB`, cutoff multiplier `0.75...1`, and
reverb-send adjustment `-0.15...0`. Nothing applies a suggestion to live audio.

The Swift CLI now accepts `--stems-directory`, requires the exact filenames
`rhythm.wav`, `bass.wav`, `harmony.wav`, `happenings.wav`, and `lead.wav`, and
serializes a schema-2 quality report for every analyzed full mix. Input file
ordering and JSON keys remain deterministic.

## RED

Command:

```text
xcodebuild test -quiet -project Steps4.xcodeproj -scheme Steps4 \
  -destination 'platform=iOS Simulator,name=iPhone 16e' \
  -only-testing:Steps4Tests/DayObjectsMixQualityAnalyzerTests \
  -only-testing:Steps4Tests/DayObjectsLoudnessAnalyzerTests
```

Result: expected compile failure before production code existed. Both new
synthetic test methods referenced the missing `DayObjectsMixQualityAnalyzer`;
0 tests executed. The tests covered DC/brightness/true-peak classification and
bounded rhythm/bass overlap suggestions.

CLI RED command:

```text
Scripts/day_objects_audio/analyze_day_objects_mix.swift --help 2>&1 | \
  rg -- '--stems-directory'
```

Result: exit 1 because the option was absent.

## GREEN and final verification

The first focused GREEN ran the two new synthetic tests plus the existing nine
loudness tests: 11 passed, 0 failed.

Final command:

```text
xcodebuild test -quiet -project Steps4.xcodeproj -scheme Steps4 \
  -destination 'platform=iOS Simulator,name=iPhone 16e' \
  -only-testing:Steps4Tests/DayObjectsMixQualityAnalyzerTests \
  -only-testing:Steps4Tests/DayObjectsLoudnessAnalyzerTests \
  -only-testing:Steps4Tests/DayObjectsMixScenarioTests
```

Result bundle summary: 28 selected tests, 25 passed, 3 intentional opt-in
long-render skips, 0 failed. The two analyzer suites account for 15/15 passing
tests; the existing offline scenario suite accounts for the remaining 13 tests.

Additional checks:

- CLI bootstrap/help compilation: passed and lists `--stems-directory`.
- Xcode project syntax (`plutil -lint`): passed.
- `git diff --check`: passed.
- Existing project-wide Swift 6 migration warnings remain unchanged.
- The two pre-existing untracked audition WAV files were not read, modified, or
  staged.

## Fix round 1

### Contract and algorithms

`analyze(fullMix:stems:activeRoles:)` now accepts an explicit set of roles that
were intentionally active in the render. Omitting it preserves the original API
semantics by treating `stems.keys` as active. Every supplied buffer is still
validated, but only explicitly active roles participate in the `> -42 dB`
audibility gate or can produce masking/correction suggestions. An active role
without a supplied stem fails with `missingActiveStem` in stable role order.
This handles exporters that always write all five stem files while leaving
unused buses silent.

The schema-3 report adds these deterministic, finite metrics and gates for the
24-second acceptance renders:

- `clippedSampleRatio`: samples with absolute magnitude `>= 1.0`, divided by
  all channel samples. Any such sample reports `clipping`; the
  existing `> -1 dBTP` true-peak safety issue remains independent.
- `transientDensityPerSecond`: full-band frame magnitude rises of at least
  `max(0.02 full scale, 1.5 × full-mix RMS)`, with a 40 ms refractory period,
  divided by duration. Values `> 12/second` report excessive density.
- `harmonyLeadMaskingScore` and `happeningsLeadMaskingScore`: cosine similarity
  of phase-independent, accumulated FFT-bin energy from `160..<4,000 Hz` for
  each active pair. Values `> 0.75` report masking.
- `reverbTailEnergyRatio`: mean-square energy in the final
  `min(2 seconds, duration)` divided by whole-render mean-square energy. A
  steady render scores `1`; values `> 1.5` report excessive tail accumulation.
  The finite report value is capped at `120`.

Spectral metrics use deterministic 4,096-point Hann-windowed FFTs with 50% hop.
Every final window is zero-padded, including the only window of a capture
shorter than 4,096 frames. Band partitions remain `20..<160 Hz`,
`160..<4,000 Hz`, and `4,000...20,000 Hz`. Silent inputs return finite zero
ratios and the existing `-120 dB` floor; non-finite samples remain an explicit
analysis error before report encoding.

Masking suggestions attenuate only the active harmony/happenings role, and a
tail suggestion targets only the most accumulated active spatial role. Merged
suggestions are emitted in `DayObjectsMixRole.allCases` order and remain clamped
to gain `-3...0 dB`, ducking `0...4 dB`, cutoff `0.75...1`, and reverb-send
change `-0.15...0`. They are report data only and are never applied live.

With `--stems-directory`, the CLI now accepts exactly one full-mix file. It
rejects directory and multiple-file inputs, and rejects any resolved input path
that is one of the exact `rhythm.wav`, `bass.wav`, `harmony.wav`,
`happenings.wav`, or `lead.wav` stem paths. Directory analysis remains available
when no stems directory is supplied.

### Fix-round RED evidence

Synthetic API/metric RED:

```text
xcodebuild test -quiet -project Steps4.xcodeproj -scheme Steps4 \
  -destination 'platform=iOS Simulator,name=iPhone 16e' \
  -only-testing:Steps4Tests/DayObjectsMixQualityAnalyzerTests
```

Result: expected compile failure because `activeRoles` and the new metric/issue
members did not exist; 0 tests executed. The failing tests covered all five
exported buffers with silent inactive roles, distinct sample clipping and true
peak, transient density, both masking pairs, tail accumulation, and a short
8 kHz capture.

CLI directory RED:

```text
Scripts/day_objects_audio/analyze_day_objects_mix.swift \
  --stems-directory /tmp/day-objects-task6-cli-red.tE5pX3 \
  /tmp/day-objects-task6-cli-red.tE5pX3 2>&1 | \
  rg 'requires exactly one full-mix file'
```

Result: exit 1/no match because the old CLI recursively treated the directory
as candidate mixes before failing on stem discovery.

CLI multiple-input RED:

```text
Scripts/day_objects_audio/analyze_day_objects_mix.swift \
  --stems-directory /tmp/day-objects-cli-stems \
  /tmp/mix-one.wav /tmp/mix-two.wav 2>&1 | \
  rg 'requires exactly one full-mix file'
```

Result: exit 1/no match because the old parser emitted only a generic unexpected
argument error.

### Fix-round GREEN and final verification

The first expanded analyzer GREEN was 12 passed, 0 failed. Its only preceding
test failure was the short 8 kHz Nyquist fixture expecting more than 90% high
energy; the zero-padded Hann window correctly measured `0.7277169241728002`,
still above the production `0.45` brightness gate, so the assertion was aligned
to the contract. Three negative controls were then added for separated spectra,
a steady tone, and a missing active stem. The focused analyzer and loudness run
passed 24/24 tests (15 mix-quality and 9 loudness).

Final command:

```text
xcodebuild test -quiet -project Steps4.xcodeproj -scheme Steps4 \
  -destination 'platform=iOS Simulator,name=iPhone 16e' \
  -resultBundlePath /tmp/day-objects-task6-fix-final.2eEcPa/Task6Fix.xcresult \
  -only-testing:Steps4Tests/DayObjectsMixQualityAnalyzerTests \
  -only-testing:Steps4Tests/DayObjectsLoudnessAnalyzerTests \
  -only-testing:Steps4Tests/DayObjectsMixScenarioTests
```

Result bundle summary: 37 selected tests, 34 passed, 3 intentional opt-in
long-render skips, 0 failed. The analyzer/loudness suites passed 24/24; the
scenario suite supplied the other 13 selected tests.

Four CLI regression checks passed: stems-plus-directory rejection,
stems-plus-stem-path rejection, stems-plus-multiple-input rejection, and help
output. `plutil -lint Steps4.xcodeproj/project.pbxproj` and `git diff --check`
also passed. No runtime audio behavior, ledger entry, or WAV file was changed.

## Fix round 2

### Active-stem and Task 7 caller contract

When `--stems-directory` is present, the schema-4 CLI now requires
`--active-stems role,...`. The comma-separated list must be nonempty, contain
unique names, and be a subset of `rhythm,bass,harmony,happenings,lead`; malformed
input exits with usage status 64. `--active-stems` without a stems directory is
also rejected. The validated set is passed directly to
`DayObjectsMixQualityAnalyzer`, so an intentionally active silent stem still
fails audibility while an exported inactive silent bus does not.

Task 7 must call `analyze(fullMix:stems:activeRoles:tailBoundaryFrames:)` with
the roles actually scheduled for that render, even though its pack writes all
five stem files. For every active role eligible for tail analysis, it must pass
the first frame after that role's last intended event (before the rendered
effect decay). A boundary must be strictly inside the shared stem frame range
and belong to an active role. Task 7 must omit a role when it cannot provide a
trustworthy boundary; omission intentionally skips tail classification for that
role. The default parameters preserve source compatibility for legacy callers:
omitted `activeRoles` still means `stems.keys`, and omitted boundaries mean no
tail gate.

### Revised deterministic algorithms

- Transient density uses the maximum absolute channel sample to feed a 5 ms
  moving mean-absolute envelope. An onset is a below-to-above crossing where
  that short envelope exceeds a 50 ms exponential slow envelope by
  `max(0.02 full scale, 0.25 × full-mix RMS)`. A 40 ms refractory period bounds
  repeat detections. The existing `> 12 onsets/second` issue gate is unchanged.
- Harmony/lead and happenings/lead masking use aligned 4,096-frame Hann FFT
  windows with 50% hop. A window contributes only when the mix and both stems
  exceed `-80 dBFS` RMS and each stem's `160..<4,000 Hz` energy is above
  `-42 dB` relative to the mix in that window. Per-window cosine overlap is
  weighted by `min(lhs mid energy, rhs mid energy) / mix mid energy`, clamped to
  `0...1`; the weighted mean retains the `> 0.75` issue gate. Non-overlapping
  windows do not contribute.
- Tail analysis is per role, never full-mix-derived. For a caller-supplied
  boundary, it compares mean-square energy for up to two seconds after the
  boundary with an equally sized reference immediately before it in the same
  stem. The ratio is finite and clamped to `0...120`; `> 0.2` reports excessive
  persistence. `reverbTailEnergyRatioByRole` contains only evidenced roles,
  while the backward-compatible scalar is their maximum or zero. Suggestions
  are emitted only for evidenced roles over the gate and remain bounded,
  deterministic report data that is never applied live.

### Fix-round RED evidence

Analyzer RED command:

```text
xcodebuild test -quiet -project Steps4.xcodeproj -scheme Steps4 \
  -destination 'platform=iOS Simulator,name=iPhone 16e' \
  -only-testing:Steps4Tests/DayObjectsMixQualityAnalyzerTests
```

Result: expected compile failure on the missing `tailBoundaryFrames`,
`invalidTailBoundary`, and `reverbTailEnergyRatioByRole` API; 0 tests executed.
The added fixtures cover 5 ms attack/15 ms decay bursts at 20 per second,
steady tone/noise-floor negative controls, simultaneous and separated-in-time
masking, a spectrally subaudible overlap, dry harmony followed by late dry bass,
an exponential post-boundary tail, and invalid boundary metadata.

The CLI RED matrix ran missing, duplicate, unknown, and empty `--active-stems`
cases through the executable and grepped for the required usage diagnostics.
All four grep commands exited 1/no match against the prior parser.

An additional masking RED ran only
`testSubAudibleStemDoesNotFlagContemporaneousMasking`: 0 passed, 1 failed. The
full-band window gate scored the fixture `0.04135880573906027`; after switching
audibility and weights to mid-band energy it scored `0.004338612768865985`,
below the independently chosen `0.01` negative-control ceiling.

### Fix-round GREEN and final verification

Final command:

```text
xcodebuild test -quiet -project Steps4.xcodeproj -scheme Steps4 \
  -destination 'platform=iOS Simulator,name=iPhone 16e' \
  -resultBundlePath /tmp/day-objects-task6-fix2-verify.nYuyOA/Task6Fix2.xcresult \
  -only-testing:Steps4Tests/DayObjectsMixQualityAnalyzerTests \
  -only-testing:Steps4Tests/DayObjectsLoudnessAnalyzerTests \
  -only-testing:Steps4Tests/DayObjectsMixScenarioTests
```

Result bundle summary: 42 selected tests, 39 passed, 3 intentional opt-in
long-render skips, 0 failed. The analyzer and loudness suites passed 29/29
(20 mix-quality plus 9 loudness); the scenario suite supplied the remaining 13
selected tests.

Ten CLI behavior checks passed: the five active-stem validation paths, a valid
subset reaching stem loading, stems-plus-directory rejection, stem-as-mix
rejection, multiple-input rejection, and help output. The five malformed usage
cases were also run without a pipe and each returned status 64. No runtime audio
application, ledger entry, or WAV file was changed.

## Fix round 3

This section supersedes the fix-round-2 transient and masking algorithms; all
other thresholds and contracts remain unchanged.

### Carrier-independent onset novelty

Transient density now uses a deterministic high-frequency-content frame-energy
novelty measure instead of rectified waveform amplitude. For each channel, the
analyzer takes the first sample difference, measures its Hann-weighted RMS in a
10 ms frame every 5 ms, and compares that value with a 50 ms exponential
baseline. A candidate requires differenced energy `>= 0.01 full scale` and a
positive rise over the baseline `>= 0.005 full scale`; candidates retain the
40 ms refractory period. Reported density remains count divided by render
duration, with the existing `> 12/second` issue gate. This removes carrier-cycle
ripple without weakening the 5 ms attack/15 ms decay burst fixture.

### Sample-time masking support and level-sensitive severity

The 4,096-frame, 50%-hop FFT still supplies `160..<4,000 Hz` spectral shape and
relative-energy weights. Before any window's cosine similarity can contribute,
the analyzer now intersects audible support at sample time. At each sample it
uses maximum channel magnitude and requires the mix and both stems to exceed
`-80 dBFS`, with each stem also above `-42 dB` relative to the mix. A window's
similarity is multiplied by the fraction of samples with simultaneous support.
Adjacent tones that merely coexist inside a long FFT window therefore add zero
masking evidence.

For supported samples, the analyzer computes the weaker-to-stronger RMS level
ratio `sqrt(min energy / max energy)`. The window contribution is now:

```text
cosine spectral overlap
  × simultaneous-support fraction
  × weaker-to-stronger level ratio
  × min(lhs mid energy, rhs mid energy) / mix mid energy
```

The weighted report score remains finite and clamped to `0...1`; its existing
`> 0.75` issue gate is unchanged. Because masking suggestion severity derives
from that score, the contemporaneous level ratio is not normalized away.
Equal-level simultaneous 1 kHz stems remain a strong issue, while `-20 dB` and
`-40 dB` stems receive materially smaller scores and no masking correction.
Harmony/lead and happenings/lead use the same path.

### Fix-round RED evidence

Command:

```text
xcodebuild test -quiet -project Steps4.xcodeproj -scheme Steps4 \
  -destination 'platform=iOS Simulator,name=iPhone 16e' \
  -resultBundlePath /tmp/day-objects-task6-fix3-red.NKHxRu/Task6Fix3RED.xcresult \
  -only-testing:Steps4Tests/DayObjectsMixQualityAnalyzerTests/testTransientDensityDoesNotFlagSteadyCarriers \
  -only-testing:Steps4Tests/DayObjectsMixQualityAnalyzerTests/testAdjacentIdenticalFrequenciesDoNotMaskAcrossFFTWindow \
  -only-testing:Steps4Tests/DayObjectsMixQualityAnalyzerTests/testMaskingScorePreservesWeakerStemLevelRatio
```

Result: 3 selected, 0 passed, 3 failed for the expected behaviors. The 20 Hz,
0.2-amplitude steady sine reported `20.0` onsets/second. Adjacent, sample-disjoint
1 kHz roles with a 0 ms gap reported harmony/lead masking
`0.896863024566152`; the 20 ms case still reported `0.9958626594414589`.
The `-20 dB` weaker role reported `1.0`, and the `-40 dB` case remained
approximately `1.0`, proving the prior weighted mean normalized level away.

The final controls sweep steady `0.2`-amplitude carriers at 20, 30, 40, 50,
60, 250, 1,000, and 5,000 Hz; each must remain at no more than one startup onset
per second and never flag excessive density. The original 20-per-second,
5 ms attack/15 ms decay 1 kHz burst fixture remains at `20 ± 0.5` and flagged.
Masking controls cover exact zero sample overlap with 0, 10, and 20 ms gaps,
plus simultaneous equal, `-20 dB`, and `-40 dB` levels for both role pairs.

### Fix-round GREEN and final verification

Final command:

```text
xcodebuild test -quiet -project Steps4.xcodeproj -scheme Steps4 \
  -destination 'platform=iOS Simulator,name=iPhone 16e' \
  -resultBundlePath /tmp/day-objects-task6-fix3-final.Suro9S/Task6Fix3.xcresult \
  -only-testing:Steps4Tests/DayObjectsMixQualityAnalyzerTests \
  -only-testing:Steps4Tests/DayObjectsLoudnessAnalyzerTests \
  -only-testing:Steps4Tests/DayObjectsMixScenarioTests
```

Result bundle summary: 45 selected tests, 42 passed, 3 intentional opt-in
long-render skips, 0 failed. The analyzer and loudness suites passed 32/32
(23 mix-quality plus 9 loudness); the scenario suite supplied the remaining 13
selected tests. The existing ten CLI validation/behavior checks also passed.
No runtime audio application, ledger entry, or WAV file was changed.

## Fix round 4

This section supersedes the fix-round-3 onset algorithm only. Masking,
active-role CLI metadata, tail-boundary analysis, public report fields, issue
gates, and suggestion semantics are unchanged.

### Root cause and adaptive detector

The first-difference energy used in fix round 3 scales with carrier frequency.
Consequently the fixed `0.01` energy floor suppressed otherwise identical
100/250 Hz attacks while passing 1 kHz attacks. The second fixed novelty floor
also had no estimate of local variance, so random frame-to-frame fluctuation in
audible stationary noise repeatedly crossed it.

Transient density now measures frequency-neutral, full-band RMS in a 10 ms
window every 5 ms. Each frame is compared with the preceding, bounded 50 ms
history. Its baseline is the history median and its local variation is the
median absolute deviation. A candidate must exceed `0.01 FS` and rise over the
baseline by the largest of `0.005 FS`, 50% of the baseline, or three local
deviations. The existing 40 ms refractory period remains. This makes steady
tones and stationary texture establish their own deterministic threshold,
while the silence-to-attack transition of a pitched burst remains visible at
every tested pitch.

The history is capped at ten scalar frames. Runtime is linear in input frames,
channels, and the fixed 10 ms measurement window; robust-statistic work sorts
at most ten values. No additional buffer proportional to render length is
allocated.

### RED evidence

Command:

```text
xcodebuild test -quiet -project Steps4.xcodeproj -scheme Steps4 \
  -destination 'platform=iOS Simulator,name=iPhone 16e' \
  -resultBundlePath /tmp/day-objects-task6-fix4-red.qXQJ3L/Task6Fix4RED.xcresult \
  -only-testing:Steps4Tests/DayObjectsMixQualityAnalyzerTests/testEnvelopeTransientDensityFlagsRealisticToneBurstsAcrossPitch \
  -only-testing:Steps4Tests/DayObjectsMixQualityAnalyzerTests/testTransientDensityDoesNotFlagAudibleStationaryNoise
```

Result: 2 selected, 0 passed, 2 failed for the intended regressions. The
0.5-amplitude 5 ms attack/15 ms decay fixtures reported `0.0` rather than
`20.0` onsets/second at both 100 and 250 Hz. Seeded stationary noise reported
13...17 onsets/second across three seeds and amplitudes 0.15/0.20.

### GREEN and regression verification

The first focused GREEN passed four tests covering pitched bursts at
100/250/400/600/1,000 Hz, steady carriers at
20/30/40/50/60/100/250/400/600/1,000/5,000 Hz, the existing low-level noise
floor, and three seeds of audible stationary noise at amplitudes 0.15 and 0.20.
An additional range check added and passed 5,000 Hz burst coverage.

Final command:

```text
xcodebuild test -quiet -project Steps4.xcodeproj -scheme Steps4 \
  -destination 'platform=iOS Simulator,name=iPhone 16e' \
  -resultBundlePath /tmp/day-objects-task6-fix4-final.lXupcF/Task6Fix4.xcresult \
  -only-testing:Steps4Tests/DayObjectsMixQualityAnalyzerTests \
  -only-testing:Steps4Tests/DayObjectsLoudnessAnalyzerTests \
  -only-testing:Steps4Tests/DayObjectsMixScenarioTests
```

Result bundle summary: 46 selected, 43 passed, 3 intentional opt-in
long-render skips, 0 failed. CLI bootstrap/help compilation passed; eight
negative parser/input regression paths passed; and a valid
`--stems-directory` plus `--active-stems harmony,lead` invocation produced a
schema-4 report containing `transientDensityPerSecond` (exit 2 only because the
unmastered system sound used as the fixture did not meet the mix gates).
`git diff --check` also passed.

### Self-review

- The public analyzer/report API and the `> 12 onsets/second` issue gate are
  unchanged.
- The threshold is adaptive to both steady pitched energy and stochastic local
  variance, but retains an absolute audibility floor for silence/low noise.
- Test expectations are literal and exercise the real analyzer; no production
  helper computes expected densities.
- The masking and tail code paths were not edited and their full selected suites
  passed.
- Only the analyzer, its regression tests, and this report changed. The two
  pre-existing untracked audition WAVs were not read, modified, or staged.
