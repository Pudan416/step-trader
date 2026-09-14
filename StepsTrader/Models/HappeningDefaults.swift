import Foundation

/// The thirty built-in happenings and the addition economy's constants.
/// The original ten keep their identifiers and order. New choices follow
/// them so upgrading expands the field without rewriting saved days.
enum HappeningDefaults {

    // MARK: - Economy
    //
    // day = steps(20) + sleep(20) + happenings(60) = 100
    //
    // The 100 ceiling is deliberately unchanged — onboarding has a slide built
    // on it. Additions past the tenth still land on the canvas and still
    // increment `useCount`; they just stop earning.

    static let pointsPerAddition: Int = 6
    static let happeningsMaxPoints: Int = 60

    // MARK: - Built-ins
    //
    // Ids use the `happening_` namespace so they can never collide with the old
    // `body_` / `mind_` / `heart_` ids still sitting in users' saved days.

    static let builtIns: [Happening] = [
        Happening(id: "happening_walk",           title: "Walk",                   isBuiltIn: true),
        Happening(id: "happening_workout",        title: "Workout",                isBuiltIn: true),
        Happening(id: "happening_slept_well",     title: "Slept well",             isBuiltIn: true),
        Happening(id: "happening_called_someone", title: "Connected",              isBuiltIn: true),
        Happening(id: "happening_drinks",         title: "Time together",          isBuiltIn: true),
        Happening(id: "happening_read",           title: "Read",                   isBuiltIn: true),
        Happening(id: "happening_laughed",        title: "Laughed",                isBuiltIn: true),
        Happening(id: "happening_made_something", title: "Made something",         isBuiltIn: true),
        Happening(id: "happening_outside",        title: "Time outside",           isBuiltIn: true),
        Happening(id: "happening_did_nothing",    title: "Rested",                 isBuiltIn: true),
        Happening(id: "happening_cooked", title: "Cooked", isBuiltIn: true),
        Happening(id: "happening_shared_meal", title: "Shared a meal", isBuiltIn: true),
        Happening(id: "happening_hugged", title: "Hugged someone", isBuiltIn: true),
        Happening(id: "happening_met_someone", title: "Met someone new", isBuiltIn: true),
        Happening(id: "happening_helped", title: "Helped someone", isBuiltIn: true),
        Happening(id: "happening_played", title: "Played", isBuiltIn: true),
        Happening(id: "happening_danced", title: "Danced", isBuiltIn: true),
        Happening(id: "happening_sang", title: "Sang", isBuiltIn: true),
        Happening(id: "happening_drew", title: "Drew", isBuiltIn: true),
        Happening(id: "happening_wrote", title: "Wrote", isBuiltIn: true),
        Happening(id: "happening_photos", title: "Took photos", isBuiltIn: true),
        Happening(id: "happening_swam", title: "Swam", isBuiltIn: true),
        Happening(id: "happening_bike", title: "Rode a bike", isBuiltIn: true),
        Happening(id: "happening_stretched", title: "Stretched", isBuiltIn: true),
        Happening(id: "happening_explored", title: "Explored", isBuiltIn: true),
        Happening(id: "happening_film", title: "Watched a film", isBuiltIn: true),
        Happening(id: "happening_plants", title: "Tended plants", isBuiltIn: true),
        Happening(id: "happening_daydreamed", title: "Daydreamed", isBuiltIn: true),
        Happening(id: "happening_asked_for_help", title: "Asked for help", isBuiltIn: true),
        Happening(id: "happening_said_no", title: "Said no", isBuiltIn: true)
    ]

    static let builtInIds: Set<String> = Set(builtIns.map(\.id))
}
