# Happenings viewport edge scaling — 2026-09-15

Feature build: `b001911659ff05b3005ee631030714664f76fdb3` on `codex/happenings-field`.

In All, circles retain their current size through the central region and smoothly shrink to 84% at the viewport edges. Horizontal and vertical distance use one bounded factor, so corners do not shrink twice. Panning restores the original size as a circle returns to the center. Shape radius and native label scale use the same layout; native scrolling still owns all positions. The existing stationary canvas and soft backdrop blur remain underneath.

The effect blends with the Frequent/All balloon transition, is absent in Frequent, and is disabled for Reduce Motion. Direct geometry observation updates the viewport on iOS 17 as well as newer OS versions. The renderer requests 60 fps during movement; this is not a measured device frame rate.

## Validation

- Three unit tests cover all edges/corners, continuity, restoration, unchanged world positions/bounds and composition with balloon appearance.
- UI regression verifies the same Read choice shrinks after a horizontal drag and restores its size and position on returning to All.
- Simulator screenshots: [centered](all-centered.png), [panned](all-panned.png).
- A first observer implementation did not deliver viewport updates. The UI regression caught it; direct `onGeometryChange` observation fixed it.
- App and four embedded extensions built together with dedicated DerivedData. Strict signatures, provisioning, 11 fonts, 21 shared gate images, 122 audio files, asset catalog and Metal library verified. The source mirror matches all 1164 tracked non-artifact files.

This is the explicitly requested isolated feature build. No integration push or PR publication was performed. Simulator checks are distinct from physical-device visual verification, which was not performed.

## Final results

- Final clean source revision: `b001911659ff05b3005ee631030714664f76fdb3`.
- 3 unit tests and 4 UI tests passed: edge scaling/restoration, Frequent/All round trip, large text/Health controls, stationary canvas pixels during panning.
- Result bundle: `/tmp/nowhere-happenings-staggered-dd/Logs/Test/Test-Steps4-2026.09.15_20-31-25-+0200.xcresult`. Screenshots above are from this final run.
- Wi-Fi installation on iPhone Costa succeeded. Normal application launch also succeeded at 20:33 Europe/Belgrade; no UI-test launch flags used. See `device-verification.json` for actual tool results.
