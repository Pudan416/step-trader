import XCTest
@testable import Steps4

final class SettingsGoalControlTests: XCTestCase {
    func testWholeGoalAdjustmentsCarryAcrossDigitBoundaries() {
        XCTAssertEqual(StepGoalValue.adjusted(9_500, by: 500), 10_000)
        XCTAssertEqual(StepGoalValue.adjusted(10_000, by: -500), 9_500)
        XCTAssertEqual(StepGoalValue.adjusted(12_345, by: 500), 12_845)
    }

    func testAdjustmentsStopAtBounds() {
        XCTAssertEqual(StepGoalValue.adjusted(1_000, by: -500), 1_000)
        XCTAssertEqual(StepGoalValue.adjusted(99_500, by: 500), 99_500)
        XCTAssertEqual(StepGoalValue.adjusted(99_345, by: 500), 99_500)
        XCTAssertEqual(StepGoalValue.adjusted(1_234, by: -500), 1_000)
    }

    func testExactEntryPreservesIndividualStepsAndAcceptsLocalizedDigits() {
        XCTAssertEqual(StepGoalValue.parse("12345"), 12_345)
        XCTAssertEqual(StepGoalValue.parse("١٢٣٤٥"), 12_345)
        XCTAssertEqual(StepGoalValue.parse(" 1000 "), 1_000)
        XCTAssertEqual(StepGoalValue.parse("99500"), 99_500)
    }

    func testExactEntryRejectsInvalidAndOutOfRangeValues() {
        for input in ["", "999", "99501", "12.5", "-1000", "1000abc", "999999999999999999999999"] {
            XCTAssertNil(StepGoalValue.parse(input), input)
        }
    }
}
