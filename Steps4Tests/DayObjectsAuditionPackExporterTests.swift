#if DEBUG || INTERNAL_BUILD
import AVFAudio
import CryptoKit
import XCTest
@testable import Steps4

@MainActor
final class DayObjectsAuditionPackExporterTests: XCTestCase {
    func testPackWritesAnonymousMixesPrivateStemsAndDeterministicReports() async throws {
        let first = try temporaryDirectory()
        let second = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: first); try? FileManager.default.removeItem(at: second) }
        var calls: [(DayMusicPlan, DayObjectsMixRole?)] = []
        var progress: [Int] = []
        let fixtures = try (0..<6).map { _ in try buffer() }
        let report = try qualityFixture()
        let exporter = DayObjectsAuditionPackExporter(render: { plan, role, schedule in
            XCTAssertEqual(schedule.durationSeconds, 24)
            XCTAssertEqual(schedule.eventEndSeconds, 22)
            XCTAssertEqual(schedule.sampleRate, 48_000)
            calls.append((plan, role))
            let roleIndex = role.flatMap { DayObjectsMixRole.allCases.firstIndex(of: $0) }.map { $0 + 1 } ?? 0
            let fixture = fixtures[roleIndex]
            fixture.floatChannelData![0][0] = Float(roleIndex + 1) * 0.01
            return fixture
        }, analyze: { _, stems, active, boundaries in
            XCTAssertEqual(stems.count, 5)
            XCTAssertEqual(Set(boundaries.keys), active)
            XCTAssertTrue(boundaries.values.allSatisfy { $0 == 1_056_000 })
            return report
        }, progress: { progress.append($0) })
        let result = try await exporter.export(input: input, seed: 99, directory: first)
        XCTAssertEqual(calls.count, 72)
        XCTAssertEqual(progress, Array(0...12))
        XCTAssertTrue(calls.allSatisfy { $0.0.seed == 99 && $0.0.input == input.normalized() })
        for offset in stride(from: 0, to: calls.count, by: 6) {
            let variantCalls = Array(calls[offset..<(offset + 6)])
            XCTAssertTrue(variantCalls.allSatisfy { $0.0 == variantCalls[0].0 })
            XCTAssertEqual(variantCalls.map(\.1), [nil, .rhythm, .bass, .harmony, .happenings, .lead])
        }
        XCTAssertEqual(Set(result.entries.map { "\($0.world.rawValue)/\($0.mood.rawValue)" }).count, 12)
        XCTAssertEqual(result.entries.map(\.publicNumber), Array(1...12))
        for entry in result.entries {
            XCTAssertEqual(entry.mixPath, String(format: "preview-%02d.wav", entry.publicNumber))
            XCTAssertEqual(Set(entry.stemPaths.keys), Set(["rhythm", "bass", "harmony", "happenings", "lead"]))
            XCTAssertFalse(entry.instrumentRecipeIDs.isEmpty)
            XCTAssertFalse(entry.progressionDegrees.isEmpty)
            XCTAssertFalse(entry.kitID.isEmpty)
            XCTAssertEqual(Set(Array(entry.stemSHA256.values) + [entry.sha256]).count, 6,
                           "Each file must contain its own render, never a cached mix or another stem")
            for (role, path) in entry.stemPaths {
                XCTAssertEqual(path, String(format: "private/%02d/%@.wav", entry.publicNumber, role))
                let data = try Data(contentsOf: first.appendingPathComponent(path))
                XCTAssertEqual(entry.stemSHA256[role], SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined())
            }
            let file = try AVAudioFile(forReading: first.appendingPathComponent(entry.mixPath))
            XCTAssertEqual(file.length, 1_152_000)
            XCTAssertEqual(file.processingFormat.sampleRate, 48_000)
        }
        let repeated = try await exporter.export(input: input, seed: 99, directory: second)
        XCTAssertEqual(result.entries, repeated.entries)
        XCTAssertEqual(try Data(contentsOf: result.manifestURL), try Data(contentsOf: repeated.manifestURL))
        XCTAssertEqual(try Data(contentsOf: result.qualityReportURL), try Data(contentsOf: repeated.qualityReportURL))
        let quality = try JSONDecoder().decode([DayObjectsAuditionQualityEntry].self, from: Data(contentsOf: result.qualityReportURL))
        XCTAssertEqual(quality.count, 12)
        XCTAssertTrue(quality.allSatisfy { !$0.passes && $0.report.issues.contains(.silence) })
    }

    func testSeedChangesAnonymousAssignment() async throws {
        var assignments: Set<String> = []
        let exporter = DayObjectsAuditionPackExporter(render: { plan, _, _ in
            assignments.insert("\(plan.soundWorld.rawValue)/\(plan.mood.rawValue)")
            throw TestFailure.injected
        })
        for seed in UInt64(0)..<12 {
            let directory = try temporaryDirectory()
            defer { try? FileManager.default.removeItem(at: directory) }
            do {
                _ = try await exporter.export(input: input, seed: seed, directory: directory)
                XCTFail("Expected injected stop")
            } catch let error as DayObjectsAuditionPackError {
                XCTAssertEqual(error.seed, seed)
                XCTAssertEqual(error.publicNumber, 1)
            }
        }
        XCTAssertGreaterThan(assignments.count, 1, "Public numbers must depend on the seed")
    }

    func testLaterFailurePreservesCompletedQualityEvidence() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let fixture = try buffer()
        let report = try qualityFixture()
        var count = 0
        let exporter = DayObjectsAuditionPackExporter(render: { _, _, _ in
            count += 1
            if count == 7 { throw TestFailure.injected }
            return fixture
        }, analyze: { _, _, _, _ in report })
        do {
            _ = try await exporter.export(input: input, seed: 99, directory: directory)
            XCTFail("Expected second-preview failure")
        } catch let error as DayObjectsAuditionPackError {
            XCTAssertEqual(error.publicNumber, 2)
            XCTAssertEqual(error.layer, "fullMix")
        }
        XCTAssertEqual(count, 7)
        let reports = try JSONDecoder().decode([DayObjectsAuditionQualityEntry].self,
            from: Data(contentsOf: directory.appendingPathComponent("mix-quality.json")))
        XCTAssertEqual(reports.count, 1)
        XCTAssertEqual(reports.first?.publicNumber, 1)
        XCTAssertEqual(reports.first?.passes, false)
        let failure = try JSONDecoder().decode(DayObjectsAuditionPackError.self,
            from: Data(contentsOf: directory.appendingPathComponent("export-failure.json")))
        XCTAssertEqual(failure.publicNumber, 2)
        XCTAssertEqual(failure.seed, 99)
    }

    func testRenderFailureNamesNumberSeedLayerAndStopsWithoutRetry() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let fixture = try buffer()
        var calls = 0
        let exporter = DayObjectsAuditionPackExporter(render: { _, role, _ in
            calls += 1
            if role == .bass { throw TestFailure.injected }
            return fixture
        })
        do {
            _ = try await exporter.export(input: input, seed: 99, directory: directory)
            XCTFail("Expected render failure")
        } catch let error as DayObjectsAuditionPackError {
            XCTAssertEqual(error.publicNumber, 1)
            XCTAssertEqual(error.seed, 99)
            XCTAssertEqual(error.layer, "bass")
        }
        XCTAssertEqual(calls, 3)
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.appendingPathComponent("preview-02.wav").path))
    }

    func testAnalyzerFailureStopsOnceAndUsesExplicitPlanActivity() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let fixture = try buffer()
        var renderCount = 0
        var analyzerCount = 0
        let empty = DayMusicInput(countedSteps: 0, stepGoal: 10_000, countedSleepHours: 0,
                                 sleepGoalHours: 8, happeningIDs: [], spentColors: 0)
        let exporter = DayObjectsAuditionPackExporter(render: { _, _, _ in renderCount += 1; return fixture },
            analyze: { _, _, active, boundaries in
                analyzerCount += 1
                XCTAssertFalse(active.contains(.rhythm))
                XCTAssertFalse(active.contains(.bass))
                XCTAssertFalse(active.contains(.happenings))
                XCTAssertTrue(active.contains(.lead))
                XCTAssertEqual(Set(boundaries.keys), active)
                throw TestFailure.injected
            })
        do {
            _ = try await exporter.export(input: empty, seed: 42, directory: directory)
            XCTFail("Expected analysis failure")
        } catch let error as DayObjectsAuditionPackError {
            XCTAssertEqual(error.publicNumber, 1)
            XCTAssertEqual(error.seed, 42)
            XCTAssertEqual(error.layer, "analysis")
        }
        XCTAssertEqual(renderCount, 6)
        XCTAssertEqual(analyzerCount, 1)
    }

    private var input: DayMusicInput {
        .init(countedSteps: 7_500, stepGoal: 10_000, countedSleepHours: 6.5,
              sleepGoalHours: 8, happeningIDs: ["one", "two"], spentColors: 25)
    }

    private func buffer() throws -> AVAudioPCMBuffer {
        let format = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 2))
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 1_152_000))
        buffer.frameLength = buffer.frameCapacity
        for channel in 0..<2 { buffer.floatChannelData![channel].initialize(repeating: 0, count: Int(buffer.frameLength)) }
        return buffer
    }

    private func qualityFixture() throws -> DayObjectsMixQualityReport {
        let format = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: 8_000, channels: 1))
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 8_000))
        buffer.frameLength = 8_000
        buffer.floatChannelData![0].initialize(repeating: 0, count: 8_000)
        return try DayObjectsMixQualityAnalyzer.analyze(fullMix: buffer, stems: [:], activeRoles: [])
    }

    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private enum TestFailure: Error { case injected }
}
#endif
