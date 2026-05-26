import XCTest
@testable import Steps4

final class SubscriptionStateTests: XCTestCase {

    // MARK: - SubscriptionState.isPro matrix

    func testIsPro_unknown() {
        XCTAssertFalse(SubscriptionState.unknown.isPro)
    }

    func testIsPro_free() {
        XCTAssertFalse(SubscriptionState.free.isPro)
    }

    func testIsPro_grandfathered() {
        XCTAssertTrue(SubscriptionState.grandfathered.isPro)
    }

    func testIsPro_lifetime() {
        XCTAssertTrue(SubscriptionState.lifetime(productId: "pro_lifetime").isPro)
    }

    func testIsPro_subscribed() {
        XCTAssertTrue(SubscriptionState.subscribed(
            productId: "pro_monthly",
            willRenew: true,
            expiresAt: Date().addingTimeInterval(86400)
        ).isPro)
    }

    func testIsPro_subscribedNotRenewing() {
        XCTAssertTrue(SubscriptionState.subscribed(
            productId: "pro_annual",
            willRenew: false,
            expiresAt: Date().addingTimeInterval(86400)
        ).isPro)
    }

    func testIsPro_loadingFromCacheTrue() {
        XCTAssertTrue(SubscriptionState.loadingFromCache(isPro: true).isPro)
    }

    func testIsPro_loadingFromCacheFalse() {
        XCTAssertFalse(SubscriptionState.loadingFromCache(isPro: false).isPro)
    }

    // MARK: - SubscriptionStore init from defaults

    @MainActor
    func testInit_grandfatheredFromDefaults() {
        let defaults = UserDefaults(suiteName: "SubscriptionStoreTests_gf")!
        defer { defaults.removePersistentDomain(forName: "SubscriptionStoreTests_gf") }
        defaults.set(true, forKey: SharedKeys.isGrandfathered)

        let store = SubscriptionStore(defaults: defaults)

        XCTAssertEqual(store.state, .grandfathered)
        XCTAssertTrue(store.isPro)
    }

    @MainActor
    func testInit_cachedProFromDefaults() {
        let defaults = UserDefaults(suiteName: "SubscriptionStoreTests_cp")!
        defer { defaults.removePersistentDomain(forName: "SubscriptionStoreTests_cp") }
        defaults.set(true, forKey: SharedKeys.cachedHasProEntitlement)

        let store = SubscriptionStore(defaults: defaults)

        XCTAssertTrue(store.isPro, "Optimistically Pro from cache")
    }

    @MainActor
    func testInit_freshInstallDefaults() {
        let defaults = UserDefaults(suiteName: "SubscriptionStoreTests_fi")!
        defer { defaults.removePersistentDomain(forName: "SubscriptionStoreTests_fi") }

        let store = SubscriptionStore(defaults: defaults)

        XCTAssertEqual(store.state, .unknown)
        XCTAssertFalse(store.state.isPro)
    }

    @MainActor
    func testInit_grandfatheredTakesPriorityOverCache() {
        let defaults = UserDefaults(suiteName: "SubscriptionStoreTests_pr")!
        defer { defaults.removePersistentDomain(forName: "SubscriptionStoreTests_pr") }
        defaults.set(true, forKey: SharedKeys.isGrandfathered)
        defaults.set(true, forKey: SharedKeys.cachedHasProEntitlement)

        let store = SubscriptionStore(defaults: defaults)

        XCTAssertEqual(store.state, .grandfathered,
                       "Grandfathered is permanent; cache is secondary")
    }
}
