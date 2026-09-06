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
