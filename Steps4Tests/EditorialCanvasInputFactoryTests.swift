import CoreGraphics
import Foundation
import XCTest
@testable import Steps4

final class EditorialCanvasInputFactoryTests: XCTestCase {
    @MainActor
    func testNewDayZeroSpendRoundTripHasNoAutomaticDigitalTrace() async throws {
        var canvas = DayCanvas.newDailyCanvas(dayKey: "2026-09-12")
        canvas.elements = [element(id: UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!)]
        canvas.inkEarned = 6
        canvas.inkSpent = 0
        let restored = try JSONDecoder().decode(DayCanvas.self, from: JSONEncoder().encode(canvas))
        XCTAssertEqual(restored.inkSpent, 0)
        XCTAssertNil(restored.artworkRecipe?.glitchStrength)
        func input(_ value: DayCanvas) -> EditorialCanvasRenderInput {
            EditorialCanvasInputFactory.make(canvas: value,
                metrics: .init(stepsProgress: 0, sleepProgress: 0, spentProgress: value.decayNorm),
                paletteCategories: ModernPaletteSelection.all)
        }
        let automatic = input(restored)
        XCTAssertEqual(automatic.digitalImpact, .none)
        var explicitZero = restored
        explicitZero.artworkRecipe?.glitchStrength = 0
        let a = await DayObjectsImageRenderer.image(input: automatic,
            size: CGSize(width: 300, height: 500), scale: 1, elapsedTime: 4)
        let b = await DayObjectsImageRenderer.image(input: input(explicitZero),
            size: CGSize(width: 300, height: 500), scale: 1, elapsedTime: 4)
        XCTAssertNotNil(a)
        XCTAssertEqual(a?.pngData(), b?.pngData(), "Automatic zero spend must match explicitly disabled trace pixels")
        if let a {
            let attachment = XCTAttachment(image: a)
            attachment.name = "New-day-zero-spend-low-health"; attachment.lifetime = .keepAlways; add(attachment)
        }
    }

    func testRemixSeedChangesVisibleEditorialRecipeDeterministicallyWithoutChangingEvents() throws {
        var canvas = DayCanvas(dayKey: "2026-09-06")
        canvas.elements = (0..<10).map { index in
            var value = element(id: UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", index))!)
            value.editorialColorVariant = index
            return value
        }
        func scene(_ canvas: DayCanvas) -> DayObjectScene {
            DayObjectScene.make(input: EditorialCanvasInputFactory.make(
                canvas: canvas,
                metrics: .init(stepsProgress: 0.6, sleepProgress: 0.8, spentProgress: 0.3),
                paletteCategories: [.neon, .warm]
            ).sceneInput)
        }
        let legacy = scene(canvas)
        canvas.remixSeed = 77
        let first = scene(canvas)
        XCTAssertEqual(first, scene(canvas))
        XCTAssertEqual(first.actorIDs, legacy.actorIDs)
        XCTAssertEqual(first.input.actorColorVariants, legacy.input.actorColorVariants)
        XCTAssertEqual(first.input.motionEnergy, legacy.input.motionEnergy)
        XCTAssertEqual(first.input.visualClarity, legacy.input.visualClarity)
        let before = try XCTUnwrap(legacy.sceneRecipeV1)
        let after = try XCTUnwrap(first.sceneRecipeV1)
        XCTAssertNotEqual(after.actors.map(\.position), before.actors.map(\.position))
        XCTAssertNotEqual(after.actors.map(\.shape), before.actors.map(\.shape))
        XCTAssertNotEqual(after.actors.map(\.diameter), before.actors.map(\.diameter))
        XCTAssertNotEqual(after.actors.map(\.material), before.actors.map(\.material))
        XCTAssertNotEqual(after.actors.map(\.motion), before.actors.map(\.motion))
        XCTAssertNotEqual(after.backgroundStyle, before.backgroundStyle)
        XCTAssertNotEqual(first.paletteSet, legacy.paletteSet)
        canvas.remixSeed = nil
        XCTAssertEqual(scene(canvas), legacy, "Undo to an unremixed day restores the exact legacy renderer input")
    }
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
