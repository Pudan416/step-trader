import XCTest
@testable import Nowhere

@MainActor
final class SpentRestoreTests: XCTestCase {
    private var directory: URL!
    private var previousDirectory: URL?
    private var previousDefaults: [String: Any]?

    override func setUpWithError() throws {
        previousDefaults = UserDefaults.nowhere().persistentDomain(forName: SharedKeys.appGroupId)
        previousDirectory = PersistenceManager.storageDirectoryOverride
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("SpentRestore-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        PersistenceManager.storageDirectoryOverride = directory
    }

    override func tearDownWithError() throws {
        UserDefaults.nowhere().setPersistentDomain(previousDefaults ?? [:], forName: SharedKeys.appGroupId)
        PersistenceManager.storageDirectoryOverride = previousDirectory
        try FileManager.default.removeItem(at: directory)
    }

    func testFreshRestorePreservesSpendInMemoryDiskAndReload() async throws {
        try await checkRestore(previousToday: [:])
    }

    func testRestoreReplacesStaleProjectionWithoutLosingOtherDays() async throws {
        try await checkRestore(previousToday: ["stale-feed": 7])
    }

    private func checkRestore(previousToday: [String: Int]) async throws {
        let economy = UserEconomyStore(budgetEngine: MockBudgetEngine())
        economy.appStepsSpentToday = previousToday
        economy.appStepsSpentByDay = ["2000-01-01": ["historical-feed": 3]]
        economy.restoreDailySpend(totalSpent: 12, spentByApp: ["fixture-feed": 12])
        let today = AppModel.dayKey(for: .now)
        XCTAssertEqual(economy.spentSteps, 12)
        XCTAssertEqual(economy.appStepsSpentToday, ["fixture-feed": 12])
        XCTAssertEqual(economy.appStepsSpentByDay[today], ["fixture-feed": 12],
                       "Full sync reads today's per-app breakdown from this history map")
        XCTAssertEqual(economy.appStepsSpentByDay["2000-01-01"], ["historical-feed": 3])

        let file = directory.appendingPathComponent("appStepsSpentByDay.json")
        for _ in 0..<100 where !FileManager.default.fileExists(atPath: file.path) {
            try await Task.sleep(for: .milliseconds(10))
        }
        let saved = try JSONDecoder().decode([String: [String: Int]].self, from: Data(contentsOf: file))
        XCTAssertEqual(saved[today], ["fixture-feed": 12])
        XCTAssertEqual(saved["2000-01-01"], ["historical-feed": 3])

        let reloaded = UserEconomyStore(budgetEngine: MockBudgetEngine())
        await reloaded.loadAppStepsSpentToday()
        XCTAssertEqual(reloaded.appStepsSpentToday, ["fixture-feed": 12])
        XCTAssertEqual(reloaded.appStepsSpentByDay[today], ["fixture-feed": 12])
        XCTAssertEqual(reloaded.appStepsSpentByDay["2000-01-01"], ["historical-feed": 3])
    }
}
