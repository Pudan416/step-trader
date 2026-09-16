import AppIntents
import WidgetKit

// MARK: - Group Entity (for widget configuration picker)

struct TicketGroupEntity: AppEntity {
    static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "App Group")
    static var defaultQuery = TicketGroupQuery()

    var id: String
    var name: String
    var needsAppName = false

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)", subtitle: needsAppName
            ? "Name this feed in Nowhere using Rename."
            : nil)
    }
}

struct TicketGroupQuery: EntityQuery {
    func entities(for identifiers: [String]) async throws -> [TicketGroupEntity] {
        let all = loadAllGroups()
        return identifiers.compactMap { id in all.first { $0.id == id } }
    }

    func suggestedEntities() async throws -> [TicketGroupEntity] {
        loadAllGroups()
    }

    func defaultResult() async -> TicketGroupEntity? {
        loadAllGroups().first
    }

    func loadAllGroups() -> [TicketGroupEntity] {
        guard let g = UserDefaults(suiteName: SharedKeys.appGroupId) else { return [] }
        let decoded = WidgetGroupOption.loadVisibleFeeds(defaults: g)
        SharedKeys.recordWidgetInteraction("catalog visible=\(decoded.map(\.id)) stored=\(g.data(forKey: SharedKeys.ticketGroups)?.count ?? -1)", source: "widget-groups")
        return decoded.enumerated().map { index, group in
            let display = group.pickerName(index: index)
            return TicketGroupEntity(id: group.id, name: display.title, needsAppName: display.needsAppName)
        }
    }
}

/// Each configuration slot gets a distinct default from the same Feeds list.
/// A shared EntityQuery default alone would choose the first group three times.
struct WidgetGroupOptionsProvider: DynamicOptionsProvider {
    let index: Int

    func results() async throws -> [TicketGroupEntity] {
        TicketGroupQuery().loadAllGroups()
    }

    func defaultResult() async -> TicketGroupEntity? {
        let groups = TicketGroupQuery().loadAllGroups()
        return groups.indices.contains(index) ? groups[index] : nil
    }
}

// MARK: - Widget Configuration Intent

struct SelectGroupIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "Select Groups"
    static var description: IntentDescription = "Choose up to three app groups and a background for this widget."

    @Parameter(title: "App group 1", optionsProvider: WidgetGroupOptionsProvider(index: 0))
    var group1: TicketGroupEntity?

    @Parameter(title: "App group 2", optionsProvider: WidgetGroupOptionsProvider(index: 1))
    var group2: TicketGroupEntity?

    @Parameter(title: "App group 3", optionsProvider: WidgetGroupOptionsProvider(index: 2))
    var group3: TicketGroupEntity?

    @Parameter(title: "Background", default: .appDefault)
    var background: WidgetBackgroundOption

    @Parameter(title: "Wallpaper position", default: .appDefault)
    var wallpaperPosition: WallpaperPositionOption

    init() {}

    static var parameterSummary: some ParameterSummary {
        Summary {
            \.$group1
            \.$group2
            \.$group3
            \.$background
            \.$wallpaperPosition
        }
    }

    var selectedIds: [String] {
        let selected = [group1, group2, group3].compactMap { $0?.id }
        let defaults = selected.isEmpty ? TicketGroupQuery().loadAllGroups().map(\.id) : []
        let resolved = WidgetGroupSelection.resolvedIDs(selected, feedIDs: defaults, limit: WidgetGroupSelection.largeLimit)
        SharedKeys.recordWidgetInteraction("large selected=\(selected) resolved=\(resolved)", source: "widget-groups")
        return resolved
    }
}

// MARK: - Single Group Intent (Combo Medium Widget)

struct SelectSingleGroupIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "Select Group"
    static var description: IntentDescription = "Choose one app group and a background for this widget."

    @Parameter(title: "App Group", optionsProvider: WidgetGroupOptionsProvider(index: 0))
    var group: TicketGroupEntity?

    @Parameter(title: "Background", default: .appDefault)
    var background: WidgetBackgroundOption

    @Parameter(title: "Wallpaper position", default: .appDefault)
    var wallpaperPosition: WallpaperPositionOption

    init() {}

    var selectedId: String? {
        group?.id ?? TicketGroupQuery().loadAllGroups().first?.id
    }
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
