import Foundation

public enum BackgroundCondition: String, CaseIterable, Codable, Sendable {
    case light
    case dark
    case warm
    case cool
    case saturated
    case lowContrast
}

public enum SleepCondition: String, CaseIterable, Codable, Sendable {
    case normal
    case low
}

public enum StepCondition: String, CaseIterable, Codable, Sendable {
    case low
    case normal
}

public struct CorpusFixture: Codable, Equatable, Sendable {
    public let suite: String
    public let index: Int
    public let collision: Int
    public let seed: UInt64
    public let actorCount: Int
    public let eventIDs: [String]
    public let background: BackgroundCondition
    public let sleep: SleepCondition
    public let steps: StepCondition
    public let reduceMotion: Bool
}

public struct ContinuityStage: Codable, Equatable, Sendable {
    public let stage: Int
    public let actorCount: Int
    public let eventIDs: [String]
}

public struct ContinuityFixture: Codable, Equatable, Sendable {
    public let suite: String
    public let index: Int
    public let collision: Int
    public let seed: UInt64
    public let background: BackgroundCondition
    public let sleep: SleepCondition
    public let steps: StepCondition
    public let reduceMotion: Bool
    public let stages: [ContinuityStage]
}

public struct CorpusManifest: Codable, Equatable, Sendable {
    public static let visibleV1Commit = "8a8539a77ce704fcc688ebe8cb98d78e2a0f80dd"
    public static let visibleV1Nonce = "day-objects-editorial-field-visible-v1"

    public static let canonicalEventIDs = [
        "0A9B16D9-07B5-4D12-9C2F-6CFEF7AD0801",
        "1BE8C246-8DD2-4D68-B4C0-4E8F24A85E02",
        "2C9F4B58-ABF5-4F7E-8CA9-6D415C7B3D03",
        "3D247E01-C609-43C1-A5B2-3E0D9CF8B504",
        "4E6B83FD-19A8-4AA2-91FC-D297E6C15405",
        "5FA2D140-7C0E-45B9-BE3D-8124A937EF06",
        "60D319B7-3E21-4E8A-879F-5C6B24FA0A07",
        "71E4AC82-5F36-4B19-9D48-A7C2E60B1D08",
        "82F5B06C-6A47-4C2E-8E51-B93D17CA2F09",
        "9346C9D1-7B58-4D3F-A062-CE4B28D03A10",
    ]

    public let version: String
    public let specificationCommit: String
    public let nonce: String
    public let canonicalEventIDs: [String]
    public let phases: [Double]
    public let breadth: [CorpusFixture]
    public let continuity: ContinuityFixture
    public let stress: [CorpusFixture]

    public static func visibleV1() -> CorpusManifest {
        let actorCounts = [1, 1, 2, 2, 3, 3, 5, 5, 7, 7, 10, 10]
        let backgrounds: [BackgroundCondition] = [
            .light, .dark, .warm, .cool, .saturated, .lowContrast,
            .light, .dark, .warm, .cool, .saturated, .lowContrast,
        ]
        let sleeps: [SleepCondition] = [
            .normal, .low, .normal, .low, .normal, .low,
            .low, .normal, .low, .normal, .low, .normal,
        ]
        let steps: [StepCondition] = [
            .normal, .low, .low, .normal, .normal, .low,
            .low, .normal, .normal, .low, .low, .normal,
        ]
        let reduceMotion = [false, true, false, true, false, true, true, false, true, false, true, false]

        var usedSeeds = Set<UInt64>()
        func makeFixture(
            suite: String,
            index: Int,
            actorCount: Int,
            background: BackgroundCondition,
            sleep: SleepCondition,
            steps: StepCondition,
            reduceMotion: Bool
        ) -> CorpusFixture {
            let resolved = SeedDerivation.uniqueSeed(
                commit: visibleV1Commit,
                nonce: visibleV1Nonce,
                suite: suite,
                index: index,
                usedSeeds: usedSeeds
            )
            usedSeeds.insert(resolved.seed)
            return CorpusFixture(
                suite: suite,
                index: index,
                collision: resolved.collision,
                seed: resolved.seed,
                actorCount: actorCount,
                eventIDs: Array(canonicalEventIDs.prefix(actorCount)),
                background: background,
                sleep: sleep,
                steps: steps,
                reduceMotion: reduceMotion
            )
        }

        let breadth = actorCounts.indices.map { index in
            makeFixture(
                suite: "breadth",
                index: index,
                actorCount: actorCounts[index],
                background: backgrounds[index],
                sleep: sleeps[index],
                steps: steps[index],
                reduceMotion: reduceMotion[index]
            )
        }

        let continuitySeed = SeedDerivation.uniqueSeed(
            commit: visibleV1Commit,
            nonce: visibleV1Nonce,
            suite: "continuity",
            index: 0,
            usedSeeds: usedSeeds
        )
        usedSeeds.insert(continuitySeed.seed)
        let continuityCounts = [1, 2, 3, 5, 7, 10, 5]
        let continuity = ContinuityFixture(
            suite: "continuity",
            index: 0,
            collision: continuitySeed.collision,
            seed: continuitySeed.seed,
            background: .cool,
            sleep: .normal,
            steps: .normal,
            reduceMotion: false,
            stages: continuityCounts.enumerated().map { stage, actorCount in
                ContinuityStage(
                    stage: stage,
                    actorCount: actorCount,
                    eventIDs: Array(canonicalEventIDs.prefix(actorCount))
                )
            }
        )

        let stress = (0..<48).map { index in
            makeFixture(
                suite: "stress",
                index: index,
                actorCount: [1, 2, 3, 5, 7, 10][index % 6],
                background: BackgroundCondition.allCases[index % BackgroundCondition.allCases.count],
                sleep: SleepCondition.allCases[index % SleepCondition.allCases.count],
                steps: StepCondition.allCases[(index / 2) % StepCondition.allCases.count],
                reduceMotion: index.isMultiple(of: 3)
            )
        }

        return CorpusManifest(
            version: "visible-v1",
            specificationCommit: visibleV1Commit,
            nonce: visibleV1Nonce,
            canonicalEventIDs: canonicalEventIDs,
            phases: [0, 0.25, 0.5, 0.75],
            breadth: breadth,
            continuity: continuity,
            stress: stress
        )
    }

    public func canonicalJSON() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        var json = try encoder.encode(self)
        json.append(0x0A)
        return json
    }
}
