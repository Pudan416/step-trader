import Foundation

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
            ids = legacy
        } else {
            ids = HappeningPaletteSelection.repaired(ids: [], catalog: catalog, defaults: defaultIDs)
        }

        defaults.set(ids, forKey: SharedKeys.happeningPaletteSelection)
    }

    func save(_ ids: [String], catalog: [Happening]) throws {
        guard isValidSelection(ids, catalog: catalog) else {
            throw HappeningPaletteSelectionError.requiresExactlyTen
        }

        self.ids = ids
        defaults.set(ids, forKey: SharedKeys.happeningPaletteSelection)
    }

    @discardableResult
    func insertReplacingLeastUsed(_ id: String, catalog: [Happening]) throws -> String {
        guard isValidSelection(ids, catalog: catalog),
              catalog.contains(where: { $0.id == id }),
              !ids.contains(id) else {
            throw HappeningPaletteSelectionError.requiresExactlyTen
        }

        let index = HappeningPaletteSelection.replacementIndex(in: ids, catalog: catalog)
        let removed = ids[index]
        try save(
            HappeningPaletteSelection.replacingLeastUsed(in: ids, with: id, catalog: catalog),
            catalog: catalog
        )
        return removed
    }

    private func isValidSelection(_ ids: [String], catalog: [Happening]) -> Bool {
        let liveIDs = Set(catalog.map(\.id))
        return ids.count == HappeningPaletteSelection.slotCount
            && Set(ids).count == HappeningPaletteSelection.slotCount
            && ids.allSatisfy(liveIDs.contains)
    }
}
