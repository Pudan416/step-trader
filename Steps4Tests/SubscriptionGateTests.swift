import XCTest
@testable import Steps4

/// The app is free: every gate answers yes for every input, including the
/// `isPro: false` case that used to be the restricted path. These tests exist
/// so a future reintroduction of gating has to break something visible.
final class SubscriptionGateTests: XCTestCase {

    func testBlockingGroupsAreUnlimited() {
        for isPro in [true, false] {
            for count in 0...10 {
                XCTAssertTrue(
                    SubscriptionGate.canAddBlockingGroup(isPro: isPro, currentCount: count),
                    "count \(count), isPro \(isPro)"
                )
            }
        }
    }

    func testEveryFeatureGateAnswersYes() {
        for isPro in [true, false] {
            XCTAssertTrue(SubscriptionGate.canCreateCustomActivity(isPro: isPro))
            XCTAssertTrue(SubscriptionGate.canAddMoment(isPro: isPro))
            XCTAssertTrue(SubscriptionGate.canUseDailyRandomTheme(isPro: isPro))
            XCTAssertTrue(SubscriptionGate.canCustomizeShapes(isPro: isPro))
        }
    }

    func testEveryVisualOptionIsAvailable() {
        for isPro in [true, false] {
            for palette in ["warmSunset", "ocean", "aurora", "dusk", "dawn", "ember", "horizon", "coolOcean"] {
                XCTAssertTrue(SubscriptionGate.isGradientPaletteAvailable(isPro: isPro, paletteRaw: palette))
            }
            for style in ["radial", "linear", "angular"] {
                XCTAssertTrue(SubscriptionGate.isGradientStyleAvailable(isPro: isPro, styleRaw: style))
            }
            for texture in ["none", "grain", "glass", "plastic"] {
                XCTAssertTrue(SubscriptionGate.isCanvasTextureAvailable(isPro: isPro, textureRaw: texture))
            }
        }
    }
}
