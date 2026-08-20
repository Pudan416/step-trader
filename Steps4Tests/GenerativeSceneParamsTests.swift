import XCTest
@testable import Steps4

/// The mapping layer between day data and the generative scene. The shader is
/// judged by eye; this is the part that has to be right by argument.
final class GenerativeSceneParamsTests: XCTestCase {

    // MARK: - Normalisation is smooth, not stepped

    func testEnergyRisesWithoutThresholds() {
        // The brief's step bands describe the result; a threshold in the
        // mapping would show up as a visible jump in the picture.
        var previous = GenerativeSceneParams.energy(forSteps: 0)
        for steps in stride(from: 100, through: 20_000, by: 100) {
            let value = GenerativeSceneParams.energy(forSteps: steps)
            XCTAssertGreaterThan(value, previous, "energy stalled at \(steps) steps")
            XCTAssertLessThanOrEqual(value, 1.0)
            previous = value
        }
    }

    func testEnergyIsZeroWithoutSteps() {
        XCTAssertEqual(GenerativeSceneParams.energy(forSteps: 0), 0)
        XCTAssertEqual(GenerativeSceneParams.energy(forSteps: -500), 0)
    }

    func testEnergyStillSeparatesLongDaysFromVeryLongOnes() {
        // A curve that saturates too early makes every active day identical.
        let long = GenerativeSceneParams.energy(forSteps: 12_000)
        let veryLong = GenerativeSceneParams.energy(forSteps: 20_000)
        XCTAssertGreaterThan(veryLong - long, 0.03)
    }

    func testClarityIsMonotoneInSleep() {
        var previous = GenerativeSceneParams.clarity(forSleepHours: 0)
        for quarter in 1...40 {
            let value = GenerativeSceneParams.clarity(forSleepHours: Double(quarter) / 4)
            XCTAssertGreaterThanOrEqual(value, previous)
            previous = value
        }
        XCTAssertEqual(GenerativeSceneParams.clarity(forSleepHours: 8), 1.0, accuracy: 0.001)
        XCTAssertEqual(GenerativeSceneParams.clarity(forSleepHours: 3), 0.0, accuracy: 0.001)
    }

    func testEventsSaturateNearTheNominalDayLength() {
        XCTAssertEqual(GenerativeSceneParams.events(forCount: 0), 0)
        XCTAssertGreaterThan(GenerativeSceneParams.events(forCount: 5), 0.8)
        XCTAssertLessThanOrEqual(GenerativeSceneParams.events(forCount: 50), 1.0)
    }

    // MARK: - Determinism

    func testSceneIsReproducibleFromTheDayKey() {
        let a = GenerativeSceneParams.forDay(dayKey: "2026-08-18", steps: 7_400, sleepHours: 7, eventCount: 3)
        let b = GenerativeSceneParams.forDay(dayKey: "2026-08-18", steps: 7_400, sleepHours: 7, eventCount: 3)
        XCTAssertEqual(a, b)
    }

    func testDifferentDaysGetDifferentSeeds() {
        let a = GenerativeSceneParams.seed(forDayKey: "2026-08-18")
        let b = GenerativeSceneParams.seed(forDayKey: "2026-08-19")
        XCTAssertNotEqual(a, b)
    }

    func testSeedStaysInUnitRange() {
        for day in 1...28 {
            let seed = GenerativeSceneParams.seed(forDayKey: String(format: "2026-08-%02d", day))
            XCTAssertTrue((0..<1).contains(seed), "seed out of range for day \(day): \(seed)")
        }
    }

    // MARK: - Inputs stay on separate axes

    func testStepsAndSleepDoNotShareAChannel() {
        // The failure this guards: both metrics reaching for brightness, so a
        // long day on a good night and a short day on a bad one land in the
        // same grey middle and the picture stops carrying information.
        let activeRested = GenerativeSceneParams.forDay(
            dayKey: "2026-08-18", steps: 15_000, sleepHours: 8.5, eventCount: 2)
        let idleTired = GenerativeSceneParams.forDay(
            dayKey: "2026-08-18", steps: 1_200, sleepHours: 4.0, eventCount: 2)

        XCTAssertGreaterThan(activeRested.energy - idleTired.energy, 0.5)
        XCTAssertGreaterThan(activeRested.clarity - idleTired.clarity, 0.5)

        let activeTired = GenerativeSceneParams.forDay(
            dayKey: "2026-08-18", steps: 15_000, sleepHours: 4.0, eventCount: 2)
        // Same steps, different night: energy must not move at all.
        XCTAssertEqual(activeTired.energy, activeRested.energy, accuracy: 0.0001)
        XCTAssertLessThan(activeTired.clarity, activeRested.clarity)
    }

    func testParametersAreClampedToUnitRange() {
        let params = GenerativeSceneParams(
            energy: 4.2, clarity: -1, events: 9, seed: 3.75, palette: .ocean)
        XCTAssertEqual(params.energy, 1)
        XCTAssertEqual(params.clarity, 0)
        XCTAssertEqual(params.events, 1)
        XCTAssertEqual(params.seed, 0.75, accuracy: 0.0001)
    }

    // MARK: - Palette

    func testPaletteIsDrawnFromTheExistingAppFamilies() {
        for seed in stride(from: 0.0, to: 1.0, by: 0.017) {
            let palette = GenerativeScenePalette.forSeed(seed)
            XCTAssertTrue(GenerativeScenePalette.all.contains(palette))
            XCTAssertEqual(palette.glow, AppColors.brandAccent)
        }
    }

    func testEveryPaletteFamilyIsReachable() {
        let names = Set(stride(from: 0.0, to: 1.0, by: 0.01)
            .map { GenerativeScenePalette.forSeed($0).name })
        XCTAssertEqual(names, Set(GenerativeScenePalette.all.map(\.name)))
    }
}
