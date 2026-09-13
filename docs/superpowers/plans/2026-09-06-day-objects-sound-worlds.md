# Day Objects Sound Worlds — implementation plan

## Goal

Make the Canvas music clearly vary in both timbre and musical behavior while
preserving the existing steps, sleep, happenings, glitch, and touch mappings.

## Phases

1. Add a deterministic two-world domain (`feltAndWood`, `metalAndCurrent`) and
   route it through the director, layer planners, plan diffing, and playback.
   Cover contrasting instrument palettes and behavior with tests first.
2. Give each happening a stable musical identity, a short motif/response role,
   and a fair shared event budget. All ten introductions must occur within the
   first minute without simultaneous overload.
3. Add twelve authored happening characters (31...42), checked-in WAV assets,
   pitch variants where useful, hashes, and explicit generated/source
   provenance. Keep IDs 1...30 compatible.
4. Add real Canvas controls for sound-world selection, Music Remix, and Music
   Undo. Visual Remix remains independent. Undo restores the previous seed and
   world and reschedules the actual mobile runtime.
5. Tune per-world processing/mix differences without adding a second mobile
   playback world. Render equal-input listening examples for both worlds.
6. Run focused tests, resource validation, app build, offline audio analysis,
   and full available test suite. Integrate with the latest PR head without
   overwriting parallel Happenings/UI work.

## Non-goals

- No full Synth One engine import.
- No release-gate change; audio remains DEBUG/INTERNAL_BUILD.
- No four-world catalog, DAW, microphone recording, or granular engine.
- No mapping from every visual shape/material property in this prototype.

## Progress (2026-09-06)

All six planned phases are implemented in `codex/day-objects-sound-worlds`.

- The deterministic `feltAndWood` and `metalAndCurrent` worlds are routed from
  the Canvas controls through music direction, playback, plan diffing, and
  per-world processing.
- Happenings have stable identities, fair scheduling, introductions within the
  first minute, and world-specific envelopes/effect sends used by the real
  sample pool.
- The authored bank contains 42 recipes and 114 checked-in WAV variants with
  source metadata and license records. IDs 1...30 remain compatible.
- Music world, Music Remix, and Music Undo controls are implemented without
  coupling them to the visual Remix action.
- Equal-input 24-second listening renders were exported to
  `artifacts/day-objects-sound-worlds/`. Master calibration preserves the
  internal layer balance and measures -17.03 LUFS / -3.28 dBTP for Felt & Wood
  and -16.55 LUFS / -2.79 dBTP for Metal & Current.
- Focused resource validation passed 19/19 tests; planner validation passed
  105/105 tests; the final bass/director/scheduler/sample-pool/mix validation
  passed 83/83 tests. A clean build-for-testing completed successfully.

Safety note: the earlier renderer failure came from passing a frame count to
`_tail_frames`, whose parameter was seconds. That could request roughly 1.94
billion list elements. `_pad_to_frames` now handles frame counts explicitly,
render length is rejected above 4.5 seconds before allocation, and regression
coverage includes both `reverse-bloom` and `modal-decay`. The full synthesis
suite passed 14/14 with 50,784 KB peak RSS. The final bank rebuild used 121,200
KB peak RSS. Two long aggregate Python checks reached the explicit 60-second
cap and were stopped without automatic retries; their recipes had already
passed the required sequential checks.
