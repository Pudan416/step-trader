import XCTest
@testable import Nowhere

@MainActor
final class SpentRestoreTests: XCTestCase {
    private var directory: URL!
    private var previousDirectory: URL?
    private var previousDefaults: [String: Any]?
    private var previousSession: Data?
    private var previousLegacySession: Data?
    private var previousUser: AppUser?
    private var previousAuthenticated = false
    private var previousAnonymous = false
    private var session: URLSession!
    private let userID = "spent-restore-fixture"

    override func setUp() async throws {
        try await super.setUp()
        let auth = AuthenticationService.shared
        await auth.waitForInitialization()
        previousUser = auth.currentUser
        previousAuthenticated = auth.isAuthenticated
        previousAnonymous = auth.isAnonymous
        previousSession = SessionKeychain.loadSession()
        previousLegacySession = UserDefaults.standard.data(forKey: "supabaseSession_v1")
        previousDefaults = UserDefaults.nowhere().persistentDomain(forName: SharedKeys.appGroupId)
        previousDirectory = PersistenceManager.storageDirectoryOverride
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("SpentRestore-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data("{}".utf8).write(to: directory.appendingPathComponent("pastDaySnapshots.json"))
        PersistenceManager.storageDirectoryOverride = directory
        let storedSession = Data("""
        {"access_token":"fixture-token","refresh_token":"fixture-refresh","token_type":"bearer",
        "expires_in":3600,"expires_at":"2099-01-01T00:00:00Z",
        "user":{"id":"\(userID)","created_at":"2024-01-01T00:00:00Z","is_anonymous":false}}
        """.utf8)
        SessionKeychain.deleteSession()
        UserDefaults.standard.set(storedSession, forKey: "supabaseSession_v1")
        auth.currentUser = AppUser(id: userID, email: nil, createdAt: .now)
        auth.isAuthenticated = true
        auth.isAnonymous = false
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [SpentRestoreResponseProtocol.self]
        session = URLSession(configuration: configuration)
        SpentRestoreResponseProtocol.reset(spentRow: try JSONEncoder().encode([
            DailySpentRow(userId: userID, dayKey: AppModel.dayKey(for: .now),
                          totalSpent: 12, spentByApp: ["fixture-feed": 12])
        ]))
    }

    override func tearDown() async throws {
        session.invalidateAndCancel()
        let auth = AuthenticationService.shared
        auth.currentUser = previousUser
        auth.isAuthenticated = previousAuthenticated
        auth.isAnonymous = previousAnonymous
        SessionKeychain.deleteSession()
        if let previousSession { _ = SessionKeychain.saveSession(previousSession) }
        UserDefaults.standard.set(previousLegacySession, forKey: "supabaseSession_v1")
        UserDefaults.nowhere().setPersistentDomain(previousDefaults ?? [:], forName: SharedKeys.appGroupId)
        PersistenceManager.storageDirectoryOverride = previousDirectory
        try FileManager.default.removeItem(at: directory)
        try await super.tearDown()
    }

    func testFreshRestorePreservesSpendInMemoryDiskAndOutgoingSync() async throws {
        try await checkRestore(previousToday: [:])
    }

    func testRestoreReplacesStaleProjectionWithoutLosingOtherDays() async throws {
        try await checkRestore(previousToday: ["stale-feed": 7])
    }

    private func checkRestore(previousToday: [String: Int]) async throws {
        let model = AppModel(
            healthKitService: MockHealthKitService(), familyControlsService: MockFamilyControlsService(),
            notificationService: MockNotificationService(), budgetEngine: MockBudgetEngine(),
            subscriptionStore: SubscriptionStore())
        model.isBootstrapping = true
        model.appStepsSpentToday = previousToday
        model.appStepsSpentByDay = ["2000-01-01": ["historical-feed": 3]]
        model.stepsToday = 1_000 // A real local day admits daily-spend full sync.
        let sync = SupabaseSyncService(network: NetworkClient(session: session))
        let restored = await sync.restoreFromServer(model: model)
        XCTAssertTrue(restored)
        let today = AppModel.dayKey(for: .now)
        XCTAssertEqual(model.spentStepsToday, 12)
        XCTAssertEqual(model.appStepsSpentToday, ["fixture-feed": 12])
        XCTAssertEqual(model.appStepsSpentByDay[today], ["fixture-feed": 12])
        XCTAssertEqual(model.appStepsSpentByDay["2000-01-01"], ["historical-feed": 3])

        let file = directory.appendingPathComponent("appStepsSpentByDay.json")
        for _ in 0..<100 where !FileManager.default.fileExists(atPath: file.path) {
            try await Task.sleep(for: .milliseconds(10))
        }
        let saved = try JSONDecoder().decode([String: [String: Int]].self, from: Data(contentsOf: file))
        XCTAssertEqual(saved[today], ["fixture-feed": 12])

        await sync.performFullSync(model: model)
        let rows = try SpentRestoreResponseProtocol.sentSpentRows().map {
            try JSONDecoder().decode(DailySpentRow.self, from: $0)
        }
        let row = try XCTUnwrap(rows.last)
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(row.totalSpent, 12)
        XCTAssertEqual(row.spentByApp, ["fixture-feed": 12])
        XCTAssertEqual(row.dayKey, today)
    }
}

private final class SpentRestoreResponseProtocol: URLProtocol, @unchecked Sendable {
    private static let lock = NSLock()
    private static var spentRow = Data()
    private static var sentRows: [Data] = []

    static func reset(spentRow: Data) {
        lock.lock()
        defer { lock.unlock() }
        self.spentRow = spentRow
        sentRows = []
    }

    static func sentSpentRows() -> [Data] {
        lock.lock()
        defer { lock.unlock() }
        return sentRows
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        var data = Data("[]".utf8)
        if request.url?.lastPathComponent == "user_daily_spent" {
            Self.lock.lock()
            if request.httpMethod == "GET" {
                data = Self.spentRow
            } else if request.httpMethod == "POST" {
                var body = request.httpBody ?? Data()
                if let stream = request.httpBodyStream {
                    stream.open()
                    defer { stream.close() }
                    var buffer = [UInt8](repeating: 0, count: 4096)
                    while stream.hasBytesAvailable {
                        let count = stream.read(&buffer, maxLength: buffer.count)
                        guard count > 0 else { break }
                        body.append(contentsOf: buffer.prefix(count))
                    }
                }
                Self.sentRows.append(body)
            }
            Self.lock.unlock()
        }
        let response = HTTPURLResponse(url: request.url!, statusCode: 200,
                                       httpVersion: nil, headerFields: ["Content-Type": "application/json"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
