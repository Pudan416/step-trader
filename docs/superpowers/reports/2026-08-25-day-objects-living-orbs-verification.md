# Day Objects Living Orbs — Verification Report

Date: 2026-08-25  
Branch: `codex/day-objects-living-orbs`  
Base implementation HEAD: `831c9b6b911583aceb6efda5c23b312c97f83aa6`

## Outcome

Day Objects now uses one stable living orb per unique happening, capped at ten. The old small Figma-like actors are replaced by large overlapping orbs with six procedural material families: satin, inner glow, rim glow, glass, membrane, and spectral. Each day deterministically chooses three distinct modern palettes: one for the animated mesh background and two for the objects. Individual orbs receive stable one-, two-, or three-colour subsets, depth, size, material, and route, so they remain recognisable while moving slowly across the usable canvas and interacting with one another.

Steps control the global motion energy, sleep controls scene focus, and happenings control the number of visible orbs. Reduce Motion freezes geometry, depth, and material animation without removing the composition. Procedural grain is applied after the sleep-driven blur at the fixed approved strength of `0.05`.

The debug/internal Day Objects lab exposes the completed renderer with a `0...10` happenings range, a default of eight, daily palette and material diagnostics, and the updated visual matrix.

## Final verification

- Exact Day Objects scope after final review fixes: 110 unit tests and 1 UI test passed, 0 failed, 0 skipped. Result: `/tmp/living-orbs-final-review.HkXSQK/Logs/Test/Test-Steps4-2026.08.25_06-22-23-+0200.xcresult`.
- Full project suite after all fixes: 730 unit cases executed with 0 failures and 1 pre-existing expected skip; all 18 UI tests passed. Result: `/tmp/living-orbs-final-review.HkXSQK/Logs/Test/Test-Steps4-2026.08.25_06-30-08-+0200.xcresult`.
- Exact Debug simulator build: `BUILD SUCCEEDED`. Log: `/tmp/living-orbs-final-review-build.log`.
- Simulator app product: `/tmp/living-orbs-final-review.HkXSQK/Build/Products/Debug-iphonesimulator/Nowhere.app`.
- `Scripts/verify-experiment-scope.sh`: `Day Objects is the only tracked experiment.`
- `plutil -lint Steps4.xcodeproj/project.pbxproj`: `OK`.
- `git diff --check`: clean.
- Day Objects no longer references the shared legacy `radialFillStyle`, `DayObjectRadialFillStyle`, or `DayObjectRadialPreset` API.
- The final build log contains no Day Objects compiler or Metal warnings.

## Final code-review fixes

The final whole-branch review found seven valid integration defects and each was reproduced before repair:

- arbitrary UUID-like event IDs could collide in palette slots, colour subsets, materials, route sectors, and travel direction;
- some palette colours were unreadable against the rendered background;
- soft-encounter metadata did not actually bring members to a shared overlap point;
- glass sampled the vertically mirrored background coordinate;
- the animated `MTKView` was capped at 30 FPS;
- centre opacity, material-local depth softness, and shared light softness were uploaded but did not affect pixels;
- depth softness was inverted, making near objects softer than distant ones.

The repaired allocation preserves exact 6/4 object-palette use, ten unique colour subsets, a 50–70% dominant-material share, multiple accent materials, at least five occupied sectors, and both travel directions for arbitrary IDs. Existing actors remain stable when another happening is removed or reordered. Five time-staggered pair channels now meet at their declared 15–40% overlap inside safe distributed lanes. The renderer samples glass in top-left screen coordinates, targets 60 FPS, softens distant objects, attenuates high-frequency radial distortion with depth, applies translucent centres, and uses the daily light-softness value in shading.

## GPU and visual acceptance

The final GPU matrix covers light and dark palette categories, phone portrait and tablet landscape, 1/4/7/10 actors, clarity 0/0.5/1, motion 0/0.55/1, and Reduce Motion on/off. This produces 288 populated frames plus 72 matching empty-background baselines.

The acceptance gates verify nonblank output, actor contribution, colourfulness, safe borders, UI exclusion, negative space, distribution across at least five canvas sectors at ten objects, at least three material families, the deterministic 6/4 split between the two object palettes, and ten unique colour subsets. Insertion, removal, and capped replacement each have before/during/after coverage.

Final inspected artifacts:

- Complete final attachment export and manifest: `/tmp/living-orbs-final-review-export.iaR7rn/`.
- Final live lab screenshot: `/tmp/living-orbs-final-review-export.iaR7rn/C01859A8-76A8-48AC-8F0C-D97F67DC3FBE.png`.
- Final 3×5 daily grid screenshot: `/tmp/living-orbs-final-review-export.iaR7rn/6CCD380F-0E7A-425A-9410-1E360D7FD551.png`.
- Final dark phone portrait painted fixture: `/tmp/living-orbs-final-review-export.iaR7rn/A5A24114-25F3-4C6E-A690-33877E906232.png`.
- Final dark tablet landscape painted fixture: `/tmp/living-orbs-final-review-export.iaR7rn/9C879004-F935-486A-96A8-1F1DBB947EFA.png`.

Manual inspection found varied orb sizes and materials, multi-colour and translucent objects, coherent overlap, broad canvas distribution, stable background palettes, readable controls, no clipping, and no intrusion into the bottom control exclusion. The final lab and grid visibly include satin, glow, membrane, rim, and glass responses rather than Figma-like polygons. The lower-clarity frames are intentionally softened by the sleep model while the grain remains sharp.

## Physical-device status

The paired target is `iPhone Costa`, an iPhone 15 Pro on iOS 26.6 (`00008130-001E3CE622C0001C`; CoreDevice ID `43B6B950-DBCA-50C3-AE14-FBD518808E3B`). Developer Mode is enabled.

The signed device build could not start because the installed Xcode 26.3.1 cannot mount a developer disk image for iOS 26.6. Xcode timed out while resolving the destination before compilation or installation. Evidence: `/tmp/living-orbs-device-build.log`.

Consequently the required five-minute physical Metal profile was not run. FPS, dropped frames, peak memory, and thermal state are explicitly **unmeasured**, not inferred from the simulator. Update Xcode to a release that supports iOS 26.6, unlock and reconnect the phone, then rerun the device build and profile.

## Installation

Open this exact project, not the root checkout that previously showed `feat/canvas-ui-simplification`:

`/Users/kosta/Documents/Documents - Konstantin’s MacBook Pro/dev local/step-trader/.worktrees/experiment-cleanup/Steps4.xcodeproj`

Confirm the branch is `codex/day-objects-living-orbs`, select an iPhone simulator or the unlocked `iPhone Costa`, and press Run. On Debug/Internal builds, open Settings → Appearance → Day Objects Lab. The lab can also be launched with the scheme argument `-uiLab dayObjects`.
