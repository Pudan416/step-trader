import XCTest
#if canImport(Steps4)
@testable import Steps4
#endif

final class GateArtworkTests: XCTestCase {
    private func withStore(_ body: (GateArtworkStore, UserDefaults) throws -> Void) rethrows {
        let name = "GateArtworkTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        try body(GateArtworkStore(defaults: defaults), defaults)
    }

    func testEmptyDayGetsArtworkAndConfigurationRefreshKeepsIt() {
        withStore { store, defaults in
            let now = Date(timeIntervalSince1970: 1000)
            let first = store.shieldArtwork(for: "app-a", now: now)
            // A new store represents the extension being recreated by iOS.
            let recreated = GateArtworkStore(defaults: defaults)
            XCTAssertEqual(first, recreated.shieldArtwork(for: "app-a", now: now.addingTimeInterval(20)))
        }
    }

    func testHandoffKeepsObjectAndIsConsumedOnlyByItsGroup() {
        withStore { store, defaults in
            let now = Date(timeIntervalSince1970: 1000)
            let shield = store.shieldArtwork(for: "app-a", now: now)
            store.prepareHandoff(from: "app-a", groupID: "group-a", now: now)
            let app = GateArtworkStore(defaults: defaults)
            XCTAssertNil(app.takeHandoff(for: "group-b", now: now))
            XCTAssertEqual(shield, app.takeHandoff(for: "group-a", now: now.addingTimeInterval(10)))
            XCTAssertNil(app.takeHandoff(for: "group-a", now: now.addingTimeInterval(11)))
            XCTAssertNotEqual(shield, store.shieldArtwork(for: "app-a", now: now.addingTimeInterval(12)))
        }
    }

    func testOldHandoffIsNotReused() {
        withStore { store, _ in
            let now = Date(timeIntervalSince1970: 1000)
            store.prepareHandoff(from: "app-a", groupID: "group-a", now: now)
            XCTAssertNil(store.takeHandoff(for: "group-a", now: now.addingTimeInterval(601)))
        }
    }

    func testRequestAfterLongLookKeepsObjectOnDeferredShieldRefresh() {
        withStore { store, _ in
            let now = Date(timeIntervalSince1970: 1000)
            let shown = store.shieldArtwork(for: "app-a", now: now)
            store.prepareHandoff(from: "app-a", groupID: "group-a", now: now.addingTimeInterval(120))
            XCTAssertEqual(shown, store.shieldArtwork(for: "app-a", now: now.addingTimeInterval(121)))
            XCTAssertEqual(shown, store.takeHandoff(for: "group-a", now: now.addingTimeInterval(122)))
        }
    }

    func testClosingShieldAndReturningLaterBothRefreshArtwork() {
        withStore { store, _ in
            let now = Date(timeIntervalSince1970: 1000)
            let first = store.shieldArtwork(for: "app-a", now: now)
            store.endShield(for: "app-a")
            let second = store.shieldArtwork(for: "app-a", now: now.addingTimeInterval(1))
            XCTAssertNotEqual(first, second)
            XCTAssertNotEqual(second, store.shieldArtwork(for: "app-a", now: now.addingTimeInterval(601)))
        }
    }

    func testArtworkUsesActualHappeningPresetsAndCompatibleMaterials() throws {
        for index in 0..<GateArtwork.variantCount {
            let artwork = GateArtwork(seed: UInt32(index))
            let preset = try XCTUnwrap(MetalShapeGenomeCatalog.presets.first { $0.id == artwork.presetID })
            let material = try XCTUnwrap(MetalShapeMaterial(rawValue: artwork.materialID))
            XCTAssertTrue(preset.compatibility.allowed.contains(material))
            XCTAssertEqual(material, .sideLight, "Gate icons keep the quiet two-color treatment")
            let frame = MetalShapeGenomeFrame.make(preset: preset, material: material, seed: artwork.renderSeed)
            let colors = artwork.colorVariant.map { frame.material.withColorVariant($0) } ?? frame.material
            XCTAssertEqual(colors.color1, colors.color2, "Hue changes must not introduce a third color")
        }
    }

    func testEveryVariantIsBundledInAppAndShieldAndRendersIdentically() throws {
        let plugins = try XCTUnwrap(Bundle.main.builtInPlugInsURL)
        let shield = try XCTUnwrap(Bundle(url: plugins.appendingPathComponent("ShieldConfiguration.appex")))
        for index in 0..<GateArtwork.variantCount {
            let artwork = GateArtwork(seed: UInt32(index))
            let appImage = try XCTUnwrap(GateArtworkRenderer.render(artwork, pixels: 240))
            let shieldImage = try XCTUnwrap(GateArtworkRenderer.render(artwork, pixels: 240, bundle: shield))
            let appData = try XCTUnwrap(appImage.dataProvider?.data) as Data
            let shieldData = try XCTUnwrap(shieldImage.dataProvider?.data) as Data
            XCTAssertEqual(appData, shieldData, artwork.resourceName)
            XCTAssertEqual(appData[3], 0, artwork.resourceName)
            XCTAssertGreaterThan(appData[120 * appImage.bytesPerRow + 120 * 4 + 3], 0, artwork.resourceName)
        }
    }

    func testRandomSelectionDoesNotImmediatelyRepeatTheVisibleVariant() {
        for index in 0..<GateArtwork.variantCount {
            let previous = GateArtwork(seed: UInt32(index))
            XCTAssertNotEqual(GateArtwork.random(excluding: previous).variantIndex, previous.variantIndex)
        }
    }

    func testArtworkRendersWithTransparentCornersAndVisibleBody() throws {
        let image = try XCTUnwrap(GateArtworkRenderer.render(GateArtwork(seed: 44100105), pixels: 240))
        let data = try XCTUnwrap(image.dataProvider?.data) as Data
        XCTAssertEqual(data[3], 0, "The shield background must show through the corners")
        XCTAssertGreaterThan(data[(120 * image.bytesPerRow) + 120 * 4 + 3], 0, "Empty days still need a visible object")
    }

    func testSameSeedRendersSameObjectAcrossRecreation() throws {
        let first = try XCTUnwrap(GateArtworkRenderer.render(GateArtwork(seed: 93222711), pixels: 240)?.dataProvider?.data) as Data
        let repeated = try XCTUnwrap(GateArtworkRenderer.render(GateArtwork(seed: 93222711), pixels: 240)?.dataProvider?.data) as Data
        let other = try XCTUnwrap(GateArtworkRenderer.render(GateArtwork(seed: 39831142), pixels: 240)?.dataProvider?.data) as Data
        XCTAssertEqual(first, repeated)
        XCTAssertNotEqual(first, other)
    }
}
