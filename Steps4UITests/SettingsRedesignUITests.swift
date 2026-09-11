import XCTest

final class SettingsRedesignUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    private func reveal(_ element: XCUIElement, in app: XCUIApplication) {
        for _ in 0..<8 {
            if element.exists && element.isHittable && element.frame.midY < app.frame.maxY - 110 { return }
            let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.65))
            let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.4))
            if element.exists && element.frame.midY < app.frame.minY + 150 {
                end.press(forDuration: 0.1, thenDragTo: start)
            } else {
                start.press(forDuration: 0.1, thenDragTo: end)
            }
        }
        if !(element.exists && element.isHittable) {
            capture(app, name: "Unreachable control")
            print(app.debugDescription)
        }
        XCTAssertTrue(element.exists && element.isHittable)
    }

    private func capture(_ app: XCUIApplication, name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testCombinedDailyAccentScreensAndRotation() {
        XCUIDevice.shared.orientation = .portrait
        defer { XCUIDevice.shared.orientation = .portrait }
        let app = launchSettings(extraArguments: ["ui-testing-me-static-poster"])
        capture(app, name: "Daily palette · Settings")
        openSettingsDestination("settings.destination.appearance", in: app)
        capture(app, name: "Daily palette · Appearance")
        app.navigationBars.buttons.element(boundBy: 0).tap()
        app.buttons["settings.close"].tap()
        app.buttons["tab_feeds"].tap()
        capture(app, name: "Daily palette · Feeds")
        app.buttons["tab_me"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["me_poster_carousel"].waitForExistence(timeout: 5))
        capture(app, name: "Daily palette · Me")
        app.buttons["tab_canvas"].tap()
        app.buttons["canvas_sound_button"].tap()
        let close = app.buttons["canvas_close_fullscreen_button"]
        XCTAssertTrue(close.waitForExistence(timeout: 5))
        capture(app, name: "Daily palette · Play full screen")
        XCUIDevice.shared.orientation = .landscapeLeft
        let rotated = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in app.frame.width > app.frame.height }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [rotated], timeout: 8), .completed)
        capture(app, name: "Combined Canvas · Landscape")
        XCUIDevice.shared.orientation = .portrait
        XCTAssertTrue(close.waitForExistence(timeout: 8))
        close.tap()
        XCTAssertTrue(app.buttons["canvas_add_button"].waitForExistence(timeout: 5))
    }

    func testAppearanceApplyPersistsAndExactGoalEntryWorks() {
        let app = launchSettings()
        openSettingsDestination("settings.destination.appearance", in: app)
        app.buttons["settings.appearance.style.legacy"].tap()
        reveal(app.buttons["Manual"], in: app)
        app.buttons["Manual"].tap()
        reveal(app.buttons["Linear"], in: app)
        app.buttons["Linear"].tap()
        XCTAssertEqual(app.buttons["Linear"].value as? String, "Selected")
        app.buttons["settings.appearance.apply"].tap()
        app.terminate()
        launchSettings(app, seedSettings: false)
        openSettingsDestination("settings.destination.appearance", in: app)
        reveal(app.buttons["Linear"], in: app)
        XCTAssertEqual(app.buttons["Linear"].value as? String, "Selected")
        app.navigationBars.buttons.element(boundBy: 0).tap()
        app.buttons["settings.yourDay"].tap()
        app.buttons["settings.yourDay.steps.exactValue"].tap()
        let field = app.alerts.textFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 3))
        field.tap()
        if let text = field.value as? String { field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: text.count)) }
        field.typeText("12345")
        app.alerts.buttons["Save"].tap()
        XCTAssertTrue(String(describing: app.otherElements["settings.yourDay.steps.adjustable"].value).contains("12,345"))
    }

    func testLiveCanvasSurvivesRepeatedTabSwitches() {
        let app = launchSettings()
        openSettingsDestination("settings.destination.appearance", in: app)
        app.buttons["settings.appearance.style.editorial"].tap()
        let apply = app.buttons["settings.appearance.apply"]
        if apply.isEnabled { apply.tap() }
        else { app.navigationBars.buttons.element(boundBy: 0).tap() }
        app.buttons["settings.close"].tap()
        for index in 0..<3 {
            app.buttons["tab_feeds"].tap()
            let selected = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
                app.buttons["tab_feeds"].isSelected
            }, object: nil)
            XCTAssertEqual(XCTWaiter.wait(for: [selected], timeout: 5), .completed)
            capture(app, name: "Glass Feeds return \(index)")
            app.buttons["tab_me"].tap()
            XCTAssertTrue(app.descendants(matching: .any)["me_poster_carousel"].waitForExistence(timeout: 3))
            capture(app, name: "Live Me return \(index)")
            app.buttons["tab_canvas"].tap()
            XCTAssertTrue(app.otherElements["dayObjects.canvas"].firstMatch.waitForExistence(timeout: 3))
            capture(app, name: "Live Canvas return \(index)")
        }
    }

    func testDailyCanvasAcrossTabsAndSettings() {
        let app = launchSettings(extraArguments: ["ui-testing-me-static-poster"])
        for style in ["legacy", "editorial"] {
            openSettingsDestination("settings.destination.appearance", in: app)
            app.buttons["settings.appearance.style.\(style)"].tap()
            let apply = app.buttons["settings.appearance.apply"]
            if apply.isEnabled { apply.tap() }
            else { app.navigationBars.buttons.element(boundBy: 0).tap() }
            Thread.sleep(forTimeInterval: 2)
            capture(app, name: "Daily canvas \(style) Settings")
            app.buttons["settings.yourDay"].tap()
            Thread.sleep(forTimeInterval: 1)
            capture(app, name: "Daily canvas \(style) Goals")
            app.navigationBars.buttons.element(boundBy: 0).tap()
            app.buttons["settings.close"].tap()
            Thread.sleep(forTimeInterval: 1)
            capture(app, name: "Daily canvas \(style) Me")
            app.buttons["tab_feeds"].tap()
            Thread.sleep(forTimeInterval: 1)
            capture(app, name: "Daily canvas \(style) Feeds")
            app.buttons["tab_me"].tap()
            app.buttons["me_settings_button"].tap()
            XCTAssertTrue(app.buttons["settings.yourDay"].waitForExistence(timeout: 5))
        }
    }

    func testAppearanceActionsRemainCompactAtAccessibilitySize() {
        let app = launchSettings(contentSizeCategory: "UICTContentSizeCategoryAccessibilityM")
        openSettingsDestination("settings.destination.appearance", in: app)
        let actions = app.otherElements["settings.appearance.actions"]
        XCTAssertTrue(actions.waitForExistence(timeout: 3))
        XCTAssertLessThan(actions.frame.height, app.frame.height / 3)
        XCTAssertTrue(app.buttons["settings.appearance.style.legacy"].isHittable)
        capture(app, name: "Review Appearance accessibility actions")
    }

    func testProfileAndWidgetInstallationScreenshotsInLightMode() {
        let app = launchSettings(contentSizeCategory: "UICTContentSizeCategoryL", appearance: "Light",
                                 extraArguments: ["ui-testing-settings-account"])
        openSettingsDestination("settings.account", in: app)
        app.buttons["settings.account.editProfile"].tap()
        XCTAssertTrue(app.buttons["Save"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["Save"].isHittable)
        capture(app, name: "Review Profile editor Light")
        app.buttons["Cancel"].tap()
        app.navigationBars.buttons.element(boundBy: 0).tap()
        openSettingsDestination("settings.destination.widgets", in: app)
        app.buttons["settings.widgets.install"].tap()
        XCTAssertTrue(app.navigationBars["Add widget"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["Done"].isHittable)
        capture(app, name: "Review Widget install Light")
    }

    func testSettingsDesignScreenshotsInLightAndLargeText() {
        for (size, appearance) in [("UICTContentSizeCategoryL", "Light"), ("UICTContentSizeCategoryAccessibilityM", "Dark")] {
            let app = launchSettings(contentSizeCategory: size, appearance: appearance,
                                     extraArguments: ["ui-testing-settings-account"])
            capture(app, name: "Review Home \(appearance)")
            let destinations = [
                ("settings.account", "Account"), ("settings.yourDay", "Goals & schedule"),
                ("settings.destination.appearance", "Appearance"),
                ("settings.destination.notifications", "Notifications"),
                ("settings.destination.permissions", "Permissions"),
                ("settings.destination.widgets", "Widgets"),
                ("settings.destination.wallpaper", "Wallpaper"),
                ("settings.destination.help", "Help & feedback"),
                ("settings.destination.notes", "Notes from Kosta"),
                ("settings.destination.about", "About"),
                ("settings.destination.developer", "Developer")
            ]
            for (id, title) in destinations {
                openSettingsDestination(id, in: app)
                XCTAssertTrue(app.navigationBars[title].waitForExistence(timeout: 5), title)
                capture(app, name: "Review \(title) \(appearance) top")
                app.swipeUp()
                capture(app, name: "Review \(title) \(appearance) lower")
                if title == "Appearance" {
                    let ingredients = app.buttons["Canvas ingredients"]
                    if ingredients.exists {
                        revealWallpaperControl(ingredients, in: app)
                        ingredients.tap()
                        app.swipeUp()
                        capture(app, name: "Review Canvas ingredients \(appearance)")
                    }
                }
                if title == "Widgets" {
                    let install = app.buttons["settings.widgets.install"]
                    revealWallpaperControl(install, in: app)
                    assertMinimumHitTarget(install)
                    install.tap()
                    XCTAssertTrue(app.navigationBars["Add widget"].waitForExistence(timeout: 3))
                    capture(app, name: "Review Widget install \(appearance)")
                    app.buttons["Done"].tap()
                }
                if title == "Account" {
                    let edit = app.buttons["settings.account.editProfile"]
                    revealWallpaperControl(edit, in: app)
                    edit.tap()
                    XCTAssertTrue(app.buttons["Cancel"].waitForExistence(timeout: 3))
                    capture(app, name: "Review Profile editor \(appearance)")
                    app.buttons["Cancel"].tap()
                }
                if title == "Wallpaper" {
                    let setup = app.buttons["Setup"]
                    revealWallpaperControl(setup, in: app)
                    setup.tap()
                    capture(app, name: "Review Wallpaper instructions \(appearance)")
                }
                app.navigationBars.buttons.element(boundBy: 0).tap()
                XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5))
                if title == "Widgets" { capture(app, name: "Review Home Screen \(appearance)") }
            }
            app.terminate()
        }
    }

    private func launchSettings(extraArguments: [String] = []) -> XCUIApplication {
        launchSettings(
            contentSizeCategory: "UICTContentSizeCategoryL",
            extraArguments: extraArguments
        )
    }

    private func launchSettings(
        contentSizeCategory: String,
        appearance: String? = nil,
        reduceMotion: Bool = false,
        increaseContrast: Bool = false,
        seedSettings: Bool = true,
        extraArguments: [String] = []
    ) -> XCUIApplication {
        let app = XCUIApplication()
        launchSettings(
            app,
            contentSizeCategory: contentSizeCategory,
            appearance: appearance,
            reduceMotion: reduceMotion,
            increaseContrast: increaseContrast,
            seedSettings: seedSettings,
            extraArguments: extraArguments
        )
        return app
    }

    private func launchSettings(
        _ app: XCUIApplication,
        contentSizeCategory: String = "UICTContentSizeCategoryL",
        appearance: String? = nil,
        reduceMotion: Bool = false,
        increaseContrast: Bool = false,
        seedSettings: Bool,
        extraArguments: [String] = []
    ) {
        app.launchArguments = ["ui-testing"]
        if seedSettings {
            app.launchArguments.append("ui-testing-settings")
        }
        app.launchArguments.append(contentsOf: extraArguments)
        app.launchArguments += [
            "-AppleLanguages", "(en)", "-AppleLocale", "en_US",
            "-UIPreferredContentSizeCategoryName", contentSizeCategory,
        ]
        if let appearance {
            app.launchArguments += ["-AppleInterfaceStyle", appearance]
        }
        if reduceMotion {
            app.launchArguments += ["-UIAccessibilityReduceMotionEnabled", "YES"]
        }
        if increaseContrast {
            app.launchArguments += ["-UIAccessibilityDarkerSystemColorsEnabled", "YES"]
        }
        app.launch()
        XCTAssertTrue(app.buttons["tab_me"].waitForExistence(timeout: 10))
        app.buttons["tab_me"].tap()
        XCTAssertTrue(app.buttons["me_settings_button"].waitForExistence(timeout: 5))
        app.buttons["me_settings_button"].coordinate(
            withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)
        ).tap()
        XCTAssertTrue(app.staticTexts["Settings"].waitForExistence(timeout: 5))
    }

    private func launchTicketSettings(
        contentSizeCategory: String = "UICTContentSizeCategoryL",
        appearance: String? = nil,
        reduceMotion: Bool = false,
        increaseContrast: Bool = false
    ) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [
            "ui-testing",
            "ui-testing-ticket-settings",
            "-AppleLanguages", "(en)",
            "-AppleLocale", "en_US",
            "-UIPreferredContentSizeCategoryName", contentSizeCategory,
        ]
        if let appearance {
            app.launchArguments += ["-AppleInterfaceStyle", appearance]
        }
        if reduceMotion {
            app.launchArguments += ["-UIAccessibilityReduceMotionEnabled", "YES"]
        }
        if increaseContrast {
            app.launchArguments += ["-UIAccessibilityDarkerSystemColorsEnabled", "YES"]
        }
        app.launch()

        XCTAssertTrue(app.otherElements["ui-testing-ticket-settings.isolatedRoot"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["tab_feeds"].waitForExistence(timeout: 10))
        app.buttons["tab_feeds"].tap()
        XCTAssertTrue(app.navigationBars["Study"].waitForExistence(timeout: 5))
        return app
    }

    func testYourDayIsAvailableWithoutOpeningLogin() {
        let app = launchSettings()

        let yourDay = app.buttons["settings.yourDay"]
        XCTAssertTrue(yourDay.waitForExistence(timeout: 3))
        yourDay.tap()

        XCTAssertTrue(app.staticTexts["Goals & schedule"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.otherElements["settings.yourDay.steps"].exists)
        XCTAssertTrue(app.otherElements["settings.yourDay.sleep"].exists)
        XCTAssertTrue(app.otherElements["settings.yourDay.boundary"].exists)
        XCTAssertFalse(app.staticTexts["Sign in to continue"].exists)
    }

    func testSettingsUsesVisibleCloseAndSystemBackNavigation() {
        let app = launchSettings()
        let close = app.buttons["settings.close"]
        XCTAssertTrue(close.waitForExistence(timeout: 3))
        assertMinimumHitTarget(close)

        app.buttons["settings.yourDay"].tap()
        XCTAssertTrue(app.navigationBars["Goals & schedule"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.navigationBars.buttons.element(boundBy: 0).isHittable)
    }

    func testAppearanceHorizontalSwipeDoesNotDismissDestination() {
        let app = launchSettings()
        openSettingsDestination("settings.destination.appearance", in: app)
        app.buttons["settings.appearance.style.legacy"].tap()
        reveal(app.buttons["Manual"], in: app)
        app.buttons["Manual"].tap()
        let carousel = app.otherElements["settings.appearance.paletteCarousel"]
        XCTAssertTrue(carousel.waitForExistence(timeout: 3))

        reveal(carousel, in: app)
        let horizon = app.buttons["Horizon"]
        XCTAssertTrue(horizon.exists)
        XCTAssertGreaterThan(horizon.frame.midX, carousel.frame.maxX)
        for _ in 0..<3 where horizon.frame.midX > carousel.frame.maxX {
            carousel.swipeLeft()
        }
        XCTAssertGreaterThanOrEqual(horizon.frame.midX, carousel.frame.minX)
        XCTAssertLessThanOrEqual(horizon.frame.midX, carousel.frame.maxX)
        XCTAssertTrue(horizon.isHittable)
        horizon.tap()
        XCTAssertEqual(horizon.value as? String, "Selected")
        XCTAssertTrue(app.navigationBars["Appearance"].exists)
    }

    func testAppearanceManualChoicesExposeSelectedStateAtAccessibilitySize() {
        let app = launchSettings(contentSizeCategory: "UICTContentSizeCategoryAccessibilityM")
        openSettingsDestination("settings.destination.appearance", in: app)
        app.buttons["settings.appearance.style.legacy"].tap()
        reveal(app.buttons["Manual"], in: app)
        app.buttons["Manual"].tap()
        let selectedPalette = app.buttons["Sunset"]
        reveal(selectedPalette, in: app)
        XCTAssertEqual(selectedPalette.value as? String, "Selected")
    }

    func testNotificationsUsesGroupedDetailSurface() {
        let app = launchSettings()
        app.buttons["settings.destination.notifications"].tap()
        XCTAssertTrue(app.otherElements["settings.detail.background"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.otherElements["settings.notifications.accessWindow"].exists)
    }

    func testAccountIdentityLeadsProfileDetailsWithoutADuplicateGroup() {
        let app = launchSettings(extraArguments: ["ui-testing-settings-account"])
        let account = app.buttons["settings.account"]
        XCTAssertTrue(account.waitForExistence(timeout: 3))
        XCTAssertTrue(waitForLabel("Konstantin Pudan", of: account))
        account.tap()

        let profileHeader = app.otherElements["settings.account.profileHeader"]
        let displayName = app.staticTexts["Konstantin Pudan"]
        let email = app.staticTexts["konstantin@example.com"]
        let editProfile = app.buttons["settings.account.editProfile"]
        let syncSection = app.staticTexts["SYNC"]

        XCTAssertTrue(profileHeader.waitForExistence(timeout: 3))
        XCTAssertTrue(displayName.exists)
        XCTAssertTrue(email.exists)
        XCTAssertTrue(editProfile.exists)
        XCTAssertTrue(syncSection.waitForExistence(timeout: 3))
        XCTAssertFalse(app.staticTexts["PROFILE"].exists)
        XCTAssertLessThan(profileHeader.frame.maxY + 20, syncSection.frame.minY)
        XCTAssertTrue(editProfile.isHittable)
        assertMinimumHitTarget(editProfile)
    }

    func testAccountIdentityKeepsEditorialAlignmentAtAccessibilitySize() {
        let app = launchSettings(
            contentSizeCategory: "UICTContentSizeCategoryAccessibilityM",
            extraArguments: ["ui-testing-settings-account"]
        )
        let account = app.buttons["settings.account"]
        XCTAssertTrue(account.waitForExistence(timeout: 3))
        XCTAssertTrue(waitForLabel("Konstantin Pudan", of: account))
        account.tap()

        let profileHeader = app.otherElements["settings.account.profileHeader"]
        let displayName = app.staticTexts["Konstantin Pudan"]
        let email = app.staticTexts["konstantin@example.com"]
        let editProfile = app.buttons["settings.account.editProfile"]
        let syncSection = app.staticTexts["SYNC"]

        XCTAssertTrue(profileHeader.waitForExistence(timeout: 3))
        XCTAssertTrue(editProfile.waitForExistence(timeout: 3))
        XCTAssertTrue(syncSection.waitForExistence(timeout: 3))
        XCTAssertGreaterThan(editProfile.frame.minY, email.frame.maxY)
        XCTAssertEqual(editProfile.frame.minX, displayName.frame.minX, accuracy: 2)
        XCTAssertLessThan(profileHeader.frame.maxY + 20, syncSection.frame.minY)
        XCTAssertTrue(editProfile.isHittable)
        assertMinimumHitTarget(editProfile)
    }

    func testNotificationSectionLabelsSitAboveTheirCards() {
        let app = launchSettings(extraArguments: ["ui-testing-notifications-denied"])
        app.buttons["settings.destination.notifications"].tap()

        assertSectionLabel(
            "NOTIFICATION ACCESS",
            sitsAbove: app.descendants(matching: .any)["settings.notifications.authorization"],
            in: app
        )
        assertSectionLabel(
            "ACCESS WINDOW",
            sitsAbove: app.descendants(matching: .any)["settings.notifications.accessWindow"],
            in: app
        )
    }

    func testZeroHealthDataDoesNotProduceUrgentWarning() {
        let app = launchSettings(extraArguments: ["ui-testing-health-zero-success"])
        app.buttons["settings.destination.permissions"].tap()
        XCTAssertTrue(app.staticTexts["Connected"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.staticTexts["Health not granted"].exists)
    }

    func testDeletingFeedRequiresConfirmation() {
        let app = launchTicketSettings()

        app.buttons["settings.feed.delete"].tap()
        let confirmation = app.sheets["Delete Study?"]
        XCTAssertTrue(confirmation.waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["Delete Feed"].exists)

        app.otherElements["dismiss popup"].tap()

        XCTAssertFalse(confirmation.waitForExistence(timeout: 3))
        XCTAssertTrue(app.navigationBars["Study"].exists)
    }

    func testConfirmingFeedDeletionRemovesSeededFeed() {
        let app = launchTicketSettings()

        app.buttons["settings.feed.delete"].tap()
        XCTAssertTrue(app.sheets["Delete Study?"].waitForExistence(timeout: 3))
        app.buttons["Delete Feed"].tap()

        let studyNavigation = app.navigationBars["Study"]
        let sheetDismissed = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "exists == false"),
            object: studyNavigation
        )
        XCTAssertEqual(XCTWaiter.wait(for: [sheetDismissed], timeout: 3), .completed)
    }

    func testDeniedNotificationsShowSystemRecoveryAction() {
        let app = launchSettings(extraArguments: ["ui-testing-notifications-denied"])
        app.buttons["settings.destination.notifications"].tap()
        XCTAssertTrue(app.staticTexts["Off in System Settings"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["Open Settings"].exists)
    }

    func testPermissionActionsMeetMinimumTargetsAtDefaultSize() {
        let app = launchSettings(extraArguments: [
            "ui-testing-notifications-denied",
            "ui-testing-permissions-actions",
        ])
        openSettingsDestination("settings.destination.permissions", in: app)

        assertPermissionActionTargets(in: app)
    }

    func testPermissionActionsStackAndMeetMinimumTargetsAtAccessibilitySize() {
        let app = launchSettings(
            contentSizeCategory: "UICTContentSizeCategoryAccessibilityM",
            extraArguments: [
                "ui-testing-notifications-denied",
                "ui-testing-permissions-actions",
            ]
        )
        openSettingsDestination("settings.destination.permissions", in: app)

        assertPermissionActionTargets(in: app)
        let healthAction = app.buttons["settings.permissions.health.action"]
        let healthStatus = app.staticTexts["settings.permissions.health.status"]
        XCTAssertGreaterThan(healthAction.frame.minY, healthStatus.frame.minY)
    }

    func testPermissionFailureRecoveryActionsMeetMinimumTargets() {
        let app = launchSettings(extraArguments: ["ui-testing-permissions-health-error"])
        openSettingsDestination("settings.destination.permissions", in: app)

        let tryAgain = app.buttons["settings.permissions.health.error.tryAgain"]
        XCTAssertTrue(tryAgain.waitForExistence(timeout: 3))
        assertMinimumHitTarget(tryAgain)
        assertMinimumHitTarget(app.buttons["settings.permissions.health.error.openSettings"])
    }

    func testNotificationFailureRecoveryActionsMeetMinimumTargets() {
        let app = launchSettings(extraArguments: [
            "ui-testing-notifications-denied",
            "ui-testing-notifications-error",
        ])
        openSettingsDestination("settings.destination.notifications", in: app)

        let tryAgain = app.buttons["settings.notifications.error.tryAgain"]
        XCTAssertTrue(tryAgain.waitForExistence(timeout: 3))
        assertMinimumHitTarget(tryAgain)
        assertMinimumHitTarget(app.buttons["settings.notifications.error.openSettings"])
    }

    func testGradientPreviewCloseHasNamedMinimumTarget() {
        let app = launchSettings()
        openSettingsDestination("settings.destination.appearance", in: app)
        app.buttons["settings.appearance.style.legacy"].tap()
        let manual = app.buttons["Manual"]
        reveal(manual, in: app); manual.tap()
        let linear = app.buttons["Linear"]
        reveal(linear, in: app); linear.tap()
        let cancel = app.buttons["settings.appearance.cancel"]
        XCTAssertTrue(cancel.waitForExistence(timeout: 3))
        assertMinimumHitTarget(cancel)
        assertMinimumHitTarget(app.buttons["settings.appearance.apply"])
        cancel.tap()
        app.buttons["Discard changes"].tap()
        openSettingsDestination("settings.destination.appearance", in: app)
        app.buttons["settings.appearance.style.legacy"].tap()
        reveal(app.buttons["Manual"], in: app)
        app.buttons["settings.appearance.style.legacy"].tap()
        reveal(app.buttons["Manual"], in: app)
        app.buttons["Manual"].tap()
        let radial = app.buttons["Radial"]
        reveal(radial, in: app)
        XCTAssertEqual(radial.value as? String, "Selected")
    }

    func testNotesRemainUsableAtAccessibilitySize() {
        for (size, name) in [("UICTContentSizeCategoryL", "Light"), ("UICTContentSizeCategoryAccessibilityM", "Dark")] {
            let app = launchSettings(contentSizeCategory: size)
            openSettingsDestination("settings.destination.notes", in: app)
            XCTAssertTrue(app.otherElements["settings.notes.card"].waitForExistence(timeout: 3))
            capture(app, name: "Review Notes from Kosta \(name) top")
            app.swipeUp()
            capture(app, name: "Review Notes from Kosta \(name) lower")
            let allNotes = app.buttons["settings.notes.all"]
            XCTAssertTrue(allNotes.waitForExistence(timeout: 3))
            XCTAssertTrue(allNotes.isHittable)
            assertMinimumHitTarget(allNotes)
            allNotes.tap()
            XCTAssertTrue(app.scrollViews["settings.notes.allList"].waitForExistence(timeout: 3))
            let firstNote = app.buttons["settings.notes.item.about_canvas"]
            XCTAssertTrue(firstNote.waitForExistence(timeout: 3))
            XCTAssertTrue(firstNote.isHittable)
            assertMinimumHitTarget(firstNote)
            let done = app.buttons["settings.notes.done"]
            XCTAssertTrue(done.waitForExistence(timeout: 3))
            XCTAssertTrue(done.isHittable)
            assertMinimumHitTarget(done)
            capture(app, name: "Review Notes list \(name)")
            app.terminate()
        }
    }

    func testYourDayEditorsExposeContextualSemanticsAndMinimumHitTargets() {
        let app = launchSettings()
        app.buttons["settings.yourDay"].tap()
        let steps = app.otherElements["settings.yourDay.steps.adjustable"]
        XCTAssertTrue(steps.waitForExistence(timeout: 3))
        XCTAssertTrue(String(describing: steps.value).contains("10,000"))
        for id in ["settings.yourDay.steps.increment", "settings.yourDay.steps.decrement", "settings.yourDay.steps.exactValue", "settings.yourDay.sleep.increment", "settings.yourDay.sleep.decrement"] {
            let control = app.buttons[id]
            reveal(control, in: app)
            assertMinimumHitTarget(control)
        }
        let picker = app.buttons["settings.yourDay.boundary.picker"]
        reveal(picker, in: app)
        assertMinimumHitTarget(picker)
        capture(app, name: "Goals and schedule")
    }

    func testSignedOutYourDayEditsPersistAcrossOrdinaryRelaunch() {
        let app = launchSettings()
        app.buttons["settings.yourDay"].tap()
        app.buttons["settings.yourDay.steps.increment"].tap()
        app.buttons["settings.yourDay.sleep.increment"].tap()
        let picker = app.buttons["settings.yourDay.boundary.picker"]
        reveal(picker, in: app); picker.tap()
        let wheel = app.pickerWheels.firstMatch
        XCTAssertTrue(wheel.waitForExistence(timeout: 3))
        let initialTime = wheel.value as? String ?? ""
        wheel.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.7)).tap()
        let changed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value != %@", initialTime), object: wheel)
        XCTAssertEqual(XCTWaiter.wait(for: [changed], timeout: 3), .completed)
        let chosenTime = wheel.value as? String ?? ""
        XCTAssertFalse(chosenTime.isEmpty)
        app.buttons["settings.yourDay.boundary.done"].tap()
        // Wait beyond AppModel's 350 ms debounced boundary write.
        let commit = expectation(description: "day boundary stored")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { commit.fulfill() }
        wait(for: [commit], timeout: 1)
        app.terminate()
        launchSettings(app, seedSettings: false)
        app.buttons["settings.yourDay"].tap()
        XCTAssertTrue(String(describing: app.otherElements["settings.yourDay.steps.adjustable"].value).contains("10,500"))
        XCTAssertTrue(String(describing: app.otherElements["settings.yourDay.sleep.adjustable"].value).contains("8.5"))
        let persisted = app.buttons["settings.yourDay.boundary.picker"]
        reveal(persisted, in: app)
        XCTAssertEqual(persisted.value as? String, chosenTime)
    }

    func testCardHomePrioritizesAccountThenYourDay() {
        defer { capture(XCUIApplication(), name: "Settings home") }
        let app = launchSettings()
        let account = app.buttons["settings.account"]
        let yourDay = app.buttons["settings.yourDay"]

        XCTAssertTrue(account.waitForExistence(timeout: 3))
        XCTAssertTrue(yourDay.exists)
        XCTAssertLessThan(account.frame.minY, yourDay.frame.minY)
        XCTAssertGreaterThan(yourDay.frame.height, account.frame.height)

        let appearance = app.buttons["settings.destination.appearance"]
        let notifications = app.buttons["settings.destination.notifications"]
        XCTAssertTrue(appearance.exists)
        XCTAssertTrue(notifications.exists)
        XCTAssertLessThan(appearance.frame.minX, notifications.frame.minX)
        XCTAssertEqual(appearance.frame.minY, notifications.frame.minY, accuracy: 2)

        for id in [
            "settings.destination.appearance",
            "settings.destination.notifications",
            "settings.destination.permissions",
            "settings.destination.widgets",
            "settings.destination.wallpaper",
            "settings.destination.notes",
            "settings.destination.about",
        ] {
            XCTAssertTrue(app.buttons[id].exists, "Missing Settings destination: \(id)")
        }
    }

    func testCompactHomeKeepsTheHierarchyScannable() {
        let app = launchSettings()
        let account = app.buttons["settings.account"]
        let yourDay = app.buttons["settings.yourDay"]
        let appearance = app.buttons["settings.destination.appearance"]
        let appSettingsSection = app.staticTexts["settings.appSettings.section"]

        XCTAssertTrue(account.waitForExistence(timeout: 3))
        XCTAssertTrue(yourDay.exists)
        XCTAssertTrue(appearance.exists)
        XCTAssertTrue(appSettingsSection.exists)

        XCTAssertGreaterThanOrEqual(account.frame.height, 76)
        XCTAssertLessThanOrEqual(account.frame.height, 82)
        XCTAssertGreaterThan(yourDay.frame.height, account.frame.height)
        XCTAssertLessThanOrEqual(yourDay.frame.height, 188)
        XCTAssertLessThanOrEqual(appearance.frame.height, 114)
    }

    func testAccessibilityTypeKeepsDestinationCardsReadable() {
        let app = launchSettings(contentSizeCategory: "UICTContentSizeCategoryAccessibilityM")
        let appearance = app.buttons["settings.destination.appearance"]
        let notifications = app.buttons["settings.destination.notifications"]

        XCTAssertTrue(appearance.waitForExistence(timeout: 3))
        XCTAssertTrue(notifications.exists)
        XCTAssertEqual(appearance.frame.minX, notifications.frame.minX, accuracy: 2)
        XCTAssertGreaterThan(notifications.frame.minY, appearance.frame.minY)
        XCTAssertTrue(appearance.isHittable)
        XCTAssertTrue(notifications.isHittable)

        app.swipeUp()
        let widgets = app.buttons["settings.destination.widgets"]
        XCTAssertTrue(widgets.waitForExistence(timeout: 3))
        XCTAssertEqual(widgets.label, "Widgets")
        XCTAssertGreaterThan(widgets.frame.width, 250)
        XCTAssertGreaterThanOrEqual(widgets.frame.height, 112)
    }

    func testSettingsCriticalFlowAtAccessibilitySize() {
        let app = launchSettings(
            contentSizeCategory: "UICTContentSizeCategoryAccessibilityM",
            appearance: "Dark",
            reduceMotion: true,
            increaseContrast: true
        )
        let yourDay = app.buttons["settings.yourDay"]
        XCTAssertTrue(yourDay.waitForExistence(timeout: 3))
        XCTAssertTrue(yourDay.isHittable)
        assertMinimumHitTarget(yourDay)

        let appearance = app.buttons["settings.destination.appearance"]
        XCTAssertTrue(appearance.waitForExistence(timeout: 3))
        XCTAssertTrue(appearance.isHittable)
        assertMinimumHitTarget(appearance)
        appearance.tap()

        XCTAssertTrue(app.navigationBars["Appearance"].waitForExistence(timeout: 3))
        let automatic = app.buttons["Automatic"]
        app.buttons["settings.appearance.style.legacy"].tap()
        let manual = app.buttons["Manual"]
        XCTAssertTrue(automatic.waitForExistence(timeout: 3))
        XCTAssertTrue(manual.exists)
        reveal(automatic, in: app)
        XCTAssertTrue(automatic.isHittable)
        XCTAssertTrue(manual.isHittable)
        assertMinimumHitTarget(automatic)
        assertMinimumHitTarget(manual)
    }

    func testGridUsesMeasuredDeviceWidth() {
        let app = launchSettings()
        let appearance = app.buttons["settings.destination.appearance"]
        let notifications = app.buttons["settings.destination.notifications"]

        XCTAssertTrue(appearance.waitForExistence(timeout: 3))
        XCTAssertTrue(notifications.exists)
        let minimumTwoColumnAppWidth: CGFloat = (2 * 164) + 12 + (2 * 20)
        if app.frame.width < minimumTwoColumnAppWidth {
            XCTAssertEqual(appearance.frame.minX, notifications.frame.minX, accuracy: 2)
            XCTAssertGreaterThan(notifications.frame.minY, appearance.frame.minY)
            XCTAssertGreaterThan(appearance.frame.width, 300)
        } else {
            XCTAssertLessThan(appearance.frame.minX, notifications.frame.minX)
            XCTAssertEqual(appearance.frame.minY, notifications.frame.minY, accuracy: 2)
        }
    }

    func testWidgetsAndWallpaperHaveSeparateInstallFlows() {
        let app = launchSettings()
        openSettingsDestination("settings.destination.widgets", in: app)

        XCTAssertTrue(app.navigationBars["Widgets"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["settings.widgets.install"].exists)
        XCTAssertFalse(app.otherElements["settings.wallpaper.controls"].exists)
        XCTAssertTrue(app.otherElements["settings.widgets.controls"].exists)
        capture(app, name: "Simplified widget setup")
        let transparent = app.buttons["settings.widgets.background.clear"]
        revealWallpaperControl(transparent, in: app)
        transparent.tap()
        XCTAssertTrue(app.staticTexts["settings.widgets.clearInstructions"].exists)
        XCTAssertFalse(app.segmentedControls["settings.widgets.position"].exists)
        XCTAssertEqual(transparent.value as? String, "Not selected")
        capture(app, name: "Transparent widget preview")
        app.navigationBars.buttons.element(boundBy: 0).tap()
        openSettingsDestination("settings.destination.wallpaper", in: app)
        XCTAssertTrue(app.navigationBars["Wallpaper"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.otherElements["settings.wallpaper.controls"].exists)
        XCTAssertFalse(app.otherElements["settings.widgets.controls"].exists)
        assertMinimumHitTarget(app.buttons["settings.wallpaper.install"])
        capture(app, name: "Separate wallpaper setup")
    }

    // Scroll from the outer gutter: dragging through the background-choice
    // buttons can activate a choice during XCTest's press-and-drag gesture.
    private func revealWallpaperControl(_ element: XCUIElement, in app: XCUIApplication) {
        // SwiftUI segmented controls can report isHittable=false even when visible.
        // Position taps below use coordinates and verify the selected state.
        let topEdge = app.navigationBars.firstMatch.frame.maxY
        for _ in 0..<24 {
            if element.exists && element.frame.width > 0 && element.frame.minY >= topEdge - 1
                && element.frame.maxY < app.frame.maxY - 90 { return }
            let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.98, dy: 0.60))
            let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.98, dy: 0.48))
            if element.exists && element.frame.minY < topEdge {
                end.press(forDuration: 0.1, thenDragTo: start)
            } else {
                start.press(forDuration: 0.1, thenDragTo: end)
            }
        }
        capture(app, name: "Wallpaper control unreachable")
        XCTFail("Wallpaper control did not become visible")
    }

    private func waitForWallpaperSelection(_ button: XCUIElement) {
        let selected = XCTNSPredicateExpectation(predicate: NSPredicate(format: "selected == true"), object: button)
        XCTAssertEqual(XCTWaiter.wait(for: [selected], timeout: 3), .completed)
    }

    func testWallpaperAlignmentPositionPersists() {
        let app = launchSettings()
        openSettingsDestination("settings.destination.widgets", in: app)
        let match = app.buttons["settings.widgets.matchWallpaper"]
        revealWallpaperControl(match, in: app)
        match.tap()
        let position = app.segmentedControls["settings.widgets.position"]
        revealWallpaperControl(position.buttons["Bottom"], in: app)
        position.buttons["Bottom"].coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        waitForWallpaperSelection(position.buttons["Bottom"])
        XCTAssertEqual(match.value as? String, "Selected")
        capture(app, name: "Wallpaper alignment bottom")
        app.terminate()
        launchSettings(app, seedSettings: false)
        openSettingsDestination("settings.destination.widgets", in: app)
        revealWallpaperControl(position.buttons["Bottom"], in: app)
        waitForWallpaperSelection(position.buttons["Bottom"])
        position.buttons["Top"].coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        waitForWallpaperSelection(position.buttons["Top"])
        let tune = app.buttons["Adjust"]
        revealWallpaperControl(tune, in: app)
        tune.tap()
        let slider = app.sliders["Top edge"]
        revealWallpaperControl(slider, in: app)
        slider.adjust(toNormalizedSliderPosition: 0.5)
        capture(app, name: "Wallpaper alignment calibration")
        let reset = app.buttons["Reset alignment"]
        revealWallpaperControl(reset, in: app)
        reset.tap()
    }

    func testWallpaperOffersInstallBeforeOptionalInstructions() {
        let app = launchSettings()
        openSettingsDestination("settings.destination.wallpaper", in: app)
        let install = app.buttons["settings.wallpaper.install"]
        reveal(install, in: app)
        assertMinimumHitTarget(install)
        let setup = app.buttons["Setup"]
        revealWallpaperControl(setup, in: app)
        setup.tap()
        let openShortcuts = app.buttons["settings.wallpaper.openShortcuts"]
        reveal(openShortcuts, in: app)
        assertMinimumHitTarget(openShortcuts)
        XCTAssertTrue(app.staticTexts["Create an automation"].exists)
        XCTAssertTrue(app.staticTexts["Check your Lock Screen"].exists)
        capture(app, name: "Wallpaper setup")
    }

    func testDeveloperDiagnosticsHaveOneDestination() {
        let app = launchSettings()

        let developer = app.buttons["settings.destination.developer"]
        XCTAssertTrue(developer.exists)
        developer.tap()
        XCTAssertTrue(app.staticTexts["Developer"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["Copy Shield Diagnostics"].exists)
    }

    private func assertMinimumHitTarget(
        _ element: XCUIElement,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        // XCUI serializes CoreGraphics frames through floating-point layers;
        // a nominal 44 pt control can arrive as 43.999999999999986.
        let subpixelTolerance: CGFloat = 0.001
        XCTAssertTrue(element.waitForExistence(timeout: 3), file: file, line: line)
        XCTAssertGreaterThanOrEqual(
            element.frame.width + subpixelTolerance,
            44,
            file: file,
            line: line
        )
        XCTAssertGreaterThanOrEqual(
            element.frame.height + subpixelTolerance,
            44,
            file: file,
            line: line
        )
    }

    private func assertSectionLabel(
        _ title: String,
        sitsAbove surface: XCUIElement,
        in app: XCUIApplication,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let label = app.staticTexts[title]
        XCTAssertTrue(label.waitForExistence(timeout: 3), file: file, line: line)
        XCTAssertTrue(surface.waitForExistence(timeout: 3), file: file, line: line)
        XCTAssertLessThanOrEqual(
            label.frame.maxY + 8,
            surface.frame.minY,
            "Section labels should have clear space before the card surface",
            file: file,
            line: line
        )
    }

    private func openSettingsDestination(
        _ identifier: String,
        in app: XCUIApplication,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let destination = app.buttons[identifier]
        for _ in 0..<24 {
            let topEdge = app.navigationBars.firstMatch.frame.maxY + 8
            let viewport = CGRect(x: 0, y: topEdge, width: app.frame.width,
                                  height: app.frame.maxY - topEdge - 48)
            if destination.exists {
                let visible = destination.frame.intersection(viewport)
                if !visible.isNull && visible.height >= 32 {
                    app.coordinate(withNormalizedOffset: .zero)
                        .withOffset(CGVector(dx: visible.midX, dy: visible.midY)).tap()
                    return
                }
            }
            let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.70))
            let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.48))
            if destination.exists && destination.frame.maxY < topEdge {
                end.press(forDuration: 0.05, thenDragTo: start)
            } else {
                start.press(forDuration: 0.05, thenDragTo: end)
            }
        }
        capture(app, name: "Unreachable settings destination")
        XCTFail("Settings destination is not reachable: \(identifier)", file: file, line: line)
    }

    private func assertPermissionActionTargets(
        in app: XCUIApplication,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        for identifier in [
            "settings.permissions.health.action",
            "settings.permissions.screenTime.action",
            "settings.permissions.notifications.action",
        ] {
            let action = app.buttons[identifier]
            revealWallpaperControl(action, in: app)
            XCTAssertTrue(action.isHittable, "Permission action is not reachable: \(identifier)", file: file, line: line)
            assertMinimumHitTarget(action, file: file, line: line)
        }
    }

    private func waitForValue(_ expected: String, of element: XCUIElement) -> Bool {
        let predicate = NSPredicate { object, _ in
            guard let element = object as? XCUIElement else { return false }
            return String(describing: element.value).contains(expected)
        }
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: element)
        return XCTWaiter.wait(for: [expectation], timeout: 3) == .completed
    }

    private func waitForLabel(_ expected: String, of element: XCUIElement) -> Bool {
        let predicate = NSPredicate(format: "label == %@", expected)
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: element)
        return XCTWaiter.wait(for: [expectation], timeout: 3) == .completed
    }
}
