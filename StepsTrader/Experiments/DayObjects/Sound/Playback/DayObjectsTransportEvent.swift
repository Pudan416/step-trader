#if DEBUG || INTERNAL_BUILD
import Foundation

enum DayObjectsTransportEventKind: Equatable, Sendable {
    case subdivision
    case beat
    case barBoundary
    case harmonicCycleBoundary
}

struct DayObjectsTransportEvent: Equatable, Sendable {
    let kind: DayObjectsTransportEventKind
    let position: MusicalPosition
    let hostTimeSeconds: TimeInterval
    let tempoBPM: Double
    let nextSubdivisionHostTimeSeconds: TimeInterval

    init(
        kind: DayObjectsTransportEventKind,
        position: MusicalPosition,
        hostTimeSeconds: TimeInterval,
        tempoBPM: Double,
        nextSubdivisionHostTimeSeconds: TimeInterval? = nil
    ) {
        self.kind = kind
        self.position = position
        self.hostTimeSeconds = hostTimeSeconds
        self.tempoBPM = tempoBPM
        let fixtureInterval = tempoBPM.isFinite && tempoBPM > 0 ? 15 / tempoBPM : 0
        self.nextSubdivisionHostTimeSeconds = nextSubdivisionHostTimeSeconds
            ?? hostTimeSeconds + fixtureInterval
    }
}
#endif
