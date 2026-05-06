import XCTest
@testable import Steps4

@MainActor
final class BudgetEngineTests: XCTestCase {

    private static let budgetKeys: [String] = [
        SharedKeys.selectedTariff,
        SharedKeys.todayAnchor,
        SharedKeys.dayEndHour,
        SharedKeys.dayEndMinute,
    ]

    override func setUp() {
        super.setUp()
        for key in Self.budgetKeys {
            UserDefaults.standard.removeObject(forKey: key)
            UserDefaults.stepsTrader().removeObject(forKey: key)
        }
    }

    override func tearDown() {
        for key in Self.budgetKeys {
            UserDefaults.standard.removeObject(forKey: key)
            UserDefaults.stepsTrader().removeObject(forKey: key)
        }
        super.tearDown()
    }

    // MARK: - Tariff stepsPerMinute

    func testTariffStepsPerMinute() {
        XCTAssertEqual(Tariff.hard.stepsPerMinute, 1000)
        XCTAssertEqual(Tariff.medium.stepsPerMinute, 500)
        XCTAssertEqual(Tariff.easy.stepsPerMinute, 100)
        XCTAssertEqual(Tariff.free.stepsPerMinute, 0)
    }

    func testTariffEntryCostSteps() {
        XCTAssertEqual(Tariff.hard.entryCostSteps, 100)
        XCTAssertEqual(Tariff.medium.entryCostSteps, 50)
        XCTAssertEqual(Tariff.easy.entryCostSteps, 10)
        XCTAssertEqual(Tariff.free.entryCostSteps, 0)
    }

    // MARK: - minutes(from steps)

    func testMinutesFromSteps_mediumTariff() {
        UserDefaults.stepsTrader().set(Tariff.medium.rawValue, forKey: SharedKeys.selectedTariff)
        let engine = BudgetEngine()
        XCTAssertEqual(engine.minutes(from: 0), 0)
        XCTAssertEqual(engine.minutes(from: 500), 1)
        XCTAssertEqual(engine.minutes(from: 1000), 2)
        XCTAssertEqual(engine.minutes(from: 250), 0)
        XCTAssertEqual(engine.minutes(from: 501), 1)
    }

    func testMinutesFromSteps_hardTariff() {
        UserDefaults.stepsTrader().set(Tariff.hard.rawValue, forKey: SharedKeys.selectedTariff)
        let engine = BudgetEngine()
        XCTAssertEqual(engine.minutes(from: 1000), 1)
        XCTAssertEqual(engine.minutes(from: 5000), 5)
        XCTAssertEqual(engine.minutes(from: 999), 0)
    }

    func testMinutesFromSteps_easyTariff() {
        UserDefaults.stepsTrader().set(Tariff.easy.rawValue, forKey: SharedKeys.selectedTariff)
        let engine = BudgetEngine()
        XCTAssertEqual(engine.minutes(from: 100), 1)
        XCTAssertEqual(engine.minutes(from: 250), 2)
        XCTAssertEqual(engine.minutes(from: 50), 0)
    }

    func testMinutesFromSteps_negativeStepsReturnsZero() {
        UserDefaults.stepsTrader().set(Tariff.medium.rawValue, forKey: SharedKeys.selectedTariff)
        let engine = BudgetEngine()
        XCTAssertEqual(engine.minutes(from: -100), 0)
    }

    // MARK: - updateTariff

    func testUpdateTariffChangesStepsPerMinute() {
        UserDefaults.stepsTrader().set(Tariff.medium.rawValue, forKey: SharedKeys.selectedTariff)
        let engine = BudgetEngine()
        XCTAssertEqual(engine.minutes(from: 500), 1)

        engine.updateTariff(.hard)
        XCTAssertEqual(engine.tariff, .hard)
        XCTAssertEqual(engine.minutes(from: 1000), 1)
        XCTAssertEqual(engine.minutes(from: 500), 0)
    }

    func testUpdateTariffPersists() {
        UserDefaults.stepsTrader().set(Tariff.medium.rawValue, forKey: SharedKeys.selectedTariff)
        let engine = BudgetEngine()
        engine.updateTariff(.easy)

        let saved = UserDefaults.stepsTrader().string(forKey: SharedKeys.selectedTariff)
        XCTAssertEqual(saved, Tariff.easy.rawValue)
    }

    // MARK: - resetIfNeeded

    func testResetIfNeeded_resetsOnDayChange() {
        let yesterday = Calendar.current.date(byAdding: .day, value: -1,
                                              to: Calendar.current.startOfDay(for: Date()))!

        UserDefaults.stepsTrader().set(Tariff.medium.rawValue, forKey: SharedKeys.selectedTariff)
        UserDefaults.stepsTrader().set(yesterday, forKey: SharedKeys.todayAnchor)

        let engine = BudgetEngine()
        let anchorBefore = engine.todayAnchor

        engine.resetIfNeeded()
        XCTAssertNotEqual(engine.todayAnchor, anchorBefore,
                          "todayAnchor should advance to the current day")
    }

    func testResetIfNeeded_noResetSameDay() {
        UserDefaults.stepsTrader().set(Tariff.medium.rawValue, forKey: SharedKeys.selectedTariff)
        let engine = BudgetEngine()
        let anchorBefore = engine.todayAnchor

        engine.resetIfNeeded()
        XCTAssertEqual(engine.todayAnchor, anchorBefore,
                       "Same-day resetIfNeeded should not change todayAnchor")
    }

    // MARK: - Free tariff

    func testMinutesFromSteps_freeTariff() {
        UserDefaults.stepsTrader().set(Tariff.free.rawValue, forKey: SharedKeys.selectedTariff)
        let engine = BudgetEngine()
        XCTAssertEqual(engine.tariff, .free)
        XCTAssertEqual(engine.stepsPerMinute, 0,
                       "Free tariff has 0 stepsPerMinute (truly free)")
        XCTAssertEqual(engine.minutes(from: 100), 1440,
                       "Free tariff returns 1440 (unlimited) for any step count")
        XCTAssertEqual(engine.minutes(from: 0), 1440)
    }

    func testFreeTariff_zeroCostEntry() {
        XCTAssertEqual(Tariff.free.entryCostSteps, 0,
                       "Free tariff should have zero entry cost")
        XCTAssertEqual(Tariff.free.stepsPerMinute, 0,
                       "Free tariff has 0 stepsPerMinute")
    }

    func testFreeTariff_differentRateFromEasy() {
        XCTAssertNotEqual(Tariff.free.stepsPerMinute, Tariff.easy.stepsPerMinute,
                          "Free (0) differs from easy (100)")
        XCTAssertEqual(Tariff.free.entryCostSteps, 0)
        XCTAssertGreaterThan(Tariff.easy.entryCostSteps, 0)
    }

    // MARK: - resetIfNeeded with custom day-end time

    func testResetIfNeeded_respectsCustomDayEnd() {
        let cal = Calendar.current
        let now = Date()
        let yesterday = cal.date(byAdding: .day, value: -1, to: cal.startOfDay(for: now))!

        let g = UserDefaults.stepsTrader()
        g.set(Tariff.medium.rawValue, forKey: SharedKeys.selectedTariff)
        g.set(yesterday, forKey: SharedKeys.todayAnchor)
        g.set(4, forKey: SharedKeys.dayEndHour)
        g.set(30, forKey: SharedKeys.dayEndMinute)

        let engine = BudgetEngine()
        engine.resetIfNeeded()
        XCTAssertNotEqual(engine.todayAnchor, yesterday,
                          "After day change with custom day-end, anchor should advance")
    }

    func testUpdateDayEnd_persistsValues() {
        UserDefaults.stepsTrader().set(Tariff.medium.rawValue, forKey: SharedKeys.selectedTariff)
        let engine = BudgetEngine()
        engine.updateDayEnd(hour: 5, minute: 45)
        XCTAssertEqual(engine.dayEndHour, 5)
        XCTAssertEqual(engine.dayEndMinute, 45)
    }

    func testUpdateDayEnd_clampsOutOfRangeValues() {
        UserDefaults.stepsTrader().set(Tariff.medium.rawValue, forKey: SharedKeys.selectedTariff)
        let engine = BudgetEngine()
        engine.updateDayEnd(hour: 99, minute: -5)
        XCTAssertEqual(engine.dayEndHour, 23,
                       "Hour should be clamped to 23")
        XCTAssertEqual(engine.dayEndMinute, 0,
                       "Minute should be clamped to 0")
    }

    func testUpdateDayEnd_clampsMinuteUpperBound() {
        UserDefaults.stepsTrader().set(Tariff.medium.rawValue, forKey: SharedKeys.selectedTariff)
        let engine = BudgetEngine()
        engine.updateDayEnd(hour: 3, minute: 99)
        XCTAssertEqual(engine.dayEndHour, 3)
        XCTAssertEqual(engine.dayEndMinute, 59,
                       "Minute should be clamped to 59")
    }

    // MARK: - Init reads from stepsTrader defaults

    func testInit_readsTariffFromSharedDefaults() {
        UserDefaults.stepsTrader().set(Tariff.hard.rawValue, forKey: SharedKeys.selectedTariff)
        let engine = BudgetEngine()
        XCTAssertEqual(engine.tariff, .hard)
    }

    func testInit_fallsBackToStandardDefaults() {
        UserDefaults.standard.set(Tariff.easy.rawValue, forKey: SharedKeys.selectedTariff)
        let engine = BudgetEngine()
        XCTAssertEqual(engine.tariff, .easy)
    }

    func testInit_defaultsToMediumWhenNoSavedTariff() {
        let engine = BudgetEngine()
        XCTAssertEqual(engine.tariff, .medium)
    }

    func testInit_readsDayEndFromSharedDefaults() {
        let g = UserDefaults.stepsTrader()
        g.set(3, forKey: SharedKeys.dayEndHour)
        g.set(15, forKey: SharedKeys.dayEndMinute)
        let engine = BudgetEngine()
        XCTAssertEqual(engine.dayEndHour, 3)
        XCTAssertEqual(engine.dayEndMinute, 15)
    }

    func testInit_clampsDayEndOnLoad() {
        let g = UserDefaults.stepsTrader()
        g.set(50, forKey: SharedKeys.dayEndHour)
        g.set(-10, forKey: SharedKeys.dayEndMinute)
        let engine = BudgetEngine()
        XCTAssertEqual(engine.dayEndHour, 23)
        XCTAssertEqual(engine.dayEndMinute, 0)
    }

    // MARK: - reloadFromStorage

    func testReloadFromStorage_picksUpNewValues() {
        UserDefaults.stepsTrader().set(Tariff.medium.rawValue, forKey: SharedKeys.selectedTariff)
        let engine = BudgetEngine()
        XCTAssertEqual(engine.dayEndHour, 0)

        UserDefaults.stepsTrader().set(6, forKey: SharedKeys.dayEndHour)
        UserDefaults.stepsTrader().set(30, forKey: SharedKeys.dayEndMinute)
        engine.reloadFromStorage()

        XCTAssertEqual(engine.dayEndHour, 6)
        XCTAssertEqual(engine.dayEndMinute, 30)
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
