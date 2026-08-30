# Day Objects Editorial Field corpus

This Swift package owns the renderer-independent, reproducible visible seed
corpus for the Day Objects Editorial Field review process. It does not import
or modify production Day Objects or the main application canvas.

Generate the committed manifest from the immutable specification commit and
public nonce:

```bash
swift run --package-path Tools/DayObjectsEditorialField editorial-field-corpus visible --output Tools/DayObjectsEditorialField/Manifests/visible-v1.json
```

Verify that a manifest is byte-for-byte canonical and print its SHA-256 plus
fixture counts:

```bash
swift run --package-path Tools/DayObjectsEditorialField editorial-field-corpus verify --manifest Tools/DayObjectsEditorialField/Manifests/visible-v1.json
```

Run the core tests:

```bash
swift test --package-path Tools/DayObjectsEditorialField --filter CorpusManifestTests
```

Render a complete neutral composition evidence package into a new or empty
round directory:

```bash
swift run --package-path Tools/DayObjectsEditorialField editorial-field-render composition \
  --manifest Tools/DayObjectsEditorialField/Manifests/visible-v1.json \
  --output artifacts/day-objects-editorial-field/composition/<artist-round>
```

The default composition command renders the `393 x 852` point phone canvas at
`3x` (`1179 x 2556` pixels), derives a centered square calendar tile by cropping
that exact phone image, and emits all four separate debug overlay families:
`crop`, `overlap`, `centerOfMass`, and `occupiedBounds`. For a clean neutral
package without overlays, append `--overlays none`; a subset can be requested
as a comma-separated list. Overlay selection never changes the core render.

Every package contains the source corpus copy, `152` breadth/continuity core
PNG views, neutral breadth and continuity contact sheets, actor/geometry
`metrics.json`, a machine-readable `manifest.json`, `SHA256SUMS`, and
`package-hash.txt`. The output directory must be new or empty so an artist
cannot silently replace an existing round.

Verify every artifact and the package hash before handing the directory to a
critic:

```bash
swift run --package-path Tools/DayObjectsEditorialField editorial-field-render verify \
  --package artifacts/day-objects-editorial-field/composition/<artist-round>
```

Any changed, added, or removed package file makes verification fail. Record the
printed package SHA-256, source commit, exact render command, artifact path, and
known limitations when returning an artist round. Neutral evidence is only for
composition review; it contains no material color, motion, Metal, or production
renderer behavior.

`visible-v1` is a named semantic corpus contract, not a caller-supplied label.
Generation rejects any manifest whose canonical decoded content differs from
`CorpusManifest.visibleV1()`, including reordered or missing fixtures, changed
phases/stages/identities, a different nonce or specification commit, or an
incomplete stress suite. Verification repeats that contract check and also
cross-checks the evidence manifest, metrics, exact required render/overlay
paths, artifact records, and PNG dimensions after validating `SHA256SUMS`.
Recomputing checksums therefore cannot turn a truncated package into valid
`visible-v1` evidence. Future held-out corpora must add their own explicit
corpus kind and validator; unknown kinds fail closed.

The visible corpus fixes the specification commit
`8a8539a77ce704fcc688ebe8cb98d78e2a0f80dd`, nonce
`day-objects-editorial-field-visible-v1`, canonical actor identities,
condition tables, four capture phases, and SHA-256 seed derivation. The first
eight digest bytes are interpreted as one unsigned big-endian `UInt64`; any
collision is resolved by incrementing and recording the collision suffix.
