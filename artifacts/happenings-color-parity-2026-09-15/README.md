# Saved happening color parity

Committed happenings without an editorial color variant were shown with native color variant 0 in the chooser, while the canvas retained the original frozen material. Variant 0 rotates hue; it is not an identity transform.

The assignment now retains a missing variant as nil. Native material resolution also accepts nil as the unchanged material, including the chooser label-contrast calculation. Explicit variants (including 0) and new uncommitted color rolls retain their behavior. Saved canvas data is not rewritten.

## Verification

The new regression reproduced the bug before the fix. It checks saved/restored native figures with nil, 0 and 37 across three chooser reroll values, comparing their resolved material with the actual canvas input.

64 focused tests passed: assignment state/cache, render input factory, palette frame generation and native rendering/persistence tests. The already documented baseline-failing background endpoint tolerance test was excluded; its unchanged baseline evidence is in the stationary-canvas artifact.

Result: `/tmp/nowhere-happenings-staggered-dd/Logs/Test/Test-Steps4-2026.09.15_09-47-41-+0200.xcresult`.

No current-integration publication. Device installation and physical-device visual verification are recorded separately.
