import XCTest
@testable import Steps4

final class SmoothActivationTests: XCTestCase {
    func testCubicSmoothstepHasExactEndpointsAndMidpoint() {
        XCTAssertEqual(smoothActivation(0.2, start: 0.2, end: 0.6), 0)
        XCTAssertEqual(smoothActivation(0.4, start: 0.2, end: 0.6), 0.5, accuracy: 1e-12)
        XCTAssertEqual(smoothActivation(0.6, start: 0.2, end: 0.6), 1)
    }

    func testValuesClampOutsideTheActivationWindow() {
        XCTAssertEqual(smoothActivation(-100, start: 0.2, end: 0.6), 0)
        XCTAssertEqual(smoothActivation(100, start: 0.2, end: 0.6), 1)
    }

    func testCurveIsContinuousAtBothEndpoints() {
        let epsilon = 0.000_001

        XCTAssertEqual(smoothActivation(0.2 - epsilon, start: 0.2, end: 0.6), 0)
        XCTAssertLessThan(smoothActivation(0.2 + epsilon, start: 0.2, end: 0.6), 1e-9)
        XCTAssertGreaterThan(smoothActivation(0.6 - epsilon, start: 0.2, end: 0.6), 1 - 1e-9)
        XCTAssertEqual(smoothActivation(0.6 + epsilon, start: 0.2, end: 0.6), 1)
    }

    func testCurveIsMonotonicAcrossAndBeyondTheWindow() {
        let values = (-100...200).map { index in
            smoothActivation(Double(index) / 100, start: 0.2, end: 0.6)
        }

        for (earlier, later) in zip(values, values.dropFirst()) {
            XCTAssertLessThanOrEqual(earlier, later)
        }
    }

    func testNonFiniteOrInvalidInputsSafelyDeactivate() {
        let nonFinite = [Double.nan, .infinity, -.infinity]

        for value in nonFinite {
            XCTAssertEqual(smoothActivation(value, start: 0.2, end: 0.6), 0)
            XCTAssertEqual(smoothActivation(0.4, start: value, end: 0.6), 0)
            XCTAssertEqual(smoothActivation(0.4, start: 0.2, end: value), 0)
        }
        XCTAssertEqual(smoothActivation(0.4, start: 0.6, end: 0.2), 0)
        XCTAssertEqual(smoothActivation(0.4, start: 0.4, end: 0.4), 0)
    }
}
