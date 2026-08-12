import XCTest
@testable import Steps4

@MainActor
final class HappeningShapeAssignmentModelTests: XCTestCase {

    private var storageDirectory: URL!

    override func setUp() {
        super.setUp()
        storageDirectory = FileManager.default.temporaryDirectory
            .appending(
                path: "HappeningShapeAssignmentModelTests-\(UUID().uuidString)",
                directoryHint: .isDirectory
            )
        try? FileManager.default.createDirectory(at: storageDirectory, withIntermediateDirectories: true)
        try? Data("{}".utf8).write(to: storageDirectory.appending(path: "pastDaySnapshots.json"))
        PersistenceManager.storageDirectoryOverride = storageDirectory
        clearKeys()
    }

    override func tearDown() {
        clearKeys()
        PersistenceManager.storageDirectoryOverride = nil
        try? FileManager.default.removeItem(at: storageDirectory)
        storageDirectory = nil
        super.tearDown()
    }

    private func clearKeys() {
        let defaults = UserDefaults.stepsTrader()
        for key in [
            SharedKeys.todayAdditions,
            SharedKeys.happeningCatalog,
            SharedKeys.happeningPaletteSelection,
            SharedKeys.happeningShapeNonce,
            SharedKeys.happeningShapeNonceDayKey,
        ] {
            defaults.removeObject(forKey: key)
        }
    }

    private func makeModel() -> AppModel {
        AppModel(
            healthKitService: MockHealthKitService(),
            familyControlsService: MockFamilyControlsService(),
            notificationService: MockNotificationService(),
            budgetEngine: MockBudgetEngine(),
            subscriptionStore: SubscriptionStore.shared
        )
    }

    func testEveryConfiguredHappeningHasAFigure() {
        let model = makeModel()
        model.loadDailyEnergyState()

        let figures = model.paletteFigures()
        for happening in model.configuredPaletteHappenings() {
            XCTAssertNotNil(figures[happening.id], "No figure for \(happening.id)")
        }
    }

    func testFiguresAreStableAcrossCalls() {
        let model = makeModel()
        model.loadDailyEnergyState()
        XCTAssertEqual(model.paletteFigures(), model.paletteFigures())
    }

    func testRerollChangesTheFigures() {
        let model = makeModel()
        model.loadDailyEnergyState()

        let before = model.paletteFigures()
        model.rerollPaletteFigures()

        XCTAssertNotEqual(before, model.paletteFigures())
    }

    /// Shake must not reach what is already on the canvas. The addition keeps
    /// the colour it was logged with however many times the field re-rolls.
    func testRerollDoesNotChangeAlreadyLoggedAdditions() {
        let model = makeModel()
        let date = Date(timeIntervalSince1970: 1_786_176_000)
        model.loadDailyEnergyState()
        _ = model.addHappening(id: "happening_walk", colorHex: "#AABBCC", at: date)

        model.rerollPaletteFigures(on: date)

        XCTAssertEqual(model.todayAdditions.first?.colorHex, "#AABBCC")
    }

    /// Ten tiles, ten colours — the roll is fed the configured ids, so this is
    /// really a check that the model passes them all in one call rather than
    /// rolling per happening.
    func testConfiguredHappeningsGetDistinctColours() {
        let model = makeModel()
        model.loadDailyEnergyState()

        let figures = model.paletteFigures()
        let colours = model.configuredPaletteHappenings().compactMap { figures[$0.id]?.colorHex }

        XCTAssertEqual(Set(colours).count, colours.count)
    }
}
