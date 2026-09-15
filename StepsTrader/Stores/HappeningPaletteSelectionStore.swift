import Foundation

enum HappeningPaletteSelectionDraftToggleResult: Equatable {
    case added
    case removed
    case protected
    case limitReached
    case unavailable
}

/// In-memory selection edits for the chooser. Persistence is intentionally
/// deferred until the enclosing panel's Done action calls the store's `save`.
struct HappeningPaletteSelectionDraft {
    private let originalIDs: [String]
    private let liveIDs: Set<String>
    private let protectedIDs: Set<String>

    private(set) var ids: [String]

    init(selected: [String], catalog: [Happening], protectedIDs: Set<String> = []) {
        originalIDs = selected
        ids = selected
        liveIDs = Set(catalog.map(\.id))
        self.protectedIDs = protectedIDs
    }

    var canSave: Bool {
        ids.count == HappeningPaletteSelection.slotCount
            && Set(ids).count == HappeningPaletteSelection.slotCount
            && ids.allSatisfy(liveIDs.contains)
    }

    var hasChanges: Bool { ids != originalIDs }

    /// A replacement preserves slot order and count, and cannot evict a Canvas item.
    @discardableResult
    mutating func replace(id: String, with replacementID: String) -> Bool {
        guard let index = ids.firstIndex(of: id),
              !protectedIDs.contains(id), liveIDs.contains(replacementID),
              !ids.contains(replacementID) else { return false }
        ids[index] = replacementID
        return true
    }

    mutating func toggle(id: String) -> HappeningPaletteSelectionDraftToggleResult {
        guard liveIDs.contains(id) else { return .unavailable }

        if let index = ids.firstIndex(of: id) {
            guard !protectedIDs.contains(id) else { return .protected }
            ids.remove(at: index)
            return .removed
        }

        guard ids.count < HappeningPaletteSelection.slotCount else { return .limitReached }
        ids.append(id)
        return .added
    }

    mutating func cancel() {
        ids = originalIDs
    }
}

final class HappeningPaletteSelectionStore {
    private let defaults: UserDefaults
    private(set) var ids: [String] = []

    init(defaults: UserDefaults = .stepsTrader()) {
        self.defaults = defaults
    }

    func load(catalog: [Happening]) {
        let defaultIDs = HappeningDefaults.builtIns.map(\.id)

        if let saved = defaults.stringArray(forKey: SharedKeys.happeningPaletteSelection) {
            ids = HappeningPaletteSelection.repaired(ids: saved, catalog: catalog, defaults: defaultIDs)
        } else if let legacy = defaults.stringArray(forKey: SharedKeys.legacyHappeningPaletteOrderIds),
                  isValidSelection(legacy, catalog: catalog) {
            ids = HappeningPaletteSelection.repaired(ids: legacy, catalog: catalog, defaults: defaultIDs)
        } else {
            ids = HappeningPaletteSelection.repaired(ids: [], catalog: catalog, defaults: defaultIDs)
        }

        defaults.set(ids, forKey: SharedKeys.happeningPaletteSelection)
    }

    func save(_ ids: [String], catalog: [Happening]) throws {
        guard isValidSelection(ids, catalog: catalog),
              Set(ids.map(HappeningPaletteSelection.choiceID)).count == ids.count else {
            throw HappeningPaletteSelectionError.requiresExactlyTen
        }

        self.ids = HappeningPaletteSelection.repaired(ids: ids, catalog: catalog, defaults: [])
        defaults.set(self.ids, forKey: SharedKeys.happeningPaletteSelection)
    }

    @discardableResult
    func insertReplacingLeastUsed(
        _ id: String,
        catalog: [Happening],
        excluding protectedIDs: Set<String> = []
    ) throws -> String {
        guard isValidSelection(ids, catalog: catalog),
              catalog.contains(where: { $0.id == id }),
              !ids.contains(id) else {
            throw HappeningPaletteSelectionError.requiresExactlyTen
        }

        guard let index = HappeningPaletteSelection.replacementIndex(
            in: ids,
            catalog: catalog,
            excluding: protectedIDs
        ) else {
            throw HappeningPaletteSelectionError.noReplaceableSlot
        }
        let removed = ids[index]
        var replacement = ids
        replacement[index] = id
        try save(replacement, catalog: catalog)
        return removed
    }

    private func isValidSelection(_ ids: [String], catalog: [Happening]) -> Bool {
        let liveIDs = Set(catalog.map(\.id))
        return ids.count == HappeningPaletteSelection.slotCount
            && Set(ids).count == HappeningPaletteSelection.slotCount
            && ids.allSatisfy(liveIDs.contains)
    }
}


/// A stable automatic home set. Only a day boundary permits a learned swap.
/// The optional editor can save an explicit selection into the same home set.
final class FrequentHappeningStore {
    private struct Snapshot: Codable, Equatable {
        let dayKey: String
        let ids: [String]
    }
    private let defaults: UserDefaults
    private var snapshot: Snapshot?

    init(defaults: UserDefaults = .stepsTrader()) {
        self.defaults = defaults
        snapshot = defaults.data(forKey: SharedKeys.happeningFrequentPalette).flatMap {
            try? JSONDecoder().decode(Snapshot.self, from: $0)
        }
    }

    func resolve(catalog: [Happening], healthIDs: [String], protectedIDs: Set<String>, dayKey: String, seedIDs: [String] = []) -> [String] {
        let ids = FrequentHappeningSelection.resolve(catalog: catalog, previous: snapshot?.ids ?? seedIDs,
            healthIDs: healthIDs, protectedIDs: protectedIDs, allowsPromotion: snapshot?.dayKey != dayKey)
        let next = Snapshot(dayKey: dayKey, ids: ids)
        if next != snapshot {
            snapshot = next
            if let data = try? JSONEncoder().encode(next) {
                defaults.set(data, forKey: SharedKeys.happeningFrequentPalette)
            }
        }
        return ids
    }
    func saveExplicitSelection(_ ids: [String], dayKey: String) {
        snapshot = Snapshot(dayKey: dayKey, ids: ids)
        if let data = try? JSONEncoder().encode(snapshot) {
            defaults.set(data, forKey: SharedKeys.happeningFrequentPalette)
        }
    }

}
