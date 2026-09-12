# Native atlas primary-canvas implementation

> Use superpowers:executing-plans inline. No subagents. Preserve the existing integration worktree and unrelated changes.

**Goal:** Port the approved atlas into new primary daily canvases, preserving event identity and historical rendering.
**Architecture:** Optional persisted recipe in DayCanvas; propagated through Editorial input; shared Metal path for display and export. Historical inputs stay on the current renderer.
**Tech stack:** Swift, Codable, Metal, XCTest; no dependencies.
**Spec:** `docs/superpowers/specs/2026-09-09-atlas-primary-canvas-design.md`.

## Constraints

- Do not migrate existing saved canvases, including today, without explicit selection.
- Recipe-enabled rendering must not drop insertion, removal, sound response, backdrop capture or palette presentation.
- Keep ten-actor capacity and event IDs; no arbitrary generated events.
- Unknown recipe versions are retained and never regenerated.
- No remote data mutations or website deployment.

## Tasks

- [x] Persist recipe: optional `DayCanvas.artworkRecipe` with frozen native geometry/material uniforms and event IDs; Codable compatibility, determinism and material-policy tests added.
- [x] Plan scene: versioned trajectory/size/palette/interaction/trace selection; reconciliation preserves existing actors, uses free slots, and caps descriptors at ten actual event IDs.
- [x] Propagate: recipe passes through Editorial input and normalization; native adapter preserves event IDs and opacity/sound envelopes. Historical inputs remain on the previous route. Recipe-enabled palette previews now use the same native contour/material as their prospective canvas element.
- [x] Render: shared native Metal shader with actor compositing, overlap coverage and selected static trace; bounded linear targets and sRGB output; screen/export use `encodeFrame`.
- [x] Integrate creation and editing: new-canvas-only activation, existing editor effect controls and locks, color variants, spent-color intensity, and Remix without event mutation. Existing saved canvases are not migrated.
- [ ] Verify: focused XCTest suites, Metal compile/render probes, iOS build, source/export parity, historical fixtures and interaction metadata. Keep activation disabled until the shared native rendering path is verified.

## Verification commands

Use `xcrun simctl list devices booted` to select an available device, then `xcodebuild test -project Steps4.xcodeproj -scheme Steps4 -destination 'platform=iOS Simulator,id=<selected ID>' -only-testing:Steps4Tests/NativeAtlasRecipeTests -only-testing:Steps4Tests/EditorialCanvasInputFactoryTests -only-testing:Steps4Tests/CanvasPersistenceRegressionTests`. Capture results in a task-specific temporary derived-data path. A passing data-model test is not evidence that graphics or integration are complete.

## Verification record — 2026-09-09

### Approved calm-picker / contrast / chrome refinement

- Added regression tests first: neutral available circles, visible distinct palette colors and dark energy backing over white all failed before implementation (`14-18-05`). A rendered endpoint test then caught pastel averaging (`14-24-54`); the atlas-only field branch preserves swatches with broad plateaus and soft transitions. Historical weighted-mesh rendering remains unchanged.
- Final focused run `Test-Steps4-2026.09.09_14-29-20-+0200.xcresult`: **38 passed, 0 failed**, including background endpoints in actual Metal pixels, shared grain finish, neutral/selected/added picker states, persistence and background behavior. The stronger background initially tinted added objects through opacity; neutralizing only their covered pixels fixed that regression without changing canvas compositing.
- Native UI flow with light/dark appearance passed on iPhone (`14-26-45`) and iPad compatibility mode (`14-23-14`). Confirmation screenshots in `/tmp/nowhere-calm-chrome-confirm` and initial iPad screenshots in `/tmp/nowhere-calm-ipad-review`. The last subsequent change affects added-state desaturation only; covered by the final native render tests. No broad historical visual-suite run or performance certification claimed.
- Signed Debug device build passed; updated iPhone Costa in place at 14:31, bundle `personal-project.StepsTrader`, without uninstall/reset. Physical visual assessment remains for the user.

### Follow-up: restore original canvas presentation

- Regressions reproduced with four new native render/generator tests before fixes. Dense inner contour fill is excluded and old native descriptors use a simple contour at rendering time. Original mesh gradient and shared final grain restored. Picker circle/reveal/neutral-added transitions restored.
- Focused final run `Test-Steps4-2026.09.09_13-47-49-+0200.xcresult`: **34 passed, 0 failed**, covering native recipes, picker frames, background behavior and the original post-process grain/defocus test. Render attachments exported to `/tmp/native-atlas-restoration-final`; picker stages inspected visually.
- Signed Debug device build succeeded; installed in place on iPhone Costa at 13:49 (bundle `personal-project.StepsTrader`), without uninstalling or resetting app data. Physical touch/visual QA remains for device review.

### Initial port verification (before follow-up fixes)

- Release simulator build succeeded (exit 0) after the final code changes; no signing or distribution performed.
- Final focused run `Test-Steps4-2026.09.09_12-24-54-+0200.xcresult`: **58 passed, 0 failed** after the final code changes. This covers NativeAtlasRecipe, EditorialCanvasInputFactory, CanvasPersistenceRegression, TodayCanvasBackground, MetalShapeGenomeFrame and HappeningPaletteRenderFrame suites. Release readiness remains open because of the seven broader visual failures and physical-device validation.
- The new storage activation and clarity/color tests were first observed failing, then passed after integration. The recipe lock and native picker tests also caught missing behavior before their fixes.
- `Test-Steps4-2026.09.09_12-15-07-+0200.xcresult`: 56 focused tests passed, zero failures.
- `Test-Steps4-2026.09.09_12-16-55-+0200.xcresult`: broader run, 165 passed / 7 failed. All native-recipe tests passed, including all five trace types at zero/full strength, native picker, sound response and deterministic rendering.
- The seven failures are in `DayObjectRenderFrameTests`: `testActorShaderRendersOnlyCircleDerivedOrbFamilies`, `testAllHTMLCircleRecipesHaveDistinctApprovedResponses`, `testCenterOpacityAndLocalAndSharedSoftnessChangeRenderedOrbs`, `testCommittedLabPerceptualSignaturesCoverTransferCompositionAndPalette`, `testInsertionAndRemovalTriptychsMatchCommittedPerceptualSignatures`, `testOutlineRecipeRendersContoursInsteadOfAFilledDisc`, `testShiftedRadialFocusMovesTheRenderedHighlight`. They exercise the prior render path; do not silently loosen visual thresholds or rewrite historical artwork to make them pass. No clean pre-change baseline was run, so do not claim experimentally proven pre-existing failures.
- Native image attachment exported and visually inspected at `/tmp/native-atlas-review/302F8AF8-EB01-4EA5-9811-F7B84127B240.png`.
- Derived data/results: `/tmp/nowhere-native-atlas-dd`. Physical-device performance, editor touch QA and release distribution are not validated. The integration remains local, with no commit, website deployment or physical-device installation.
