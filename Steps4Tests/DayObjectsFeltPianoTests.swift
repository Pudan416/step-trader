import AudioKit
import AVFoundation
import XCTest
@testable import Steps4

final class DayObjectsFeltPianoTests: XCTestCase {
    func testManifestDecodesExactCC0SamplesAndNearestRootZonesAcrossPlayableRegister() throws {
        let samples = try FeltPianoManifest.load(from: Bundle(for: type(of: self)))

        XCTAssertEqual(samples.map(\.rootMIDINote), [36, 40, 43, 48, 52, 55, 60, 64, 67, 72, 76, 79])
        XCTAssertEqual(samples.map(\.velocityLayer), Array(repeating: 1, count: 12))
        XCTAssertTrue(samples.allSatisfy {
            $0.sourceKey == "sfzinstruments/Osiris_Piano" &&
            $0.licenseFilename == "OsirisPiano-CC0-1.0.txt" &&
            $0.originalSHA256.count == 64 && $0.editedSHA256.count == 64
        })
        XCTAssertEqual(
            samples.map { $0.originalSHA256 + ":" + $0.editedSHA256 },
            [
                "cce3112e179b2bf20c4b18de67345a4cee8e2f981cdbf58d95e1758d14cc0ef1:033f516d8e0057b3a757e975996dc0d2134c0ad18878a9b097b626fac55af1c7",
                "d52280ab1804cf9ecd1dd93d8fc245a17b801ffdebe0ff47b07d965fb4f5bf45:52fc1f374b127ae0c0a5ca7574ca26edd121ad570b0be03827b9b5e723ffa96d",
                "af26a649cf2d3de12cf75ff8d403ede451f5c0c81e4cb0500adabb966b44da28:b1f50a4cf006d120d1da6f7127e3324b355e12a157a0de99e907cbe9279dd842",
                "4e509d501311b1fc7e6691cff1127f5a068a2292ec4501f94e68a36183a05e68:a00fd0a10d95de071b37d43684750df700f1ec3a5a36f6ace3401c9cbbb36f93",
                "58c4188910fd6feb1b31561936f146f89f376dfa9d29acfa7e0c574334a97869:03d091b7977d949587d06641fe775e648a85fa3f7d1d4a4a19823f707e11e203",
                "47a25644da5e4b770fd35ba29e53acded50a267985dad2f0d5e8f5a2698fe6ce:d7029053ac37c674351053ccee763cf4090bc0d6fc156b3c1f2d59b5155d997c",
                "f9e1ecef1ae24470796591f09d2d0aed4b320b5a376df8b7abf30c7880628545:07eb5a0d8abbdf039967b59cce5a75d4bb3d0dab2d2018e3dd57122d27dc1127",
                "592a756ccad9242f461a4af0542bc6bfdcbcfb3624e638baa2a0ac15eef773be:74c0748b394ce3b02d175938dd537ffcc0f51a9f54758ba855c5708a01f9b563",
                "f66433c9210a9a30544dd9b74c7a6688afc168a6476988b33b6745a21429f7af:6f8d9825f3c77fa2fbce627d610fe2c99ca4f32febb9208af966c08713e3f674",
                "b402a966e7a9fd5f165d07b92c53d90f06fca9430036c377432d4071de5ae4d5:a44461ea38774dcf0bbd9a2a406df418c6d63832b61790b56486edf58eacb99e",
                "d3f7e471c4b7ad9f45a6aa4451189423eba33d6d849f1a6603a357fa6f201f00:12b7182462c11c72e6bb7f3deac9c1a55b196cb510e7f6bbf74380c6ccfcdcf6",
                "f7b14111af1078676f761d6e1ff22ef368baf6b895acbe5cfd1555f74cc84ac2:d900e6d295f3cdd7e142c88564282ee58de3095fa9f715474a09e458f7e58b98",
            ]
        )

        let zones = FeltPianoManifest.nearestRootZones(for: samples)
        XCTAssertEqual(zones.count, samples.count)
        XCTAssertEqual(zones.first?.keyRange.lowerBound, 36)
        XCTAssertEqual(zones.last?.keyRange.upperBound, 83)
        XCTAssertEqual(Set(zones.flatMap { Array($0.keyRange) }), Set(36...83))
        XCTAssertTrue(zip(zones, zones.dropFirst()).allSatisfy { $0.keyRange.upperBound < $1.keyRange.lowerBound })
        for midi in 36...83 {
            let zone = try XCTUnwrap(zones.first { $0.keyRange.contains(UInt8(midi)) })
            XCTAssertEqual(FeltPianoManifest.sample(for: UInt8(midi), in: samples), zone.sample)
        }
    }

    func testRecipeUsesSoftBoundedAndSharedRoomShaping() {
        let recipe = DayObjectsFeltPianoRecipe.default

        XCTAssertGreaterThan(recipe.attackSeconds, 0)
        XCTAssertLessThanOrEqual(recipe.releaseSeconds, 0.75)
        XCTAssertGreaterThan(recipe.lowPassCutoffHz, 0)
        XCTAssertLessThan(recipe.mechanicalNoiseGain, 0.1)
        XCTAssertLessThan(recipe.noteTrimDB, 0)
        XCTAssertGreaterThan(recipe.roomSend, 0)
        XCTAssertGreaterThan(recipe.reverbSend, 0)
    }

    func testFixedPoolStealsOldestNoteWithoutPlayerGrowth() throws {
        let samples = try FeltPianoManifest.load(from: Bundle(for: type(of: self)))
        var players: [FakeFeltPianoPlayer] = []
        let piano = DayObjectsFeltPiano(
            samples: samples,
            resourceResolver: fixtureURL,
            playerFactory: { _, _ in
                let player = FakeFeltPianoPlayer()
                players.append(player)
                return player
            }
        )
        let baseline = piano.metrics

        let first = piano.noteOn(60, velocity: 0.8)
        XCTAssertNotNil(first)
        XCTAssertNotNil(piano.noteOn(64, velocity: 0.8))
        XCTAssertNotNil(piano.noteOn(67, velocity: 0.8))
        XCTAssertNotNil(piano.noteOn(71, velocity: 0.8))
        XCTAssertNotNil(piano.noteOn(72, velocity: 0.8))
        XCTAssertEqual(piano.metrics.activeNoteCount, baseline.maximumPolyphony)
        XCTAssertEqual(players.map(\.releaseCount).reduce(0, +), 1)

        for _ in 0..<1_000 { _ = piano.noteOn(60, velocity: 0.7) }
        XCTAssertEqual(piano.metrics.allocatedPlayerCount, baseline.allocatedPlayerCount)
        XCTAssertEqual(players.count, baseline.allocatedPlayerCount)
        XCTAssertFalse(piano.noteOff(first!))
        XCTAssertEqual(players.first?.playedNotes.first?.sample.rootMIDINote, 60)
        XCTAssertEqual(players.first?.playedNotes.first?.pitchCents, 0)
    }

    func testNearestRootSelectionPassesCentsWithoutChangingPlaybackRate() throws {
        var players: [FakeFeltPianoPlayer] = []
        let piano = DayObjectsFeltPiano(
            samples: try FeltPianoManifest.load(from: Bundle(for: type(of: self))),
            resourceResolver: fixtureURL,
            playerFactory: { _, _ in
                let player = FakeFeltPianoPlayer()
                players.append(player)
                return player
            }
        )

        _ = piano.noteOn(61, velocity: 0.8)

        let selectedSample = try XCTUnwrap(FeltPianoManifest.sample(for: 61, in: try FeltPianoManifest.load(from: Bundle(for: type(of: self)))))
        XCTAssertEqual(players.first?.playedNotes, [.init(midiNote: 61, velocity: 0.8, sample: selectedSample, pitchCents: 100)])
    }

    func testPreparationResolvesEveryCanonicalSampleBeforeAllocatingTheFixedPool() throws {
        let samples = try FeltPianoManifest.load(from: Bundle(for: type(of: self)))
        var resolved: [String] = []
        var playerCount = 0
        let piano = DayObjectsFeltPiano(
            samples: samples,
            resourceResolver: { sample in
                resolved.append(sample.filename)
                return URL(fileURLWithPath: "/fixtures/\(sample.filename)")
            },
            playerFactory: { _, _ in
                playerCount += 1
                return FakeFeltPianoPlayer()
            }
        )

        XCTAssertEqual(resolved, samples.map(\.filename))
        XCTAssertEqual(piano.preloadedSampleCount, samples.count)
        XCTAssertEqual(playerCount, piano.metrics.allocatedPlayerCount)
    }

    func testStopSendsAllNotesOffToEveryPreallocatedBackend() throws {
        var players: [FakeFeltPianoPlayer] = []
        let piano = DayObjectsFeltPiano(
            samples: try FeltPianoManifest.load(from: Bundle(for: type(of: self))),
            resourceResolver: fixtureURL,
            playerFactory: { _, _ in
                let player = FakeFeltPianoPlayer()
                players.append(player)
                return player
            }
        )
        _ = piano.noteOn(60, velocity: 0.7)
        _ = piano.noteOn(64, velocity: 0.7)

        piano.stop()

        XCTAssertEqual(piano.metrics.activeNoteCount, 0)
        XCTAssertTrue(players.allSatisfy { $0.allNotesOffCount == 1 })
    }

    func testMissingC4DisablesOnlyPianoRoleAndLeavesTonalContractUntouched() throws {
        let samples = try FeltPianoManifest.load(from: Bundle(for: type(of: self)))
        let piano = DayObjectsFeltPiano(
            samples: samples,
            resourceResolver: { $0.rootMIDINote == 60 ? nil : self.fixtureURL($0) },
            playerFactory: { _, _ in FakeFeltPianoPlayer() }
        )

        XCTAssertFalse(piano.isEnabled)
        XCTAssertNil(piano.noteOn(60, velocity: 0.8))
        XCTAssertEqual(piano.diagnostics, [.init(id: "day-objects.piano.resource-missing.felt-c4", role: .piano)])
        XCTAssertEqual(DayObjectsInstrumentManifest.descriptors(in: .keys).count, 3)
    }

    func testBackendPreloadFailureDisablesOnlyPianoWithStableDiagnostic() throws {
        let samples = try FeltPianoManifest.load(from: Bundle(for: type(of: self)))
        let piano = DayObjectsFeltPiano(
            samples: samples,
            resourceResolver: fixtureURL,
            playerFactory: { _, _ in throw DayObjectsFeltPianoBackendPreparationError.resourcePreloadFailed(samples[6]) }
        )

        XCTAssertFalse(piano.isEnabled)
        XCTAssertEqual(piano.preloadedSampleCount, 0)
        XCTAssertEqual(piano.diagnostics, [.init(id: "day-objects.piano.resource-preload-failed.felt-c4", role: .piano)])
        XCTAssertEqual(DayObjectsInstrumentManifest.descriptors(in: .keys).count, 3)
    }

    func testDetachedAudioKitBackendAppliesRecipeAndStopsEveryRootOnStealAndStop() throws {
        let samples = try FeltPianoManifest.load(from: Bundle(for: type(of: self)))
        let adapter = DayObjectsAudioKitFeltPiano(samples: samples, resourceResolver: bundledURL)
        let baseline = adapter.metrics

        XCTAssertTrue(adapter.piano.isEnabled)
        XCTAssertEqual(baseline.preloadedSampleCount, samples.count)
        XCTAssertEqual(baseline.loadedPlayerCount, baseline.fixedBackendCount * samples.count)
        XCTAssertEqual(baseline.appliedRecipe.mechanicalOnsetGain, DayObjectsFeltPianoRecipe.default.mechanicalNoiseGain, accuracy: 0.000_001)
        XCTAssertEqual(baseline.appliedRecipe.lowPassCutoffHz, DayObjectsFeltPianoRecipe.default.lowPassCutoffHz)
        XCTAssertEqual(baseline.appliedRecipe.mechanicalOnsetHighPassHz, DayObjectsFeltPianoRecipe.default.mechanicalOnsetHighPassHz)
        XCTAssertEqual(baseline.appliedRecipe.mechanicalOnsetBranchInputCount, 2)

        let releasedToken = try XCTUnwrap(adapter.piano.noteOn(61, velocity: 0.8))
        XCTAssertEqual(adapter.metrics.lastPlayedRootMIDINote, 60)
        XCTAssertEqual(adapter.metrics.lastPlayedPitchCents, 100)
        let beforeRelease = adapter.metrics.totalHardStoppedVoiceCount
        XCTAssertTrue(adapter.piano.noteOff(releasedToken))
        XCTAssertEqual(adapter.metrics.selectedRootMIDINotes, [60])
        XCTAssertEqual(adapter.metrics.releaseTailBackendCount, 1)
        XCTAssertEqual(adapter.metrics.totalHardStoppedVoiceCount, beforeRelease)

        _ = adapter.piano.noteOn(60, velocity: 0.8)
        _ = adapter.piano.noteOn(64, velocity: 0.8)
        _ = adapter.piano.noteOn(67, velocity: 0.8)
        _ = adapter.piano.noteOn(71, velocity: 0.8)
        let beforeSteal = adapter.metrics.totalHardStoppedVoiceCount
        _ = adapter.piano.noteOn(72, velocity: 0.8)
        XCTAssertEqual(adapter.metrics.totalHardStoppedVoiceCount - beforeSteal, 1)
        XCTAssertEqual(adapter.metrics.lastPlayedRootMIDINote, 72)
        XCTAssertEqual(adapter.metrics.lastPlayedPitchCents, 0)
        let beforeStop = adapter.metrics.totalHardStoppedVoiceCount

        adapter.piano.stop()

        XCTAssertEqual(adapter.metrics.totalHardStoppedVoiceCount - beforeStop, baseline.fixedBackendCount)
        XCTAssertTrue(adapter.metrics.selectedRootMIDINotes.isEmpty)
        XCTAssertEqual(adapter.metrics.releaseTailBackendCount, 0)
        XCTAssertEqual(adapter.metrics.loadedPlayerCount, baseline.loadedPlayerCount)
    }

    func testAudioKitBackendRejectsActualNilAndEmptyBufferedPlayersBeforeEnablingPiano() throws {
        let samples = try FeltPianoManifest.load(from: Bundle(for: type(of: self)))
        let format = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1))
        let emptyBuffer = try XCTUnwrap(AVAudioPCMBuffer(
            pcmFormat: format,
            frameCapacity: 1
        ))

        for makeInvalidPlayer in [
            { (player: AudioPlayer) in player.buffer = nil },
            { (player: AudioPlayer) in player.buffer = emptyBuffer },
        ] {
            let adapter = DayObjectsAudioKitFeltPiano(
                samples: samples,
                resourceResolver: bundledURL,
                bufferedPlayerLoader: { url in
                    let player = AudioPlayer(url: url, buffered: true)
                    if let player { makeInvalidPlayer(player) }
                    return player
                }
            )

            XCTAssertFalse(adapter.piano.isEnabled)
            XCTAssertEqual(adapter.metrics.preloadedSampleCount, 0)
            XCTAssertEqual(adapter.metrics.loadedPlayerCount, 0)
            XCTAssertEqual(adapter.piano.diagnostics, [.init(id: "day-objects.piano.resource-preload-failed.felt-c2", role: .piano)])
        }
    }

    private func fixtureURL(_ sample: FeltPianoSample) -> URL? {
        URL(fileURLWithPath: "/fixtures/\(sample.filename)")
    }

    private func bundledURL(_ sample: FeltPianoSample) -> URL? {
        let filename = sample.filename as NSString
        return Bundle(for: type(of: self)).url(
            forResource: filename.deletingPathExtension,
            withExtension: filename.pathExtension,
            subdirectory: "FeltPiano"
        )
    }
}

private final class FakeFeltPianoPlayer: DayObjectsFeltPianoBackend {
    private(set) var releaseCount = 0
    private(set) var allNotesOffCount = 0
    private(set) var playedNotes: [DayObjectsFeltPianoNote] = []

    func play(_ note: DayObjectsFeltPianoNote) { playedNotes.append(note) }
    func release() { releaseCount += 1 }
    func allNotesOff() { allNotesOffCount += 1 }
}
