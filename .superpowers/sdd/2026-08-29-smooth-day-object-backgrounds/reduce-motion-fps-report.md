# Day Objects Reduce Motion mesh freeze and 30 FPS report

Date: 2026-08-30
Worktree: `codex/current-integration`

## Scope

- Freeze only the mesh-gradient elapsed time when the scene has Reduce Motion
  enabled.
- Keep the renderer clock and active `MTKView` cadence intact, preserving the
  existing opacity-only insertion/removal transitions.
- Lower the live Day Objects `MTKView` requested cadence from 60 to 30 FPS.
- Do not change render-target resolution, render passes, blur, Metal shader
  ABI/formulas, or any other application animation cadence.

## Root cause and change

`DayObjectsRenderer.draw(in:)` creates `DayObjectsMeshGradientUniforms` through
its scene initializer. That initializer previously forwarded the live elapsed
clock even for a scene with `input.reduceMotion == true`. It now resolves only
the mesh input time to zero in that case; the renderer's clock and view remain
active, so opacity-only transition envelopes still receive frames.

`DayObjectsMetalView.configureAnimationFrameRate(_:)` now configures the real
Day Objects `MTKView` to request 30 FPS.

## TDD evidence

### RED

Added these behavioral tests before production changes:

- `DayObjectPaletteTests.testMeshGradientReduceMotionFreezesUniformsAndGPUOutputWhileStandardMotionAdvances`
  creates the production scene-based mesh uniforms at elapsed times 5 and 95,
  renders both through the production Metal mesh shader, and asserts:
  - Reduce Motion uniforms and readback pixels are equal;
  - normal-motion uniforms differ and GPU RGB difference exceeds `0.01`.
- `DayObjectRenderFrameTests.testLiveDayObjectsMetalViewTargetsThirtyFramesPerSecond`
  applies the real Day Objects configuration to an `MTKView` and observes its
  configured preferred FPS.

Command:

```sh
xcodebuild test -project Steps4.xcodeproj -scheme Steps4 -configuration Debug \
  -destination 'platform=iOS Simulator,name=iPhone 17,OS=latest' \
  -only-testing:Steps4Tests/DayObjectPaletteTests/testMeshGradientReduceMotionFreezesUniformsAndGPUOutputWhileStandardMotionAdvances \
  -only-testing:Steps4Tests/DayObjectRenderFrameTests/testLiveDayObjectsMetalViewTargetsThirtyFramesPerSecond \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO
```

Result: **RED** — 2 tests executed with 3 expected assertion failures. The
frozen mesh uniforms/pixels differed across elapsed times, and the real view
reported 60 rather than 30 FPS.

### GREEN

Implemented the two minimal production changes, then re-ran the same focused
command.

Result: **GREEN** — 2 passed, 0 failed. The Reduce Motion mesh readback is
identical at both elapsed times; normal motion still changes; the configured
view reports 30 FPS.

## Verification

All commands used iPhone 17, iOS Simulator, Debug configuration.

```sh
xcodebuild test -project Steps4.xcodeproj -scheme Steps4 -configuration Debug \
  -destination 'platform=iOS Simulator,name=iPhone 17,OS=latest' \
  -only-testing:Steps4Tests/DayObjectRenderFrameTests \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO
```

Result: **79 passed, 0 failed**. Both perceptual signature tests passed in the
full render-frame suite; no golden change or export was needed.

```sh
xcodebuild -quiet test -project Steps4.xcodeproj -scheme Steps4 -configuration Debug \
  -destination 'platform=iOS Simulator,name=iPhone 17,OS=latest' \
  -only-testing:Steps4Tests/DayObjectPaletteTests \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO
```

Result: **46 passed, 0 failed**.

```sh
xcodebuild -quiet test -project Steps4.xcodeproj -scheme Steps4 -configuration Debug \
  -destination 'platform=iOS Simulator,name=iPhone 17,OS=latest' \
  -only-testing:Steps4Tests/DayObjectRenderFrameTests/testCommittedPerceptualSignaturesCoverProductionTransferCompositionAndPalette \
  -only-testing:Steps4Tests/DayObjectRenderFrameTests/testInsertionAndRemovalTriptychsMatchCommittedPerceptualSignatures \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO
```

Result: **2 passed, 0 failed**.

```sh
xcodebuild -quiet build -project Steps4.xcodeproj -scheme Steps4 -configuration Debug \
  -destination 'platform=iOS Simulator,name=iPhone 17,OS=latest' \
  CODE_SIGNING_ALLOWED=NO
```

Result: **exit 0**.

Final review: `git diff --check` passed. `StepsTrader/Localizable.xcstrings`
was pre-existing unrelated work and remains untouched and unstaged.
