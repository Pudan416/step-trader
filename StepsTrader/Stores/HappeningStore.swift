import Foundation

/// Owns the happening catalog: the ten built-ins plus everything the user has
/// created or carried over from the old 31-option set.
///
/// Persisted as one JSON blob in the App Group so the widget and extensions can
/// resolve labels. Deliberately not an `ObservableObject` — `AppModel` holds it
/// and republishes, so there is one source of change notifications, not two.
final class HappeningStore {

    private let defaults: UserDefaults

    /// The catalog, in insertion order: built-ins first, then user happenings
    /// and reconstituted orphans in the order they were added.
    private(set) var all: [Happening] = []

    init(defaults: UserDefaults = .stepsTrader()) {
        self.defaults = defaults
    }

    /// Loads the catalog, seeding built-ins on first run and topping up any
    /// built-in a previous build did not ship. Existing use counts survive both.
    /// Safe to call more than once.
    func load() {
        var stored: [Happening] = []
        if let data = defaults.data(forKey: SharedKeys.happeningCatalog) {
            do {
                stored = try JSONDecoder().decode([Happening].self, from: data)
            } catch {
                // A corrupt blob must not brick the palette. Reseeding loses
                // use counts, which only affects ordering — recoverable.
                AppLogger.energy.error(
                    "Happening catalog unreadable, reseeding: \(error.localizedDescription)"
                )
            }
        }

        let known = Set(stored.map(\.id))
        let missing = HappeningDefaults.builtIns.filter { !known.contains($0.id) }
        all = stored + missing

        if !missing.isEmpty { persist() }
    }

    func happening(id: String) -> Happening? {
        all.first { $0.id == id }
    }

    /// Creating a happening is itself an addition — the palette's `+` node
    /// spawns its canvas element in the same action, so it starts used.
    ///
    /// Duplicate titles are allowed: two happenings that read the same are
    /// still two happenings, and merging them would silently rewrite what the
    /// user typed.
    @discardableResult
    func create(title: String, at date: Date = .now) -> Happening {
        let made = Happening(
            id: "user_\(UUID().uuidString)",
            title: title.trimmingCharacters(in: .whitespacesAndNewlines),
            isBuiltIn: false,
            useCount: 1,
            lastUsedAt: date
        )
        all.append(made)
        persist()
        return made
    }

    func mergeRestored(_ happenings: [Happening]) {
        guard !happenings.isEmpty else { return }
        for restored in happenings where !restored.isBuiltIn {
            if let index = all.firstIndex(where: { $0.id == restored.id }) {
                all[index] = restored
            } else {
                all.append(restored)
            }
        }
        persist()
    }

    /// Records one addition. Drives palette ordering, so it is stored rather
    /// than derived from history.
    func recordUse(id: String, at date: Date = .now) {
        guard let index = all.firstIndex(where: { $0.id == id }) else {
            AppLogger.energy.error("recordUse for unknown happening: \(id, privacy: .public)")
            return
        }
        all[index].recordUse(at: date)
        persist()
    }

    /// Cutting 31 built-ins to 10 would orphan ids sitting in a user's saved
    /// days, and those days would lose their labels. Bring each one back as a
    /// user happening.
    ///
    /// Idempotent: ids already in the catalog are never touched, so counts
    /// accumulated after an earlier pass survive. Sorted so a launch-time run
    /// over the whole history produces a stable catalog order.
    func reconstituteOrphans(
        fromHistoryIds historyIds: Set<String>,
        titleResolver: (String) -> String
    ) {
        let orphans = historyIds.subtracting(all.map(\.id)).sorted()
        guard !orphans.isEmpty else { return }

        all.append(contentsOf: orphans.map { id in
            Happening(id: id, title: titleResolver(id), isBuiltIn: false)
        })
        AppLogger.energy.info("Reconstituted \(orphans.count) orphaned happening ids")
        persist()
    }

    private func persist() {
        do {
            defaults.set(try JSONEncoder().encode(all), forKey: SharedKeys.happeningCatalog)
        } catch {
            AppLogger.energy.error(
                "Failed to persist happening catalog: \(error.localizedDescription)"
            )
        }
    }
}
