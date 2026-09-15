import XCTest
@testable import Steps4

final class FeatureTipPolicyTests: XCTestCase {
    private var defaults: UserDefaults!
    private var store: FeatureTipStore!
    private var suite: String!
    private let start = Date(timeIntervalSince1970: 1_800_000_000)
    private func day(_ n: Int) -> Date { start.addingTimeInterval(Double(n) * 86_400) }

    override func setUp() {
        super.setUp()
        suite = "FeatureTipPolicyTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)!
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        store = FeatureTipStore(defaults: defaults, calendar: calendar)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suite)
        store = nil
        defaults = nil
        super.tearDown()
    }

    private func eligible(_ tip: FeatureTip = .widgets, at date: Date, launches: Int = 20,
                          canvas: Bool = true, used: Bool = false) -> Bool {
        store.isEligible(tip, launchCount: launches, hasCanvas: canvas, featureUsed: used, now: date)
    }

    private func snooze() {
        store.recordPresentation(.widgets, now: start)
        store.recordDismissal(.widgets, now: start)
    }

    func testFirstOfferRespectsLaunchThresholdAndWallpaperRequiresCanvas() {
        XCTAssertFalse(eligible(at: start, launches: 4))
        XCTAssertTrue(eligible(at: start, launches: 5))
        XCTAssertFalse(eligible(.wallpaper, at: start, launches: 6))
        XCTAssertFalse(eligible(.wallpaper, at: start, launches: 7, canvas: false))
        XCTAssertTrue(eligible(.wallpaper, at: start, launches: 7))
    }

    func testSnoozeRequiresBothAWeekAndThreeSubsequentCanvasDays() {
        snooze()
        store.recordCanvasUse(now: day(1))
        store.recordCanvasUse(now: day(2))
        XCTAssertFalse(eligible(at: day(8)))
        store.recordCanvasUse(now: day(3))
        XCTAssertFalse(eligible(at: day(7).addingTimeInterval(-1)))
        XCTAssertTrue(eligible(at: day(7)))
    }

    func testRepeatedVisitsAndDismissalDayDoNotInflateCanvasDays() {
        store.recordCanvasUse(now: day(-1))
        snooze()
        store.recordCanvasUse(now: start.addingTimeInterval(60))
        for _ in 0..<10 { store.recordCanvasUse(now: day(1)) }
        store.recordCanvasUse(now: day(2))
        XCTAssertFalse(eligible(at: day(9)))
        store.recordCanvasUse(now: day(3))
        XCTAssertTrue(eligible(at: day(9)))
    }

    func testOnlyOneRepeatSurvivesRelaunch() {
        snooze()
        for n in 1...3 { store.recordCanvasUse(now: day(n)) }
        store.recordPresentation(.widgets, now: day(7))
        store.recordDismissal(.widgets, now: day(7))
        for n in 8...12 { store.recordCanvasUse(now: day(n)) }
        store = FeatureTipStore(defaults: defaults)
        XCTAssertFalse(eligible(at: day(40)))
    }

    func testSnoozeAndCanvasDaysPersistAcrossRelaunch() {
        snooze()
        for n in 1...3 { store.recordCanvasUse(now: day(n)) }
        store = FeatureTipStore(defaults: defaults)
        XCTAssertTrue(eligible(at: day(7)))
    }

    func testGlobalCooldownAppliesAcrossTipsAndReviewRequests() {
        store.recordPresentation(.widgets, now: start)
        XCTAssertFalse(eligible(.wallpaper, at: day(2).addingTimeInterval(-1)))
        XCTAssertTrue(eligible(.wallpaper, at: day(2)))
        store.recordReviewRequest(now: day(2))
        XCTAssertFalse(eligible(.wallpaper, at: day(3)))
        XCTAssertFalse(store.canPresentPrompt(now: day(4).addingTimeInterval(-1)))
        XCTAssertTrue(eligible(.wallpaper, at: day(4)))
    }

    func testAcceptedOrAlreadyUsedFeatureIsNotOfferedAgain() {
        XCTAssertFalse(eligible(at: start, used: true))
        store.recordPresentation(.widgets, now: start)
        store.recordAcceptance(.widgets)
        // A following sheet dismissal must not convert acceptance to snoozing.
        store.recordDismissal(.widgets, now: start)
        for n in 1...3 { store.recordCanvasUse(now: day(n)) }
        XCTAssertFalse(eligible(at: day(10)))
        XCTAssertTrue(eligible(.wallpaper, at: day(10)))
    }

    func testPresentationWithoutExplicitDismissalRecoversAsSnoozedAfterTermination() {
        store.recordPresentation(.widgets, now: start)
        for n in 1...3 { store.recordCanvasUse(now: day(n)) }
        store = FeatureTipStore(defaults: defaults)
        XCTAssertTrue(eligible(at: day(7)))
    }

    func testOldSeenFlagsStayDismissedAndDoNotSuppressOtherTip() {
        defaults.set(true, forKey: "featureTipSeen_widgets_v1")
        XCTAssertFalse(eligible(at: day(20)))
        XCTAssertTrue(eligible(.wallpaper, at: day(20)))
    }

    func testUnknownOldStateDoesNotResetSeenUsersDuringMigration() {
        defaults.set(true, forKey: "featureTipSeen_wallpaper_v1")
        store.recordPresentation(.widgets, now: start)
        XCTAssertFalse(eligible(.wallpaper, at: day(20)))
    }
}
