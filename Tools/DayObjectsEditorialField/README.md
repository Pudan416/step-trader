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

The visible corpus fixes the specification commit
`8a8539a77ce704fcc688ebe8cb98d78e2a0f80dd`, nonce
`day-objects-editorial-field-visible-v1`, canonical actor identities,
condition tables, four capture phases, and SHA-256 seed derivation. The first
eight digest bytes are interpreted as one unsigned big-endian `UInt64`; any
collision is resolved by incrementing and recording the collision suffix.
