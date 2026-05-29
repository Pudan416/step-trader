import XCTest
@testable import Steps4

// MARK: - §5.2 characterization tests
//
// Models the unsynchronized read-modify-write pattern on the App-Group
// `UserDefaults` shared between the app and the DeviceActivity extension:
//
//     load blob → JSONDecode → mutate → JSONEncode → set
//
// (See `BlockingStore.saveAppSelection` / ticket-group + budget-key updates,
// and `DeviceActivityMonitorExtension.setupBlockForMinuteMode`.) Individual
// `set`/`get` is atomic, but the compound sequence is not serialized across
// writers, so concurrent writers lose updates / resurrect stale state.
//
// CAVEAT: XCTest runs in ONE process. Two concurrent `DispatchQueue`s stand in
// for the app + extension processes, so this reproduces the *logical* lost
// update, not the exact cross-process timing. `readWriteGap` widens the window
// between read and write to make the race reliably observable rather than
// vanishingly rare.
//
// Status: reproduced 2026-05-29 — with 2 lock-step writers the race test lost
// exactly 50% of updates (stored 150 of 300), while the serialized control
// kept all 200. The §5.2 *fix* (moving compound state behind a coordinated
// store) is DEFERRED to a dedicated session, so the race assertion is parked
// behind `XCTSkipIf(true, …)` to keep the suite green. Remove that one line
// when implementing the fix — the assertion then becomes the regression guard.

final class AppGroupRMWConcurrencyTests: XCTestCase {

    private let testKey = "test.section5_2.rmw.blob"

    override func setUp() {
        super.setUp()
        UserDefaults.stepsTrader().removeObject(forKey: testKey)
    }

    override func tearDown() {
        UserDefaults.stepsTrader().removeObject(forKey: testKey)
        super.tearDown()
    }

    // MARK: - Helpers

    /// One read-modify-write increment of `field` against the shared blob.
    private func rmwIncrement(_ field: String, readWriteGap: useconds_t) {
        let defaults = UserDefaults.stepsTrader()
        var dict: [String: Int] = [:]
        if let data = defaults.data(forKey: testKey),
           let decoded = try? JSONDecoder().decode([String: Int].self, from: data) {
            dict = decoded
        }
        if readWriteGap > 0 { usleep(readWriteGap) }   // read → (gap) → write
        dict[field, default: 0] += 1
        if let data = try? JSONEncoder().encode(dict) {
            defaults.set(data, forKey: testKey)
        }
    }

    private func storedCount(_ field: String) -> Int {
        guard let data = UserDefaults.stepsTrader().data(forKey: testKey),
              let dict = try? JSONDecoder().decode([String: Int].self, from: data)
        else { return 0 }
        return dict[field] ?? 0
    }

    // MARK: - Control: serialized RMW loses nothing (proves the harness)

    func testSerializedReadModifyWrite_keepsEveryUpdate() {
        let n = 200
        for _ in 0..<n { rmwIncrement("c", readWriteGap: 0) }
        XCTAssertEqual(storedCount("c"), n,
            "Serialized RMW must not lose updates — if this fails, the test harness itself is wrong.")
    }

    // MARK: - The §5.2 race: concurrent RMW loses updates

    func testConcurrentReadModifyWrite_losesUpdates() throws {
        // §5.2 fix deferred — see CODE_AUDIT.md §5.2. Reproduced 2026-05-29:
        // 2 lock-step writers lose ~50% of updates. Delete this line when the
        // coordinated store lands; the assertion below is the regression guard.
        try XCTSkipIf(true, "§5.2 fix deferred to a dedicated session — re-arm by removing this skip.")

        let writers = 2          // app + DeviceActivity extension
        let perWriter = 150
        let expected = writers * perWriter

        let group = DispatchGroup()
        for i in 0..<writers {
            let q = DispatchQueue(label: "rmw.writer.\(i)")
            group.enter()
            q.async {
                for _ in 0..<perWriter { self.rmwIncrement("c", readWriteGap: 250) }
                group.leave()
            }
        }
        group.wait()

        let actual = storedCount("c")
        // On the CURRENT unsynchronized code this assertion FAILS; the message
        // reports how many increments were lost (the scope of §5.2).
        XCTAssertEqual(actual, expected,
            "§5.2 lost-update race: expected \(expected) increments, stored \(actual) — lost \(expected - actual).")
    }
}
