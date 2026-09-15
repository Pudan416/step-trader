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
        XCTAssertEqual(t.step, .balance)
        XCTAssertEqual(t.addedEntryID, "entry")
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

}
#endif
