# Playback Task 10 report

## Scope and honesty boundary

Task 10 verified simulator behavior, deterministic allocation/lifecycle gates,
and the Release compile boundary. It created the physical listening matrix but
did not install to, run on, or listen through a physical iPhone. Physical audio,
CPU, memory, thermal and Metal frame-pacing acceptance remain pending.

No product source changed. The only Swift changes are narrow automated stress
tests in the existing engine/controller test files.

## Baseline complete suites

Run serially on iPhone 17 Pro simulator:

1. Exact final Task 10 playback command: PASS, 152/152, zero failures,
   selected suite 122.576 s. Log:
   `/tmp/day-objects-task10-final-playback.log`; summary:
   `/tmp/day-objects-task10-final-playback-summary.json`.
2. Exact final Task 10 UI command: PASS, 6/6, zero failures, selected suite
   104.203 s. Log: `/tmp/day-objects-task10-final-ui.log`; summary:
   `/tmp/day-objects-task10-final-ui-summary.json`.

The playback run emitted repeated AudioKit simulator diagnostics
(`kAudioUnitErr_InvalidParameter` and mono-to-stereo copy messages). They were
recorded as simulator observations, not interpreted as physical listening
evidence.

## Load coverage audit and added gates

Existing deterministic tests already covered:

- 100 Remixes with constant banks/pools/nodes/tasks/transport and no residual
  Lead/Happening tokens;
- 1,000 Lead updates with one voice and one amplitude attack;
- Grid and VoiceOver held-Lead cancellation;
- ten-Happening birth/recurrence density in a fixed six-voice pool;
- 1,000 harmony changes, 10,000 rhythm subdivisions and 10,000 transport bars.

Explicit coverage was absent for 25 Sound cycles, repeated background and
interruption convergence, and repeated Happenings 0↔10. Three narrowly scoped
tests were added. Their focused first run passed 3/3, so no production defect or
product code change was required; the final exact suite then passed 152/152.
Focused xcresult:
`Test-Steps4-2026.09.01_14-40-18-+0200.xcresult`; log:
`/tmp/day-objects-task10-stress-red-or-green.log`.

The existing Grid/VoiceOver cancellation tests were also run directly: PASS,
2/2, zero failures. Log:
`/tmp/day-objects-task10-lead-cancellation.log`; summary:
`/tmp/day-objects-task10-lead-cancellation-summary.json`.

## Release boundary

A fresh DerivedData directory was created with `mktemp -d` and used for:

```text
xcodebuild build -project Steps4.xcodeproj -scheme Steps4 \
  -configuration Release -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath /tmp/day-objects-task10-release.NjSZvy \
  CODE_SIGNING_ALLOWED=NO
```

Result: `BUILD SUCCEEDED`. Log: `/tmp/day-objects-task10-release.log`.

The built universal simulator binary was audited with `nm` and `strings`; no
playback engine/runtime/controller/player/scheduler symbols or Sound/Lead
runtime strings were found. Source scans found no playback-type reference in
production Canvas, Models, Stores or Services. Release keeps the experimental
feature false and the lab fallback inert.

## Artifacts

- `docs/day-objects-generative-playback-listening-checklist.md`: exact Steps,
  Sleep, Happenings, Glitch and four-Remix matrix; every speaker/headphone field
  is PENDING/UNTESTED.
- `docs/day-objects-generative-playback-performance.md`: observed simulator,
  build and deterministic stress evidence, separated from pending physical
  measurements.
- Playback design spec: verified automated outcomes and open physical gate only.

Unrelated dirty instrument-bank documentation was preserved and excluded.
No merge, push, publish, install or physical-listening claim was made.
