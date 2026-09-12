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
        XCTAssertEqual(preview.gpuActor.silhouetteVariant, assignment.silhouette.variant)
        XCTAssertEqual(preview.halfSize.y / preview.halfSize.x, assignment.silhouette.aspect, accuracy: 0.0001)
        XCTAssertEqual(preview.gpuAppearance, assignment.material.gpuAppearance)
        XCTAssertEqual(added.gpuActor.presentationSaturation, 1, accuracy: 0.001)
        XCTAssertEqual(removal.gpuActor.removalEmphasis, 1)
        XCTAssertEqual(frame.postProcess.grainIntensity, 0.05)
        XCTAssertEqual(frame.postProcess.blurRadius, 0)
    }

    func testDepthSortedMultiMaterialUploadKeepsEveryActorOnItsOwnAppearance() throws {
        let presentation = makePresentation()
        let frame = HappeningPaletteRenderFrame.make(
            presentation: presentation,
            scene: makeScene(),
            elapsed: 2
        )
        let upload = DayObjectsActorUpload(
            actors: frame.actors,
            resolution: SIMD2(390, 844)
        )

        XCTAssertEqual(upload.actors.map(\.appearanceIndex), (0..<10).map(UInt32.init))
        for (index, actor) in frame.actors.enumerated() {
            XCTAssertEqual(upload.appearances[index], actor.gpuAppearance)
            XCTAssertEqual(
                upload.appearances[Int(upload.actors[index].appearanceIndex)],
                actor.gpuAppearance
            )
        }
        XCTAssertGreaterThan(Set(upload.appearances.map(\.metadata)).count, 1)
    }

    func testBuilderConvertsTopLeftPalettePointsToPositiveUpMetalCoordinates() throws {
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
        // SwiftUI y grows down from the top; the actor vertex shader writes
        // positive y directly to Metal clip space, which grows upward.
        XCTAssertEqual(actor.gpuActor.position.y, 1.0, accuracy: 0.0001)
        XCTAssertEqual(actor.gpuActor.halfSize.x, Float(source.radius / 390), accuracy: 0.0001)
        let silhouette = try XCTUnwrap(presentation.slots.first?.assignment.silhouette)
        XCTAssertEqual(actor.gpuActor.halfSize.y, Float(source.radius / 390) * silhouette.aspect, accuracy: 0.0001)
    }

    func testTransitionTimelineInterpolatesControlsAndGeometryThroughCompletion() {
        let initial = makePresentation(stateForFirstSlot: .available)
        let updated = makePresentation(
            stateForFirstSlot: .additionPreview,
            firstSourceOffset: CGSize(width: 64, height: 32),
            firstSourceRadiusDelta: 16
        )
        var timeline = HappeningPaletteTransitionTimeline()

        timeline.update(to: initial, elapsed: 0)
        timeline.update(to: updated, elapsed: 1)
        let start = try! slot(for: "h0", in: timeline.sample(at: 1))
        let quarter = try! slot(for: "h0", in: timeline.sample(at: 1.085))
        let complete = try! slot(for: "h0", in: timeline.sample(at: 1.341))

        XCTAssertEqual(start.controls.paletteMorph, 0, accuracy: 0.001)
        XCTAssertEqual(start.source.center.x, 39, accuracy: 0.001)
        XCTAssertEqual(start.source.center.y, 32, accuracy: 0.001)
        XCTAssertEqual(start.source.radius, 32, accuracy: 0.001)

        XCTAssertEqual(quarter.controls.paletteMorph, 0.15625, accuracy: 0.001)
        XCTAssertEqual(quarter.controls.scale, 1.009375, accuracy: 0.001)
        XCTAssertEqual(quarter.source.center.x, 49, accuracy: 0.001)
        XCTAssertEqual(quarter.source.center.y, 37, accuracy: 0.001)
        XCTAssertEqual(quarter.source.radius, 34.5, accuracy: 0.001)

        XCTAssertEqual(complete.controls.paletteMorph, 1, accuracy: 0.001)
        XCTAssertEqual(complete.controls.scale, 1.06, accuracy: 0.001)
        XCTAssertEqual(complete.source.center.x, 103, accuracy: 0.001)
        XCTAssertEqual(complete.source.center.y, 64, accuracy: 0.001)
        XCTAssertEqual(complete.source.radius, 48, accuracy: 0.001)
    }

    func testReduceMotionSwitchesEndpointsWithoutResumingMorphing() {
        let initial = makePresentation(reduceMotion: true)
        let updated = makePresentation(
            stateForFirstSlot: .additionPreview,
            reduceMotion: true,
            firstSourceOffset: CGSize(width: 64, height: 32),
            firstSourceRadiusDelta: 16
        )
        var timeline = HappeningPaletteTransitionTimeline()

        timeline.update(to: initial, elapsed: 0)
        timeline.update(to: updated, elapsed: 1)

        let beforeSwitch = try! slot(for: "h0", in: timeline.sample(at: 1.099))
        let switchPoint = try! slot(for: "h0", in: timeline.sample(at: 1.10))
        let beforeFadeInCompletes = try! slot(for: "h0", in: timeline.sample(at: 1.199))
        let completed = try! slot(for: "h0", in: timeline.sample(at: 1.20))
        let afterCompletion = try! slot(for: "h0", in: timeline.sample(at: 1.50))

        XCTAssertEqual(beforeSwitch.source.center.x, 39, accuracy: 0.001)
        XCTAssertEqual(beforeSwitch.source.radius, 32, accuracy: 0.001)
        XCTAssertEqual(beforeSwitch.controls.opacity, 0.01, accuracy: 0.001)
        XCTAssertEqual(switchPoint.source.center.x, 103, accuracy: 0.001)
        XCTAssertEqual(switchPoint.source.radius, 48, accuracy: 0.001)
        XCTAssertEqual(switchPoint.controls.opacity, 0, accuracy: 0.001)
        XCTAssertEqual(beforeFadeInCompletes.controls.opacity, 0.99, accuracy: 0.001)
        XCTAssertEqual(completed.source.center.x, 103, accuracy: 0.001)
        XCTAssertEqual(completed.source.radius, 48, accuracy: 0.001)
        XCTAssertEqual(completed.controls.paletteMorph, 1, accuracy: 0.001)
        XCTAssertEqual(completed.controls.opacity, 1, accuracy: 0.001)
        XCTAssertEqual(afterCompletion.source.center.x, 103, accuracy: 0.001)
        XCTAssertEqual(afterCompletion.source.radius, 48, accuracy: 0.001)
        XCTAssertEqual(afterCompletion.controls.paletteMorph, 1, accuracy: 0.001)
    }

    func testRepeatedIdenticalUpdateDoesNotRestartAnExistingTransition() {
        let initial = makePresentation()
        let updated = makePresentation(stateForFirstSlot: .additionPreview)
        var timeline = HappeningPaletteTransitionTimeline()

        timeline.update(to: initial, elapsed: 0)
        timeline.update(to: updated, elapsed: 1)
        timeline.update(to: updated, elapsed: 1.085)
        let sample = timeline.sample(at: 1.17)

        XCTAssertEqual(sample.controls(for: "h0").paletteMorph, 0.5, accuracy: 0.001)
        XCTAssertEqual(sample.controls(for: "h0").scale, 1.03, accuracy: 0.001)
    }

    func testUnrelatedSlotUpdateDoesNotRestartAnotherSlotTransition() {
        let initial = makePresentation()
        let firstChanged = makePresentation(stateForFirstSlot: .additionPreview)
        let secondChanged = makePresentation(
            stateForFirstSlot: .additionPreview,
            stateForSecondSlot: .removalPreview
        )
        var timeline = HappeningPaletteTransitionTimeline()

        timeline.update(to: initial, elapsed: 0)
        timeline.update(to: firstChanged, elapsed: 1)
        timeline.update(to: secondChanged, elapsed: 1.085)
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

    private func slot(for happeningID: String, in sample: HappeningPaletteRenderSample) throws -> HappeningPaletteRenderSample.Slot {
        try XCTUnwrap(sample.slots.first { $0.happeningID == happeningID })
    }

    private func makePresentation(
        stateForFirstSlot: HappeningPaletteSlotVisualState = .available,
        stateForSecondSlot: HappeningPaletteSlotVisualState = .additionPreview,
        reduceMotion: Bool = false,
        isTransitionActive: Bool = false,
        firstSourceOffset: CGSize = .zero,
        firstSourceRadiusDelta: CGFloat = 0
    ) -> HappeningPaletteRenderPresentation {
        let assignments = HappeningEditorialAssignmentResolver.assignments(
            happenings: (0..<10).map {
                Happening(id: "h\($0)", title: "Happening \($0)", isBuiltIn: true)
            },
            baseInput: editorialInput(),
            colorNonce: 7
        )
        let states: [HappeningPaletteSlotVisualState] = [
            stateForFirstSlot, stateForSecondSlot, .added, .removalPreview,
            .available, .available, .available, .available, .available, .available,
        ]
        let sources = (0..<10).map { index in
            let isFirst = index == 0
            let baseCenter = CGPoint(
                x: 39 + CGFloat(index) * 31,
                y: 32 + CGFloat(index) * 51
            )
            let center = CGPoint(
                x: baseCenter.x + (isFirst ? firstSourceOffset.width : 0),
                y: baseCenter.y + (isFirst ? firstSourceOffset.height : 0)
            )
            return HappeningFieldLayout.Source(
                index: index,
                center: center,
                radius: 32 + (isFirst ? firstSourceRadiusDelta : 0)
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
            reduceMotion: reduceMotion,
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
