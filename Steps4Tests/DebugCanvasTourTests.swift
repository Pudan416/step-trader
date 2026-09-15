#if DEBUG
import XCTest
@testable import Steps4

@MainActor
final class DebugCanvasTourTests: XCTestCase {
    private func tour() -> DebugCanvasTour { DebugCanvasTour(defaults: nil) }

    func testUnexpectedAndRepeatedEventsCannotCompleteAction() {
        let t = tour(); t.start(); t.hostReady()
        t.send(.dataPanelExpanded)
        XCTAssertEqual(t.step, .welcome)
        t.send(.begin); t.send(.begin)
        XCTAssertEqual(t.step, .add)
        t.send(.happeningAdded("entry"))
        XCTAssertEqual(t.step, .add)
    }

    func testHappeningWaitsForDismissAndKeepsEntryIdentity() {
        let t = tour(); t.start(); t.hostReady(); t.send(.begin)
        t.send(.palettePresented); t.send(.happeningAdded("entry"))
        XCTAssertEqual(t.step, .happening)
        t.send(.happeningAdded("duplicate"))
        t.send(.paletteDismissed)
        XCTAssertEqual(t.step, .momentResult)
        XCTAssertEqual(t.addedEntryID, "entry")
    }

    func testMomentConfirmationRequiresNextBeforeUserCanOpenDrawer() {
        let t = tour(); t.start(at: .happening); t.hostReady()
        t.send(.happeningAdded("saved"))
        t.send(.momentAcknowledged)
        XCTAssertEqual(t.step, .happening)
        t.send(.paletteDismissed)
        XCTAssertEqual(t.step, .momentResult)
        XCTAssertFalse(t.allowsControl("canvas.balanceHandle"))
        XCTAssertTrue(t.isContextualControl("canvas.balanceSummary"))
        t.send(.dataPanelExpanded)
        XCTAssertEqual(t.step, .momentResult)
        t.send(.momentAcknowledged)
        XCTAssertEqual(t.step, .balance)
        XCTAssertTrue(t.allowsControl("canvas.balanceHandle"))
        t.send(.momentAcknowledged)
        XCTAssertEqual(t.step, .balance)
        t.send(.dataPanelExpanded)
        XCTAssertEqual(t.step, .healthValue)
        XCTAssertEqual(t.addedEntryID, "saved")
    }

    func testUsingExistingDayAlsoWaitsForMomentAcknowledgement() {
        let t = tour(); t.start(at: .happening); t.hostReady()
        t.send(.useExistingDay)
        XCTAssertEqual(t.step, .momentResult)
        XCTAssertNil(t.addedEntryID)
        XCTAssertTrue(t.skippedBranches.contains("addHappening"))
        t.send(.momentAcknowledged)
        XCTAssertEqual(t.step, .balance)
    }

    func testVersionOneBalanceResumesAtNewConfirmationWithoutLosingEntry() throws {
        let name = "CanvasTourTests.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let t = DebugCanvasTour(defaults: defaults)
        t.start(at: .balance); t.hostReady()
        let key = "debug.canvasOnboarding.session.v1"
        var saved = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(defaults.data(forKey: key))) as? [String: Any])
        saved["flowVersion"] = 1
        saved["addedEntryID"] = "existing-entry"
        defaults.set(try JSONSerialization.data(withJSONObject: saved), forKey: key)
        let restored = DebugCanvasTour(defaults: defaults)
        XCTAssertFalse(restored.isActive)
        XCTAssertEqual(restored.flowVersion, 2)
        restored.resume(groupIDs: []); restored.hostReady()
        XCTAssertEqual(restored.step, .momentResult)
        XCTAssertEqual(restored.addedEntryID, "existing-entry")
        restored.send(.momentAcknowledged)
        XCTAssertEqual(restored.step, .balance)
    }

    func testRestartAndStopInvalidateLateOperations() {
        let t = tour(); t.start(at: .addApps); t.hostReady()
        let old = t.beginOperation("picker")!
        t.start(at: .addApps); t.hostReady()
        t.send(.appSelectionCommitted("old"), token: old)
        XCTAssertNil(t.selectedGroupID)
        let token = t.beginOperation("picker")!
        t.stop()
        t.send(.appSelectionCommitted("late"), token: token)
        XCTAssertFalse(t.isActive)
        XCTAssertNil(t.selectedGroupID)
    }

    func testPickerCommitWaitsForDismissAndCancellationRetries() {
        let t = tour(); t.start(at: .addApps); t.hostReady()
        t.sheetPresented("appPicker")
        t.sheetDismissed("appPicker")
        XCTAssertEqual(t.step, .addApps)
        t.sheetPresented("appPicker")
        t.send(.appSelectionCommitted("group"))
        XCTAssertEqual(t.step, .addApps)
        t.sheetDismissed("appPicker")
        XCTAssertEqual(t.step, .selectionResult)
        t.send(.appSelectionCommitted("duplicate"))
        XCTAssertEqual(t.selectedGroupID, "group")
    }

    func testWrongGroupCannotCompleteUnlockAndMissingGroupRecovers() {
        let t = tour(); t.start(at: .addApps); t.hostReady()
        t.send(.appSelectionCommitted("group")); t.send(.selectionAcknowledged)
        t.send(.groupOpened("other")); XCTAssertEqual(t.step, .selectFeed)
        t.send(.groupOpened("group")); t.send(.unlockSucceeded("other"))
        XCTAssertEqual(t.step, .chooseDuration)
        t.revalidate(groupIDs: [])
        XCTAssertEqual(t.step, .addApps)
        XCTAssertNil(t.selectedGroupID)
    }

    func testOptionalBranchesAndShareCancellationDoNotClaimSaved() {
        let t = tour(); t.start(at: .saveDays); t.hostReady()
        t.send(.posterReady("today")); t.send(.showSetup); t.sheetPresented("setup", returnContext: "setup")
        t.send(.setupCompleted)
        XCTAssertEqual(t.step, .setup)
        t.sheetDismissed("setup")
        XCTAssertEqual(t.step, .poster)
        t.sheetPresented("share")
        t.send(.shareDismissed(false)); t.sheetDismissed("share")
        XCTAssertEqual(t.step, .finish)
        XCTAssertFalse(t.shareCompleted)
        t.send(.finish)
        XCTAssertFalse(t.isActive)
    }

    func testRestoreIsPausedAndStartNeverResumesImplicitly() throws {
        let name = "CanvasTourTests.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let t = DebugCanvasTour(defaults: defaults)
        t.start(); t.hostReady(); t.send(.begin)
        let restored = DebugCanvasTour(defaults: defaults)
        XCTAssertFalse(restored.isActive)
        XCTAssertEqual(restored.step, .add)
        restored.start()
        XCTAssertEqual(restored.step, .welcome)
    }

    func testAuthorizationDismissRequiresFreshPickerOperation() throws {
        let t = tour(); t.start(at: .addApps); t.hostReady()
        let authorization = try XCTUnwrap(t.beginOperation("appSelection"))
        t.sheetPresented("screenTimeAuthorization")
        t.sheetDismissed("screenTimeAuthorization")
        XCTAssertFalse(t.isCurrent(authorization))
        let picker = try XCTUnwrap(t.beginOperation("appSelection"))
        XCTAssertNotEqual(authorization.id, picker.id)
        t.sheetPresented("appPicker")
        t.send(.appSelectionCommitted("stale"), token: authorization)
        XCTAssertNil(t.selectedGroupID)
        t.send(.appSelectionCommitted("chosen"), token: picker)
        XCTAssertEqual(t.step, .addApps)
        t.sheetDismissed("appPicker")
        XCTAssertEqual(t.selectedGroupID, "chosen")
        XCTAssertEqual(t.step, .selectionResult)
    }

    func testFailedUnlockCanRetryAndLateFirstResultCannotSpendTourProgress() throws {
        let t = tour(); t.start(at: .addApps); t.hostReady()
        t.send(.appSelectionCommitted("group")); t.send(.selectionAcknowledged)
        t.send(.groupOpened("group"))
        let first = try XCTUnwrap(t.beginOperation("unlock"))
        t.endOperation(first, error: "Access is unavailable")
        XCTAssertEqual(t.step, .chooseDuration)
        XCTAssertNil(t.operation)
        let retry = try XCTUnwrap(t.beginOperation("unlock"))
        t.send(.unlockSucceeded("group"), token: first)
        XCTAssertEqual(t.step, .chooseDuration)
        XCTAssertTrue(t.isCurrent(retry))
        t.send(.unlockSucceeded("group"), token: retry)
        XCTAssertEqual(t.step, .meTab)
        XCTAssertNil(t.operation)
    }

    func testNestedSetupPickerReturnsToChecklistWithoutAdvancing() throws {
        let t = tour(); t.start(at: .setup); t.hostReady()
        t.sheetPresented("setup", returnContext: "setup")
        let picker = try XCTUnwrap(t.beginOperation("appSelection", returnContext: "setup"))
        t.sheetPresented("appPicker", returnContext: "setup")
        t.send(.appSelectionCommitted("optional-group"), token: picker)
        t.sheetDismissed("appPicker")
        t.sheetPresented("setup", returnContext: "setup")
        XCTAssertEqual(t.step, .setup)
        XCTAssertEqual(t.returnContext, "setup")
        XCTAssertEqual(t.presentedSheet, "setup")
        XCTAssertNil(t.operation)
        t.send(.setupCompleted)
        XCTAssertEqual(t.step, .setup)
        t.sheetDismissed("setup")
        XCTAssertEqual(t.step, .poster)
    }

    func testLateSheetDismissCannotClearNewSessionOperation() {
        let t = tour(); t.start(at: .addApps); t.hostReady()
        let old = t.sessionID
        t.sheetPresented("appPicker")
        t.start(at: .addApps); t.hostReady()
        let current = t.beginOperation("picker")!
        t.sheetPresented("appPicker")
        t.sheetDismissed("appPicker", sessionID: old)
        XCTAssertEqual(t.operation, current)
        XCTAssertEqual(t.presentedSheet, "appPicker")
    }

    func testSetupWaitsForRealPosterReadiness() {
        let t = tour(); t.start(at: .saveDays); t.hostReady()
        t.send(.showSetup)
        XCTAssertEqual(t.step, .saveDays)
        t.send(.posterReady("today")); t.send(.showSetup)
        XCTAssertEqual(t.step, .setup)
    }

    func testResumeHealthRequiresUserToOpenPanelAgain() throws {
        let name = "CanvasTourTests.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let t = DebugCanvasTour(defaults: defaults)
        t.start(at: .healthValue); t.hostReady()
        let restored = DebugCanvasTour(defaults: defaults)
        restored.resume(groupIDs: [])
        XCTAssertEqual(restored.step, .balance)
    }

    func testMissingTargetDoesNotAdvanceAndQuietModeDoesNotResetStep() {
        let t = tour(); t.start(); t.hostReady(); t.send(.begin)
        t.targetVisible = false
        t.quietMode = .hide
        XCTAssertEqual(t.step, .add)
        XCTAssertTrue(t.isActive)
        t.stop()
        XCTAssertFalse(t.overlayVisible)
    }

    func testExitConfirmationPreservesStepAndSavedResultsUntilConfirmed() {
        let t = tour(); t.start(); t.hostReady(); t.send(.begin)
        t.send(.palettePresented); t.send(.happeningAdded("saved")); t.send(.paletteDismissed)
        t.send(.momentAcknowledged)
        t.send(.skipRequested)
        XCTAssertTrue(t.isActive)
        XCTAssertEqual(t.step, .balance)
        XCTAssertEqual(t.exitRequest, "skip")
        t.requestExit(reason: "outside tap")
        XCTAssertEqual(t.exitRequest, "skip")
        t.continueTour()
        XCTAssertNil(t.exitRequest)
        XCTAssertEqual(t.addedEntryID, "saved")
        t.send(.dataPanelExpanded)
        XCTAssertEqual(t.step, .healthValue)
        t.requestExit(reason: "outside tap"); t.confirmExit()
        XCTAssertFalse(t.isActive)
        XCTAssertEqual(t.addedEntryID, "saved")
    }

    func testExitCannotOverlaySystemUIAndRestartClearsConfirmation() {
        let t = tour(); t.start(at: .healthValue); t.hostReady()
        t.sheetPresented("health"); t.requestExit(reason: "outside tap")
        XCTAssertNil(t.exitRequest)
        t.sheetDismissed("health"); t.requestExit(reason: "outside tap")
        XCTAssertNotNil(t.exitRequest)
        t.start(); t.hostReady(); t.confirmExit()
        XCTAssertTrue(t.isActive)
        XCTAssertEqual(t.step, .welcome)
    }

    func testCardGeometryKeepsTargetsAndNavigationClearAtBothPhoneSizes() {
        for size in [CGSize(width: 375, height: 570), CGSize(width: 402, height: 722)] {
            for target in [CGRect(x: 310, y: size.height - 65, width: 44, height: 44),
                           CGRect(x: 20, y: 100, width: 330, height: 44),
                           CGRect(x: 20, y: 230, width: 80, height: 65)] {
                for height in [CGFloat(140), 280, 700] {
                    let frame = CanvasTourCardGeometry.frame(in: size, idealHeight: height,
                        step: .chooseDuration, target: target, navigationTop: size.height - 65)
                    XCTAssertFalse(frame.intersects(target))
                    XCTAssertGreaterThanOrEqual(frame.minX, 16)
                    XCTAssertGreaterThanOrEqual(frame.minY, 16)
                    XCTAssertLessThanOrEqual(frame.maxX, size.width - 16)
                    XCTAssertLessThanOrEqual(frame.maxY, size.height - 65)
                }
            }
        }
    }

}
#endif
