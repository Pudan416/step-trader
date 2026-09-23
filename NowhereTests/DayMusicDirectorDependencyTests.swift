import Foundation
import XCTest

final class DayMusicDirectorDependencyTests: XCTestCase {
    func testDirectorSourcesUseNoPlayerUIHealthOrRenderingFrameworks() throws {
        let sources = try directorSources()
        let forbiddenImports = [
            "AudioKit",
            "AVFoundation",
            "SwiftUI",
            "Metal",
            "MetalKit",
            "HealthKit",
            "UIKit",
            "AppKit",
        ]

        for source in sources {
            let contents = try String(contentsOf: source, encoding: .utf8)
            for framework in forbiddenImports {
                XCTAssertFalse(
                    contents.contains("import \(framework)"),
                    "\(source.lastPathComponent) imports forbidden framework \(framework)"
                )
            }
        }
    }

    func testDirectorSourcesContainNoNondeterministicOrRuntimeLoadingAPIs() throws {
        let sources = try directorSources()
        let forbiddenTokens = [
            "hashValue",
            "Hasher",
            "UUID(",
            "Date(",
            ".random",
            "Bundle.",
            "FileManager",
            "JSONDecoder",
            "Data(contentsOf:",
        ]

        for source in sources {
            let contents = try String(contentsOf: source, encoding: .utf8)
            for token in forbiddenTokens {
                XCTAssertFalse(
                    contents.contains(token),
                    "\(source.lastPathComponent) contains forbidden API token \(token)"
                )
            }
        }
    }

    private func directorSources() throws -> [URL] {
        let bundle = Bundle(for: type(of: self))
        let directory = try XCTUnwrap(
            bundle.url(forResource: "Director", withExtension: nil),
            "Director sources must be bundled into the test target"
        )
        let sources = try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ).filter { $0.pathExtension == "swift" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }

        XCTAssertFalse(sources.isEmpty, "Director source directory must be scanned")
        return sources
    }
}
