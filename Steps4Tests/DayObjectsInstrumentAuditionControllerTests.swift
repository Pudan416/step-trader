#if DEBUG || INTERNAL_BUILD
import Combine
import UIKit
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

        await controller.auditionHit()
        XCTAssertEqual(bank.fakeDrums.hitCount, 0)
        controller.selectCategory(.drums)
        await controller.auditionNote()
        await controller.auditionChord()
        await controller.auditionHit()

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

    func testLeadGestureHoldsOneTokenUpdatesFromNonzeroFirstMoveAndReleasesAtEnd() async {
        let bank = FakeAuditionBank()
        let controller = DayObjectsInstrumentAuditionController(bank: bank, audioSession: FakeAuditionSession())
        await controller.turnSoundOn()
        controller.selectCategory(.lead)

        controller.beginLead(at: .init(x: 0.75, y: 0.1))
        controller.beginLead(at: .init(x: 0.25, y: 0.9))
        controller.updateLead(at: .init(x: 1, y: 1))
        controller.updateLead(at: .init(x: 0, y: 0))
        controller.endLead()

        XCTAssertEqual(bank.pool.noteRequests.count, 2)
        XCTAssertEqual(bank.pool.updateRequests.count, 2)
        XCTAssertEqual(bank.pool.updateRequests[0].midiNote, 81)
        XCTAssertEqual(bank.pool.updateRequests[0].cutoffHz, DayObjectsAudioParameters.minimumCutoffHz)
        XCTAssertEqual(bank.pool.updateRequests[1].midiNote, 57)
        XCTAssertEqual(bank.pool.updateRequests[1].cutoffHz, DayObjectsAudioParameters.maximumCutoffHz)
        XCTAssertEqual(bank.pool.noteOffCount, 2)
    }

    func testOneLeadSurvivesMoveReturnToOriginAndDuplicateCancellation() async {
        let bank = FakeAuditionBank()
        let controller = DayObjectsInstrumentAuditionController(bank: bank, audioSession: FakeAuditionSession())
        await controller.turnSoundOn()
        controller.selectCategory(.lead)

        controller.beginLead(at: .init(x: 0.8, y: 0.2))
        controller.updateLead(at: .init(x: 0.4, y: 0.6))
        controller.updateLead(at: .init(x: 0, y: 0))
        controller.endLead()
        controller.endLead()

        XCTAssertEqual(bank.pool.noteRequests.count, 1)
        XCTAssertEqual(bank.pool.updateRequests.count, 2)
        XCTAssertEqual(bank.pool.noteOffCount, 1)
    }

    func testCategoryAvailabilityChangesForTonalAndDrumControls() async {
        let controller = DayObjectsInstrumentAuditionController(bank: FakeAuditionBank(), audioSession: FakeAuditionSession())
        await controller.turnSoundOn()
        XCTAssertTrue(controller.allowsNote)
        XCTAssertTrue(controller.allowsChord)
        XCTAssertFalse(controller.allowsHit)
        controller.selectCategory(.drums)
        XCTAssertFalse(controller.allowsNote)
        XCTAssertFalse(controller.allowsChord)
        XCTAssertTrue(controller.allowsHit)
    }

    func testActionFailureStopsBankAndDeactivatesBeforeRetry() async {
        let bank = FakeAuditionBank()
        let session = FakeAuditionSession()
        let controller = DayObjectsInstrumentAuditionController(bank: bank, audioSession: session)
        await controller.turnSoundOn()
        bank.pool.shouldFailPrepare = true

        await controller.auditionNote()

        XCTAssertEqual(controller.soundState, .error("Selected preset is unavailable. Try Sound again."))
        XCTAssertEqual(bank.stopCount, 1)
        XCTAssertEqual(session.deactivationCount, 1)
        bank.pool.shouldFailPrepare = false
        await controller.turnSoundOn()
        XCTAssertEqual(controller.soundState, .on)
    }

    func testDeactivationFailureRetainsOwnershipForExplicitRetry() async {
        let bank = FakeAuditionBank()
        let session = FakeAuditionSession()
        let controller = DayObjectsInstrumentAuditionController(bank: bank, audioSession: session)
        await controller.turnSoundOn()
        session.shouldFailDeactivation = true

        await controller.stop()
        XCTAssertEqual(controller.soundState, .error("Sound session is still active. Try stopping again."))
        XCTAssertEqual(session.deactivationCount, 1)

        session.shouldFailDeactivation = false
        await controller.stop()
        XCTAssertEqual(controller.soundState, .off)
        XCTAssertEqual(session.deactivationCount, 2)
    }

    func testConcurrentStopsCoalesceBeforeTheBankStopAwaits() async {
        let bank = FakeAuditionBank()
        bank.shouldSuspendStop = true
        let session = FakeAuditionSession()
        let controller = DayObjectsInstrumentAuditionController(bank: bank, audioSession: session)
        await controller.turnSoundOn()

        async let firstStop: Void = controller.stop()
        await Task.yield()
        async let secondStop: Void = controller.handleInterruption()
        await Task.yield()
        XCTAssertEqual(bank.stopCount, 1)

        bank.resumeStop()
        await firstStop
        await secondStop
        XCTAssertEqual(session.deactivationCount, 1)
        XCTAssertEqual(controller.soundState, .off)
    }

    func testLeadFailureThenStopMergesOneTeardownToOff() async {
        let bank = FakeAuditionBank()
        bank.shouldSuspendStop = true
        bank.pool.shouldFailPrepare = true
        let session = FakeAuditionSession()
        let controller = DayObjectsInstrumentAuditionController(bank: bank, audioSession: session)
        await controller.turnSoundOn()
        controller.selectCategory(.lead)

        controller.beginLead(at: .init(x: 0.5, y: 0.5))
        await Task.yield()
        async let stop: Void = controller.handleInterruption()
        await Task.yield()
        XCTAssertEqual(bank.stopCount, 1)

        bank.resumeStop()
        await stop
        XCTAssertEqual(session.deactivationCount, 1)
        XCTAssertEqual(controller.soundState, .off)
    }

    func testLeadFailureTeardownOutlivesDroppedControllerOwnership() async {
        let bank = FakeAuditionBank()
        bank.pool.shouldFailPrepare = true
        let session = FakeAuditionSession()
        var controller: DayObjectsInstrumentAuditionController? = .init(
            bank: bank,
            audioSession: session
        )
        await controller?.turnSoundOn()
        controller?.selectCategory(.lead)
        let controllerReference = WeakReference(controller)

        controller?.beginLead(at: .init(x: 0.5, y: 0.5))
        controller = nil

        for _ in 0..<100
        where bank.stopCount == 0 || session.deactivationCount == 0 || controllerReference.value != nil {
            await Task.yield()
        }
        XCTAssertEqual(bank.stopCount, 1)
        XCTAssertEqual(session.deactivationCount, 1)
        XCTAssertNil(controllerReference.value, "The completed teardown task must break its temporary controller cycle")
    }

    func testSystemAccessibilitySourceResamplesVoiceOverOnStatusNotification() {
        let notificationCenter = NotificationCenter()
        var isVoiceOverRunning = false
        let source = DayObjectsSystemAccessibilityStatusSource(
            notificationCenter: notificationCenter,
            voiceOverStatus: { isVoiceOverRunning }
        )

        XCTAssertFalse(source.isVoiceOverRunning)
        isVoiceOverRunning = true
        notificationCenter.post(
            name: UIAccessibility.voiceOverStatusDidChangeNotification,
            object: nil
        )
        XCTAssertTrue(source.isVoiceOverRunning)
    }

    func testLabViewUsesInjectedAccessibilityStatusToCancelHeldLead() async {
        let bank = FakeAuditionBank()
        let controller = DayObjectsInstrumentAuditionController(
            bank: bank,
            audioSession: FakeAuditionSession()
        )
        await controller.turnSoundOn()
        controller.selectCategory(.lead)
        controller.beginLead(at: .init(x: 0.5, y: 0.5))
        let accessibilityStatus = FakeAccessibilityStatusSource(isVoiceOverRunning: false)
        let view = DayObjectsLabView(
            auditionController: controller,
            accessibilityStatusSource: accessibilityStatus
        )

        accessibilityStatus.setVoiceOverRunning(true)

        withExtendedLifetime(view) {
            XCTAssertEqual(bank.pool.noteOffCount, 1)
        }
    }

    func testGridEnableCancelsHeldLeadExactlyOnceAndDisablesAudition() async {
        let harness = await makeLeadHarness()

        harness.coordinator.gridVisibilityChanged(isVisible: true)
        harness.coordinator.gridVisibilityChanged(isVisible: true)

        XCTAssertEqual(harness.bank.pool.noteOffCount, 1)
        XCTAssertFalse(harness.coordinator.allowsLeadGesture(isGridVisible: true))
        XCTAssertEqual(harness.bank.stopCount, 0, "Grid mode keeps Sound on for the manual buttons")
    }

    func testVoiceOverEnableCancelsHeldLeadExactlyOnceAndDisablesAudition() async {
        let harness = await makeLeadHarness()

        harness.accessibilityStatus.setVoiceOverRunning(true)
        harness.accessibilityStatus.setVoiceOverRunning(true)

        XCTAssertEqual(harness.bank.pool.noteOffCount, 1)
        XCTAssertFalse(harness.coordinator.allowsLeadGesture(isGridVisible: false))
    }

    func testGestureCancellationAndOverlayDisappearanceAreIdempotent() async {
        let gestureHarness = await makeLeadHarness()
        gestureHarness.coordinator.gestureDidEndOrCancel()
        gestureHarness.coordinator.gestureDidEndOrCancel()
        XCTAssertEqual(gestureHarness.bank.pool.noteOffCount, 1)

        let overlayHarness = await makeLeadHarness()
        overlayHarness.coordinator.overlayDidDisappear()
        overlayHarness.coordinator.overlayDidDisappear()
        XCTAssertEqual(overlayHarness.bank.pool.noteOffCount, 1)
    }

    func testViewDisappearanceCancelsLeadAndStopsOnce() async {
        let harness = await makeLeadHarness()

        let firstStop = harness.coordinator.viewDidDisappear()
        let secondStop = harness.coordinator.viewDidDisappear()
        await firstStop.value
        await secondStop.value

        XCTAssertEqual(harness.bank.pool.noteOffCount, 1)
        XCTAssertEqual(harness.bank.stopCount, 1)
        XCTAssertEqual(harness.session.deactivationCount, 1)
        XCTAssertEqual(harness.controller.soundState, .off)
    }

    func testInactiveSceneCancelsLeadAndStopsOnce() async {
        let harness = await makeLeadHarness()

        let firstStop = try! XCTUnwrap(harness.coordinator.sceneActivityChanged(isActive: false))
        let secondStop = try! XCTUnwrap(harness.coordinator.sceneActivityChanged(isActive: false))
        await firstStop.value
        await secondStop.value

        XCTAssertEqual(harness.bank.pool.noteOffCount, 1)
        XCTAssertEqual(harness.bank.stopCount, 1)
        XCTAssertEqual(harness.session.deactivationCount, 1)
        XCTAssertEqual(harness.controller.soundState, .off)
    }

    func testInterruptionCancelsLeadAndStopsOnce() async {
        let harness = await makeLeadHarness()

        let firstStop = harness.coordinator.interruptionBegan()
        let secondStop = harness.coordinator.interruptionBegan()
        await firstStop.value
        await secondStop.value

        XCTAssertEqual(harness.bank.pool.noteOffCount, 1)
        XCTAssertEqual(harness.bank.stopCount, 1)
        XCTAssertEqual(harness.session.deactivationCount, 1)
        XCTAssertEqual(harness.controller.soundState, .off)
    }

    private func makeLeadHarness() async -> (
        controller: DayObjectsInstrumentAuditionController,
        coordinator: DayObjectsLeadAuditionCoordinator,
        bank: FakeAuditionBank,
        session: FakeAuditionSession,
        accessibilityStatus: FakeAccessibilityStatusSource
    ) {
        let bank = FakeAuditionBank()
        let session = FakeAuditionSession()
        let controller = DayObjectsInstrumentAuditionController(bank: bank, audioSession: session)
        await controller.turnSoundOn()
        controller.selectCategory(.lead)
        controller.beginLead(at: .init(x: 0.5, y: 0.5))
        let accessibilityStatus = FakeAccessibilityStatusSource(isVoiceOverRunning: false)
        let coordinator = DayObjectsLeadAuditionCoordinator(
            controller: controller,
            accessibilityStatusSource: accessibilityStatus
        )
        return (controller, coordinator, bank, session, accessibilityStatus)
    }
}

private final class WeakReference<Object: AnyObject> {
    weak var value: Object?

    init(_ value: Object?) {
        self.value = value
    }
}

@MainActor
private final class FakeAccessibilityStatusSource: DayObjectsAccessibilityStatusSource {
    private let subject: CurrentValueSubject<Bool, Never>

    var isVoiceOverRunning: Bool { subject.value }
    var voiceOverStatusChanges: AnyPublisher<Bool, Never> {
        subject.eraseToAnyPublisher()
    }

    init(isVoiceOverRunning: Bool) {
        subject = .init(isVoiceOverRunning)
    }

    func setVoiceOverRunning(_ isVoiceOverRunning: Bool) {
        subject.send(isVoiceOverRunning)
    }
}

@MainActor
private final class FakeAuditionSession: DayObjectsInstrumentAuditionSession {
    private(set) var activationCount = 0
    private(set) var deactivationCount = 0
    var shouldFailDeactivation = false
    func activatePlayback() throws { activationCount += 1 }
    func deactivate() throws {
        deactivationCount += 1
        if shouldFailDeactivation { throw TestError.startFailed }
    }
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
    var shouldSuspendStop = false
    private var stopContinuation: CheckedContinuation<Void, Never>?

    func prepare(configuration: DayObjectsInstrumentBankConfiguration) throws { prepareCount += 1 }
    func tonalPool(named id: String) throws -> DayObjectsTonalVoicePoolProtocol { pool }
    func start() throws {
        startCount += 1
        onStart?()
        if shouldFailStart { throw TestError.startFailed }
    }
    func stop() async {
        stopCount += 1
        if shouldSuspendStop {
            await withCheckedContinuation { continuation in
                stopContinuation = continuation
            }
        }
    }
    func releaseAll() { releaseAllCount += 1 }

    func resumeStop() {
        stopContinuation?.resume()
        stopContinuation = nil
    }
}

private final class FakeAuditionPool: DayObjectsTonalVoicePoolProtocol {
    private(set) var noteRequests: [DayObjectsTonalNoteRequest] = []
    private(set) var updateRequests: [DayObjectsVoiceUpdate] = []
    private(set) var noteOffCount = 0
    var shouldFailPrepare = false
    var metrics: DayObjectsTonalPoolMetrics { .init(name: "audition", allocatedVoiceCount: 0, allocatedNodeCount: 0, activeVoiceCount: 0, activeLeadVoiceCount: 0, activeChordVoiceCount: 0) }
    func prepareInstrument(_ id: DayObjectsInstrumentID) throws {
        if shouldFailPrepare { throw TestError.startFailed }
    }
    func noteOn(_ request: DayObjectsTonalNoteRequest) -> DayObjectsVoiceToken? {
        noteRequests.append(request)
        return .init()
    }
    func update(_ token: DayObjectsVoiceToken, with update: DayObjectsVoiceUpdate) { updateRequests.append(update) }
    func noteOff(_ token: DayObjectsVoiceToken) { noteOffCount += 1 }
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
