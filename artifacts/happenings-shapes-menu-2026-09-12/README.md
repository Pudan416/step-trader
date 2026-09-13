# Happenings: Native Atlas diversity and menu states

Baseline: c6fa54330e5f24a076549d20b8e608e319bba135 (PR #21). All pictures here are simulator/offscreen Metal renders, not physical-device observations or a copy of the user's saved Canvas.

## Confirmed causes

- `NativeAtlasRecipe.reconciled` selected one, two, or nine presets per day using `rootSeed % 3`. Its family index used the same seed modulo nine: single-family days could only select soft drift, concave square, or soft square. Different colors/parameters did not change this restricted silhouette inventory.
- The older `HappeningEditorialAssignmentResolver.variedElementID` optimized Editorial geometry, while the active Native Atlas renderer independently picked an atlas preset. That previous diversity fix did not control the actual silhouette.
- `.added` explicitly requested saturation 0.08 and opacity 0.82. The native renderer remapped that saturation to zero. Gray was an intentional presentation state, not missing persistence.
- The atlas is evaluated directly by Metal from frozen uniforms. The PNG export manifest is a review inventory, not a runtime asset lookup. No missing-image fallback caused this reproduction. The nine presets and their material compatibility remain unchanged.

## Trace and preservation

Stable happening ID + custom day -> deterministic preview UUID. The day's persisted nonce changes the color variant. On new native additions, the complete existing recipe chooses a least-used preset, alternating rounded, radial and angular groups when counts tie. The resolver carries that exact native actor into the renderer; `DayCanvas.elements` appending the same UUID freezes the same geometry, material, placement, size and rotation. The canvas JSON retains these numeric parameters and the element's color variant.

Already committed UUIDs and colors win over new palette rolls or catalog title changes. Retained actors are returned unchanged. Ordinary restore/reconciliation still uses atlas-1 for any missing historical actors; only explicitly new element IDs use the new selection policy. No schema migration or historical regeneration is performed. Legacy canvases without native recipes retain their existing path.

Previous work checked: 055208d1, 6c81fd07, 673407c7 and dirty canvas-v2 shape changes; the relevant prior Editorial diversity and silhouette fields are already integrated. Catalog naming is handled in the neighboring task.

## Reproduction

Same ten built-in IDs, same order, nonce 7; three fresh canvases dated September 10–12, 2026. All additions go through the production assignment resolver and `DayCanvas.elements.append`. Every retained actor is compared after each addition, then JSON is encoded/decoded.

Before: distinct presets among the first nine additions = **1, 5, 6**. September 10 produced ten soft squares. See `before-native-distribution.txt` for the exact sequence. The strips use the production Native Atlas renderer with full-color preview treatment to expose geometry independently of the old gray added state.

## Menu behavior

- Available: neutral circle.
- First activation: actual colored figure, a short reveal/scale transition, and the existing localized Add label. No Canvas mutation or colors awarded.
- Second activation: persistent full color/opacity and a high-contrast checkmark.
- Existing removal behavior remains two activations with its separate Delete label and muted preview.
- Closing/reopening cancels unconfirmed selection and derives added state from today's Canvas. Day rollover clears pending selection. Pending duplicate taps are ignored; the synchronous MainActor transaction still rejects duplicate daily additions and saves Canvas before crediting the entry.
- VoiceOver retains explicit Available / Previewing addition / On Canvas / Previewing removal values and action hints. Reduce Motion retains its short fade without spatial interpolation. The Add/Delete text and checkmark provide non-color state cues.

## Verification

- Red reproduction: `/tmp/nowhere-shapes-red2.xcresult`: three expected failures (diversity 1/5/6, GPU saturation 0.08, near-neutral actual pixels).
- Candidate: `/tmp/nowhere-shapes-verified.xcresult`: 124 unit/render tests and three UI tests passed. This includes Reduce Motion endpoints, light/dark label ink, largest Dynamic Type layout, pending duplicate taps, reopen/cancel, new-day state, persistence and daily-addition accounting.
- After: distinct presets among the first nine additions = **9, 9, 9**. Exact output in `after-native-distribution.txt`; screenshots in `index.html`.
- Menu screenshots: first activation shows 0/0 colors; three confirmed additions show 18/18. No phone data was changed. App scheme Steps4 built with all four embedded extensions for the simulator.
- VoiceOver verification covers accessible values/hints and rendered non-color cues; it is not a physical-device spoken VoiceOver session.

Final integration base: 2f5ac794 (English-only catalog), including 12ca5aea (Display 0.4). `/tmp/nowhere-shapes-final-clean.xcresult`: **206 unit/render tests + one UI scenario passed**. The largest-text UI scenario also passed on the identical production code in `/tmp/nowhere-shapes-final.xcresult`. That earlier reused-simulator run exposed seven existing unit-test isolation failures by recovering three UI fixture additions; the new UI scenario now removes its own additions after capture. The final clean run reinstalls only the dedicated simulator app. Updated menu captures use Display 0.4 and the English-only catalog.

Local integration artifacts were preserved at backup commit a653922bedfc55290317a9e92e8545214056fe85 (`codex/backup-integration-before-shapes-menu-20260912`) without changing its working index. No physical-device installation was performed.

Post-UI isolation verification: `/tmp/nowhere-shapes-post-ui.xcresult`, **30 tests passed without cleaning/reinstalling the simulator again**. The UI scenario's own cleanup prevents its three additions from leaking into subsequent unit runs.
