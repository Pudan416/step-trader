#if DEBUG || INTERNAL_BUILD
import AVFAudio
import Combine
import Foundation

enum DayObjectsInstrumentAuditionState: Equatable {
    case off
    case starting
    case on
    case stopping
    case error(String)
}

@MainActor
protocol DayObjectsInstrumentAuditionSession: AnyObject {
    func activatePlayback() throws
    func deactivate() throws
}

@MainActor
protocol DayObjectsAccessibilityStatusSource: AnyObject {
    var isVoiceOverRunning: Bool { get }
    var voiceOverStatusChanges: AnyPublisher<Bool, Never> { get }
}

@MainActor
final class DayObjectsLeadAuditionCoordinator: ObservableObject {
    @Published private(set) var isVoiceOverRunning: Bool

    private let controller: DayObjectsInstrumentAuditionController
    private let accessibilityStatusSource: any DayObjectsAccessibilityStatusSource
    private var accessibilityStatusCancellable: AnyCancellable?

    init(
        controller: DayObjectsInstrumentAuditionController,
        accessibilityStatusSource: any DayObjectsAccessibilityStatusSource
    ) {
        self.controller = controller
        self.accessibilityStatusSource = accessibilityStatusSource
        isVoiceOverRunning = accessibilityStatusSource.isVoiceOverRunning
        accessibilityStatusCancellable = accessibilityStatusSource.voiceOverStatusChanges
            .removeDuplicates()
            .sink { [weak self] isVoiceOverRunning in
                guard let self else { return }
                self.isVoiceOverRunning = isVoiceOverRunning
                if isVoiceOverRunning {
                    self.controller.endLead()
                }
            }
    }

    func allowsLeadGesture(isGridVisible: Bool) -> Bool {
        !isGridVisible && !isVoiceOverRunning && controller.allowsLeadXY
    }

    func gridVisibilityChanged(isVisible: Bool) {
        if isVisible {
            controller.endLead()
        }
    }

    func gestureDidEndOrCancel() {
        controller.endLead()
    }

    func overlayDidDisappear() {
        controller.endLead()
    }

    @discardableResult
    func viewDidDisappear() -> Task<Void, Never> {
        controller.endLead()
        return Task { @MainActor [controller] in
            await controller.stop()
        }
    }

    @discardableResult
    func sceneActivityChanged(isActive: Bool) -> Task<Void, Never>? {
        guard !isActive else {
            controller.handleForeground()
            return nil
        }
        controller.endLead()
        return Task { @MainActor [controller] in
            await controller.stop()
        }
    }

    @discardableResult
    func interruptionBegan() -> Task<Void, Never> {
        controller.endLead()
        return Task { @MainActor [controller] in
            await controller.handleInterruption()
        }
    }
}

@MainActor
final class DayObjectsSystemInstrumentAuditionSession: DayObjectsInstrumentAuditionSession {
    private let session: AVAudioSession

    init(session: AVAudioSession = .sharedInstance()) {
        self.session = session
    }

    func activatePlayback() throws {
        try session.setCategory(.playback)
        try session.setActive(true)
    }

    func deactivate() throws {
        try session.setActive(false, options: .notifyOthersOnDeactivation)
    }
}

@MainActor
final class DayObjectsInstrumentAuditionController: ObservableObject {
    @Published private(set) var soundState: DayObjectsInstrumentAuditionState = .off
    @Published private(set) var selectedCategory: DayObjectsInstrumentCategory = .pad
    @Published private(set) var selectedDescriptorID: DayObjectsInstrumentID?

    let bank: any DayObjectsInstrumentBankProtocol
    private let audioSession: any DayObjectsInstrumentAuditionSession
    private var isSessionActive = false
    private var bankMayOwnResources = false
    private var teardownTask: Task<Void, Never>?
    private var requestedTerminalState: DayObjectsInstrumentAuditionState?
    private var heldLead: (pool: DayObjectsTonalVoicePoolProtocol, token: DayObjectsVoiceToken)?

    convenience init() {
        self.init(
            bank: DayObjectsInstrumentBank(),
            audioSession: DayObjectsSystemInstrumentAuditionSession()
        )
    }

    init(
        bank: any DayObjectsInstrumentBankProtocol,
        audioSession: any DayObjectsInstrumentAuditionSession
    ) {
        self.bank = bank
        self.audioSession = audioSession
        selectedDescriptorID = bank.descriptors.first(where: { $0.category == .pad })?.id
    }

    var presets: [DayObjectsInstrumentDescriptor] {
        bank.descriptors.filter { $0.category == selectedCategory }
    }

    var selectedDescriptor: DayObjectsInstrumentDescriptor? {
        guard let selectedDescriptorID else { return presets.first }
        return presets.first { $0.id == selectedDescriptorID } ?? presets.first
    }

    var allowsNote: Bool { selectedCategory != .drums }
    var allowsChord: Bool { selectedCategory != .drums }
    var allowsHit: Bool { selectedCategory == .drums }
    var allowsLeadXY: Bool { soundState == .on && selectedCategory == .lead && teardownTask == nil }

    var attribution: String {
        guard let descriptor = selectedDescriptor else {
            switch selectedCategory {
            case .drums: return "Day Objects drum bank · bundled WAV sources"
            case .piano: return "Osiris Piano · CC0-1.0"
            default: return "No preset available"
            }
        }
        return "\(descriptor.bankName) · Synth One preset"
    }

    var diagnostics: String {
        switch soundState {
        case .off: return "Sound is off"
        case .starting: return "Preparing instrument bank"
        case .on: return "Bank ready · \(bank.metrics.tonalPoolCount) tonal pool"
        case .stopping: return "Stopping sound"
        case let .error(message): return message
        }
    }

    func selectCategory(_ category: DayObjectsInstrumentCategory) {
        guard selectedCategory != category else { return }
        releaseHeldGates()
        selectedCategory = category
        selectedDescriptorID = bank.descriptors.first(where: { $0.category == category })?.id
    }

    func selectPreset(_ id: DayObjectsInstrumentID) {
        guard presets.contains(where: { $0.id == id }), selectedDescriptorID != id else { return }
        releaseHeldGates()
        selectedDescriptorID = id
    }

    func turnSoundOn() async {
        guard soundState != .on, soundState != .starting, teardownTask == nil else { return }
        if isSessionActive || bankMayOwnResources {
            await requestTeardown(finalState: .off)
            guard !isSessionActive, !bankMayOwnResources else { return }
        }
        soundState = .starting
        do {
            try audioSession.activatePlayback()
            isSessionActive = true
            bankMayOwnResources = true
            try bank.prepare(configuration: Self.configuration)
            try bank.start()
            soundState = .on
        } catch {
            await actionFailed("Unable to start sound. Try again.")
        }
    }

    func stop() async {
        guard soundState != .off || isSessionActive || bankMayOwnResources || heldLead != nil else { return }
        await requestTeardown(finalState: .off)
    }

    func handleInterruption() async {
        await stop()
    }

    func handleForeground() {
        // Foregrounding must never revive sound; the next start remains an explicit user action.
    }

    func auditionNote() async {
        guard soundState == .on else { return }
        if selectedCategory == .piano {
            _ = bank.piano.noteOn(60, velocity: 0.82)
            return
        }
        guard let descriptor = selectedDescriptor else { return }
        await playTonal(descriptor, notes: [descriptor.referenceMIDI], role: .note)
    }

    func auditionChord() async {
        guard soundState == .on else { return }
        if selectedCategory == .piano {
            [48, 55, 60, 64].forEach { _ = bank.piano.noteOn(UInt8($0), velocity: 0.72) }
            return
        }
        guard let descriptor = selectedDescriptor else { return }
        await playTonal(descriptor, notes: descriptor.auditionChord, role: .chord)
    }

    func auditionHit() async {
        guard soundState == .on, selectedCategory == .drums else { return }
        bank.drums.hit(.kickFull, velocity: 0.82)
    }

    func beginLead(at point: DayObjectNormalizedPoint) {
        guard allowsLeadXY, let descriptor = selectedDescriptor else { return }
        endLead()
        do {
            let pool = try bank.tonalPool(named: DayObjectsTonalPoolSpecification.manualAudition.name)
            try pool.prepareInstrument(descriptor.id)
            let parameters = Self.leadParameters(point, descriptor: descriptor)
            guard let token = pool.noteOn(.init(
                instrumentID: descriptor.id,
                midiNote: parameters.note,
                velocity: 0.86,
                role: .lead,
                envelopeVariant: nil,
                pan: 0,
                delaySend: 0.18,
                reverbSend: 0.20
            )) else { return }
            heldLead = (pool, token)
        } catch {
            // Token allocation is synchronous. Cleanup may await the bank, but
            // no held Lead can be installed after this failure path starts.
            registerTeardown(finalState: .error("Lead audition is unavailable. Try Sound again."))
        }
    }

    func updateLead(at point: DayObjectNormalizedPoint) {
        guard allowsLeadXY, let heldLead, let descriptor = selectedDescriptor else { return }
        let parameters = Self.leadParameters(point, descriptor: descriptor)
        heldLead.pool.update(heldLead.token, with: .init(
            midiNote: Double(parameters.note),
            cutoffHz: parameters.cutoffHz
        ))
    }

    func endLead() {
        guard let heldLead else { return }
        heldLead.pool.noteOff(heldLead.token)
        self.heldLead = nil
    }

    private func playTonal(
        _ descriptor: DayObjectsInstrumentDescriptor,
        notes: [UInt8],
        role: DayObjectsTonalVoiceRole
    ) async {
        do {
            let pool = try bank.tonalPool(named: DayObjectsTonalPoolSpecification.manualAudition.name)
            try pool.prepareInstrument(descriptor.id)
            notes.forEach { note in
                _ = pool.noteOn(.init(
                    instrumentID: descriptor.id,
                    midiNote: note,
                    velocity: 0.78,
                    role: role,
                    envelopeVariant: nil,
                    pan: 0,
                    delaySend: 0.12,
                    reverbSend: 0.16
                ))
            }
        } catch {
            await actionFailed("Selected preset is unavailable. Try Sound again.")
        }
    }

    private func releaseHeldGates() {
        endLead()
        bank.releaseAll()
    }

    private func actionFailed(_ message: String) async {
        await requestTeardown(finalState: .error(message))
    }

    private func registerTeardown(finalState: DayObjectsInstrumentAuditionState) {
        requestedTerminalState = mergedTerminalState(requestedTerminalState, finalState)
        guard teardownTask == nil else { return }
        teardownTask = Task { @MainActor [self] in
            await performTeardown()
        }
    }

    private func requestTeardown(finalState: DayObjectsInstrumentAuditionState) async {
        registerTeardown(finalState: finalState)
        await teardownTask?.value
    }

    private func performTeardown() async {
        soundState = .stopping
        releaseHeldGates()
        if bankMayOwnResources {
            await bank.stop()
            bankMayOwnResources = false
        }
        if isSessionActive {
            do {
                try audioSession.deactivate()
                isSessionActive = false
            } catch {
                soundState = .error("Sound session is still active. Try stopping again.")
                requestedTerminalState = nil
                teardownTask = nil
                return
            }
        }
        soundState = requestedTerminalState ?? .off
        requestedTerminalState = nil
        teardownTask = nil
    }

    private func mergedTerminalState(
        _ current: DayObjectsInstrumentAuditionState?,
        _ incoming: DayObjectsInstrumentAuditionState
    ) -> DayObjectsInstrumentAuditionState {
        if current == .off || incoming == .off { return .off }
        return incoming
    }

    private static func leadParameters(
        _ point: DayObjectNormalizedPoint,
        descriptor: DayObjectsInstrumentDescriptor
    ) -> (note: UInt8, cutoffHz: Double) {
        let range = descriptor.manualAuditionSafeMIDIRange
        let semitones = Int(range.upperBound) - Int(range.lowerBound)
        let note = UInt8(Int(range.lowerBound) + Int((Double(semitones) * point.x).rounded()))
        let minimum = DayObjectsAudioParameters.minimumCutoffHz
        let maximum = DayObjectsAudioParameters.maximumCutoffHz
        let cutoffHz = minimum * pow(maximum / minimum, 1 - point.y)
        return (note, cutoffHz)
    }

    private static let configuration = DayObjectsInstrumentBankConfiguration(
        tonalPools: [.manualAudition],
        pianoVoiceCount: 4,
        drumOverlapCounts: Dictionary(uniqueKeysWithValues: DayObjectsDrumVoice.allCases.map { ($0, 2) })
    )
}

private extension DayObjectsInstrumentDescriptor {
    /// Safe manual registers keep direct Lead audition inside the instrument
    /// bank's supported MIDI bounds while preserving each descriptor's centre.
    var manualAuditionSafeMIDIRange: ClosedRange<UInt8> {
        let spread: Int
        switch category {
        case .bass:
            spread = 10
        case .lead:
            spread = 12
        case .pad, .pluck, .keys:
            spread = 14
        case .drums, .piano:
            spread = 0
        }

        let lowerBound = max(
            Int(DayObjectsAudioParameters.minimumMIDINote),
            Int(referenceMIDI) - spread
        )
        let upperBound = min(
            Int(DayObjectsAudioParameters.maximumMIDINote),
            Int(referenceMIDI) + spread
        )
        return UInt8(lowerBound)...UInt8(upperBound)
    }
}
#endif
