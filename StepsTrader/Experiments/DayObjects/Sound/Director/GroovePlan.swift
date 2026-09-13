enum GrooveMode: CaseIterable, Equatable, Sendable {
    case percussion
    case bassPulse
    case bassArp
    case bassBed
}

struct GroovePlan: Equatable, Sendable {
    let mode: GrooveMode
    let auxiliaryRetention: Double
    let maximumAnchorKicksPerBar: Int
    let thinningSeed: UInt64

    var usesBass: Bool { mode != .percussion }

    static let percussion = GroovePlan(
        mode: .percussion,
        auxiliaryRetention: 1,
        maximumAnchorKicksPerBar: 2,
        thinningSeed: 0
    )
}
