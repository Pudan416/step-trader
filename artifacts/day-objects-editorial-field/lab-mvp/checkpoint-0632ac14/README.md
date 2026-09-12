# Day Objects Editorial Field — Lab MVP visual checkpoint

This is a deliberately small visual checkpoint, not a release evidence package.

- Frozen material approval: `660f977789dce9fd71089c6fa46097ed35d5da34`
- Deterministic motion core: `8d1667288d8d213d8b8ea5c71a2b5df4ea11f064`
- Sandbox motion renderer: `0632ac146c39c2ea0e45df68ab972e6eeb7ce7f5`
- Composition source: approved visible recipe archive
- Material source: deterministic approved `MaterialDNA`

## Review files

- `contact-sheet.png`: 1, 3, 5, and 10 happenings across light, dark, and low-contrast backgrounds, with full-screen and calendar-tile views. The final card previews low sleep with a 6-point post-composite blur and a tile cropped from the blurred full canvas.
- `motion-10s.gif`: 40 real sandbox renders over 10 seconds (4 fps), normal steps, normal sleep, 10 happenings, low-contrast background.
- `reduce-motion.png`: independent renders at 0 and 10 seconds with Reduce Motion enabled. Their source PNG bytes are identical.

## Integrity

```text
051d720a6922c58cc068c9de4210a07e571fa7efa7733a3d1fdde70fa5d25cfd  contact-sheet.png
71e846ac41ccf8bb9a271c617746f85fae578054359651455dba053f6a946a1f  motion-10s.gif
0bf05afc4afc56dff7ebbbd5f6aa799a9d033b1520b32f673ee066c6d015e919  reduce-motion.png
```

The low-sleep treatment is a checkpoint preview of the intended whole-canvas blur. It is not yet committed into the sandbox motion renderer or the app. Metal integration, held-out coverage, release evidence, device performance, and perceptual goldens are intentionally deferred.
