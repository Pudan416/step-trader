# Gate artwork: soft color variants

Latest visual revision, superseding the three-material board in `gate-native-review-2026-09-10`.

All seven happening shapes now use the upper row's `sideLight` material. The radial and three-color procedural variants have been removed from the gate resource pool. Each shape has three different colorways; each row of the review board gives all seven forms different hues. Colors use the same `MetalShapeMaterialUniforms.withColorVariant` operation as the native Canvas, preserving the two-color relationship. Geometry and renderer remain shared with happenings.

`objects.png` arranges the actual bundled transparent Metal exports. It is a resource review board, not a screenshot of an app screen. Reproduction instructions: `artifacts/gate-artwork-review/native-artwork.md`.
