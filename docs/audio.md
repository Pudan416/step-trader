# Canvas audio

## Ownership

Production source is under `StepsTrader/Experiments/DayObjects/Sound/`:

- `Domain/` — instrument IDs, sound recipes, catalog decoding and validation.
- `Director/` — deterministic plans derived from the day's inputs.
- `Engine/` — instrument pools, AudioKit graph and bank lifecycle.
- `Playback/` — scheduling, transport, startup/stop and transitions.
- `Lab/` — controls and state; `DayObjectsMusicLabController` also drives the real Canvas.
- `Diagnostics/` — offline rendering, audition export and mix analysis.
- `Resources/` — licensed samples, presets, catalogs and their manifest.

See [Canvas components](architecture/canvas-components.md) for graph ownership.
Naming a directory Lab or Experiments does not make its contents safe to delete.

## Resource contract

`audio-assets-manifest.json` records asset paths, hashes and provenance. The current
inventory includes 12 FeltPiano CAF files, 8 drum WAV files, 114 happening WAV files,
and the selected SynthOne presets. Sound-world definitions live in `SoundWorlds/`.
Files are chosen dynamically by recipes; keep their stable IDs and required licenses.

Use `Scripts/import_day_objects_audio_assets.sh` and the scripts under
`Scripts/day_objects_audio/` when regenerating resources. Read their arguments before
running them: importing/regenerating is an intentional asset change, not a build step.
[Mix analysis instructions](../Scripts/day_objects_audio/README.md) describe the CLI.

Asset transformations must update the manifest and relevant fixture expectations,
retain original provenance and prove equivalent decoded audio when described as lossless.
Do not trim samples, reduce precision or remove roots during repository housekeeping.

## Verification

For resource changes, run `DayObjectsAudioResourceTests`, `DayObjectsFeltPianoTests`,
`DayObjectsDrumBankTests`, `DayObjectsHappeningSamplePoolTests` and catalog tests.
For lifecycle changes, also run playback, transport, remix and bank tests.

The built bundle must pass `Scripts/check_canvas_audio_bundle.py`. Verify its
bundled license notices and catalogs as well as the actual audio files.

After changing playback or sample encoding, check on a physical iPhone:

- All four worlds and supported moods; soft and dense days; every instrument category.
- First play, repeated play/stop, rapid toggles and Remix while preparation is pending.
- Held lead gestures, release tails, bass/harmony transitions and happening attacks.
- Foreground/background, interruptions, output-route changes and resuming after a pause.
- No clipping, clicks, missing instruments, unexpected level jumps or stuck notes.
- Startup latency, memory and CPU under representative polyphony and longer playback.

Automated renders and simulator results do not prove this device listening matrix passed.
Store dated listening/profiling evidence in ignored `artifacts/`, not in this maintained guide.
