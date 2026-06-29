import XCTest
@testable import Steps4

final class SubscriptionGateTests: XCTestCase {
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        defaults = UserDefaults(suiteName: "SubscriptionGateTests")!
        defaults.removePersistentDomain(forName: "SubscriptionGateTests")
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: "SubscriptionGateTests")
        super.tearDown()
    }

    // MARK: - Blocking Groups

    func testCanAddBlockingGroup_proAlwaysTrue() {
        for count in 0...5 {
            XCTAssertTrue(SubscriptionGate.canAddBlockingGroup(isPro: true, currentCount: count))
        }
    }

    func testCanAddBlockingGroup_freeBelowLimit() {
        XCTAssertTrue(SubscriptionGate.canAddBlockingGroup(isPro: false, currentCount: 0))
        XCTAssertTrue(SubscriptionGate.canAddBlockingGroup(isPro: false, currentCount: 1))
    }

    func testCanAddBlockingGroup_freeAtLimit() {
        XCTAssertFalse(SubscriptionGate.canAddBlockingGroup(isPro: false, currentCount: 2))
        XCTAssertFalse(SubscriptionGate.canAddBlockingGroup(isPro: false, currentCount: 5))
    }

    // MARK: - Custom Card

    func testCanCreateCustomActivity_proBypasses() {
        XCTAssertTrue(SubscriptionGate.canCreateCustomActivity(isPro: true))
    }

    func testCanCreateCustomActivity_freeBlocked() {
        XCTAssertFalse(SubscriptionGate.canCreateCustomActivity(isPro: false))
    }

    // MARK: - Daily Random Theme (free for everyone)

    func testCanUseDailyRandomTheme_proBypasses() {
        XCTAssertTrue(SubscriptionGate.canUseDailyRandomTheme(isPro: true))
    }

    func testCanUseDailyRandomTheme_freeAllowed() {
        XCTAssertTrue(SubscriptionGate.canUseDailyRandomTheme(isPro: false))
    }

    // MARK: - Custom Shapes (free for everyone)

    func testCanCustomizeShapes_proBypasses() {
        XCTAssertTrue(SubscriptionGate.canCustomizeShapes(isPro: true))
    }

    func testCanCustomizeShapes_freeAllowed() {
        XCTAssertTrue(SubscriptionGate.canCustomizeShapes(isPro: false))
    }

    // MARK: - Gradient Gates (all palettes/styles free for everyone)

    func testIsGradientPaletteAvailable_proAll() {
        XCTAssertTrue(SubscriptionGate.isGradientPaletteAvailable(isPro: true, paletteRaw: "anything"))
    }

    func testIsGradientPaletteAvailable_freeAll() {
        for palette in ["warmSunset", "ocean", "aurora", "dusk", "dawn", "ember", "horizon", "coolOcean"] {
            XCTAssertTrue(SubscriptionGate.isGradientPaletteAvailable(isPro: false, paletteRaw: palette))
        }
    }

    func testIsGradientStyleAvailable_proAll() {
        XCTAssertTrue(SubscriptionGate.isGradientStyleAvailable(isPro: true, styleRaw: "anything"))
    }

    func testIsGradientStyleAvailable_freeAll() {
        for style in ["radial", "linear", "angular"] {
            XCTAssertTrue(SubscriptionGate.isGradientStyleAvailable(isPro: false, styleRaw: style))
        }
    }

    // MARK: - Post-Onboarding Paywall

    func testShouldShowPostOnboardingPaywall_proNever() {
        XCTAssertFalse(SubscriptionGate.shouldShowPostOnboardingPaywall(isPro: true, defaults: defaults))
    }

    func testShouldShowPostOnboardingPaywall_freeFirstTime() {
        XCTAssertTrue(SubscriptionGate.shouldShowPostOnboardingPaywall(isPro: false, defaults: defaults))
    }

    func testShouldShowPostOnboardingPaywall_freeAfterMarked() {
        SubscriptionGate.markPostOnboardingPaywallShown(defaults: defaults)
        XCTAssertFalse(SubscriptionGate.shouldShowPostOnboardingPaywall(isPro: false, defaults: defaults))
    }

    func testMarkPostOnboardingPaywall_idempotent() {
        SubscriptionGate.markPostOnboardingPaywallShown(defaults: defaults)
        SubscriptionGate.markPostOnboardingPaywallShown(defaults: defaults)
        XCTAssertFalse(SubscriptionGate.shouldShowPostOnboardingPaywall(isPro: false, defaults: defaults))
    }
}
