import XCTest
@testable import Steps4

final class CanvasRenderBudgetTests: XCTestCase {
    func testNormalPowerBudgetsFollowElementAndSourceThresholds() {
        let cases: [(count: Int, snowflake: Int, organic: Int, metaball: Int)] = [
            (0, 10, 4, 48),
            (6, 10, 4, 42),
            (7, 7, 3, 42),
            (10, 7, 3, 42),
            (11, 7, 3, 36),
            (12, 7, 3, 36),
            (13, 5, 2, 36),
        ]

        for testCase in cases {
            XCTAssertEqual(
                CanvasRenderBudget.snowflakeTrailLength(
                    elementCount: testCase.count,
                    lowPowerMode: false
                ),
                testCase.snowflake,
                "snowflake count \(testCase.count)"
            )
            XCTAssertEqual(
                CanvasRenderBudget.organicLayerCount(
                    elementCount: testCase.count,
                    lowPowerMode: false
                ),
                testCase.organic,
                "organic count \(testCase.count)"
            )
            XCTAssertEqual(
                CanvasRenderBudget.metaballGridResolution(
                    sourceCount: testCase.count,
                    lowPowerMode: false
                ),
                testCase.metaball,
                "metaball source count \(testCase.count)"
            )
        }
    }

    func testLowPowerModeCapsEveryBudget() {
        let cases: [(count: Int, snowflake: Int, organic: Int, metaball: Int)] = [
            (0, 5, 2, 32),
            (6, 5, 2, 32),
            (12, 5, 2, 32),
            (13, 5, 2, 32),
        ]

        for testCase in cases {
            XCTAssertEqual(
                CanvasRenderBudget.snowflakeTrailLength(
                    elementCount: testCase.count,
                    lowPowerMode: true
                ),
                testCase.snowflake,
                "snowflake count \(testCase.count)"
            )
            XCTAssertEqual(
                CanvasRenderBudget.organicLayerCount(
                    elementCount: testCase.count,
                    lowPowerMode: true
                ),
                testCase.organic,
                "organic count \(testCase.count)"
            )
            XCTAssertEqual(
                CanvasRenderBudget.metaballGridResolution(
                    sourceCount: testCase.count,
                    lowPowerMode: true
                ),
                testCase.metaball,
                "metaball source count \(testCase.count)"
            )
        }
    }
}
