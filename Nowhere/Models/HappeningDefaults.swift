import Foundation

/// The reviewed fixed catalog and the addition economy. Historical identities
/// remain resolvable separately; they are not additional selectable choices.
enum HappeningDefaults {

    // MARK: - Economy
    //
    // day = steps(20) + sleep(20) + happenings(60) = 100
    //
    // The 100 ceiling is deliberately unchanged — onboarding has a slide built
    // on it. A day accepts up to ten additions, each earning six colors.

    static let maximumDailyAdditions: Int = 10
    static let pointsPerAddition: Int = 6
    static let happeningsMaxPoints: Int = 60

    // MARK: - Built-ins
    //
    // Original IDs/copy are historical resolvers, not extra selectable choices.

    static let legacyBuiltIns: [Happening] = [
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
        Happening(id: "happening_said_no", title: "Said no", isBuiltIn: true),
        Happening(id: "happening_listened", title: "Listened", isBuiltIn: true)
    ]

    static let maximumCatalogCount = 100
    static let allowsCustomCreation = false

    // Retired choices still resolve in archived days and restored entries.
    private static let retiredEventTitles: [String: String] = [
        "event_root_ate": "Ate", "event_ate": "Ate a meal",
        "event_alonefood": "Ate alone", "event_root_wentout": "Went out",
        "event_root_people": "Saw people", "event_computer": "Worked at a desk",
        "event_tasks": "Did my tasks", "event_stayedin": "Stayed indoors",
        "event_relaxed": "Chilled at home", "event_gym": "Went to the gym",
        "event_store": "Went to a store", "event_scroll": "Scrolled for hours"
    ]

    static func historicalTitle(for id: String) -> String? {
        retiredEventTitles[id] ?? legacyBuiltIns.first { $0.id == id }?.title
    }

    /// System identities are shared between accounts. The legacy custom table
    /// has a global ID key, so these must never be uploaded as user-owned rows.
    static func customHappeningsForSync(_ happenings: [Happening]) -> [Happening] {
        return happenings.filter { happening in
            !happening.isBuiltIn && !isSystemHappeningID(happening.id)
        }
    }

    static func isSystemHappeningID(_ id: String) -> Bool {
        ["event_", "happening_", "body_", "mind_", "heart_", "health_workout_"]
            .contains(where: id.hasPrefix)
    }

    /// One catalog backs Personal, All, the old chooser and external suggestions.
    static let builtIns: [Happening] = HappeningEventTree.all.map {
        Happening(id: "event_\($0.id)", title: $0.title, isBuiltIn: true, tags: HappeningEventTree.tags(for: $0.id))
    }
    static let builtInIds: Set<String> = Set(builtIns.map(\.id))

    /// Known equivalents affect new-choice selection only, never saved history.
    /// Generic historical meals, contacts and outings are not narrowed to new roots.
    static func canonicalID(_ id: String) -> String {
        if id.hasPrefix("health_workout_"), let type = UInt(id.dropFirst(15)) {
            // Persisted HKWorkoutActivityType raw values, confirmed against the SDK.
            switch type {
            case 52: return "event_walk"
            case 37: return "event_run"
            case 46: return "event_swam"
            case 14, 77, 78: return "event_danced"
            case 62: return "event_stretched"
            default: return id
            }
        }
        switch id {
        case "happening_walk", "body_walking": return "event_walk"
        case "happening_read": return "event_book"
        case "happening_workout", "body_physical_effort": return "event_workout"
        case "happening_did_nothing", "body_resting": return "event_root_chilled"
        case "event_computer", "event_tasks": return "event_root_worked"
        case "event_relaxed": return "event_root_chilled"
        case "happening_made_something": return "event_made"
        case "happening_cooked": return "event_cooked"
        case "happening_film": return "event_movie"
        case "happening_outside": return "event_nature"
        case "happening_danced": return "event_danced"
        case "happening_sang": return "event_sang"
        case "happening_drew": return "event_drew"
        case "happening_wrote", "mind_writing": return "event_wrote"
        case "happening_photos": return "event_photos"
        case "happening_swam": return "event_swam"
        case "happening_stretched", "body_stretching": return "event_stretched"
        case "happening_asked_for_help": return "event_askedhelp"
        case "happening_said_no": return "event_saidno"
        default: return id
        }
    }

    static func selectableHappening(id: String) -> Happening? {
        let canonical = canonicalID(id)
        return builtIns.first { $0.id == canonical }
    }
}
