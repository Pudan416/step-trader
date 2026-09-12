# Day Objects Editorial Field — Metal Lab MVP

This handoff is the approved Editorial Field composition and material model
running through the app's existing instanced Metal renderer. It remains scoped
to Day Objects Lab; the main canvas and Gallery are unchanged.

## Review files

- `full-screen.png`: ten happenings in the full-screen Lab presentation.
- `calendar-tile.png`: the same stable scene identity in the square calendar presentation.
- `reduce-motion.png`: the full-screen neutral pose with the Lab Reduce Motion override enabled.
- `editorial-field-metal-motion-10s.mp4`: a 9.78-second, full-resolution Simulator recording. Motion is intentionally slow; depth layers use different amplitudes and phases.

## How to open it

In a debug build, open Settings → Appearance → Day Objects. The Lab offers
full-screen/tile presentation, light/dark/low-contrast backgrounds, low sleep,
Reduce Motion, and 0–10 happenings. For a direct debug launch, pass
`-uiLab dayObjects`.

## Validation

- SceneRecipeV1 and motion invariants: 5 targeted tests passed.
- Full-screen → calendar tile → Reduce Motion UI handoff: 1 UI test passed.
- Final iOS Simulator build: passed.
- The unchanged sandbox renderer retains its earlier `147/147` unit and `7/7`
  integration pass at `0632ac146c39c2ea0e45df68ab972e6eeb7ce7f5`; it was not rerun solely to regenerate evidence.

## Integrity

```text
69a8834ef1606771c55185be2f35735de46bfeaa1a64f32060306b9e05300815  full-screen.png
dc11872d7d1f22fa434b160322cfb0c534e51a3abd1ea3cc3469389978c57368  calendar-tile.png
7e0712a9f12320484c131098338d223eb6edd966e8ff26921dee15f6dfc7ab8c  reduce-motion.png
406bce49fba78dc03219d3b70569b7ced74ef66f644200cb650399702bffe5bf  editorial-field-metal-motion-10s.mp4
```

Release-grade held-out coverage, repeated blind reviews, device performance,
perceptual goldens, and exhaustive state combinations remain in the documented
post-MVP hardening backlog.
