import Foundation
import Observation

/// Survey answers are preferences, never HappeningStore records or use counters.
struct HappeningPersonalizationProfile: Codable, Equatable {
    enum Completion: String, Codable { case pending, completed, skipped }
    var version = 1
    var completion = Completion.pending
    var questionIndex = 0
    var hasStarted = false
    var answers: [String: Set<String>] = [:]
    var emotionDayKey: String?

    var question: HappeningPersonalizationQuestion {
        HappeningPersonalizationQuestion.allCases[min(max(questionIndex, 0), 5)]
    }
    var selectedChoiceIDs: Set<String> {
        Set(answers[question.rawValue, default: []].map { "survey:\(question.rawValue):\($0)" })
    }
    /// Ephemeral identities never enter the catalog, Canvas, or HappeningStore.
    var fieldChoices: [Happening] {
        guard hasStarted else { return [] }
        return question.choices.map {
            Happening(id: "survey:\(question.rawValue):\($0.id)", title: $0.label, isBuiltIn: false)
        }
    }

    func scores(dayKey: String, includeMood: Bool = true) -> [String: Double] {
        var result: [String: Double] = [:]
        for question in HappeningPersonalizationQuestion.allCases {
            if question == .feelings && (!includeMood || emotionDayKey != dayKey) { continue }
            let selected = answers[question.rawValue, default: []]
            if question == .habits && selected.contains("beer") {
                result["event_beer", default: 0] += 3
            }
            for choice in question.choices where selected.contains(choice.id) {
                for id in choice.events where HappeningEventTree.event(id) != nil {
                    result["event_" + id, default: 0] += question == .aspirations ? 1 : 3
                }
                for sphere in choice.spheres {
                    for event in HappeningEventTree.all where HappeningEventTree.personalSphereIndex(for: event.id) == sphere {
                        result["event_" + event.id, default: 0] += 0.6
                    }
                }
            }
        }
        return result
    }
}

struct HappeningPersonalizationChoice: Identifiable {
    let id: String
    let label: String
    var events: [String] = []
    var spheres: [Int] = []
    /// An existing catalog actor represents the preference visually. This does
    /// not claim that the representative event happened or add it to the day.
    var representativeEvent: String?
    var visualHappeningID: String? {
        (representativeEvent ?? events.first { HappeningEventTree.event($0) != nil }).map { "event_" + $0 }
    }
    init(_ id: String, _ label: String, _ events: [String] = [], spheres: [Int] = [], representativeEvent: String? = nil) {
        self.id = id; self.label = label; self.events = events; self.spheres = spheres
        self.representativeEvent = representativeEvent
    }
}

enum HappeningPersonalizationQuestion: String, CaseIterable {
    case routine, unwind, feelings, habits, people, aspirations
    var title: String {
        switch self {
        case .routine: "What does your day usually include?"
        case .unwind: "What do you do to chill?"
        case .feelings: "How have you been feeling lately?"
        case .habits: "Which habits feel familiar?"
        case .people: "Who do you spend time with?"
        case .aspirations: "What would you like to spend more time on?"
        }
    }
    var choices: [HappeningPersonalizationChoice] {
        switch self {
        case .routine: [
            .init("work", "Working", ["root_worked"]), .init("study", "Studying", ["solo", "class"]),
            .init("walk", "Going for walks", ["walk"]), .init("cook", "Cooking", ["cooked", "root_home"]),
            .init("friend", "Seeing friends", ["friend"]), .init("break", "Taking breaks", ["break", "root_chilled"]),
            .init("home", "Staying home", ["root_home"])]
        case .unwind: [
            .init("read", "Reading", ["book"]),
            .init("walk", "Walking", ["walk", "nature"]), .init("music", "Listening to music", ["music"]),
            .init("games", "Playing games", ["videogame", "boardgame"]),
            .init("doomscroll", "Doomscrolling", ["doomscroll"]), .init("coding", "Vibe coding", ["made"]),
            .init("movies", "Watching movies", ["movie"]), .init("series", "Watching series", ["show"])]
        case .feelings: [
            .init("calm", "Calm", ["calm"]), .init("happy", "Happy", ["happy"]), .init("curious", "Curious", ["curious"]),
            .init("tired", "Tired", ["tired"]), .init("anxious", "Anxious", ["anxious"]), .init("angry", "Angry", ["angry"]),
            .init("lonely", "Lonely", ["lonely"]), .init("mixed", "Mixed feelings", ["mixed"])]
        case .habits: [
            .init("coffee", "Drinking coffee", ["coffee"]), .init("smoked", "Smoking", ["smoked"]),
            .init("alcohol", "Drinking alcohol", ["drink", "beer"], representativeEvent: "drink"),
            .init("drunk", "Getting drunk", ["wasted"]), .init("late", "Staying up late", ["stayedlate"]),
            .init("games", "Playing video games", ["videogame"]), .init("time", "Losing track of time", ["losttime"]),
            .init("bed", "Staying in bed", ["bed"]), .init("nothing", "Getting little done", ["nothingwork"])]
        // Relationship context boosts a domain; it never pretends a call or text happened.
        case .people: [
            .init("friends", "Friends", ["friend"], spheres: [5]), .init("family", "Family", ["family"], spheres: [5]),
            .init("partner", "A partner", spheres: [5], representativeEvent: "peoplecall"), .init("colleagues", "Colleagues", ["colleague"], spheres: [0, 5]),
            .init("new", "New people", spheres: [5], representativeEvent: "guests"), .init("myself", "Mostly on my own", ["alonepeople"], spheres: [1])]
        case .aspirations: [
            .init("move", "Movement", spheres: [3], representativeEvent: "run"), .init("rest", "Rest", ["break", "nap", "root_chilled"], spheres: [1]),
            .init("connection", "Connection", spheres: [5], representativeEvent: "texted"), .init("create", "Creativity", ["made", "drew", "photos"], spheres: [1]),
            .init("learn", "Learning", ["solo", "book"], spheres: [0]), .init("new", "New experiences", ["new"], spheres: [4])]
        }
    }

}

@MainActor
enum HappeningPersonalizationStore {
    static var scope: String { AuthenticationService.shared.currentUser?.id ?? "local" }
    private static func key(_ scope: String) -> String { "happenings.personalization.v1." + scope }
    static func load(scope suppliedScope: String? = nil) -> HappeningPersonalizationProfile {
        let scope = suppliedScope ?? self.scope
        guard let data = UserDefaults.standard.data(forKey: key(scope)),
              let profile = try? JSONDecoder().decode(HappeningPersonalizationProfile.self, from: data), profile.version == 1
        else { return HappeningPersonalizationProfile() }
        return profile
    }
    static func draft(scope: String) -> HappeningPersonalizationProfile? {
        guard let data = UserDefaults.standard.data(forKey: key(scope) + ".draft") else { return nil }
        return try? JSONDecoder().decode(HappeningPersonalizationProfile.self, from: data)
    }
    static func saveDraft(_ profile: HappeningPersonalizationProfile, scope: String) {
        guard let data = try? JSONEncoder().encode(profile) else { return }
        UserDefaults.standard.set(data, forKey: key(scope) + ".draft")
    }
    static func clearDraft(scope: String) { UserDefaults.standard.removeObject(forKey: key(scope) + ".draft") }
    static func save(_ profile: HappeningPersonalizationProfile, scope: String) {
        guard let data = try? JSONEncoder().encode(profile) else { return }
        UserDefaults.standard.set(data, forKey: key(scope))
    }
}

/// Replays the existing tour with a fresh draft; committed preferences and days survive cancellation.
@Observable @MainActor
final class HappeningOnboardingCoordinator {
    static let shared = HappeningOnboardingCoordinator()
    var replayRevision = UUID()
    var suspendsCanvasTour = false
    var replayPending = false
    private(set) var replayScope: String?
    private(set) var freshQuestionsPending = false
    var requiresReplayQuestions: Bool { freshQuestionsPending || replayScope == HappeningPersonalizationStore.scope }
    func cancelReplay() { replayPending = false; replayScope = nil; freshQuestionsPending = false; suspendsCanvasTour = false }
    func didCompleteQuestions() { replayScope = nil; freshQuestionsPending = false }
    func prepareQuestions(scope: String) {
        guard freshQuestionsPending else { return }
        // Authentication can restore an account after Welcome appears. Reset the
        // draft only at the explicit Add action, for the account using it now.
        HappeningPersonalizationStore.saveDraft(HappeningPersonalizationProfile(), scope: scope)
        replayScope = scope
        freshQuestionsPending = false
    }
    func replay(source: String = "happeningsReplay") {
        replayScope = nil
        freshQuestionsPending = true
        suspendsCanvasTour = false
        replayPending = true
        replayRevision = UUID()
        CanvasTour.shared.start(source: source)
    }
}
