# Graphite, Frost and Grain Implementation Plan

> Execute inline with executing-plans. No delegation or commits: preserve the existing integration worktree.

**Goal:** Implement the approved graphite controls, day/night reading surfaces and sharper grain.

**Architecture:** SwiftUI owns interface theme and a shared frosted snapshot; Metal owns artwork independently. Keep historical finish unchanged. Settings persist only on Apply.

**Tech Stack:** SwiftUI, Metal, XCTest, existing Steps4 scheme.

**Spec:** User approval in this conversation: graphite mockup #303235; light/dark/system appearance; matching frost on Feeds and Me; no text shadows; sharper static monochrome grain above artwork, below controls.

## Constraints

- No changes to artwork seeds, historical data, event counts, payment logic or website.
- Existing integration worktree; install in place without uninstalling.
- Run focused regression and light/dark UI tests, not the unrelated full visual suite.

## Tasks

- [x] Add and run failing tests in CanvasPersistenceRegressionTests: theme resolution, dark corner surfaces, native high-frequency grain. Confirm all three fail for the expected reasons.
- [ ] Theme: AppTheme resolves system/daylight/night; ThemeModifiers passes resolved colors. SettingsAppearanceDraft loads and applies appTheme; SettingsAppearancePage exposes segmented choice. Tests check light/dark resolution and draft persistence.
- [ ] Material: AppColors.graphite shared by smokedCanvasControl, CanvasBottomActionRow, fullscreen dock and existing energy/navigation. Remove energy label shadows. Render tests sample dark surfaces on white.
- [ ] Reading surfaces: TodayCanvasBackground uses 28pt blur and fixed theme veil. Me and Feeds use the same framing; semantic text colors, no timer shadow. UI test launches explicit daylight/night, captures Canvas, Me and Feeds.
- [ ] Finish: nativeAtlasFinishFragment requests static fine monochrome grain; historical dayObjectsDisplayFragment retains prior paper texture. Native detail test compares measured fine detail against historical rendering.
- [ ] Run NativeAtlasRecipeTests, HappeningPaletteRenderFrameTests, TodayCanvasBackgroundTests and the historical grain regression. Review actual UI screenshots, build device and install without deleting user data.

Native grain implementation uses final pixels, not elapsed time:

```metal
const float noise = (fine * 0.8 + clusters * 0.2) * 2.0 - 1.0;
return saturate(color + noise * clamp(uniforms.grainIntensity, 0.0, 0.075) * 1.25);
```

Theme contract:

```swift
func isLight(in scheme: ColorScheme?) -> Bool {
    self == .daylight || (self == .system && scheme == .light)
}
```

## Verification — 9 September 2026

Implemented all UI/finish tasks above. Native graphite controls and both theme variants were visually inspected on simulator screenshots. Fixed archive-link contrast and kept calendar thumbnail ink independent of interface theme. Existing large-Dynamic-Type greeting wrapping remains outside this material/theme change; normal text size was also inspected.

Red run: three new tests failed for missing theme resolution, transparent corner controls and insufficient fine grain. Green run: 44 focused tests passed, zero failures, including draft Apply/Discard, palette interactions, background preservation, native grain and both light/dark Me/Feeds flows.

Result: `/tmp/nowhere-native-atlas-dd/Logs/Test/Test-Steps4-2026.09.09_15-38-42-+0200.xcresult`.
Screens: `/tmp/nowhere-frost-verified-screens/`.
Full unrelated test suite was not run. No commits, merges, website deployment or user-data migrations.
