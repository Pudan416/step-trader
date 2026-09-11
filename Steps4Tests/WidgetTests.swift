import XCTest
@testable import Steps4

final class WidgetTests: XCTestCase {

    func testGroupIdentityKeepsCustomNameForPresetApp() {
        let identity = AppGroupIdentity(name: "Evening break", templateApp: "com.burbn.instagram", applicationCount: 1)
        XCTAssertEqual(identity.title, "Evening break")
        XCTAssertEqual(identity.detail, "Instagram")
    }

    func testGroupIdentityShowsActualScopeForCustomGroups() {
        let identity = AppGroupIdentity(name: "Social feeds", templateApp: nil,
                                        applicationCount: 3, categoryCount: 2, webDomainCount: 1)
        XCTAssertEqual(identity.title, "Social feeds")
        XCTAssertEqual(identity.detail, "3 apps · 2 categories · 1 website")
    }

    func testMissingSelectionDoesNotInventOneApp() {
        let identity = AppGroupIdentity(name: "Study", templateApp: nil, selectionData: nil)
        XCTAssertEqual(identity.detail, "App group")
        let corrupt = AppGroupIdentity(name: "Study", templateApp: nil, selectionData: Data("invalid".utf8))
        XCTAssertEqual(corrupt, identity)
    }

    func testBlankPresetNameFallsBackToApplicationName() {
        let identity = AppGroupIdentity(name: "  \n ", templateApp: "com.google.ios.youtube", applicationCount: 0)
        XCTAssertEqual(identity.title, "YouTube")
        XCTAssertEqual(identity.detail, "1 app")
    }

    func testLargeWidgetKeepsOnlyThreeUniqueGroupsInSelectionOrder() {
        XCTAssertEqual(WidgetGroupSelection.largeIDs(["a", "b", "c", "d"]), ["a", "b", "c"])
        XCTAssertEqual(WidgetGroupSelection.largeIDs(["a", "a", "b", "c"]), ["a", "b", "c"])
        XCTAssertEqual(WidgetGroupSelection.largeIDs(["c", "a"]), ["c", "a"])
        XCTAssertEqual(WidgetGroupSelection.largeIDs([]), [])
    }

    @MainActor
    func testWidgetBackgroundChoicesAreIndependentOfEachOtherAndAppDefaults() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let suite = "widget-instance-tests-" + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer {
            try? FileManager.default.removeItem(at: directory)
            defaults.removePersistentDomain(forName: suite)
        }
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let image = UIGraphicsImageRenderer(size: CGSize(width: 400, height: 800), format: format).image { context in
            UIColor.red.setFill(); context.fill(CGRect(x: 0, y: 0, width: 400, height: 400))
            UIColor.blue.setFill(); context.fill(CGRect(x: 0, y: 400, width: 400, height: 400))
        }
        try WidgetWallpaperFile.write(.init(imageData: XCTUnwrap(image.pngData()), screenSize: image.size), to: directory)
        let size = CGSize(width: 340, height: 160)
        defaults.set("basic", forKey: SharedKeys.widgetBackgroundMode)
        let top = try XCTUnwrap(WidgetWallpaperFile.background(widgetSize: size, mode: .aligned, position: .top, defaults: defaults, directory: directory))
        let bottom = try XCTUnwrap(WidgetWallpaperFile.background(widgetSize: size, mode: .aligned, position: .bottom, defaults: defaults, directory: directory))
        XCTAssertEqual(try centerRGB(top), [255, 0, 0])
        XCTAssertEqual(try centerRGB(bottom), [0, 0, 255])
        XCTAssertNotNil(WidgetWallpaperFile.background(widgetSize: size, mode: .wallpaper, defaults: defaults, directory: directory))
        XCTAssertNil(WidgetWallpaperFile.background(widgetSize: size, mode: .appDefault, defaults: defaults, directory: directory))
        XCTAssertEqual(defaults.string(forKey: SharedKeys.widgetBackgroundMode), "basic", "Rendering one instance must never change shared defaults")

        defaults.set("wallpaper", forKey: SharedKeys.widgetBackgroundMode)
        XCTAssertNil(WidgetWallpaperFile.background(widgetSize: size, mode: .basic, defaults: defaults, directory: directory))
        XCTAssertNotNil(WidgetWallpaperFile.background(widgetSize: size, defaults: defaults, directory: directory), "Existing widgets retain the app default")
        XCTAssertEqual(try centerRGB(XCTUnwrap(WidgetWallpaperFile.background(widgetSize: size, mode: .aligned, position: .top, defaults: defaults, directory: directory))), [255, 0, 0])
        XCTAssertEqual(defaults.string(forKey: SharedKeys.widgetBackgroundMode), "wallpaper")
    }

    func testInvalidBackgroundDefaultsFallBackToNoPicture() throws {
        let suite = "widget-mode-tests-" + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        for raw in ["removed-mode", "appDefault", "clear"] {
            defaults.set(raw, forKey: SharedKeys.widgetBackgroundMode)
            XCTAssertEqual(WidgetBackgroundOption.appDefault.resolved(defaults: defaults), .basic)
            XCTAssertEqual(WidgetBackgroundOption.aligned.resolved(defaults: defaults), .aligned)
        }
    }

    // Coordinates deliberately use a simple 400 × 800 screen at 3× scale.
    // These catch using a scaled whole wallpaper instead of a positioned crop.
    func testWallpaperCropPreservesScreenScaleAndPosition() throws {
        let expectedY: [WidgetWallpaperPosition: CGFloat] = [.top: 240, .middle: 840, .bottom: 1440]
        for position in WidgetWallpaperPosition.allCases {
            let rect = try XCTUnwrap(WidgetWallpaperGeometry.cropRect(
                imageSize: CGSize(width: 1200, height: 2400),
                screenSize: CGSize(width: 400, height: 800),
                widgetSize: CGSize(width: 340, height: 160), position: position))
            XCTAssertEqual(rect.origin.x, 90, accuracy: 0.001)
            XCTAssertEqual(rect.origin.y, expectedY[position]!, accuracy: 0.001)
            XCTAssertEqual(rect.width, 1020, accuracy: 0.001)
            XCTAssertEqual(rect.height, 480, accuracy: 0.001)
        }
    }

    func testWallpaperCropUsesCenteredAspectFillAndLargeSize() throws {
        let rect = try XCTUnwrap(WidgetWallpaperGeometry.cropRect(
            imageSize: CGSize(width: 1600, height: 2400),
            screenSize: CGSize(width: 400, height: 800),
            widgetSize: CGSize(width: 340, height: 360), position: .bottom))
        XCTAssertEqual(rect.minX, 290, accuracy: 0.001)
        XCTAssertEqual(rect.minY, 840, accuracy: 0.001)
        XCTAssertEqual(rect.width, 1020, accuracy: 0.001)
        XCTAssertEqual(rect.height, 1080, accuracy: 0.001)
    }

    func testWallpaperCropAppliesCalibration() throws {
        let rect = try XCTUnwrap(WidgetWallpaperGeometry.cropRect(
            imageSize: CGSize(width: 1200, height: 2400),
            screenSize: CGSize(width: 400, height: 800),
            widgetSize: CGSize(width: 340, height: 160), position: .top,
            top: 0.125, bottom: 0.85))
        XCTAssertEqual(rect.minY, 300, accuracy: 0.001)
    }

    func testWallpaperCropRejectsInvalidOrUnsupportedGeometry() {
        for size in [CGSize.zero, CGSize(width: CGFloat.nan, height: 800), CGSize(width: 400, height: -1)] {
            XCTAssertNil(WidgetWallpaperGeometry.cropRect(
                imageSize: CGSize(width: 1200, height: 2400), screenSize: size,
                widgetSize: CGSize(width: 340, height: 160), position: .top))
        }
        XCTAssertNil(WidgetWallpaperGeometry.cropRect(
            imageSize: CGSize(width: 1200, height: 2400), screenSize: CGSize(width: 400, height: 800),
            widgetSize: CGSize(width: 600, height: 160), position: .top))
        XCTAssertNil(WidgetWallpaperGeometry.cropRect(
            imageSize: CGSize(width: 1200, height: 2400), screenSize: CGSize(width: 400, height: 800),
            widgetSize: CGSize(width: 340, height: 160), position: .top, top: .nan))
    }

    @MainActor
    func testWallpaperFileUsesSavedScreenAndPerWidgetOverride() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let suite = "widget-wallpaper-tests-" + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer {
            try? FileManager.default.removeItem(at: directory)
            defaults.removePersistentDomain(forName: suite)
        }
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let image = UIGraphicsImageRenderer(size: CGSize(width: 400, height: 800), format: format).image { context in
            UIColor.red.setFill(); context.fill(CGRect(x: 0, y: 0, width: 400, height: 240))
            UIColor.green.setFill(); context.fill(CGRect(x: 0, y: 240, width: 400, height: 240))
            UIColor.blue.setFill(); context.fill(CGRect(x: 0, y: 480, width: 400, height: 320))
        }
        let data = try XCTUnwrap(image.pngData())
        try WidgetWallpaperFile.write(.init(imageData: data, screenSize: CGSize(width: 400, height: 800)), to: directory)
        XCTAssertEqual(WidgetWallpaperFile.read(from: directory)?.imageData, data)
        defaults.set("aligned", forKey: SharedKeys.widgetBackgroundMode)
        defaults.set("bottom", forKey: SharedKeys.widgetWallpaperPosition)
        let bottom = try XCTUnwrap(WidgetWallpaperFile.background(widgetSize: CGSize(width: 340, height: 160),
                                                                 defaults: defaults, directory: directory))
        XCTAssertEqual(bottom.size, CGSize(width: 340, height: 160))
        XCTAssertEqual(try centerRGB(bottom), [0, 0, 255])
        let top = try XCTUnwrap(WidgetWallpaperFile.background(widgetSize: CGSize(width: 340, height: 160),
                                                              position: .top, defaults: defaults, directory: directory))
        XCTAssertEqual(try centerRGB(top), [255, 0, 0], "One widget must not inherit another widget's selected position")
        defaults.set("basic", forKey: SharedKeys.widgetBackgroundMode)
        XCTAssertNil(WidgetWallpaperFile.background(widgetSize: CGSize(width: 340, height: 160),
                                                    defaults: defaults, directory: directory))
    }

    @MainActor
    func testLegacyWallpaperIsAvailableButDoesNotPretendToBeAligned() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let suite = "widget-wallpaper-legacy-" + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer {
            try? FileManager.default.removeItem(at: directory)
            defaults.removePersistentDomain(forName: suite)
        }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let image = UIGraphicsImageRenderer(size: CGSize(width: 40, height: 80)).image { context in
            UIColor.blue.setFill(); context.fill(CGRect(x: 0, y: 0, width: 40, height: 80))
        }
        try XCTUnwrap(image.jpegData(compressionQuality: 1)).write(to: directory.appendingPathComponent("wallpaper_bg.jpg"))
        defaults.set("wallpaper", forKey: SharedKeys.widgetBackgroundMode)
        XCTAssertNotNil(WidgetWallpaperFile.background(widgetSize: CGSize(width: 340, height: 160), defaults: defaults, directory: directory))
        defaults.set("aligned", forKey: SharedKeys.widgetBackgroundMode)
        XCTAssertNil(WidgetWallpaperFile.background(widgetSize: CGSize(width: 340, height: 160), defaults: defaults, directory: directory))
        try WidgetWallpaperFile.write(.init(imageData: Data([0, 1, 2]), screenSize: CGSize(width: 400, height: 800)), to: directory)
        XCTAssertNil(WidgetWallpaperFile.background(widgetSize: CGSize(width: 340, height: 160), defaults: defaults, directory: directory))
    }

    private func centerRGB(_ image: UIImage) throws -> [UInt8] {
        let cgImage = try XCTUnwrap(image.cgImage)
        let pixel = try XCTUnwrap(cgImage.cropping(to: CGRect(x: cgImage.width / 2, y: cgImage.height / 2, width: 1, height: 1)))
        var bytes = [UInt8](repeating: 0, count: 4)
        try bytes.withUnsafeMutableBytes { buffer in
            let context = try XCTUnwrap(CGContext(data: buffer.baseAddress, width: 1, height: 1,
                                                 bitsPerComponent: 8, bytesPerRow: 4,
                                                 space: CGColorSpaceCreateDeviceRGB(),
                                                 bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue))
            context.draw(pixel, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        }
        return Array(bytes.prefix(3))
    }

    // MARK: - WidgetSnapshot encoding/decoding

    func testWidgetSnapshot_roundTrip() throws {
        let now = Date()
        let snap = WidgetSnapshot(
            balance: 42, earned: 60,
            stepsPoints: 15, sleepPoints: 20,
            bodyPoints: 5, mindPoints: 3, heartPoints: 2,
            timestamp: now
        )
        let data = try JSONEncoder().encode(snap)
        let decoded = try JSONDecoder().decode(WidgetSnapshot.self, from: data)

        XCTAssertEqual(decoded.balance, 42)
        XCTAssertEqual(decoded.earned, 60)
        XCTAssertEqual(decoded.stepsPoints, 15)
        XCTAssertEqual(decoded.sleepPoints, 20)
        XCTAssertEqual(decoded.bodyPoints, 5)
        XCTAssertEqual(decoded.mindPoints, 3)
        XCTAssertEqual(decoded.heartPoints, 2)
        XCTAssertEqual(decoded.timestamp.timeIntervalSince1970,
                       now.timeIntervalSince1970, accuracy: 0.001)
    }

    func testWidgetSnapshot_zeroState() throws {
        let snap = WidgetSnapshot(
            balance: 0, earned: 0,
            stepsPoints: 0, sleepPoints: 0,
            bodyPoints: 0, mindPoints: 0, heartPoints: 0,
            timestamp: Date()
        )
        let data = try JSONEncoder().encode(snap)
        let decoded = try JSONDecoder().decode(WidgetSnapshot.self, from: data)
        XCTAssertEqual(decoded.balance, 0)
        XCTAssertEqual(decoded.earned, 0)
    }

    func testWidgetSnapshot_totalPoints() {
        let snap = WidgetSnapshot(
            balance: 80, earned: 80,
            stepsPoints: 30, sleepPoints: 25,
            bodyPoints: 10, mindPoints: 8, heartPoints: 7,
            timestamp: Date()
        )
        let total = snap.stepsPoints + snap.sleepPoints + snap.bodyPoints + snap.mindPoints + snap.heartPoints
        XCTAssertEqual(total, 80)
    }

    // MARK: - AccessWindow

    func testAccessWindow_allCases() {
        let all = AccessWindow.allCases
        XCTAssertEqual(all.count, 3)
        XCTAssertTrue(all.contains(.minutes10))
        XCTAssertTrue(all.contains(.minutes30))
        XCTAssertTrue(all.contains(.hour1))
    }

    func testAccessWindow_minutes() {
        XCTAssertEqual(AccessWindow.minutes10.minutes, 10)
        XCTAssertEqual(AccessWindow.minutes30.minutes, 30)
        XCTAssertEqual(AccessWindow.hour1.minutes, 60)
    }

    func testAccessWindow_rawValueRoundTrip() {
        for window in AccessWindow.allCases {
            XCTAssertEqual(AccessWindow(rawValue: window.rawValue), window)
        }
    }

    func testAccessWindow_displayName() {
        XCTAssertEqual(AccessWindow.minutes10.displayName, "10 min")
        XCTAssertEqual(AccessWindow.minutes30.displayName, "30 min")
        XCTAssertEqual(AccessWindow.hour1.displayName, "1 hour")
    }

    func testAccessWindow_spendColorsLabel() {
        XCTAssertTrue(AccessWindow.minutes10.spendColorsLabel.contains("10 min"))
        XCTAssertTrue(AccessWindow.minutes30.spendColorsLabel.contains("30 min"))
        XCTAssertTrue(AccessWindow.hour1.spendColorsLabel.contains("1 hour"))
    }

    func testAccessWindow_codableRoundTrip() throws {
        for window in AccessWindow.allCases {
            let data = try JSONEncoder().encode(window)
            let decoded = try JSONDecoder().decode(AccessWindow.self, from: data)
            XCTAssertEqual(decoded, window)
        }
    }

    // MARK: - SharedKeys widget-related constants

    func testSharedKeys_widgetKeysAreNonEmpty() {
        XCTAssertFalse(SharedKeys.appGroupId.isEmpty)
        XCTAssertFalse(SharedKeys.ticketGroups.isEmpty)
        XCTAssertFalse(SharedKeys.widgetBackgroundMode.isEmpty)
        XCTAssertFalse(SharedKeys.hasMediumWidget.isEmpty)
        XCTAssertFalse(SharedKeys.hasLargeWidget.isEmpty)
    }

    func testSharedKeys_usageBudgetKeyFormat() {
        let key = SharedKeys.usageBudgetKey("group123")
        XCTAssertTrue(key.contains("group123"))

        let initialKey = SharedKeys.usageBudgetInitialKey("group123")
        XCTAssertTrue(initialKey.contains("group123"))
        XCTAssertNotEqual(key, initialKey,
                          "Budget key and initial key should differ")
    }

    func testSharedKeys_usageBudgetKeyUniqueness() {
        let key1 = SharedKeys.usageBudgetKey("a")
        let key2 = SharedKeys.usageBudgetKey("b")
        XCTAssertNotEqual(key1, key2)
    }

    // MARK: - DayBoundary (used by widget timeline providers)

    func testDayBoundary_sameDayReturnsSameStart() {
        let now = Date()
        let start1 = DayBoundary.currentDayStart(for: now, dayEndHour: 0, dayEndMinute: 0)
        let start2 = DayBoundary.currentDayStart(for: now, dayEndHour: 0, dayEndMinute: 0)
        XCTAssertEqual(start1, start2)
    }

    func testDayBoundary_isPersistedDayBehind_nilAnchor() {
        let stale = DayBoundary.isPersistedDayBehind(
            anchor: nil, relativeTo: Date(),
            dayEndHour: 0, dayEndMinute: 0
        )
        XCTAssertFalse(stale, "nil anchor is treated as not-behind (no data yet)")
    }

    func testDayBoundary_isPersistedDayBehind_sameDay() {
        let now = Date()
        let anchor = DayBoundary.currentDayStart(for: now, dayEndHour: 0, dayEndMinute: 0)
        let stale = DayBoundary.isPersistedDayBehind(
            anchor: anchor, relativeTo: now,
            dayEndHour: 0, dayEndMinute: 0
        )
        XCTAssertFalse(stale, "Same-day anchor should not be stale")
    }

    func testDayBoundary_isPersistedDayBehind_yesterday() {
        let now = Date()
        let yesterday = Calendar.current.date(byAdding: .day, value: -1,
                                              to: Calendar.current.startOfDay(for: now))!
        let stale = DayBoundary.isPersistedDayBehind(
            anchor: yesterday, relativeTo: now,
            dayEndHour: 0, dayEndMinute: 0
        )
        XCTAssertTrue(stale, "Yesterday's anchor should be stale")
    }

    // MARK: - WidgetDataFile write/read round-trip

    func testWidgetDataFile_writeAndRead() throws {
        let snap = WidgetSnapshot(
            balance: 77, earned: 88,
            stepsPoints: 30, sleepPoints: 20,
            bodyPoints: 10, mindPoints: 5, heartPoints: 3,
            timestamp: Date()
        )
        WidgetDataFile.write(snap)
        let read = WidgetDataFile.read()

        // May be nil if app group container isn't available in test host,
        // but if it reads, values should match.
        if let read {
            XCTAssertEqual(read.balance, 77)
            XCTAssertEqual(read.earned, 88)
        }
    }
}

/// Guards the build setting that silently deleted the whole blocking mechanic.
///
/// An app extension whose deployment target is higher than its host app's is not
/// installed at all on systems below that floor — no error, no crash, the feature is
/// simply absent. Xcode rewrites `IPHONEOS_DEPLOYMENT_TARGET` whenever a target is
/// edited, and it had done exactly that twice: `ShieldConfiguration`, `ShieldAction` and
/// `UnlockWidgetExtension` sat at 26.1 and `DeviceActivityMonitor` at 18.5 while the app
/// shipped to 17. Below those versions there was no shield UI, no shield buttons, no
/// widget and no budget ticks — for an app whose entire purpose is blocking.
///
/// It lives beside the widget tests because the missing widget is the most visible
/// symptom, but it covers every embedded extension.
final class ExtensionDeploymentTargetTests: XCTestCase {

    func testNoExtensionRequiresANewerOSThanTheHostApp() throws {
        let host = Bundle.main
        let appMinimum = try XCTUnwrap(
            host.object(forInfoDictionaryKey: "MinimumOSVersion") as? String,
            "host app has no MinimumOSVersion"
        )

        let pluginsURL = try XCTUnwrap(host.builtInPlugInsURL, "host app has no PlugIns directory")
        let appexes = ((try? FileManager.default.contentsOfDirectory(
            at: pluginsURL, includingPropertiesForKeys: nil
        )) ?? []).filter { $0.pathExtension == "appex" }

        // Without this the whole check would pass vacuously if the layout ever changes.
        XCTAssertFalse(appexes.isEmpty, "found no embedded extensions to check")

        for url in appexes {
            let name = url.lastPathComponent
            let bundle = try XCTUnwrap(Bundle(url: url), "\(name) is not a readable bundle")
            let minimum = try XCTUnwrap(
                bundle.object(forInfoDictionaryKey: "MinimumOSVersion") as? String,
                "\(name) has no MinimumOSVersion"
            )

            XCTAssertFalse(
                minimum.compare(appMinimum, options: .numeric) == .orderedDescending,
                "\(name) requires iOS \(minimum) but the app ships to iOS \(appMinimum) — "
                + "it will be silently missing on every system below \(minimum)"
            )
        }
    }
}
