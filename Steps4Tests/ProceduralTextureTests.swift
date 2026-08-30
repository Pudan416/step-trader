import XCTest
import SwiftUI
@testable import Steps4

/// Fills are the axis of visual variety: same contours, different interiors.
/// Everything here is geometry in unit space — colour and scale are applied at
/// draw time, so one cached texture serves every size.
final class ProceduralTextureTests: XCTestCase {
    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: SharedKeys.allowedCanvasFills)
        super.tearDown()
    }

    func testOutlineIsAnAvailableCanvasFill() {
        XCTAssertNotNil(TextureKind(rawValue: "outline"))
    }

    func testAllowedCanvasFillsDefaultToEveryFillAndNeverBecomeEmpty() {
        UserDefaults.standard.removeObject(forKey: SharedKeys.allowedCanvasFills)
        XCTAssertEqual(TextureKind.allowedByUser, TextureKind.allCases)

        XCTAssertFalse(TextureKind.setAllowed([]))
        XCTAssertEqual(TextureKind.allowedByUser, TextureKind.allCases)
    }

    func testAllowedCanvasFillsPersistInStablePickerOrder() {
        XCTAssertTrue(TextureKind.setAllowed([.outline, .flat]))
        XCTAssertEqual(TextureKind.allowedByUser, [.flat, .outline])
        XCTAssertEqual(
            UserDefaults.standard.stringArray(forKey: SharedKeys.allowedCanvasFills),
            ["flat", "outline"]
        )
    }

    private func radii(seed: UInt64 = 1) -> [Double] {
        ProceduralShapeGenerator.organicBlobRadiusFactor(
            seed: seed, complexity: 0.5, symmetry: 1, time: 0)
    }

    // MARK: - Radial profiles

    func testExplicitProfileInitializerPreservesValidProfile() {
        let profile = RadialTextureProfile(
            center: CGPoint(x: 12, y: 34),
            outerRadius: 56,
            radii: [0.25, 1, 0.5, 0.75])
        XCTAssertEqual(profile.center, CGPoint(x: 12, y: 34))
        XCTAssertEqual(profile.outerRadius, 56)
        XCTAssertEqual(profile.radii, [0.25, 1, 0.5, 0.75])
    }

    func testCircleProfileIsFortyEightUnitRadii() {
        let profile = RadialTextureProfile.circle(
            center: CGPoint(x: 12, y: 34), radius: 56, sampleCount: 48)
        XCTAssertEqual(profile.center, CGPoint(x: 12, y: 34))
        XCTAssertEqual(profile.outerRadius, 56)
        XCTAssertEqual(profile.radii.count, 48)
        XCTAssertTrue(profile.radii.allSatisfy { $0 == 1 })
    }

    func testProfileNormalisesSourceRadii() {
        let profile = RadialTextureProfile(
            center: .zero, sourceRadii: [2, 4, 1, 3], rotation: 0)
        XCTAssertEqual(profile.outerRadius, 4)
        XCTAssertEqual(profile.radii.max(), 1)
        XCTAssertTrue(profile.radii.allSatisfy { $0.isFinite && $0 > 0 })
    }

    func testQuarterTurnResamplesIntoWorldAngleOrder() {
        let profile = RadialTextureProfile(
            center: .zero, sourceRadii: [1, 2, 3, 4], rotation: .pi / 2)
        XCTAssertEqual(profile.outerRadius, 4)
        XCTAssertEqual(profile.radii, [1, 0.25, 0.5, 0.75])
    }

    func testFractionalRotationPreservesInterpolatedAbsoluteRadii() {
        let profile = RadialTextureProfile(
            center: .zero, sourceRadii: [1, 4, 1, 1], rotation: .pi / 4)
        XCTAssertEqual(profile.outerRadius, 4)
        XCTAssertEqual(profile.radii.count, 4)
        for (radius, expected) in zip(profile.radii, [1, 2.5, 2.5, 1]) {
            XCTAssertEqual(profile.outerRadius * radius, expected, accuracy: 1e-12)
        }
    }

    func testFractionalRotationPreservesAbsoluteRadiiAcrossWrapBoundary() {
        let profile = RadialTextureProfile(
            center: .zero, sourceRadii: [4, 2, 1, 3], rotation: .pi / 8)
        XCTAssertEqual(profile.outerRadius, 4)
        XCTAssertEqual(profile.radii.count, 4)
        for (radius, expected) in zip(profile.radii, [3.75, 2.5, 1.25, 2.5]) {
            XCTAssertEqual(profile.outerRadius * radius, expected, accuracy: 1e-12)
        }
    }

    // MARK: - Determinism

    func testGeometryIsReproducibleFromSeed() {
        for kind in TextureKind.allCases {
            let spec = TextureSpec.seeded(kind: kind, seed: 77)
            let a = ProceduralTexture.geometry(spec: spec, radii: radii(), seed: 77)
            let b = ProceduralTexture.geometry(spec: spec, radii: radii(), seed: 77)
            XCTAssertEqual(a, b, "\(kind) is not reproducible")
        }
    }

    func testDifferentSeedsGiveDifferentGeometry() {
        for kind: TextureKind in [.rings, .hatch] {
            let a = ProceduralTexture.geometry(
                spec: .seeded(kind: kind, seed: 1), radii: radii(), seed: 1)
            let b = ProceduralTexture.geometry(
                spec: .seeded(kind: kind, seed: 2), radii: radii(), seed: 2)
            XCTAssertNotEqual(a, b, "\(kind) ignored its seed")
        }
    }

    func testSpecIsCodableRoundTrip() throws {
        for kind in TextureKind.allCases {
            let spec = TextureSpec.seeded(kind: kind, seed: 909)
            let data = try JSONEncoder().encode(spec)
            let decoded = try JSONDecoder().decode(TextureSpec.self, from: data)
            XCTAssertEqual(spec, decoded)
        }
    }

    /// `init(from:)` is hand-written specifically so a decoded spec still
    /// clamps — a synthesised `Decodable` would assign the raw JSON Doubles
    /// straight to the stored properties and skip the constructor entirely.
    func testSpecDecodingClampsOutOfRangeValues() throws {
        let json = """
        {"kind":"hatch","density":1.7,"uniformity":-0.4,"angle":-1.0}
        """
        let decoded = try JSONDecoder().decode(TextureSpec.self, from: Data(json.utf8))
        XCTAssertEqual(decoded.density, 1.0)
        XCTAssertEqual(decoded.uniformity, 0.0)
        XCTAssertEqual(decoded.angle, 2 * .pi - 1.0, accuracy: 1e-9)
    }

    /// `TextureSpec` is a cache key, so near-identical Doubles must not miss.
    func testSpecHashingIsQuantised() {
        let a = TextureSpec(kind: .hatch, density: 0.5, uniformity: 0.5, angle: 1.0)
        let b = TextureSpec(kind: .hatch, density: 0.50000001,
                            uniformity: 0.5, angle: 1.0)
        XCTAssertEqual(a, b)
        XCTAssertEqual(a.hashValue, b.hashValue)
    }

    // MARK: - Per-kind content

    func testFlatProducesNoSubGeometry() {
        let g = ProceduralTexture.geometry(
            spec: .seeded(kind: .flat, seed: 1), radii: radii(), seed: 1)
        XCTAssertTrue(g.rings.isEmpty)
        XCTAssertTrue(g.lines.isEmpty)
    }

    func testGradientProducesNoSubGeometry() {
        let g = ProceduralTexture.geometry(
            spec: .seeded(kind: .gradient, seed: 1), radii: radii(), seed: 1)
        XCTAssertTrue(g.rings.isEmpty)
        XCTAssertTrue(g.lines.isEmpty)
    }

    func testRingsNestInwardWithoutCrossing() {
        let g = ProceduralTexture.geometry(
            spec: .seeded(kind: .rings, seed: 5), radii: radii(), seed: 5)
        XCTAssertGreaterThanOrEqual(g.rings.count, 3)

        for ring in g.rings {
            XCTAssertEqual(ring.count, radii().count, "Ring point count must match")
            XCTAssertGreaterThan(ring.min() ?? 0, 0, "A ring collapsed through zero")
        }
        // Each ring sits strictly inside the previous one.
        for i in 1..<g.rings.count {
            for j in g.rings[i].indices {
                XCTAssertLessThan(g.rings[i][j], g.rings[i - 1][j],
                                  "Ring \(i) crossed ring \(i - 1) at \(j)")
            }
        }
    }

    func testHatchLinesShareOneAngle() {
        let spec = TextureSpec.seeded(kind: .hatch, seed: 13)
        let g = ProceduralTexture.geometry(spec: spec, radii: radii(), seed: 13)
        XCTAssertGreaterThanOrEqual(g.lines.count, 4)

        let angles = g.lines.map { atan2($0.end.y - $0.start.y, $0.end.x - $0.start.x) }
        let reference = angles[0]
        for angle in angles {
            // Parallel up to direction, so compare modulo π.
            let delta = abs((angle - reference)
                .truncatingRemainder(dividingBy: .pi))
            XCTAssertTrue(delta < 1e-6 || abs(delta - .pi) < 1e-6,
                          "Hatch line off-angle by \(delta)")
        }
    }

    func testHatchLinesStayInsideTheUnitDisc() {
        let contour = radii()
        let g = ProceduralTexture.geometry(
            spec: .seeded(kind: .hatch, seed: 19), radii: contour, seed: 19)
        // hatchGeometry's chords are constructed on the circumscribing circle
        // of radius `contour.max()` (draw-time clipping to the contour is
        // what actually bounds the visible fill — see `testHatchCoversTheFullForm`),
        // so every endpoint's distance from the origin is at most that bound.
        let bound = contour.max() ?? 1
        for line in g.lines {
            XCTAssertLessThanOrEqual(hypot(line.start.x, line.start.y), bound + 1e-9)
            XCTAssertLessThanOrEqual(hypot(line.end.x, line.end.y), bound + 1e-9)
        }
    }

    /// Pins the fix for hatch covering only ~40% of the form: scanlines must
    /// reach out toward the contour's actual extent, not stop at the
    /// inscribed circle. A hatch clipped to `contour.min() * 0.95` would fail
    /// this on any contour whose radii vary meaningfully by angle.
    func testHatchCoversTheFullForm() {
        let contour = radii()
        let g = ProceduralTexture.geometry(
            spec: .seeded(kind: .hatch, seed: 19), radii: contour, seed: 19)
        let farthestReach = g.lines
            .flatMap { [hypot($0.start.x, $0.start.y), hypot($0.end.x, $0.end.y)] }
            .max() ?? 0
        XCTAssertGreaterThan(farthestReach, (contour.min() ?? 1) * 1.05,
                             "Hatch lines never reach past the inscribed circle")
    }

    // MARK: - Uniformity
    //
    // "Однородные и нет": the same fill must be able to read as even or as
    // strongly graded across the form.

    func testHatchDensityDrivesLineCount() {
        func lineCount(_ density: Double) -> Int {
            let spec = TextureSpec(kind: .hatch, density: density,
                                   uniformity: 1.0, angle: 0.7)
            return ProceduralTexture.geometry(spec: spec, radii: radii(), seed: 67)
                .lines.count
        }
        XCTAssertLessThan(lineCount(0.2), lineCount(0.9))
    }

    // MARK: - Budget
    //
    // Sub-geometry is cached, but it still has to be drawn every frame.

    func testSubGeometryStaysWithinBudget() {
        for kind in TextureKind.allCases {
            for seed in stride(from: UInt64(0), to: 200, by: 13) {
                let spec = TextureSpec(kind: kind, density: 1.0,
                                       uniformity: 0.0, angle: 1.2)
                let g = ProceduralTexture.geometry(spec: spec, radii: radii(), seed: seed)
                XCTAssertLessThanOrEqual(g.lines.count, 40, "\(kind) lines")
                XCTAssertLessThanOrEqual(g.rings.count, 8, "\(kind) rings")
            }
        }
    }

    // MARK: - Seeded specs

    func testSeededSpecStaysInRange() {
        for kind in TextureKind.allCases {
            for seed in UInt64(0)..<50 {
                let spec = TextureSpec.seeded(kind: kind, seed: seed)
                XCTAssertEqual(spec.kind, kind)
                XCTAssertTrue((0...1).contains(spec.density))
                XCTAssertTrue((0...1).contains(spec.uniformity))
                XCTAssertTrue((0...(2 * Double.pi)).contains(spec.angle))
            }
        }
    }
}

// MARK: - Render cache

/// `RenderCache.textureGeometry` is the plan's single most important
/// constraint made real: texture geometry is generated once per bucket, not
/// per frame. These tests cover the caching mechanism itself, not the fill
/// algorithms above — hits skip regeneration, family and profile identities
/// cannot collide, generation uses canonical bucket time independent of call
/// order, pruning keeps the dictionary bounded, and per-seed phase keeps 15
/// elements' buckets from flipping on the same frame. `RenderCache` is
/// `@MainActor`, so this class is too.
@MainActor
final class RenderCacheTextureTests: XCTestCase {

    private func radii(seed: UInt64 = 1, complexity: Double = 0.5) -> [Double] {
        ProceduralShapeGenerator.organicBlobRadiusFactor(
            seed: seed, complexity: complexity, symmetry: 1, time: 0)
    }

    private func snowflakeElement(optionId: String, seed: UInt64? = nil) -> CanvasElement {
        var element = CanvasElement.spawn(
            optionId: optionId, label: optionId, existingElements: [],
            allowedShapeTypes: [.snowflake], dayKey: "2026-08-10",
            composition: DayComposition.forDay(
                dayKey: "2026-08-10", happeningCount: 1))
        element.shapeSeed = seed
        return element
    }

    private func pixelBytes(
        of image: UIImage
    ) throws -> (bytes: [UInt8], width: Int, height: Int, bytesPerRow: Int, bytesPerPixel: Int) {
        let cgImage = try XCTUnwrap(image.cgImage)
        let data = try XCTUnwrap(cgImage.dataProvider?.data)
        XCTAssertEqual(cgImage.bitsPerPixel % 8, 0)
        return (
            CFDataGetBytePtr(data).map {
                Array(UnsafeBufferPointer(start: $0, count: CFDataGetLength(data)))
            } ?? [],
            cgImage.width,
            cgImage.height,
            cgImage.bytesPerRow,
            cgImage.bitsPerPixel / 8)
    }

    func testDrawingOnlySnowflakeGhostsDoesNotPopulateTextureCache() {
        let cache = RenderCache()
        let element = CanvasElement.spawn(
            optionId: "ghost", label: "Ghost", existingElements: [],
            allowedShapeTypes: [.snowflake], dayKey: "2026-08-10",
            composition: DayComposition.forDay(
                dayKey: "2026-08-10", happeningCount: 1))
        let view = Canvas { context, size in
            SnowflakeShapeRenderer.drawTrailGhosts(
                element, context: &context, size: size, t: 10,
                decay: 0, blendMode: .normal, ampScale: 1,
                renderCache: cache, decayedColor: .red, decayedColor2: .blue)
        }.frame(width: 200, height: 200)
        let renderer = ImageRenderer(content: view)
        _ = renderer.uiImage
        XCTAssertTrue(cache.textureCache.isEmpty)
    }

    func testSnowflakeRendererRoutesEveryTextureKindThroughExpectedBranch() throws {
        let element = snowflakeElement(optionId: "body")

        for kind in TextureKind.allCases {
            let cache = RenderCache()
            let spec = TextureSpec(
                kind: kind, density: 0.7, uniformity: 0.4, angle: 1)
            let view = Canvas { context, size in
                SnowflakeShapeRenderer.draw(
                    element, context: &context, size: size, t: 10,
                    decay: 0, blendMode: .normal, ampScale: 1,
                    renderCache: cache, decayedColor: .red, decayedColor2: .blue,
                    spec: spec)
            }.frame(width: 200, height: 200)

            _ = ImageRenderer(content: view).uiImage

            if kind == .gradient {
                XCTAssertTrue(cache.textureCache.isEmpty)
            } else {
                XCTAssertEqual(cache.textureCache.count, 1)
                XCTAssertEqual(
                    try XCTUnwrap(cache.textureCache.keys.first).family,
                    .snowflake)
            }
        }
    }

    func testSnowflakeRingsStayInsideCurrentContourAtBucketEdge() throws {
        let canvasSize = CGSize(width: 400, height: 400)
        // Use the upper edge of the bucket immediately before time zero. It
        // also precedes the first trail tick, isolating the current body.
        let time = -RenderCache.texturePhase(for: 100) - 0.001
        var element = snowflakeElement(optionId: "bucket-edge", seed: 100)
        element.basePosition = CGPoint(x: 0.5, y: 0.5)
        element.phaseOffset = 0
        element.userSize = 0.38
        let spec = TextureSpec(
            kind: .rings, density: 1, uniformity: 0, angle: 0)

        let fullCache = RenderCache()
        let fullView = Canvas { context, size in
            SnowflakeShapeRenderer.draw(
                element, context: &context, size: size, t: time,
                decay: 0, blendMode: .normal, ampScale: 1,
                renderCache: fullCache, decayedColor: .white,
                decayedColor2: .white, spec: spec)
        }.frame(width: canvasSize.width, height: canvasSize.height)
        let fullRenderer = ImageRenderer(content: fullView)
        fullRenderer.scale = 1
        let full = try pixelBytes(of: XCTUnwrap(fullRenderer.uiImage))

        let maskCache = RenderCache()
        let maskView = Canvas { context, size in
            SnowflakeShapeRenderer.draw(
                element, context: &context, size: size, t: time,
                decay: 0, blendMode: .normal, ampScale: 1,
                renderCache: maskCache, decayedColor: .white,
                decayedColor2: .white,
                spec: TextureSpec(
                    kind: .gradient, density: 1, uniformity: 0, angle: 0))
        }.frame(width: canvasSize.width, height: canvasSize.height)
        let maskRenderer = ImageRenderer(content: maskView)
        maskRenderer.scale = 1
        let mask = try pixelBytes(of: XCTUnwrap(maskRenderer.uiImage))

        var escapedPixelCount = 0
        for y in 0..<full.height {
            for x in 0..<full.width {
                let offset = y * full.bytesPerRow + x * full.bytesPerPixel
                let ringPixel = full.bytes[offset..<(offset + full.bytesPerPixel)].max() ?? 0
                let maskPixel = mask.bytes[offset..<(offset + mask.bytesPerPixel)].max() ?? 0
                if ringPixel > 2 && maskPixel <= 2 {
                    escapedPixelCount += 1
                }
            }
        }

        XCTAssertEqual(
            escapedPixelCount, 0,
            "Current-body ring pixels escaped the current Snowflake contour")
    }

    /// Removing the cache-hit branch would invoke the provider twice.
    func testRepeatCallWithinOneBucketIsCached() {
        let cache = RenderCache()
        let spec = TextureSpec(kind: .hatch, density: 0.7, uniformity: 0.3, angle: 0)
        let phase = RenderCache.texturePhase(for: 5)
        var providerCalls = 0

        let first = cache.textureGeometry(
            family: .organicBlob,
            seed: 5,
            spec: spec,
            profileKey: 5_000,
            time: 0.2 - phase,
            radiiAtCanonicalTime: { _ in
                providerCalls += 1
                return self.radii(seed: 1)
            })
        let second = cache.textureGeometry(
            family: .organicBlob,
            seed: 5,
            spec: spec,
            profileKey: 5_000,
            time: 0.9 - phase,
            radiiAtCanonicalTime: { _ in
                providerCalls += 1
                return self.radii(seed: 99)
            })

        XCTAssertEqual(first, second,
                       "A call within the same bucket must hit the cache, not regenerate")
        XCTAssertEqual(providerCalls, 1)
    }

    /// Removing `profileKey` from the key would return the low-complexity
    /// rings for the high-complexity contour.
    func testDifferentProfileKeysNeverCollide() {
        let cache = RenderCache()
        let spec = TextureSpec(kind: .rings, density: 0.6, uniformity: 0.4, angle: 0)

        let low = cache.textureGeometry(
            family: .organicBlob,
            seed: 5,
            spec: spec,
            profileKey: 1_000,
            time: 0,
            radiiAtCanonicalTime: { _ in self.radii(complexity: 0.1) })
        let high = cache.textureGeometry(
            family: .organicBlob,
            seed: 5,
            spec: spec,
            profileKey: 9_000,
            time: 0,
            radiiAtCanonicalTime: { _ in self.radii(complexity: 0.9) })

        XCTAssertNotEqual(low, high, "Different radial profiles must generate separate geometry")
        XCTAssertEqual(cache.textureCache.count, 2)
    }

    /// Removing `family` from the key would let one shape family reuse
    /// another family's geometry when every other key field matches.
    func testFamiliesNeverCollide() {
        let cache = RenderCache()
        let spec = TextureSpec(kind: .rings, density: 0.6, uniformity: 0.4, angle: 0)

        let circle = cache.textureGeometry(
            family: .circle,
            seed: 5,
            spec: spec,
            profileKey: 0,
            time: 0,
            radiiAtCanonicalTime: { _ in [Double](repeating: 1, count: 48) })
        let snowflake = cache.textureGeometry(
            family: .snowflake,
            seed: 5,
            spec: spec,
            profileKey: 0,
            time: 0,
            radiiAtCanonicalTime: { _ in [1, 0.4, 1, 0.4, 1, 0.4] })

        XCTAssertNotEqual(circle, snowflake)
        XCTAssertEqual(cache.textureCache.count, 2)
    }

    /// Passing request time to the provider, or regenerating on a hit, would
    /// record two non-canonical times here.
    func testProviderReceivesCanonicalBucketTimeOnlyOnce() {
        let cache = RenderCache()
        let spec = TextureSpec(kind: .rings, density: 0.6, uniformity: 0.4, angle: 0)
        let phase = RenderCache.texturePhase(for: 75)
        let firstTime = 0.2 - phase
        let secondTime = 0.9 - phase
        var received: [Double] = []

        _ = cache.textureGeometry(
            family: .snowflake,
            seed: 75,
            spec: spec,
            profileKey: 0,
            time: firstTime,
            radiiAtCanonicalTime: {
                received.append($0)
                return [1, 0.5, 1, 0.5]
            })
        _ = cache.textureGeometry(
            family: .snowflake,
            seed: 75,
            spec: spec,
            profileKey: 0,
            time: secondTime,
            radiiAtCanonicalTime: {
                received.append($0)
                return [1, 0.2, 1, 0.2]
            })

        XCTAssertEqual(received.count, 1)
        let bucket = RenderCache.textureBucket(
            for: firstTime + phase)
        let expected = (Double(bucket) + 0.5) * RenderCache.textureBucketSeconds
            - phase
        XCTAssertEqual(received[0], expected, accuracy: 1e-12)
    }

    /// Using the first request's render time to build geometry would make the
    /// winning value depend on which request reached an empty cache first.
    func testCanonicalGeometryIsIndependentOfCallOrderWithinBucket() {
        let spec = TextureSpec(kind: .rings, density: 0.6, uniformity: 0.4, angle: 0)
        let phase = RenderCache.texturePhase(for: 75)
        let earlier = 0.2 - phase
        let later = 0.9 - phase

        func geometry(firstTime: Double, secondTime: Double) -> TextureGeometry {
            let cache = RenderCache()
            func request(at time: Double) -> TextureGeometry {
                cache.textureGeometry(
                    family: .organicBlob,
                    seed: 75,
                    spec: spec,
                    profileKey: 5_000,
                    time: time,
                    radiiAtCanonicalTime: { canonicalTime in
                        ProceduralShapeGenerator.organicBlobRadiusFactor(
                            seed: 75,
                            complexity: 0.5,
                            symmetry: 1,
                            time: canonicalTime)
                    })
            }
            let first = request(at: firstTime)
            XCTAssertEqual(first, request(at: secondTime))
            return first
        }

        XCTAssertEqual(
            geometry(firstTime: earlier, secondTime: later),
            geometry(firstTime: later, secondTime: earlier))
    }

    /// Pins the prune: repeatedly advancing the bucket must not let the
    /// dictionary grow with every bucket ever visited.
    func testCacheStaysBoundedAcrossManyBuckets() {
        let cache = RenderCache()
        let spec = TextureSpec(kind: .rings, density: 0.5, uniformity: 0.5, angle: 0)

        for i in 0..<50 {
            let time = Double(i) * RenderCache.textureBucketSeconds
            _ = cache.textureGeometry(
                family: .organicBlob,
                seed: 7,
                spec: spec,
                profileKey: 5_000,
                time: time,
                radiiAtCanonicalTime: { _ in self.radii() })
        }

        XCTAssertLessThanOrEqual(cache.textureCache.count, 3,
                                 "Prune should keep the cache bounded to the current and previous bucket")
    }

    /// OrganicBlob renders four layers at `t + layer * 2.3` with seeds spaced
    /// by 7,919. At t=0 those real clocks span buckets 0, 2, 3, and 4. A
    /// global highest-bucket prune must not evict another request whose own
    /// bucket 0 entry is still current.
    func testOrganicLayerOffsetsDoNotEvictCurrentCircleBucket() {
        let cache = RenderCache()
        let spec = TextureSpec(kind: .rings, density: 0.6, uniformity: 0.4, angle: 0)
        var circleProviderCalls = 0

        func requestCircle() {
            _ = cache.textureGeometry(
                family: .circle,
                seed: 0,
                spec: spec,
                profileKey: 0,
                time: 0,
                radiiAtCanonicalTime: { _ in
                    circleProviderCalls += 1
                    return [Double](repeating: 1, count: 48)
                })
        }

        requestCircle()
        for layer in 0..<4 {
            let layerSeed = UInt64(layer) &* 7_919
            _ = cache.textureGeometry(
                family: .organicBlob,
                seed: layerSeed,
                spec: spec,
                profileKey: 5_000,
                time: Double(layer) * 2.3,
                radiiAtCanonicalTime: { _ in self.radii(seed: layerSeed) })
        }
        requestCircle()

        XCTAssertEqual(
            circleProviderCalls,
            1,
            "Organic layer clock offsets must not evict a current circle cache entry")
    }

    /// Identity-local bucket retention must still have an explicit global
    /// bound when changing profiles create many stable request identities.
    func testCacheStaysBoundedAcrossManyRequestIdentities() {
        let cache = RenderCache()
        let spec = TextureSpec(kind: .rings, density: 0.6, uniformity: 0.4, angle: 0)

        for profileKey in 0..<400 {
            _ = cache.textureGeometry(
                family: .circle,
                seed: 0,
                spec: spec,
                profileKey: profileKey,
                time: 0,
                radiiAtCanonicalTime: { _ in [Double](repeating: 1, count: 48) })
        }

        XCTAssertLessThanOrEqual(cache.textureCache.count, 256)
    }

    func testTextureBucketMapsTimeAsIntended() {
        XCTAssertEqual(RenderCache.textureBucket(for: 0), 0)
        XCTAssertEqual(RenderCache.textureBucket(for: 1.49), 0)
        XCTAssertEqual(RenderCache.textureBucket(for: 1.5), 1)
        XCTAssertEqual(RenderCache.textureBucket(for: 2.9), 1)
        XCTAssertEqual(RenderCache.textureBucket(for: 3.0), 2)
        XCTAssertEqual(RenderCache.textureBucket(for: -0.1), -1)
    }

    /// Different seeds must land at different deterministic phases, each
    /// within one bucket's width, so regeneration work remains staggered.
    func testPhaseStaggersDifferentSeeds() {
        XCTAssertNotEqual(RenderCache.texturePhase(for: 0), RenderCache.texturePhase(for: 75))
        for seed: UInt64 in [0, 1, 75, 149, 150, 12_345] {
            let phase = RenderCache.texturePhase(for: seed)
            XCTAssertTrue((0..<RenderCache.textureBucketSeconds).contains(phase),
                          "Phase \(phase) for seed \(seed) exceeds one bucket width")
        }
    }

    /// Using only `seed % 150` makes every seed in this arithmetic progression
    /// regenerate on one 20 fps frame. Full-seed mixing must keep the maximum
    /// synchronous miss batch small enough for the 55 ms frame budget.
    func testFullSeedPhaseSpreadsModuloCollisionsAcrossTwentyFPSFrames() {
        let seeds = (0..<15).map { UInt64($0) * 150 }
        let frameSlots = seeds.map {
            Int(RenderCache.texturePhase(for: $0) / 0.05)
        }
        let largestBatch = Dictionary(grouping: frameSlots, by: { $0 })
            .values.map(\.count).max() ?? 0

        XCTAssertLessThanOrEqual(largestBatch, 2)
    }

    /// Identity-local retention must not let a phased-ahead request evict a
    /// phased-behind request's still-current entry. Select the minimum and
    /// maximum phases from a stable seed set, then place them one bucket apart.
    func testStaggeredPhasesDoNotEvictEachOtherPrematurely() {
        let cache = RenderCache()
        let spec = TextureSpec(kind: .rings, density: 0.5, uniformity: 0.5, angle: 0)
        let phasedSeeds = (0..<15).map { rank -> (seed: UInt64, phase: Double) in
            let seed = UInt64(rank) * 150
            return (seed, RenderCache.texturePhase(for: seed))
        }
        let behind = phasedSeeds.min { $0.phase < $1.phase }!
        let ahead = phasedSeeds.max { $0.phase < $1.phase }!
        let seedBehind = behind.seed
        let seedAhead = ahead.seed
        let t = RenderCache.textureBucketSeconds - ahead.phase + 0.001

        XCTAssertEqual(RenderCache.textureBucket(for: t + behind.phase), 0)
        XCTAssertEqual(RenderCache.textureBucket(for: t + ahead.phase), 1)

        let firstBehind = cache.textureGeometry(
            family: .organicBlob,
            seed: seedBehind,
            spec: spec,
            profileKey: 5_000,
            time: t,
            radiiAtCanonicalTime: { _ in self.radii() })
        // Inserting the ahead seed's entry (a later bucket) is what triggers
        // the prune.
        _ = cache.textureGeometry(
            family: .organicBlob,
            seed: seedAhead,
            spec: spec,
            profileKey: 5_000,
            time: t,
            radiiAtCanonicalTime: { _ in self.radii() })

        // Different radii on the re-query: an eviction would show up as a
        // freshly regenerated (and therefore different) result.
        let secondBehind = cache.textureGeometry(
            family: .organicBlob,
            seed: seedBehind,
            spec: spec,
            profileKey: 5_000,
            time: t,
            radiiAtCanonicalTime: { _ in self.radii(complexity: 0.9) })

        XCTAssertEqual(firstBehind, secondBehind,
                       "The phased-behind seed's entry must survive the phased-ahead seed's prune")
    }
}

@MainActor
final class CircleTextureTests: XCTestCase {
    func testCircleLegacyFillStyleGoldenSeeds() {
        XCTAssertEqual(
            CircleShapeRenderer.FillStyle(seed: 0),
            .init(isSolid: true, opacityMul: 0.85))
        XCTAssertEqual(CircleShapeRenderer.FillStyle(seed: 8).isSolid, false)
        XCTAssertEqual(
            CircleShapeRenderer.FillStyle(seed: 0x780).opacityMul,
            1.0,
            accuracy: 1e-12)
    }

    func testEveryTextureKindBuildsCircleGeometry() {
        let radii = [Double](repeating: 1, count: 48)
        for kind in TextureKind.allCases {
            let spec = TextureSpec(
                kind: kind, density: 0.7, uniformity: 0.4, angle: 1)
            let geometry = ProceduralTexture.geometry(
                spec: spec, radii: radii, seed: 7)
            switch kind {
            case .flat, .gradient, .outline:
                XCTAssertEqual(geometry, TextureGeometry())
            case .rings:
                XCTAssertFalse(geometry.rings.isEmpty)
            case .hatch:
                XCTAssertFalse(geometry.lines.isEmpty)
            }
        }
    }
}

@MainActor
final class HistoryThumbnailCacheVersionTests: XCTestCase {
    func testStoredThumbnailUsesVersionSixCacheKey() throws {
        let dayKey = "task6-cache-version-\(UUID().uuidString)"
        let cacheDirectory = URL.cachesDirectory
            .appending(path: "HistoryThumbnails", directoryHint: .isDirectory)
        defer {
            HistoryThumbnailCache.shared.invalidate(dayKey: dayKey)
        }

        let image = UIGraphicsImageRenderer(size: CGSize(width: 1, height: 1)).image {
            $0.cgContext.setFillColor(UIColor.red.cgColor)
            $0.cgContext.fill(CGRect(x: 0, y: 0, width: 1, height: 1))
        }
        HistoryThumbnailCache.shared.store(
            image,
            dayKey: dayKey,
            size: CGSize(width: 11, height: 13),
            theme: .night)

        let filenames = try FileManager.default.contentsOfDirectory(
            atPath: cacheDirectory.path)
        XCTAssertTrue(filenames.contains("\(dayKey)_11x13_night_v6.png"))
        XCTAssertFalse(filenames.contains("\(dayKey)_11x13_night_v5.png"))
    }
}
