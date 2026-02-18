import XCTest
@testable import Steps4

final class TariffDecodingTests: XCTestCase {

    // MARK: - Standard raw values

    func testStandardRawValues() {
        XCTAssertEqual(Tariff(rawValue: "hard"), .hard)
        XCTAssertEqual(Tariff(rawValue: "medium"), .medium)
        XCTAssertEqual(Tariff(rawValue: "easy"), .easy)
        XCTAssertEqual(Tariff(rawValue: "free"), .free)
    }

    // MARK: - Backward-compatible "lite" → .easy

    func testDecodingLegacyLiteValue() throws {
        let json = Data(#""lite""#.utf8)
        let decoded = try JSONDecoder().decode(Tariff.self, from: json)
        XCTAssertEqual(decoded, .easy, "Legacy 'lite' should decode as .easy")
    }

    func testDecodingCurrentEasyValue() throws {
        let json = Data(#""easy""#.utf8)
        let decoded = try JSONDecoder().decode(Tariff.self, from: json)
        XCTAssertEqual(decoded, .easy)
    }

    func testDecodingHardValue() throws {
        let json = Data(#""hard""#.utf8)
        let decoded = try JSONDecoder().decode(Tariff.self, from: json)
        XCTAssertEqual(decoded, .hard)
    }

    func testDecodingMediumValue() throws {
        let json = Data(#""medium""#.utf8)
        let decoded = try JSONDecoder().decode(Tariff.self, from: json)
        XCTAssertEqual(decoded, .medium)
    }

    func testDecodingFreeValue() throws {
        let json = Data(#""free""#.utf8)
        let decoded = try JSONDecoder().decode(Tariff.self, from: json)
        XCTAssertEqual(decoded, .free)
    }

    func testDecodingUnknownValueDefaultsToEasy() throws {
        let json = Data(#""ultra""#.utf8)
        let decoded = try JSONDecoder().decode(Tariff.self, from: json)
        XCTAssertEqual(decoded, .easy, "Unknown raw value should default to .easy")
    }

    // MARK: - Encoding uses new raw value

    func testEncodingEasyUsesNewRawValue() throws {
        let data = try JSONEncoder().encode(Tariff.easy)
        let string = String(data: data, encoding: .utf8)
        XCTAssertEqual(string, #""easy""#, "Encoding .easy should produce 'easy', not 'lite'")
    }

    // MARK: - Round-trip

    func testRoundTrip() throws {
        for tariff in Tariff.allCases {
            let data = try JSONEncoder().encode(tariff)
            let decoded = try JSONDecoder().decode(Tariff.self, from: data)
            XCTAssertEqual(decoded, tariff, "\(tariff) should round-trip correctly")
        }
    }
}
