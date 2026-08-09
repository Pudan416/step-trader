import SwiftUI
import XCTest
@testable import Steps4

final class HappeningLiquidLayoutTests: XCTestCase {

    private let size = CGSize(width: 402, height: 874)
    private let safeInsets = EdgeInsets(top: 59, leading: 0, bottom: 34, trailing: 0)

    func testEverySupportedCountHasAccessibleNonOverlappingLabelFrames() {
        for count in 0...10 {
            let layout = HappeningLiquidLayout.layout(
                count: count, in: size, safeInsets: safeInsets
            )

            XCTAssertEqual(layout.sources.count, count, "count \(count)")
            XCTAssertEqual(layout.labelFrames.count, count, "count \(count)")

            for frame in layout.labelFrames {
                XCTAssertGreaterThanOrEqual(frame.width, 44, "count \(count)")
                XCTAssertGreaterThanOrEqual(frame.height, 44, "count \(count)")
            }

            for (index, frame) in layout.labelFrames.enumerated() {
                for other in layout.labelFrames.dropFirst(index + 1) {
                    XCTAssertFalse(frame.intersects(other), "count \(count), frame \(index)")
                }
            }
        }
    }

    func testHitFramesRemainInsideSafeBounds() {
        let safeBounds = CGRect(
            x: safeInsets.leading,
            y: safeInsets.top,
            width: size.width - safeInsets.leading - safeInsets.trailing,
            height: size.height - safeInsets.top - safeInsets.bottom
        )

        for count in 0...10 {
            let layout = HappeningLiquidLayout.layout(
                count: count, in: size, safeInsets: safeInsets
            )

            for frame in layout.labelFrames {
                XCTAssertTrue(safeBounds.contains(frame), "count \(count), frame \(frame)")
            }
        }
    }

    func testContourLeavesFreeCanvasOnEverySafeEdgeAndConnectsDock() {
        let safeBounds = CGRect(
            x: safeInsets.leading,
            y: safeInsets.top,
            width: size.width - safeInsets.leading - safeInsets.trailing,
            height: size.height - safeInsets.top - safeInsets.bottom
        )

        for count in 1...10 {
            let layout = HappeningLiquidLayout.layout(
                count: count, in: size, safeInsets: safeInsets
            )
            let contour = layout.contourBounds

            XCTAssertGreaterThanOrEqual(contour.minX - safeBounds.minX, 16, "count \(count)")
            XCTAssertGreaterThanOrEqual(safeBounds.maxX - contour.maxX, 16, "count \(count)")
            XCTAssertGreaterThanOrEqual(contour.minY - safeBounds.minY, 16, "count \(count)")
            XCTAssertGreaterThanOrEqual(safeBounds.maxY - contour.maxY, 16, "count \(count)")
            XCTAssertGreaterThan(layout.dockAnchor.y, contour.maxY, "count \(count)")
            XCTAssertLessThanOrEqual(layout.dockAnchor.y - contour.maxY, 44, "count \(count)")
            XCTAssertTrue(safeBounds.contains(layout.dockAnchor), "count \(count)")
        }
    }

    func testRemovingIndexPreservesRelativeIdentityOrder() {
        let ten = HappeningLiquidLayout.layout(count: 10, in: size, safeInsets: EdgeInsets())
        let nine = HappeningLiquidLayout.layout(count: 9, in: size, safeInsets: EdgeInsets())
        let eight = HappeningLiquidLayout.layout(count: 8, in: size, safeInsets: EdgeInsets())

        XCTAssertEqual(ten.sources.map(\.index), Array(0..<10))
        XCTAssertEqual(nine.sources.map(\.index), Array(0..<9))
        XCTAssertEqual(eight.sources.map(\.index), Array(0..<8))
        XCTAssertTrue(nine.contourBounds.width < size.width)
        XCTAssertTrue(eight.contourBounds.width < size.width)
    }

    func testEmptyFieldHasNoSourcesAndAValidCloseDock() {
        let layout = HappeningLiquidLayout.layout(count: 0, in: size, safeInsets: safeInsets)
        let safeBounds = CGRect(
            x: safeInsets.leading,
            y: safeInsets.top,
            width: size.width - safeInsets.leading - safeInsets.trailing,
            height: size.height - safeInsets.top - safeInsets.bottom
        )

        XCTAssertTrue(layout.sources.isEmpty)
        XCTAssertTrue(layout.labelFrames.isEmpty)
        XCTAssertTrue(layout.contourBounds.isEmpty)
        XCTAssertTrue(safeBounds.contains(layout.dockAnchor))
    }

    func testLayoutIsDeterministicForTheSameInputs() {
        XCTAssertEqual(
            HappeningLiquidLayout.layout(count: 10, in: size, safeInsets: safeInsets),
            HappeningLiquidLayout.layout(count: 10, in: size, safeInsets: safeInsets)
        )
    }
}

final class HappeningLiquidTransitionStateTests: XCTestCase {

    func testBeginRemovalLocksTheSelectedIDAndStartsPressing() {
        var state = HappeningLiquidTransitionState()

        XCTAssertTrue(state.beginRemoval(id: "happening_walk"))
        XCTAssertEqual(state.phase, .pressing)
        XCTAssertEqual(state.selectedID, "happening_walk")
    }

    func testBusyTransitionIgnoresDuplicateAndCompetingTaps() {
        var state = HappeningLiquidTransitionState()
        XCTAssertTrue(state.beginRemoval(id: "happening_walk"))

        XCTAssertFalse(state.beginRemoval(id: "happening_walk"))
        XCTAssertFalse(state.beginRemoval(id: "happening_read"))
        XCTAssertEqual(state.phase, .pressing)
        XCTAssertEqual(state.selectedID, "happening_walk")
    }

    func testFinishRemovalUnlocksOnlyAfterReflowAndAllowsAnotherID() {
        var state = HappeningLiquidTransitionState()
        XCTAssertTrue(state.beginRemoval(id: "happening_walk"))
        XCTAssertTrue(state.advanceRemoval(id: "happening_walk", to: .sinking))
        XCTAssertTrue(state.advanceRemoval(id: "happening_walk", to: .reflowing))

        XCTAssertFalse(state.finishRemoval(id: "happening_read"))
        XCTAssertTrue(state.finishRemoval(id: "happening_walk"))
        XCTAssertEqual(state.phase, .idle)
        XCTAssertNil(state.selectedID)
        XCTAssertTrue(state.beginRemoval(id: "happening_read"))
    }

    func testCancelRemovalRollsBackEveryBusyPhaseAndUnlocksControls() {
        for terminalPhase in [RemovalPhase.pressing, .sinking, .reflowing] {
            var state = HappeningLiquidTransitionState()
            XCTAssertTrue(state.beginRemoval(id: "happening_walk"))
            if terminalPhase == .sinking || terminalPhase == .reflowing {
                XCTAssertTrue(state.advanceRemoval(id: "happening_walk", to: .sinking))
            }
            if terminalPhase == .reflowing {
                XCTAssertTrue(state.advanceRemoval(id: "happening_walk", to: .reflowing))
            }

            state.cancelRemoval()

            XCTAssertEqual(state.phase, .idle, "cancel from \(terminalPhase)")
            XCTAssertNil(state.selectedID, "cancel from \(terminalPhase)")
            XCTAssertTrue(
                state.beginRemoval(id: "happening_read"),
                "controls should unlock after cancelling \(terminalPhase)"
            )
        }
    }
}

final class HappeningLiquidPresentationStateTests: XCTestCase {

    private let size = CGSize(width: 402, height: 874)
    private let safeInsets = EdgeInsets(top: 59, leading: 0, bottom: 34, trailing: 0)

    func testOnPickParentUpdateDuringReflowDoesNotResurrectSessionRemoval() throws {
        let initial = Array(HappeningDefaults.builtIns.prefix(3))
        let removed = initial[0]
        let survivor = initial[1]
        var state = HappeningLiquidPresentationState(happenings: initial)

        var parentRefresh = initial
        parentRefresh[1].useCount = 7
        state.receiveParent(parentRefresh, whileTransitioning: true)
        XCTAssertTrue(state.remove(id: removed.id))
        state.finishTransition()

        XCTAssertFalse(state.presentedHappenings.contains { $0.id == removed.id })
        XCTAssertEqual(
            try XCTUnwrap(state.presentedHappenings.first { $0.id == survivor.id }).useCount,
            7,
            "parent metadata should still merge into surviving session items"
        )
    }

    func testSharedPresentationCountDrivesDockThroughTenNineEight() {
        var state = HappeningLiquidPresentationState(
            happenings: Array(HappeningDefaults.builtIns.prefix(10))
        )

        let ten = state.layout(in: size, safeInsets: safeInsets)
        XCTAssertEqual(state.presentedCount, 10)

        XCTAssertTrue(state.remove(id: state.presentedHappenings[0].id))
        let nine = state.layout(in: size, safeInsets: safeInsets)
        XCTAssertEqual(state.presentedCount, 9)

        XCTAssertTrue(state.remove(id: state.presentedHappenings[0].id))
        let eight = state.layout(in: size, safeInsets: safeInsets)
        XCTAssertEqual(state.presentedCount, 8)

        XCTAssertNotEqual(ten.dockAnchor, nine.dockAnchor)
        XCTAssertNotEqual(nine.dockAnchor, eight.dockAnchor)
    }

}

/// Label contrast is unrelated to the replaced blob geometry, so it remains
/// covered here after the legacy layout test file is retired.
final class HappeningPaletteLabelContrastTests: XCTestCase {

    func testLuminanceEndpoints() {
        XCTAssertEqual(HappeningLiquidLabelTreatment.relativeLuminance(ofHex: "#000000"), 0, accuracy: 0.001)
        XCTAssertEqual(HappeningLiquidLabelTreatment.relativeLuminance(ofHex: "#FFFFFF"), 1, accuracy: 0.001)
    }

    func testLuminanceToleratesMissingHashAndWhitespace() {
        XCTAssertEqual(
            HappeningLiquidLabelTreatment.relativeLuminance(ofHex: " FFFFFF "),
            HappeningLiquidLabelTreatment.relativeLuminance(ofHex: "#FFFFFF"),
            accuracy: 0.001
        )
    }

    func testTreatmentUsesProductionWeightedTwoColorBlend() {
        let treatment = HappeningLiquidLabelTreatment(
            primaryHex: "#CC5050",
            accentHex: "#E098A0"
        )

        XCTAssertEqual(treatment.red, 0.821960784, accuracy: 0.000_000_1)
        XCTAssertEqual(treatment.green, 0.392784314, accuracy: 0.000_000_1)
        XCTAssertEqual(treatment.blue, 0.401568627, accuracy: 0.000_000_1)
        XCTAssertEqual(treatment.backingLuminance, 0.237553298, accuracy: 0.000_000_1)
    }

    func testEveryRenderedWarmBlendHasFourPointFiveContrastOnItsOpaqueLens() {
        for slot in 0..<HappeningLiquidField.warmPaletteIndices.count {
            let treatment = HappeningLiquidField.labelTreatment(forSlot: slot)
            let textLuminance = treatment.foreground == .black ? 0.0 : 1.0
            let ratio = (max(treatment.backingLuminance, textLuminance) + 0.05)
                / (min(treatment.backingLuminance, textLuminance) + 0.05)

            XCTAssertGreaterThanOrEqual(
                ratio,
                4.5,
                "slot \(slot) has insufficient rendered label contrast (\(ratio))"
            )
        }
    }

    func testTextBoundsAreInsideTheGuaranteedOpaqueEllipseForEveryLayout() {
        let size = CGSize(width: 402, height: 874)
        let safeInsets = EdgeInsets(top: 59, leading: 0, bottom: 34, trailing: 0)

        for count in 1...10 {
            let layout = HappeningLiquidLayout.layout(
                count: count,
                in: size,
                safeInsets: safeInsets
            )
            for labelFrame in layout.labelFrames {
                let textSize = HappeningLiquidLabelTreatment.inscribedTextSize(
                    in: labelFrame.size
                )
                let normalizedCornerDistance = pow(textSize.width / labelFrame.width, 2)
                    + pow(textSize.height / labelFrame.height, 2)

                XCTAssertLessThanOrEqual(
                    normalizedCornerDistance,
                    1,
                    "count \(count) text corners escape the opaque label lens"
                )
            }
        }
    }

    func testSemanticLabelTypographyUsesTwoLinesAtAccessibilitySizes() {
        XCTAssertEqual(HappeningLiquidLabelTypography.maximumLines(for: .large), 3)
        XCTAssertEqual(HappeningLiquidLabelTypography.maximumLines(for: .accessibility1), 2)
    }
}
