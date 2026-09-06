import Foundation

enum HappeningPaletteSelectionError: Error, Equatable {
    case requiresExactlyTen
    case noReplaceableSlot
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
