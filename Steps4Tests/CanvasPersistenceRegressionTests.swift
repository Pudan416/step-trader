import XCTest
import HealthKit
@testable import Steps4

@MainActor
final class CanvasPersistenceRegressionTests: XCTestCase {
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        defaults = UserDefaults.stepsTrader()
        clearEnergyDefaults()
    }

    override func tearDown() {
        clearEnergyDefaults()
        super.tearDown()
    }

    /// A missing anchor key must seed the anchor, not wipe the day. The old
    /// version of this guarded the three category arrays; the state it protects
    /// is now `todayAdditions`, but the regression is the same one.
    func testLoadDailyEnergyState_MissingAnchor_DoesNotResetAdditionsOrBaseEnergy() throws {
        let today = AppModel.dayKey(for: .now)
        let additions = [
            OptionEntry(id: "a", dayKey: today, optionId: "happening_walk",
                        colorHex: "#CC5050", timestamp: .now, assetVariant: nil),
            OptionEntry(id: "b", dayKey: today, optionId: "happening_read",
                        colorHex: "#6098CC", timestamp: .now, assetVariant: nil),
        ]
        defaults.set(try JSONEncoder().encode(additions), forKey: SharedKeys.todayAdditions)
        defaults.set(65, forKey: SharedKeys.baseEnergyToday)
        defaults.removeObject(forKey: SharedKeys.dailyEnergyAnchor)

        let model = makeModel()
        model.loadDailyEnergyState()

        XCTAssertEqual(model.todayAdditions.map(\.id), ["a", "b"])
        XCTAssertEqual(model.baseEnergyToday, 65)
        XCTAssertNotNil(
            defaults.object(forKey: SharedKeys.dailyEnergyAnchor),
            "Anchor should be initialized, not reset state"
        )
    }

    /// The canvas is the backstop when the additions key is missing — a user
    /// upgrading mid-day must not see their day emptied.
    func testLoadDailyEnergyState_RecoversAdditionsFromSavedCanvas() throws {
        let today = AppModel.dayKey(for: .now)
        defaults.removeObject(forKey: SharedKeys.todayAdditions)
        defaults.set(Date.now, forKey: SharedKeys.dailyEnergyAnchor)

        var canvas = DayCanvas(dayKey: today)
        canvas.elements = [
            CanvasElement.spawn(
                optionId: "happening_walk", color: "#CC5050", label: "Walk",
                existingElements: [], dayKey: today
            )
        ]
        _ = CanvasStorageService.shared.saveCanvas(canvas)
        defer { CanvasStorageService.shared.deleteCanvas(for: today) }

        let model = makeModel()
        model.loadDailyEnergyState()

        XCTAssertEqual(model.todayAdditions.map(\.optionId), ["happening_walk"])
    }

    func testDayEndReanchorMovesAdditionAndCanvasWithoutReopeningHappening() async throws {
        let now = Date.now
        guard let pair = dayEndPairWithDifferentKeys(at: now) else {
            throw XCTSkip(
                """
                No two day ends give different keys at \(now). Only true in the \
                final minute before midnight, when every boundary of the day has \
                already passed and there is none left to move across.
                """
            )
        }
        defaults.set(pair.old.hour, forKey: SharedKeys.dayEndHour)
        defaults.set(pair.old.minute, forKey: SharedKeys.dayEndMinute)
        UserDefaults.standard.set(pair.old.hour, forKey: SharedKeys.dayEndHour)
        UserDefaults.standard.set(pair.old.minute, forKey: SharedKeys.dayEndMinute)

        let oldKey = DayBoundary.dayKey(
            for: now,
            dayEndHour: pair.old.hour,
            dayEndMinute: pair.old.minute
        )
        let newKey = DayBoundary.dayKey(
            for: now,
            dayEndHour: pair.new.hour,
            dayEndMinute: pair.new.minute
        )
        // `CanvasStorageService` writes into the app's real container, which the
        // test host shares — so running the app by hand on this simulator leaves
        // a canvas for the ambient day that this test then reads as its own.
        // Clear that one too, not just the two keys under test.
        let ambientKey = AppModel.dayKey(for: now)
        let ambientBackup = CanvasStorageService.shared.loadCanvas(for: ambientKey)
        let oldBackup = CanvasStorageService.shared.loadCanvas(for: oldKey)
        let newBackup = CanvasStorageService.shared.loadCanvas(for: newKey)
        CanvasStorageService.shared.deleteCanvas(for: ambientKey)
        CanvasStorageService.shared.deleteCanvas(for: oldKey)
        CanvasStorageService.shared.deleteCanvas(for: newKey)
        defer {
            CanvasStorageService.shared.deleteCanvas(for: oldKey)
            CanvasStorageService.shared.deleteCanvas(for: newKey)
            CanvasStorageService.shared.deleteCanvas(for: ambientKey)
            if let ambientBackup { _ = CanvasStorageService.shared.saveCanvas(ambientBackup) }
            if let oldBackup { _ = CanvasStorageService.shared.saveCanvas(oldBackup) }
            if let newBackup { _ = CanvasStorageService.shared.saveCanvas(newBackup) }
            UserDefaults.standard.removeObject(forKey: SharedKeys.dayEndHour)
            UserDefaults.standard.removeObject(forKey: SharedKeys.dayEndMinute)
        }

        defaults.set(try JSONEncoder().encode([OptionEntry]()), forKey: SharedKeys.todayAdditions)
        defaults.set(
            DayBoundary.currentDayStart(
                for: now,
                dayEndHour: pair.old.hour,
                dayEndMinute: pair.old.minute
            ),
            forKey: SharedKeys.dailyEnergyAnchor
        )
        let standardSuite = try XCTUnwrap(UserDefaults(suiteName: "day-end-reanchor-\(UUID())"))
        let budgetEngine = BudgetEngine(
            sharedDefaults: defaults,
            standardDefaults: standardSuite
        )
        let model = AppModel(
            healthKitService: MockHealthKitService(),
            familyControlsService: MockFamilyControlsService(),
            notificationService: MockNotificationService(),
            budgetEngine: budgetEngine,
            subscriptionStore: SubscriptionStore(defaults: defaults)
        )
        model.isBootstrapping = true
        model.loadDailyEnergyState()

        let entry = try XCTUnwrap(
            model.addHappening(
                id: "happening_walk",
                colorHex: "#AABBCC",
                at: now
            )
        )
        var canvas = DayCanvas(dayKey: oldKey)
        canvas.elements = [
            CanvasElement.spawn(
                id: try XCTUnwrap(UUID(uuidString: entry.id)),
                optionId: entry.optionId,
                color: entry.colorHex,
                label: "Walk",
                existingElements: [],
                dayKey: oldKey
            )
        ]
        XCTAssertTrue(CanvasStorageService.shared.saveCanvas(canvas))

        model.updateDayEnd(hour: pair.new.hour, minute: pair.new.minute)
        try await Task.sleep(for: .milliseconds(500))

        XCTAssertEqual(model.todayAdditions.map(\.dayKey), [newKey])
        XCTAssertNil(
            model.addHappening(
                id: "happening_walk",
                colorHex: "#DDEEFF",
                at: now
            ),
            "re-anchoring must preserve once-per-custom-day identity"
        )
        XCTAssertNil(CanvasStorageService.shared.loadCanvas(for: oldKey))
        let movedCanvas = try XCTUnwrap(CanvasStorageService.shared.loadCanvas(for: newKey))
        XCTAssertEqual(movedCanvas.dayKey, newKey)
        XCTAssertEqual(movedCanvas.elements.map(\.id), canvas.elements.map(\.id))
    }

    private func clearEnergyDefaults() {
        let keys = [
            SharedKeys.dailyEnergyAnchor,
            SharedKeys.dailySleepHours,
            SharedKeys.baseEnergyToday,
            SharedKeys.todayAdditions,
            SharedKeys.happeningCatalog,
            SharedKeys.dayEndHour,
            SharedKeys.dayEndMinute,
            "dailyEnergySelections_v1_body",
            "dailyEnergySelections_v1_mind",
            "dailyEnergySelections_v1_heart",
        ]
        keys.forEach { defaults.removeObject(forKey: $0) }
    }

    private struct DayEnd {
        let hour: Int
        let minute: Int
    }

    /// Two day ends that put `date` in different days — the reanchor this test
    /// exercises needs a boundary it can actually move across.
    ///
    /// Minutes are part of the search, not just hours. `dayKey` names the
    /// calendar date the day *started* on, so two day ends differ only when one
    /// of their boundaries has already passed today and the other has not. Once
    /// 23:00 is behind us every whole hour has passed and an hours-only search
    /// comes back empty — which is what failed this test at 23:44, on the
    /// unwrap rather than on anything it was asserting.
    ///
    /// Single pass: hold the first candidate, return the first one that keys
    /// differently. Deterministic, and 1440 boundary computations rather than
    /// the square of that.
    private func dayEndPairWithDifferentKeys(
        at date: Date
    ) -> (old: DayEnd, new: DayEnd)? {
        var first: (end: DayEnd, key: String)?
        for hour in 0..<24 {
            for minute in 0..<60 {
                let end = DayEnd(hour: hour, minute: minute)
                let key = DayBoundary.dayKey(
                    for: date,
                    dayEndHour: hour,
                    dayEndMinute: minute
                )
                guard let anchor = first else {
                    first = (end, key)
                    continue
                }
                if key != anchor.key { return (anchor.end, end) }
            }
        }
        return nil
    }

    private func makeModel() -> AppModel {
        AppModel(
            healthKitService: MockHealthKitService(),
            familyControlsService: MockFamilyControlsService(),
            notificationService: MockNotificationService(),
            budgetEngine: MockBudgetEngine(),
            subscriptionStore: SubscriptionStore.shared
        )
    }
}
