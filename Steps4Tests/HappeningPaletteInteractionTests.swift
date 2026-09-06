import XCTest
@testable import Steps4

final class HappeningPaletteInteractionTests: XCTestCase {
    func testAvailableNeedsTwoActivationsToAdd() {
        var state = HappeningPaletteInteractionState()
        XCTAssertEqual(state.tap(id: "walk", addedIDs: []), .armed(.add("walk")))
        XCTAssertEqual(state.visualState(for: "walk", addedIDs: []), .additionPreview)
        XCTAssertEqual(state.tap(id: "walk", addedIDs: []), .perform(.add("walk")))
    }

    func testAddedNeedsTwoActivationsToRemove() {
        var state = HappeningPaletteInteractionState()
        let added: Set<String> = ["walk"]
        XCTAssertEqual(state.tap(id: "walk", addedIDs: added), .armed(.remove("walk")))
        XCTAssertEqual(state.visualState(for: "walk", addedIDs: added), .removalPreview)
        XCTAssertEqual(state.tap(id: "walk", addedIDs: added), .perform(.remove("walk")))
    }

    func testSwitchingSlotReplacesArmedIntentWithoutMutating() {
        var state = HappeningPaletteInteractionState()
        _ = state.tap(id: "walk", addedIDs: [])
        XCTAssertEqual(state.tap(id: "read", addedIDs: []), .armed(.add("read")))
        XCTAssertEqual(state.visualState(for: "walk", addedIDs: []), .available)
        XCTAssertEqual(state.visualState(for: "read", addedIDs: []), .additionPreview)
    }

    func testFailedAdditionStaysArmedAndSuccessfulMutationConfirms() {
        var state = HappeningPaletteInteractionState()
        _ = state.tap(id: "walk", addedIDs: [])
        XCTAssertEqual(state.tap(id: "walk", addedIDs: []), .perform(.add("walk")))
        state.resolve(.add("walk"), succeeded: false)
        XCTAssertEqual(state.armedMutation, .add("walk"))
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

    func testAccessibilityValuesDescribeAllFourPaletteStates() {
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

    func testSelectedOnCanvasHasRussianLocalization() throws {
        let russianResources = try XCTUnwrap(Bundle.main.path(forResource: "ru", ofType: "lproj"))
        let russianBundle = try XCTUnwrap(Bundle(path: russianResources))

        XCTAssertEqual(
            russianBundle.localizedString(forKey: "Selected, on Canvas", value: nil, table: nil),
            "Выбрано, на холсте"
        )
    }

    func testCancelClearsArmedPendingAndConfirmation() {
        var state = HappeningPaletteInteractionState()
        _ = state.tap(id: "walk", addedIDs: [])
        state.cancel()
        XCTAssertEqual(state, HappeningPaletteInteractionState())
    }
}
