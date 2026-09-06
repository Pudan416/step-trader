import XCTest
@testable import Steps4

final class HappeningPaletteRenderFrameTests: XCTestCase {
    func testBuilderMapsTenPaletteSlotsToProductionActors() throws {
        let scene = makeScene()
        let presentation = makePresentation()

        let frame = HappeningPaletteRenderFrame.make(
            presentation: presentation,
            scene: scene,
            elapsed: 2
        )

        XCTAssertEqual(frame.actors.count, 10)

        let available = try actor(for: "h0", in: frame)
        let preview = try actor(for: "h1", in: frame)
        let added = try actor(for: "h2", in: frame)
        let removal = try actor(for: "h3", in: frame)
        let assignment = try XCTUnwrap(presentation.slots.first { $0.happeningID == "h1" }?.assignment)

        XCTAssertEqual(available.gpuActor.paletteMorph, 0)
        XCTAssertEqual(preview.gpuActor.paletteMorph, 1)
        XCTAssertEqual(preview.gpuActor.shape, assignment.shape.numericValue)
        XCTAssertEqual(preview.gpuAppearance, assignment.material.gpuAppearance)
        XCTAssertEqual(added.gpuActor.presentationSaturation, 0.08, accuracy: 0.001)
        XCTAssertEqual(removal.gpuActor.removalEmphasis, 1)
        XCTAssertEqual(frame.postProcess.grainIntensity, 0.05)
        XCTAssertEqual(frame.postProcess.blurRadius, 0)
    }

    func testBuilderConvertsPalettePointsUsingTheViewportShortSide() throws {
        let scene = makeScene()
        let presentation = makePresentation()
        let source = try XCTUnwrap(presentation.slots.first?.source)

        let frame = HappeningPaletteRenderFrame.make(
            presentation: presentation,
            scene: scene,
            elapsed: 0
        )
        let actor = try actor(for: "h0", in: frame)

        XCTAssertEqual(actor.gpuActor.position.x, -0.4, accuracy: 0.0001)
        XCTAssertEqual(actor.gpuActor.position.y, -1.0, accuracy: 0.0001)
        XCTAssertEqual(actor.gpuActor.halfSize.x, Float(source.radius / 390), accuracy: 0.0001)
        XCTAssertEqual(actor.gpuActor.halfSize.y, Float(source.radius / 390), accuracy: 0.0001)
    }

    func testTransitionTimelineInterpolatesChangedControlsAndGeometry() {
        let initial = makePresentation(stateForFirstSlot: .available)
        let updated = makePresentation(stateForFirstSlot: .additionPreview)
        var timeline = HappeningPaletteTransitionTimeline()

        timeline.update(to: initial, elapsed: 0)
        timeline.update(to: updated, elapsed: 1)
        let sample = timeline.sample(at: 1.17)

        XCTAssertEqual(sample.controls(for: "h0").paletteMorph, 0.5, accuracy: 0.001)
        XCTAssertEqual(sample.controls(for: "h0").scale, 1.03, accuracy: 0.001)
    }

    func testPresentationModeRequestsSixtyFPSOnlyDuringPaletteTransitions() {
        XCTAssertFalse(DayObjectsPresentationMode.canvas.prefersSixtyFPS)
        XCTAssertFalse(DayObjectsPresentationMode.happeningPalette(
            makePresentation(isTransitionActive: false)
        ).prefersSixtyFPS)
        XCTAssertTrue(DayObjectsPresentationMode.happeningPalette(
            makePresentation(isTransitionActive: true)
        ).prefersSixtyFPS)
    }

    private func actor(for happeningID: String, in frame: DayObjectRenderFrame) throws -> DayObjectRenderActor {
        try XCTUnwrap(frame.actors.first { $0.eventID == happeningID })
    }

    private func makePresentation(
        stateForFirstSlot: HappeningPaletteSlotVisualState = .available,
        isTransitionActive: Bool = false
    ) -> HappeningPaletteRenderPresentation {
        let assignments = HappeningEditorialAssignmentResolver.assignments(
            happenings: (0..<10).map {
                Happening(id: "h\($0)", title: "Happening \($0)", isBuiltIn: true)
            },
            baseInput: editorialInput(),
            colorNonce: 7
        )
        let states: [HappeningPaletteSlotVisualState] = [
            stateForFirstSlot, .additionPreview, .added, .removalPreview,
            .available, .available, .available, .available, .available, .available,
        ]
        let sources = (0..<10).map { index in
            HappeningFieldLayout.Source(
                index: index,
                center: CGPoint(x: 39 + CGFloat(index) * 31, y: 32 + CGFloat(index) * 51),
                radius: 32
            )
        }
        return HappeningPaletteRenderPresentation(
            slots: (0..<10).map { index in
                HappeningPaletteRenderSlot(
                    happeningID: "h\(index)",
                    assignment: assignments["h\(index)"]!,
                    visualState: states[index],
                    source: sources[index]
                )
            },
            viewportSize: CGSize(width: 390, height: 844),
            reduceMotion: false,
            isTransitionActive: isTransitionActive,
            backgroundRevision: 12
        )
    }

    private func makeScene() -> DayObjectScene {
        DayObjectScene.make(input: editorialInput())
    }

    private func editorialInput() -> DayObjectSceneInput {
        DayObjectSceneInput(
            dayKey: "2026-09-06",
            identity: "palette-render-frame",
            eventIDs: [],
            motionEnergy: 0.625,
            visualClarity: 0.625,
            canvasCoverage: .fullCanvas,
            paletteCategories: ModernPaletteSelection.all,
            usesEditorialField: true,
            editorialBackground: .dark,
            lowSleep: true,
            editorialLabConfiguration: DayObjectEditorialLabConfiguration(
                materialMode: .generativeDNA,
                placement: .depthField
            )
        )
    }
}
