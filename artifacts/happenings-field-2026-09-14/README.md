# Scrollable happenings field

Base: `16a17ddc` (`origin/codex/current-integration` when work started). Feature branch: `codex/happenings-field`.

The built-in catalog contains the agreed 30 names, each at most 15 characters. Existing IDs, custom names and use history survive upgrading from ten built-ins. The ten saved preferences determine the beginning of the field; the rest of the catalog follows and is directly selectable by scrolling.

The field uses five columns with stable positions, native horizontal/vertical/diagonal scrolling, and larger circles for larger text sizes. Scroll offsets are shared with Metal, without interpolating the figure centers away from their labels. Visible choices are culled for rendering; the artwork's ten-actor composition remains separate from the browsing buffer capacity.

Available circles mix a little of the local day gradient into a light backing. Both native and fallback shaders use the same treatment. Adding, previewing and removing happenings keep the existing confirmation interaction.

## Verification

- Steps4 app and embedded extensions built for the iOS simulator.
- 217 unit/integration/rendering tests and 4 UI tests passed, zero failures.
- UI checks: initial field, diagonal movement, adding a choice outside the original ten, persistent positions, removal preview, largest Dynamic Type, and reaching Said no at the far edge.
- Native scroll-offset regression: the original preference-only implementation reported `(0, 0)` after scrolling to `(120, 180)`; the new geometry observer passes the same test.
- Screenshots are from Nowhere Catalog QA, iOS 26.3, 402 × 874 points. These are simulator captures, not physical-device verification.
- Final test result: `/private/tmp/nowhere-happenings-field-dd/Logs/Test/Test-Steps4-2026.09.14_22-32-06-+0200.xcresult`.
- No physical-device installation or remote publication was performed.

## Screenshots

- [Initial field](happenings-field-start.png)
- [After diagonal scrolling](happenings-field-diagonal.png)
- [Added happening](happenings-field-added.png)
- [Largest text size, last choice](happenings-field-large-type.png)
