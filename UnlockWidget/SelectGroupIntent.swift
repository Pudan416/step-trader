import AppIntents
import WidgetKit

// MARK: - Group Entity (for widget configuration picker)

struct TicketGroupEntity: AppEntity {
    static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "App Group")
    static var defaultQuery = TicketGroupQuery()

    var id: String
    var name: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)")
    }
}

struct TicketGroupQuery: EntityQuery {
    func entities(for identifiers: [String]) async throws -> [TicketGroupEntity] {
        let all = loadAllGroups()
        return all.filter { identifiers.contains($0.id) }
    }

    func suggestedEntities() async throws -> [TicketGroupEntity] {
        loadAllGroups()
    }

    func defaultResult() async -> TicketGroupEntity? {
        nil
    }

    private func loadAllGroups() -> [TicketGroupEntity] {
        guard let g = UserDefaults(suiteName: SharedKeys.appGroupId),
              let data = g.data(forKey: SharedKeys.ticketGroups)
                ?? g.data(forKey: SharedKeys.legacyShieldGroups),
              let decoded = try? JSONDecoder().decode([GroupStub].self, from: data) else {
            return []
        }
        return decoded.map { TicketGroupEntity(id: $0.id, name: $0.name) }
    }

    private struct GroupStub: Decodable {
        let id: String
        let name: String
    }
}

// MARK: - Widget Configuration Intent

struct SelectGroupIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "Select Groups"
    static var description: IntentDescription = "Choose which app groups to display. Medium uses Slot 1. Large uses all four."

    @Parameter(title: "Slot 1")
    var group1: TicketGroupEntity?

    @Parameter(title: "Slot 2")
    var group2: TicketGroupEntity?

    @Parameter(title: "Slot 3")
    var group3: TicketGroupEntity?

    @Parameter(title: "Slot 4")
    var group4: TicketGroupEntity?

    init() {}

    var selectedIds: [String] {
        [group1, group2, group3, group4].compactMap { $0?.id }
    }
}

// MARK: - Single Group Intent (Combo Medium Widget)

struct SelectSingleGroupIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "Select Group"
    static var description: IntentDescription = "Choose one app group to display alongside the energy bar."

    @Parameter(title: "App Group")
    var group: TicketGroupEntity?

    init() {}

    var selectedId: String? { group?.id }
}

// MARK: - Medium Widget Mode

enum MediumWidgetMode: String {
    case stats = "stats"
    case app = "app"
}
