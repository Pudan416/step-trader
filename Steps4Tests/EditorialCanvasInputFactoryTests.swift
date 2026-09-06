import CoreGraphics
import Foundation
import XCTest
@testable import Steps4

final class EditorialCanvasInputFactoryTests: XCTestCase {
    func testBuildsFullCanvasEditorialInputWithStableElementIdentity() {
        let firstID = UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!
        let secondID = UUID(uuidString: "11111111-2222-3333-4444-555555555555")!
        var canvas = DayCanvas(dayKey: "2026-09-06")
        canvas.elements = [element(id: firstID), element(id: secondID)]

        let result = EditorialCanvasInputFactory.make(
            canvas: canvas,
            metrics: EditorialCanvasMetrics(
                stepsProgress: 0.6,
                sleepProgress: 0.8,
                spentProgress: 0.3
            ),
            paletteCategories: [.neon, .warm]
        )

        XCTAssertEqual(result.sceneInput.dayKey, "2026-09-06")
        XCTAssertEqual(result.sceneInput.identity, "primary-canvas")
        XCTAssertEqual(
            result.sceneInput.eventIDs,
            [firstID.uuidString.lowercased(), secondID.uuidString.lowercased()]
        )
        XCTAssertEqual(result.sceneInput.motionEnergy, 0.7, accuracy: 0.0001)
        XCTAssertEqual(result.sceneInput.visualClarity, 0.79, accuracy: 0.0001)
        XCTAssertEqual(result.sceneInput.canvasCoverage, .fullCanvas)
        XCTAssertEqual(result.sceneInput.paletteCategories, [.neon, .warm])
        XCTAssertTrue(result.sceneInput.usesEditorialField)
        XCTAssertEqual(
            result.sceneInput.editorialLabConfiguration,
            DayObjectEditorialLabConfiguration(
                materialMode: .generativeDNA,
                placement: .depthField
            )
        )
        XCTAssertEqual(result.digitalImpact.spentColors, 30)
    }

    func testClampsInvalidMetricsAndDerivesLowSleep() {
        let result = EditorialCanvasInputFactory.make(
            canvas: DayCanvas(dayKey: "2026-09-06"),
            metrics: EditorialCanvasMetrics(
                stepsProgress: 4,
                sleepProgress: -.infinity,
                spentProgress: 9
            ),
            paletteCategories: []
        )

        XCTAssertEqual(result.sceneInput.motionEnergy, 1, accuracy: 0.0001)
        XCTAssertEqual(result.sceneInput.visualClarity, 0.35, accuracy: 0.0001)
        XCTAssertTrue(result.sceneInput.lowSleep)
        XCTAssertEqual(result.digitalImpact.spentColors, 100)
    }

    func testBackgroundSelectionIsDeterministicForDay() {
        let canvas = DayCanvas(dayKey: "2026-09-06")
        let metrics = EditorialCanvasMetrics(
            stepsProgress: 0.5,
            sleepProgress: 0.5,
            spentProgress: 0
        )

        let first = EditorialCanvasInputFactory.make(
            canvas: canvas,
            metrics: metrics,
            paletteCategories: [.pastel]
        )
        let second = EditorialCanvasInputFactory.make(
            canvas: canvas,
            metrics: metrics,
            paletteCategories: [.pastel]
        )

        XCTAssertEqual(first.sceneInput.editorialBackground, second.sceneInput.editorialBackground)
    }

    private func element(id: UUID) -> CanvasElement {
        CanvasElement(
            id: id,
            kind: .circle,
            optionId: "test",
            label: nil,
            hexColor: "#FF0000",
            size: 0.2,
            basePosition: CGPoint(x: 0.5, y: 0.5),
            phaseOffset: 0,
            driftSpeed: 0.1,
            driftAmplitude: 0.01,
            pulseFrequency: 0.1,
            pulseAmplitude: 0.01,
            rotationSpeed: 0,
            opacity: 1,
            createdAt: Date(timeIntervalSince1970: 0)
        )
    }
}
