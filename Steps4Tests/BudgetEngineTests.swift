import XCTest
@testable import Steps4

@MainActor
final class BudgetEngineTests: XCTestCase {

    private static let budgetKeys: [String] = [
        SharedKeys.selectedTariff,
        SharedKeys.todayAnchor,
        SharedKeys.dailyBudgetMinutes,
        SharedKeys.remainingMinutes,
        SharedKeys.dayEndHour,
        SharedKeys.dayEndMinute,
    ]

    override func setUp() {
        super.setUp()
        for key in Self.budgetKeys {
            UserDefaults.standard.removeObject(forKey: key)
        }
    }

    override func tearDown() {
        for key in Self.budgetKeys {
            UserDefaults.standard.removeObject(forKey: key)
        }
        super.tearDown()
    }

    // MARK: - Tariff stepsPerMinute (formula used by BudgetEngine.minutes(from:))

    func testTariffStepsPerMinute() {
        XCTAssertEqual(Tariff.hard.stepsPerMinute, 1000)
        XCTAssertEqual(Tariff.medium.stepsPerMinute, 500)
        XCTAssertEqual(Tariff.easy.stepsPerMinute, 100)
        XCTAssertEqual(Tariff.free.stepsPerMinute, 100)
    }

    func testTariffEntryCostSteps() {
        XCTAssertEqual(Tariff.hard.entryCostSteps, 100)
        XCTAssertEqual(Tariff.medium.entryCostSteps, 50)
        XCTAssertEqual(Tariff.easy.entryCostSteps, 10)
        XCTAssertEqual(Tariff.free.entryCostSteps, 0)
    }

    // MARK: - minutes(from steps)

    func testMinutesFromSteps_mediumTariff() {
        UserDefaults.standard.set(Tariff.medium.rawValue, forKey: SharedKeys.selectedTariff)
        let engine = BudgetEngine()
        XCTAssertEqual(engine.minutes(from: 0), 0)
        XCTAssertEqual(engine.minutes(from: 500), 1)
        XCTAssertEqual(engine.minutes(from: 1000), 2)
        XCTAssertEqual(engine.minutes(from: 250), 0)
        XCTAssertEqual(engine.minutes(from: 501), 1)
    }

    func testMinutesFromSteps_hardTariff() {
        UserDefaults.standard.set(Tariff.hard.rawValue, forKey: SharedKeys.selectedTariff)
        let engine = BudgetEngine()
        XCTAssertEqual(engine.minutes(from: 1000), 1)
        XCTAssertEqual(engine.minutes(from: 5000), 5)
        XCTAssertEqual(engine.minutes(from: 999), 0)
    }

    func testMinutesFromSteps_easyTariff() {
        UserDefaults.standard.set(Tariff.easy.rawValue, forKey: SharedKeys.selectedTariff)
        let engine = BudgetEngine()
        XCTAssertEqual(engine.minutes(from: 100), 1)
        XCTAssertEqual(engine.minutes(from: 250), 2)
        XCTAssertEqual(engine.minutes(from: 50), 0)
    }

    func testMinutesFromSteps_negativeStepsReturnsZero() {
        UserDefaults.standard.set(Tariff.medium.rawValue, forKey: SharedKeys.selectedTariff)
        let engine = BudgetEngine()
        XCTAssertEqual(engine.minutes(from: -100), 0)
    }

    // MARK: - setBudget / consume

    func testSetBudgetAndConsume() {
        UserDefaults.standard.set(Tariff.medium.rawValue, forKey: SharedKeys.selectedTariff)
        let engine = BudgetEngine()
        engine.setBudget(minutes: 10)
        XCTAssertEqual(engine.dailyBudgetMinutes, 10)
        XCTAssertEqual(engine.remainingMinutes, 10)

        engine.consume(mins: 3)
        XCTAssertEqual(engine.remainingMinutes, 7)

        engine.consume(mins: 7)
        XCTAssertEqual(engine.remainingMinutes, 0)

        engine.consume(mins: 5)
        XCTAssertEqual(engine.remainingMinutes, 0)
    }

    func testConsumeDoesNotGoNegative() {
        UserDefaults.standard.set(Tariff.medium.rawValue, forKey: SharedKeys.selectedTariff)
        let engine = BudgetEngine()
        engine.setBudget(minutes: 2)
        engine.consume(mins: 5)
        XCTAssertEqual(engine.remainingMinutes, 0)
    }

    // MARK: - updateTariff

    func testUpdateTariffChangesStepsPerMinute() {
        UserDefaults.standard.set(Tariff.medium.rawValue, forKey: SharedKeys.selectedTariff)
        let engine = BudgetEngine()
        XCTAssertEqual(engine.minutes(from: 500), 1)

        engine.updateTariff(.hard)
        XCTAssertEqual(engine.tariff, .hard)
        XCTAssertEqual(engine.minutes(from: 1000), 1)
        XCTAssertEqual(engine.minutes(from: 500), 0)
    }

    // MARK: - resetIfNeeded

    func testResetIfNeeded_resetsOnDayChange() {
        let yesterday = Calendar.current.date(byAdding: .day, value: -1,
                                              to: Calendar.current.startOfDay(for: Date()))!

        UserDefaults.standard.set(Tariff.medium.rawValue, forKey: SharedKeys.selectedTariff)
        UserDefaults.standard.set(yesterday, forKey: SharedKeys.todayAnchor)

        let engine = BudgetEngine()
        engine.setBudget(minutes: 15)
        engine.consume(mins: 5)
        XCTAssertEqual(engine.remainingMinutes, 10)

        engine.resetIfNeeded()
        XCTAssertEqual(engine.dailyBudgetMinutes, 0,
                       "After day change, budget should reset to 0")
        XCTAssertEqual(engine.remainingMinutes, 0,
                       "After day change, remaining should reset to 0")
        XCTAssertNotEqual(engine.todayAnchor, yesterday,
                          "todayAnchor should advance to the current day")
    }

    func testResetIfNeeded_noResetSameDay() {
        UserDefaults.standard.set(Tariff.medium.rawValue, forKey: SharedKeys.selectedTariff)
        let engine = BudgetEngine()
        engine.setBudget(minutes: 10)
        engine.consume(mins: 3)

        engine.resetIfNeeded()
        XCTAssertEqual(engine.remainingMinutes, 7,
                       "Same-day resetIfNeeded should not change remaining minutes")
        XCTAssertEqual(engine.dailyBudgetMinutes, 10)
    }

    // MARK: - Free tariff

    func testMinutesFromSteps_freeTariff() {
        UserDefaults.standard.set(Tariff.free.rawValue, forKey: SharedKeys.selectedTariff)
        let engine = BudgetEngine()
        XCTAssertEqual(engine.tariff, .free)
        XCTAssertEqual(engine.stepsPerMinute, 100,
                       "Free tariff uses 100 steps/min to avoid divide-by-zero")
        XCTAssertEqual(engine.minutes(from: 100), 1)
        XCTAssertEqual(engine.minutes(from: 0), 0)
        XCTAssertEqual(engine.minutes(from: 50), 0)
    }

    func testFreeTariff_zeroCostEntry() {
        XCTAssertEqual(Tariff.free.entryCostSteps, 0,
                       "Free tariff should have zero entry cost")
        XCTAssertTrue(Tariff.free.stepsPerMinute > 0,
                      "stepsPerMinute must be positive to avoid divide-by-zero")
    }

    func testFreeTariff_sameRateAsEasyButZeroEntry() {
        XCTAssertEqual(Tariff.free.stepsPerMinute, Tariff.easy.stepsPerMinute,
                       "Free uses the same steps/min as easy for tracking purposes")
        XCTAssertEqual(Tariff.free.entryCostSteps, 0)
        XCTAssertGreaterThan(Tariff.easy.entryCostSteps, 0)
    }

    func testFreeTariff_budgetStillConsumable() {
        UserDefaults.standard.set(Tariff.free.rawValue, forKey: SharedKeys.selectedTariff)
        let engine = BudgetEngine()
        engine.setBudget(minutes: 60)
        XCTAssertEqual(engine.remainingMinutes, 60)
        engine.consume(mins: 10)
        XCTAssertEqual(engine.remainingMinutes, 50,
                       "Free tariff should still track budget consumption normally")
    }

    // MARK: - resetIfNeeded with custom day-end time

    func testResetIfNeeded_respectsCustomDayEnd() {
        let cal = Calendar.current
        let now = Date()
        let yesterday = cal.date(byAdding: .day, value: -1, to: cal.startOfDay(for: now))!

        UserDefaults.standard.set(Tariff.medium.rawValue, forKey: SharedKeys.selectedTariff)
        UserDefaults.standard.set(yesterday, forKey: SharedKeys.todayAnchor)
        UserDefaults.standard.set(4, forKey: SharedKeys.dayEndHour)
        UserDefaults.standard.set(30, forKey: SharedKeys.dayEndMinute)

        let engine = BudgetEngine()
        engine.setBudget(minutes: 20)
        engine.consume(mins: 8)
        XCTAssertEqual(engine.remainingMinutes, 12)

        engine.resetIfNeeded()
        XCTAssertEqual(engine.dailyBudgetMinutes, 0,
                       "After day change with custom day-end, budget resets to 0")
        XCTAssertEqual(engine.remainingMinutes, 0)
    }

    func testUpdateDayEnd_persistsValues() {
        UserDefaults.standard.set(Tariff.medium.rawValue, forKey: SharedKeys.selectedTariff)
        let engine = BudgetEngine()
        engine.updateDayEnd(hour: 5, minute: 45)
        XCTAssertEqual(engine.dayEndHour, 5)
        XCTAssertEqual(engine.dayEndMinute, 45)
    }

    func testUpdateDayEnd_clampsOutOfRangeValues() {
        UserDefaults.standard.set(Tariff.medium.rawValue, forKey: SharedKeys.selectedTariff)
        let engine = BudgetEngine()
        engine.updateDayEnd(hour: 99, minute: -5)
        XCTAssertEqual(engine.dayEndHour, 23,
                       "Hour should be clamped to 23")
        XCTAssertEqual(engine.dayEndMinute, 0,
                       "Minute should be clamped to 0")
    }

    // MARK: - Tariff backward-compatible decoding

    func testTariffDecoding_liteMapsToEasy() throws {
        let json = Data(#""lite""#.utf8)
        let decoded = try JSONDecoder().decode(Tariff.self, from: json)
        XCTAssertEqual(decoded, .easy,
                       "Legacy 'lite' rawValue should decode as .easy")
    }

    func testTariffDecoding_unknownDefaultsToEasy() throws {
        let json = Data(#""ultra""#.utf8)
        let decoded = try JSONDecoder().decode(Tariff.self, from: json)
        XCTAssertEqual(decoded, .easy,
                       "Unknown tariff strings should fall back to .easy")
    }

    func testTariffDecoding_validRawValues() throws {
        for tariff in Tariff.allCases {
            let json = Data("\"\(tariff.rawValue)\"".utf8)
            let decoded = try JSONDecoder().decode(Tariff.self, from: json)
            XCTAssertEqual(decoded, tariff)
        }
    }
}
