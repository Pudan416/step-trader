import XCTest
@testable import Steps4

/// Dust and focus replaced the abstract energy/clarity mapping. What has to
/// hold is that both stay legible: steps put material in the air, sleep decides
/// how much of the frame you can hold on to, and neither reaches for the other's
/// channel.
final class CanvasAtmosphereTests: XCTestCase {

    // MARK: - Mapping

    func testDustRisesWithStepsWithoutThresholds() {
        var previous = CanvasAtmosphere.dust(forSteps: 0)
        for steps in stride(from: 100, through: 20_000, by: 100) {
            let value = CanvasAtmosphere.dust(forSteps: steps)
            XCTAssertGreaterThan(value, previous, "dust stalled at \(steps) steps")
            XCTAssertLessThanOrEqual(value, 1.0)
            previous = value
        }
    }

    func testStillDayHasNoDust() {
        XCTAssertEqual(CanvasAtmosphere.dust(forSteps: 0), 0)
        XCTAssertEqual(CanvasAtmosphere.dust(forSteps: -100), 0)
    }

    func testFocusIsMonotoneInSleep() {
        var previous = CanvasAtmosphere.focus(forSleepHours: 0)
        for quarter in 1...40 {
            let value = CanvasAtmosphere.focus(forSleepHours: Double(quarter) / 4)
            XCTAssertGreaterThanOrEqual(value, previous)
            previous = value
        }
        XCTAssertEqual(CanvasAtmosphere.focus(forSleepHours: 8), 1.0, accuracy: 0.001)
        XCTAssertEqual(CanvasAtmosphere.focus(forSleepHours: 3), 0.0, accuracy: 0.001)
    }

    func testStepsAndSleepStayOnSeparateChannels() {
        let rested = CanvasAtmosphere.forDay(steps: 12_000, sleepHours: 8)
        let tired = CanvasAtmosphere.forDay(steps: 12_000, sleepHours: 3.5)
        // Same walking, so the air must carry the same amount of material.
        XCTAssertEqual(rested.dust, tired.dust, accuracy: 0.0001)
        XCTAssertGreaterThan(rested.focus - tired.focus, 0.5)
    }

    func testValuesAreClamped() {
        let a = CanvasAtmosphere(dust: 3, focus: -2)
        XCTAssertEqual(a.dust, 1)
        XCTAssertEqual(a.focus, 0)
    }

    // MARK: - Depth of field

    func testSubjectStaysSharpOnAGoodNight() {
        let rested = CanvasAtmosphere(dust: 0.5, focus: 1)
        XCTAssertEqual(rested.blurRadius(for: .mid), 0, accuracy: 0.001)
        // Depth of field exists even at full focus, or the frame is flat again.
        XCTAssertGreaterThan(rested.blurRadius(for: .near), rested.blurRadius(for: .far))
        XCTAssertGreaterThan(rested.blurRadius(for: .far), 0)
    }

    func testABadNightTakesTheAnchorAway() {
        let rested = CanvasAtmosphere(dust: 0.5, focus: 1)
        let tired = CanvasAtmosphere(dust: 0.5, focus: 0)
        for plane in CanvasDepthPlane.allCases {
            XCTAssertGreaterThan(
                tired.blurRadius(for: plane),
                rested.blurRadius(for: plane),
                "plane \(plane) did not soften on a bad night"
            )
        }
        // Specifically the subject: this is the difference a viewer feels.
        XCTAssertGreaterThan(tired.blurRadius(for: .mid), 3)
    }

    func testNearDustIsAlwaysSofterThanNearElements() {
        for focus in stride(from: 0.0, through: 1.0, by: 0.1) {
            let a = CanvasAtmosphere(dust: 0.5, focus: focus)
            XCTAssertLessThan(a.dustBlurRadius(for: .far), a.blurRadius(for: .far))
        }
    }

    func testDustOpacityFollowsSteps() {
        let quiet = CanvasAtmosphere(dust: 0, focus: 0.8)
        let busy = CanvasAtmosphere(dust: 1, focus: 0.8)
        for plane in CanvasDepthPlane.allCases {
            XCTAssertGreaterThan(busy.dustOpacity(for: plane), quiet.dustOpacity(for: plane))
            // Never fully absent: an airless frame is the thing being fixed.
            XCTAssertGreaterThan(quiet.dustOpacity(for: plane), 0)
        }
    }

    // MARK: - Plane assignment

    func testPlaneAssignmentIsStableForAnElement() {
        let elements = CanvasAtmosphereDemoCanvas.make(dayKey: "2026-08-18").elements
        for element in elements {
            let first = CanvasAtmosphere.plane(for: element, dayKey: "2026-08-18")
            for _ in 0..<20 {
                XCTAssertEqual(CanvasAtmosphere.plane(for: element, dayKey: "2026-08-18"), first)
            }
        }
    }

    func testSplitKeepsEveryElement() {
        let canvas = CanvasAtmosphereDemoCanvas.make(dayKey: "2026-08-18")
        let split = CanvasAtmosphere.split(canvas.elements, dayKey: canvas.dayKey)
        let total = CanvasDepthPlane.allCases.reduce(0) { $0 + (split[$1]?.count ?? 0) }
        XCTAssertEqual(total, canvas.elements.count)

        let ids = Set(CanvasDepthPlane.allCases.flatMap { split[$0] ?? [] }.map(\.id))
        XCTAssertEqual(ids, Set(canvas.elements.map(\.id)))
    }

    func testEveryPlaneGetsUsedAcrossManyElements() {
        // With 7 elements a plane can legitimately come up empty; over a large
        // sample all three must appear, or the split is not really a split.
        var counts: [CanvasDepthPlane: Int] = [:]
        let canvas = CanvasAtmosphereDemoCanvas.make(dayKey: "2026-08-18")
        let template = canvas.elements[0]
        for day in 1...200 {
            let dayKey = String(format: "2026-%02d-%02d", (day % 12) + 1, (day % 28) + 1)
            var element = template
            element.shapeSeed = CanvasElement.makeSeed(optionId: "x", dayKey: dayKey, index: day)
            counts[CanvasAtmosphere.plane(for: element, dayKey: dayKey), default: 0] += 1
        }
        for plane in CanvasDepthPlane.allCases {
            XCTAssertGreaterThan(counts[plane] ?? 0, 0, "\(plane) never used")
        }
        // The subject plane has to hold the majority share it declares.
        XCTAssertGreaterThan(counts[.mid] ?? 0, counts[.near] ?? 0)
    }

    func testPlaneSharesSumToOne() {
        let total = CanvasDepthPlane.allCases.reduce(0.0) { $0 + $1.share }
        XCTAssertEqual(total, 1.0, accuracy: 0.0001)
    }
}
