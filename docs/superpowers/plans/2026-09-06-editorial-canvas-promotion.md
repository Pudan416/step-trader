# Editorial Canvas Promotion Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the approved Editorial Field the default renderer for today's and future Canvas while preserving every pre-existing day and the complete old visual system as Legacy.

**Architecture:** Persist an explicit renderer version on each `DayCanvas` and route all live and static artwork through one style decision. A production input factory adapts canvas elements and health/energy state to `DayObjectSceneInput`; Editorial owns its Metal background and grain, while Legacy keeps the existing SwiftUI canvas, raster texture, and overlays unchanged.

**Tech Stack:** Swift 6, SwiftUI, Metal/MetalKit, Codable JSON, UserDefaults/App Group, XCTest, Xcode 26.

**Spec:** `docs/superpowers/specs/2026-09-06-editorial-canvas-promotion-design.md`

## Global Constraints

- Previously saved days without an explicit renderer style resolve to Legacy.
- Editorial is selected once for the active day at migration and is the default for new days.
- Legacy retains current figures, colors, gradients, textures, drag editing, and Smudge/Cosmic overlays.
- Editorial never creates `TextureOverlayView`, `EnergyGradientBackground`, Smudge, or Cosmic layers.
- Do not change the approved Editorial composition, material rules, or Metal grain.
- Do not move laboratory controls, diagnostics, or music controls to Gallery.
- Do not update perceptual goldens before inspecting a new render.
- Preserve unrelated dirty files and commit only task-specific paths or hunks.
- Run only one heavy build or test process at a time.

## File Structure

- `Models/CanvasVisualStyle.swift` owns renderer identity and migration policy.
- `Models/DayCanvas.swift` persists a day's renderer.
- `Experiments/DayObjects/EditorialCanvasInputFactory.swift` maps production state into Day Objects.
- `Views/Components/DayCanvasArtworkView.swift` routes live artwork without constructing inactive layers.
- `Experiments/DayObjects/DayObjectsImageRenderer.swift` renders deterministic Metal stills.
- Existing Gallery, Appearance, history, thumbnail, and export files consume those focused boundaries.
- `Steps4.xcodeproj/project.pbxproj` explicitly registers every new app and test source in its target.

---

### Task 1: Persist renderer style and migrate only the active day

**Files:**
- Create: `StepsTrader/Models/CanvasVisualStyle.swift`
- Modify: `StepsTrader/Models/DayCanvas.swift`
- Modify: `StepsTrader/Utilities/SharedKeys.swift`
- Create: `Steps4Tests/CanvasVisualStyleTests.swift`
- Modify: `Steps4.xcodeproj/project.pbxproj`

**Interfaces:**
- Produces `CanvasVisualStyle`, `DayCanvas.visualStyleRaw`, `DayCanvas.resolvedVisualStyle`.
- Produces `CanvasVisualStyleMigration.decision(dayKey:storedStyleRaw:currentDayKey:completedVersion:)`.
- Produces `SharedKeys.canvasVisualStyle` and `SharedKeys.canvasVisualStyleMigrationVersion`.

- [ ] **Step 1: Write the failing persistence tests**

```swift
final class CanvasVisualStyleTests: XCTestCase {
    func testMissingStyleResolvesLegacy() {
        XCTAssertEqual(DayCanvas(dayKey: "2026-09-01").resolvedVisualStyle, .legacy)
    }

    func testFirstMigrationPromotesOnlyCurrentDay() {
        XCTAssertEqual(
            CanvasVisualStyleMigration.decision(
                dayKey: "2026-09-06", storedStyleRaw: nil,
                currentDayKey: "2026-09-06", completedVersion: 0
            ),
            .persist(.editorial, markVersion: 1)
        )
        XCTAssertEqual(
            CanvasVisualStyleMigration.decision(
                dayKey: "2026-09-05", storedStyleRaw: nil,
                currentDayKey: "2026-09-06", completedVersion: 0
            ),
            .use(.legacy)
        )
    }

    func testExplicitLegacySurvivesCompletedMigration() {
        XCTAssertEqual(
            CanvasVisualStyleMigration.decision(
                dayKey: "2026-09-06", storedStyleRaw: "legacy",
                currentDayKey: "2026-09-06", completedVersion: 1
            ),
            .use(.legacy)
        )
    }

    func testEditorialSurvivesWholeCanvasJSONRoundTrip() throws {
        var canvas = DayCanvas(dayKey: "2026-09-06")
        canvas.visualStyleRaw = CanvasVisualStyle.editorial.rawValue
        let data = try JSONEncoder().encode(canvas)
        XCTAssertEqual(try JSONDecoder().decode(DayCanvas.self, from: data).resolvedVisualStyle, .editorial)
    }
}
```

- [ ] **Step 2: Run the focused test and verify it fails because the new types are absent**

```bash
xcodebuild test -project Steps4.xcodeproj -scheme Steps4 -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17,OS=latest' -only-testing:Steps4Tests/CanvasVisualStyleTests CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO
```

- [ ] **Step 3: Implement the minimal style and migration policy**

```swift
enum CanvasVisualStyle: String, Codable, CaseIterable, Identifiable {
    case editorial
    case legacy
    var id: String { rawValue }
}

enum CanvasVisualStyleMigration {
    static let currentVersion = 1
    enum Decision: Equatable {
        case use(CanvasVisualStyle)
        case persist(CanvasVisualStyle, markVersion: Int)
    }

    static func decision(
        dayKey: String, storedStyleRaw: String?,
        currentDayKey: String, completedVersion: Int
    ) -> Decision {
        if let storedStyleRaw, let style = CanvasVisualStyle(rawValue: storedStyleRaw) {
            return .use(style)
        }
        guard dayKey == currentDayKey, completedVersion < currentVersion else {
            return .use(.legacy)
        }
        return .persist(.editorial, markVersion: currentVersion)
    }
}
```

Add the optional Codable field to `DayCanvas`. Invalid or missing raw values resolve to Legacy. New canvas call sites explicitly supply the current preference; the bare initializer remains style-less for backward-compatible test fixtures.

- [ ] **Step 4: Re-run `CanvasVisualStyleTests`; expect PASS**

- [ ] **Step 5: Commit the model boundary**

```bash
git add StepsTrader/Models/CanvasVisualStyle.swift StepsTrader/Models/DayCanvas.swift StepsTrader/Utilities/SharedKeys.swift Steps4Tests/CanvasVisualStyleTests.swift Steps4.xcodeproj/project.pbxproj
git commit -m "feat: version Canvas visual renderer"
```

---

### Task 2: Map production Canvas state into Editorial input

**Files:**
- Create: `StepsTrader/Experiments/DayObjects/EditorialCanvasInputFactory.swift`
- Create: `Steps4Tests/EditorialCanvasInputFactoryTests.swift`
- Modify: `Steps4.xcodeproj/project.pbxproj`

**Interfaces:**
- Produces `EditorialCanvasMetrics(stepsProgress:sleepProgress:spentProgress:)`.
- Produces `EditorialCanvasRenderInput(sceneInput:digitalImpact:)`.
- Produces `EditorialCanvasInputFactory.make(canvas:metrics:paletteCategories:)`.

- [ ] **Step 1: Write failing adapter tests**

```swift
func testFactoryUsesStableUUIDAndFullCanvas() {
    var canvas = DayCanvas(dayKey: "2026-09-06")
    canvas.elements = [makeElement(id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!)]
    let result = EditorialCanvasInputFactory.make(
        canvas: canvas,
        metrics: .init(stepsProgress: 0.8, sleepProgress: 0.6, spentProgress: 0.3),
        paletteCategories: [.neon]
    )
    XCTAssertEqual(result.sceneInput.eventIDs, ["00000000-0000-0000-0000-000000000001"])
    XCTAssertEqual(result.sceneInput.canvasCoverage, .fullCanvas)
    XCTAssertTrue(result.sceneInput.usesEditorialField)
    XCTAssertEqual(result.digitalImpact.spentColors, 30)
}

func testFactoryClampsInvalidMetrics() {
    let result = EditorialCanvasInputFactory.make(
        canvas: DayCanvas(dayKey: "2026-09-06"),
        metrics: .init(stepsProgress: 4, sleepProgress: -2, spentProgress: 9),
        paletteCategories: []
    )
    XCTAssertEqual(result.sceneInput.motionEnergy, 1)
    XCTAssertEqual(result.sceneInput.visualClarity, 0.35)
    XCTAssertEqual(result.digitalImpact.spentColors, 100)
}
```

Use the test target's existing complete `CanvasElement` fixture pattern.

- [ ] **Step 2: Run `EditorialCanvasInputFactoryTests`; expect a missing-type failure**

```bash
xcodebuild test -project Steps4.xcodeproj -scheme Steps4 -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17,OS=latest' -only-testing:Steps4Tests/EditorialCanvasInputFactoryTests CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO
```

- [ ] **Step 3: Implement bounded production mapping**

```swift
let steps = clamp(metrics.stepsProgress)
let sleep = clamp(metrics.sleepProgress)
let spent = clamp(metrics.spentProgress)
let eventIDs = canvas.elements.prefix(10).map { $0.id.uuidString.lowercased() }
let seed = CanvasElement.makeSeed(
    optionId: "editorial-primary-background", dayKey: canvas.dayKey, index: 0
)
let background = DayObjectEditorialBackground.allCases[
    Int(seed % UInt64(DayObjectEditorialBackground.allCases.count))
]
let sceneInput = DayObjectSceneInput(
    dayKey: canvas.dayKey,
    identity: "primary-canvas",
    eventIDs: eventIDs,
    motionEnergy: 0.25 + 0.75 * steps,
    visualClarity: 0.35 + 0.55 * sleep,
    canvasCoverage: .fullCanvas,
    paletteCategories: paletteCategories,
    usesEditorialField: true,
    editorialBackground: background,
    lowSleep: sleep < 0.55,
    editorialLabConfiguration: .init(materialMode: .generativeDNA, placement: .depthField)
)
```

Return digital impact as `Int((spent * 100).rounded())`. Preserve input element order so insertion/removal chronology stays intact; stable UUID strings preserve retained actor identity.

- [ ] **Step 4: Run adapter plus `DayObjectSceneTests`; expect PASS and unchanged scene tests**

```bash
xcodebuild test -project Steps4.xcodeproj -scheme Steps4 -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17,OS=latest' -only-testing:Steps4Tests/EditorialCanvasInputFactoryTests -only-testing:Steps4Tests/DayObjectSceneTests CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO
```

- [ ] **Step 5: Commit the adapter**

```bash
git add StepsTrader/Experiments/DayObjects/EditorialCanvasInputFactory.swift Steps4Tests/EditorialCanvasInputFactoryTests.swift Steps4.xcodeproj/project.pbxproj
git commit -m "feat: adapt saved canvases to Editorial scenes"
```

---

### Task 3: Route live Gallery and expose Legacy in Appearance

**Files:**
- Create: `StepsTrader/Views/Components/DayCanvasArtworkView.swift`
- Modify: `StepsTrader/Views/GalleryView.swift`
- Modify: `StepsTrader/Views/Settings/SettingsAppearancePage.swift`
- Modify: `StepsTrader/Localizable.xcstrings`
- Create: `Steps4Tests/DayCanvasArtworkRoutingTests.swift`
- Modify: `Steps4Tests/SettingsHomePresentationTests.swift`
- Modify: `Steps4.xcodeproj/project.pbxproj`

**Interfaces:**
- Produces `DayCanvasArtworkLayerPolicy(style:)` with four Boolean layer decisions.
- Produces `DayCanvasArtworkView` with Editorial and Legacy branches.

- [ ] **Step 1: Write failing layer-policy tests**

```swift
func testEditorialDoesNotConstructLegacyLayers() {
    let policy = DayCanvasArtworkLayerPolicy(style: .editorial)
    XCTAssertTrue(policy.usesEditorial)
    XCTAssertFalse(policy.usesLegacyBackground)
    XCTAssertFalse(policy.usesRasterTexture)
    XCTAssertFalse(policy.usesLegacyAnimationOverlay)
}

func testLegacyKeepsExistingLayers() {
    let policy = DayCanvasArtworkLayerPolicy(style: .legacy)
    XCTAssertFalse(policy.usesEditorial)
    XCTAssertTrue(policy.usesLegacyBackground)
    XCTAssertTrue(policy.usesRasterTexture)
    XCTAssertTrue(policy.usesLegacyAnimationOverlay)
}
```

- [ ] **Step 2: Run routing and Settings tests; expect missing policy/presentation failures**

```bash
xcodebuild test -project Steps4.xcodeproj -scheme Steps4 -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17,OS=latest' -only-testing:Steps4Tests/DayCanvasArtworkRoutingTests -only-testing:Steps4Tests/SettingsHomePresentationTests CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO
```

- [ ] **Step 3: Implement the shared live router**

The Editorial switch branch contains only:

```swift
DayObjectsView(
    sceneInput: editorial.sceneInput,
    digitalImpact: editorial.digitalImpact,
    isAnimating: isAnimating,
    soundPulseBus: soundPulseBus
)
```

The Legacy branch preserves the current `EnergyGradientBackground`, `GenerativeCanvasView`, optional `CanvasAnimationOverlay`, and `TextureOverlayView` arguments. Use a real `switch`; do not instantiate inactive layers and hide them with opacity.

- [ ] **Step 4: Apply migration and live routing in Gallery**

Add AppStorage for preferred style and migration version in the app-group defaults. After local or remote loading, apply `CanvasVisualStyleMigration.decision`; persist first promotion once. On a preference change, update only today's loaded canvas, save it, invalidate its thumbnail, and end editing when switching to Editorial.

Replace `canvasLayers` with the shared router while leaving Gallery chrome, happening palette, and add/remove controls outside it. Hide the full-screen Edit action for Editorial; direct drag editing remains available in Legacy.

- [ ] **Step 5: Add the Appearance style picker**

```swift
VStack(alignment: .leading, spacing: 24) {
    canvasStylePicker
    if selectedCanvasStyle == .editorial {
        modernPaletteCategoriesSection
    } else {
        appearanceModePicker
        legacyAppearanceControls
    }
}
```

Use localized `Editorial` and `Legacy` labels with selected accessibility state. Hidden Legacy controls retain their AppStorage values. Keep the internal Day Objects Lab link behind its existing feature flag.

- [ ] **Step 6: Run migration, adapter, routing, and Settings tests; expect PASS**

```bash
xcodebuild test -project Steps4.xcodeproj -scheme Steps4 -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17,OS=latest' -only-testing:Steps4Tests/CanvasVisualStyleTests -only-testing:Steps4Tests/EditorialCanvasInputFactoryTests -only-testing:Steps4Tests/DayCanvasArtworkRoutingTests -only-testing:Steps4Tests/SettingsHomePresentationTests CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO
```

- [ ] **Step 7: Commit the live promotion**

```bash
git add StepsTrader/Views/Components/DayCanvasArtworkView.swift StepsTrader/Views/GalleryView.swift StepsTrader/Views/Settings/SettingsAppearancePage.swift StepsTrader/Localizable.xcstrings Steps4Tests/DayCanvasArtworkRoutingTests.swift Steps4Tests/SettingsHomePresentationTests.swift Steps4.xcodeproj/project.pbxproj
git commit -m "feat: promote Editorial Field to Canvas"
```

---

### Task 4: Render deterministic Editorial stills directly through Metal

**Files:**
- Modify: `StepsTrader/Experiments/DayObjects/DayObjectsRenderer.swift`
- Create: `StepsTrader/Experiments/DayObjects/DayObjectsImageRenderer.swift`
- Modify: `Steps4Tests/DayObjectRenderFrameTests.swift`
- Modify: `Steps4.xcodeproj/project.pbxproj`

**Interfaces:**
- Produces `DayObjectsRenderer.renderOffscreen(size:pointScale:elapsedTime:completion:)`.
- Produces `DayObjectsImageRenderer.image(input:size:scale:elapsedTime:) async -> UIImage?`.

- [ ] **Step 1: Write a failing 390x500 offscreen test**

```swift
let image = try await DayObjectsImageRenderer.image(
    input: input,
    size: CGSize(width: 390, height: 500),
    scale: 1,
    elapsedTime: 4
)
let cgImage = try XCTUnwrap(image?.cgImage)
XCTAssertEqual(cgImage.width, 390)
XCTAssertEqual(cgImage.height, 500)
XCTAssertGreaterThan(nonTransparentPixelCount(cgImage), 390 * 500 * 9 / 10)
XCTAssertGreaterThan(chromaticPixelCount(cgImage), 390 * 500 / 20)
```

Also assert actor IDs match `DayObjectRenderFrame.make` at the same aspect and elapsed time.

- [ ] **Step 2: Run only that test; expect missing offscreen API failure**

```bash
xcodebuild test -project Steps4.xcodeproj -scheme Steps4 -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17,OS=latest' -only-testing:Steps4Tests/DayObjectRenderFrameTests/testEditorialOffscreenImageMatchesFixedFrame CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO
```

- [ ] **Step 3: Extract shared Metal command encoding**

Both drawable and offscreen paths call:

```swift
private func encodeFrame(
    outputTexture: MTLTexture,
    outputPass: MTLRenderPassDescriptor,
    drawableSize: CGSize,
    pointToPixelScale: Float,
    elapsedTime: TimeInterval,
    present: MTLDrawable?
) -> MTLCommandBuffer?
```

Preserve the existing mesh gradient, instanced actors, optional two-pass blur, grain/display, glitch, actor-buffer lease, and performance-probe order. The offscreen path uses a shared `.bgra8Unorm_srgb` output texture and no drawable.

- [ ] **Step 4: Implement readback**

Create a fixed-clock renderer, encode one frame, await that command buffer, read BGRA bytes, and build an upright sRGB `UIImage`. Reject zero/non-finite sizes and cap either pixel dimension at 4096.

- [ ] **Step 5: Run all `DayObjectRenderFrameTests`; expect PASS**

```bash
xcodebuild test -project Steps4.xcodeproj -scheme Steps4 -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17,OS=latest' -only-testing:Steps4Tests/DayObjectRenderFrameTests CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO
```

- [ ] **Step 6: Commit only promotion-related hunks**

`DayObjectsRenderer.swift` and its test are already dirty. Inspect `git diff`, use `git add -p` for those two files, and ensure cached diff contains no pre-existing material/palette changes.

```bash
git add StepsTrader/Experiments/DayObjects/DayObjectsImageRenderer.swift
git add -p StepsTrader/Experiments/DayObjects/DayObjectsRenderer.swift Steps4Tests/DayObjectRenderFrameTests.swift
git add Steps4.xcodeproj/project.pbxproj
git commit -m "feat: render Editorial canvas stills in Metal"
```

---

### Task 5: Route history, calendar tiles, and export by stored style

**Files:**
- Modify: `StepsTrader/Services/HistoryThumbnailCache.swift`
- Modify: `StepsTrader/Views/MeViewSupport.swift`
- Modify: `StepsTrader/Views/GalleryView.swift`
- Modify: `StepsTrader/Services/CanvasStorageService.swift`
- Modify: `StepsTrader/Intents/ExportCanvasWallpaperIntent.swift`
- Modify: `Steps4Tests/CanvasPersistenceRegressionTests.swift`
- Modify: `Steps4Tests/DayCanvasArtworkRoutingTests.swift`

**Interfaces:**
- Consumes live router from Task 3 and Metal still renderer from Task 4.
- Produces style-bearing thumbnail cache identities and `CanvasExportRoute`.

- [ ] **Step 1: Write failing cache and export routing assertions**

```swift
XCTAssertNotEqual(
    HistoryThumbnailCache.cacheIdentity(dayKey: "2026-09-06", style: .legacy),
    HistoryThumbnailCache.cacheIdentity(dayKey: "2026-09-06", style: .editorial)
)
XCTAssertEqual(CanvasExportRoute(canvas: legacyCanvas), .legacySwiftUI)
XCTAssertEqual(CanvasExportRoute(canvas: editorialCanvas), .editorialMetal)
```

- [ ] **Step 2: Run persistence/routing tests; expect missing style-aware API failures**

```bash
xcodebuild test -project Steps4.xcodeproj -scheme Steps4 -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17,OS=latest' -only-testing:Steps4Tests/CanvasPersistenceRegressionTests -only-testing:Steps4Tests/DayCanvasArtworkRoutingTests CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO
```

- [ ] **Step 3: Route live history and fallbacks**

Replace the duplicated history painting block with `DayCanvasArtworkView`. Loaded days always use `canvas.resolvedVisualStyle`. A fallback for today explicitly inherits the current preference; a fallback for a past day explicitly uses Legacy.

- [ ] **Step 4: Route static surfaces**

Legacy keeps its existing `ImageRenderer` path. Editorial obtains a raw painting from `DayObjectsImageRenderer` and composes poster chrome around `Image(uiImage:)`. Include the visual-style raw value in thumbnail cache identity and increment cache version once. The wallpaper intent loads the saved day first and never wraps `DayObjectsView` directly in `ImageRenderer`.

- [ ] **Step 5: Run persistence, routing, and Metal still tests; expect PASS**

```bash
xcodebuild test -project Steps4.xcodeproj -scheme Steps4 -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17,OS=latest' -only-testing:Steps4Tests/CanvasPersistenceRegressionTests -only-testing:Steps4Tests/DayCanvasArtworkRoutingTests -only-testing:Steps4Tests/DayObjectRenderFrameTests CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO
```

- [ ] **Step 6: Commit static routing**

```bash
git add StepsTrader/Services/HistoryThumbnailCache.swift StepsTrader/Views/MeViewSupport.swift StepsTrader/Views/GalleryView.swift StepsTrader/Services/CanvasStorageService.swift StepsTrader/Intents/ExportCanvasWallpaperIntent.swift Steps4Tests/CanvasPersistenceRegressionTests.swift Steps4Tests/DayCanvasArtworkRoutingTests.swift
git commit -m "feat: preserve Canvas renderer across history and export"
```

---

### Task 6: Verify and install the promoted Canvas

**Files:**
- Create visual artifacts under `artifacts/day-objects-editorial-field/production-promotion/`.
- Modify code only for a reproduced defect, with each repair committed separately.

**Interfaces:**
- Consumes all earlier tasks.
- Produces a Simulator build, device build, screenshots, and short motion recording.

- [ ] **Step 1: Run the focused promotion suite once**

```bash
xcodebuild test -project Steps4.xcodeproj -scheme Steps4 -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17,OS=latest' -only-testing:Steps4Tests/CanvasVisualStyleTests -only-testing:Steps4Tests/EditorialCanvasInputFactoryTests -only-testing:Steps4Tests/DayCanvasArtworkRoutingTests -only-testing:Steps4Tests/CanvasPersistenceRegressionTests -only-testing:Steps4Tests/DayObjectSceneTests -only-testing:Steps4Tests/DayObjectRenderFrameTests -only-testing:Steps4Tests/SettingsHomePresentationTests CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO
```

- [ ] **Step 2: Run the complete unit suite once**

```bash
xcodebuild test -project Steps4.xcodeproj -scheme Steps4 -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17,OS=latest' -only-testing:Steps4Tests CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO
```

Expected: PASS. If system instability interrupts it, inspect the result bundle and resume only unexecuted targets rather than repeating automatically.

- [ ] **Step 3: Build one Simulator app**

```bash
xcodebuild build -project Steps4.xcodeproj -scheme Steps4 -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17,OS=latest' CODE_SIGNING_ALLOWED=NO
```

Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 4: Capture required visual states**

Capture current Editorial with ten happenings, the same current day switched to Legacy, a pre-feature Legacy historical day, an Editorial calendar tile, and an Editorial export. Record 8–12 seconds of Editorial motion. Confirm retained actors do not jump after adding/removing one happening and that there is no doubled raster grain.

- [ ] **Step 5: Review repository state**

```bash
git status --short
git diff --check
git log --oneline 3986122..HEAD
```

Confirm pre-existing material changes, the device-performance scheme, and the infrastructure artifact directory remain unstaged unless a task explicitly required an isolated hunk.

- [ ] **Step 6: Build and install once on the connected iPhone**

Discover the exact destination with `xcrun devicectl list devices`, use the configured development team, install the resulting `.app`, and verify launch without erasing app data. Real persisted data is required to validate the one-time promotion and preserved Legacy history.
