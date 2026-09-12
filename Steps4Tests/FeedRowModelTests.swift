import XCTest
import SwiftUI
@testable import Steps4

final class FeedRowModelTests: XCTestCase {

    // MARK: - Icon source

    func testRegistryAppUsesBundledAsset() {
        XCTAssertEqual(
            FeedRowModel.iconSource(forBundleId: "com.burbn.instagram"),
            .asset("instagram")
        )
    }

    func testUnknownAppFallsBackToSystemLabel() {
        XCTAssertEqual(
            FeedRowModel.iconSource(forBundleId: "com.example.unknown"),
            .systemLabel
        )
    }

    func testNilBundleIdFallsBackToSystemLabel() {
        XCTAssertEqual(FeedRowModel.iconSource(forBundleId: nil), .systemLabel)
    }

    // MARK: - Row kind

    func testSingleAppGroupRendersAsPlainIcon() {
        let kind = FeedRowModel.kind(templateApp: "com.burbn.instagram", appTokenCount: 1)
        XCTAssertEqual(kind, .single(.asset("instagram")))
    }

    func testTemplateGroupWithNoTokensStillRendersAsSingle() {
        // Template groups are validated to exactly one app, but the token count
        // can read zero before the picker's selection has been persisted.
        let kind = FeedRowModel.kind(templateApp: "com.burbn.instagram", appTokenCount: 0)
        XCTAssertEqual(kind, .single(.asset("instagram")))
    }

    func testCustomGroupWithTwoAppsRendersAsCluster() {
        let kind = FeedRowModel.kind(templateApp: nil, appTokenCount: 2)
        XCTAssertEqual(kind, .cluster(sources: [.systemLabel, .systemLabel], total: 2))
    }

    func testClusterCapsRenderedIconsButKeepsTrueTotal() {
        let kind = FeedRowModel.kind(templateApp: nil, appTokenCount: 7)
        XCTAssertEqual(
            kind,
            .cluster(sources: Array(repeating: .systemLabel, count: FeedRowModel.clusterDisplayLimit), total: 7)
        )
    }

    func testCustomGroupWithOneAppRendersAsPlainIcon() {
        XCTAssertEqual(FeedRowModel.kind(templateApp: nil, appTokenCount: 1), .single(.systemLabel))
    }

    // MARK: - Access state

    func testZeroRemainingMinutesRendersLockedState() {
        XCTAssertEqual(
            FeedRowModel.accessState(remainingMinutes: 0, initialMinutes: 30),
            .locked
        )
    }

    func testFreshWindowFillsTheWholeRow() {
        XCTAssertEqual(
            FeedRowModel.accessState(remainingMinutes: 30, initialMinutes: 30),
            .active(remainingMinutes: 30, fillFraction: 1)
        )
    }

    func testSpentWindowUsesRemainingShareAsRowFill() {
        XCTAssertEqual(
            FeedRowModel.accessState(remainingMinutes: 18, initialMinutes: 30),
            .active(remainingMinutes: 18, fillFraction: 0.6)
        )
    }

    func testRemainingMinutesCannotOverfillTheRow() {
        XCTAssertEqual(
            FeedRowModel.accessState(remainingMinutes: 40, initialMinutes: 30),
            .active(remainingMinutes: 40, fillFraction: 1)
        )
    }

    func testMissingInitialBudgetTreatsCurrentValueAsFreshWindow() {
        XCTAssertEqual(
            FeedRowModel.accessState(remainingMinutes: 10, initialMinutes: 0),
            .active(remainingMinutes: 10, fillFraction: 1)
        )
    }

    // MARK: - Row action

    func testLockedRowOpensDurationPicker() {
        XCTAssertEqual(
            FeedRowModel.tapAction(for: .locked, canOpen: true),
            .chooseDuration
        )
    }

    func testActiveLaunchableRowOpensItsApp() {
        XCTAssertEqual(
            FeedRowModel.tapAction(
                for: .active(remainingMinutes: 18, fillFraction: 0.6),
                canOpen: true
            ),
            .openApp
        )
    }

    func testActiveCustomRowFallsBackToSettings() {
        XCTAssertEqual(
            FeedRowModel.tapAction(
                for: .active(remainingMinutes: 18, fillFraction: 0.6),
                canOpen: false
            ),
            .openSettings
        )
    }

    // MARK: - Ticket shape

    func testTicketShapeLeavesSpaceAroundContentWithModestCorners() {
        let bounds = CGRect(x: 0, y: 0, width: 320, height: 82)
        let path = FeedTicketShape().path(in: bounds)

        XCTAssertTrue(path.contains(CGPoint(x: 10, y: 10)), "Card corners should leave breathing room around the header")
        XCTAssertTrue(path.contains(CGPoint(x: 4, y: 41)))
    }

    func testTicketShapeKeepsTheTrailingMenuInsideTheCard() {
        let bounds = CGRect(x: 0, y: 0, width: 320, height: 82)
        let path = FeedTicketShape().path(in: bounds)

        XCTAssertTrue(
            path.contains(CGPoint(x: 300, y: 41)),
            "The reference uses an inset menu inside a continuous rounded card, not a cutout"
        )
    }

}

final class ResourceGradientLayoutTests: XCTestCase {

    func testDarkSideSpansTheWholeLeadingEdge() {
        let layout = ResourceGradientLayout.make(in: CGSize(width: 180, height: 82))

        XCTAssertGreaterThan(layout.progress(at: CGPoint(x: 0, y: 0)), 0.95)
        XCTAssertGreaterThan(layout.progress(at: CGPoint(x: 0, y: 41)), 0.95)
        XCTAssertGreaterThan(layout.progress(at: CGPoint(x: 0, y: 82)), 0.95)
    }

    func testCircularGradientTravelsFromRightToLeft() {
        let layout = ResourceGradientLayout.make(in: CGSize(width: 180, height: 82))

        XCTAssertLessThan(layout.progress(at: CGPoint(x: 180, y: 41)), 0.35)
        XCTAssertGreaterThan(layout.progress(at: CGPoint(x: 0, y: 41)), 0.95)
    }
}

final class FeedInlineExpansionTests: XCTestCase {

    func testTappingALockedGroupExpandsItsUnlockOptionsAndRequestsScroll() {
        let result = FeedInlineExpansion().toggling(groupID: "instagram")

        XCTAssertEqual(result.expandedGroupID, "instagram")
        XCTAssertEqual(result.scrollTargetID, "instagram-unlock-options")
    }

    func testTappingAnotherGroupMovesTheExpansion() {
        let current = FeedInlineExpansion(expandedGroupID: "instagram")

        let result = current.toggling(groupID: "youtube")

        XCTAssertEqual(result.expandedGroupID, "youtube")
        XCTAssertEqual(result.scrollTargetID, "youtube-unlock-options")
    }

    func testTappingTheExpandedGroupCollapsesIt() {
        let current = FeedInlineExpansion(expandedGroupID: "instagram")

        XCTAssertEqual(current.toggling(groupID: "instagram"), FeedInlineExpansion())
    }

    func testSuccessfulPurchaseCollapsesOnlyThePurchasedGroup() {
        let current = FeedInlineExpansion(expandedGroupID: "instagram")

        XCTAssertEqual(current.collapsing(groupID: "youtube"), current)
        XCTAssertEqual(current.collapsing(groupID: "instagram"), FeedInlineExpansion())
    }

    func testAutoScrollOnlyStartsWhenOptionsReachTheTabBar() {
        XCTAssertFalse(
            FeedInlineLayout.needsAutoScroll(
                optionsBottom: 450,
                viewportHeight: 640,
                tabBarHeight: 90
            )
        )
        XCTAssertTrue(
            FeedInlineLayout.needsAutoScroll(
                optionsBottom: 550,
                viewportHeight: 640,
                tabBarHeight: 90
            )
        )
    }
}

final class FeedCardLayoutTests: XCTestCase {

    func testExpandedCardAddsRoomForUnlockOptionsInsideItsSurface() {
        let collapsed = FeedCardLayout.height(showsUnlockOptions: false)
        let expanded = FeedCardLayout.height(showsUnlockOptions: true)

        XCTAssertGreaterThan(expanded - collapsed, 44)
    }

    func testUnlockCostUsesUnsignedAmountBesideCurrencySymbol() {
        XCTAssertEqual(FeedCardLayout.priceLabel(cost: 30), "30")
    }

    func testCircularFeedControlsShareTheMinimumTouchTarget() {
        XCTAssertEqual(
            FeedCardLayout.addControlDiameter,
            FeedCardLayout.optionsControlDiameter
        )
        XCTAssertGreaterThanOrEqual(FeedCardLayout.addControlDiameter, 44)
    }
}

@MainActor
final class FeedPigmentTests: XCTestCase {
    func testMenuInkFollowsPigmentAtEachDotBeforeFullWidthIsUnlocked() {
        let palette = TodayCanvasUnlockPalette(colors: [DayObjectRGB(hex: "#FFFFFF"), DayObjectRGB(hex: "#111111")])
        XCTAssertTrue(FeedPigment.menuUsesDarkInk(palette: palette, fraction: 28.0 / 30, position: 0.90))
        XCTAssertFalse(FeedPigment.menuUsesDarkInk(palette: palette, fraction: 0.85, position: 0.90))
        XCTAssertTrue(FeedPigment.menuUsesDarkInk(palette: palette, fraction: 0.91, position: 0.88))
        XCTAssertFalse(FeedPigment.menuUsesDarkInk(palette: palette, fraction: 0.91, position: 0.926))
    }

    func testRenderFeedStatesForVisualReview() async throws {
        let model = AppModel(healthKitService: MockHealthKitService(), familyControlsService: MockFamilyControlsService(),
                             notificationService: MockNotificationService(), budgetEngine: MockBudgetEngine(),
                             subscriptionStore: SubscriptionStore())
        model.stepsBalance = 48
        model.bonusSteps = 0
        let store = TodayCanvasBackdropStore(load: { _ in nil }, render: { _, _ in nil })
        let appearance = TodayCanvasAppearance(dayKey: "2026-09-07", steps: 15, sleep: 12, earned: 62, spent: 14,
            hasSteps: true, hasSleep: true, style: CanvasVisualStyle.editorial.rawValue,
            gradient: GradientStyle.radial.rawValue, palette: GradientPalette.warmSunset.rawValue,
            texture: CanvasTexture.grainSmall.rawValue, categories: "")
        store.refresh(appearance)
        for (width, textSize, label) in [(390.0, DynamicTypeSize.large, "locked"),
                                        (390.0, .large, "standard"),
                                        (320.0, .xxxLarge, "narrow-large"),
                                        (320.0, .accessibility3, "accessibility") ] {
            let locked = label == "locked"
            model.stepsBalance = locked ? 17 : 48
            let chrome = locked ? CanvasChromePalette.resolve(backgroundColors: [DayObjectRGB(hex: "#78966B")]) : store.chromePalette
            let content = VStack(spacing: 20) {
                row("Instagram", state: locked ? .locked : .active(remainingMinutes: 10, fillFraction: 1), model: model, backdrop: store, expanded: false)
                row("YouTube", state: locked ? .locked : .active(remainingMinutes: 22, fillFraction: 22.0 / 30), model: model, backdrop: store, expanded: locked)
                row("TikTok", state: .locked, model: model, backdrop: store, expanded: !locked)
            }
            .padding(20)
            .frame(width: width)
            .background(LinearGradient(colors: locked ? [Color(red: 0.85, green: 0.89, blue: 0.81)] : [Color(red: 0.55, green: 0.35, blue: 0.37), Color(red: 0.85, green: 0.55, blue: 0.45)],
                                       startPoint: .topLeading, endPoint: .bottomTrailing))
            .environment(\.dynamicTypeSize, textSize)
            .environment(\.appTheme, .night)
            .environment(\.canvasChromePalette, chrome)
            .preferredColorScheme(.dark)
            let host = UIHostingController(rootView: content)
            host.safeAreaRegions = []
            let size = host.sizeThatFits(in: CGSize(width: width, height: 4000))
            let window = UIWindow(frame: CGRect(origin: .zero, size: size))
            window.rootViewController = host
            window.makeKeyAndVisible()
            defer { window.isHidden = true }
            host.view.frame = window.bounds
            host.view.layoutIfNeeded()
            try await Task.sleep(for: .milliseconds(100))
            let format = UIGraphicsImageRendererFormat()
            format.scale = 2
            let image = UIGraphicsImageRenderer(size: size, format: format).image { _ in
                host.view.drawHierarchy(in: host.view.bounds, afterScreenUpdates: true)
            }
            XCTAssertEqual(image.size.width, width)
            let attachment = XCTAttachment(image: image)
            attachment.name = "feeds-soft-\(label)"
            attachment.lifetime = .keepAlways
            add(attachment)
        }
    }

    private func row(_ name: String, state: FeedRowAccessState, model: AppModel, backdrop: TodayCanvasBackdropStore, expanded: Bool) -> some View {
        FeedRowView(model: model,
                    group: TicketGroup(id: name, name: name, settings: .init(entryCostSteps: 10, dayPassCostSteps: 100)),
                    accessState: state, canOpen: true, showsUnlockOptions: expanded,
                    onTap: {}, onSettings: {}, onDelete: {}, onPurchased: {}, backdrop: backdrop)
    }

    func testProgressClipsColorInPlaceAndDoesNotRevealBackdropThroughPigment() throws {
        let palette = TodayCanvasUnlockPalette(colors: [DayObjectRGB(hex: "#F78870"), DayObjectRGB(hex: "#34245E")])
        func image(_ fraction: Double, _ background: Color) throws -> CGImage {
            let renderer = ImageRenderer(content: FeedProgressFill(palette: palette, fraction: fraction)
                .frame(width: 300, height: 80).background(background))
            renderer.scale = 1
            return try XCTUnwrap(renderer.cgImage)
        }
        let full = try image(1, .black)
        let partial = try image(0.6, .black)
        let onWhite = try image(1, .white)
        for x in [12, 80, 140] {
            XCTAssertEqual(pixel(full, x: x), pixel(partial, x: x), "Spending time must crop, not squeeze, the same daily gradient")
            XCTAssertEqual(pixel(full, x: x), pixel(onWhite, x: x), "The canvas behind the card must not wash out its fill")
        }
        XCTAssertEqual(pixel(partial, x: 220), [0, 0, 0, 255])
        XCTAssertNotEqual(pixel(full, x: 220), pixel(partial, x: 220))
    }

    func testAllDailyPalettesKeepWhiteLabelsReadableWithoutNeutralizingHue() {
        for palette in ModernPaletteCatalog.all {
            let source = TodayCanvasUnlockPalette(colors: palette.hexes.map { DayObjectRGB(hex: $0) })
            let stops = FeedPigment.stops(for: source)
            for stop in stops where stop.location <= FeedPigment.textEdge {
                XCTAssertGreaterThanOrEqual(contrastRatio(stop.color.linearRGB, SIMD3(repeating: 1)), 5.5, palette.code)
            }
            let brightest = source.colors.max { $0.perceptualOKLab.x < $1.perceptualOKLab.x }
            XCTAssertEqual(stops.last?.color, brightest, "The bright edge keeps the actual day's color")
        }
    }

    private func pixel(_ image: CGImage, x: Int) -> [UInt8] {
        var bytes = [UInt8](repeating: 0, count: 4)
        bytes.withUnsafeMutableBytes { storage in
            let context = CGContext(data: storage.baseAddress, width: 1, height: 1, bitsPerComponent: 8,
                                    bytesPerRow: 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            context.translateBy(x: -CGFloat(x), y: -40)
            context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        }
        return bytes
    }
}
