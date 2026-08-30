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
    var workoutsToReturn: [DetectedWorkout] = []
    var mindfulMinutesToReturn: Double = 0
    var workoutFetchCount = 0
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

    func fetchWorkouts(from: Date, to: Date) async throws -> [DetectedWorkout] {
        workoutFetchCount += 1
        return workoutsToReturn
    }

    func fetchMindfulMinutes(from: Date, to: Date) async throws -> Double {
        mindfulMinutesToReturn
    }

    func stopObservingSteps() {
        observerStopped = true
        observerHandler = nil
    }

    func clearLastStepCount() {}

    /// Simulate a step observation update (for testing the callback path).
    func simulateStepUpdate(_ steps: Double) {
        observerHandler?(steps)
    }
}

// MARK: - Activity Suggestions

@MainActor
final class HealthActivitySuggestionTests: XCTestCase {
    override func setUp() {
        super.setUp()
        let defaults = UserDefaults.stepsTrader()
        defaults.removeObject(forKey: SharedKeys.todayAdditions)
        defaults.removeObject(forKey: "dismissedSuggestionIds_v1")
    }

    override func tearDown() {
        let defaults = UserDefaults.stepsTrader()
        defaults.removeObject(forKey: SharedKeys.todayAdditions)
        defaults.removeObject(forKey: "dismissedSuggestionIds_v1")
        super.tearDown()
    }

    func testHealthWorkoutTypesHaveDistinctStableActivitiesAndCorrectNames() {
        let cases: [(HKWorkoutActivityType, String)] = [
            (.walking, "Walking"),
            (.running, "Running"),
            (.swimming, "Swimming"),
            (.yoga, "Yoga")
        ]

        for (activityType, expectedName) in cases {
            let workout = DetectedWorkout(
                id: UUID(),
                activityType: activityType.rawValue,
                startDate: .now,
                endDate: .now,
                durationMinutes: 20,
                caloriesBurned: nil,
                distance: nil
            )

            XCTAssertEqual(workout.activityName, expectedName)
            XCTAssertEqual(workout.suggestedOptionId, "health_workout_\(activityType.rawValue)")
        }
    }

    func testRefreshSuggestsYogaAsItsOwnHealthActivity() async throws {
        let healthKit = ConfigurableHealthKitMock()
        healthKit.workoutsToReturn = [
            DetectedWorkout(
                id: UUID(),
                activityType: HKWorkoutActivityType.yoga.rawValue,
                startDate: Date.now.addingTimeInterval(-1_800),
                endDate: Date.now,
                durationMinutes: 30,
                caloriesBurned: 100,
                distance: nil
            )
        ]
        let model = AppModel(
            healthKitService: healthKit,
            familyControlsService: MockFamilyControlsService(),
            notificationService: MockNotificationService(),
            budgetEngine: MockBudgetEngine(),
            subscriptionStore: SubscriptionStore()
        )

        await model.refreshActivitySuggestions()

        XCTAssertEqual(healthKit.workoutFetchCount, 1)
        let suggestion = try XCTUnwrap(
            model.pendingActivitySuggestions.first { $0.source.isWorkout }
        )
        XCTAssertEqual(suggestion.optionId, "health_workout_57")
        XCTAssertEqual(suggestion.title, "Yoga")
    }

    func testAcceptingYogaInstallsItInCatalogAndActivePalette() throws {
        let defaults = UserDefaults.stepsTrader()
        let catalogBefore = defaults.data(forKey: SharedKeys.happeningCatalog)
        let selectionBefore = defaults.stringArray(forKey: SharedKeys.happeningPaletteSelection)
        defer {
            if let catalogBefore {
                defaults.set(catalogBefore, forKey: SharedKeys.happeningCatalog)
            } else {
                defaults.removeObject(forKey: SharedKeys.happeningCatalog)
            }
            if let selectionBefore {
                defaults.set(selectionBefore, forKey: SharedKeys.happeningPaletteSelection)
            } else {
                defaults.removeObject(forKey: SharedKeys.happeningPaletteSelection)
            }
        }

        let model = AppModel(
            healthKitService: ConfigurableHealthKitMock(),
            familyControlsService: MockFamilyControlsService(),
            notificationService: MockNotificationService(),
            budgetEngine: MockBudgetEngine(),
            subscriptionStore: SubscriptionStore()
        )
        model.happeningStore.load()
        model.happeningPaletteSelectionStore.load(catalog: model.happeningStore.all)
        let workout = DetectedWorkout(
            id: UUID(),
            activityType: HKWorkoutActivityType.yoga.rawValue,
            startDate: Date.now.addingTimeInterval(-1_800),
            endDate: Date.now,
            durationMinutes: 30,
            caloriesBurned: nil,
            distance: nil
        )
        let suggestion = try XCTUnwrap(ActivitySuggestion.fromWorkout(workout))

        model.acceptActivitySuggestion(suggestion)

        XCTAssertEqual(
            model.happeningStore.happening(id: "health_workout_57")?.title,
            "Yoga"
        )
        XCTAssertTrue(model.selectedPaletteHappeningIDs().contains("health_workout_57"))
    }

    func testRefreshDoesNotSuggestHealthWalkingWhenWalkIsAlreadyOnCanvas() async {
        let healthKit = ConfigurableHealthKitMock()
        healthKit.workoutsToReturn = [
            DetectedWorkout(
                id: UUID(),
                activityType: HKWorkoutActivityType.walking.rawValue,
                startDate: Date.now.addingTimeInterval(-1_800),
                endDate: Date.now,
                durationMinutes: 30,
                caloriesBurned: nil,
                distance: nil
            )
        ]
        let model = makeModel(healthKit: healthKit)
        model.todayAdditions = [todayEntry(optionId: "happening_walk")]

        await model.refreshActivitySuggestions()

        XCTAssertFalse(model.pendingActivitySuggestions.contains { suggestion in
            if case .workout = suggestion.source { return true }
            return false
        })
    }

    func testRefreshDoesNotSuggestSpecificWorkoutWhenGenericWorkoutIsAlreadyOnCanvas() async {
        let healthKit = ConfigurableHealthKitMock()
        healthKit.workoutsToReturn = [
            DetectedWorkout(
                id: UUID(),
                activityType: HKWorkoutActivityType.yoga.rawValue,
                startDate: Date.now.addingTimeInterval(-1_800),
                endDate: Date.now,
                durationMinutes: 30,
                caloriesBurned: nil,
                distance: nil
            )
        ]
        let model = makeModel(healthKit: healthKit)
        model.todayAdditions = [todayEntry(optionId: "happening_workout")]

        await model.refreshActivitySuggestions()

        XCTAssertFalse(model.pendingActivitySuggestions.contains { suggestion in
            if case .workout = suggestion.source { return true }
            return false
        })
    }

    func testRefreshDoesNotSuggestRestingWhenSleepIsAlreadyOnCanvas() async {
        let model = makeModel()
        model.todayAdditions = [todayEntry(optionId: "happening_slept_well")]

        await model.refreshActivitySuggestions()

        XCTAssertFalse(model.pendingActivitySuggestions.contains { $0.id == "morning_resting" })
    }

    func testRefreshDoesNotSuggestMindfulSessionWhenIntentionalRestIsAlreadyOnCanvas() async {
        let healthKit = ConfigurableHealthKitMock()
        healthKit.mindfulMinutesToReturn = 12
        let model = makeModel(healthKit: healthKit)
        model.todayAdditions = [todayEntry(optionId: "happening_did_nothing")]

        await model.refreshActivitySuggestions()

        XCTAssertFalse(model.pendingActivitySuggestions.contains { suggestion in
            if case .mindfulSession = suggestion.source { return true }
            return false
        })
    }

    func testAddingMatchingHappeningRemovesAnAlreadyVisibleSuggestion() {
        let model = makeModel()
        model.pendingActivitySuggestions = [.fromMorningResting()]

        let result = model.addHappening(
            id: "happening_slept_well",
            colorHex: "#AABBCC"
        )

        XCTAssertNotNil(result)
        XCTAssertTrue(model.pendingActivitySuggestions.isEmpty)
    }

    func testSyncedMatchingHappeningHidesAnAlreadyVisibleSuggestion() {
        let model = makeModel()
        model.pendingActivitySuggestions = [.fromMorningResting()]

        model.todayAdditions = [todayEntry(optionId: "happening_slept_well")]

        XCTAssertTrue(model.pendingActivitySuggestions.isEmpty)
    }

    func testConcreteHealthActivityPrecedesGenericMorningSuggestion() async throws {
        let healthKit = ConfigurableHealthKitMock()
        healthKit.workoutsToReturn = [
            DetectedWorkout(
                id: UUID(),
                activityType: HKWorkoutActivityType.running.rawValue,
                startDate: Date.now.addingTimeInterval(-1_800),
                endDate: Date.now,
                durationMinutes: 30,
                caloriesBurned: nil,
                distance: nil
            )
        ]
        let model = makeModel(healthKit: healthKit)

        await model.refreshActivitySuggestions()

        let first = try XCTUnwrap(model.pendingActivitySuggestions.first)
        if case .workout = first.source {
            // Expected: a concrete detected event leads the visual stack.
        } else {
            XCTFail("Expected the concrete HealthKit workout to be first")
        }
    }

    private func makeModel(
        healthKit: ConfigurableHealthKitMock = ConfigurableHealthKitMock()
    ) -> AppModel {
        AppModel(
            healthKitService: healthKit,
            familyControlsService: MockFamilyControlsService(),
            notificationService: MockNotificationService(),
            budgetEngine: MockBudgetEngine(),
            subscriptionStore: SubscriptionStore()
        )
    }

    private func todayEntry(optionId: String) -> OptionEntry {
        OptionEntry(
            id: UUID().uuidString,
            dayKey: AppModel.dayKey(for: .now),
            optionId: optionId,
            colorHex: "#AABBCC",
            timestamp: .now,
            assetVariant: nil
        )
    }
}

// MARK: - Interval Merging Tests (P8)

final class SleepIntervalMergingTests: XCTestCase {

    func testOnlyCurrentStepQueriesMayReadOrReplaceTheLiveCache() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)

        XCTAssertTrue(HealthKitService.shouldUseLiveStepCache(queryEnd: now, now: now))
        XCTAssertTrue(HealthKitService.shouldUseLiveStepCache(
            queryEnd: now.addingTimeInterval(-60),
            now: now
        ))
        XCTAssertFalse(HealthKitService.shouldUseLiveStepCache(
            queryEnd: now.addingTimeInterval(-86_400),
            now: now
        ))
    }

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
        defaults = UserDefaults.stepsTrader()
        // Clear cached values before creating the store (init reads cache)
        defaults.removeObject(forKey: SharedKeys.cachedStepsToday)
        defaults.removeObject(forKey: SharedKeys.hasStepsData)
        defaults.removeObject(forKey: "cachedSleepHoursToday")
        store = HealthStore(healthKitService: mock)
    }

    override func tearDown() {
        defaults.removeObject(forKey: SharedKeys.cachedStepsToday)
        defaults.removeObject(forKey: SharedKeys.hasStepsData)
        defaults.removeObject(forKey: "cachedSleepHoursToday")
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

        // The observer hops to the MainActor via a detached Task, so the update
        // isn't visible synchronously. Poll until it lands instead of sleeping a
        // fixed 100ms — that guess was the order-dependent CI flake (it resolves
        // on the first iteration normally, and only waits longer under load).
        var attempts = 0
        while store.stepsToday != 12345 && attempts < 200 {
            try? await Task.sleep(nanoseconds: 5_000_000) // 5ms
            attempts += 1
        }

        XCTAssertEqual(store.stepsToday, 12345)
        XCTAssertTrue(store.hasStepsData)
    }
}
