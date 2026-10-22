import Foundation
import XCTest

/// Verify shipped resources, not just source files that might miss a target.
final class PrivacyManifestTests: XCTestCase {
    func testAppDeclaresPrivateAndAppGroupDefaultsAccess() throws {
        let reasons = try reasons(in: Bundle.main.bundleURL, category: "UserDefaults")
        XCTAssertTrue(reasons.isSuperset(of: ["CA92.1", "1C8F.1"]))
    }

    func testAppDeclaresElapsedEventTiming() throws {
        // MainTabView measures tab-selection latency using systemUptime.
        XCTAssertTrue(try reasons(in: Bundle.main.bundleURL, category: "SystemBootTime").contains("35F9.1"))
    }

    func testEmbeddedExtensionsDeclareSharedDefaultsAndPrivateFallback() throws {
        let plugins = try XCTUnwrap(Bundle.main.builtInPlugInsURL)
        for name in ["UnlockWidgetExtension", "DeviceActivityMonitor", "ShieldAction", "ShieldConfiguration"] {
            let bundle = plugins.appendingPathComponent("\(name).appex", isDirectory: true)
            let reasons = try reasons(in: bundle, category: "UserDefaults")
            // SharedKeys.appGroupDefaults also contains the app-private fallback.
            XCTAssertTrue(reasons.isSuperset(of: ["CA92.1", "1C8F.1"]), name)
        }
    }

    private func reasons(in bundle: URL, category: String) throws -> Set<String> {
        // Read the bundle's own manifest, never a dependency's declaration.
        let data = try Data(contentsOf: bundle.appendingPathComponent("PrivacyInfo.xcprivacy"))
        let manifest = try XCTUnwrap(PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])
        let entries = try XCTUnwrap(manifest["NSPrivacyAccessedAPITypes"] as? [[String: Any]])
        let entry = try XCTUnwrap(entries.first {
            $0["NSPrivacyAccessedAPIType"] as? String == "NSPrivacyAccessedAPICategory\(category)"
        })
        return Set(try XCTUnwrap(entry["NSPrivacyAccessedAPITypeReasons"] as? [String]))
    }
}
