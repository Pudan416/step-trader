import XCTest
@testable import Steps4

/// Guards DiagnosticsManager's pure payload-summarization: one summary per
/// non-empty diagnostic category, empty categories omitted. (The MetricKit
/// delivery path itself can't be unit-tested — MXDiagnostic* payloads aren't
/// constructible — so the summarization is factored out to be testable.)
final class DiagnosticsManagerTests: XCTestCase {

    private let ts = Date(timeIntervalSince1970: 1_700_000_000)

    func testOnlyNonEmptyCategoriesProduceSummaries() {
        let summaries = DiagnosticsManager.summaries(
            crashes: 2, hangs: 0, cpuExceptions: 1, diskWriteExceptions: 0,
            appVersion: "1.2 (34)", osVersion: "iOS 18.6", receivedAt: ts
        )
        XCTAssertEqual(summaries.map(\.type), ["crash", "cpu_exception"])
        XCTAssertEqual(summaries.first { $0.type == "crash" }?.count, 2)
        XCTAssertEqual(summaries.first { $0.type == "cpu_exception" }?.count, 1)
    }

    func testNoDiagnosticsProducesNoSummaries() {
        let summaries = DiagnosticsManager.summaries(
            crashes: 0, hangs: 0, cpuExceptions: 0, diskWriteExceptions: 0,
            appVersion: "1.2 (34)", osVersion: "iOS 18.6", receivedAt: ts
        )
        XCTAssertTrue(summaries.isEmpty)
    }

    func testAllCategoriesPreserveMetadataAndOrder() {
        let summaries = DiagnosticsManager.summaries(
            crashes: 1, hangs: 3, cpuExceptions: 1, diskWriteExceptions: 5,
            appVersion: "1.2 (34)", osVersion: "iOS 18.6", receivedAt: ts
        )
        XCTAssertEqual(summaries.map(\.type), ["crash", "hang", "cpu_exception", "disk_write_exception"])
        XCTAssertEqual(summaries.map(\.count), [1, 3, 1, 5])
        XCTAssertTrue(summaries.allSatisfy { $0.appVersion == "1.2 (34)" && $0.osVersion == "iOS 18.6" && $0.receivedAt == ts })
    }
}
