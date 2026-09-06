#if DEBUG || INTERNAL_BUILD
struct DayObjectsHarmonyGrammar: Equatable, Sendable {
    let allowedModes: [DayMusicMode]
    /// Semitone offsets from the tonal center, ordered by mood preference.
    let progressionTemplates: [[Int]]
    /// Ordered semitone extensions above each root; the root is implicit.
    let allowedExtensions: [Int]
    let register: ClosedRange<UInt8>
    let maximumChordTones: Int
    /// Repeated entries weight the deterministic selection.
    let cycleBarChoices: [Int]

    static func `for`(world: DayObjectsSoundWorld, mood: DayObjectsSoundMood) -> Self {
        let modes: [DayMusicMode]
        let templates: [[Int]]
        let extensions: [Int]
        let register: ClosedRange<UInt8>
        let cycles: [Int]
        switch world {
        case .feltAndWood:
            modes = [.dorian, .aeolian]
            templates = [[0, 5, 10, 2], [0, 10, 5, 7], [0, 2, 10, 5]]
            extensions = mood == .sparse ? [7, 5] : mood == .moving ? [7, 2] : [2, 5]
            register = 48...72
            cycles = mood == .sparse ? [16, 16, 12] : [12, 16, 12]
        case .livingField:
            modes = [.majorPentatonic, .dorian]
            templates = [[0, 7, 9, 2], [0, 9, 2, 7], [0, 2, 7, 9]]
            extensions = mood == .sparse ? [7] : [7, 9]
            register = 48...79
            cycles = mood == .moving ? [16, 12, 16] : [16, 16, 12]
        case .metalAndCurrent:
            modes = [.aeolian, .dorian]
            templates = [[0, 0, 7, 0], [0, 7, 0, 2], [0, 2, 0, 7]]
            // Only the strange mood adds a single upper semitone to the fifth.
            extensions = mood == .strange ? [7, 8] : [7]
            register = 36...60
            cycles = mood == .sparse ? [12, 12, 8] : [8, 12, 8]
        case .electricDream:
            modes = [.mixolydian, .dorian, .majorPentatonic]
            templates = [[0, 7, 2, 9], [0, 9, 7, 2], [0, 2, 9, 7]]
            extensions = mood == .sparse ? [7, 10] : [7, 10, 2]
            register = 52...79
            cycles = mood == .sparse ? [12, 12, 8] : [8, 8, 12]
        }
        let offset: Int
        switch mood {
        case .sparse: offset = 0
        case .moving: offset = 1
        case .strange: offset = 2
        }
        return Self(
            allowedModes: modes,
            progressionTemplates: Array(templates[offset...] + templates[..<offset]),
            allowedExtensions: extensions,
            register: register,
            maximumChordTones: extensions.count + 1,
            cycleBarChoices: cycles
        )
    }
}
#endif
