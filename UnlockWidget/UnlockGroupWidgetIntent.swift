import AppIntents
import WidgetKit
#if canImport(FamilyControls)
import FamilyControls
#endif

// MARK: - Manual Refresh Intent

struct RefreshWidgetIntent: AppIntent {
    static var title: LocalizedStringResource = "Refresh Widget"
    static var description: IntentDescription = "Force-refresh widget data."
    static var isDiscoverable: Bool = false

    func perform() async throws -> some IntentResult {
        UserDefaults(suiteName: SharedKeys.appGroupId)?.synchronize()
        WidgetKind.reloadAllKinds()
        return .result()
    }
}

// MARK: - Unlock Intent

/// Compatibility entry for already-rendered widgets from older builds. Refresh
/// their timeline so the next tap uses the foreground purchase link. Never buy
/// inside the extension: its process-local authorization starts notDetermined.
struct UnlockGroupWidgetIntent: AppIntent {
    static var title: LocalizedStringResource = "Unlock App Group"
    static var isDiscoverable: Bool = false
    @Parameter(title: "Group ID") var groupId: String
    @Parameter(title: "Window") var windowRaw: String

    func perform() async throws -> some IntentResult {
        SharedKeys.recordWidgetInteraction("legacy unlock action: refreshing widget", source: "extension")
        WidgetKind.reloadAllKinds()
        return .result()
    }
}
