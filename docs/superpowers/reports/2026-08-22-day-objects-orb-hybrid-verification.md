# Day Objects Orb Hybrid — Verification Report

Date: 2026-08-22
Branch: `codex/day-objects-clean`

## Outcome

Day Objects now renders one large radial-gradient orb per happening. The four daily actor variants are sphere, ellipse, lens, and soft blob; the previous small Figma-like families are no longer part of this renderer. Orbs use deterministic daily presets, overlap and visually merge, move along the shared seeded choreography, and keep the animated daily mesh background. Procedural grain is fixed at the approved textured strength of `0.05`.

The lab copy and accessibility assertions now describe and verify the one-event/one-orb model. Perceptual baselines were intentionally regenerated after inspecting the new GPU output.

## TDD evidence

RED was captured before each production change:

- `/tmp/orb-task4-red.log`: the new explicit shape ABI was absent.
- `/tmp/orb-task5-perceptual-red.log`: the former actor perceptual and transition signatures no longer matched the orb renderer.
- `/tmp/orb-task5-ui-green.log`: the old UI expectation encoded the previous multiple-figures-per-event behavior.
- `/tmp/orb-final-scoped.log`: stale sixteen-actor and flock-size assumptions failed against the approved one-event/one-orb semantics.

GREEN evidence:

- `/tmp/orb-task4-green-focused.log`: focused orb GPU tests, 5/5 passed.
- `/tmp/orb-task4-choreography-final.log`: complete choreography suite, 16/16 passed.
- `/tmp/orb-task5-perceptual-green.log`: perceptual/drawable gates, 2/2 passed.
- `/tmp/orb-task5-ui-final.log`: Day Objects lab UI test, 1/1 passed.
- `/tmp/orb-task5-stale-tests-green.log`: updated capacity and lab-fixture tests, 2/2 passed.

## Final verification

- Exact Day Objects scope: 87 unit tests passed, then the Day Objects UI test passed; 0 failures. Log: `/tmp/orb-final-scoped-green.log`.
- Full project suite: 704 unit tests passed with 1 existing expected skip; all 18 UI tests passed; 0 failures. Log: `/tmp/orb-final-full-suite.log`.
- Simulator app build: `BUILD SUCCEEDED`. Product: `/Users/kosta/Library/Developer/Xcode/DerivedData/Steps4-bzqaokhxtjeeacdjrzkxsxdgggom/Build/Products/Debug-iphonesimulator/Nowhere.app`. Log: `/tmp/orb-final-simulator-build.log`.
- Localization catalog parses as JSON; `git diff --check` is clean.
- The old Day Objects Metal constants (`kShapeCapsule`, `kShapeDrop`, `kShapeSlab`, `kShapeDart`, `kShapeWedge`, `kShapeScallop`, `kShapeBurst`) and the reported `DayRaysShader` `kShapeSpike` warning are absent from the current Metal sources/build output.

The physical-device build could not start because `iPhone Costa` was unavailable to Xcode at verification time. `xcrun devicectl list devices` reported the iPhone 15 Pro as `unavailable`, and the Xcode destination list contained simulators only. This is an external connection/trust/lock state, not a compiler failure. Log: `/tmp/orb-final-device-build.log`.

## GPU and visual acceptance

The populated lab GPU fixture reported `sceneActors=8`, `frameActors=8`, actor coverage of 5,516 pixels, actor alpha energy of 4,118.33, minimum palette contrast of 3.40, and 6,805 strong post-process difference pixels.

Inspected captures:

- `/tmp/orb-ui-artifacts.RJZIx3/`: live single canvas and 3x5 grid.
- `/tmp/orb-gpu-artifacts.WEGax3/`: representative phone/tablet GPU captures.

The live canvas shows large, overlapping radial orbs; the 3x5 grid shows distinct daily palettes and orb variants. No legacy square/petal actors were visible. The mesh background, stable textured grain, negative space, control exclusion, and readable controls were preserved.

## Installation note

The implementation lives in the separate worktree `.worktrees/experiment-cleanup`, not in the root checkout that was previously open on `feat/canvas-ui-simplification`. Xcode must open `Steps4.xcodeproj` from that worktree and show branch `codex/day-objects-clean` before Run is used.
