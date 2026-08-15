import Foundation

/// The ten built-in happenings and the addition economy's constants.
///
/// 31 built-ins across three categories become 10, chosen for everyday
/// specificity over category coverage. Any option id that exists in a user's
/// history but is no longer built-in is reconstituted as a user happening on
/// first launch, so nobody's past days lose their labels.
enum HappeningDefaults {

    // MARK: - Economy
    //
    // day = steps(20) + sleep(20) + happenings(60) = 100
    //
    // The 100 ceiling is deliberately unchanged — onboarding has a slide built
    // on it. Additions past the sixth still land on the canvas and still
    // increment `useCount`; they just stop earning.

    static let pointsPerAddition: Int = 10
    static let happeningsMaxPoints: Int = 60

    // MARK: - Built-ins
    //
    // Ids use the `happening_` namespace so they can never collide with the old
    // `body_` / `mind_` / `heart_` ids still sitting in users' saved days.

    static let builtIns: [Happening] = [
        Happening(id: "happening_walk",           title: "Walk",                   isBuiltIn: true),
        Happening(id: "happening_workout",        title: "Workout",                isBuiltIn: true),
        Happening(id: "happening_slept_well",     title: "Slept well",             isBuiltIn: true),
        Happening(id: "happening_called_someone", title: "Called someone I love",  isBuiltIn: true),
        Happening(id: "happening_drinks",         title: "Drinks with friends",    isBuiltIn: true),
        Happening(id: "happening_read",           title: "Read",                   isBuiltIn: true),
        Happening(id: "happening_laughed",        title: "Laughed",                isBuiltIn: true),
        Happening(id: "happening_made_something", title: "Made something",         isBuiltIn: true),
        Happening(id: "happening_outside",        title: "Time outside",           isBuiltIn: true),
        Happening(id: "happening_did_nothing",    title: "Did nothing on purpose", isBuiltIn: true)
    ]

    static let builtInIds: Set<String> = Set(builtIns.map(\.id))
}
