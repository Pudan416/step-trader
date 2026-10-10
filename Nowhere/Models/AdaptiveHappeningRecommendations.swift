import Foundation

struct PersonalHappeningRecommendation: Identifiable, Equatable {
    enum Reason: Equatable {
        case pinned, intention(HappeningIntention), familiar, previouslyChosen
        case interest(HappeningCatalogCategory), explore

        var title: String {
            switch self {
            case .pinned: "Pinned by you"
            case .intention(.observe): "You chose to observe"
            case .intention(.more): "You chose more often"
            case .intention(.less): "Tracking: less often"
            case .intention(.trySomething): "You want to try this"
            case .familiar: "From your recorded days"
            case .previouslyChosen: "Previously chosen"
            case let .interest(category): "Your interest: \(category.title)"
            case .explore: "Something to explore"
            }
        }
    }

    let id: String
    let reason: Reason
}

/// Local, deterministic choices for logging. Frequency is familiarity, never a
/// claim about how often an action actually happened. Display is frozen by UI.
enum AdaptiveHappeningRecommendations {
    static let maximumCount = 8

    private struct Candidate {
        let id: String
        let category: HappeningCatalogCategory
        let reason: PersonalHappeningRecommendation.Reason
        let tier: Int
        let score: Double
        let tie: UInt64
        let isDigital: Bool
        let isDiscovery: Bool
    }

    static func ranked(catalog: [Happening], profile: PersonalHappeningProfile,
                       historyByDay: [String: [String]], todayIDs: [String],
                       dayKey: String, at date: Date) -> [PersonalHappeningRecommendation] {
        let today = Set(todayIDs.map(HappeningDefaults.canonicalID))
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.isLenient = false
        let resetDay = profile.historyStartsAfterDayKey
            ?? profile.historyStartsAt.map { formatter.string(from: $0) }
        var usedDays: [String: Set<String>] = [:]
        var lastSeen: [String: Date] = [:]
        for (day, ids) in historyByDay {
            guard day < dayKey, let seen = formatter.date(from: day),
                  formatter.string(from: seen) == day,
                  resetDay.map({ day > $0 }) ?? true else { continue }
            for id in Set(ids.map(HappeningDefaults.canonicalID)) {
                usedDays[id, default: []].insert(day)
                lastSeen[id] = max(lastSeen[id] ?? .distantPast, seen)
            }
        }

        let hasRecordedHistory = !historyByDay.isEmpty
        let candidates = catalog.compactMap { happening -> Candidate? in
            let id = happening.id
            guard let definition = HappeningCatalog.byID[id], definition.isSelectable,
                  !today.contains(id), !profile.hiddenIDs.contains(id) else { return nil }
            let days = usedDays[id]?.count ?? 0
            let age = max(0, date.timeIntervalSince(lastSeen[id] ?? date) / 86_400)
            let familiarity = log1p(Double(days)) * pow(0.5, age / 21)
            let reason: PersonalHappeningRecommendation.Reason
            let tier: Int
            let score: Double
            let discovery: Bool
            if let intention = profile.intentions[id] {
                // "Less" keeps the record easy to find and explicitly labels it
                // as tracking. It never causes a suggestion to do the action.
                reason = .intention(intention); tier = 0
                score = profile.pinnedIDs.contains(id) ? 1 : 0; discovery = false
            } else if profile.pinnedIDs.contains(id) {
                reason = .pinned; tier = 0; score = 0; discovery = false
            } else if days > 0 {
                reason = .familiar; tier = 1; score = familiarity; discovery = false
            } else if !hasRecordedHistory, profile.historyStartsAt == nil,
                      happening.useCount >= 2, let lastUse = happening.lastUsedAt, lastUse <= date {
                // Bounded legacy fallback only when there are no daily snapshots.
                // Counters include deleted choices; do not present them as days.
                reason = .previouslyChosen; tier = 2
                score = log1p(Double(min(happening.useCount, 3)))
                    * pow(0.5, max(0, date.timeIntervalSince(lastUse) / 86_400) / 21)
                discovery = false
            } else if definition.discoveryEligible && profile.interests.contains(definition.category.rawValue) {
                reason = .interest(definition.category); tier = 3; score = 0; discovery = false
            } else if definition.discoveryEligible {
                reason = .explore; tier = 4; score = 0; discovery = true
            } else { return nil }
            return Candidate(id: id, category: definition.category, reason: reason,
                tier: tier, score: score, tie: stableHash(dayKey + "|" + id),
                isDigital: definition.tags.contains("screen_use"), isDiscovery: discovery)
        }.sorted {
            if $0.tier != $1.tier { return $0.tier < $1.tier }
            if $0.score != $1.score { return $0.score > $1.score }
            if $0.tie != $1.tie { return $0.tie < $1.tie }
            return $0.id < $1.id
        }

        var result: [PersonalHappeningRecommendation] = []
        var categoryCounts: [HappeningCatalogCategory: Int] = [:]
        var digitalCount = 0
        var discoveryCount = 0
        let hasPersonalSignals = candidates.contains { $0.tier < 4 }
        // A cold start is a small, optional selection; never fill all eight
        // places with arbitrary novelty when there is no profile or history.
        let discoveryLimit = hasPersonalSignals ? 2 : 3
        // Keep one optional discovery place when familiar candidates would fill
        // the list. Eight explicit choices still outrank discovery completely.
        let reservesDiscovery = hasPersonalSignals && candidates.contains { $0.isDiscovery }
            && candidates.filter { $0.tier == 0 }.count < maximumCount
        for candidate in candidates {
            guard result.count < maximumCount else { break }
            // Explicit choices take precedence over diversity quotas.
            if candidate.tier > 0 {
                if reservesDiscovery, !candidate.isDiscovery,
                   result.count >= maximumCount - 1 { continue }
                guard categoryCounts[candidate.category, default: 0] < 2,
                      !candidate.isDigital || digitalCount < 2,
                      !candidate.isDiscovery || discoveryCount < discoveryLimit else { continue }
            }
            result.append(.init(id: candidate.id, reason: candidate.reason))
            categoryCounts[candidate.category, default: 0] += 1
            if candidate.isDigital { digitalCount += 1 }
            if candidate.isDiscovery { discoveryCount += 1 }
        }
        return result
    }

    private static func stableHash(_ value: String) -> UInt64 {
        value.utf8.reduce(UInt64(14_695_981_039_346_656_037)) { ($0 ^ UInt64($1)) &* 1_099_511_628_211 }
    }
}
