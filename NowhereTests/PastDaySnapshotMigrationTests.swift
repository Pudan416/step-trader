import XCTest
@testable import Nowhere

@MainActor
final class PastDaySnapshotMigrationTests: XCTestCase {
    private var directory: URL!
    private var previousDirectory: URL?
    private var previousLegacyData: Data?
    private var defaults: UserDefaults!

    override func setUpWithError() throws {
        try super.setUpWithError()
        defaults = UserDefaults.nowhere()
        previousLegacyData = defaults.data(forKey: SharedKeys.pastDaySnapshots)
        previousDirectory = PersistenceManager.storageDirectoryOverride
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("PastDaySnapshotMigration-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        PersistenceManager.storageDirectoryOverride = directory
        defaults.removeObject(forKey: SharedKeys.pastDaySnapshots)
    }

    override func tearDownWithError() throws {
        if let previousLegacyData {
            defaults.set(previousLegacyData, forKey: SharedKeys.pastDaySnapshots)
        } else {
            defaults.removeObject(forKey: SharedKeys.pastDaySnapshots)
        }
        PersistenceManager.storageDirectoryOverride = previousDirectory
        try FileManager.default.removeItem(at: directory)
        try super.tearDownWithError()
    }

    func testFailedMigrationPreservesLegacyAcrossLoadsThenRetriesSuccessfully() throws {
        let expected = history()
        let legacy = try JSONEncoder().encode(expected)
        defaults.set(legacy, forKey: SharedKeys.pastDaySnapshots)
        let blockedDirectory = directory.appendingPathComponent("blocked")
        try Data("not a directory".utf8).write(to: blockedDirectory)
        PersistenceManager.storageDirectoryOverride = blockedDirectory

        XCTAssertEqual(makeModel().loadPastDaySnapshots(), expected)
        XCTAssertEqual(defaults.data(forKey: SharedKeys.pastDaySnapshots), legacy)
        XCTAssertEqual(makeModel().loadPastDaySnapshots(), expected,
                       "A second launch must still have the only saved copy")
        XCTAssertEqual(defaults.data(forKey: SharedKeys.pastDaySnapshots), legacy)

        try FileManager.default.removeItem(at: blockedDirectory)
        try FileManager.default.createDirectory(at: blockedDirectory, withIntermediateDirectories: true)

        XCTAssertEqual(makeModel().loadPastDaySnapshots(), expected)
        XCTAssertEqual(try readFile(), expected)
        XCTAssertNil(defaults.data(forKey: SharedKeys.pastDaySnapshots))
        XCTAssertEqual(makeModel().loadPastDaySnapshots(), expected,
                       "History remains available after the legacy key is removed")
    }

    func testSuccessfulMigrationWritesCompleteHistoryBeforeRemovingLegacy() throws {
        let expected = history()
        defaults.set(try JSONEncoder().encode(expected), forKey: SharedKeys.pastDaySnapshots)

        XCTAssertEqual(makeModel().loadPastDaySnapshots(), expected)
        XCTAssertEqual(try readFile(), expected)
        XCTAssertNil(defaults.data(forKey: SharedKeys.pastDaySnapshots))
    }

    func testExistingHistoryFileTakesPrecedenceOverLegacyWithoutDeletingIt() throws {
        let expected = history()
        try JSONEncoder().encode(expected).write(
            to: PersistenceManager.pastDaySnapshotsFileURL, options: .atomic)
        let legacy = try JSONEncoder().encode(["2000-01-01": PastDaySnapshot(
            inkEarned: 5, inkSpent: 0, happeningIds: [])])
        defaults.set(legacy, forKey: SharedKeys.pastDaySnapshots)

        XCTAssertEqual(makeModel().loadPastDaySnapshots(), expected)
        XCTAssertEqual(defaults.data(forKey: SharedKeys.pastDaySnapshots), legacy)
    }

    private func history() -> [String: PastDaySnapshot] {
        ["2026-10-01": PastDaySnapshot(
            inkEarned: 31, inkSpent: 12, happeningIds: ["event_walk"],
            steps: 2_400, sleepHours: 8, happeningTagCounts: ["movement": 1],
            dayTitle: "A walk home")]
    }

    private func readFile() throws -> [String: PastDaySnapshot] {
        try JSONDecoder().decode([String: PastDaySnapshot].self,
                                 from: Data(contentsOf: PersistenceManager.pastDaySnapshotsFileURL))
    }

    private func makeModel() -> AppModel {
        let model = AppModel(
            healthKitService: MockHealthKitService(),
            familyControlsService: MockFamilyControlsService(),
            notificationService: MockNotificationService(),
            budgetEngine: MockBudgetEngine(), subscriptionStore: SubscriptionStore())
        model.isBootstrapping = true
        return model
    }
}
