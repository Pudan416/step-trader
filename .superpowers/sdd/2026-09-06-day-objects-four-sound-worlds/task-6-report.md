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
