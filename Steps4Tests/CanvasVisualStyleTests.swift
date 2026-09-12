import Foundation
import XCTest
@testable import Steps4

final class CanvasVisualStyleTests: XCTestCase {
    func testMissingStyleOnHistoricalCanvasResolvesLegacy() {
        XCTAssertEqual(
            DayCanvas(dayKey: "2026-09-01").resolvedVisualStyle,
            .legacy
        )
    }

    func testFirstMigrationPromotesOnlyCurrentDay() {
        let current = CanvasVisualStyleMigration.decision(
            dayKey: "2026-09-06",
            storedStyleRaw: nil,
            currentDayKey: "2026-09-06",
            completedVersion: 0
        )
        let historical = CanvasVisualStyleMigration.decision(
            dayKey: "2026-09-05",
            storedStyleRaw: nil,
            currentDayKey: "2026-09-06",
            completedVersion: 0
        )

        XCTAssertEqual(current, .persist(.editorial, markVersion: 1))
        XCTAssertEqual(historical, .use(.legacy))
    }

    func testCompletedMigrationNeverOverridesDeliberateLegacy() {
        XCTAssertEqual(
            CanvasVisualStyleMigration.decision(
                dayKey: "2026-09-06",
                storedStyleRaw: CanvasVisualStyle.legacy.rawValue,
                currentDayKey: "2026-09-06",
                completedVersion: 1
            ),
            .use(.legacy)
        )
    }

    func testStyleSurvivesWholeCanvasJSONRoundTrip() throws {
        var canvas = DayCanvas(dayKey: "2026-09-06")
        canvas.visualStyleRaw = CanvasVisualStyle.editorial.rawValue

        let data = try JSONEncoder().encode(canvas)
        let decoded = try JSONDecoder().decode(DayCanvas.self, from: data)

        XCTAssertEqual(decoded.resolvedVisualStyle, .editorial)
    }
}
