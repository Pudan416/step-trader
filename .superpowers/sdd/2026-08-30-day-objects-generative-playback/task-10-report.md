# Playback Task 10 report

## Scope and honesty boundary

Task 10 verified simulator behavior, deterministic allocation/lifecycle gates,
and the Release compile boundary. It created the physical listening matrix but
did not install to, run on, or listen through a physical iPhone. Physical audio,
CPU, memory, thermal and Metal frame-pacing acceptance remain pending.

The review follow-up added a narrow debug/internal live-runtime observation
snapshot and centralized the debug/internal controller Lead-availability policy
used by both view change sites. No Release-visible playback feature was added.

## Baseline complete suites

Run serially on iPhone 17 Pro simulator:

1. Pre-review exact Task 10 playback command: PASS, 152/152, zero failures,
   selected suite 122.576 s. The final post-review command is recorded below.
2. Pre-review exact Task 10 UI command: PASS, 6/6, zero failures, selected suite
   104.203 s. The final post-review command is recorded below.

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

## Review follow-up evidence

The original three stress additions used recording playback/runtime boundaries.
They remain useful for command routing and lifecycle convergence but are not
claimed as real allocation evidence.

Two additional tests now exercise `DayObjectsLivePlaybackRuntime`:

- 25 Sound-equivalent start/stop cycles use the actual AudioKit shared bank
  pair and actual transport behind `DayObjectsMusicPlaybackEngine`; only the
  system audio-session boundary is recorded. A real post-prepare allocation
  snapshot is the baseline for node/pool counts, shared-node identities,
  instrument fingerprints, and tonal/piano/drum player allocations. All cycles
  preserve it and every stop has zero tasks, transport, voices, Lead/Happening
  tokens, and scheduler records.
- ten Happenings 0↔10→0 loops use the running live runtime and real scheduler;
  all ten record IDs appear, removal returns records/tokens to zero, and the
  same real allocation snapshot remains fixed.

Two integrated `DayObjectsMusicLabController` tests begin a generative Lead and
then invoke Grid and VoiceOver through `leadAvailabilityChanged`, the same
policy method called by both `DayObjectsLabView` change sites. Repeated policy,
update, and release calls forward exactly one `endLead` and no disabled update.
The recording playback boundary proves controller behavior, not audible output.

The final focused follow-up result was PASS, 4/4, zero failures, 78.443 s
selected-test time. The two live-runtime tests took 78.361 s together; the
25-cycle test took 46.911 s. Xcresult:
`Test-Steps4-2026.09.01_15-21-34-+0200.xcresult`; log:
`/tmp/day-objects-task10-followup-focused-green.log`.

An intermediate strengthened assertion produced a reproducible RED: total
runtime `activeVoiceCount` was 9 after each Happening removal. Source tracing
showed that this aggregate intentionally includes the still-running harmony and
rhythm scene. The corrected invariant asserts zero Happening scheduler
records/tokens, stable aggregate ambient voices between removal cycles, and zero
aggregate voices after Sound stops. No product defect or product fix resulted.

Fresh serial final commands on iPhone 17 Pro simulator:

- exact playback selection: PASS, 156/156, zero failures, 198.240 s selected
  suite time; log `/tmp/day-objects-task10-followup-final-playback.log`;
  xcresult `Test-Steps4-2026.09.01_15-24-08-+0200.xcresult`;
- exact Day Objects Lab UI selection: PASS, 6/6, zero failures, 104.535 s
  selected suite time; log `/tmp/day-objects-task10-followup-ui.log`; xcresult
  `Test-Steps4-2026.09.01_15-11-06-+0200.xcresult`.

## Release boundary

A fresh post-review DerivedData directory was created with `mktemp -d` and
used for:

```text
xcodebuild build -project Steps4.xcodeproj -scheme Steps4 \
  -configuration Release -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath /tmp/day-objects-task10-followup-release.MAZIch \
  CODE_SIGNING_ALLOWED=NO
```

Result: `BUILD SUCCEEDED`. Log:
`/tmp/day-objects-task10-followup-release.log`.

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
