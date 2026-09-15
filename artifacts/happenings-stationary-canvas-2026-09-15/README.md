# Stationary canvas under the happenings field

The original viewport-sized canvas stays visible and paused beneath the chooser. The scrolling Metal view draws only targets and selected figures with a transparent background; labels share its scroll-content transform. Both native-atlas and fallback renderer paths preserve coverage alpha. Display finishing handles premultiplied sRGB output without affecting the canvas finish.

Seven staggered rows and the centered starting position remain unchanged.

## Validation

- New pixel regression failed on the previous implementation with 84 assertions, then passed: both renderers, all four target states, a fully transparent empty field, and the opaque original canvas.
- 45 of 46 render/frame tests passed. The one pre-existing failure is `NativeAtlasRecipeTests.testNativeBackgroundShowsBothPaletteEndpointsInPixels`: observed endpoint distance 0.12156862587321038 versus threshold 0.12. Rebuilding the unchanged HEAD production source reproduces exactly the same failure. No threshold or unrelated rendering behavior was changed.
- Four scroll/layout tests passed, including immediate shared movement without another SwiftUI/Metal frame.
- Two simulator UI tests passed: stationary canvas pixels before/after a diagonal pan, and centered staggered layout with pan/add/remove/reopen behavior.
- Screenshots before and after panning were visually inspected. The canvas fills the whole viewport in both positions.
- Physical-device UI verification is separate from these simulator results.

UI result: `/tmp/nowhere-happenings-staggered-dd/Logs/Test/Test-Steps4-2026.09.15_09-31-31-+0200.xcresult`.

This remains an isolated feature build; the user requested no current-integration publication.

## Physical device installation

Installed and launched revision `eee054729af962a58e8df3abca67c217dd18f426` on iPhone Costa over Wi-Fi at 2026-09-15T09:41:18.819891+02:00. The first transmission timed out; the second succeeded. Signed application and all four embedded extensions were checked, with 11 fonts, 21 matching gate images, 122 audio resources, Assets.car and default.metallib present. No physical-device visual verification was performed.
