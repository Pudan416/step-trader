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

    func testFailedMutationStaysArmedAndSuccessfulMutationConfirms() {
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

    func testCancelClearsArmedPendingAndConfirmation() {
        var state = HappeningPaletteInteractionState()
        _ = state.tap(id: "walk", addedIDs: [])
        state.cancel()
        XCTAssertEqual(state, HappeningPaletteInteractionState())
    }
}
