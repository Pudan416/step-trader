import Foundation

/// Owns fixed choices plus historical/imported records needed to resolve saved days.
/// Only selectable exposes choices for new additions.
///
/// Persisted as one JSON blob in the App Group so the widget and extensions can
/// resolve labels. Deliberately not an `ObservableObject` — `AppModel` holds it
/// and republishes, so there is one source of change notifications, not two.
final class HappeningStore {

    private let defaults: UserDefaults

    /// The catalog, in insertion order: built-ins first, then user happenings
    /// and reconstituted orphans in the order they were added.
    private(set) var all: [Happening] = []

    init(defaults: UserDefaults = .nowhere()) {
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

        var metadataChanged = !missing.isEmpty
        let builtInTags = Dictionary(HappeningDefaults.builtIns.map { ($0.id, $0.tags) }, uniquingKeysWith: { first, _ in first })
        for index in all.indices {
            let canonicalTags = all[index].isBuiltIn
                ? builtInTags[all[index].id]
                : HappeningEventTree.tags(forStoredHappeningID: all[index].id)
            if let canonicalTags, !canonicalTags.isEmpty, all[index].tags != canonicalTags {
                all[index].tags = canonicalTags
                metadataChanged = true
            }
        }

        if metadataChanged { persist() }
    }

    func happening(id: String) -> Happening? {
        all.first { $0.id == id }
            ?? HappeningDefaults.legacyBuiltIns.first { $0.id == id }
    }

    /// Authoritative English copy and fixed order, with saved usage attached.
    /// Historical/custom records stay in all but never become extra choices.
    var selectable: [Happening] {
        let groups = Dictionary(grouping: all) { HappeningDefaults.canonicalID($0.id) }
        return HappeningDefaults.builtIns.map { choice in
            var result = choice
            let records = groups[choice.id] ?? []
            result.useCount = records.reduce(0) { $0 + $1.useCount }
            result.lastUsedAt = records.compactMap(\.lastUsedAt).max()
            return result
        }
    }

    /// Compatibility helper for legacy fixtures/import code; no product UI calls it.
    /// New additions and palette edits reject IDs outside the fixed catalog.
    /// Creating a happening only adds it to the catalog. A later successful
    /// daily addition records its first use.
    ///
    /// Duplicate titles are allowed: two happenings that read the same are
    /// still two happenings, and merging them would silently rewrite what the
    /// user typed.
    @discardableResult
    func create(title: String, at date: Date = .now) -> Happening {
        let normalizedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let made = Happening(
            id: "user_\(UUID().uuidString)",
            title: Happening.limitedTitle(normalizedTitle),
            isBuiltIn: false
        )
        all.append(made)
        persist()
        return made
    }

    /// Installs an activity discovered outside the app under a stable id.
    /// Repeated detections reuse the same catalog item instead of creating
    /// duplicate rows for the same HealthKit workout type.
    @discardableResult
    func ensureExternalHappening(id: String, title: String) -> Happening {
        let canonicalTags = HappeningEventTree.tags(forStoredHappeningID: id) ?? []
        if let index = all.firstIndex(where: { $0.id == id }) {
            if !canonicalTags.isEmpty, all[index].tags != canonicalTags {
                all[index].tags = canonicalTags
                persist()
            }
            // Repair older generic Health imports, while leaving deliberate
            // user renames untouched on every later HealthKit refresh.
            if id.hasPrefix("health_workout_"), all[index].title == "Workout", title != "Workout" {
                all[index].title = Happening.limitedTitle(title)
                persist()
            }
            return all[index]
        }

        let made = Happening(id: id, title: title, isBuiltIn: false, tags: canonicalTags)
        all.append(made)
        persist()
        return made
    }

    @discardableResult
    func renameHappening(id: String, title: String) -> Happening? {
        guard let index = all.firstIndex(where: { $0.id == id && !$0.isBuiltIn }) else { return nil }
        let normalizedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedTitle.isEmpty else { return nil }
        all[index].title = Happening.limitedTitle(normalizedTitle)
        persist()
        return all[index]
    }

    func mergeRestored(_ happenings: [Happening]) {
        guard !happenings.isEmpty else { return }
        for source in happenings where !source.isBuiltIn {
            var restored = source
            if let canonicalTags = HappeningEventTree.tags(forStoredHappeningID: restored.id) {
                restored.tags = canonicalTags
            }
            if let index = all.firstIndex(where: { $0.id == restored.id }) {
                all[index] = restored
            } else {
                all.append(restored)
            }
        }
        persist()
    }

    /// Retains usage metadata for future adaptation. Current choices use fixed order.
    func recordUse(id: String, at date: Date = .now) {
        guard let index = all.firstIndex(where: { $0.id == id }) else {
            AppLogger.energy.error("recordUse for unknown happening: \(id, privacy: .public)")
            return
        }
        all[index].recordUse(at: date)
        persist()
    }

    /// Recover retired IDs referenced by saved days as historical records.
    /// They resolve labels but are excluded from selectable choices.
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
