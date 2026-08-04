import XCTest
@testable import Steps4

/// The coach-mark tour has a Feeds leg that only makes sense once a blocking
/// group exists. Onboarding lets users skip blocked-app setup, so these tests
/// pin down that the tour never walks a group-less user through it — or talks
/// to them about unlocking an app they never connected.
@MainActor
final class CoachMarkTourTests: XCTestCase {

    /// Drives the tour to completion, collecting every step that was shown.
    private func walkTour(hasTicketGroups: Bool) -> [CoachMarkStep] {
        let manager = CoachMarkManager()
        manager.configure { hasTicketGroups }
        manager.start()

        var visited: [CoachMarkStep] = []
        // Generous bound: the walk must terminate well inside one pass over
        // `allCases`, and a runaway loop should fail loudly rather than hang.
        for _ in 0..<(CoachMarkStep.allCases.count + 5) {
            guard let step = manager.currentStep else { break }
            visited.append(step)
            manager.advance()
        }
        XCTAssertNil(manager.currentStep, "tour did not terminate")
        XCTAssertFalse(manager.isActive)
        return visited
    }

    func testTourWithoutTicketGroups_skipsFeedsLeg() {
        let visited = walkTour(hasTicketGroups: false)

        for step in visited {
            XCTAssertFalse(
                step.requiresTicketGroups,
                "\(step) needs a blocking group but was shown to a user without one"
            )
        }
        XCTAssertEqual(visited.last, .allSet)
        XCTAssertTrue(visited.contains(.canvasTrace))
    }

    func testTourWithTicketGroups_showsFeedsLeg() {
        let visited = walkTour(hasTicketGroups: true)

        XCTAssertEqual(visited, CoachMarkStep.allCases)
        XCTAssertTrue(visited.contains(.tapUnlockPill))
    }

    func testTourNotConfigured_defaultsToSkippingFeedsLeg() {
        // No `configure` call: the manager must not assume a group exists.
        let manager = CoachMarkManager()
        manager.start()
        while manager.currentStep != nil, manager.currentStep != .allSet {
            manager.advance()
        }
        XCTAssertEqual(manager.currentStep, .allSet)
    }

    func testClosingTooltip_dropsUnlockCopyWithoutTicketGroups() {
        let without = CoachMarkManager()
        without.configure { false }
        let with = CoachMarkManager()
        with.configure { true }

        XCTAssertEqual(with.tooltip(for: .allSet), CoachMarkStep.allSet.tooltip)
        XCTAssertNotEqual(without.tooltip(for: .allSet), CoachMarkStep.allSet.tooltip)
        XCTAssertEqual(without.tooltip(for: .allSet), CoachMarkStep.allSet.tooltipWithoutTicketGroups)
    }

    func testTooltipOverridesOnlyApplyToStepsThatDefineThem() {
        let manager = CoachMarkManager()
        manager.configure { false }

        for step in CoachMarkStep.allCases where step.tooltipWithoutTicketGroups == nil {
            XCTAssertEqual(manager.tooltip(for: step), step.tooltip)
        }
    }

    func testShownStepsNeverMentionUnlockingWithoutTicketGroups() {
        let manager = CoachMarkManager()
        manager.configure { false }
        manager.start()

        while let step = manager.currentStep {
            let copy = manager.tooltip(for: step).lowercased()
            XCTAssertFalse(copy.contains("unlock"), "\(step) promises an unlock: \(copy)")
            XCTAssertFalse(copy.contains("connected"), "\(step) assumes a connected app: \(copy)")
            manager.advance()
        }
    }
}
