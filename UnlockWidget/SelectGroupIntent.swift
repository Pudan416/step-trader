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
    static var description: IntentDescription = "Choose up to three app groups and a background for this widget."

    @Parameter(title: "App group 1")
    var group1: TicketGroupEntity?

    @Parameter(title: "App group 2")
    var group2: TicketGroupEntity?

    @Parameter(title: "App group 3")
    var group3: TicketGroupEntity?

    @Parameter(title: "Background", default: .appDefault)
    var background: WidgetBackgroundOption

    @Parameter(title: "Wallpaper position", default: .appDefault)
    var wallpaperPosition: WallpaperPositionOption

    init() {}

    var selectedIds: [String] {
        WidgetGroupSelection.largeIDs([group1, group2, group3].compactMap { $0?.id })
    }
}

// MARK: - Single Group Intent (Combo Medium Widget)

struct SelectSingleGroupIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "Select Group"
    static var description: IntentDescription = "Choose one app group and a background for this widget."

    @Parameter(title: "App Group")
    var group: TicketGroupEntity?

    @Parameter(title: "Background", default: .appDefault)
    var background: WidgetBackgroundOption

    @Parameter(title: "Wallpaper position", default: .appDefault)
    var wallpaperPosition: WallpaperPositionOption

    init() {}

    var selectedId: String? { group?.id }
}

// MARK: - Medium Widget Mode

enum MediumWidgetMode: String {
    case stats = "stats"
    case app = "app"
}


enum WallpaperPositionOption: String, AppEnum {
    case appDefault, top, middle, bottom
    static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "Wallpaper position")
    static var caseDisplayRepresentations: [Self: DisplayRepresentation] = [
        .appDefault: "Use app setting", .top: "Top", .middle: "Middle", .bottom: "Bottom"
    ]
    var position: WidgetWallpaperPosition? { WidgetWallpaperPosition(rawValue: rawValue) }
}

struct StatusWidgetIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "Energy Status"
    static var description: IntentDescription = "Choose a background and wallpaper position for this widget."
    @Parameter(title: "Background", default: .appDefault)
    var background: WidgetBackgroundOption

    @Parameter(title: "Wallpaper position", default: .appDefault)
    var wallpaperPosition: WallpaperPositionOption
    init() {}
}

// Glass / Clear is a Home Screen appearance controlled by iOS, not a per-widget option.
extension WidgetBackgroundOption: AppEnum {
    static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "Background")
    static var caseDisplayRepresentations: [Self: DisplayRepresentation] = [
        .appDefault: "App default",
        .basic: "No picture",
        .wallpaper: "Picture inside",
        .aligned: "Continue wallpaper"
    ]
}
