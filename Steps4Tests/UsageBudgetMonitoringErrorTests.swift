import XCTest
@testable import Steps4
#if canImport(DeviceActivity)
import DeviceActivity
#endif

final class UsageBudgetMonitoringErrorTests: XCTestCase {

    #if canImport(DeviceActivity)
    func testExcessiveActivitiesIsClassifiedDistinctly() {
        let classified = UsageBudgetMonitoringError.classify(
            DeviceActivityCenter.MonitoringError.excessiveActivities
        )
        XCTAssertEqual(classified, .excessiveActivities)
    }
    #endif

    func testUnknownErrorFallsBackToOther() {
        struct Boom: Error, LocalizedError {
            var errorDescription: String? { "boom" }
        }
        XCTAssertEqual(UsageBudgetMonitoringError.classify(Boom()), .other("boom"))
    }

    func testCapMessageNamesTheCauseAndTheRemedy() {
        let message = UsageBudgetMonitoringError.excessiveActivities.userFacingMessage.lowercased()
        XCTAssertTrue(message.contains("too many"), "the message must name the cause")
        XCTAssertTrue(message.contains("close"), "the message must offer a remedy")
    }

    func testOtherMessageMentionsTheRefund() {
        let message = UsageBudgetMonitoringError.other("boom").userFacingMessage
        XCTAssertTrue(message.lowercased().contains("refunded"))
    }

    /// This one is raised *before* any charge, so it must not claim a refund the way the
    /// post-charge failures do — saying "refunded" here would tell the user colors moved
    /// when none did.
    func testNotAuthorizedMessageNamesTheRemedyAndPromisesNoRefund() {
        let message = UsageBudgetMonitoringError.notAuthorized.userFacingMessage.lowercased()
        XCTAssertTrue(message.contains("screen time"), "the message must name what is missing")
        XCTAssertTrue(message.contains("settings"), "the message must say where to fix it")
        XCTAssertFalse(message.contains("refunded"), "nothing was charged, so nothing was refunded")
    }
}
