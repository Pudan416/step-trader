import XCTest
@testable import Nowhere

final class HappeningPaletteInteractionTests: XCTestCase {
    func testAvailableAddsOnFirstActivation() {
        var state = HappeningPaletteInteractionState()
        XCTAssertEqual(state.tap(id: "walk", addedIDs: []), .perform(.add("walk")))
        XCTAssertEqual(state.pendingMutation, .add("walk"))
        state.resolve(.add("walk"), succeeded: true)
        XCTAssertEqual(state.visualState(for: "walk", addedIDs: ["walk"]), .added)
    }

    func testRapidTapsCannotSubmitPendingAdditionTwice() {
        var state = HappeningPaletteInteractionState()
        XCTAssertEqual(state.tap(id: "walk", addedIDs: []), .perform(.add("walk")))
        XCTAssertEqual(state.tap(id: "walk", addedIDs: []), .ignored)
        XCTAssertEqual(state.tap(id: "read", addedIDs: []), .ignored)
        state.resolve(.add("walk"), succeeded: true)
        XCTAssertEqual(state.visualState(for: "walk", addedIDs: ["walk"]), .added)
        // A fresh tap can only arm the existing removal action, never add again.
        XCTAssertEqual(state.tap(id: "walk", addedIDs: ["walk"]), .armed(.remove("walk")))
    }

    func testReopeningRestoresAddedIDsAndCancelsRemovalPreview() {
        var state = HappeningPaletteInteractionState()
        _ = state.tap(id: "walk", addedIDs: ["walk"])
        state.cancel()
        XCTAssertEqual(state.visualState(for: "walk", addedIDs: ["walk"]), .added)
        XCTAssertEqual(state.visualState(for: "read", addedIDs: ["walk"]), .available)
        XCTAssertEqual(state.tap(id: "read", addedIDs: ["walk"]), .perform(.add("read")))
        state.cancel()
        // The new custom day supplies an empty set from its own Canvas.
        XCTAssertEqual(state.visualState(for: "walk", addedIDs: []), .available)
    }

    func testAddedNeedsTwoActivationsToRemove() {
        var state = HappeningPaletteInteractionState()
        let added: Set<String> = ["walk"]
        XCTAssertEqual(state.tap(id: "walk", addedIDs: added), .armed(.remove("walk")))
        XCTAssertEqual(state.visualState(for: "walk", addedIDs: added), .removalPreview)
        XCTAssertEqual(state.tap(id: "walk", addedIDs: added), .perform(.remove("walk")))
    }

    func testChoosingAnotherAddedSlotReplacesRemovalPreviewWithoutMutating() {
        var state = HappeningPaletteInteractionState()
        let added: Set<String> = ["walk", "read"]
        _ = state.tap(id: "walk", addedIDs: added)
        XCTAssertEqual(state.tap(id: "read", addedIDs: added), .armed(.remove("read")))
        XCTAssertEqual(state.visualState(for: "walk", addedIDs: added), .added)
        XCTAssertEqual(state.visualState(for: "read", addedIDs: added), .removalPreview)
    }

    func testFailedAdditionCanRetryWithOneTapAndSuccessfulMutationConfirms() {
        var state = HappeningPaletteInteractionState()
        XCTAssertEqual(state.tap(id: "walk", addedIDs: []), .perform(.add("walk")))
        state.resolve(.add("walk"), succeeded: false)
        XCTAssertNil(state.armedMutation)
        XCTAssertNil(state.pendingMutation)
        XCTAssertEqual(state.tap(id: "walk", addedIDs: []), .perform(.add("walk")))
        state.resolve(.add("walk"), succeeded: true)
        XCTAssertNil(state.armedMutation)
        XCTAssertEqual(state.confirmation, .added("walk"))
    }

    func testFailedRemovalClearsArmedIntentAndReturnsToAddedState() {
        var state = HappeningPaletteInteractionState()
        let added: Set<String> = ["walk"]
        _ = state.tap(id: "walk", addedIDs: added)
        XCTAssertEqual(state.tap(id: "walk", addedIDs: added), .perform(.remove("walk")))

        state.resolve(.remove("walk"), succeeded: false)

        XCTAssertNil(state.armedMutation)
        XCTAssertNil(state.pendingMutation)
        XCTAssertEqual(state.visualState(for: "walk", addedIDs: added), .added)
    }

    func testAccessibilityValuesDescribePaletteStates() {
        XCTAssertEqual(HappeningPaletteAccessibility.value(for: .available), "Available")
        XCTAssertEqual(
            HappeningPaletteAccessibility.value(for: .additionPreview),
            "Previewing addition to Canvas"
        )
        XCTAssertEqual(HappeningPaletteAccessibility.value(for: .added), "On Canvas")
        XCTAssertEqual(
            HappeningPaletteAccessibility.value(for: .removalPreview),
            "Previewing removal from Canvas"
        )
    }

    func testPaletteSuccessHapticsDistinguishAddFromRemove() {
        XCTAssertEqual(HappeningPaletteSuccessHaptic.forMutation(.add("walk")), .addition)
        XCTAssertEqual(HappeningPaletteSuccessHaptic.forMutation(.remove("walk")), .removal)
        XCTAssertNotEqual(
            HappeningPaletteSuccessHaptic.forMutation(.add("walk")),
            HappeningPaletteSuccessHaptic.forMutation(.remove("walk"))
        )
    }

    func testTimedAccessCopyResolvesFromEnglishResourcesAndFormatsMinutes() throws {
        let englishResources = try XCTUnwrap(Bundle.main.path(forResource: "en", ofType: "lproj"))
        let englishBundle = try XCTUnwrap(Bundle(path: englishResources))
        XCTAssertEqual(
            englishBundle.localizedString(forKey: "This group is already unlocked", value: "MISSING_TIMED_ACCESS_RESOURCE", table: nil),
            "This group is already unlocked"
        )
        XCTAssertEqual(
            englishBundle.localizedString(forKey: "Add a happening to earn colors, or continue without an unlock.", value: "MISSING_TIMED_ACCESS_RESOURCE", table: nil),
            "Add a happening to earn colors, or continue without an unlock."
        )
        let format = englishBundle.localizedString(
            forKey: "Try %lld minutes. You'll spend real colors. The timer starts after payment and runs even when you aren't using the apps.",
            value: "MISSING_TIMED_ACCESS_RESOURCE", table: nil
        )
        XCTAssertEqual(
            String(format: format, Int64(30)),
            "Try 30 minutes. You'll spend real colors. The timer starts after payment and runs even when you aren't using the apps."
        )
    }

    func testShippingAppIsEnglishOnly() throws {
        XCTAssertNil(Bundle.main.path(forResource: "ru", ofType: "lproj"))
        let englishResources = try XCTUnwrap(Bundle.main.path(forResource: "en", ofType: "lproj"))
        let englishBundle = try XCTUnwrap(Bundle(path: englishResources))

        XCTAssertEqual(
            englishBundle.localizedString(forKey: "Frequent", value: nil, table: nil),
            "Frequent"
        )
    }

    func testCancelClearsArmedPendingAndConfirmation() {
        var state = HappeningPaletteInteractionState()
        _ = state.tap(id: "walk", addedIDs: ["walk"])
        state.cancel()
        XCTAssertEqual(state, HappeningPaletteInteractionState())
    }
}
