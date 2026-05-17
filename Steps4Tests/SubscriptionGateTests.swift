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

    func testCanAddBlockingGroup_freeAtZero() {
        XCTAssertTrue(SubscriptionGate.canAddBlockingGroup(isPro: false, currentCount: 0))
    }

    func testCanAddBlockingGroup_freeAtLimit() {
        XCTAssertFalse(SubscriptionGate.canAddBlockingGroup(isPro: false, currentCount: 1))
        XCTAssertFalse(SubscriptionGate.canAddBlockingGroup(isPro: false, currentCount: 5))
    }

    // MARK: - Custom Activity

    func testCanCreateCustomActivity_proBypasses() {
        XCTAssertTrue(SubscriptionGate.canCreateCustomActivity(isPro: true))
    }

    func testCanCreateCustomActivity_freeBlocked() {
        XCTAssertFalse(SubscriptionGate.canCreateCustomActivity(isPro: false))
    }

    // MARK: - Daily Random Theme

    func testCanUseDailyRandomTheme_proBypasses() {
        XCTAssertTrue(SubscriptionGate.canUseDailyRandomTheme(isPro: true))
    }

    func testCanUseDailyRandomTheme_freeBlocked() {
        XCTAssertFalse(SubscriptionGate.canUseDailyRandomTheme(isPro: false))
    }

    // MARK: - Custom Shapes

    func testCanCustomizeShapes_proBypasses() {
        XCTAssertTrue(SubscriptionGate.canCustomizeShapes(isPro: true))
    }

    func testCanCustomizeShapes_freeBlocked() {
        XCTAssertFalse(SubscriptionGate.canCustomizeShapes(isPro: false))
    }

    // MARK: - Gradient Gates

    func testIsGradientPaletteAvailable_proAll() {
        XCTAssertTrue(SubscriptionGate.isGradientPaletteAvailable(isPro: true, paletteRaw: "anything"))
    }

    func testIsGradientPaletteAvailable_freeOnlyWarmSunset() {
        XCTAssertTrue(SubscriptionGate.isGradientPaletteAvailable(isPro: false, paletteRaw: "warmSunset"))
        XCTAssertFalse(SubscriptionGate.isGradientPaletteAvailable(isPro: false, paletteRaw: "coolOcean"))
    }

    func testIsGradientStyleAvailable_proAll() {
        XCTAssertTrue(SubscriptionGate.isGradientStyleAvailable(isPro: true, styleRaw: "anything"))
    }

    func testIsGradientStyleAvailable_freeRadialAndLinear() {
        XCTAssertTrue(SubscriptionGate.isGradientStyleAvailable(isPro: false, styleRaw: "radial"))
        XCTAssertTrue(SubscriptionGate.isGradientStyleAvailable(isPro: false, styleRaw: "linear"))
        XCTAssertFalse(SubscriptionGate.isGradientStyleAvailable(isPro: false, styleRaw: "angular"))
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
