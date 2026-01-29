import XCTest
@testable import Steps4

final class BudgetEngineTests: XCTestCase {

    override func setUp() {
        super.setUp()
        UserDefaults.standard.removeObject(forKey: "selectedTariff")
    }

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: "selectedTariff")
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
        UserDefaults.standard.set(Tariff.medium.rawValue, forKey: "selectedTariff")
        let engine = BudgetEngine()
        XCTAssertEqual(engine.minutes(from: 0), 0)
        XCTAssertEqual(engine.minutes(from: 500), 1)
        XCTAssertEqual(engine.minutes(from: 1000), 2)
        XCTAssertEqual(engine.minutes(from: 250), 0)
        XCTAssertEqual(engine.minutes(from: 501), 1)
    }

    func testMinutesFromSteps_hardTariff() {
        UserDefaults.standard.set(Tariff.hard.rawValue, forKey: "selectedTariff")
        let engine = BudgetEngine()
        XCTAssertEqual(engine.minutes(from: 1000), 1)
        XCTAssertEqual(engine.minutes(from: 5000), 5)
        XCTAssertEqual(engine.minutes(from: 999), 0)
    }

    func testMinutesFromSteps_easyTariff() {
        UserDefaults.standard.set(Tariff.easy.rawValue, forKey: "selectedTariff")
        let engine = BudgetEngine()
        XCTAssertEqual(engine.minutes(from: 100), 1)
        XCTAssertEqual(engine.minutes(from: 250), 2)
        XCTAssertEqual(engine.minutes(from: 50), 0)
    }

    func testMinutesFromSteps_negativeStepsReturnsZero() {
        UserDefaults.standard.set(Tariff.medium.rawValue, forKey: "selectedTariff")
        let engine = BudgetEngine()
        XCTAssertEqual(engine.minutes(from: -100), 0)
    }

    // MARK: - setBudget / consume

    func testSetBudgetAndConsume() {
        UserDefaults.standard.set(Tariff.medium.rawValue, forKey: "selectedTariff")
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
        UserDefaults.standard.set(Tariff.medium.rawValue, forKey: "selectedTariff")
        let engine = BudgetEngine()
        engine.setBudget(minutes: 2)
        engine.consume(mins: 5)
        XCTAssertEqual(engine.remainingMinutes, 0)
    }

    // MARK: - updateTariff

    func testUpdateTariffChangesStepsPerMinute() {
        UserDefaults.standard.set(Tariff.medium.rawValue, forKey: "selectedTariff")
        let engine = BudgetEngine()
        XCTAssertEqual(engine.minutes(from: 500), 1)

        engine.updateTariff(.hard)
        XCTAssertEqual(engine.tariff, .hard)
        XCTAssertEqual(engine.minutes(from: 1000), 1)
        XCTAssertEqual(engine.minutes(from: 500), 0)
    }
}
