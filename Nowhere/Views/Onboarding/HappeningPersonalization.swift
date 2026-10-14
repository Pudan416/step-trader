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

    func scores(dayKey: String, includeMood: Bool = true) -> [String: Double] {
        var result: [String: Double] = [:]
        for question in HappeningPersonalizationQuestion.allCases {
            if question == .feelings && (!includeMood || emotionDayKey != dayKey) { continue }
            for choice in question.choices where answers[question.rawValue, default: []].contains(choice.id) {
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
    init(_ id: String, _ label: String, _ events: [String] = [], spheres: [Int] = []) {
        self.id = id; self.label = label; self.events = events; self.spheres = spheres
    }
}

enum HappeningPersonalizationQuestion: String, CaseIterable {
    case routine, unwind, feelings, habits, people, aspirations
    var title: String {
        switch self {
        case .routine: "What does your day usually include?"
        case .unwind: "What do you do to chill?"
        case .feelings: "How have you been feeling lately?"
        case .habits: "Any habits you’ve noticed?"
        case .people: "Who do you spend time with?"
        case .aspirations: "What would you like to spend more time on?"
        }
    }
    var choices: [HappeningPersonalizationChoice] {
        switch self {
        case .routine: [
            .init("work", "Worked", ["root_worked"]), .init("study", "Studied", ["solo", "class"]),
            .init("walk", "Went for a walk", ["walk"]), .init("cook", "Cooked", ["cooked", "root_home"]),
            .init("friend", "Saw a friend", ["friend"]), .init("break", "Took a break", ["break", "root_chilled"]),
            .init("home", "Stayed home", ["root_home"])]
        case .unwind: [
            .init("read", "Reading", ["book"]), .init("cook", "Cooking", ["cooked", "root_home"]),
            .init("walk", "Walking", ["walk", "nature"]), .init("music", "Listening to music", ["music"]),
            .init("games", "Playing games", ["videogame", "boardgame"]), .init("friends", "Seeing friends", ["friend"]),
            .init("photos", "Taking photos", ["photos"]), .init("make", "Making things", ["made", "hobby", "drew"])]
        case .feelings: [
            .init("calm", "Calm", ["calm"]), .init("happy", "Happy", ["happy"]), .init("curious", "Curious", ["curious"]),
            .init("tired", "Tired", ["tired"]), .init("anxious", "Anxious", ["anxious"]), .init("angry", "Angry", ["angry"]),
            .init("lonely", "Lonely", ["lonely"]), .init("mixed", "Mixed", ["mixed"])]
        case .habits: [
            .init("coffee", "Had coffee", ["coffee"]), .init("smoked", "Smoked", ["smoked"]),
            .init("beer", "Had a beer", ["beer"]), .init("late", "Stayed up late", ["stayedlate"]),
            .init("games", "Played video games", ["videogame"]), .init("time", "Lost track of time", ["losttime"]),
            .init("bed", "Stayed in bed", ["bed"]), .init("nothing", "Got nothing done", ["nothingwork"])]
        // Relationship context boosts a domain; it never pretends a call or text happened.
        case .people: [
            .init("friends", "Friends", ["friend"], spheres: [5]), .init("family", "Family", ["family"], spheres: [5]),
            .init("partner", "A partner", spheres: [5]), .init("colleagues", "Colleagues", ["colleague"], spheres: [0, 5]),
            .init("new", "New people", spheres: [5]), .init("myself", "Mostly myself", ["alonepeople"], spheres: [1])]
        case .aspirations: [
            .init("move", "Movement", spheres: [3]), .init("rest", "Rest", ["break", "nap", "root_chilled"], spheres: [1]),
            .init("connection", "Connection", spheres: [5]), .init("create", "Creativity", ["made", "drew", "photos"], spheres: [1]),
            .init("learn", "Learning", ["solo", "book"], spheres: [0]), .init("new", "New experiences", ["new"], spheres: [4])]
        }
    }
    var presetID: String {
        switch self {
        case .routine: "legacy.soft-square"
        case .unwind: "genome.soft-clover"
        case .feelings: "legacy.rounded-hexagon"
        case .habits: "legacy.rounded-triangle"
        case .people: "genome.windflower"
        case .aspirations: "genome.concave-square"
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

/// Requests navigation only. Debug replay does not reset daily records or legacy onboarding.
@Observable @MainActor
final class HappeningOnboardingCoordinator {
    static let shared = HappeningOnboardingCoordinator()
    var replayRevision = UUID()
    var suspendsCanvasTour = false
    var replayPending = false
    func replay() { replayPending = true; replayRevision = UUID() }
}
