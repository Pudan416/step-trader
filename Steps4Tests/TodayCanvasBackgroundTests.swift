import XCTest
import Combine
import MetalKit
@testable import Steps4

@MainActor
final class TodayCanvasBackgroundTests: XCTestCase {
    private func appearance(day: String = "2026-09-07") -> TodayCanvasAppearance {
        TodayCanvasAppearance(
            dayKey: day, steps: 15, sleep: 12, earned: 100, spent: 25,
            hasSteps: true, hasSleep: true, style: CanvasVisualStyle.editorial.rawValue,
            gradient: GradientStyle.radial.rawValue, palette: GradientPalette.warmSunset.rawValue,
            texture: CanvasTexture.grainSmall.rawValue, categories: ""
        )
    }

    func testVisibleFrameKeepsCanvasViewportAndReleasesPausedRenderer() async throws {
        let store = TodayCanvasBackdropStore(debounce: .zero, load: { _ in nil }, render: { _, _ in UIImage() })
        store.refresh(appearance())
        for _ in 0..<20 { await Task.yield() }
        let scene = DayObjectScene.make(input: .init(
            dayKey: "2026-09-07", identity: "viewport-test", eventIDs: [],
            motionEnergy: 0.5, visualClarity: 0.5, canvasCoverage: .fullCanvas,
            usesEditorialField: true, editorialBackground: .lowContrast
        ))
        let renderer = try XCTUnwrap(DayObjectsRenderer.create(
            scene: scene, environment: .init(motionEnergy: 0.5, visualClarity: 0.5)
        ))
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 320, height: 640))
        let controller = UIViewController()
        window.rootViewController = controller
        window.makeKeyAndVisible()
        let view = MTKView(frame: CGRect(x: 12, y: 30, width: 240, height: 460), device: renderer.device)
        DayObjectsRenderer.configureDisplay(view)
        view.delegate = renderer
        view.framebufferOnly = true
        controller.view.addSubview(view)
        defer { view.isPaused = true; window.isHidden = true }
        store.registerSource(view, renderer: renderer)
        store.unregisterSource(MTKView()) // Other posters cannot clear the canvas source.
        view.draw()
        await store.captureVisibleFrame()
        let captured = try XCTUnwrap(store.visibleFrame)
        XCTAssertEqual(captured.windowRect, view.convert(view.bounds, to: nil))
        XCTAssertEqual(captured.image.size.width, view.bounds.width, accuracy: 0.1)
        XCTAssertEqual(captured.image.size.height, view.bounds.height, accuracy: 0.1)
        XCTAssertFalse(view.isPaused, "The capture must not leave the canvas frozen")
        store.refresh(appearance(day: "2026-09-08"))
        XCTAssertNil(store.visibleFrame, "A captured frame must not survive a day change")
        store.unregisterSource(view)
        await store.captureVisibleFrame()
        XCTAssertNil(store.visibleFrame, "The picker/dismantled canvas must not become a backdrop")
    }

    func testFeedPigmentKeepsSourcePaletteAfterWashedOutSnapshotAndPreferenceChange() async throws {
        let washedOut = UIGraphicsImageRenderer(size: CGSize(width: 12, height: 12)).image { ctx in
            UIColor.lightGray.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: 12, height: 12))
        }
        let firstRendered = expectation(description: "first snapshot published")
        let secondRendered = expectation(description: "updated snapshot published")
        let store = TodayCanvasBackdropStore(debounce: .zero, load: { _ in nil }, render: { _, _ in washedOut })
        var publishedCount = 0
        let subscription = store.$image.compactMap { $0 }.sink { _ in
            publishedCount += 1
            if publishedCount == 1 { firstRendered.fulfill() }
            if publishedCount == 2 { secondRendered.fulfill() }
        }
        var input = appearance()
        input.style = CanvasVisualStyle.legacy.rawValue
        input.palette = GradientPalette.ocean.rawValue
        store.refresh(input)
        await fulfillment(of: [firstRendered], timeout: 3)
        XCTAssertEqual(store.feedPalette.colors.first?.sRGB.x ?? -1, Float(0x7F) / 255, accuracy: 0.001)
        XCTAssertEqual(store.feedPalette.colors.last?.sRGB.z ?? -1, Float(0x33) / 255, accuracy: 0.001)
        XCTAssertNotEqual(store.feedPalette, store.unlockPalette, "Rendered haze must not replace the pigment used in Feeds")
        let ocean = store.feedPalette
        input.palette = GradientPalette.aurora.rawValue
        store.refresh(input)
        XCTAssertNotEqual(store.feedPalette, ocean, "A preference change must reach Feeds even while a snapshot already exists")
        await fulfillment(of: [secondRendered], timeout: 3)
        withExtendedLifetime(subscription) {}
    }

    func testCurrentPreferencesAndMetricsApplyWithoutRewritingSavedCanvas() {
        var saved = DayCanvas(dayKey: "2026-09-07")
        saved.visualStyleRaw = CanvasVisualStyle.legacy.rawValue
        saved.stepsPoints = 2
        let originalDate = saved.createdAt
        let result = appearance().canvas(from: saved)
        XCTAssertEqual(result.createdAt, originalDate)
        XCTAssertGreaterThan(result.lastModified, saved.lastModified)
        XCTAssertEqual(result.resolvedVisualStyle, .editorial)
        XCTAssertEqual(result.stepsPoints, 15)
        XCTAssertEqual(result.decayNorm, 0.25)
        XCTAssertEqual(saved.stepsPoints, 2)
        XCTAssertEqual(saved.resolvedVisualStyle, .legacy)
        let next = appearance(day: "2026-09-08").canvas(from: saved)
        XCTAssertEqual(next.dayKey, "2026-09-08")
        XCTAssertNotEqual(next.createdAt, originalDate)
    }

    func testRemixedSnapshotPreservesSavedAppearanceWhileRefreshingMetrics() {
        var saved = DayCanvas(dayKey: "2026-09-07")
        saved.remixSeed = 99
        saved.gradientStyle = GradientStyle.allCases.first { $0 != .radial }!.rawValue
        saved.gradientPalette = GradientPalette.ocean.rawValue
        saved.textureRaw = CanvasTexture.allCases.first { $0 != .grainSmall }!.rawValue
        let result = appearance().canvas(from: saved)
        XCTAssertEqual(result.remixSeed, 99)
        XCTAssertEqual(result.gradientStyle, saved.gradientStyle)
        XCTAssertEqual(result.gradientPalette, saved.gradientPalette)
        XCTAssertEqual(result.textureRaw, saved.textureRaw)
        XCTAssertEqual(result.stepsPoints, 15)
        XCTAssertEqual(result.sleepPoints, 12)
        XCTAssertEqual(result.inkSpent, 25)
    }

    func testSharedUnlockPaletteFollowsPersistedRemixAndUndo() async {
        let input = appearance()
        var saved = DayCanvas(dayKey: input.dayKey)
        saved.remixSeed = 99
        let first = expectation(description: "remixed background")
        let second = expectation(description: "restored background")
        var publications = 0
        let store = TodayCanvasBackdropStore(debounce: .zero, load: { _ in saved }, render: { _, _ in UIImage() })
        let subscription = store.$image.compactMap { $0 }.sink { _ in
            publications += 1
            if publications == 1 { first.fulfill() } else { second.fulfill() }
        }
        let sceneInput = EditorialCanvasInputFactory.make(
            canvas: saved,
            metrics: EditorialCanvasMetrics(stepsProgress: 0.5, sleepProgress: 0.5, spentProgress: 0),
            paletteCategories: ModernPaletteSelection.all
        ).sceneInput
        let expected = DayObjectScene.make(input: sceneInput).paletteSet.background.hexes
            .map { DayObjectRGB(hex: $0) }.sorted { $0.perceptualOKLab.x > $1.perceptualOKLab.x }
        store.refresh(input)
        XCTAssertEqual(store.feedPalette.colors, expected, "Feeds must immediately follow the saved visual/music remix")
        await fulfillment(of: [first], timeout: 2)
        XCTAssertEqual(store.unlockPalette.colors, expected)
        saved.remixSeed = nil
        store.refresh(input, reload: true)
        XCTAssertEqual(store.feedPalette, TodayCanvasUnlockPalette.make(appearance: input), "Undo must restore the feed pigment immediately")
        await fulfillment(of: [second], timeout: 2)
        XCTAssertEqual(store.unlockPalette, TodayCanvasUnlockPalette.make(appearance: input))
        withExtendedLifetime(subscription) { }
    }

    func testLegacySnapshotIncludesItsFigures() async throws {
        var input = appearance()
        input.style = CanvasVisualStyle.legacy.rawValue
        var canvas = input.canvas(from: nil)
        canvas.lastModified = .now.addingTimeInterval(2)
        let empty = await CanvasStorageService.shared.renderedSnapshot(
            canvas: canvas, size: CGSize(width: 195, height: 422), scale: 1,
            paletteCategories: ModernPaletteSelection.all
        )
        canvas.elements = [CanvasElement(
            id: UUID(), kind: .circle, optionId: "background-test", label: nil,
            hexColor: "#FFFFFF", hexColor2: nil, size: 0.6,
            basePosition: CGPoint(x: 0.5, y: 0.5), phaseOffset: 0,
            driftSpeed: 0, driftAmplitude: 0, pulseFrequency: 0,
            pulseAmplitude: 0, rotationSpeed: 0, opacity: 1,
            createdAt: .now.addingTimeInterval(-10), shapeSeed: 42, frozenShapeType: .circle
        )]
        let populated = await CanvasStorageService.shared.renderedSnapshot(
            canvas: canvas, size: CGSize(width: 195, height: 422), scale: 1,
            paletteCategories: ModernPaletteSelection.all
        )
        XCTAssertNotEqual(try XCTUnwrap(empty?.pngData()), try XCTUnwrap(populated?.pngData()))
    }

    func testRenderedPaletteUsesActualPixelsOrderedByLightness() throws {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let image = UIGraphicsImageRenderer(size: CGSize(width: 120, height: 120), format: format).image { ctx in
            UIColor(red: 0.8, green: 0.6, blue: 0.6, alpha: 1).setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: 60, height: 120))
            UIColor(red: 0.3, green: 0.2, blue: 0.2, alpha: 1).setFill()
            ctx.fill(CGRect(x: 60, y: 0, width: 60, height: 120))
        }
        let palette = try XCTUnwrap(TodayCanvasUnlockPalette.sampled(from: image))
        XCTAssertEqual(palette.colors.first!.sRGB.x, 0.8, accuracy: 0.01)
        XCTAssertEqual(palette.colors.last!.sRGB.x, 0.3, accuracy: 0.01)
        XCTAssertTrue(zip(palette.colors, palette.colors.dropFirst()).allSatisfy {
            $0.perceptualOKLab.x >= $1.perceptualOKLab.x
        })
        XCTAssertNil(TodayCanvasUnlockPalette.sampled(from: UIImage()))
    }

    func testUnlockGradientUsesSelectedLegacyPaletteFromLightToDark() {
        var input = appearance()
        input.style = CanvasVisualStyle.legacy.rawValue
        input.palette = GradientPalette.ocean.rawValue
        let ocean = TodayCanvasUnlockPalette.make(appearance: input)
        for component in 0..<3 {
            XCTAssertEqual(ocean.colors[0].sRGB[component], DayObjectRGB(hex: "#7FDBDA").sRGB[component], accuracy: 0.000001)
            XCTAssertEqual(ocean.colors[3].sRGB[component], DayObjectRGB(hex: "#0B1E33").sRGB[component], accuracy: 0.000001)
        }
        XCTAssertTrue(zip(ocean.colors, ocean.colors.dropFirst()).allSatisfy {
            $0.perceptualOKLab.x >= $1.perceptualOKLab.x
        })
        input.palette = GradientPalette.aurora.rawValue
        XCTAssertNotEqual(ocean, TodayCanvasUnlockPalette.make(appearance: input))
    }

    func testUnlockPaletteMatchesObjectsCanvasForEachDay() {
        for day in ["2026-09-07", "2026-09-08", "2026-09-09"] {
            let input = appearance(day: day)
            let sceneInput = EditorialCanvasInputFactory.make(
                canvas: input.canvas(from: nil),
                metrics: EditorialCanvasMetrics(stepsProgress: 0.5, sleepProgress: 0.5, spentProgress: 0),
                paletteCategories: ModernPaletteSelection.all
            ).sceneInput
            let scene = DayObjectScene.make(input: sceneInput)
            let expected = scene.paletteSet.background.hexes.map { DayObjectRGB(hex: $0) }
                .sorted { $0.perceptualOKLab.x > $1.perceptualOKLab.x }
            XCTAssertEqual(TodayCanvasUnlockPalette.make(appearance: input).colors, expected)
        }
    }

    func testFirstRenderDoesNotWaitForUpdateDebounce() async {
        let started = expectation(description: "first frame starts immediately")
        let store = TodayCanvasBackdropStore(debounce: .seconds(30), load: { _ in nil }, render: { _, _ in
            started.fulfill()
            return UIImage()
        })
        store.refresh(appearance())
        XCTAssertFalse(store.unlockPalette.colors.isEmpty, "Today's palette must be ready before the snapshot")
        await fulfillment(of: [started], timeout: 1)
    }

    func testFailedRefreshKeepsImageAndCanRetrySameInput() async {
        let first = UIImage()
        let recovered = UIImage()
        var count = 0
        let store = TodayCanvasBackdropStore(debounce: .zero, load: { _ in nil }, render: { _, _ in
            count += 1
            return count == 1 ? first : (count == 2 ? nil : recovered)
        })
        store.refresh(appearance())
        for _ in 0..<100 { await Task.yield() }
        XCTAssertTrue(store.image === first)
        var updated = appearance()
        updated.steps += 1
        store.refresh(updated)
        for _ in 0..<100 { await Task.yield() }
        XCTAssertTrue(store.image === first, "A failed export must not blank a visible screen")
        XCTAssertEqual(count, 2, "Failure must not spin in a retry loop")
        store.refresh(updated)
        for _ in 0..<100 { await Task.yield() }
        XCTAssertTrue(store.image === recovered)
        XCTAssertEqual(count, 3)
    }

    func testWidgetExportsSerializeAndKeepOnlyLatestPendingCanvas() async {
        let started = expectation(description: "first export")
        let finished = expectation(description: "latest export")
        var resume: CheckedContinuation<Void, Never>?
        var renderedSteps: [Int] = []
        let queue = CanvasWidgetSnapshotQueue(debounce: .zero) { canvas, _ in
            renderedSteps.append(canvas.stepsPoints)
            if canvas.stepsPoints == 1 {
                await withCheckedContinuation { resume = $0; started.fulfill() }
            }
            if canvas.stepsPoints == 3 { finished.fulfill() }
        }
        var canvas = appearance().canvas(from: nil)
        canvas.stepsPoints = 1
        queue.submit(canvas, categories: ModernPaletteSelection.all)
        await fulfillment(of: [started], timeout: 2)
        canvas.stepsPoints = 2
        queue.submit(canvas, categories: ModernPaletteSelection.all)
        canvas.stepsPoints = 3
        queue.submit(canvas, categories: ModernPaletteSelection.all)
        for _ in 0..<100 { await Task.yield() }
        XCTAssertEqual(renderedSteps, [1], "Exports must not overlap")
        resume?.resume()
        await fulfillment(of: [finished], timeout: 2)
        XCTAssertEqual(renderedSteps, [1, 3], "Intermediate stale states must not be rendered")
    }

    func testIdenticalRefreshesReuseOneImageAndAvoidDiskReads() async {
        let rendered = expectation(description: "first render")
        var renderCount = 0
        var loadCount = 0
        let store = TodayCanvasBackdropStore(debounce: .zero, load: { _ in
            loadCount += 1
            return nil
        }, render: { _, _ in
            renderCount += 1
            rendered.fulfill()
            return UIImage()
        })
        store.refresh(appearance())
        await fulfillment(of: [rendered], timeout: 2)
        for _ in 0..<20 { store.refresh(appearance()) }
        try? await Task.sleep(for: .milliseconds(30))
        XCTAssertEqual(renderCount, 1)
        XCTAssertEqual(loadCount, 1)
    }

    func testNewDayRejectsAnOlderInFlightRender() async {
        let started = expectation(description: "old render started")
        let finished = expectation(description: "new image published")
        var continuation: CheckedContinuation<UIImage?, Never>?
        let oldImage = UIImage()
        let newImage = UIImage()
        var renderCount = 0
        var preparedDays: [String] = []
        let store = TodayCanvasBackdropStore(debounce: .zero, load: { _ in nil }, render: { _, _ in
            renderCount += 1
            if renderCount == 1 {
                return await withCheckedContinuation {
                    continuation = $0
                    started.fulfill()
                }
            }
            return newImage
        }, onRenderedCanvas: { canvas, _ in preparedDays.append(canvas.dayKey) })
        var published: [UIImage] = []
        let subscription = store.$image.compactMap { $0 }.sink {
            published.append($0)
            if $0 === newImage { finished.fulfill() }
        }
        store.refresh(appearance())
        await fulfillment(of: [started], timeout: 2)
        store.refresh(appearance(day: "2026-09-08"))
        XCTAssertNil(store.image)
        continuation?.resume(returning: oldImage)
        await fulfillment(of: [finished], timeout: 2)
        XCTAssertEqual(renderCount, 2)
        XCTAssertEqual(preparedDays, ["2026-09-08"], "Stale renders must not replace the poster snapshot")
        XCTAssertEqual(published.count, 1)
        XCTAssertTrue(published.first === newImage)
        withExtendedLifetime(subscription) { }
    }
}
