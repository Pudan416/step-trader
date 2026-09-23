enum BassArticulation: Hashable, Sendable {
    case pulse
    case arpeggio
    case sustained
}

struct BassDuckingPlan: Equatable, Sendable {
    let maximumAttenuationDecibels: Double
    let attackSeconds: Double
    let holdSeconds: Double
    let releaseSeconds: Double
}

struct BassEventPlan: Equatable, Sendable {
    let stableID: UInt64
    let chordIndex: Int
    let startSubdivision: Int64
    let durationSubdivisions: Int64
    let midiNote: UInt8
    let velocity: Double
    let activationThreshold: Double
    let allowedPitchClasses: Set<Int>
}

struct BassPlan: Equatable, Sendable {
    let mode: GrooveMode
    let instrumentID: DayObjectsInstrumentID
    let register: ClosedRange<UInt8>
    let articulation: BassArticulation
    let stepsProgress: Double
    let cutoffMultiplier: Double
    let glideMilliseconds: Double
    let reverbSend: Double
    let ducking: BassDuckingPlan
    let events: [BassEventPlan]

    var activeEvents: [BassEventPlan] {
        events.filter { $0.activationThreshold <= stepsProgress }
    }
}
