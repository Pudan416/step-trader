import XCTest
@testable import Steps4

@MainActor
final class CanvasOnboardingStateTests: XCTestCase {
    private func withDefaults(_ test: (UserDefaults) throws -> Void) throws {
        let suiteName = "CanvasOnboardingStateTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        try test(defaults)
    }

    func testFreshInstallClaimsAutomaticStartOnceWithoutCompleting() throws {
        try withDefaults { defaults in
            let state = CanvasOnboardingState(defaults: defaults)
            XCTAssertFalse(state.isCompleted)
            XCTAssertTrue(state.claimAutomaticStart())
            XCTAssertFalse(state.claimAutomaticStart())
            XCTAssertNil(defaults.object(forKey: "onboarding_state_v1"))
            // Dismissing or abandoning the tour does not persist completion.
            XCTAssertTrue(CanvasOnboardingState(defaults: defaults).claimAutomaticStart())
        }
    }

    func testCompletionPersistsAndPreventsFutureAutomaticStart() throws {
        try withDefaults { defaults in
            let state = CanvasOnboardingState(defaults: defaults)
            state.complete()
            state.complete()
            XCTAssertTrue(state.isCompleted)
            XCTAssertFalse(state.claimAutomaticStart())
            XCTAssertEqual(defaults.integer(forKey: "onboarding_state_v1"), 1)
            let nextLaunch = CanvasOnboardingState(defaults: defaults)
            XCTAssertTrue(nextLaunch.isCompleted)
            XCTAssertFalse(nextLaunch.claimAutomaticStart())
        }
    }

    func testLegacyCompletionMigratesBothSupportedCompletionPaths() throws {
        for legacyKeys in [["hasCompletedOnboarding_v1"], ["hasSeenIntro_v3", "hasSeenEnergySetup_v1"]] {
            try withDefaults { defaults in
                legacyKeys.forEach { defaults.set(true, forKey: $0) }
                let state = CanvasOnboardingState(defaults: defaults)
                XCTAssertTrue(state.isCompleted)
                XCTAssertFalse(state.claimAutomaticStart())
                XCTAssertEqual(defaults.integer(forKey: "onboarding_state_v1"), 1)
                legacyKeys.forEach { XCTAssertTrue(defaults.bool(forKey: $0)) }
            }
        }
    }

    func testPartialLegacyProgressDoesNotCountAsCompletion() throws {
        for legacyKey in ["hasSeenIntro_v3", "hasSeenEnergySetup_v1", "hasMigratedOnboarding_v1", "shouldStartCoachMark"] {
            try withDefaults { defaults in
                defaults.set(true, forKey: legacyKey)
                let state = CanvasOnboardingState(defaults: defaults)
                XCTAssertFalse(state.isCompleted)
                XCTAssertTrue(state.claimAutomaticStart())
            }
        }
    }

    func testResetClearsOnlyOnboardingAndNeedsNewProcessForAutomaticStart() throws {
        try withDefaults { defaults in
            defaults.set(1, forKey: "onboarding_state_v1")
            let legacyKeys = ["hasCompletedOnboarding_v1", "hasSeenIntro_v3",
                              "hasSeenEnergySetup_v1", "hasMigratedOnboarding_v1", "shouldStartCoachMark"]
            legacyKeys.forEach { defaults.set(true, forKey: $0) }
            let savedCanvas = Data([1, 2, 3, 4])
            defaults.set(savedCanvas, forKey: "savedCanvas")
            defaults.set("account-id", forKey: "accountIdentity")
            defaults.set(9, forKey: "appLaunchCount")
            defaults.set(true, forKey: "hasCompletedInitialRestore")
            let state = CanvasOnboardingState(defaults: defaults)
            state.resetForFirstLaunchTest()
            XCTAssertFalse(state.isCompleted)
            XCTAssertFalse(state.claimAutomaticStart())
            (legacyKeys + ["onboarding_state_v1"]).forEach { XCTAssertNil(defaults.object(forKey: $0)) }
            XCTAssertEqual(defaults.data(forKey: "savedCanvas"), savedCanvas)
            XCTAssertEqual(defaults.string(forKey: "accountIdentity"), "account-id")
            XCTAssertEqual(defaults.integer(forKey: "appLaunchCount"), 9)
            XCTAssertTrue(defaults.bool(forKey: "hasCompletedInitialRestore"))
            let nextLaunch = CanvasOnboardingState(defaults: defaults)
            XCTAssertFalse(nextLaunch.isCompleted)
            XCTAssertTrue(nextLaunch.claimAutomaticStart())
        }
    }

    func testResetDuringPendingFirstStartupSuppressesDelayedAutomaticStart() {
        let state = CanvasOnboardingState(defaults: nil)
        state.resetForFirstLaunchTest()
        XCTAssertFalse(state.claimAutomaticStart())
    }

    func testNilDefaultsFixtureRetainsOnlyInMemoryLifecycle() {
        let state = CanvasOnboardingState(defaults: nil)
        XCTAssertTrue(state.claimAutomaticStart())
        state.complete()
        XCTAssertTrue(state.isCompleted)
        XCTAssertFalse(state.claimAutomaticStart())
        XCTAssertFalse(CanvasOnboardingState(defaults: nil).isCompleted)
    }
}
