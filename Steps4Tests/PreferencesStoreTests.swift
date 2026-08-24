import XCTest
@testable import Steps4

/// Guards the preference key→domain routing centralized in `PreferencesStore`
/// (§M3). The restore path used to hand-route ~25 keys across three UserDefaults
/// suites; a single wrong suite silently broke a restored setting with nothing
/// to catch it. These tests pin each key to the suite it's read back from, so a
/// future mis-route fails CI instead of shipping.
final class PreferencesStoreTests: XCTestCase {

    private var group: UserDefaults!
    private var standard: UserDefaults!
    private var mirror: UserDefaults!
    private let groupName = "test.prefs.group"
    private let standardName = "test.prefs.standard"
    private let mirrorName = "test.prefs.mirror"

    override func setUp() {
        super.setUp()
        group = UserDefaults(suiteName: groupName)
        standard = UserDefaults(suiteName: standardName)
        mirror = UserDefaults(suiteName: mirrorName)
        group.removePersistentDomain(forName: groupName)
        standard.removePersistentDomain(forName: standardName)
        mirror.removePersistentDomain(forName: mirrorName)
    }

    override func tearDown() {
        group.removePersistentDomain(forName: groupName)
        standard.removePersistentDomain(forName: standardName)
        mirror.removePersistentDomain(forName: mirrorName)
        super.tearDown()
    }

    private func sampleScalars() -> PreferencesStore.Scalars {
        PreferencesStore.Scalars(
            stepsTarget: 12345,
            sleepTarget: 7.5,
            restDayOverride: true,
            hasWallpaperShortcut: true,
            wallpaperShortcutUses: 3,
            notifyOneMinBefore: false,
            notifyWhenTimerOver: false,
            notifyCanvasReminder: true,
            canvasReminderHour: 19,
            canvasReminderMinute: 45,
            notifyDayResetWarning: false,
            dayResetWarningHours: 2,
            canvasOverlayStyle: "test-overlay",
            gradientStyle: "test-grad-style",
            gradientPalette: "test-grad-palette",
            userGradientStyle: "test-user-style",
            userGradientPalette: "test-user-palette",
            dailyRandomThemeEnabled: true,
            modernPaletteCategories: ["pastel", "neon"],
            bodyCanvasShape: "test-body",
            mindCanvasShape: "test-mind",
            heartCanvasShape: "test-heart",
            allowedCanvasShapes: ["circle", "rays"]
        )
    }

    /// App-group-suite keys land in `group`, appearance keys land in `standard`,
    /// and the two active-theme keys are mirrored into `mirror`.
    func testApplyScalarsRoutesEachKeyToItsSuite() {
        let s = sampleScalars()
        PreferencesStore.applyScalars(s, group: group, standard: standard, appGroupMirror: mirror)

        // App-group suite.
        XCTAssertEqual(group.double(forKey: SharedKeys.userStepsTarget), 12345)
        XCTAssertEqual(group.double(forKey: SharedKeys.userSleepTarget), 7.5)
        XCTAssertTrue(group.bool(forKey: SharedKeys.restDayOverrideEnabled))
        XCTAssertTrue(group.bool(forKey: PreferencesStore.hasWallpaperShortcutKey))
        XCTAssertEqual(group.integer(forKey: PreferencesStore.wallpaperShortcutUsesKey), 3)
        XCTAssertFalse(group.bool(forKey: SharedKeys.notifyOneMinBefore))
        XCTAssertFalse(group.bool(forKey: SharedKeys.notifyWhenTimerOver))
        XCTAssertTrue(group.bool(forKey: SharedKeys.notifyCanvasReminder))
        XCTAssertEqual(group.integer(forKey: SharedKeys.canvasReminderHour), 19)
        XCTAssertEqual(group.integer(forKey: SharedKeys.canvasReminderMinute), 45)
        XCTAssertFalse(group.bool(forKey: SharedKeys.notifyDayResetWarning))
        XCTAssertEqual(group.integer(forKey: SharedKeys.dayResetWarningHours), 2)
        XCTAssertEqual(group.string(forKey: SharedKeys.canvasOverlayStyle), "test-overlay")

        // Standard suite (appearance).
        XCTAssertEqual(standard.string(forKey: SharedKeys.gradientStyle), "test-grad-style")
        XCTAssertEqual(standard.string(forKey: SharedKeys.gradientPalette), "test-grad-palette")
        XCTAssertEqual(standard.string(forKey: SharedKeys.userGradientStyle), "test-user-style")
        XCTAssertEqual(standard.string(forKey: SharedKeys.userGradientPalette), "test-user-palette")
        XCTAssertTrue(standard.bool(forKey: SharedKeys.dailyRandomThemeEnabled))
        XCTAssertEqual(
            standard.string(forKey: SharedKeys.modernPaletteCategories),
            "pastel,neon"
        )
        XCTAssertEqual(standard.string(forKey: SharedKeys.bodyCanvasShape), "test-body")
        XCTAssertEqual(standard.string(forKey: SharedKeys.mindCanvasShape), "test-mind")
        XCTAssertEqual(standard.string(forKey: SharedKeys.heartCanvasShape), "test-heart")
        XCTAssertEqual(
            standard.stringArray(forKey: SharedKeys.allowedCanvasShapes), ["circle", "rays"]
        )

        // Theme mirror for widgets/extensions.
        XCTAssertEqual(mirror.string(forKey: SharedKeys.gradientStyle), "test-grad-style")
        XCTAssertEqual(mirror.string(forKey: SharedKeys.gradientPalette), "test-grad-palette")
    }

    /// An absent server-side value must not look like a deliberate empty set —
    /// writing `[]` would defeat the seeding path in `allowedByUser`.
    func testApplyScalarsSkipsEmptyAllowedCanvasShapes() {
        standard.set(["snowflake"], forKey: SharedKeys.allowedCanvasShapes)

        var s = sampleScalars()
        s.allowedCanvasShapes = []
        PreferencesStore.applyScalars(s, group: group, standard: standard, appGroupMirror: mirror)

        XCTAssertEqual(
            standard.stringArray(forKey: SharedKeys.allowedCanvasShapes), ["snowflake"],
            "An empty restore must leave the local set alone"
        )
    }

    func testPreferencesRowDefaultsMissingModernCategoriesToAll() throws {
        let data = try XCTUnwrap(#"{"user_id":"person"}"#.data(using: .utf8))
        let row = try JSONDecoder().decode(UserPreferencesRow.self, from: data)

        XCTAssertEqual(
            Set(row.modernPaletteCategories),
            Set(ModernPaletteCategory.allCases.map(\.rawValue))
        )
    }

    func testPreferencesRowDecodesModernCategories() throws {
        let data = try XCTUnwrap(
            #"{"user_id":"person","modern_palette_categories":["pastel","neon"]}"#
                .data(using: .utf8)
        )
        let row = try JSONDecoder().decode(UserPreferencesRow.self, from: data)

        XCTAssertEqual(row.modernPaletteCategories, ["pastel", "neon"])
    }

    func testPreferencePayloadDoesNotDedupeDifferentModernCategories() {
        XCTAssertNotEqual(
            preferencesPayload(categories: ["pastel"]),
            preferencesPayload(categories: ["neon"])
        )
    }

    /// The appearance keys must NOT be written to the app-group suite (only the
    /// two mirrored theme keys are), and app-group-only keys must NOT leak into
    /// `standard`. This is the specific class of mis-route the refactor prevents.
    func testApplyScalarsDoesNotCrossContaminateSuites() {
        let s = sampleScalars()
        PreferencesStore.applyScalars(s, group: group, standard: standard, appGroupMirror: mirror)

        // Appearance keys are not in the app-group suite (except the 2 mirrored).
        XCTAssertNil(group.string(forKey: SharedKeys.userGradientStyle))
        XCTAssertNil(group.string(forKey: SharedKeys.bodyCanvasShape))
        XCTAssertNil(group.stringArray(forKey: SharedKeys.allowedCanvasShapes))
        // App-group-only keys are not in standard.
        XCTAssertNil(standard.string(forKey: SharedKeys.canvasOverlayStyle))
        XCTAssertEqual(standard.double(forKey: SharedKeys.userStepsTarget), 0)
    }

    private func preferencesPayload(
        categories: [String]
    ) -> SupabaseSyncService.UserPreferencesPayload {
        SupabaseSyncService.UserPreferencesPayload(
            stepsTarget: 10_000,
            sleepTarget: 8,
            dayEndHour: 0,
            dayEndMinute: 0,
            restDayOverride: false,
            hasWallpaperShortcut: false,
            wallpaperShortcutUses: 0,
            notifyOneMinBefore: true,
            notifyWhenTimerOver: true,
            notifyCanvasReminder: false,
            canvasReminderHour: 21,
            canvasReminderMinute: 0,
            notifyDayResetWarning: true,
            dayResetWarningHours: 1,
            hasMediumWidget: false,
            hasLargeWidget: false,
            lastOpenedAt: nil,
            gradientStyle: "radial",
            gradientPalette: "warmSunset",
            userGradientStyle: "radial",
            userGradientPalette: "warmSunset",
            dailyRandomThemeEnabled: false,
            modernPaletteCategories: categories,
            canvasOverlayStyle: "smudge",
            allowedCanvasShapes: ["circle"]
        )
    }
}
