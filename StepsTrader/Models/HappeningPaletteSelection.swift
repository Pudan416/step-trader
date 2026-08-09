import Foundation

enum HappeningPaletteSelectionError: Error, Equatable {
    case requiresExactlyTen
}

/// Pure rules for the user's fixed, ten-slot happening palette.
enum HappeningPaletteSelection {
    static let slotCount = 10

    /// Removes deleted and duplicate ids, then fills empty slots in a stable
    /// order: the supplied defaults first, followed by the catalog source order.
    static func repaired(ids: [String], catalog: [Happening], defaults: [String]) -> [String] {
        let liveIDs = Set(catalog.map(\.id))
        var seen = Set<String>()

        return (ids + defaults + catalog.map(\.id)).reduce(into: []) { repaired, id in
            guard repaired.count < slotCount, liveIDs.contains(id), seen.insert(id).inserted else {
                return
            }
            repaired.append(id)
        }
    }

    /// The least-used visible happening loses its slot. Ties favour the oldest
    /// use, then the earlier current slot so replacement is deterministic.
    static func replacementIndex(in ids: [String], catalog: [Happening]) -> Int {
        precondition(!ids.isEmpty)
        let happeningsByID = Dictionary(uniqueKeysWithValues: catalog.map { ($0.id, $0) })

        return ids.indices.min { lhs, rhs in
            let left = happeningsByID[ids[lhs]]!
            let right = happeningsByID[ids[rhs]]!
            if left.useCount != right.useCount { return left.useCount < right.useCount }

            let leftLastUsed = left.lastUsedAt ?? .distantPast
            let rightLastUsed = right.lastUsedAt ?? .distantPast
            if leftLastUsed != rightLastUsed { return leftLastUsed < rightLastUsed }
            return lhs < rhs
        }!
    }

    static func replacingLeastUsed(in ids: [String], with id: String, catalog: [Happening]) -> [String] {
        var replaced = ids
        replaced[replacementIndex(in: ids, catalog: catalog)] = id
        return replaced
    }
}

/// Transitional, non-persisting compatibility surface for Task 2's pending
/// AppModel migration. The v1 frozen order is neither read nor written here.
final class HappeningPaletteOrderCache {
    func order(for dayKey: String, happenings: [Happening]) -> [String] {
        Array(happenings.prefix(HappeningPaletteSelection.slotCount).map(\.id))
    }

    func append(id: String, dayKey: String) {}
}
