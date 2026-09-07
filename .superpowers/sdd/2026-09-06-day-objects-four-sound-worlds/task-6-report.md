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
