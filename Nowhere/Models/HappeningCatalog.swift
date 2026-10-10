import Foundation

/// Browsing and Personal metadata. These categories do not change Canvas recipes
/// or the tags recorded in historical days.
enum HappeningCatalogCategory: String, Codable, CaseIterable, Identifiable, Hashable {
    case workStudy, movement, foodDrink, rest, care, people, home
    case outdoors, travel, creative, play, feelings, privateMoments

    var id: String { rawValue }

    var title: String {
        switch self {
        case .workStudy: "Work & learning"
        case .movement: "Movement"
        case .foodDrink: "Food & drink"
        case .rest: "Rest"
        case .care: "Care"
        case .people: "People"
        case .home: "Home"
        case .outdoors: "Outdoors"
        case .travel: "Getting around"
        case .creative: "Making things"
        case .play: "Culture & play"
        case .feelings: "Feelings"
        case .privateMoments: "Personal moments"
        }
    }

    /// Personal moments are selected from history or directly; they are never
    /// pulled in by a broad category interest.
    static var interests: [Self] { allCases.filter { $0 != .privateMoments } }
}

struct HappeningDefinition: Identifiable {
    let id: String
    let title: String
    let category: HappeningCatalogCategory
    let tags: [String]
    let discoveryEligible: Bool

    /// Every definition can be logged through the ordinary Canvas history.
    var isSelectable: Bool { true }

    init(_ id: String, _ title: String, _ category: HappeningCatalogCategory,
         tags: [String] = [], discoveryEligible: Bool = true) {
        self.id = id
        self.title = title
        self.category = category
        self.tags = tags
        self.discoveryEligible = discoveryEligible
    }

    var happening: Happening {
        Happening(id: id, title: title, isBuiltIn: true, tags: tags)
    }
}

/// Authoritative editorial identities, independent of the 100-position field.
/// Do not generate IDs from titles or reorder the original entries during edits.
enum HappeningCatalog {
    static let version = 4
    static let definitions: [HappeningDefinition] = original + extended
    static let byID = Dictionary(uniqueKeysWithValues: definitions.map { ($0.id, $0) })

    static func definition(for id: String) -> HappeningDefinition? {
        byID[HappeningDefaults.canonicalID(id)]
    }

    static func matches(_ happening: Happening, query: String,
                        category: HappeningCatalogCategory? = nil) -> Bool {
        let definition = definition(for: happening.id)
        guard category == nil || definition?.category == category else { return false }
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return query.isEmpty || happening.localizedTitle().localizedStandardContains(query)
            || definition?.category.title.localizedStandardContains(query) == true
    }

    private static let original: [HappeningDefinition] = [
        .init("event_root_worked", "Worked", .workStudy, tags: ["work_activity", "work_study"]),
        .init("event_root_chilled", "Chilled", .rest, tags: ["rest_play"]),
        .init("event_root_home", "Stayed home", .home, tags: ["home_everyday"]),
        .init("event_meal_breakfast", "Had breakfast", .foodDrink, tags: ["body_wellbeing", "food_drink", "meal"]),
        .init("event_walk", "Went for a walk", .outdoors, tags: ["body_wellbeing", "movement", "outdoors"]),
        .init("event_friend", "Saw a friend", .people, tags: ["people_connection", "social_context", "with_others"]),
        .init("event_break", "Took a break", .rest, tags: ["rest"]),
        .init("event_email", "Checked email", .workStudy, tags: ["digital_admin", "screen_use", "work_study"], discoveryEligible: false),
        .init("event_wrote", "Wrote", .creative, tags: ["making", "work_study"]),
        .init("event_made", "Made something", .creative, tags: ["making", "work_study"]),
        .init("event_meeting", "Went to a meeting", .workStudy, tags: ["in_person", "meeting", "work_study"]),
        .init("event_workcall", "Had a work call", .workStudy, tags: ["phone_call", "work_activity", "work_study"]),
        .init("event_deadline", "Felt deadline stress", .workStudy, tags: ["pressure", "stress", "work_study"], discoveryEligible: false),
        .init("event_bored", "Was bored at work", .workStudy, tags: ["boredom", "work_study"], discoveryEligible: false),
        .init("event_avoidedwork", "Avoided my work", .workStudy, tags: ["avoidance", "work_study"], discoveryEligible: false),
        .init("event_nothingwork", "Got nothing done", .workStudy, tags: ["work_activity", "work_study"], discoveryEligible: false),
        .init("event_class", "Went to class", .workStudy, tags: ["learning", "work_study"]),
        .init("event_solo", "Studied alone", .workStudy, tags: ["alone", "learning", "work_study"]),
        .init("event_group", "Studied with others", .workStudy, tags: ["learning", "with_others", "work_study"]),
        .init("event_listings", "Browsed job ads", .workStudy, tags: ["job_search", "screen_use", "work_study"]),
        .init("event_application", "Sent an application", .workStudy, tags: ["job_search", "work_study"]),
        .init("event_interview", "Had an interview", .workStudy, tags: ["conversation", "job_search", "work_study"]),
        .init("event_run", "Went for a run", .movement, tags: ["body_wellbeing", "exercise", "movement"]),
        .init("event_workout", "Worked out", .movement, tags: ["body_wellbeing", "exercise", "movement"]),
        .init("event_swam", "Swam", .movement, tags: ["body_wellbeing", "exercise", "movement"]),
        .init("event_stretched", "Stretched", .movement, tags: ["body_wellbeing", "exercise", "movement"]),
        .init("event_errands", "Ran errands", .movement, tags: ["body_wellbeing", "errands"]),
        .init("event_snack", "Had a snack", .foodDrink, tags: ["body_wellbeing", "food_drink"]),
        .init("event_meal_lunch", "Had lunch", .foodDrink, tags: ["body_wellbeing", "food_drink", "meal"]),
        .init("event_meal_dinner", "Had dinner", .foodDrink, tags: ["body_wellbeing", "food_drink", "meal"]),
        .init("event_coffee", "Had coffee", .foodDrink, tags: ["body_wellbeing", "caffeine", "food_drink"]),
        .init("event_tea", "Had tea", .foodDrink, tags: ["body_wellbeing", "caffeine", "food_drink"]),
        .init("event_wasted", "Got wasted", .foodDrink, tags: ["body_wellbeing", "food_drink", "alcohol"], discoveryEligible: false),
        .init("event_hangover", "Had a hangover", .foodDrink, tags: ["body_wellbeing", "tiredness", "alcohol"], discoveryEligible: false),
        .init("event_slept", "Slept", .rest, tags: ["body_wellbeing", "sleep"]),
        .init("event_nap", "Took a nap", .rest, tags: ["body_wellbeing", "rest", "sleep"]),
        .init("event_bed", "Stayed in bed", .rest, tags: ["body_wellbeing", "rest"], discoveryEligible: false),
        .init("event_shower", "Took a shower", .care, tags: ["body_wellbeing", "personal_care"]),
        .init("event_family", "Saw family", .people, tags: ["people_connection", "social_context", "with_others"]),
        .init("event_colleague", "Saw a colleague", .people, tags: ["people_connection", "social_context", "with_others"]),
        .init("event_texted", "Texted someone", .people, tags: ["communication", "people_connection"]),
        .init("event_peoplecall", "Called someone", .people, tags: ["people_connection", "phone_call"]),
        .init("event_snapped", "Snapped at someone", .people, tags: ["anger", "people_connection"], discoveryEligible: false),
        .init("event_avoidedpeople", "Avoided everyone", .people, tags: ["avoidance", "people_connection"], discoveryEligible: false),
        .init("event_helped", "Helped a friend", .care, tags: ["care", "people_connection", "with_others"]),
        .init("event_askedhelp", "Asked for help", .care, tags: ["care", "people_connection"]),
        .init("event_saidno", "Said no", .people, tags: ["boundaries", "people_connection"]),
        .init("event_child", "Looked after a kid", .care, tags: ["care", "childcare", "people_connection"]),
        .init("event_pet", "Cared for a pet", .care, tags: ["care", "people_connection", "pet"]),
        .init("event_alonepeople", "Kept to myself", .people, tags: ["alone", "people_connection"]),
        .init("event_leftout", "Felt left out", .people, tags: ["loneliness", "people_connection"], discoveryEligible: false),
        .init("event_cooked", "Cooked", .foodDrink, tags: ["cooking", "food_drink", "home_everyday"]),
        .init("event_cleaned", "Cleaned up", .home, tags: ["domestic", "home_everyday"]),
        .init("event_laundry", "Did the laundry", .home, tags: ["domestic", "home_everyday", "laundry"]),
        .init("event_fixed", "Fixed something", .home, tags: ["home_everyday", "repair"]),
        .init("event_plants", "Watered plants", .outdoors, tags: ["care", "home_everyday", "plants"]),
        .init("event_ignored", "Ignored the mess", .home, tags: ["domestic", "home_everyday"], discoveryEligible: false),
        .init("event_shopping", "Went shopping", .home, tags: ["errands", "home_everyday", "shopping"]),
        .init("event_paperwork", "Did paperwork", .home, tags: ["errands", "home_everyday"]),
        .init("event_appointment", "Had an appointment", .home, tags: ["errands", "home_everyday"]),
        .init("event_guests", "Had people over", .home, tags: ["home_everyday", "social_context", "with_others"]),
        .init("event_doomscroll", "Doomscrolled", .home, tags: ["home_everyday", "screen_use", "social_media", "time_slip"], discoveryEligible: false),
        .init("event_transit", "Took the bus", .travel, tags: ["commute", "getting_around", "public_transit"]),
        .init("event_train", "Took the train", .travel, tags: ["commute", "getting_around", "public_transit"]),
        .init("event_car", "Drove to work", .travel, tags: ["car_travel", "commute", "getting_around"]),
        .init("event_bike", "Biked to work", .travel, tags: ["commute", "getting_around", "movement"]),
        .init("event_walked", "Walked to work", .travel, tags: ["commute", "getting_around", "movement"]),
        .init("event_cafe", "Went to a café", .foodDrink, tags: ["cafe_or_bar", "getting_around"]),
        .init("event_bar", "Went to a bar", .foodDrink, tags: ["cafe_or_bar", "getting_around"]),
        .init("event_nature", "Spent time outside", .outdoors, tags: ["getting_around", "outdoors"]),
        .init("event_lost", "Got lost", .travel, tags: ["getting_around", "time_slip"], discoveryEligible: false),
        .init("event_detour", "Took a detour", .travel, tags: ["getting_around", "location_change"]),
        .init("event_new", "Went somewhere new", .travel, tags: ["getting_around", "location_change", "new_place"]),
        .init("event_videos", "Watched videos", .play, tags: ["media", "rest_play", "screen_use"], discoveryEligible: false),
        .init("event_movie", "Watched a movie", .play, tags: ["media", "rest_play", "screen_use"]),
        .init("event_show", "Watched a show", .play, tags: ["media", "rest_play", "screen_use"]),
        .init("event_losttime", "Lost track of time", .play, tags: ["rest_play", "screen_use", "time_slip"], discoveryEligible: false),
        .init("event_book", "Read a book", .play, tags: ["reading", "rest_play"]),
        .init("event_news", "Read the news", .play, tags: ["news", "reading", "rest_play"], discoveryEligible: false),
        .init("event_articles", "Read posts", .play, tags: ["reading", "rest_play"], discoveryEligible: false),
        .init("event_videogame", "Played video games", .play, tags: ["play_or_hobby", "rest_play", "screen_use"], discoveryEligible: false),
        .init("event_boardgame", "Played a board game", .play, tags: ["play_or_hobby", "rest_play"]),
        .init("event_withkid", "Played with a kid", .play, tags: ["play_or_hobby", "rest_play", "with_others"]),
        .init("event_music", "Listened to music", .play, tags: ["music", "rest_play"]),
        .init("event_hobby", "Did hobby stuff", .creative, tags: ["play_or_hobby", "rest_play"]),
        .init("event_drew", "Drew", .creative, tags: ["making", "rest_play"]),
        .init("event_sang", "Sang", .creative, tags: ["making", "music", "rest_play"]),
        .init("event_danced", "Danced", .play, tags: ["movement", "music", "rest_play"]),
        .init("event_photos", "Took photos", .creative, tags: ["making", "rest_play"]),
        .init("event_nothingplay", "Did nothing much", .rest, tags: ["rest_play", "unstructured_time"]),
        .init("event_rage", "Raged", .feelings, tags: ["anger", "feelings"], discoveryEligible: false),
        .init("event_happy", "Felt happy", .feelings, tags: ["feelings", "happiness"], discoveryEligible: false),
        .init("event_tired", "Felt tired", .feelings, tags: ["feelings", "tiredness"], discoveryEligible: false),
        .init("event_anxious", "Felt anxious", .feelings, tags: ["anxiety", "feelings"], discoveryEligible: false),
        .init("event_angry", "Felt angry", .feelings, tags: ["anger", "feelings"], discoveryEligible: false),
        .init("event_calm", "Felt calm", .feelings, tags: ["calm", "feelings"], discoveryEligible: false),
        .init("event_lonely", "Felt lonely", .feelings, tags: ["feelings", "loneliness"], discoveryEligible: false),
        .init("event_curious", "Felt curious", .feelings, tags: ["curiosity", "feelings"], discoveryEligible: false),
        .init("event_okay", "Felt okay", .feelings, tags: ["feelings", "okayness"], discoveryEligible: false),
        .init("event_mixed", "Had mixed feelings", .feelings, tags: ["feelings", "mixed_emotions"], discoveryEligible: false),
    ]

    private static let extended: [HappeningDefinition] = [
        .init("event_presented_work", "Presented work", .workStudy, tags: ["work_study", "learning"]),
        .init("event_gave_feedback", "Gave feedback", .workStudy, tags: ["work_study", "learning"]),
        .init("event_got_feedback", "Got feedback", .workStudy, tags: ["work_study", "learning"]),
        .init("event_mentored", "Mentored someone", .workStudy, tags: ["work_study", "learning"]),
        .init("event_learned_language", "Learned a language", .workStudy, tags: ["work_study", "learning"]),
        .init("event_practised_skill", "Practised a skill", .workStudy, tags: ["work_study", "learning"]),
        .init("event_finished_project", "Finished a project", .workStudy, tags: ["work_study", "learning"]),
        .init("event_started_project", "Started a project", .workStudy, tags: ["work_study", "learning"]),
        .init("event_took_exam", "Took an exam", .workStudy, tags: ["work_study", "learning"]),
        .init("event_gave_lesson", "Gave a lesson", .workStudy, tags: ["work_study", "learning"]),
        .init("event_read_paper", "Read a paper", .workStudy, tags: ["work_study", "learning"]),
        .init("event_visited_library", "Used a library", .workStudy, tags: ["work_study", "learning"]),
        .init("event_worked_overtime", "Worked overtime", .workStudy, tags: ["work_study", "learning"], discoveryEligible: false),
        .init("event_rode_bike", "Rode a bike", .movement, tags: ["body_wellbeing", "movement"]),
        .init("event_hiked", "Hiked", .movement, tags: ["body_wellbeing", "movement"]),
        .init("event_climbed", "Went climbing", .movement, tags: ["body_wellbeing", "movement"]),
        .init("event_practised_yoga", "Practised yoga", .movement, tags: ["body_wellbeing", "movement"]),
        .init("event_practised_pilates", "Practised pilates", .movement, tags: ["body_wellbeing", "movement"]),
        .init("event_lifted_weights", "Lifted weights", .movement, tags: ["body_wellbeing", "movement"]),
        .init("event_played_tennis", "Played tennis", .movement, tags: ["body_wellbeing", "movement"]),
        .init("event_played_football", "Played football", .movement, tags: ["body_wellbeing", "movement"]),
        .init("event_played_basketball", "Played basketball", .movement, tags: ["body_wellbeing", "movement"]),
        .init("event_skated", "Skated", .movement, tags: ["body_wellbeing", "movement"]),
        .init("event_skied", "Skied", .movement, tags: ["body_wellbeing", "movement"]),
        .init("event_surfed", "Surfed", .movement, tags: ["body_wellbeing", "movement"]),
        .init("event_kayaked", "Kayaked", .movement, tags: ["body_wellbeing", "movement"]),
        .init("event_skipped_rope", "Skipped rope", .movement, tags: ["body_wellbeing", "movement"]),
        .init("event_played_badminton", "Played badminton", .movement, tags: ["body_wellbeing", "movement"]),
        .init("event_played_volleyball", "Played volleyball", .movement, tags: ["body_wellbeing", "movement"]),
        .init("event_baked_bread", "Baked bread", .foodDrink, tags: ["body_wellbeing", "food_drink"]),
        .init("event_baked_cake", "Baked a cake", .foodDrink, tags: ["body_wellbeing", "food_drink"]),
        .init("event_tried_recipe", "Tried a recipe", .foodDrink, tags: ["body_wellbeing", "food_drink"]),
        .init("event_grilled_food", "Grilled food", .foodDrink, tags: ["body_wellbeing", "food_drink"]),
        .init("event_packed_lunch", "Packed a lunch", .foodDrink, tags: ["body_wellbeing", "food_drink"]),
        .init("event_shared_meal", "Shared a meal", .foodDrink, tags: ["body_wellbeing", "food_drink"]),
        .init("event_ate_out", "Ate at a restaurant", .foodDrink, tags: ["body_wellbeing", "food_drink"]),
        .init("event_ordered_takeaway", "Ordered takeaway", .foodDrink, tags: ["body_wellbeing", "food_drink"]),
        .init("event_tried_food", "Tried a new food", .foodDrink, tags: ["body_wellbeing", "food_drink"]),
        .init("event_picked_fruit", "Picked fruit", .foodDrink, tags: ["body_wellbeing", "food_drink"]),
        .init("event_made_smoothie", "Made a smoothie", .foodDrink, tags: ["body_wellbeing", "food_drink"]),
        .init("event_made_preserves", "Made preserves", .foodDrink, tags: ["body_wellbeing", "food_drink"]),
        .init("event_ate_dessert", "Had dessert", .foodDrink, tags: ["body_wellbeing", "food_drink"]),
        .init("event_ate_late", "Ate late", .foodDrink, tags: ["body_wellbeing", "food_drink"], discoveryEligible: false),
        .init("event_skipped_meal", "Skipped a meal", .foodDrink, tags: ["body_wellbeing", "food_drink"], discoveryEligible: false),
        .init("event_overate", "Ate past fullness", .foodDrink, tags: ["body_wellbeing", "food_drink"], discoveryEligible: false),
        .init("event_slept_in", "Slept in", .rest, tags: ["body_wellbeing", "rest"]),
        .init("event_went_to_bed_early", "Went to bed early", .rest, tags: ["body_wellbeing", "rest"]),
        .init("event_stayed_up_late", "Stayed up late", .rest, tags: ["body_wellbeing", "rest"], discoveryEligible: false),
        .init("event_lay_down", "Lay down for a while", .rest, tags: ["body_wellbeing", "rest"]),
        .init("event_sat_in_silence", "Sat in silence", .rest, tags: ["body_wellbeing", "rest"]),
        .init("event_meditated", "Meditated", .rest, tags: ["body_wellbeing", "rest"]),
        .init("event_breathing_exercise", "Tried slow breathing", .rest, tags: ["body_wellbeing", "rest"]),
        .init("event_took_bath", "Took a bath", .rest, tags: ["body_wellbeing", "rest"]),
        .init("event_went_to_sauna", "Went to a sauna", .rest, tags: ["body_wellbeing", "rest"]),
        .init("event_got_massage", "Had a massage", .rest, tags: ["body_wellbeing", "rest"]),
        .init("event_rested_eyes", "Rested my eyes", .rest, tags: ["body_wellbeing", "rest"]),
        .init("event_watched_clouds", "Watched clouds", .rest, tags: ["body_wellbeing", "rest"]),
        .init("event_brushed_teeth", "Brushed my teeth", .care, tags: ["body_wellbeing", "personal_care"]),
        .init("event_flossed", "Flossed my teeth", .care, tags: ["body_wellbeing", "personal_care"]),
        .init("event_washed_hair", "Washed my hair", .care, tags: ["body_wellbeing", "personal_care"]),
        .init("event_had_haircut", "Had a haircut", .care, tags: ["body_wellbeing", "personal_care"]),
        .init("event_shaved", "Shaved", .care, tags: ["body_wellbeing", "personal_care"]),
        .init("event_did_skincare", "Did skincare", .care, tags: ["body_wellbeing", "personal_care"]),
        .init("event_wore_sunscreen", "Wore sunscreen", .care, tags: ["body_wellbeing", "personal_care"]),
        .init("event_saw_dentist", "Saw a dentist", .care, tags: ["body_wellbeing", "personal_care"]),
        .init("event_saw_doctor", "Saw a doctor", .care, tags: ["body_wellbeing", "personal_care"], discoveryEligible: false),
        .init("event_took_medicine", "Took my medicine", .care, tags: [], discoveryEligible: false),
        .init("event_went_to_therapy", "Went to therapy", .care, tags: [], discoveryEligible: false),
        .init("event_had_period", "Had my period", .care, tags: [], discoveryEligible: false),
        .init("event_felt_ill", "Felt ill", .care, tags: ["body_wellbeing", "personal_care"], discoveryEligible: false),
        .init("event_had_pain", "Was in pain", .care, tags: ["body_wellbeing", "personal_care"], discoveryEligible: false),
        .init("event_met_new_person", "Met someone new", .people, tags: ["people_connection", "with_others"]),
        .init("event_hugged_someone", "Hugged someone", .people, tags: ["people_connection", "with_others"]),
        .init("event_had_date", "Went on a date", .people, tags: ["people_connection", "with_others"]),
        .init("event_kissed_someone", "Kissed someone", .people, tags: ["people_connection", "with_others"]),
        .init("event_had_deep_talk", "Had a deep talk", .people, tags: ["people_connection", "with_others"]),
        .init("event_reconnected", "Reconnected", .people, tags: ["people_connection", "with_others"]),
        .init("event_made_friend", "Made a friend", .people, tags: ["people_connection", "with_others"]),
        .init("event_sent_letter", "Sent a letter", .people, tags: ["people_connection", "with_others"]),
        .init("event_sent_voice_note", "Sent a voice note", .people, tags: ["people_connection", "with_others"]),
        .init("event_thanked_someone", "Thanked someone", .people, tags: ["people_connection", "with_others"]),
        .init("event_apologised", "Apologised", .people, tags: ["people_connection", "with_others"]),
        .init("event_forgave_someone", "Forgave someone", .people, tags: ["people_connection", "with_others"]),
        .init("event_had_argument", "Had an argument", .people, tags: ["people_connection", "with_others"], discoveryEligible: false),
        .init("event_set_boundary", "Set a boundary", .people, tags: ["people_connection", "with_others"]),
        .init("event_volunteered", "Volunteered", .people, tags: ["people_connection", "with_others"]),
        .init("event_gave_gift", "Gave a gift", .people, tags: ["people_connection", "with_others"]),
        .init("event_received_gift", "Received a gift", .people, tags: ["people_connection", "with_others"]),
        .init("event_washed_dishes", "Washed dishes", .home, tags: ["home_everyday", "domestic"]),
        .init("event_vacuumed", "Vacuumed", .home, tags: ["home_everyday", "domestic"]),
        .init("event_changed_sheets", "Changed the sheets", .home, tags: ["home_everyday", "domestic"]),
        .init("event_took_out_rubbish", "Took out the rubbish", .home, tags: ["home_everyday", "domestic"]),
        .init("event_recycled", "Sorted recycling", .home, tags: ["home_everyday", "domestic"]),
        .init("event_decluttered", "Cleared some space", .home, tags: ["home_everyday", "domestic"]),
        .init("event_mended_clothes", "Mended clothes", .home, tags: ["home_everyday", "domestic"]),
        .init("event_ironed", "Ironed clothes", .home, tags: ["home_everyday", "domestic"]),
        .init("event_assembled_furniture", "Built furniture", .home, tags: ["home_everyday", "domestic"]),
        .init("event_rearranged_room", "Rearranged a room", .home, tags: ["home_everyday", "domestic"]),
        .init("event_decorated_home", "Decorated my home", .home, tags: ["home_everyday", "domestic"]),
        .init("event_paid_bill", "Paid a bill", .home, tags: ["home_everyday", "domestic"]),
        .init("event_planned_budget", "Planned my budget", .home, tags: ["home_everyday", "domestic"]),
        .init("event_posted_parcel", "Posted a parcel", .home, tags: ["home_everyday", "domestic"]),
        .init("event_donated_items", "Donated things", .home, tags: ["home_everyday", "domestic"]),
        .init("event_bought_groceries", "Bought groceries", .home, tags: ["home_everyday", "domestic"]),
        .init("event_walked_dog", "Walked a dog", .home, tags: ["home_everyday", "domestic"]),
        .init("event_visited_park", "Visited a park", .outdoors, tags: ["getting_around", "outdoors"]),
        .init("event_sat_by_water", "Sat by the water", .outdoors, tags: ["getting_around", "outdoors"]),
        .init("event_visited_beach", "Went to the beach", .outdoors, tags: ["getting_around", "outdoors"]),
        .init("event_watched_sunrise", "Watched the sunrise", .outdoors, tags: ["getting_around", "outdoors"]),
        .init("event_watched_sunset", "Watched the sunset", .outdoors, tags: ["getting_around", "outdoors"]),
        .init("event_stargazed", "Looked at the stars", .outdoors, tags: ["getting_around", "outdoors"]),
        .init("event_birdwatched", "Watched birds", .outdoors, tags: ["getting_around", "outdoors"]),
        .init("event_planted_something", "Planted something", .outdoors, tags: ["getting_around", "outdoors"]),
        .init("event_weeded_garden", "Weeded the garden", .outdoors, tags: ["getting_around", "outdoors"]),
        .init("event_picnicked", "Had a picnic", .outdoors, tags: ["getting_around", "outdoors"]),
        .init("event_camped", "Went camping", .outdoors, tags: ["getting_around", "outdoors"]),
        .init("event_walked_in_rain", "Walked in the rain", .outdoors, tags: ["getting_around", "outdoors"]),
        .init("event_collected_litter", "Picked up litter", .outdoors, tags: ["getting_around", "outdoors"]),
        .init("event_flew", "Took a flight", .travel, tags: ["getting_around", "location_change"]),
        .init("event_took_ferry", "Took a ferry", .travel, tags: ["getting_around", "location_change"]),
        .init("event_took_tram", "Took a tram", .travel, tags: ["getting_around", "location_change"]),
        .init("event_took_metro", "Took the metro", .travel, tags: ["getting_around", "location_change"]),
        .init("event_rode_taxi", "Took a taxi", .travel, tags: ["getting_around", "location_change"]),
        .init("event_rode_scooter", "Rode a scooter", .travel, tags: ["getting_around", "location_change"]),
        .init("event_went_road_trip", "Went on a road trip", .travel, tags: ["getting_around", "location_change"]),
        .init("event_visited_town", "Visited another town", .travel, tags: ["getting_around", "location_change"]),
        .init("event_packed_bag", "Packed a bag", .travel, tags: ["getting_around", "location_change"]),
        .init("event_unpacked", "Unpacked", .travel, tags: ["getting_around", "location_change"]),
        .init("event_painted", "Painted", .creative, tags: ["rest_play", "making"]),
        .init("event_made_collage", "Made a collage", .creative, tags: ["rest_play", "making"]),
        .init("event_sculpted", "Sculpted", .creative, tags: ["rest_play", "making"]),
        .init("event_made_pottery", "Made pottery", .creative, tags: ["rest_play", "making"]),
        .init("event_knitted", "Knitted", .creative, tags: ["rest_play", "making"]),
        .init("event_sewed", "Sewed", .creative, tags: ["rest_play", "making"]),
        .init("event_embroidered", "Embroidered", .creative, tags: ["rest_play", "making"]),
        .init("event_folded_origami", "Folded origami", .creative, tags: ["rest_play", "making"]),
        .init("event_played_instrument", "Played an instrument", .creative, tags: ["rest_play", "making"]),
        .init("event_made_music", "Made music", .creative, tags: ["rest_play", "making"]),
        .init("event_wrote_poem", "Wrote a poem", .creative, tags: ["rest_play", "making"]),
        .init("event_wrote_story", "Wrote a story", .creative, tags: ["rest_play", "making"]),
        .init("event_kept_journal", "Wrote in a journal", .creative, tags: ["rest_play", "making"]),
        .init("event_recorded_sound", "Recorded sounds", .creative, tags: ["rest_play", "making"]),
        .init("event_edited_video", "Edited a video", .creative, tags: ["rest_play", "making"]),
        .init("event_coded_project", "Coded a project", .creative, tags: ["rest_play", "making"]),
        .init("event_made_print", "Made a print", .creative, tags: ["rest_play", "making"]),
        .init("event_arranged_flowers", "Arranged flowers", .creative, tags: ["rest_play", "making"]),
        .init("event_visited_museum", "Visited a museum", .play, tags: ["rest_play", "play_or_hobby"]),
        .init("event_visited_gallery", "Visited a gallery", .play, tags: ["rest_play", "play_or_hobby"]),
        .init("event_went_concert", "Went to a concert", .play, tags: ["rest_play", "play_or_hobby"]),
        .init("event_went_theatre", "Went to the theatre", .play, tags: ["rest_play", "play_or_hobby"]),
        .init("event_went_cinema", "Went to the cinema", .play, tags: ["rest_play", "play_or_hobby"]),
        .init("event_listened_podcast", "Heard a podcast", .play, tags: ["rest_play", "play_or_hobby"]),
        .init("event_listened_audiobook", "Heard an audiobook", .play, tags: ["rest_play", "play_or_hobby"]),
        .init("event_did_puzzle", "Did a puzzle", .play, tags: ["rest_play", "play_or_hobby"]),
        .init("event_played_cards", "Played cards", .play, tags: ["rest_play", "play_or_hobby"]),
        .init("event_played_chess", "Played chess", .play, tags: ["rest_play", "play_or_hobby"]),
        .init("event_tried_new_hobby", "Tried a new hobby", .play, tags: ["rest_play", "play_or_hobby"]),
        .init("event_went_karaoke", "Went to karaoke", .play, tags: ["rest_play", "play_or_hobby"]),
        .init("event_felt_grateful", "Felt grateful", .feelings, tags: ["feelings"], discoveryEligible: false),
        .init("event_felt_proud", "Felt proud", .feelings, tags: ["feelings"], discoveryEligible: false),
        .init("event_felt_relieved", "Felt relieved", .feelings, tags: ["feelings"], discoveryEligible: false),
        .init("event_felt_excited", "Felt excited", .feelings, tags: ["feelings"], discoveryEligible: false),
        .init("event_felt_inspired", "Felt inspired", .feelings, tags: ["feelings"], discoveryEligible: false),
        .init("event_felt_safe", "Felt safe", .feelings, tags: ["feelings"], discoveryEligible: false),
        .init("event_felt_sad", "Felt sad", .feelings, tags: ["feelings"], discoveryEligible: false),
        .init("event_felt_overwhelmed", "Felt overwhelmed", .feelings, tags: ["feelings"], discoveryEligible: false),
        .init("event_felt_disappointed", "Felt disappointed", .feelings, tags: ["feelings"], discoveryEligible: false),
        .init("event_felt_ashamed", "Felt ashamed", .feelings, tags: ["feelings"], discoveryEligible: false),
        .init("event_felt_jealous", "Felt jealous", .feelings, tags: ["feelings"], discoveryEligible: false),
        .init("event_cried", "Cried", .feelings, tags: ["feelings"], discoveryEligible: false),
        .init("event_laughed", "Laughed", .feelings, tags: ["feelings"], discoveryEligible: false),
        .init("event_smoked_cigarette", "Smoked a cigarette", .privateMoments, tags: ["smoking"], discoveryEligible: false),
        .init("event_vaped", "Vaped", .privateMoments, tags: ["smoking"], discoveryEligible: false),
        .init("event_drank_beer", "Drank beer", .privateMoments, tags: ["alcohol"], discoveryEligible: false),
        .init("event_drank_wine", "Drank wine", .privateMoments, tags: ["alcohol"], discoveryEligible: false),
        .init("event_drank_spirits", "Drank spirits", .privateMoments, tags: ["alcohol"], discoveryEligible: false),
        .init("event_used_substance", "Used a substance", .privateMoments, tags: ["substance_use"], discoveryEligible: false),
        .init("event_smoked_hookah", "Smoked hookah", .privateMoments, tags: ["smoking"], discoveryEligible: false),
    ]
}
