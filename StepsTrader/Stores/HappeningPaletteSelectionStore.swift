import Foundation

enum HappeningPaletteSelectionDraftToggleResult: Equatable {
    case added
    case removed
    case limitReached
    case unavailable
}

/// In-memory selection edits for the chooser. Persistence is intentionally
/// deferred until the enclosing panel's Done action calls the store's `save`.
struct HappeningPaletteSelectionDraft {
    private let originalIDs: [String]
    private let liveIDs: Set<String>

    private(set) var ids: [String]

    init(selected: [String], catalog: [Happening]) {
        originalIDs = selected
        ids = selected
        liveIDs = Set(catalog.map(\.id))
    }

    var canSave: Bool {
        ids.count == HappeningPaletteSelection.slotCount
            && Set(ids).count == HappeningPaletteSelection.slotCount
            && ids.allSatisfy(liveIDs.contains)
    }

    mutating func toggle(id: String) -> HappeningPaletteSelectionDraftToggleResult {
        guard liveIDs.contains(id) else { return .unavailable }

        if let index = ids.firstIndex(of: id) {
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
