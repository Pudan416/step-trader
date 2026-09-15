import Foundation

enum HappeningPaletteSelectionError: Error, Equatable {
    case requiresExactlyTen
    case noReplaceableSlot
}

/// Pure rules for the user's fixed, ten-slot happening palette.
enum HappeningPaletteSelection {
    static let slotCount = 10

    /// The chooser and saved palette share known imported equivalents.
    /// Catalog records, history and use counts stay intact.
    /// Equal titles alone are never evidence that two user happenings are one.
    static func alternatives(catalog: [Happening], selected: [String], query: String = "") -> [Happening] {
        let selectedChoices = Set(selected.map(choiceID))
        let groups = Dictionary(grouping: catalog) { choiceID($0.id) }
        let search = query.trimmingCharacters(in: .whitespacesAndNewlines)
        var seen = Set<String>()

        return catalog.compactMap { happening in
            let key = choiceID(happening.id)
            guard !selectedChoices.contains(key), seen.insert(key).inserted,
                  let members = groups[key] else { return nil }
            // Keep imported titles searchable even when the row uses current copy.
            guard search.isEmpty || members.contains(where: {
                $0.localizedTitle().localizedCaseInsensitiveContains(search)
                    || $0.title.localizedCaseInsensitiveContains(search)
            }) else { return nil }
            return members.first { $0.id == key } ?? happening
        }
    }

    static func choiceID(_ id: String) -> String {
        switch id {
        // 52 is the persisted HKWorkoutActivityType.walking raw value.
        // Other workout types can share a label while being distinct activities.
        case "body_walking", "health_workout_52": "happening_walk"
        default: id
        }
    }

    /// Repairs saved slots using the current built-in for known aliases, then
    /// fills vacancies in default order. Historical catalog records are untouched.
    static func repaired(ids: [String], catalog: [Happening], defaults: [String]) -> [String] {
        let liveIDs = Set(catalog.map(\.id))
        var seen = Set<String>()

        return (ids + defaults + catalog.map(\.id)).reduce(into: []) { repaired, id in
            let key = choiceID(id)
            let currentID = liveIDs.contains(key) ? key : id
            guard repaired.count < slotCount, liveIDs.contains(currentID), seen.insert(key).inserted else {
                return
            }
            repaired.append(currentID)
        }
    }

    /// The least-used visible happening loses its slot. Ties favour the oldest
    /// use, then the earlier current slot so replacement is deterministic.
    static func replacementIndex(
        in ids: [String],
        catalog: [Happening],
        excluding protectedIDs: Set<String> = []
    ) -> Int? {
        let happeningsByID = Dictionary(uniqueKeysWithValues: catalog.map { ($0.id, $0) })

        return ids.indices.filter { !protectedIDs.contains(ids[$0]) }.min { lhs, rhs in
            let left = happeningsByID[ids[lhs]]!
            let right = happeningsByID[ids[rhs]]!
            if left.useCount != right.useCount { return left.useCount < right.useCount }

            let leftLastUsed = left.lastUsedAt ?? .distantPast
            let rightLastUsed = right.lastUsedAt ?? .distantPast
            if leftLastUsed != rightLastUsed { return leftLastUsed < rightLastUsed }
            return lhs < rhs
        }
    }

    static func replacingLeastUsed(
        in ids: [String],
        with id: String,
        catalog: [Happening],
        excluding protectedIDs: Set<String> = []
    ) -> [String]? {
        guard let index = replacementIndex(
            in: ids,
            catalog: catalog,
            excluding: protectedIDs
        ) else {
            return nil
        }
        var replaced = ids
        replaced[index] = id
        return replaced
    }
}

/// Automatic home set; the complete catalog remains available in All.
enum FrequentHappeningSelection {
    static let healthCoreIDs = ["happening_slept_well", "happening_walk", "happening_workout", "happening_did_nothing"]

    static func resolve(catalog: [Happening], previous: [String], healthIDs: [String],
                        protectedIDs: Set<String>, allowsPromotion: Bool) -> [String] {
        let key = HappeningPaletteSelection.choiceID
        let choices = HappeningPaletteSelection.alternatives(catalog: catalog, selected: [])
        let byID = Dictionary(uniqueKeysWithValues: choices.map { (key($0.id), $0) })
        func unique(_ ids: [String]) -> [String] {
            var seen = Set<String>()
            return ids.map(key).filter { byID[$0] != nil && seen.insert($0).inserted }
        }
        let required = Array(unique(healthCoreIDs + healthIDs).prefix(10))
        let protected = Set(protectedIDs.map(key))
        var ids = Array(unique((previous.isEmpty ? required : previous) + required
            + HappeningDefaults.builtIns.map(\.id) + choices.map(\.id)).prefix(10))
        // New Health activities can enter immediately, but never displace an
        // item already on today's canvas. All always retains overflow choices.
        for id in required where !ids.contains(id) {
            guard let slot = ids.indices.reversed().first(where: {
                !required.contains(ids[$0]) && !protected.contains(ids[$0])
            }) else { continue }
            ids[slot] = id
        }
        guard allowsPromotion else { return ids }
        let candidates = choices.filter {
            !ids.contains(key($0.id)) && !$0.id.hasPrefix("health_workout_") && $0.useCount >= 3
        }.sorted {
            if $0.useCount != $1.useCount { return $0.useCount > $1.useCount }
            if $0.lastUsedAt != $1.lastUsedAt { return ($0.lastUsedAt ?? .distantPast) > ($1.lastUsedAt ?? .distantPast) }
            return $0.id < $1.id
        }
        guard let candidate = candidates.first,
              let slot = ids.indices.filter({ !required.contains(ids[$0]) && !protected.contains(ids[$0]) }).min(by: {
                  let lhs = byID[ids[$0]]!, rhs = byID[ids[$1]]!
                  if lhs.useCount != rhs.useCount { return lhs.useCount < rhs.useCount }
                  if lhs.lastUsedAt != rhs.lastUsedAt { return (lhs.lastUsedAt ?? .distantPast) < (rhs.lastUsedAt ?? .distantPast) }
                  return $0 > $1
              }), candidate.useCount >= (byID[ids[slot]]?.useCount ?? 0) + 2 else { return ids }
        ids[slot] = key(candidate.id)
        return ids
    }
}


enum HappeningPaletteMode: String, CaseIterable {
    case frequent
    case all

    var title: String {
        switch self {
        case .frequent: String(localized: "Frequent", comment: "Happening chooser: automatic frequent set")
        case .all: String(localized: "All", comment: "Happening chooser: full catalog")
        }
    }
}
