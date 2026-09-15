# Frequent / All happening chooser

The chooser opens with ten automatically selected happenings and a fixed bottom Frequent / All switch. All retains the centered, two-dimensional staggered field. The canvas stays stationary below the transparent field and labels share the circles’ scroll transform.

Health core choices (Slept well, Walk, Workout, Rested) are present from first opening. Detected workout choices are added to the catalog without logging a canvas event and prioritized in the ten; walking aliases are deduplicated. Health and today’s added slots are protected. Overflow remains in All. Remaining choices learn from existing usage with at most one promotion per day (at least three uses and a two-use lead), preserving slot positions and persisting across launches. The existing optional editor reflects the same ten choices.

Accessibility text uses a vertically scrollable single column. The Metal drawable is capped at 4096 pixels on the longest edge to avoid oversized-texture crashes in tall fields; SwiftUI labels retain native resolution. Normal screen-sized artwork retains native scale.

## Validation

- 60 distinct focused unit tests passed across selection, storage, field geometry, daily learning, Health aliasing/protection/overflow and drawable sizing.
- UI scenarios passed for default ten, switching to All and back, stable positions, preserved canvas selection, fixed Health editor slots, stationary canvas pixels, staggered All layout, optional creation/replacement/cancellation, and accessibility text.
- A large-text run initially exposed an oversized Metal drawable crash; the drawable limit fixed it and the scenario passed on rerun.
- Screenshots are simulator captures, not physical-device visual verification.
- Prior unrelated NativeAtlasRecipeTests.testNativeBackgroundShowsBothPaletteEndpointsInPixels failure is documented in ../happenings-stationary-canvas-2026-09-15/README.md; its threshold was not changed.

## Build scope

User-authorized isolated codex/happenings-field build. No integration publication. Device install evidence is recorded in device-verification.json after installation.
