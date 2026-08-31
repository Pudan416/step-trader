#if DEBUG || INTERNAL_BUILD
import XCTest
@testable import Steps4

@MainActor
final class DayObjectsInstrumentAuditionControllerTests: XCTestCase {
    func testFreshControllerStartsWithSoundOff() {
        let controller = DayObjectsInstrumentAuditionController(
            bank: FakeAuditionBank(),
            audioSession: FakeAuditionSession()
        )

        XCTAssertEqual(controller.soundState, .off)
    }

    func testExplicitSoundOnActivatesSessionPreparesAndStartsBank() async {
        let bank = FakeAuditionBank()
        let session = FakeAuditionSession()
        let controller = DayObjectsInstrumentAuditionController(bank: bank, audioSession: session)
        bank.onStart = { XCTAssertEqual(controller.soundState, .starting) }

        await controller.turnSoundOn()

        XCTAssertEqual(controller.soundState, .on)
        XCTAssertEqual(session.activationCount, 1)
        XCTAssertEqual(bank.prepareCount, 1)
        XCTAssertEqual(bank.startCount, 1)
    }

    func testFailedStartLeavesRetryableErrorAndSecondExplicitStartCanSucceed() async {
        let bank = FakeAuditionBank()
        bank.shouldFailStart = true
        let session = FakeAuditionSession()
        let controller = DayObjectsInstrumentAuditionController(bank: bank, audioSession: session)

        await controller.turnSoundOn()
        XCTAssertEqual(controller.soundState, .error("Unable to start sound. Try again."))
        XCTAssertEqual(session.deactivationCount, 1)

        bank.shouldFailStart = false
        await controller.turnSoundOn()
        XCTAssertEqual(controller.soundState, .on)
        XCTAssertEqual(bank.startCount, 2)
    }

    func testChangingPresetReleasesExistingGatesAndStopPathsAreIdempotent() async {
        let bank = FakeAuditionBank()
        let controller = DayObjectsInstrumentAuditionController(bank: bank, audioSession: FakeAuditionSession())
        await controller.turnSoundOn()
        let secondPad = try! XCTUnwrap(controller.presets.dropFirst().first)

        controller.selectPreset(secondPad.id)
        await controller.stop()
        await controller.handleInterruption()

        XCTAssertEqual(bank.releaseAllCount, 2)
        XCTAssertEqual(bank.stopCount, 1)
        XCTAssertEqual(controller.soundState, .off)
    }

    func testCategoryCommandsDispatchOnlyWhenTheirCategoryIsMeaningful() async {
        let bank = FakeAuditionBank()
        let controller = DayObjectsInstrumentAuditionController(bank: bank, audioSession: FakeAuditionSession())
        await controller.turnSoundOn()

        controller.auditionHit()
        XCTAssertEqual(bank.fakeDrums.hitCount, 0)
        controller.selectCategory(.drums)
        controller.auditionNote()
        controller.auditionChord()
        controller.auditionHit()

        XCTAssertEqual(bank.pool.noteRequests.count, 0)
        XCTAssertEqual(bank.fakeDrums.hitCount, 1)
    }

    func testForegroundDoesNotResumeSound() async {
        let bank = FakeAuditionBank()
        let controller = DayObjectsInstrumentAuditionController(bank: bank, audioSession: FakeAuditionSession())

        controller.handleForeground()
        XCTAssertEqual(controller.soundState, .off)
        XCTAssertEqual(bank.startCount, 0)
    }

    func testEveryTonalCategoryExposesItsThreeManifestPresets() {
        let controller = DayObjectsInstrumentAuditionController(
            bank: FakeAuditionBank(),
            audioSession: FakeAuditionSession()
        )

        for category in [
            DayObjectsInstrumentCategory.pad,
            .pluck,
            .bass,
            .lead,
            .keys,
        ] {
            controller.selectCategory(category)
            XCTAssertEqual(controller.presets.count, 3, "\(category.rawValue) must expose its three licensed presets")
        }
    }

    func testLeadGestureStartsOnlyForLeadAndMapsXToSafeRegister() async {
        let bank = FakeAuditionBank()
        let controller = DayObjectsInstrumentAuditionController(bank: bank, audioSession: FakeAuditionSession())
        await controller.turnSoundOn()

        controller.beginLead(at: .init(x: 0, y: 0.5))
        XCTAssertTrue(bank.pool.noteRequests.isEmpty)

        controller.selectCategory(.lead)
        controller.beginLead(at: .init(x: 0, y: 0.5))
        XCTAssertEqual(bank.pool.noteRequests.last?.role, .lead)
        XCTAssertEqual(bank.pool.noteRequests.last?.midiNote, 57)
    }
}

@MainActor
private final class FakeAuditionSession: DayObjectsInstrumentAuditionSession {
    private(set) var activationCount = 0
    private(set) var deactivationCount = 0
    func activatePlayback() throws { activationCount += 1 }
    func deactivate() throws { deactivationCount += 1 }
}

@MainActor
private final class FakeAuditionBank: DayObjectsInstrumentBankProtocol {
    let descriptors = DayObjectsInstrumentManifest.defaultDescriptors
    var metrics: DayObjectsInstrumentBankMetrics {
        .init(
            state: .unprepared,
            tonalPoolCount: 0,
            graph: nil,
            allocationFingerprint: nil,
            drumMetrics: drums.metrics,
            pianoMetrics: piano.metrics
        )
    }
    let fakeDrums = FakeAuditionDrums()
    let fakePiano = FakeAuditionPiano()
    var drums: any DayObjectsDrumBankProtocol { fakeDrums }
    var piano: any DayObjectsPianoPoolProtocol { fakePiano }
    let pool = FakeAuditionPool()
    var shouldFailStart = false
    var onStart: (() -> Void)?
    private(set) var prepareCount = 0
    private(set) var startCount = 0
    private(set) var stopCount = 0
    private(set) var releaseAllCount = 0

    func prepare(configuration: DayObjectsInstrumentBankConfiguration) throws { prepareCount += 1 }
    func tonalPool(named id: String) throws -> DayObjectsTonalVoicePoolProtocol { pool }
    func start() throws {
        startCount += 1
        onStart?()
        if shouldFailStart { throw TestError.startFailed }
    }
    func stop() async { stopCount += 1 }
    func releaseAll() { releaseAllCount += 1 }
}

private final class FakeAuditionPool: DayObjectsTonalVoicePoolProtocol {
    private(set) var noteRequests: [DayObjectsTonalNoteRequest] = []
    var metrics: DayObjectsTonalPoolMetrics { .init(name: "audition", allocatedVoiceCount: 0, allocatedNodeCount: 0, activeVoiceCount: 0, activeLeadVoiceCount: 0, activeChordVoiceCount: 0) }
    func prepareInstrument(_ id: DayObjectsInstrumentID) throws {}
    func noteOn(_ request: DayObjectsTonalNoteRequest) -> DayObjectsVoiceToken? {
        noteRequests.append(request)
        return nil
    }
    func update(_ token: DayObjectsVoiceToken, with update: DayObjectsVoiceUpdate) {}
    func noteOff(_ token: DayObjectsVoiceToken) {}
    func releaseAll() {}
}

private final class FakeAuditionDrums: DayObjectsDrumBankProtocol {
    private(set) var hitCount = 0
    var metrics: DayObjectsDrumBankMetrics { .init(allocatedPlayerCount: 0, enabledVoiceCount: 0) }
    func hit(_ voice: DayObjectsDrumVoice, velocity: Double) { hitCount += 1 }
    func releaseAll() {}
}

private final class FakeAuditionPiano: DayObjectsPianoPoolProtocol {
    var metrics: DayObjectsFeltPianoMetrics { .init(allocatedPlayerCount: 0, activeNoteCount: 0, maximumPolyphony: 0) }
    func noteOn(_ midiNote: UInt8, velocity: Double) -> DayObjectsFeltPianoToken? { nil }
    func noteOff(_ token: DayObjectsFeltPianoToken) {}
    func releaseAll() {}
}

private enum TestError: Error { case startFailed }
#endif
