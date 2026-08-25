import SwiftUI
import UIKit
import XCTest
@testable import Steps4

final class AppTypographyTests: XCTestCase {
    func testRequiredUnboundedInstancesAreRegisteredInTheApplicationBundle() {
        XCTAssertNotNil(
            UIFont(name: "Unbounded-Regular", size: 24),
            "The regular Unbounded instance must be bundled and registered by the app target."
        )
        XCTAssertNotNil(
            UIFont(name: "Unbounded-Black", size: 24),
            "The exact static Unbounded Black face used by posters must be registered by the app target."
        )
    }

    @MainActor
    func testAppBlackBrandFontRendersTheStaticUnboundedBlackFace() throws {
        XCTAssertNotNil(
            UIFont(name: "Unbounded-Black", size: 80),
            "The static Unbounded Black face must be available before SwiftUI can render it."
        )

        let actual = try renderedImage(
            Text("0")
                .font(.unbounded(80, weight: .black))
        )
        let expected = try renderedImage(
            Text("0")
                .font(.custom("Unbounded-Black", fixedSize: 80))
        )

        let actualImage = try XCTUnwrap(actual.cgImage)
        let expectedImage = try XCTUnwrap(expected.cgImage)
        XCTAssertEqual(actualImage.width, expectedImage.width)
        XCTAssertEqual(actualImage.height, expectedImage.height)
        XCTAssertTrue(
            try rgbaPixels(in: actualImage) == rgbaPixels(in: expectedImage),
            "The app's .black brand font must render the exact static Unbounded Black face."
        )
    }

    @MainActor
    func testGalleryPosterDateMatchesFigmaUnboundedBlackSpec() throws {
        let date = try XCTUnwrap(
            Calendar(identifier: .gregorian).date(from: DateComponents(year: 2026, month: 8, day: 22))
        )
        let poster = MeGalleryPoster(
            date: date,
            steps: nil,
            sleepHours: nil,
            events: []
        ) {
            Color.clear
        }
        .frame(width: 604, height: 842)
        .fontDesign(.rounded)

        let posterImage = try renderedImage(poster)
        let posterTop = try XCTUnwrap(
            posterImage.cgImage?.cropping(to: CGRect(x: 0, y: 0, width: 604, height: 100))
        )
        let actualBounds = try darkPixelBounds(in: posterTop)

        let referenceImage = try renderedImage(
            Text("22/08/26")
                .font(.custom("Unbounded-Black", fixedSize: 40))
        )
        let expectedBounds = try darkPixelBounds(in: try XCTUnwrap(referenceImage.cgImage))

        XCTAssertEqual(actualBounds.width, expectedBounds.width, accuracy: 2)
        XCTAssertEqual(actualBounds.height, expectedBounds.height, accuracy: 2)
    }

    @MainActor
    func testMuseumPosterDateRendersTheBlackUnboundedInstance() throws {
        let date = try XCTUnwrap(
            Calendar(identifier: .gregorian).date(from: DateComponents(year: 2026, month: 8, day: 22))
        )
        let poster = CanvasFrameView(date: date) {
            Color.white
        }
        .frame(width: 604, height: 842)

        let posterImage = try renderedPosterImage(poster)
        let posterHeader = try XCTUnwrap(
            posterImage.cgImage?.cropping(to: CGRect(x: 0, y: 0, width: 604, height: 96))
        )
        let actualInk = try darkPixelCount(in: posterHeader)

        let blackReference = try renderedImage(
            Text("22/08/26")
                .font(.custom("Unbounded-Black", fixedSize: 48))
        )
        let expectedInk = try darkPixelCount(in: try XCTUnwrap(blackReference.cgImage))

        XCTAssertEqual(actualInk, expectedInk, accuracy: 40)
    }

    @MainActor
    func testGalleryPosterBalancesArtworkGapsBetweenRules() throws {
        let image = try galleryPosterImage(
            steps: nil,
            sleepHours: nil,
            events: []
        )
        let cgImage = try XCTUnwrap(image.cgImage)
        let artwork = try coloredPixelBounds(in: cgImage)
        let topRule = try darkPixelBounds(
            in: try XCTUnwrap(cgImage.cropping(to: CGRect(x: 0, y: 96, width: 604, height: 16)))
        ).offsetBy(dx: 0, dy: 96)
        let bottomRule = try darkPixelBounds(
            in: try XCTUnwrap(cgImage.cropping(to: CGRect(x: 0, y: 764, width: 604, height: 18)))
        ).offsetBy(dx: 0, dy: 764)

        let topGap = artwork.minY - topRule.maxY
        let bottomGap = bottomRule.minY - artwork.maxY

        XCTAssertEqual(topGap, bottomGap, accuracy: 1)
    }

    @MainActor
    func testGalleryPosterRotatedMetricsEndAtArtworkBottomAndRuleEdge() throws {
        let image = try galleryPosterImage(
            steps: 12_345,
            sleepHours: 7.5,
            events: []
        )
        let cgImage = try XCTUnwrap(image.cgImage)
        let artwork = try coloredPixelBounds(in: cgImage)
        let topRule = try darkPixelBounds(
            in: try XCTUnwrap(cgImage.cropping(to: CGRect(x: 0, y: 96, width: 604, height: 16)))
        ).offsetBy(dx: 0, dy: 96)
        let metrics = try darkPixelBounds(
            in: try XCTUnwrap(cgImage.cropping(to: CGRect(x: 536, y: 112, width: 40, height: 653)))
        ).offsetBy(dx: 536, dy: 112)

        XCTAssertLessThanOrEqual(abs(metrics.maxX - topRule.maxX), 8)
        XCTAssertLessThanOrEqual(abs(metrics.maxY - artwork.maxY), 8)
    }

    @MainActor
    func testGalleryPosterFooterLabelsShareTheirTopEdge() throws {
        let image = try galleryPosterImage(
            steps: nil,
            sleepHours: nil,
            events: (1...10).map { "Happening \($0)" }
        )
        let cgImage = try XCTUnwrap(image.cgImage)
        let nowhere = try darkPixelBounds(
            in: try XCTUnwrap(cgImage.cropping(to: CGRect(x: 32, y: 776, width: 190, height: 58)))
        ).offsetBy(dx: 32, dy: 776)
        let events = try darkPixelBounds(
            in: try XCTUnwrap(cgImage.cropping(to: CGRect(x: 270, y: 776, width: 300, height: 58)))
        ).offsetBy(dx: 270, dy: 776)

        XCTAssertEqual(nowhere.minY, events.minY, accuracy: 4)
    }

    @MainActor
    private func renderedImage<V: View>(_ view: V) throws -> UIImage {
        let renderer = ImageRenderer(
            content: view
                .foregroundStyle(.black)
                .padding(8)
                .background(.white)
                .fixedSize()
        )
        renderer.scale = 1
        return try XCTUnwrap(renderer.uiImage)
    }

    @MainActor
    private func renderedPosterImage<V: View>(_ view: V) throws -> UIImage {
        let renderer = ImageRenderer(content: view)
        renderer.scale = 1
        renderer.proposedSize = ProposedViewSize(width: 604, height: 842)
        return try XCTUnwrap(renderer.uiImage)
    }

    @MainActor
    private func galleryPosterImage(
        steps: Int?,
        sleepHours: Double?,
        events: [String]
    ) throws -> UIImage {
        let date = try XCTUnwrap(
            Calendar(identifier: .gregorian).date(from: DateComponents(year: 2026, month: 8, day: 22))
        )
        let renderer = ImageRenderer(
            content: MeGalleryPoster(
                date: date,
                steps: steps,
                sleepHours: sleepHours,
                events: events
            ) {
                Color(red: 0.92, green: 0.08, blue: 0.74)
            }
            .frame(width: 604, height: 842)
        )
        renderer.scale = 1
        renderer.proposedSize = ProposedViewSize(width: 604, height: 842)
        return try XCTUnwrap(renderer.uiImage)
    }

    private func darkPixelBounds(in image: CGImage) throws -> CGRect {
        let width = image.width
        let height = image.height
        let bytesPerRow = width * 4
        var pixels = [UInt8](repeating: 0, count: height * bytesPerRow)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let context = try XCTUnwrap(
            CGContext(
                data: &pixels,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: bytesPerRow,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )
        )
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))

        var minX = width
        var minY = height
        var maxX = -1
        var maxY = -1
        for y in 0..<height {
            for x in 0..<width {
                let offset = y * bytesPerRow + x * 4
                let isDark = pixels[offset] < 80 && pixels[offset + 1] < 80 && pixels[offset + 2] < 80
                if isDark && pixels[offset + 3] > 160 {
                    minX = min(minX, x)
                    minY = min(minY, y)
                    maxX = max(maxX, x)
                    maxY = max(maxY, y)
                }
            }
        }

        guard maxX >= minX, maxY >= minY else {
            throw XCTSkip("No dark text pixels found in rendered typography fixture")
        }
        return CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1)
    }

    private func rgbaPixels(in image: CGImage) throws -> [UInt8] {
        let width = image.width
        let height = image.height
        let bytesPerRow = width * 4
        var pixels = [UInt8](repeating: 0, count: height * bytesPerRow)
        let context = try XCTUnwrap(
            CGContext(
                data: &pixels,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: bytesPerRow,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )
        )
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return pixels
    }

    private func darkPixelCount(in image: CGImage) throws -> Int {
        let width = image.width
        let height = image.height
        let bytesPerRow = width * 4
        var pixels = [UInt8](repeating: 0, count: height * bytesPerRow)
        let context = try XCTUnwrap(
            CGContext(
                data: &pixels,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: bytesPerRow,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )
        )
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))

        var count = 0
        for y in 0..<height {
            for x in 0..<width {
                let offset = y * bytesPerRow + x * 4
                let isDark = pixels[offset] < 80 && pixels[offset + 1] < 80 && pixels[offset + 2] < 80
                if isDark && pixels[offset + 3] > 160 {
                    count += 1
                }
            }
        }
        return count
    }

    private func coloredPixelBounds(in image: CGImage) throws -> CGRect {
        let width = image.width
        let height = image.height
        let bytesPerRow = width * 4
        var pixels = [UInt8](repeating: 0, count: height * bytesPerRow)
        let context = try XCTUnwrap(
            CGContext(
                data: &pixels,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: bytesPerRow,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )
        )
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))

        var minX = width
        var minY = height
        var maxX = -1
        var maxY = -1
        for y in 0..<height {
            for x in 0..<width {
                let offset = y * bytesPerRow + x * 4
                let isArtworkColor = pixels[offset] > 180
                    && pixels[offset + 1] < 80
                    && pixels[offset + 2] > 140
                if isArtworkColor && pixels[offset + 3] > 160 {
                    minX = min(minX, x)
                    minY = min(minY, y)
                    maxX = max(maxX, x)
                    maxY = max(maxY, y)
                }
            }
        }

        return try XCTUnwrap(
            maxX >= minX && maxY >= minY
                ? CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1)
                : nil
        )
    }
}
