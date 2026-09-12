#if DEBUG || INTERNAL_BUILD
import AudioKit
import AudioKitEX
import AudioToolbox
import AVFoundation
import Foundation
import SoundpipeAudioKit

final class DayObjectsCategoryValidatedTonalPool: DayObjectsTonalVoicePoolProtocol {
    let pool: DayObjectsTonalVoicePoolProtocol
    let descriptors: [DayObjectsInstrumentID: DayObjectsInstrumentDescriptor]
    let preparedInstruments: [DayObjectsInstrumentID: NormalizedSynthVoice]

    init(pool: DayObjectsTonalVoicePoolProtocol, descriptors: [DayObjectsInstrumentID: DayObjectsInstrumentDescriptor], preparedInstruments: [DayObjectsInstrumentID: NormalizedSynthVoice]) {
        self.pool = pool
        self.descriptors = descriptors
        self.preparedInstruments = preparedInstruments
    }

    var metrics: DayObjectsTonalPoolMetrics { pool.metrics }

    func prepareInstrument(_ id: DayObjectsInstrumentID) throws {
        guard let descriptor = descriptors[id] else { throw DayObjectsInstrumentBankError.unknownInstrument(id) }
        guard descriptor.category != .drums, descriptor.category != .piano else {
            throw DayObjectsInstrumentBankError.invalidTonalInstrumentCategory(descriptor.category)
        }
        guard preparedInstruments[id] != nil else { throw DayObjectsInstrumentBankError.unknownInstrument(id) }
        try pool.prepareInstrument(id)
    }

    func prepareInstruments(_ ids: [DayObjectsInstrumentID]) throws {
        for id in ids {
            guard let descriptor = descriptors[id] else { throw DayObjectsInstrumentBankError.unknownInstrument(id) }
            guard descriptor.category != .drums, descriptor.category != .piano else {
                throw DayObjectsInstrumentBankError.invalidTonalInstrumentCategory(descriptor.category)
            }
            guard preparedInstruments[id] != nil else { throw DayObjectsInstrumentBankError.unknownInstrument(id) }
        }
        try pool.prepareInstruments(ids)
    }

    func noteOn(_ request: DayObjectsTonalNoteRequest) -> DayObjectsVoiceToken? {
        guard let descriptor = descriptors[request.instrumentID], descriptor.category != .drums, descriptor.category != .piano, preparedInstruments[request.instrumentID] != nil else { return nil }
        return pool.noteOn(request)
    }
    func noteOn(
        _ request: DayObjectsTonalNoteRequest,
        atHostTime hostTime: TimeInterval
    ) -> DayObjectsVoiceToken? {
        guard let descriptor = descriptors[request.instrumentID], descriptor.category != .drums, descriptor.category != .piano, preparedInstruments[request.instrumentID] != nil else { return nil }
        return pool.noteOn(request, atHostTime: hostTime)
    }
    func update(_ token: DayObjectsVoiceToken, with update: DayObjectsVoiceUpdate) { pool.update(token, with: update) }
    func noteOff(_ token: DayObjectsVoiceToken) { pool.noteOff(token) }
    func releaseAll() { pool.releaseAll() }
}

final class DayObjectsInactiveDrumBank: DayObjectsDrumBankProtocol {
    var metrics: DayObjectsDrumBankMetrics { .init(allocatedPlayerCount: 0, enabledVoiceCount: 0) }
    func hit(_ voice: DayObjectsDrumVoice, velocity: Double) {}
    func releaseAll() {}
}

final class DayObjectsInactivePianoPool: DayObjectsPianoPoolProtocol {
    var metrics: DayObjectsFeltPianoMetrics { .init(allocatedPlayerCount: 0, activeNoteCount: 0, maximumPolyphony: 0) }
    func noteOn(_ midiNote: UInt8, velocity: Double) -> DayObjectsFeltPianoToken? { nil }
    func noteOff(_ token: DayObjectsFeltPianoToken) {}
    func releaseAll() {}
}

final class DayObjectsAudioKitTonalPoolAdapter: DayObjectsTonalVoicePoolProtocol {
    let adapter: DayObjectsAudioKitTonalPool
    init(_ adapter: DayObjectsAudioKitTonalPool) { self.adapter = adapter }
    var metrics: DayObjectsTonalPoolMetrics { adapter.pool.metrics }
    func prepareInstrument(_ id: DayObjectsInstrumentID) throws { try adapter.pool.prepareInstrument(id) }
    func prepareInstruments(_ ids: [DayObjectsInstrumentID]) throws { try adapter.pool.prepareInstruments(ids) }
    func noteOn(_ request: DayObjectsTonalNoteRequest) -> DayObjectsVoiceToken? { adapter.pool.noteOn(request) }
    func noteOn(
        _ request: DayObjectsTonalNoteRequest,
        atHostTime hostTime: TimeInterval
    ) -> DayObjectsVoiceToken? {
        adapter.pool.noteOn(request, atHostTime: hostTime)
    }
    func update(_ token: DayObjectsVoiceToken, with update: DayObjectsVoiceUpdate) { adapter.pool.update(token, with: update) }
    func noteOff(_ token: DayObjectsVoiceToken) { adapter.pool.noteOff(token) }
    func releaseAll() { adapter.pool.releaseAll() }
}

final class DayObjectsAudioKitDrumBankAdapter: DayObjectsDrumBankProtocol {
    let adapter: DayObjectsAudioKitDrumBank
    init(_ adapter: DayObjectsAudioKitDrumBank) { self.adapter = adapter }
    var metrics: DayObjectsDrumBankMetrics { adapter.bank.metrics }
    func hit(_ voice: DayObjectsDrumVoice, velocity: Double) { adapter.bank.hit(voice, velocity: velocity) }
    func schedule(_ hit: DayObjectsScheduledDrumHit) { adapter.bank.schedule(hit) }
    func releaseAll() { adapter.releaseAll() }
}

final class DayObjectsAudioKitPianoPoolAdapter: DayObjectsPianoPoolProtocol {
    let adapter: DayObjectsAudioKitFeltPiano
    init(_ adapter: DayObjectsAudioKitFeltPiano) { self.adapter = adapter }
    var metrics: DayObjectsFeltPianoMetrics { adapter.piano.metrics }
    func noteOn(_ midiNote: UInt8, velocity: Double) -> DayObjectsFeltPianoToken? { adapter.piano.noteOn(midiNote, velocity: velocity) }
    func noteOn(_ request: DayObjectsPianoNoteRequest) -> DayObjectsFeltPianoToken? {
        adapter.room.dryWetMix = AUValue(min(max(request.roomSend, 0), 1))
        adapter.reverb.dryWetMix = AUValue(min(max(request.reverbSend, 0), 1))
        return adapter.piano.noteOn(request)
    }
    func updateExpression(_ token: DayObjectsFeltPianoToken, expression: Double) {
        adapter.piano.updateExpression(token, expression: expression)
    }
    func update(_ token: DayObjectsFeltPianoToken, with update: DayObjectsPianoVoiceUpdate) {
        adapter.update(token, with: update)
    }
    func noteOff(_ token: DayObjectsFeltPianoToken) { _ = adapter.piano.noteOff(token) }
    func releaseAll() { adapter.piano.stop() }
}
#endif
