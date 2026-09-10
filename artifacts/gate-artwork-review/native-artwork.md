# Shared happening artwork for Shield and PayGate

Replaces the independent CoreGraphics silhouette generator from commit 38a0bb94.

The 21 transparent PNGs in `Shared/GateArtworkImages` were exported at 768 × 768 with `MetalShapeGenomeRenderer.image`, using the same `MetalShapeGenomeCatalog`, `MetalShapeGenomeFrame.make` and shader contour/material functions used by the native happening atlas. Seven catalog presets × three colorways of the soft `sideLight` material. Each row gives every shape a different hue through the existing canvas `withColorVariant` function; it preserves the two-color relationship. The three-color procedural fill and radial material are no longer in the gate pool. IDs, render seed and color variants are defined in `GateArtwork`.

The snapshots are decorative, independent of a user's events or balance. Both the app and ShieldConfiguration bundle the same directory. Rendering downsamples to the requested size; the Screen Time extension does not initialize Metal or read personal canvas data. Random selection avoids an immediate repeat of the visible variant. The existing shield-to-PayGate seed handoff is preserved.

## Regenerate

1. Build the Debug app and launch with `-uiLab shapeGenomeExport -gateArtworkExport YES`.
2. Copy `Documents/GateArtwork` from that app's simulator data container into `Shared/GateArtworkImages`, replacing the images.
3. Run `Steps4Tests/GateArtworkTests`; these check catalog membership and material compatibility, all bundled images, app/extension image equality, transparency, selection and handoff behavior.
4. Rebuild the review sheet:

```sh
swiftc -parse-as-library Shared/GateArtwork.swift artifacts/gate-artwork-review/render-objects.swift -o /tmp/gate-review
/tmp/gate-review Shared/GateArtworkImages artifacts/gate-artwork-review/objects.png
```

The image pool is a curated set of exported happening objects, not an unbounded live generator. Regenerate when the shared contour or material implementation changes. Persisted variant order must remain stable to keep app/extension handoff deterministic.
