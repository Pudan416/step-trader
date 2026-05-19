import XCTest
import HealthKit
@testable import Steps4

// MARK: - Parameterized Mock (P14)

final class ConfigurableHealthKitMock: HealthKitServiceProtocol {
    var stepsToReturn: Double = 0
    var sleepToReturn: Double = 0
    var stepsError: Error?
    var sleepError: Error?
    var authStatus: HKAuthorizationStatus = .sharingAuthorized
    var sleepAuthStatus: HKAuthorizationStatus = .sharingAuthorized
    var authorizationRequested = false
    var observerStarted = false
    var observerStopped = false
    private var observerHandler: ((Double) -> Void)?

    func fetchSleep(from: Date, to: Date) async throws -> Double {
        if let error = sleepError { throw error }
        return sleepToReturn
    }

    @MainActor func requestAuthorization() async throws {
        authorizationRequested = true
    }

    @MainActor func authorizationStatus() -> HKAuthorizationStatus {
        authStatus
    }

    @MainActor func sleepAuthorizationStatus() -> HKAuthorizationStatus {
        sleepAuthStatus
    }

    func fetchSteps(from: Date, to: Date) async throws -> Double {
        if let error = stepsError { throw error }
        return stepsToReturn
    }

    func startObservingSteps(updateHandler: @escaping (Double) -> Void) {
        observerStarted = true
        observerHandler = updateHandler
    }

    func fetchWorkouts(from: Date, to: Date) async throws -> [DetectedWorkout] { [] }

    func fetchMindfulMinutes(from: Date, to: Date) async throws -> Double { 0 }

    func stopObservingSteps() {
        observerStopped = true
        observerHandler = nil
    }

    /// Simulate a step observation update (for testing the callback path).
    func simulateStepUpdate(_ steps: Double) {
        observerHandler?(steps)
    }
}

// MARK: - Interval Merging Tests (P8)

final class SleepIntervalMergingTests: XCTestCase {

    private func date(_ hour: Int, _ minute: Int = 0) -> Date {
        var comps = DateComponents()
        comps.year = 2026
        comps.month = 2
        comps.day = 17
        comps.hour = hour
        comps.minute = minute
        return Calendar.current.date(from: comps)!
    }

    func testEmptyIntervals() {
        let result = HealthKitService.mergedDuration(of: [])
        XCTAssertEqual(result, 0)
    }

    func testSingleInterval() {
        // 23:00 to 07:00 next day — but since we use same-day dates, end < start.
        // Use proper dates instead.
        let start = date(1)
        let end = date(8)
        let result = HealthKitService.mergedDuration(of: [(start: start, end: end)])
        XCTAssertEqual(result, 7 * 3600, accuracy: 1)
    }

    func testNonOverlappingIntervals() {
        // Two separate sleep sessions: 23:00-02:00 and 04:00-07:00
        let intervals = [
            (start: date(0), end: date(2)),
            (start: date(4), end: date(7))
        ]
        let result = HealthKitService.mergedDuration(of: intervals)
        // 2h + 3h = 5h
        XCTAssertEqual(result, 5 * 3600, accuracy: 1)
    }

    func testFullyOverlappingIntervals() {
        // Watch: 23:00-07:00 and Phone: 00:00-06:00 (fully contained)
        let intervals = [
            (start: date(0), end: date(7)),
            (start: date(1), end: date(6))
        ]
        let result = HealthKitService.mergedDuration(of: intervals)
        // Should merge to 0:00-7:00 = 7h, NOT 7+5=12h
        XCTAssertEqual(result, 7 * 3600, accuracy: 1)
    }

    func testPartiallyOverlappingIntervals() {
        // Watch: 23:00-05:00 and Phone: 03:00-07:00
        let intervals = [
            (start: date(0), end: date(5)),
            (start: date(3), end: date(7))
        ]
        let result = HealthKitService.mergedDuration(of: intervals)
        // Merges to 0:00-7:00 = 7h, NOT 5+4=9h
        XCTAssertEqual(result, 7 * 3600, accuracy: 1)
    }

    func testAdjacentIntervals() {
        // Core: 00:00-03:00, REM: 03:00-04:00, Deep: 04:00-06:00
        let intervals = [
            (start: date(0), end: date(3)),
            (start: date(3), end: date(4)),
            (start: date(4), end: date(6))
        ]
        let result = HealthKitService.mergedDuration(of: intervals)
        // Adjacent intervals merge to 0:00-6:00 = 6h
        XCTAssertEqual(result, 6 * 3600, accuracy: 1)
    }

    func testUnsortedIntervals() {
        // Input out of order — should still merge correctly
        let intervals = [
            (start: date(4), end: date(7)),
            (start: date(0), end: date(5))
        ]
        let result = HealthKitService.mergedDuration(of: intervals)
        // Merges to 0:00-7:00 = 7h
        XCTAssertEqual(result, 7 * 3600, accuracy: 1)
    }

    func testManySourcesOverlapping() {
        // Simulating Watch Core + Watch REM + Watch Deep + Phone asleep all overlapping
        let intervals = [
            (start: date(0), end: date(2)),    // Core
            (start: date(2), end: date(4)),    // REM
            (start: date(1), end: date(5)),    // Phone asleep (overlaps both)
            (start: date(4, 30), end: date(7)) // Deep (4:30 < 5:00 so still overlaps)
        ]
        let result = HealthKitService.mergedDuration(of: intervals)
        // Sorted: (0-2), (1-5), (2-4), (4:30-7) → all merge to 0:00-7:00 = 7h
        XCTAssertEqual(result, 7 * 3600, accuracy: 1)
    }
}

// MARK: - HealthStore Tests (P13)

@MainActor
final class HealthStoreTests: XCTestCase {
    private var mock: ConfigurableHealthKitMock!
    private var store: HealthStore!
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        mock = ConfigurableHealthKitMock()
        store = HealthStore(healthKitService: mock)
        defaults = UserDefaults.stepsTrader()
        // Clear cached values
        defaults.removeObject(forKey: SharedKeys.cachedStepsToday)
        defaults.removeObject(forKey: SharedKeys.hasStepsData)
    }

    override func tearDown() {
        defaults.removeObject(forKey: SharedKeys.cachedStepsToday)
        defaults.removeObject(forKey: SharedKeys.hasStepsData)
        super.tearDown()
    }

    // MARK: - Step fetching

    func testRefreshStepsSetsStepsAndFlag() async {
        mock.stepsToReturn = 5432
        await store.refreshStepsIfAuthorized()

        XCTAssertEqual(store.stepsToday, 5432)
        XCTAssertTrue(store.hasStepsData)
    }

    /// Read-only HealthKit apps keep `.notDetermined` write status after the user allows reads.
    /// HealthKitService must still run queries (regression: guard on `.notDetermined` returned 0 steps).
    func testRefreshStepsWhenWriteStatusNotDetermined() async {
        mock.authStatus = .notDetermined
        mock.stepsToReturn = 9999
        await store.refreshStepsIfAuthorized()

        XCTAssertEqual(store.stepsToday, 9999)
        XCTAssertTrue(store.hasStepsData)
    }

    func testRefreshStepsZeroIsValid() async {
        mock.stepsToReturn = 0
        await store.refreshStepsIfAuthorized()

        XCTAssertEqual(store.stepsToday, 0)
        XCTAssertTrue(store.hasStepsData, "Zero steps should still mark hasStepsData = true")
    }

    func testRefreshStepsCachesValue() async {
        mock.stepsToReturn = 8000
        await store.refreshStepsIfAuthorized()

        let cached = defaults.double(forKey: SharedKeys.cachedStepsToday)
        XCTAssertEqual(cached, 8000)
        XCTAssertTrue(defaults.bool(forKey: SharedKeys.hasStepsData))
    }

    func testRefreshStepsFallsBackToCacheOnError() async {
        // First: cache a value
        mock.stepsToReturn = 3000
        await store.refreshStepsIfAuthorized()

        // Now: fail the next fetch
        mock.stepsError = NSError(domain: "test", code: 99)
        let newStore = HealthStore(healthKitService: mock)
        await newStore.refreshStepsIfAuthorized()

        // Should fall back to cached value
        XCTAssertEqual(newStore.stepsToday, 3000)
    }

    // MARK: - Sleep fetching

    func testRefreshSleepSetsSleepAndFlag() async {
        mock.sleepToReturn = 7.5
        await store.refreshSleepIfAuthorized()

        XCTAssertEqual(store.dailySleepHours, 7.5, accuracy: 0.01)
        XCTAssertTrue(store.hasSleepData)
    }

    func testRefreshSleepErrorDoesNotCrash() async {
        mock.sleepError = NSError(domain: "test", code: 42)
        await store.refreshSleepIfAuthorized()

        XCTAssertEqual(store.dailySleepHours, 0)
        XCTAssertFalse(store.hasSleepData)
    }

    // MARK: - Authorization status

    func testAuthStatusNotDetermined() {
        mock.authStatus = .notDetermined
        let newStore = HealthStore(healthKitService: mock)
        XCTAssertEqual(newStore.authorizationStatus, .notDetermined)
    }

    func testAuthStatusSharingDenied() {
        mock.authStatus = .sharingDenied
        let newStore = HealthStore(healthKitService: mock)
        XCTAssertEqual(newStore.authorizationStatus, .sharingDenied)
    }

    func testAuthStatusSharingAuthorized() {
        mock.authStatus = .sharingAuthorized
        let newStore = HealthStore(healthKitService: mock)
        XCTAssertEqual(newStore.authorizationStatus, .sharingAuthorized)
    }

    // MARK: - Observation

    func testStartObservingCallsMock() {
        store.startObservingSteps()
        XCTAssertTrue(mock.observerStarted)
    }

    func testStopObservingCallsMock() {
        store.startObservingSteps()
        store.stopObservingSteps()
        XCTAssertTrue(mock.observerStopped)
    }

    func testObserverCallbackUpdatesStore() async {
        store.startObservingSteps()
        mock.simulateStepUpdate(12345)

        // Give the MainActor task a moment to process
        try? await Task.sleep(nanoseconds: 100_000_000)

        XCTAssertEqual(store.stepsToday, 12345)
        XCTAssertTrue(store.hasStepsData)
    }
}
