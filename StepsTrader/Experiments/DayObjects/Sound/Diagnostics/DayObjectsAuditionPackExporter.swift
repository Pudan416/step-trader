#if DEBUG || INTERNAL_BUILD
import AVFAudio
import CryptoKit
import Foundation

struct DayObjectsAuditionSchedule: Encodable, Equatable, Sendable {
    let durationSeconds = 24.0
    let eventEndSeconds = 22.0
    let sampleRate = 48_000.0

    func activeRoles(in plan: DayMusicPlan) -> Set<DayObjectsMixRole> {
        var roles: Set<DayObjectsMixRole> = [.lead] // A held diagnostic gesture is scheduled.
        if plan.rhythm.rhythmicRichness > 0 { roles.insert(.rhythm) }
        if plan.bass?.activeEvents.isEmpty == false { roles.insert(.bass) }
        if plan.harmony.activeRoleCount > 0 { roles.insert(.harmony) }
        if !plan.happenings.isEmpty { roles.insert(.happenings) }
        return roles
    }

    /// The scheduled gate-off releases every role at 22s. The remaining 2s
    /// traverse the same instrument/effect graph without new musical events.
    func tailBoundaryFrames(in plan: DayMusicPlan) -> [DayObjectsMixRole: Int] {
        Dictionary(uniqueKeysWithValues: activeRoles(in: plan).map {
            ($0, Int((eventEndSeconds * sampleRate).rounded()))
        })
    }
}

struct DayObjectsAuditionPackEntry: Codable, Equatable, Sendable {
    let publicNumber: Int
    let seed: UInt64
    let world: DayObjectsSoundWorld
    let mood: DayObjectsSoundMood
    let guestWorld: DayObjectsSoundWorld?
    let guestInstrumentIDs: [DayObjectsInstrumentID]
    let mixPath: String
    let stemPaths: [String: String]
    let instrumentRecipeIDs: [DayObjectsInstrumentID]
    let harmonySources: [String]
    let happeningRecipeIDs: [String]
    let progressionDegrees: [Int]
    let musicalFingerprint: String
    let kitID: String
    let sha256: String
    let stemSHA256: [String: String]
}

struct DayObjectsAuditionQualityEntry: Codable, Equatable, Sendable {
    let publicNumber: Int
    let seed: UInt64
    let activeRoles: [DayObjectsMixRole]
    let tailBoundaryFrames: [String: Int]
    let passes: Bool
    let report: DayObjectsMixQualityReport
}

struct DayObjectsAuditionPackResult: Equatable, Sendable {
    let entries: [DayObjectsAuditionPackEntry]
    let manifestURL: URL
    let qualityReportURL: URL
}

struct DayObjectsAuditionPackError: Error, LocalizedError, Codable, Equatable, Sendable {
    let publicNumber: Int
    let seed: UInt64
    let layer: String
    let reason: String

    var errorDescription: String? {
        "Preview \(publicNumber), seed \(seed), layer \(layer): \(reason)"
    }
}

/// Owns one sequential render at a time; every stem is a fresh rendering of
/// its own plan through the existing production bus-isolation path.
@MainActor
final class DayObjectsAuditionPackExporter {
    typealias Render = @MainActor (DayMusicPlan, DayObjectsMixRole?, DayObjectsAuditionSchedule) async throws -> AVAudioPCMBuffer
    typealias Analyze = @MainActor (AVAudioPCMBuffer, [DayObjectsMixRole: AVAudioPCMBuffer], Set<DayObjectsMixRole>, [DayObjectsMixRole: Int]) throws -> DayObjectsMixQualityReport

    private let render: Render
    private let analyze: Analyze
    private let progress: @MainActor (Int) -> Void

    init(
        bundle: Bundle = .main,
        render: Render? = nil,
        analyze: Analyze? = nil,
        progress: @escaping @MainActor (Int) -> Void = { _ in }
    ) {
        self.render = render ?? { plan, role, schedule in
            let renderer = DayObjectsOfflineMixRenderer(
                bundle: bundle,
                auditionMode: role.map { .isolatedBus($0.bus) } ?? .fullComposition,
                leadGestureProfile: .held,
                contextRetryLimit: 0
            )
            return try await renderer.render(
                plan: plan, durationSeconds: schedule.durationSeconds,
                sampleRate: schedule.sampleRate, eventEndSeconds: schedule.eventEndSeconds
            )
        }
        self.analyze = analyze ?? { fullMix, stems, active, boundaries in
            try DayObjectsMixQualityAnalyzer.analyze(
                fullMix: fullMix, stems: stems, activeRoles: active, tailBoundaryFrames: boundaries
            )
        }
        self.progress = progress
    }

    func export(input: DayMusicInput, seed: UInt64, directory: URL) async throws -> DayObjectsAuditionPackResult {
        let schedule = DayObjectsAuditionSchedule()
        let manifestURL = directory.appendingPathComponent("audition-manifest.json")
        let qualityURL = directory.appendingPathComponent("mix-quality.json")
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        var entries: [DayObjectsAuditionPackEntry] = []
        var reports: [DayObjectsAuditionQualityEntry] = []
        var number = 1
        var layer = "directory"
        var ownsDirectory = false
        progress(0)
        do {
            if FileManager.default.fileExists(atPath: directory.path),
               !(try FileManager.default.contentsOfDirectory(atPath: directory.path)).isEmpty {
                throw CocoaError(.fileWriteFileExists)
            }
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            ownsDirectory = true
            var random = StableMusicRandom(seed: seed, domain: MusicSeedDomain("audition.order"))
            let pairs = random.shuffled(DayObjectsSoundWorld.allCases.flatMap { world in
                DayObjectsSoundMood.allCases.map { (world, $0) }
            })
            for (index, pair) in pairs.enumerated() {
                number = index + 1
                layer = "fullMix"
                try Task.checkCancellation()
                let plan = DeterministicMusicDirector.makePlan(
                    input: input, remixSeed: seed, soundWorld: pair.0, mood: pair.1
                )
                let mixPath = String(format: "preview-%02d.wav", number)
                let mix = try await render(plan, nil, schedule)
                let mixHash = try write(mix, to: directory.appendingPathComponent(mixPath), schedule: schedule)
                var stems: [DayObjectsMixRole: AVAudioPCMBuffer] = [:]
                var paths: [String: String] = [:]
                var hashes: [String: String] = [:]
                for role in DayObjectsMixRole.allCases {
                    layer = role.rawValue
                    try Task.checkCancellation()
                    let path = String(format: "private/%02d/%@.wav", number, role.rawValue)
                    let url = directory.appendingPathComponent(path)
                    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                    let stem = try await render(plan, role, schedule)
                    hashes[role.rawValue] = try write(stem, to: url, schedule: schedule)
                    paths[role.rawValue] = path
                    stems[role] = stem
                }
                layer = "analysis"
                let active = schedule.activeRoles(in: plan)
                let boundaries = schedule.tailBoundaryFrames(in: plan)
                let report = try analyze(mix, stems, active, boundaries)
                reports.append(.init(
                    publicNumber: number, seed: seed,
                    activeRoles: DayObjectsMixRole.allCases.filter(active.contains),
                    tailBoundaryFrames: Dictionary(uniqueKeysWithValues: boundaries.map { ($0.key.rawValue, $0.value) }),
                    passes: report.passes, report: report
                ))
                let harmonyIDs = plan.harmony.roles.compactMap { role -> DayObjectsInstrumentID? in
                    switch role.instrumentTarget {
                    case let .tonal(id): id
                    case .feltPiano: nil
                    }
                }
                let recipeIDs = Set(harmonyIDs + [plan.lead.instrumentID] + (plan.bass.map { [$0.instrumentID] } ?? []))
                entries.append(.init(
                    publicNumber: number, seed: seed, world: plan.soundWorld, mood: plan.mood,
                    guestWorld: plan.guestWorld,
                    guestInstrumentIDs: plan.guestInstrumentIDs.sorted { $0.rawValue < $1.rawValue },
                    mixPath: mixPath, stemPaths: paths,
                    instrumentRecipeIDs: recipeIDs.sorted { $0.rawValue < $1.rawValue },
                    harmonySources: plan.harmony.roles.map {
                        switch $0.instrumentTarget {
                        case let .tonal(id): id.rawValue
                        case .feltPiano: "feltPiano"
                        }
                    },
                    happeningRecipeIDs: plan.happenings.map { String($0.recipeID.rawValue) }.sorted(),
                    progressionDegrees: plan.world.progression.map(\.modalDegree),
                    musicalFingerprint: plan.world.musicalFingerprint, kitID: plan.rhythm.kitID,
                    sha256: mixHash, stemSHA256: hashes
                ))
                layer = "report"
                // Persist every completed report, including quality issues. A later
                // infrastructure failure must not erase calibration evidence.
                try encoder.encode(reports).write(to: qualityURL, options: .atomic)
                try encoder.encode(Manifest(schedule: schedule, entries: entries)).write(to: manifestURL, options: .atomic)
                progress(number)
            }
            return .init(entries: entries, manifestURL: manifestURL, qualityReportURL: qualityURL)
        } catch {
            let failure = DayObjectsAuditionPackError(publicNumber: number, seed: seed, layer: layer,
                                                     reason: String(describing: error))
            if ownsDirectory {
                try? encoder.encode(failure).write(to: directory.appendingPathComponent("export-failure.json"), options: .atomic)
            }
            throw failure
        }
    }

    private struct Manifest: Encodable {
        let schemaVersion = 1
        let schedule: DayObjectsAuditionSchedule
        let entries: [DayObjectsAuditionPackEntry]
    }

    private func write(_ buffer: AVAudioPCMBuffer, to url: URL, schedule: DayObjectsAuditionSchedule) throws -> String {
        guard buffer.frameLength == AVAudioFrameCount(schedule.durationSeconds * schedule.sampleRate),
              buffer.format.sampleRate == schedule.sampleRate, buffer.format.channelCount == 2 else {
            throw DayObjectsOfflineMixRendererError.renderFailed
        }
        try writeWAV(buffer, to: url)
        let data = try Data(contentsOf: url, options: .mappedIfSafe)
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private func writeWAV(_ buffer: AVAudioPCMBuffer, to url: URL) throws {
        let file = try AVAudioFile(forWriting: url, settings: buffer.format.settings)
        try file.write(from: buffer)
    }
}

private extension DayObjectsMixRole {
    var bus: DayObjectsRoleBus {
        switch self {
        case .rhythm: .rhythm
        case .bass: .bass
        case .harmony: .harmony
        case .happenings: .happenings
        case .lead: .lead
        }
    }
}
#endif
