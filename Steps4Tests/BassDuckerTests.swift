#if DEBUG || INTERNAL_BUILD
import XCTest
@testable import Steps4

final class BassDuckerTests: XCTestCase {
    func testEnvelopeIsBoundedAndDuplicateKickDoesNotStack() throws {
        let ducker = BassDucker()
        let pulseDucking = BassDuckingPlan(
            maximumAttenuationDecibels: 5,
            attackSeconds: 0.005,
            holdSeconds: 0.045,
            releaseSeconds: 0.180
        )

        let first = try XCTUnwrap(
            ducker.command(kickVelocity: 1, hostTime: 10, plan: pulseDucking)
        )
        let duplicate = ducker.command(kickVelocity: 1, hostTime: 10, plan: pulseDucking)

        XCTAssertEqual(first.maximumAttenuationDecibels, 5)
        XCTAssertNil(duplicate)
        XCTAssertTrue((0.003...0.008).contains(first.attackSeconds))
        XCTAssertTrue((0.030...0.060).contains(first.holdSeconds))
        XCTAssertTrue((0.120...0.220).contains(first.releaseSeconds))
    }

    func testVelocityScalesDuckingWithoutEscapingThePlanCap() throws {
        let plan = BassDuckingPlan(
            maximumAttenuationDecibels: 4,
            attackSeconds: 0.005,
            holdSeconds: 0.040,
            releaseSeconds: 0.160
        )

        let quiet = try XCTUnwrap(BassDucker().command(
            kickVelocity: 0.25,
            hostTime: 1,
            plan: plan
        ))
        let clipped = try XCTUnwrap(BassDucker().command(
            kickVelocity: 2,
            hostTime: 2,
            plan: plan
        ))

        XCTAssertEqual(quiet.maximumAttenuationDecibels, 1, accuracy: 0.000_001)
        XCTAssertEqual(clipped.maximumAttenuationDecibels, 4, accuracy: 0.000_001)
    }
}
#endif
