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
}
