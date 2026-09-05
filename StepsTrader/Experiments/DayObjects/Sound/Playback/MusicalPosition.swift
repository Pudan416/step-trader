#if DEBUG || INTERNAL_BUILD
struct MusicalPosition: Equatable, Comparable, Sendable {
    static let subdivisionsPerBeat: Int64 = 4
    static let beatsPerBar: Int64 = 4
    static let subdivisionsPerBar = subdivisionsPerBeat * beatsPerBar

    let absoluteSubdivision: Int64

    init(absoluteSubdivision: Int64) {
        self.absoluteSubdivision = max(0, absoluteSubdivision)
    }

    var absoluteBeat: Int64 {
        absoluteSubdivision / Self.subdivisionsPerBeat
    }

    var bar: Int64 {
        absoluteSubdivision / Self.subdivisionsPerBar
    }

    var beatInBar: Int {
        Int(absoluteBeat % Self.beatsPerBar)
    }

    var subdivisionInBeat: Int {
        Int(absoluteSubdivision % Self.subdivisionsPerBeat)
    }

    var subdivisionInBar: Int {
        Int(absoluteSubdivision % Self.subdivisionsPerBar)
    }

    static func < (lhs: MusicalPosition, rhs: MusicalPosition) -> Bool {
        lhs.absoluteSubdivision < rhs.absoluteSubdivision
    }
}
#endif
