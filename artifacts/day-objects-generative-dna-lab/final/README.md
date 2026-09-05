# Day Objects Generative DNA — Lab MVP handoff

This package was captured from the real instanced Metal renderer inside Day Objects Lab. It is not an HTML, Core Graphics, or Figma approximation.

## Source

- Runtime implementation: `85c6044`
- Capture instrumentation: `d670753`
- Branch: `codex/editorial-motion-render`
- Device: iPhone 17 Pro Simulator (`iPhone18,1`)
- Simulator runtime: iOS 26.3.1
- Device UUID: `A55C6AF8-3836-4E40-BA57-2C18A9DC81EF`
- App bundle: `personal-project.StepsTrader`

## Files

- `contact-sheet.png`: fifteen sequential generated days plus the review states below.
- `grid-15-days.png`: Lab offsets 1...15, corresponding to 2026-01-02...2026-01-16, with deterministic daily art directions.
- `full-screen.png`: 2026-01-01, ten happenings, normal sleep, normal motion, depth-field placement.
- `calendar-tile.png`: the same 2026-01-01 scene in calendar-tile presentation.
- `reduce-motion.png`: the same 2026-01-01 scene with Reduce Motion enabled. Actor identity, geometry, material, and placement are preserved while continuous drift and local phase animation stop.
- `light-low-sleep.png`: 2026-01-02, ten happenings, light background, low-sleep state.
- `motion.mp4`: ten seconds of the 2026-01-01 scene in normal motion at approximately 30 fps. Motion is whole-object drift with individual depth and parallax; there is no fast local rotation.

The fifteen-day grid covers the four carrier regions and the six material mechanisms through sequential deterministic dates. Each individual day stays deliberately coherent: one primary family, geometry region, and material, with no more than one compatible accent.

## Capture commands

Simulator build:

```bash
xcodebuild build -project Steps4.xcodeproj -scheme Steps4 \
  -destination 'platform=iOS Simulator,id=A55C6AF8-3836-4E40-BA57-2C18A9DC81EF'
```

Real-app stills:

```bash
xcodebuild test -project Steps4.xcodeproj -scheme Steps4 \
  -destination 'platform=iOS Simulator,id=A55C6AF8-3836-4E40-BA57-2C18A9DC81EF' \
  -only-testing:Steps4UITests/DayObjectsLabUITests/testEditorialFieldMVPVisualHandoff

xcodebuild test -project Steps4.xcodeproj -scheme Steps4 \
  -destination 'platform=iOS Simulator,id=A55C6AF8-3836-4E40-BA57-2C18A9DC81EF' \
  -only-testing:Steps4UITests/DayObjectsLabUITests/testLabExposesChoreographyControlsAndAddsEventsInPlace
```

Normal-motion recording:

```bash
xcrun simctl launch --terminate-running-process \
  A55C6AF8-3836-4E40-BA57-2C18A9DC81EF \
  personal-project.StepsTrader \
  -uiLab dayObjects -AppleLanguages '(en)' -AppleLocale en_US \
  -dayObjectsVisualHandoff

xcrun simctl io A55C6AF8-3836-4E40-BA57-2C18A9DC81EF \
  recordVideo --codec=h264 motion.mp4
```

The captured stream was trimmed losslessly to exactly ten seconds with `avconvert --preset PresetPassthrough`.

## Verification notes

- The Simulator build completed with `** BUILD SUCCEEDED **`.
- The complete `DayObjectSceneTests` target passed.
- The new scheduler, recipe coherence, stable identity, carrier ABI, Metal carrier/material behavior, gradient continuity, full-screen/tile, Reduce Motion, and Lab-control checks passed.
- Harmonic path materials are closed contours with no deliberately removed angular sector; the 72-angle Metal continuity regression passed.
- Both final capture UI tests passed: one in 43.011 seconds and one in 67.974 seconds.
- The complete targeted Day Objects command still reports three legacy perceptual-signature failures. The same three failures reproduce unchanged on baseline `5d7e1fee`; therefore no perceptual goldens were modified for this Lab MVP.
- The main application canvas and main Gallery were not changed.

## Deferred release hardening

The 24-fixture held-out corpus, repeated blind criticism, exhaustive state combinations, physical-device performance gate, sandbox/Metal blind certification, production Gallery integration, and perceptual-golden refresh remain outside this Lab MVP.
