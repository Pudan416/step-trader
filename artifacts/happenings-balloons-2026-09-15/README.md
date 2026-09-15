# Spaced Frequent circles and balloon expansion

Frequent keeps its ten choices in 3/2/3/2 rows with an 8-point nominal gap, matching All. All unfolds the remaining catalog around those ten, which retain their reading order in the center of the 4/5 staggered field. The same 0.58-second transition reverses when returning to Frequent, including after panning. Rapid reversals start from the current sampled progress. Reduce Motion changes endpoints without spring movement.

The scroll surface and its content size stay stable across modes. A shared timeline supplies identical source centers, radii and appearance scales to Metal and SwiftUI labels; Metal skips secondary geometry smoothing. Additional circles grow only into free space, preserving an 8-point nominal clearance through the transition. Hidden choices are removed from accessibility and interaction. The canvas remains fixed below the transparent field.

## Validation

47 distinct focused unit tests passed: 24 layout, 14 renderer, 5 scrolling, 3 expansion, and 1 staggered ten-item regression. Coverage includes intermediate-frame spacing, stable world size, exact endpoints, central identity order, rapid reversal and immediate shared geometry in the renderer.

Four UI scenarios passed: Frequent → All → pan → Frequent restores all initial frames; Health choices and canvas selection survive mode changes; the underlying canvas pixels stay fixed during panning; accessibility text remains fully reachable with the fixed switch. The former immediate-switch assertions were updated to wait for the new animation endpoint. An initial isolated UI run encountered a previously created custom test item; resetting the editor fixture restored deterministic catalog counts.

Simulator: Nowhere Catalog QA, iOS 26.3, F833D84C-FA6A-4A1D-9CF5-C8BD1F1DEEDE. The video is a 7-second simulator recording showing expansion, panning and collapse. It is not physical-device visual verification.

Result bundles (local):
- /tmp/nowhere-happenings-staggered-dd/Logs/Test/Test-Steps4-2026.09.15_14-08-14-+0200.xcresult (shared renderer geometry, regular mode switch and stationary canvas passed; large-type immediate assertion corrected below)
- /tmp/nowhere-happenings-staggered-dd/Logs/Test/Test-Steps4-2026.09.15_14-11-36-+0200.xcresult (large type passed)
- /tmp/nowhere-happenings-staggered-dd/Logs/Test/Test-Steps4-2026.09.15_14-14-29-+0200.xcresult (final balloon geometry and mode switch passed)
- /tmp/nowhere-happenings-staggered-dd/Logs/Test/Test-Steps4-2026.09.15_14-17-13-+0200.xcresult (layout and Health/canvas selection passed)

## Device scope

Local codex/happenings-field feature build; no integration publication. iPhone Costa was unavailable over Wi-Fi at the device check. Signed build/resource verification and any installation outcome are recorded separately.

Signed revision `be636d5b790d15e7453524ac57e662f7131bfaa0` built successfully with all four extensions; signatures, provisioning and bundled resources passed verification. Installation attempt returned CoreDevice error 1011 because iPhone Costa remained unavailable over Wi-Fi. The initial attempt did not install this revision.

On 2026-09-15T19:40:56.640210+02:00, the user requested installation again. Wi-Fi installation and launch both succeeded on iPhone Costa. Installed app and four extensions were built from `be636d5b790d15e7453524ac57e662f7131bfaa0`; the signed bundle was reverified before installation. Physical-device UI appearance was not inspected.
