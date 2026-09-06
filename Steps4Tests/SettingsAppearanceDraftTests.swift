import XCTest
@testable import Steps4

final class SettingsAppearanceDraftTests: XCTestCase {
    func testEditingAndDiscardingNeverWritePreferences() {
        let name = "appearance-draft-\(UUID())"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        defaults.set(GradientPalette.warmSunset.rawValue, forKey: SharedKeys.gradientPalette)
        let before = defaults.dictionaryRepresentation()
        var draft = SettingsAppearanceDraft.load(from: defaults)
        draft.palette = GradientPalette.ocean.rawValue
        draft.setAutomatic(true)
        draft.reroll()
        draft.shapes = [.circle]
        draft.fills = [.outline]
        XCTAssertEqual(defaults.dictionaryRepresentation() as NSDictionary, before as NSDictionary)
        XCTAssertEqual(SettingsAppearanceDraft.load(from: defaults).palette, GradientPalette.warmSunset.rawValue)
    }

    func testApplyWritesExactPreviewAndMirrorsSharedPreferences() {
        let name = "appearance-apply-\(UUID())", sharedName = "appearance-shared-\(UUID())"
        let defaults = UserDefaults(suiteName: name)!, shared = UserDefaults(suiteName: sharedName)!
        defer { defaults.removePersistentDomain(forName: name); shared.removePersistentDomain(forName: sharedName) }
        var draft = SettingsAppearanceDraft.load(from: defaults)
        draft.palette = GradientPalette.ocean.rawValue
        draft.setAutomatic(true)
        draft.reroll()
        draft.shapes = [.circle]
        draft.fills = [.outline]
        draft.apply(to: defaults, shared: shared, dayKey: "2026-09-06")
        XCTAssertEqual(defaults.string(forKey: SharedKeys.gradientPalette), draft.palette)
        XCTAssertEqual(shared.string(forKey: SharedKeys.gradientStyle), draft.style)
        XCTAssertEqual(defaults.string(forKey: SharedKeys.dailyRandomThemeLastRolledKey), "2026-09-06")
        XCTAssertEqual(SettingsAppearanceDraft.load(from: defaults), draft)
        draft.setAutomatic(false)
        XCTAssertEqual(draft.palette, GradientPalette.ocean.rawValue)
        draft.apply(to: defaults, shared: shared, dayKey: "2026-09-06")
        XCTAssertNil(defaults.string(forKey: SharedKeys.dailyRandomThemeLastRolledKey))
        XCTAssertEqual(shared.string(forKey: SharedKeys.gradientPalette), GradientPalette.ocean.rawValue)
    }

    func testLegacyShapeMigrationDoesNotWriteDuringPreview() {
        let name = "appearance-migration-\(UUID())"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        defaults.set(CanvasShapeType.blob.rawValue, forKey: SharedKeys.bodyCanvasShape)
        let draft = SettingsAppearanceDraft.load(from: defaults)
        XCTAssertEqual(draft.shapes, [.circle])
        XCTAssertNil(defaults.array(forKey: SharedKeys.allowedCanvasShapes))
    }
}
