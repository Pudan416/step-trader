enum HarmonyRole: CaseIterable, Equatable, Sendable {
    case drone
    case primaryPad
    case secondaryPadOrKeys
    case pianoOrKeysAccents
    case innerMotion
}

enum HarmonyInstrumentTarget: Equatable, Sendable {
    case tonal(DayObjectsInstrumentID)
    case feltPiano
}

struct HarmonyActivationPlan: Equatable, Sendable {
    let startProgress: Double
    let fullProgress: Double
    let amount: Double
}

struct HarmonyChordScheduleEntry: Equatable, Sendable {
    let chordIndex: Int
    let startBar: Int
    let durationBars: Int
    let rootPitchClass: Int
    let chordPitchClasses: [Int]
    let safePassingPitchClasses: [Int]
    let voicedMIDINotes: [UInt8]
}

struct HarmonyRolePlan: Equatable, Sendable {
    let role: HarmonyRole
    let instrumentTarget: HarmonyInstrumentTarget
    let register: ClosedRange<UInt8>
    let gain: Double
    let attackSeconds: Double
    let releaseSeconds: Double
    let delaySend: Double
    let reverbSend: Double
    let activation: HarmonyActivationPlan
    let chordSchedule: [HarmonyChordScheduleEntry]
    let crossfadeBars: Double
}

struct HarmonyPlan: Equatable, Sendable {
    let sleepProgress: Double
    let cycleBars: Int
    let chordCount: Int
    let roles: [HarmonyRolePlan]

    var activeRoleCount: Int {
        roles.filter { $0.gain > 0 && !$0.chordSchedule.isEmpty }.count
    }

    var harmonicInformationScore: Double {
        Double(chordCount) + roles.reduce(0) { score, role in
            score + role.activation.amount
        }
    }

    func role(for role: HarmonyRole) -> HarmonyRolePlan? {
        roles.first { $0.role == role }
    }
}
