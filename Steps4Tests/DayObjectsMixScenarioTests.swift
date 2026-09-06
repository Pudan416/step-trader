#if DEBUG || INTERNAL_BUILD
import AVFAudio
import XCTest
@testable import Steps4

@MainActor
final class DayObjectsMixScenarioTests: XCTestCase {
    private static let scenarioDurationSeconds = 60.0
    private static let scenarioSampleRate = 48_000.0

    func testRendererRejectsDurationsOutsideOneToSixtySeconds() async throws {
        let renderer = DayObjectsOfflineMixRenderer(bundle: Bundle(for: type(of: self)))
        let plan = makePlan()

        for duration in [0, 0.999, 60.001, .infinity, .nan] {
            do {
                _ = try await renderer.render(
                    plan: plan,
                    durationSeconds: duration,
                    sampleRate: 48_000
                )
                XCTFail("Expected duration \(duration) to be rejected")
            } catch {
                XCTAssertEqual(error as? DayObjectsOfflineMixRendererError, .invalidDuration)
            }
        }
    }

    func testRendererRejectsUnsupportedSampleRates() async throws {
        let renderer = DayObjectsOfflineMixRenderer(bundle: Bundle(for: type(of: self)))
        let plan = makePlan()

        for sampleRate in [0, 7_999, 384_001, .infinity, .nan] {
            do {
                _ = try await renderer.render(
                    plan: plan,
                    durationSeconds: 1,
                    sampleRate: sampleRate
                )
                XCTFail("Expected sample rate \(sampleRate) to be rejected")
            } catch {
                XCTAssertEqual(error as? DayObjectsOfflineMixRendererError, .unsupportedSampleRate)
            }
        }
    }

    func testRendererUsesStereoFloatPCMAndReturnsExactlyRequestedFrames() async throws {
        let renderer = DayObjectsOfflineMixRenderer(bundle: Bundle(for: type(of: self)))

        let buffer = try await renderer.render(
            plan: makePlan(),
            durationSeconds: 1,
            sampleRate: 48_000
        )

        XCTAssertEqual(buffer.format.commonFormat, .pcmFormatFloat32)
        XCTAssertFalse(buffer.format.isInterleaved)
        XCTAssertEqual(buffer.format.channelCount, 2)
        XCTAssertEqual(buffer.format.sampleRate, 48_000, accuracy: 0.001)
        XCTAssertEqual(buffer.frameLength, 48_000)
        let channels = try XCTUnwrap(buffer.floatChannelData)
        let peak = (0..<Int(buffer.frameLength)).reduce(Float.zero) { partial, index in
            max(partial, abs(channels[0][index]), abs(channels[1][index]))
        }
        XCTAssertGreaterThan(peak, 0.000_001)
    }

    func testRendererReleasesProcessLeaseWhenCancelledAfterOfflineBegin() async throws {
        let renderer = DayObjectsOfflineMixRenderer(
            bundle: Bundle(for: type(of: self)),
            offlineBeginCheckpoint: { throw CancellationError() }
        )

        do {
            _ = try await renderer.render(
                plan: makePlan(),
                durationSeconds: 1,
                sampleRate: 48_000
            )
            XCTFail("Expected injected cancellation")
        } catch {
            XCTAssertTrue(error is CancellationError)
        }

        let secondRenderer = DayObjectsOfflineMixRenderer(bundle: Bundle(for: type(of: self)))
        let buffer = try await secondRenderer.render(
            plan: makePlan(),
            durationSeconds: 1,
            sampleRate: 48_000
        )
        XCTAssertEqual(buffer.frameLength, 48_000)
    }

    func testQuietOfflineRenderDoesNotEstimateFalseRequiredPeakAttenuation() async throws {
        let renderer = DayObjectsOfflineMixRenderer(bundle: Bundle(for: type(of: self)))

        let buffer = try await renderer.render(
            plan: makePlan(),
            durationSeconds: 1,
            sampleRate: 48_000
        )

        let loudness = try DayObjectsStereoCaptureAdapter.analyze(buffer)
        XCTAssertLessThan(
            loudness.truePeakDBTP,
            DayObjectsPersistentMasterGraph.limiterCeilingDBFS - 1
        )
        let diagnostics = try XCTUnwrap(renderer.lastDiagnostics)
        XCTAssertLessThan(
            diagnostics.maximumEstimatedLimiterReductionDB,
            0.1,
            "A signal with at least 1 dB of output headroom must not estimate required attenuation"
        )
    }

    func testExportsEqualInputSoundWorldPreviewsWhenExplicitlyRequested() async throws {
        let environment = ProcessInfo.processInfo.environment
        guard environment["DAY_OBJECTS_SOUND_WORLD_PREVIEWS"] == "1" else {
            throw XCTSkip("Set DAY_OBJECTS_SOUND_WORLD_PREVIEWS=1 to export the two listening references")
        }
        let outputDirectory = environment["DAY_OBJECTS_SOUND_WORLD_PREVIEW_DIR"]
            .flatMap { $0.isEmpty ? nil : URL(fileURLWithPath: $0, isDirectory: true) }
            ?? FileManager.default.temporaryDirectory
                .appendingPathComponent("day-objects-sound-worlds", isDirectory: true)
        try FileManager.default.createDirectory(
            at: outputDirectory,
            withIntermediateDirectories: true
        )
        let input = DayMusicInput(
            countedSteps: 7_500,
            stepGoal: 10_000,
            countedSleepHours: 6.5,
            sleepGoalHours: 8,
            happeningIDs: (0..<10).map { "preview-happening-\($0)" },
            spentColors: 25
        )
        let seed: UInt64 = 0xD4A0_B1EC_75ED_0001

        for world in DayObjectsSoundWorld.allCases {
            let plan = DeterministicMusicDirector.makePlan(
                input: input,
                remixSeed: seed,
                soundWorld: world
            )
            let renderer = DayObjectsOfflineMixRenderer(
                bundle: Bundle(for: type(of: self)),
                leadGestureProfile: .held
            )
            let buffer = try await renderer.render(
                plan: plan,
                durationSeconds: 24,
                sampleRate: Self.scenarioSampleRate
            )
            let outputURL = outputDirectory
                .appendingPathComponent("\(world.rawValue).wav")
            if FileManager.default.fileExists(atPath: outputURL.path) {
                try FileManager.default.removeItem(at: outputURL)
            }
            let file = try AVAudioFile(
                forWriting: outputURL,
                settings: buffer.format.settings
            )
            try file.write(from: buffer)

            let loudness = try DayObjectsStereoCaptureAdapter.analyze(buffer)
            XCTAssertTrue(loudness.containsOnlyFiniteSamples)
            XCTAssertGreaterThan(loudness.integratedLUFS, -120)
            XCTAssertLessThanOrEqual(loudness.truePeakDBTP, -1)
            print(
                "DAY_OBJECTS_SOUND_WORLD_PREVIEW \(world.rawValue) "
                    + "path=\(outputURL.path) lufs=\(loudness.integratedLUFS) "
                    + "dbtp=\(loudness.truePeakDBTP)"
            )
        }
    }

    func testProductionIsolationWithSelectedRoleHavingNoSourceIsSilentFromFrameZero() async throws {
        let renderer = DayObjectsOfflineMixRenderer(
            bundle: Bundle(for: type(of: self)),
            auditionMode: .isolatedBus(.lead),
            leadGestureProfile: .none
        )

        let buffer = try await renderer.render(
            plan: makePlan(),
            durationSeconds: 1,
            sampleRate: 48_000
        )
        let channels = try XCTUnwrap(buffer.floatChannelData)
        let maximumMagnitude = (0..<Int(buffer.frameLength)).reduce(Float.zero) { peak, frame in
            max(peak, abs(channels[0][frame]), abs(channels[1][frame]))
        }
        let report = try DayObjectsStereoCaptureAdapter.analyze(buffer)

        XCTAssertEqual(maximumMagnitude, 0, accuracy: 0.000_000_1)
        XCTAssertEqual(report.integratedLUFS, -120)
        XCTAssertEqual(report.truePeakDBTP, -120)
    }

    func testScenarioDefinitionCoversEveryRequiredAxisAndIsolationCheck() throws {
        let scenarios = try makeScenarios()
        let variantsByCategory = Dictionary(grouping: scenarios, by: \.category)
            .mapValues { Set($0.map(\.variant)) }

        XCTAssertEqual(variantsByCategory["steps"], ["0", "25", "50", "75", "100"])
        XCTAssertEqual(variantsByCategory["sleep"], ["low", "mid", "full"])
        XCTAssertEqual(variantsByCategory["happenings"], ["0", "1", "10"])
        XCTAssertEqual(variantsByCategory["glitch"], ["0", "25", "50", "100"])
        XCTAssertEqual(variantsByCategory["groove"], ["percussion", "bass-pulse", "bass-arp", "bass-bed"])
        XCTAssertEqual(variantsByCategory["bass"], [
            "bass.analog-boom", "bass.hey-jakob", "bass.bassliner", "bass.jec-hollores-2",
        ])
        XCTAssertEqual(variantsByCategory["lead"], ["slow", "fast"])
        XCTAssertEqual(variantsByCategory["worst-case"], ["four-tails-kick-bass-chord-held-lead"])
        XCTAssertEqual(variantsByCategory["isolated"], [
            "rhythm", "bass", "harmony", "happenings", "lead",
        ])
        let isolatedScenarios = scenarios.filter { $0.category == "isolated" }
        XCTAssertTrue(isolatedScenarios.allSatisfy { $0.leadGestureProfile == .held })
        XCTAssertEqual(scenarios.count, 31)
    }

    func testScenarioJSONUsesExplicitEstimatedLimiterGateName() throws {
        let result = ScenarioResult(
            id: "fixture",
            category: "fixture",
            variant: "fixture",
            seed: "1",
            grooveMode: "percussion",
            bassInstrumentID: nil,
            integratedLUFS: -17,
            truePeakDBTP: -1.2,
            durationSeconds: 60,
            renderWallTimeSeconds: 1,
            containsOnlyFiniteSamples: true,
            maximumEstimatedLimiterReductionDB: 0.5,
            averageRoleRMSDBFS: [:],
            maximumRolePeakDBFS: [:],
            maximumRoleActiveVoiceCount: [:],
            stressActivities: [],
            stressTransportSubdivision: nil,
            transportSubdivisionsWereMonotonic: true,
            harmonyTransition: nil,
            scheduledBassReleaseHostTimeSeconds: nil,
            actualBassReleaseHostTimeSeconds: nil,
            bassActiveVoiceCountAfterRelease: nil
        )

        let json = try XCTUnwrap(String(
            data: JSONEncoder().encode(result),
            encoding: .utf8
        ))

        XCTAssertTrue(json.contains("\"maximumEstimatedLimiterReductionDB\""))
        XCTAssertFalse(json.contains("\"maximumLimiterReductionDB\""))
    }

    func testWorstCaseWaitsForRealTransportSecondChordBoundaryInsteadOfInjectingFuturePosition() async throws {
        let scenario = try XCTUnwrap(try makeScenarios().first { $0.category == "worst-case" })
        let transition = try XCTUnwrap(
            scenario.plan.harmony.roles
                .filter { $0.gain > 0 }
                .flatMap(\.chordSchedule)
                .filter { $0.startBar > 0 }
                .min {
                    if $0.startBar == $1.startBar { return $0.chordIndex < $1.chordIndex }
                    return $0.startBar < $1.startBar
                }
        )
        let transitionSubdivision = Int64(transition.startBar)
            * MusicalPosition.subdivisionsPerBar
        let expectedHostTime = 1
            + (Double(transitionSubdivision) * 15 / scenario.plan.rhythm.tempoBPM)
        let renderer = DayObjectsOfflineMixRenderer(
            bundle: Bundle(for: type(of: self)),
            auditionMode: scenario.auditionMode,
            leadGestureProfile: scenario.leadGestureProfile,
            stressProfile: scenario.stressProfile
        )

        _ = try await renderer.render(
            plan: scenario.plan,
            durationSeconds: expectedHostTime,
            sampleRate: Self.scenarioSampleRate
        )

        let diagnostics = try XCTUnwrap(renderer.lastDiagnostics)
        let activities = diagnostics.stressActivities
        let harmony = try XCTUnwrap(diagnostics.harmonyTransition)
        XCTAssertTrue(diagnostics.transportSubdivisionsWereMonotonic)
        XCTAssertEqual(diagnostics.stressTransportSubdivision, transitionSubdivision)
        XCTAssertEqual(harmony.chordIndex, transition.chordIndex)
        XCTAssertEqual(harmony.startSubdivision, transitionSubdivision)
        XCTAssertEqual(harmony.startHostTimeSeconds, expectedHostTime, accuracy: 0.000_000_001)
        XCTAssertGreaterThan(harmony.oldVoiceCount, 0)
        XCTAssertGreaterThan(harmony.newVoiceCount, 0)
        XCTAssertGreaterThan(harmony.maximumAudibleProgress, 0)
        XCTAssertGreaterThan(harmony.maximumNewChordExpression, 0)
        XCTAssertGreaterThan(
            try XCTUnwrap(harmony.firstAudibleProgressHostTimeSeconds),
            harmony.startHostTimeSeconds
        )
        XCTAssertEqual(activities.count, 8)
        XCTAssertEqual(Set(activities.map(\.hostTimeSeconds)).count, 1)
        XCTAssertTrue(
            activities.allSatisfy {
                abs($0.hostTimeSeconds - expectedHostTime) <= 0.000_000_001
            },
            "Stress must be triggered by the real monotonically advancing transport boundary"
        )
        XCTAssertEqual(Set(activities.map(\.component)), [
            .kickSoft, .bassAttack, .chordTransition, .heldLead, .happeningTail,
        ])
        XCTAssertEqual(activities.filter { $0.component == .kickSoft }.count, 1)
        XCTAssertEqual(activities.filter { $0.component == .bassAttack }.count, 1)
        XCTAssertEqual(activities.filter { $0.component == .chordTransition }.count, 1)
        XCTAssertEqual(activities.filter { $0.component == .heldLead }.count, 1)
        let happeningActivities = activities.filter { $0.component == .happeningTail }
        XCTAssertEqual(happeningActivities.count, 4)
        XCTAssertEqual(Set(happeningActivities.map(\.identifier)).count, 4)
        XCTAssertGreaterThanOrEqual(
            diagnostics.maximumRoleActiveVoiceCount[.happenings, default: 0],
            4
        )
        let scheduledRelease = try XCTUnwrap(diagnostics.scheduledBassReleaseHostTimeSeconds)
        let actualRelease = try XCTUnwrap(diagnostics.actualBassReleaseHostTimeSeconds)
        XCTAssertEqual(scheduledRelease, expectedHostTime + 0.220, accuracy: 0.000_000_001)
        XCTAssertEqual(actualRelease, scheduledRelease, accuracy: 0.5 / Self.scenarioSampleRate)
        XCTAssertEqual(diagnostics.bassActiveVoiceCountAfterRelease, 0)
        XCTAssertLessThan(
            try XCTUnwrap(harmony.firstAudibleProgressHostTimeSeconds),
            actualRelease,
            "The short Bass gate must remain active long enough to overlap audible chord progress"
        )
    }

    func testWorstCaseThrowsWhenFourHappeningTailsCannotBeAuditioned() async throws {
        let scenario = try XCTUnwrap(try makeScenarios().first { $0.category == "worst-case" })
        let fullPlan = scenario.plan
        let incompletePlan = DayMusicPlan(
            seed: fullPlan.seed,
            input: fullPlan.input,
            world: fullPlan.world,
            rhythm: fullPlan.rhythm,
            groove: fullPlan.groove,
            bass: fullPlan.bass,
            harmony: fullPlan.harmony,
            happenings: Array(fullPlan.happenings.prefix(2)),
            lead: fullPlan.lead,
            glitch: fullPlan.glitch,
            mix: fullPlan.mix
        )
        let renderer = DayObjectsOfflineMixRenderer(
            bundle: Bundle(for: type(of: self)),
            leadGestureProfile: .held,
            stressProfile: .fourHappeningTailsWithKickBassChordAndHeldLead
        )

        do {
            _ = try await renderer.render(
                plan: incompletePlan,
                durationSeconds: 12,
                sampleRate: Self.scenarioSampleRate
            )
            XCTFail("Expected the incomplete four-tail stress audition to fail")
        } catch {
            XCTAssertEqual(
                error as? DayObjectsOfflineMixRendererError,
                .stressAuditionFailed(.happeningTail)
            )
        }
    }

    func testSixtySecondScenarioMatrixWhenExplicitlyRequested() async throws {
        guard ProcessInfo.processInfo.environment["DAY_OBJECTS_AUDIO_RENDER_MATRIX"] == "1" else {
            throw XCTSkip("Set DAY_OBJECTS_AUDIO_RENDER_MATRIX=1 for the 31 x 60-second acceptance matrix")
        }
        let scenarios = try makeScenarios()
        var results: [ScenarioResult] = []
        results.reserveCapacity(scenarios.count)
        for (index, scenario) in scenarios.enumerated() {
            print(
                "DAY_OBJECTS_SCENARIO \(index + 1)/\(scenarios.count) \(scenario.id) "
                    + "bass=\(scenario.plan.bass?.instrumentID.rawValue ?? "none")"
            )
            let result = try await measure(scenario)
            guard result.renderWallTimeSeconds <= 60 else {
                XCTFail("\(result.id) exceeded the 60-second render limit")
                return
            }
            results.append(result)
            print(
                "DAY_OBJECTS_RESULT \(result.id) lufs=\(result.integratedLUFS) "
                    + "dbtp=\(result.truePeakDBTP) "
                    + "maximumEstimatedLimiterReductionDB=\(result.maximumEstimatedLimiterReductionDB) "
                    + "renderWall=\(result.renderWallTimeSeconds)"
            )
        }

        let isolated = results.filter { $0.category == "isolated" }
        let isolatedFocus = isolated.filter { ["harmony", "happenings", "lead"].contains($0.variant) }
        let isolatedSpread = (isolatedFocus.map(\.integratedLUFS).max() ?? -120)
            - (isolatedFocus.map(\.integratedLUFS).min() ?? -120)
        let glitchZero = try XCTUnwrap(results.first { $0.id == "glitch-0" })
        let glitchFull = try XCTUnwrap(results.first { $0.id == "glitch-100" })
        let glitchDifference = abs(glitchZero.integratedLUFS - glitchFull.integratedLUFS)
        let report = ScenarioMatrixReport(
            schemaVersion: 3,
            durationSeconds: Self.scenarioDurationSeconds,
            sampleRateHz: Int(Self.scenarioSampleRate),
            analyzer: Self.analyzerDescription,
            scenarios: results,
            comparisons: .init(
                isolatedHarmonyHappeningLeadSpreadLU: isolatedSpread,
                glitchZeroToFullDifferenceLU: glitchDifference
            )
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let reportData = try encoder.encode(report)
        let reportURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("day-objects-mix-scenario-report.json")
        try reportData.write(to: reportURL, options: .atomic)
        print("DAY_OBJECTS_REPORT_PATH=\(reportURL.path)")

        for result in results {
            XCTAssertTrue(result.containsOnlyFiniteSamples, result.id)
            XCTAssertEqual(result.durationSeconds, 60, accuracy: 0.000_001, result.id)
            XCTAssertLessThanOrEqual(result.renderWallTimeSeconds, 60, result.id)
            XCTAssertLessThanOrEqual(result.truePeakDBTP, -1, result.id)
            if result.id == "isolated-bass" {
                XCTAssertEqual(result.integratedLUFS, -120, result.id)
                XCTAssertEqual(result.truePeakDBTP, -120, result.id)
            } else {
                XCTAssertGreaterThan(result.integratedLUFS, -120, result.id)
            }
            if result.category != "worst-case" {
                XCTAssertLessThan(result.maximumEstimatedLimiterReductionDB, 2, result.id)
            }
        }
        let representativeIDs: Set<String> = [
            "steps-50", "sleep-mid", "happenings-1", "glitch-25",
            "groove-percussion", "groove-bass-pulse", "groove-bass-arp", "groove-bass-bed",
        ]
        for result in results where representativeIDs.contains(result.id) {
            XCTAssertTrue((-18 ... -16).contains(result.integratedLUFS),
                          "\(result.id): \(result.integratedLUFS) LUFS-I")
        }
        XCTAssertLessThanOrEqual(isolatedSpread, 1.5)
        XCTAssertLessThanOrEqual(glitchDifference, 1)
        let worst = try XCTUnwrap(results.first { $0.category == "worst-case" })
        XCTAssertEqual(worst.stressActivities.count, 8)
        XCTAssertEqual(Set(worst.stressActivities.map(\.hostTimeSeconds)).count, 1)
        XCTAssertEqual(worst.stressActivities.filter { $0.component == .happeningTail }.count, 4)
        XCTAssertGreaterThanOrEqual(worst.maximumRoleActiveVoiceCount["happenings", default: 0], 4)
        try assertWorstCaseTransportEvidence(worst)
    }

    func testControlledCalibrationProbeWhenExplicitlyRequested() async throws {
        let environment = ProcessInfo.processInfo.environment
        guard environment["DAY_OBJECTS_AUDIO_CALIBRATION_PROBE"] == "1" else {
            throw XCTSkip("Set DAY_OBJECTS_AUDIO_CALIBRATION_PROBE=1 for controlled calibration evidence")
        }
        let selection = environment["DAY_OBJECTS_AUDIO_CALIBRATION_SELECTION"] ?? "batch-a"
        let label = environment["DAY_OBJECTS_AUDIO_CALIBRATION_LABEL"] ?? selection
        let selectedIDs: Set<String>
        switch selection {
        case "batch-a":
            selectedIDs = [
                "steps-50", "sleep-mid", "happenings-1", "glitch-25",
                "groove-percussion", "groove-bass-pulse", "groove-bass-arp", "groove-bass-bed",
            ]
        case "guard":
            selectedIDs = [
                "steps-50", "worst-case-overlap",
                "isolated-rhythm", "isolated-bass", "isolated-harmony",
                "isolated-happenings", "isolated-lead",
                "glitch-0", "glitch-100", "bass-bb-roys-phaser",
            ]
        case "bb":
            selectedIDs = ["bass-bb-roys-phaser"]
        case "arp":
            selectedIDs = ["groove-bass-arp"]
        case "steps":
            selectedIDs = ["steps-50"]
        case "steps-trio":
            selectedIDs = ["steps-0", "steps-50", "steps-100"]
        case "percussion":
            selectedIDs = ["groove-percussion"]
        case "isolated-support":
            selectedIDs = ["isolated-harmony", "isolated-happenings", "isolated-lead"]
        case "crest-guards":
            selectedIDs = [
                "steps-50", "groove-percussion",
                "isolated-rhythm", "isolated-bass", "isolated-harmony",
                "isolated-happenings", "isolated-lead",
            ]
        case "worst":
            selectedIDs = ["worst-case-overlap"]
        default:
            throw DayObjectsAudioError("Unknown calibration selection: \(selection)")
        }

        let scenarios = try makeScenarios().filter { selectedIDs.contains($0.id) }
        XCTAssertEqual(scenarios.count, selectedIDs.count)
        var results: [ScenarioResult] = []
        for (index, scenario) in scenarios.enumerated() {
            print("DAY_OBJECTS_CALIBRATION \(index + 1)/\(scenarios.count) \(label) \(scenario.id)")
            let result = try await measure(scenario)
            print(
                "DAY_OBJECTS_CALIBRATION_RESULT \(label) \(result.id) "
                    + "lufs=\(result.integratedLUFS) dbtp=\(result.truePeakDBTP) "
                    + "maximumEstimatedLimiterReductionDB=\(result.maximumEstimatedLimiterReductionDB) "
                    + "roleRMS=\(result.averageRoleRMSDBFS) renderWall=\(result.renderWallTimeSeconds)"
            )
            guard result.renderWallTimeSeconds <= 60 else {
                XCTFail("\(result.id) exceeded the 60-second render limit")
                return
            }
            results.append(result)
        }

        if environment["DAY_OBJECTS_AUDIO_CALIBRATION_ASSERT_ACCEPTANCE"] == "1" {
            if selection == "arp" {
                XCTAssertEqual(results.count, 1)
                let result = try XCTUnwrap(results.first)
                XCTAssertEqual(result.id, "groove-bass-arp")
                XCTAssertTrue(result.containsOnlyFiniteSamples)
                XCTAssertEqual(result.durationSeconds, 60, accuracy: 0.000_001)
                XCTAssertLessThanOrEqual(result.renderWallTimeSeconds, 60)
                XCTAssertLessThanOrEqual(result.truePeakDBTP, -1)
                XCTAssertTrue((-18 ... -16).contains(result.integratedLUFS))
                XCTAssertLessThanOrEqual(result.maximumEstimatedLimiterReductionDB, 1.7)
            } else if selection == "steps" || selection == "percussion" {
                XCTAssertEqual(results.count, 1)
                let result = try XCTUnwrap(results.first)
                XCTAssertEqual(result.id, selection == "steps" ? "steps-50" : "groove-percussion")
                XCTAssertTrue(result.containsOnlyFiniteSamples)
                XCTAssertEqual(result.durationSeconds, 60, accuracy: 0.000_001)
                XCTAssertLessThanOrEqual(result.renderWallTimeSeconds, 60)
                XCTAssertLessThanOrEqual(result.truePeakDBTP, -1)
                XCTAssertTrue((-18 ... -16).contains(result.integratedLUFS))
                XCTAssertLessThan(result.maximumEstimatedLimiterReductionDB, 2)
            } else if selection == "steps-trio" {
                XCTAssertEqual(Set(results.map(\.id)), ["steps-0", "steps-50", "steps-100"])
                for result in results {
                    XCTAssertTrue(result.containsOnlyFiniteSamples, result.id)
                    XCTAssertEqual(result.durationSeconds, 60, accuracy: 0.000_001, result.id)
                    XCTAssertLessThanOrEqual(result.renderWallTimeSeconds, 60, result.id)
                    XCTAssertLessThanOrEqual(result.truePeakDBTP, -1, result.id)
                    XCTAssertGreaterThan(result.integratedLUFS, -120, result.id)
                    XCTAssertLessThan(result.maximumEstimatedLimiterReductionDB, 2, result.id)
                }
                for id in ["steps-50", "steps-100"] {
                    let representative = try XCTUnwrap(results.first { $0.id == id })
                    XCTAssertTrue((-18 ... -16).contains(representative.integratedLUFS), id)
                }
            } else if selection == "isolated-support" {
                XCTAssertEqual(results.count, 3)
                for result in results {
                    XCTAssertTrue(result.containsOnlyFiniteSamples, result.id)
                    XCTAssertEqual(result.durationSeconds, 60, accuracy: 0.000_001, result.id)
                    XCTAssertLessThanOrEqual(result.renderWallTimeSeconds, 60, result.id)
                    XCTAssertLessThanOrEqual(result.truePeakDBTP, -1, result.id)
                    XCTAssertGreaterThan(result.integratedLUFS, -120, result.id)
                    XCTAssertLessThan(result.maximumEstimatedLimiterReductionDB, 2, result.id)
                }
                let spread = (results.map(\.integratedLUFS).max() ?? -120)
                    - (results.map(\.integratedLUFS).min() ?? -120)
                XCTAssertLessThanOrEqual(spread, 1.5)
            } else if selection == "crest-guards" {
                try assertCrestGuardAcceptance(results)
            } else if selection == "worst" {
                XCTAssertEqual(results.count, 1)
                let result = try XCTUnwrap(results.first)
                XCTAssertEqual(result.id, "worst-case-overlap")
                XCTAssertTrue(result.containsOnlyFiniteSamples)
                XCTAssertEqual(result.durationSeconds, 60, accuracy: 0.000_001)
                XCTAssertLessThanOrEqual(result.renderWallTimeSeconds, 60)
                XCTAssertLessThanOrEqual(result.truePeakDBTP, -1)
                try assertWorstCaseTransportEvidence(result)
            } else {
                try assertGuardAcceptance(results)
            }
        }

        let report = CalibrationProbeReport(
            schemaVersion: 3,
            calibrationLabel: label,
            durationSeconds: Self.scenarioDurationSeconds,
            sampleRateHz: Int(Self.scenarioSampleRate),
            analyzer: Self.analyzerDescription,
            scenarios: results
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let reportData = try encoder.encode(report)
        let safeLabel = label.map { $0.isLetter || $0.isNumber || $0 == "-" ? $0 : "-" }
        let reportURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("day-objects-calibration-\(String(safeLabel)).json")
        try reportData.write(to: reportURL, options: .atomic)
        print("DAY_OBJECTS_CALIBRATION_REPORT_PATH=\(reportURL.path)")
    }

    private func makePlan() -> DayMusicPlan {
        DeterministicMusicDirector.makePlan(
            input: DayMusicInput(
                countedSteps: 7_500,
                stepGoal: 10_000,
                countedSleepHours: 6,
                sleepGoalHours: 8,
                happeningIDs: ["offline-a", "offline-b"],
                spentColors: 25
            ),
            remixSeed: 0x0FF1_1E
        )
    }

    private func makeScenarios() throws -> [Scenario] {
        let baselineSeed: UInt64 = 0xC411_BA7E
        let baseline = input()
        var scenarios: [Scenario] = []

        for progress in [0, 25, 50, 75, 100] {
            scenarios.append(.init(
                id: "steps-\(progress)",
                category: "steps",
                variant: "\(progress)",
                plan: plan(
                    input: input(stepsProgress: Double(progress) / 100),
                    seed: baselineSeed
                )
            ))
        }
        for (variant, progress) in [("low", 0.0), ("mid", 0.5), ("full", 1.0)] {
            scenarios.append(.init(
                id: "sleep-\(variant)",
                category: "sleep",
                variant: variant,
                plan: plan(input: input(sleepProgress: progress), seed: baselineSeed)
            ))
        }
        for count in [0, 1, 10] {
            scenarios.append(.init(
                id: "happenings-\(count)",
                category: "happenings",
                variant: "\(count)",
                plan: plan(input: input(happeningCount: count), seed: baselineSeed)
            ))
        }
        for progress in [0, 25, 50, 100] {
            scenarios.append(.init(
                id: "glitch-\(progress)",
                category: "glitch",
                variant: "\(progress)",
                plan: plan(
                    input: input(glitchProgress: Double(progress) / 100),
                    seed: baselineSeed
                )
            ))
        }
        for mode in GrooveMode.allCases {
            let matching = try plan(matching: mode, input: baseline)
            let variant = grooveName(mode)
            scenarios.append(.init(
                id: "groove-\(variant)",
                category: "groove",
                variant: variant,
                plan: matching
            ))
        }
        for instrumentID in [
            "bass.analog-boom", "bass.hey-jakob", "bass.bassliner", "bass.jec-hollores-2",
        ] {
            scenarios.append(.init(
                id: "bass-\(instrumentID.replacingOccurrences(of: "bass.", with: ""))",
                category: "bass",
                variant: instrumentID,
                plan: try plan(matchingBassInstrumentID: instrumentID, input: baseline)
            ))
        }
        scenarios.append(.init(
            id: "lead-slow",
            category: "lead",
            variant: "slow",
            plan: plan(input: baseline, seed: baselineSeed),
            leadGestureProfile: .slow
        ))
        scenarios.append(.init(
            id: "lead-fast",
            category: "lead",
            variant: "fast",
            plan: plan(input: baseline, seed: baselineSeed),
            leadGestureProfile: .fast
        ))
        scenarios.append(.init(
            id: "worst-case-overlap",
            category: "worst-case",
            variant: "four-tails-kick-bass-chord-held-lead",
            plan: try plan(
                matching: .bassPulse,
                input: input(
                    stepsProgress: 1,
                    sleepProgress: 1,
                    happeningCount: 10,
                    glitchProgress: 1
                )
            ),
            leadGestureProfile: .held,
            stressProfile: .fourHappeningTailsWithKickBassChordAndHeldLead
        ))

        let isolatedPlan = plan(
            input: input(happeningCount: 10),
            seed: baselineSeed
        )
        for role in DayObjectsRoleBus.allCases {
            scenarios.append(.init(
                id: "isolated-\(roleName(role))",
                category: "isolated",
                variant: roleName(role),
                plan: isolatedPlan,
                auditionMode: .isolatedBus(role),
                leadGestureProfile: .held
            ))
        }
        return scenarios
    }

    private func measure(
        _ scenario: Scenario,
        durationSeconds: Double = 60
    ) async throws -> ScenarioResult {
        let renderer = DayObjectsOfflineMixRenderer(
            bundle: Bundle(for: type(of: self)),
            auditionMode: scenario.auditionMode,
            leadGestureProfile: scenario.leadGestureProfile,
            stressProfile: scenario.stressProfile
        )
        let renderStartedAt = ProcessInfo.processInfo.systemUptime
        let buffer = try await renderer.render(
            plan: scenario.plan,
            durationSeconds: durationSeconds,
            sampleRate: Self.scenarioSampleRate
        )
        let renderWallTimeSeconds = ProcessInfo.processInfo.systemUptime - renderStartedAt
        let loudness = try DayObjectsStereoCaptureAdapter.analyze(buffer)
        let diagnostics = try XCTUnwrap(renderer.lastDiagnostics)
        return ScenarioResult(
            id: scenario.id,
            category: scenario.category,
            variant: scenario.variant,
            seed: String(scenario.plan.seed),
            grooveMode: grooveName(scenario.plan.groove.mode),
            bassInstrumentID: scenario.plan.bass?.instrumentID.rawValue,
            integratedLUFS: loudness.integratedLUFS,
            truePeakDBTP: loudness.truePeakDBTP,
            durationSeconds: loudness.durationSeconds,
            renderWallTimeSeconds: renderWallTimeSeconds,
            containsOnlyFiniteSamples: loudness.containsOnlyFiniteSamples,
            maximumEstimatedLimiterReductionDB: diagnostics.maximumEstimatedLimiterReductionDB,
            averageRoleRMSDBFS: roleValues(diagnostics.averageRoleRMSDBFS),
            maximumRolePeakDBFS: roleValues(diagnostics.maximumRolePeakDBFS),
            maximumRoleActiveVoiceCount: roleValues(diagnostics.maximumRoleActiveVoiceCount),
            stressActivities: diagnostics.stressActivities,
            stressTransportSubdivision: diagnostics.stressTransportSubdivision,
            transportSubdivisionsWereMonotonic: diagnostics.transportSubdivisionsWereMonotonic,
            harmonyTransition: diagnostics.harmonyTransition,
            scheduledBassReleaseHostTimeSeconds: diagnostics.scheduledBassReleaseHostTimeSeconds,
            actualBassReleaseHostTimeSeconds: diagnostics.actualBassReleaseHostTimeSeconds,
            bassActiveVoiceCountAfterRelease: diagnostics.bassActiveVoiceCountAfterRelease
        )
    }

    private func assertGuardAcceptance(_ results: [ScenarioResult]) throws {
        for result in results {
            XCTAssertTrue(result.containsOnlyFiniteSamples, result.id)
            XCTAssertEqual(result.durationSeconds, 60, accuracy: 0.000_001, result.id)
            XCTAssertLessThanOrEqual(result.renderWallTimeSeconds, 60, result.id)
            XCTAssertLessThanOrEqual(result.truePeakDBTP, -1, result.id)
            if result.id == "isolated-bass" {
                XCTAssertEqual(result.integratedLUFS, -120, result.id)
                XCTAssertEqual(result.truePeakDBTP, -120, result.id)
            } else {
                XCTAssertGreaterThan(result.integratedLUFS, -120, result.id)
            }
            if result.category != "worst-case" {
                XCTAssertLessThan(result.maximumEstimatedLimiterReductionDB, 2, result.id)
            }
        }

        let representative = try XCTUnwrap(results.first { $0.id == "steps-50" })
        XCTAssertTrue((-18 ... -16).contains(representative.integratedLUFS))
        let glitchZero = try XCTUnwrap(results.first { $0.id == "glitch-0" })
        let glitchFull = try XCTUnwrap(results.first { $0.id == "glitch-100" })
        XCTAssertLessThanOrEqual(abs(glitchZero.integratedLUFS - glitchFull.integratedLUFS), 1)
        let isolatedFocus = results.filter {
            $0.category == "isolated" && ["harmony", "happenings", "lead"].contains($0.variant)
        }
        XCTAssertEqual(isolatedFocus.count, 3)
        let isolatedSpread = (isolatedFocus.map(\.integratedLUFS).max() ?? -120)
            - (isolatedFocus.map(\.integratedLUFS).min() ?? -120)
        XCTAssertLessThanOrEqual(isolatedSpread, 1.5)
        let worst = try XCTUnwrap(results.first { $0.category == "worst-case" })
        XCTAssertEqual(worst.stressActivities.count, 8)
        XCTAssertEqual(Set(worst.stressActivities.map(\.hostTimeSeconds)).count, 1)
        XCTAssertEqual(worst.stressActivities.filter { $0.component == .happeningTail }.count, 4)
        XCTAssertGreaterThanOrEqual(worst.maximumRoleActiveVoiceCount["happenings", default: 0], 4)
        try assertWorstCaseTransportEvidence(worst)
    }

    private func assertCrestGuardAcceptance(_ results: [ScenarioResult]) throws {
        XCTAssertEqual(results.count, 7)
        for result in results {
            XCTAssertTrue(result.containsOnlyFiniteSamples, result.id)
            XCTAssertEqual(result.durationSeconds, 60, accuracy: 0.000_001, result.id)
            XCTAssertLessThanOrEqual(result.renderWallTimeSeconds, 60, result.id)
            XCTAssertLessThanOrEqual(result.truePeakDBTP, -1, result.id)
            if result.id == "isolated-bass" {
                XCTAssertEqual(result.integratedLUFS, -120, result.id)
                XCTAssertEqual(result.truePeakDBTP, -120, result.id)
            } else {
                XCTAssertGreaterThan(result.integratedLUFS, -120, result.id)
                XCTAssertLessThanOrEqual(result.maximumEstimatedLimiterReductionDB, 1.7, result.id)
            }
        }

        for id in ["steps-50", "groove-percussion"] {
            let representative = try XCTUnwrap(results.first { $0.id == id })
            XCTAssertTrue((-18 ... -16).contains(representative.integratedLUFS), id)
        }
        let isolatedFocus = results.filter {
            $0.category == "isolated" && ["harmony", "happenings", "lead"].contains($0.variant)
        }
        XCTAssertEqual(isolatedFocus.count, 3)
        let spread = (isolatedFocus.map(\.integratedLUFS).max() ?? -120)
            - (isolatedFocus.map(\.integratedLUFS).min() ?? -120)
        XCTAssertLessThanOrEqual(spread, 1.5)
    }

    private func assertWorstCaseTransportEvidence(_ result: ScenarioResult) throws {
        XCTAssertTrue(result.transportSubdivisionsWereMonotonic)
        XCTAssertEqual(result.stressActivities.count, 8)
        XCTAssertEqual(Set(result.stressActivities.map(\.hostTimeSeconds)).count, 1)
        XCTAssertEqual(Set(result.stressActivities.map(\.component)), [
            .kickSoft, .bassAttack, .chordTransition, .heldLead, .happeningTail,
        ])
        XCTAssertEqual(result.stressActivities.filter { $0.component == .kickSoft }.count, 1)
        XCTAssertEqual(result.stressActivities.filter { $0.component == .bassAttack }.count, 1)
        XCTAssertEqual(result.stressActivities.filter { $0.component == .chordTransition }.count, 1)
        XCTAssertEqual(result.stressActivities.filter { $0.component == .heldLead }.count, 1)
        let happeningActivities = result.stressActivities.filter { $0.component == .happeningTail }
        XCTAssertEqual(happeningActivities.count, 4)
        XCTAssertEqual(Set(happeningActivities.map(\.identifier)).count, 4)
        XCTAssertGreaterThanOrEqual(result.maximumRoleActiveVoiceCount["happenings", default: 0], 4)
        let transition = try XCTUnwrap(result.harmonyTransition)
        XCTAssertFalse(transition.role.isEmpty)
        let sharedHostTime = try XCTUnwrap(result.stressActivities.first?.hostTimeSeconds)
        XCTAssertEqual(result.stressTransportSubdivision, transition.startSubdivision)
        XCTAssertEqual(transition.startHostTimeSeconds, sharedHostTime, accuracy: 0.000_000_001)
        XCTAssertGreaterThan(transition.oldVoiceCount, 0)
        XCTAssertGreaterThan(transition.newVoiceCount, 0)
        XCTAssertGreaterThan(transition.maximumAudibleProgress, 0)
        XCTAssertGreaterThan(transition.maximumNewChordExpression, 0)
        let progressHostTime = try XCTUnwrap(transition.firstAudibleProgressHostTimeSeconds)
        XCTAssertGreaterThan(progressHostTime, sharedHostTime)
        let scheduledRelease = try XCTUnwrap(result.scheduledBassReleaseHostTimeSeconds)
        let actualRelease = try XCTUnwrap(result.actualBassReleaseHostTimeSeconds)
        XCTAssertEqual(scheduledRelease, sharedHostTime + 0.220, accuracy: 0.000_000_001)
        XCTAssertEqual(actualRelease, scheduledRelease, accuracy: 0.5 / Self.scenarioSampleRate)
        XCTAssertLessThan(progressHostTime, actualRelease)
        XCTAssertEqual(result.bassActiveVoiceCountAfterRelease, 0)
    }

    private func input(
        stepsProgress: Double = 0.5,
        sleepProgress: Double = 0.5,
        happeningCount: Int = 4,
        glitchProgress: Double = 0.25
    ) -> DayMusicInput {
        DayMusicInput(
            countedSteps: stepsProgress * 10_000,
            stepGoal: 10_000,
            countedSleepHours: sleepProgress * 8,
            sleepGoalHours: 8,
            happeningIDs: (0..<happeningCount).map { "offline-happening-\($0)" },
            spentColors: Int((glitchProgress * 100).rounded())
        )
    }

    private func plan(input: DayMusicInput, seed: UInt64) -> DayMusicPlan {
        DeterministicMusicDirector.makePlan(input: input, remixSeed: seed)
    }

    private func plan(matching mode: GrooveMode, input: DayMusicInput) throws -> DayMusicPlan {
        for seed in UInt64(0)..<10_000 {
            let candidate = plan(input: input, seed: seed)
            if candidate.groove.mode == mode { return candidate }
        }
        throw DayObjectsAudioError("No deterministic seed found for groove \(grooveName(mode))")
    }

    private func plan(
        matchingBassInstrumentID instrumentID: String,
        input: DayMusicInput
    ) throws -> DayMusicPlan {
        for seed in UInt64(0)..<20_000 {
            let candidate = plan(input: input, seed: seed)
            if candidate.bass?.instrumentID.rawValue == instrumentID { return candidate }
        }
        throw DayObjectsAudioError("No deterministic seed found for \(instrumentID)")
    }

    private func grooveName(_ mode: GrooveMode) -> String {
        switch mode {
        case .percussion: "percussion"
        case .bassPulse: "bass-pulse"
        case .bassArp: "bass-arp"
        case .bassBed: "bass-bed"
        }
    }

    private func roleName(_ role: DayObjectsRoleBus) -> String {
        switch role {
        case .rhythm: "rhythm"
        case .bass: "bass"
        case .harmony: "harmony"
        case .happenings: "happenings"
        case .lead: "lead"
        }
    }

    private func roleValues(_ values: [DayObjectsRoleBus: Double]) -> [String: Double] {
        Dictionary(uniqueKeysWithValues: values.map { (roleName($0.key), $0.value) })
    }

    private func roleValues(_ values: [DayObjectsRoleBus: Int]) -> [String: Int] {
        Dictionary(uniqueKeysWithValues: values.map { (roleName($0.key), $0.value) })
    }

    private struct Scenario {
        let id: String
        let category: String
        let variant: String
        let plan: DayMusicPlan
        var auditionMode: DayObjectsAuditionMode = .fullComposition
        var leadGestureProfile: DayObjectsOfflineLeadGestureProfile = .none
        var stressProfile: DayObjectsOfflineStressProfile = .none
    }

    private struct ScenarioResult: Codable {
        let id: String
        let category: String
        let variant: String
        let seed: String
        let grooveMode: String
        let bassInstrumentID: String?
        let integratedLUFS: Double
        let truePeakDBTP: Double
        let durationSeconds: Double
        let renderWallTimeSeconds: Double
        let containsOnlyFiniteSamples: Bool
        let maximumEstimatedLimiterReductionDB: Double
        let averageRoleRMSDBFS: [String: Double]
        let maximumRolePeakDBFS: [String: Double]
        let maximumRoleActiveVoiceCount: [String: Int]
        let stressActivities: [DayObjectsOfflineStressActivity]
        let stressTransportSubdivision: Int64?
        let transportSubdivisionsWereMonotonic: Bool
        let harmonyTransition: DayObjectsOfflineHarmonyTransitionEvidence?
        let scheduledBassReleaseHostTimeSeconds: TimeInterval?
        let actualBassReleaseHostTimeSeconds: TimeInterval?
        let bassActiveVoiceCountAfterRelease: Int?
    }

    private struct ScenarioMatrixReport: Codable {
        let schemaVersion: Int
        let durationSeconds: Double
        let sampleRateHz: Int
        let analyzer: String
        let scenarios: [ScenarioResult]
        let comparisons: Comparisons

        struct Comparisons: Codable {
            let isolatedHarmonyHappeningLeadSpreadLU: Double
            let glitchZeroToFullDifferenceLU: Double
        }
    }

    private struct CalibrationProbeReport: Codable {
        let schemaVersion: Int
        let calibrationLabel: String
        let durationSeconds: Double
        let sampleRateHz: Int
        let analyzer: String
        let scenarios: [ScenarioResult]
    }

    private static let analyzerDescription = "ITU-R BS.1770 K-weighting; 400 ms blocks; 75% overlap; -70 LUFS absolute / -10 LU relative gates; BS.1770-5 Annex 2 four-phase 4x true peak with zero-padded boundaries"
}
#endif
