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

    func testQuietOfflineRenderDoesNotReportFalseLimiterReduction() async throws {
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
            diagnostics.maximumLimiterReductionDB,
            0.1,
            "A signal with at least 1 dB of output headroom must not report gain reduction"
        )
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
            "bass.analog-boom", "bass.hey-jakob", "bass.bb-roys-phaser", "bass.jec-hollores-2",
        ])
        XCTAssertEqual(variantsByCategory["lead"], ["slow", "fast"])
        XCTAssertEqual(variantsByCategory["worst-case"], ["four-tails-kick-bass-chord-held-lead"])
        XCTAssertEqual(variantsByCategory["isolated"], [
            "rhythm", "bass", "harmony", "happenings", "lead",
        ])
        XCTAssertEqual(scenarios.count, 31)
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
            results.append(result)
            print(
                "DAY_OBJECTS_RESULT \(result.id) lufs=\(result.integratedLUFS) "
                    + "dbtp=\(result.truePeakDBTP) limiter=\(result.maximumLimiterReductionDB) "
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
            schemaVersion: 1,
            durationSeconds: Self.scenarioDurationSeconds,
            sampleRateHz: Int(Self.scenarioSampleRate),
            analyzer: "ITU-R BS.1770 K-weighting; 400 ms blocks; 75% overlap; -70 LUFS absolute / -10 LU relative gates; 4x true peak",
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
            XCTAssertGreaterThan(result.integratedLUFS, -120, result.id)
            if result.category != "worst-case" {
                XCTAssertLessThan(result.maximumLimiterReductionDB, 2, result.id)
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
        XCTAssertGreaterThanOrEqual(worst.maximumRoleActiveVoiceCount["happenings", default: 0], 4)
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
            "bass.analog-boom", "bass.hey-jakob", "bass.bb-roys-phaser", "bass.jec-hollores-2",
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
                leadGestureProfile: role == .lead ? .held : .none
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
            maximumLimiterReductionDB: diagnostics.maximumLimiterReductionDB,
            averageRoleRMSDBFS: roleValues(diagnostics.averageRoleRMSDBFS),
            maximumRolePeakDBFS: roleValues(diagnostics.maximumRolePeakDBFS),
            maximumRoleActiveVoiceCount: roleValues(diagnostics.maximumRoleActiveVoiceCount)
        )
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
        let maximumLimiterReductionDB: Double
        let averageRoleRMSDBFS: [String: Double]
        let maximumRolePeakDBFS: [String: Double]
        let maximumRoleActiveVoiceCount: [String: Int]
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
}
#endif
