import XCTest
import SwiftUI
import MetalKit
@testable import Steps4

final class DayCanvasArtworkRoutingTests: XCTestCase {
    @MainActor
    func testPaletteAndCanvasKeepOneEditorialMetalViewAndRenderer() async throws {
        let input = EditorialCanvasRenderInput(
            sceneInput: .init(dayKey: "2026-09-06", identity: "palette-routing", eventIDs: [],
                              motionEnergy: 0.5, visualClarity: 0.75), digitalImpact: .none
        )
        var legacyConstructions = 0
        func artwork(_ mode: DayObjectsPresentationMode) -> DayCanvasArtworkView<Color> {
            DayCanvasArtworkView(style: .editorial, editorial: input, isAnimating: false,
                                 presentationMode: mode) {
                legacyConstructions += 1
                return Color.red
            }
        }
        let host = UIHostingController(rootView: artwork(.canvas))
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer { window.isHidden = true }
        func metalViews(in view: UIView) -> [MTKView] {
            (view as? MTKView).map { [$0] } ?? view.subviews.flatMap { metalViews(in: $0) }
        }
        host.view.layoutIfNeeded()
        let original = try XCTUnwrap(metalViews(in: host.view).first)
        // Renderer resources are prepared asynchronously to keep Canvas startup responsive.
        let deadline = ContinuousClock.now.advanced(by: .seconds(5))
        while original.delegate == nil, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        let renderer = try XCTUnwrap(original.delegate)
        for mode: DayObjectsPresentationMode in [
            .happeningPalette(.init(slots: [], viewportSize: window.bounds.size,
                                    reduceMotion: false, isTransitionActive: false, backgroundRevision: 1)),
            .canvas,
        ] {
            host.rootView = artwork(mode)
            try await Task.sleep(for: .milliseconds(30))
            host.view.layoutIfNeeded()
            let views = metalViews(in: host.view)
            XCTAssertEqual(views.count, 1)
            XCTAssertTrue(views.first === original)
            XCTAssertTrue(views.first?.delegate === renderer)
        }
        XCTAssertEqual(legacyConstructions, 0)
    }

    func testThumbnailCacheIdentityIncludesVisualStyle() {
        XCTAssertNotEqual(
            HistoryThumbnailCache.cacheIdentity(
                dayKey: "2026-09-06",
                style: .legacy
            ),
            HistoryThumbnailCache.cacheIdentity(
                dayKey: "2026-09-06",
                style: .editorial
            )
        )
    }

    func testExportRouteUsesSavedCanvasVisualStyle() {
        var legacyCanvas = DayCanvas(dayKey: "2026-09-05")
        legacyCanvas.visualStyleRaw = CanvasVisualStyle.legacy.rawValue
        var editorialCanvas = DayCanvas(dayKey: "2026-09-06")
        editorialCanvas.visualStyleRaw = CanvasVisualStyle.editorial.rawValue

        XCTAssertEqual(CanvasExportRoute(canvas: legacyCanvas), .legacySwiftUI)
        XCTAssertEqual(CanvasExportRoute(canvas: editorialCanvas), .editorialMetal)
    }

    func testEditorialReusesStableLegacySmudgeSourceWithoutConstructingLegacyArtwork() {
        let policy = DayCanvasArtworkLayerPolicy(style: .editorial)

        XCTAssertTrue(policy.usesEditorial)
        XCTAssertFalse(policy.usesLegacyBackground)
        XCTAssertFalse(policy.usesRasterTexture)
        XCTAssertTrue(policy.usesInteractiveAnimationOverlay)
        XCTAssertEqual(policy.animationSnapshotSource, .legacySwiftUI)
    }

    func testLegacyKeepsExistingLayers() {
        let policy = DayCanvasArtworkLayerPolicy(style: .legacy)

        XCTAssertFalse(policy.usesEditorial)
        XCTAssertTrue(policy.usesLegacyBackground)
        XCTAssertTrue(policy.usesRasterTexture)
        XCTAssertTrue(policy.usesInteractiveAnimationOverlay)
        XCTAssertEqual(policy.animationSnapshotSource, .legacySwiftUI)
    }
}
