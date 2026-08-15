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
        XCTAssertTrue(visited.contains(.feedsExplain))
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

    // MARK: - Every step must have a way out

    /// The steps a user completes by acting on the app instead of tapping
    /// "next". Each one needs *both* a `.coachMarkAnchor(...)` (so the
    /// spotlight has something to cut out and the tap can land) and a call
    /// site that reports the action back to the manager — otherwise the tour
    /// stops dead on it and the only way on is "skip all".
    ///
    /// Keep this list in sync by hand: it is the thing the two tests below
    /// check the enum and the source tree against.
    private static let actionDrivenSteps: Set<CoachMarkStep> = [
        .expandChevron,
        .tapPlusButton,
        .tapMind,
        .spotlightFocusing,
        .tapAddToCanvas,
        .tapFeedsTab
    ]

    /// Pure form of the invariant: a step either offers a "next" button or is
    /// declared action-driven. A new case that is neither fails here.
    func testEveryStepHasAWayForward() {
        for step in CoachMarkStep.allCases {
            let isActionDriven = Self.actionDrivenSteps.contains(step)
            if step.hasNextButton {
                XCTAssertFalse(
                    isActionDriven,
                    "\(step) has a next button and is also listed as action-driven — pick one"
                )
            } else {
                XCTAssertTrue(
                    isActionDriven,
                    "\(step) has no next button and is not in actionDrivenSteps: the tour would dead-end on it. Give it a next button, add it to the list (with an anchor and a completion call site), or drop the step."
                )
            }
        }
    }

    /// Strong form: the declared action-driven steps really are anchored and
    /// really are reported as completed somewhere in the app sources. This is
    /// what catches a step being orphaned by the deletion of the view that
    /// used to own it.
    func testActionDrivenStepsAreAnchoredAndReportedInTheSources() throws {
        let sources = try Self.appSourceText()

        for step in Self.actionDrivenSteps {
            let name = String(describing: step)

            XCTAssertTrue(
                sources.contains("coachMarkAnchor(.\(name))"),
                "\(name) is action-driven but nothing in StepsTrader/ anchors it — the spotlight would dim the whole screen with nothing to tap"
            )

            let isReported =
                sources.contains("postAction(for: .\(name))")
                || sources.contains("completeAction(for: .\(name))")
            XCTAssertTrue(
                isReported,
                "\(name) is action-driven but no call site posts or completes it — the tour would dead-end on it"
            )
        }
    }

    /// The app sources, concatenated. Located relative to this test file, so
    /// it works for a local run against the checkout that was compiled; a
    /// runner that cannot see the tree skips rather than lying.
    private static func appSourceText() throws -> String {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // Steps4Tests
            .deletingLastPathComponent()   // repo root
            .appendingPathComponent("StepsTrader")

        try XCTSkipUnless(
            FileManager.default.fileExists(atPath: root.path),
            "source tree not reachable from this runner at \(root.path)"
        )

        guard let walker = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: nil
        ) else {
            XCTFail("could not enumerate \(root.path)")
            return ""
        }

        var combined = ""
        for case let url as URL in walker where url.pathExtension == "swift" {
            combined += (try? String(contentsOf: url, encoding: .utf8)) ?? ""
        }
        XCTAssertFalse(combined.isEmpty, "read no Swift sources under \(root.path)")
        return combined
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
