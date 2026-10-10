import Foundation
import Combine

/// App-private defaults: no App Group, analytics, cloud or exported metadata.
@MainActor
final class PersonalHappeningProfileStore: ObservableObject {
    @Published private(set) var profile: PersonalHappeningProfile
    private let defaults: UserDefaults
    private let key = "nowhere.personalHappenings.profile.v1"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        profile = defaults.data(forKey: key)
            .flatMap { try? JSONDecoder().decode(PersonalHappeningProfile.self, from: $0) }
            ?? PersonalHappeningProfile()
    }

    func toggleInterest(_ category: HappeningCatalogCategory) {
        guard HappeningCatalogCategory.interests.contains(category) else { return }
        update { value in
            if !value.interests.insert(category.rawValue).inserted {
                value.interests.remove(category.rawValue)
            }
        }
    }

    func setPinned(_ pinned: Bool, id: String) {
        let id = HappeningDefaults.canonicalID(id)
        guard !pinned || HappeningCatalog.byID[id]?.isSelectable == true else { return }
        update {
            if pinned { $0.pinnedIDs.insert(id); $0.hiddenIDs.remove(id) }
            else { $0.pinnedIDs.remove(id) }
        }
    }

    func setHidden(_ hidden: Bool, id: String) {
        let id = HappeningDefaults.canonicalID(id)
        update {
            if hidden { $0.hiddenIDs.insert(id) }
            else { $0.hiddenIDs.remove(id) }
        }
    }

    func setIntention(_ intention: HappeningIntention?, id: String) {
        let id = HappeningDefaults.canonicalID(id)
        guard intention == nil || HappeningCatalog.byID[id]?.isSelectable == true else { return }
        update {
            $0.intentions[id] = intention
            if intention != nil { $0.hiddenIDs.remove(id) }
        }
    }

    func reset(at date: Date = .now) {
        update {
            $0 = PersonalHappeningProfile(historyStartsAt: date,
                historyStartsAfterDayKey: AppModel.dayKey(for: date))
        }
    }

    private func update(_ change: (inout PersonalHappeningProfile) -> Void) {
        var next = profile
        change(&next)
        guard next != profile, let data = try? JSONEncoder().encode(next) else { return }
        defaults.set(data, forKey: key)
        profile = next
    }
}
