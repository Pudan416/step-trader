import XCTest
import SwiftUI
@testable import Steps4

/// The CPU spotlight renderer survived the radar deletion because the Gallery
/// canvas ray path calls it per frame (`RayShapeRenderer.draw`). The radar was
/// its only other caller, and nothing else covers it — these are
/// characterisation tests, pinning behaviour that is already correct.
final class RayShapeRendererTests: XCTestCase {

    private let near: (Float, Float, Float) = (1.0, 0.8, 0.4)
    private let mid: (Float, Float, Float) = (0.8, 0.5, 0.2)
    private let far: (Float, Float, Float) = (0.2, 0.1, 0.05)

    func testRendersABitmapOfTheRequestedSize() throws {
        let image = try XCTUnwrap(
            RayShapeRenderer.renderSpotlightBitmap(
                size: 64, time: 0, near: near, mid: mid, far: far
            )
        )
        XCTAssertEqual(image.width, 64)
        XCTAssertEqual(image.height, 64)
    }

    func testTheBitmapIsNotBlank() throws {
        let data = try XCTUnwrap(
            RayShapeRenderer.renderSpotlightPixels(
                size: 32, time: 0, near: near, mid: mid, far: far
            )
        )
        // A blank render would be uniformly transparent; the beam has to put
        // some non-zero alpha on the canvas.
        XCTAssertTrue(data.contains { $0 != 0 }, "Spotlight bitmap is entirely empty")
    }

    /// Premultiplied alpha: no channel may exceed its pixel's alpha, or the
    /// image composites with bright fringes wherever the beam fades out.
    func testPixelsStayPremultiplied() throws {
        let size = 32
        let data = try XCTUnwrap(
            RayShapeRenderer.renderSpotlightPixels(
                size: size, time: 0, near: near, mid: mid, far: far
            )
        )
        XCTAssertEqual(data.count, size * size * 4)
        for pixel in stride(from: 0, to: data.count, by: 4) {
            let alpha = data[pixel + 3]
            for channel in 0..<3 {
                XCTAssertLessThanOrEqual(
                    data[pixel + channel], alpha,
                    "Channel \(channel) exceeds alpha at byte \(pixel)"
                )
            }
        }
    }

    /// `rgbComponents` reaches UIColor, so it is main-actor bound — unlike the
    /// pixel loop above, which is `nonisolated` precisely so it can run off it.
    @MainActor
    func testRgbComponentsReadsAKnownColour() {
        let (r, g, b) = RayShapeRenderer.rgbComponents(Color(red: 1, green: 0.5, blue: 0))
        XCTAssertEqual(r, 1.0, accuracy: 0.01)
        XCTAssertEqual(g, 0.5, accuracy: 0.01)
        XCTAssertEqual(b, 0.0, accuracy: 0.01)
    }
}
