# Neutral confirmation and restored blur accents

Review `index.html` for actual simulator captures and the same three-day Metal render sample before/after this follow-up. The baseline is integration `2f4eabd3`, which already includes the nine-silhouette selection change (`709174c6`).

## Behavior

- First tap: the neutral circle reveals a neutral silhouette; Add has a small capsule outline.
- Second tap: commit the event, restore full pigment, display the check badge.
- First removal tap: neutral silhouette and Delete; the second tap removes it.
- Only the pending figure breathes by 2.5% on a 1.6-second cycle. Text and hit targets stay fixed. Reduce Motion uses the static endpoint and stops continuous rendering.
- Neutrality holds during reveal and cancellation; a cancelled addition returns to its circle without flashing color.

## Silhouettes and blur

The previous revision expanded new additions from correlated one/two-preset pools to the nine existing silhouettes. Four presets support `directionalBlur`; distributing picks across all nine reduced its incidence. This follow-up retains a blurred accent when a compatible new actor is chosen after at least two others and none of the retained actors is blurred. It does not change catalog compatibility or shader blur settings.

The same ten-event sample on September 10/11/12 goes from 0/0/1 to 1/1/2 directional-blur actors. Both versions retain nine distinct initial silhouettes. Full material reports accompany the strips. Already frozen actors and historical restoration keep their parameters; only explicit additions use the new rule.

## Validation

- 78 unit/render tests passed: palette states, cancellation, Reduce Motion, rendering lifetime, interaction, layout, NativeAtlas compatibility/persistence, and prospective-versus-committed assignments. Actual Metal readback verifies neutral confirmation pixels and full pigment after adding.
- Result bundle: `/tmp/nowhere-confirmation-final-unit.xcresult`.
- Both UI tests passed: `testHappeningMenuStatesAndReopening` and `testHappeningPaletteAccessibilityKeepsFixedRows`. The first covers switching previews, two-tap additions, reopening, neutral removal preview, cancellation on close, and final two-tap removal. The second checks fixed 3/2/3/2 rows and tappable targets with accessibility5 / increased contrast.
- UI result bundles: `/tmp/nowhere-confirmation-final-ui.xcresult` and `/tmp/nowhere-confirmation-integrated-ui.xcresult`. Both UI tests were repeated successfully after rebasing onto `d2c7536c` (Nowhere Display 0.5); screenshots and videos show that integrated version. The MP4 files record the actual pending states during this run via `simctl io recordVideo`, without post-processing.

Captures use the dedicated Nowhere Shapes Menu QA simulator (`74514734-98E6-466B-BB2B-BD48E025B163`), iPhone 17 / iOS 26.3. Scheme Steps4 and embedded extensions use `/tmp/nowhere-shapes-menu-dd`. No physical-device installation or visual verification was performed for this follow-up.
