# Canvas: Procedural Texture & Day Composition — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make each day's canvas read as a distinct generative work rather than a scatter of similar glowing shapes — by giving forms procedural fills (uniform and graded), and by deriving one composition, palette and texture policy per day so the canvas is internally coherent and structurally different from every other day.

**Architecture:** Three seed-driven primitives (`SimplexNoise2D`, `PoissonDiscSampler`, `SeededRNG.derived`) feed two new systems. `ProceduralTexture` fills a contour five different ways — flat, gradient, rings, hatch, stipple — each with a uniformity parameter so the same fill can be even or strongly graded. `DayComposition` derives an archetype, palette, contrast key and texture policy from the day itself, and every element obeys it. No new contour families, no new rendering technology, no third-party dependencies.

**Tech Stack:** Swift 6, SwiftUI `Canvas`, XCTest, existing `SeededRNG` (SplitMix64), existing `ProceduralShapeGenerator`, iOS Simulator `iPhone 17`.

## Design Position

Recorded so a later reader does not relitigate it:

- **The idiom is digital art, not painting.** Additive rendering (`plusLighter`, radial gradients falling to alpha 0) stays. Nothing here imitates pigment, occlusion, or brush edges.
- **Variety comes from fills, not from outlines.** The four shipped shape families stay as they are. What changes is what happens *inside* a form.
- **Uniqueness lives one level up.** Randomising per-element parameters produces numerically vast but perceptually identical output — every canvas ends up the same kind of picture with different numbers. Randomising the *rule* (which archetype, which palette, which texture mix) is what makes days differ.
- **Arithmetic:** 6 archetypes x 5 palette roots x 3 contrast keys x texture policies gives roughly 90 perceptually distinct kinds of picture from the shapes that already ship.

## Global Constraints

- No new persisted fields on `CanvasElement`. The JSON schema does not change, so no migration is needed and old canvases keep decoding. `DayComposition` is derived from `dayKey`, never stored.
- `CanvasColorPalette.seededSecondColor(seed:primary:)` must NOT change. It runs in `init(from:)` for every element saved without `hexColor2`, so any change to it silently repaints history.
- `CanvasElement.basePosition` and `size` are persisted per element. Placement and sizing changes therefore affect **only newly spawned elements**.
- Contour and fill changes DO affect historical canvases — geometry is regenerated from `shapeSeed` on every render. Accepted: position, size and colour are unchanged, and archival PNGs already exist via `CanvasStorageService`. Tasks 2 and 4 each carry a visual-verification step before commit.
- Performance budget (`CanvasLab-Spec.md` §16): no shape may exceed 200 contour points, and 15 clustered elements must hold ≥18 fps.
- **Textures are geometry, generated once and cached — never per frame.** Animation moves and fades a cached texture; it does not regenerate it. This is the single rule that keeps the budget.
- No Metal in the texture system. Metal shaders render blank under `ImageRenderer`, which would break wallpaper export and history thumbnails. Everything here is `Canvas`/Core Graphics and exports intact.
- Every generator stays pure: no `Date()`, no `UserDefaults`, no `UIScreen`, no global RNG. Everything that changes the result arrives as an argument.
- Any collection feeding geometry must be explicitly sorted. Swift randomises hash seeds per process, so `Set`/`Dictionary` iteration order differs between launches.
- Tests use XCTest and `@testable import Steps4`, matching every file in `Steps4Tests/`.

---

## File Structure

**Primitives**
- Create `StepsTrader/Utilities/SimplexNoise.swift`: deterministic 2D simplex noise + fbm.
- Create `StepsTrader/Utilities/PoissonDiscSampler.swift`: incremental Bridson sampling, weighted by a density field. Used both for element placement and for stipple fills.
- Modify `StepsTrader/Utilities/SeededRNG.swift`: add `derived(from:domain:)` for stream separation.

**Form**
- Modify `StepsTrader/Shapes/OrganicBlobShapeGenerator.swift`: swap sine-sum internals for simplex; expose normalised radii so textures can reuse the contour.

**Texture**
- Create `StepsTrader/Shapes/ProceduralTexture.swift`: the five fills and their cached geometry.
- Modify `StepsTrader/Shapes/OrganicBlobShapeRenderer.swift`: draw through `ProceduralTexture` instead of a hardcoded radial gradient.
- Modify `StepsTrader/Views/Canvas/CanvasRenderCache.swift`: add the texture cache.

**Composition**
- Create `StepsTrader/Models/DayComposition.swift`: archetype, palette, contrast key, texture policy — derived from the day.
- Modify `StepsTrader/Models/CanvasElement.swift`: seed-driven `spawn` that consults `DayComposition`; delete `findOpenPosition`.
- Modify `StepsTrader/Views/GalleryView.swift`: pass the day's composition into spawn and reroll.

**Tests**
- Create `Steps4Tests/SimplexNoiseTests.swift`
- Create `Steps4Tests/PoissonDiscSamplerTests.swift`
- Create `Steps4Tests/ProceduralTextureTests.swift`
- Create `Steps4Tests/DayCompositionTests.swift`

**Order: 1 → 2 → 3 → 4 → 5 → 6.** Each task ends green and committable. Tasks 4, 5 and 6 are each independently revertible.

**Run the full canvas suite after every task:**

```bash
xcodebuild test -project Steps4.xcodeproj -scheme Steps4 \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:Steps4Tests 2>&1 | tail -30
```

---

### Task 1: Seeded Simplex Noise

**Files:**
- Modify: `StepsTrader/Utilities/SeededRNG.swift`
- Create: `StepsTrader/Utilities/SimplexNoise.swift`
- Test: `Steps4Tests/SimplexNoiseTests.swift`

**Interfaces:**
- Consumes: `SeededRNG(seed:)`, `SeededRNG.nextInt(in:)` (existing).
- Produces:
  - `SeededRNG.derived(from seed: UInt64, domain: StaticString) -> SeededRNG`
  - `SimplexNoise2D(seed: UInt64)`
  - `SimplexNoise2D.value(_ x: Double, _ y: Double) -> Double` — approximately `[-1, 1]`
  - `SimplexNoise2D.fbm(_ x: Double, _ y: Double, octaves: Int, persistence: Double, lacunarity: Double) -> Double`

- [ ] **Step 1: Write the failing tests**

Create `Steps4Tests/SimplexNoiseTests.swift`:

```swift
import XCTest
import SwiftUI
@testable import Steps4

/// `SimplexNoise2D` is the shared source of coherent randomness: contour
/// deformation, texture density fields, and composition weighting all draw on
/// it. Two properties matter — reproducible from its seed, and correlated
/// between neighbouring samples.
final class SimplexNoiseTests: XCTestCase {

    // MARK: - Stream separation

    func testDerivedStreamsWithDifferentDomainsDiverge() {
        var a = SeededRNG.derived(from: 12345, domain: "shape")
        var b = SeededRNG.derived(from: 12345, domain: "placement")
        XCTAssertNotEqual(a.next(), b.next(), "Domains must isolate streams")
    }

    func testDerivedStreamIsReproducible() {
        var a = SeededRNG.derived(from: 999, domain: "texture")
        var b = SeededRNG.derived(from: 999, domain: "texture")
        XCTAssertEqual(
            (0..<8).map { _ in a.next() },
            (0..<8).map { _ in b.next() }
        )
    }

    // MARK: - Determinism

    func testSameSeedProducesIdenticalField() {
        let a = SimplexNoise2D(seed: 0xDEADBEEF)
        let b = SimplexNoise2D(seed: 0xDEADBEEF)
        for i in 0..<200 {
            let x = Double(i) * 0.137
            let y = Double(i) * -0.211
            XCTAssertEqual(a.value(x, y), b.value(x, y), accuracy: 0)
        }
    }

    func testDifferentSeedsProduceDifferentFields() {
        let a = SimplexNoise2D(seed: 1)
        let b = SimplexNoise2D(seed: 2)
        let differences = (0..<100).filter { i in
            abs(a.value(Double(i) * 0.31, 0.5) - b.value(Double(i) * 0.31, 0.5)) > 1e-9
        }
        XCTAssertGreaterThan(differences.count, 80)
    }

    func testSeedZeroIsValid() {
        XCTAssertTrue(SimplexNoise2D(seed: 0).value(1.5, 2.5).isFinite)
    }

    // MARK: - Range
    //
    // The 70.0 scaling constant is empirical, so the field can overshoot unity
    // very slightly. 1.05 is the tolerance every caller is written against.

    func testValueStaysWithinUnitRange() {
        let noise = SimplexNoise2D(seed: 42)
        for i in 0..<5_000 {
            let x = Double(i) * 0.0173
            let y = Double(i) * 0.0291 - 40
            let v = noise.value(x, y)
            XCTAssertGreaterThanOrEqual(v, -1.05, "Out of range at \(x),\(y)")
            XCTAssertLessThanOrEqual(v, 1.05, "Out of range at \(x),\(y)")
        }
    }

    func testFbmStaysWithinUnitRange() {
        let noise = SimplexNoise2D(seed: 7)
        for i in 0..<2_000 {
            let x = Double(i) * 0.023
            let v = noise.fbm(x, x * 0.7, octaves: 2, persistence: 0.45, lacunarity: 2.0)
            XCTAssertGreaterThanOrEqual(v, -1.05)
            XCTAssertLessThanOrEqual(v, 1.05)
        }
    }

    // MARK: - Continuity

    func testNeighbouringSamplesAreCorrelated() {
        let noise = SimplexNoise2D(seed: 314)
        var maxJump = 0.0
        for i in 0..<1_000 {
            let x = Double(i) * 0.05
            maxJump = max(maxJump, abs(noise.value(x, 3.0) - noise.value(x + 0.001, 3.0)))
        }
        XCTAssertLessThan(maxJump, 0.05, "A 0.001 step must not swing the field")
    }

    func testFieldIsNotConstant() {
        let noise = SimplexNoise2D(seed: 55)
        let samples = (0..<500).map { noise.value(Double($0) * 0.19, 1.7) }
        XCTAssertGreaterThan(samples.max()! - samples.min()!, 0.8)
    }

    func testNegativeCoordinatesBehave() {
        let noise = SimplexNoise2D(seed: 88)
        for i in 1...500 {
            let v = noise.value(Double(-i) * 0.37, Double(-i) * 0.11)
            XCTAssertTrue(v.isFinite)
            XCTAssertGreaterThanOrEqual(v, -1.05)
            XCTAssertLessThanOrEqual(v, 1.05)
        }
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

```bash
xcodebuild test -project Steps4.xcodeproj -scheme Steps4 \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:Steps4Tests/SimplexNoiseTests 2>&1 | tail -20
```

Expected: compile failure — `cannot find 'SimplexNoise2D' in scope`.

- [ ] **Step 3: Add `derived` to `SeededRNG`**

Append inside `struct SeededRNG` in `StepsTrader/Utilities/SeededRNG.swift`, after `nextInt(in:)`:

```swift
    /// A child generator isolated from the parent's call order.
    ///
    /// Without this, every consumer of a seed draws from one shared sequence:
    /// adding a single `next()` anywhere shifts everything downstream and every
    /// saved canvas regenerates differently. Giving each aspect — `"shape"`,
    /// `"placement"`, `"texture"`, `"palette"` — its own domain makes the
    /// streams independent, so a new parameter can be added without disturbing
    /// the rest.
    static func derived(from seed: UInt64, domain: StaticString) -> SeededRNG {
        let prime: UInt64 = 0x0000_0100_0000_01B3
        var hash: UInt64 = 0xCBF2_9CE4_8422_2325
        domain.withUTF8Buffer { bytes in
            for byte in bytes {
                hash ^= UInt64(byte)
                hash &*= prime
            }
        }
        return SeededRNG(seed: seed ^ hash)
    }
```

- [ ] **Step 4: Write `SimplexNoise2D`**

Create `StepsTrader/Utilities/SimplexNoise.swift`:

```swift
import Foundation

/// Deterministic 2D simplex noise (Gustavson's formulation).
///
/// Unlike a sum of sines with per-sample random phase, neighbouring samples
/// here are correlated — which is what makes a generated contour or a texture
/// density field read as structured rather than as noise. The permutation
/// table is built from a `SeededRNG` shuffle, so the whole field is
/// reproducible from one `UInt64`.
///
/// The 2D simplex patent (US 6867776) expired in 2022; there are no licensing
/// constraints on this construction.
///
/// Reference: Stefan Gustavson, "Simplex noise demystified" (2005).
struct SimplexNoise2D {

    private let perm: [Int]        // 512 entries; perm[i] == perm[i & 255]
    private let permMod12: [Int]

    /// The twelve 3D gradients of the classic construction, projected to 2D by
    /// dropping z. Several collapse into duplicates — that is the standard
    /// behaviour and keeps the `% 12` indexing intact.
    private static let gradients: [(Double, Double)] = [
        (1, 1), (-1, 1), (1, -1), (-1, -1),
        (1, 0), (-1, 0), (1, 0), (-1, 0),
        (0, 1), (0, -1), (0, 1), (0, -1),
    ]

    private static let f2 = 0.5 * (3.0.squareRoot() - 1.0)
    private static let g2 = (3.0 - 3.0.squareRoot()) / 6.0

    init(seed: UInt64) {
        var rng = SeededRNG(seed: seed)
        var source = Array(0..<256)
        // Fisher-Yates, same pattern as CanvasColorPalette.seededColorTriple.
        for i in stride(from: 255, through: 1, by: -1) {
            source.swapAt(i, rng.nextInt(in: 0...i))
        }

        var perm = [Int](repeating: 0, count: 512)
        var permMod12 = [Int](repeating: 0, count: 512)
        for i in 0..<512 {
            perm[i] = source[i & 255]
            permMod12[i] = perm[i] % 12
        }
        self.perm = perm
        self.permMod12 = permMod12
    }

    /// Noise value in approximately `[-1, 1]`.
    func value(_ x: Double, _ y: Double) -> Double {
        let skew = (x + y) * Self.f2
        let i = Int(floor(x + skew))
        let j = Int(floor(y + skew))

        let unskew = Double(i + j) * Self.g2
        let x0 = x - (Double(i) - unskew)
        let y0 = y - (Double(j) - unskew)

        let (i1, j1) = x0 > y0 ? (1, 0) : (0, 1)

        let x1 = x0 - Double(i1) + Self.g2
        let y1 = y0 - Double(j1) + Self.g2
        let x2 = x0 - 1.0 + 2.0 * Self.g2
        let y2 = y0 - 1.0 + 2.0 * Self.g2

        let ii = i & 255
        let jj = j & 255
        let g0 = permMod12[ii + perm[jj]]
        let g1 = permMod12[ii + i1 + perm[jj + j1]]
        let g2i = permMod12[ii + 1 + perm[jj + 1]]

        // 70.0 scales the three-corner sum into [-1, 1].
        return 70.0 * (contribution(x0, y0, g0)
            + contribution(x1, y1, g1)
            + contribution(x2, y2, g2i))
    }

    /// Fractal Brownian motion — stacked octaves, normalised back to `[-1, 1]`.
    func fbm(
        _ x: Double,
        _ y: Double,
        octaves: Int = 2,
        persistence: Double = 0.45,
        lacunarity: Double = 2.0
    ) -> Double {
        var total = 0.0
        var amplitude = 1.0
        var frequency = 1.0
        var normaliser = 0.0

        for _ in 0..<max(1, octaves) {
            total += value(x * frequency, y * frequency) * amplitude
            normaliser += amplitude
            amplitude *= persistence
            frequency *= lacunarity
        }
        return total / normaliser
    }

    private func contribution(_ x: Double, _ y: Double, _ gradientIndex: Int) -> Double {
        var falloff = 0.5 - x * x - y * y
        guard falloff > 0 else { return 0 }
        falloff *= falloff
        let g = Self.gradients[gradientIndex]
        return falloff * falloff * (g.0 * x + g.1 * y)
    }
}
```

- [ ] **Step 5: Add both new files to the Xcode targets**

`SimplexNoise.swift` → `Steps4`; `SimplexNoiseTests.swift` → `Steps4Tests`. Verify:

```bash
xcodebuild build -project Steps4.xcodeproj -scheme Steps4 \
  -destination 'platform=iOS Simulator,name=iPhone 17' 2>&1 | tail -5
```

Expected: `BUILD SUCCEEDED`.

- [ ] **Step 6: Run the tests to verify they pass**

```bash
xcodebuild test -project Steps4.xcodeproj -scheme Steps4 \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:Steps4Tests/SimplexNoiseTests 2>&1 | tail -20
```

Expected: all 10 tests PASS.

- [ ] **Step 7: Commit**

```bash
git add StepsTrader/Utilities/SimplexNoise.swift StepsTrader/Utilities/SeededRNG.swift Steps4Tests/SimplexNoiseTests.swift Steps4.xcodeproj
git commit -m "feat: add seeded 2D simplex noise and derived RNG streams"
```

---

### Task 2: Coherent Organic Blob Contour

**Files:**
- Modify: `StepsTrader/Shapes/OrganicBlobShapeGenerator.swift:23-59`
- Test: `Steps4Tests/SimplexNoiseTests.swift` (extend)

**Interfaces:**
- Consumes: `SimplexNoise2D` (Task 1), `ProceduralShapeGenerator.smoothClosedPath(through:)` (existing).
- Produces:
  - `ProceduralShapeGenerator.organicBlobPath(seed:complexity:symmetry:time:in:) -> Path` — **signature unchanged**, so the three call sites (`OrganicBlobShapeRenderer.swift:111`, `CanvasShapePreview.swift:229`, `ShapeIconCache.swift:159`) need no edits.
  - `ProceduralShapeGenerator.organicBlobRadiusFactor(seed:complexity:symmetry:time:) -> [Double]` — normalised radii, `1.0` = circle. Task 4 reuses this to build ring textures without duplicating the contour maths.

Today `generateOrganicBlob` draws a fresh `rng.nextDouble` phase **inside the loop over contour points**, so point *i* and *i+1* are uncorrelated: the result is dithered, not organic. Sampling a single simplex field along a ring fixes it and is periodic in θ for free — the ring closes on itself, so there is no seam.

- [ ] **Step 1: Write the failing tests**

Append to `Steps4Tests/SimplexNoiseTests.swift`:

```swift
// MARK: - Organic blob contour

final class OrganicBlobContourTests: XCTestCase {

    private let rect = CGRect(x: 0, y: 0, width: 200, height: 200)

    func testRadiiAreReproducibleFromSeed() {
        let a = ProceduralShapeGenerator.organicBlobRadiusFactor(
            seed: 4242, complexity: 0.5, symmetry: 1, time: 0)
        let b = ProceduralShapeGenerator.organicBlobRadiusFactor(
            seed: 4242, complexity: 0.5, symmetry: 1, time: 0)
        XCTAssertEqual(a, b)
    }

    func testDifferentSeedsGiveDifferentContours() {
        let a = ProceduralShapeGenerator.organicBlobRadiusFactor(
            seed: 1, complexity: 0.5, symmetry: 1, time: 0)
        let b = ProceduralShapeGenerator.organicBlobRadiusFactor(
            seed: 2, complexity: 0.5, symmetry: 1, time: 0)
        XCTAssertNotEqual(a, b)
    }

    /// The star-shaped guarantee. While every radius stays positive the contour
    /// cannot self-intersect, which is why no clean-up pass is needed — and why
    /// textures can safely clip to it.
    func testRadiiStayPositiveAcrossTheParameterSpace() {
        for seed in stride(from: UInt64(0), to: 400, by: 7) {
            for complexityStep in 0...10 {
                let complexity = Double(complexityStep) / 10.0
                let radii = ProceduralShapeGenerator.organicBlobRadiusFactor(
                    seed: seed, complexity: complexity, symmetry: 1, time: 0)
                XCTAssertGreaterThan(radii.min() ?? 0, 0.5,
                                     "seed \(seed) complexity \(complexity)")
                XCTAssertLessThan(radii.max() ?? 99, 1.5)
            }
        }
    }

    /// The regression this task exists to fix. The old sine-sum generator drew
    /// a fresh random phase per point, so adjacent radii could differ by the
    /// full amplitude — around 1.0. 0.25 is comfortably below that and
    /// comfortably above what a correctly sampled ring produces.
    func testAdjacentRadiiAreCorrelated() {
        for seed in stride(from: UInt64(0), to: 200, by: 11) {
            let radii = ProceduralShapeGenerator.organicBlobRadiusFactor(
                seed: seed, complexity: 1.0, symmetry: 1, time: 0)
            for i in radii.indices {
                XCTAssertLessThan(
                    abs(radii[i] - radii[(i + 1) % radii.count]), 0.25,
                    "Discontinuity at point \(i) of seed \(seed)")
            }
        }
    }

    func testContourIsSeamlessAtTheWrapPoint() {
        for seed in stride(from: UInt64(0), to: 200, by: 11) {
            let radii = ProceduralShapeGenerator.organicBlobRadiusFactor(
                seed: seed, complexity: 0.8, symmetry: 1, time: 0)
            XCTAssertLessThan(abs(radii.first! - radii.last!), 0.25,
                              "Seam at seed \(seed)")
        }
    }

    func testTimeMorphsTheContourGraduallyNotAbruptly() {
        let t0 = ProceduralShapeGenerator.organicBlobRadiusFactor(
            seed: 31337, complexity: 0.6, symmetry: 1, time: 0)
        let t1 = ProceduralShapeGenerator.organicBlobRadiusFactor(
            seed: 31337, complexity: 0.6, symmetry: 1, time: 1)
        let t100 = ProceduralShapeGenerator.organicBlobRadiusFactor(
            seed: 31337, complexity: 0.6, symmetry: 1, time: 100)

        let oneSecond = zip(t0, t1).map { abs($0 - $1) }.max() ?? 0
        XCTAssertGreaterThan(oneSecond, 0, "The contour must actually animate")
        XCTAssertLessThan(oneSecond, 0.05, "One second must not jump the shape")

        let longRun = zip(t0, t100).map { abs($0 - $1) }.max() ?? 0
        XCTAssertGreaterThan(longRun, 0.05, "Over 100s it must visibly morph")
    }

    /// Averaged over seeds: a single seed can pair a quiet patch of the field
    /// with the higher amplitude and invert the comparison.
    func testComplexityIncreasesDeviationFromACircle() {
        func deviation(_ complexity: Double) -> Double {
            let perSeed = stride(from: UInt64(0), to: 300, by: 13).map { seed -> Double in
                let radii = ProceduralShapeGenerator.organicBlobRadiusFactor(
                    seed: seed, complexity: complexity, symmetry: 1, time: 0)
                return radii.map { abs($0 - 1.0) }.reduce(0, +) / Double(radii.count)
            }
            return perSeed.reduce(0, +) / Double(perSeed.count)
        }
        XCTAssertLessThan(deviation(0.0), deviation(1.0))
    }

    func testPointCountStaysWithinThePerformanceBudget() {
        // CanvasLab-Spec §16: no shape may exceed 200 points, and the organic
        // blob renderer stacks 4 layers per element.
        let radii = ProceduralShapeGenerator.organicBlobRadiusFactor(
            seed: 1, complexity: 1.0, symmetry: 1, time: 0)
        XCTAssertLessThanOrEqual(radii.count * 4, 200)
    }

    func testPathIsNonEmptyAndBounded() {
        let path = ProceduralShapeGenerator.organicBlobPath(
            seed: 909, complexity: 0.5, symmetry: 1, time: 0, in: rect)
        XCTAssertFalse(path.isEmpty)
        // Max radius factor 1.32 around a centre of 100 with radius 100.
        XCTAssertTrue(rect.insetBy(dx: -40, dy: -40).contains(path.boundingRect))
    }

    func testSymmetryFoldingStillMirrors() {
        let radii = ProceduralShapeGenerator.organicBlobRadiusFactor(
            seed: 606, complexity: 0.7, symmetry: 6, time: 0)
        let sector = radii.count / 6
        for i in 0..<sector {
            XCTAssertEqual(radii[i], radii[i + sector], accuracy: 1e-9,
                           "Sector \(i) did not mirror")
        }
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

```bash
xcodebuild test -project Steps4.xcodeproj -scheme Steps4 \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:Steps4Tests/OrganicBlobContourTests 2>&1 | tail -20
```

Expected: `type 'ProceduralShapeGenerator' has no member 'organicBlobRadiusFactor'`.

- [ ] **Step 3: Replace the generator internals**

Replace the whole body of `StepsTrader/Shapes/OrganicBlobShapeGenerator.swift`:

```swift
import SwiftUI

// MARK: - Organic Blob Path Generator

extension ProceduralShapeGenerator {

    /// Contour points per blob. Four layers are stacked per element, so this
    /// times four must stay under the 200-point budget in CanvasLab-Spec §16.
    static let blobPointCount = 48

    /// How fast the sampling ring travels through the noise field, in noise
    /// units per second. Slow enough that a blob never appears to twitch.
    private static let blobTimeDrift = 0.012

    static func organicBlobPath(
        seed: UInt64,
        complexity: Double = 0.5,
        symmetry: Int = 1,
        time: Double = 0,
        in rect: CGRect
    ) -> Path {
        let factors = organicBlobRadiusFactor(
            seed: seed, complexity: complexity, symmetry: symmetry, time: time
        )
        return closedPath(
            radii: factors,
            center: CGPoint(x: rect.midX, y: rect.midY),
            radius: Double(min(rect.width, rect.height)) / 2
        )
    }

    /// A closed contour from normalised radii. Shared with the ring texture,
    /// which draws the same contour at successively smaller radii.
    static func closedPath(radii: [Double], center: CGPoint, radius: Double) -> Path {
        var points = [CGPoint]()
        points.reserveCapacity(radii.count)
        for (i, factor) in radii.enumerated() {
            let angle = (Double(i) / Double(radii.count)) * 2 * .pi
            points.append(CGPoint(
                x: Double(center.x) + cos(angle) * radius * factor,
                y: Double(center.y) + sin(angle) * radius * factor
            ))
        }
        return smoothClosedPath(through: points)
    }

    /// Normalised radius per contour point, where `1.0` is a perfect circle.
    ///
    /// A single simplex field is sampled along a ring in noise space. Because
    /// the ring closes on itself the result is exactly periodic in θ — no seam
    /// — and because neighbouring θ map to neighbouring points in the field,
    /// the contour is smooth by construction. Time translates the ring through
    /// the field, morphing the shape without ever repeating.
    ///
    /// Amplitude is capped so the factor stays well above zero: a strictly
    /// positive radius makes the contour star-shaped, and a star-shaped contour
    /// cannot self-intersect.
    static func organicBlobRadiusFactor(
        seed: UInt64,
        complexity: Double,
        symmetry: Int,
        time: Double
    ) -> [Double] {
        let sym = max(1, min(symmetry, 12))
        let count = max(blobPointCount, sym * 8)
        let clamped = min(max(complexity, 0), 1)

        let noise = SimplexNoise2D(seed: seed)

        // Ring radius sets how many lobes fit around the circumference, and is
        // capped by the sampling rate: the arc between adjacent samples must
        // stay small enough that the second octave (2x the base frequency)
        // does not alias, which would reintroduce exactly the point-to-point
        // jitter this change removes. More detail comes from octaves, not a
        // bigger ring.
        //
        // These three numbers were calibrated empirically, not derived: the
        // measured worst-case delta between adjacent radii over seeds 0..<500
        // x complexity 0.0...1.0 is 0.1933, against the 0.25 the contour test
        // asserts. Changing any of them requires re-running that sweep.
        // Measured lobe structure at these values: 3-6 lobes at complexity 0,
        // 5-9 at complexity 1 — still a blob, not a circle.
        let ringRadius = 0.6 + clamped * 0.4      // 0.6 … 1.0
        let amplitude = 0.12 + clamped * 0.20     // max 0.32 → factor ∈ [0.68, 1.32]

        let driftX = time * blobTimeDrift
        let driftY = time * blobTimeDrift * 0.7

        var factors = [Double]()
        factors.reserveCapacity(count)

        for i in 0..<count {
            let angle = (Double(i) / Double(count)) * 2 * .pi

            var sampleAngle = angle
            if sym > 1 {
                let sector = (2 * .pi) / Double(sym)
                let local = angle.truncatingRemainder(dividingBy: sector)
                sampleAngle = local > sector / 2 ? sector - local : local
            }

            let sx = cos(sampleAngle) * ringRadius + driftX
            let sy = sin(sampleAngle) * ringRadius + driftY
            // Two octaves, not three: a third would sit at 4x the base
            // frequency, past the ring's sampling rate, and would alias. The
            // low persistence keeps even the second octave's contribution
            // small for the same reason — see the calibration note above.
            let n = noise.fbm(sx, sy, octaves: 2, persistence: 0.2, lacunarity: 2.0)

            factors.append(1.0 + n * amplitude)
        }
        return factors
    }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

```bash
xcodebuild test -project Steps4.xcodeproj -scheme Steps4 \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:Steps4Tests/OrganicBlobContourTests 2>&1 | tail -20
```

Expected: all 11 tests PASS.

- [ ] **Step 5: Run the whole canvas suite for regressions**

```bash
xcodebuild test -project Steps4.xcodeproj -scheme Steps4 \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:Steps4Tests 2>&1 | tail -30
```

Expected: no new failures.

- [ ] **Step 6: Verify visually and measure frame rate**

This step gates the commit — the contour of every historical canvas changes here.

On the booted `iPhone 17` simulator, add three or four happenings with the Organic shape enabled. Confirm: contours are smooth and lobed rather than dithered; the morph over ~30 seconds is continuous with no popping; a blob never pinches to a point.

Then fill a canvas to 15 elements and check Instruments → Animation Hitches. Budget is ≥18 fps. Point count went from 12 to 40 per layer, so this is the measurement that matters. If it drops below 18, lower `blobPointCount` to 32 and re-run steps 4 and 5.

- [ ] **Step 7: Commit**

```bash
git add StepsTrader/Shapes/OrganicBlobShapeGenerator.swift Steps4Tests/SimplexNoiseTests.swift
git commit -m "feat: draw organic blobs from a simplex field instead of per-point sine jitter"
```

---

### Task 3: Weighted Poisson-Disc Sampler

**Files:**
- Create: `StepsTrader/Utilities/PoissonDiscSampler.swift`
- Test: `Steps4Tests/PoissonDiscSamplerTests.swift`

**Interfaces:**
- Consumes: `SeededRNG`, `SeededRNG.nextDouble()`, `.nextDouble(in:)`, `.nextCGFloat(in:)` (existing).
- Produces:
  - `PoissonDiscSampler.nextPoint(existing:bounds:minDistance:weight:using:) -> CGPoint` — one more well-spaced point, biased by a density field. Task 6 passes the archetype's weight function here.
  - `PoissonDiscSampler.fill(bounds:minDistance:maxPoints:weight:using:) -> [CGPoint]` — a whole set at once. Task 4's stipple texture uses this.

The `weight` closure is what makes one sampler serve both jobs: for element placement it carries the composition archetype, for stipple it carries the density gradient across a form.

- [ ] **Step 1: Write the failing tests**

Create `Steps4Tests/PoissonDiscSamplerTests.swift`:

```swift
import XCTest
@testable import Steps4

/// Replaces `CanvasElement.findOpenPosition`, which used rejection sampling
/// against the global RNG: it clumped on busy canvases and gave a different
/// layout on every run. The weight closure additionally lets a composition
/// archetype bias where mass lands.
final class PoissonDiscSamplerTests: XCTestCase {

    private let bounds = CGRect(x: 0.12, y: 0.12, width: 0.76, height: 0.76)

    private func distance(_ a: CGPoint, _ b: CGPoint) -> Double {
        Double(hypot(a.x - b.x, a.y - b.y))
    }

    // MARK: - Determinism

    func testSameSeedGivesSamePoint() {
        var rngA = SeededRNG(seed: 1234)
        var rngB = SeededRNG(seed: 1234)
        let existing = [CGPoint(x: 0.3, y: 0.3), CGPoint(x: 0.7, y: 0.6)]

        let a = PoissonDiscSampler.nextPoint(
            existing: existing, bounds: bounds, minDistance: 0.2,
            weight: { _ in 1 }, using: &rngA)
        let b = PoissonDiscSampler.nextPoint(
            existing: existing, bounds: bounds, minDistance: 0.2,
            weight: { _ in 1 }, using: &rngB)
        XCTAssertEqual(a, b)
    }

    /// Callers pass `dayCanvas.elements.map(\.basePosition)`, whose order can
    /// vary after a sync merge. Layout must not depend on it.
    func testResultIsIndependentOfInputOrder() {
        let existing = [
            CGPoint(x: 0.2, y: 0.8), CGPoint(x: 0.5, y: 0.3),
            CGPoint(x: 0.8, y: 0.5), CGPoint(x: 0.35, y: 0.65),
        ]
        var rngA = SeededRNG(seed: 99)
        var rngB = SeededRNG(seed: 99)

        let a = PoissonDiscSampler.nextPoint(
            existing: existing, bounds: bounds, minDistance: 0.18,
            weight: { _ in 1 }, using: &rngA)
        let b = PoissonDiscSampler.nextPoint(
            existing: existing.reversed(), bounds: bounds, minDistance: 0.18,
            weight: { _ in 1 }, using: &rngB)
        XCTAssertEqual(a, b)
    }

    func testDifferentSeedsGiveDifferentPoints() {
        var rngA = SeededRNG(seed: 1)
        var rngB = SeededRNG(seed: 2)
        let a = PoissonDiscSampler.nextPoint(
            existing: [CGPoint(x: 0.5, y: 0.5)], bounds: bounds,
            minDistance: 0.2, weight: { _ in 1 }, using: &rngA)
        let b = PoissonDiscSampler.nextPoint(
            existing: [CGPoint(x: 0.5, y: 0.5)], bounds: bounds,
            minDistance: 0.2, weight: { _ in 1 }, using: &rngB)
        XCTAssertNotEqual(a, b)
    }

    // MARK: - Bounds

    func testFirstPointLandsInsideBounds() {
        for seed in UInt64(0)..<50 {
            var rng = SeededRNG(seed: seed)
            let p = PoissonDiscSampler.nextPoint(
                existing: [], bounds: bounds, minDistance: 0.25,
                weight: { _ in 1 }, using: &rng)
            XCTAssertTrue(bounds.contains(p), "First point \(p) escaped")
        }
    }

    func testEveryPointLandsInsideBounds() {
        var rng = SeededRNG(seed: 7)
        var placed: [CGPoint] = []
        for _ in 0..<25 {
            let p = PoissonDiscSampler.nextPoint(
                existing: placed, bounds: bounds, minDistance: 0.2,
                weight: { _ in 1 }, using: &rng)
            XCTAssertTrue(bounds.contains(p), "Point \(p) escaped")
            placed.append(p)
        }
    }

    // MARK: - Spacing

    func testSpacingIsRespectedWhileThereIsRoom() {
        var rng = SeededRNG(seed: 3)
        var placed: [CGPoint] = []
        let minDistance = 0.16

        // Five points fit comfortably in a 0.76-square at this spacing, so the
        // sampler should never need a relaxed round.
        for _ in 0..<5 {
            let p = PoissonDiscSampler.nextPoint(
                existing: placed, bounds: bounds,
                minDistance: minDistance, weight: { _ in 1 }, using: &rng)
            for other in placed {
                XCTAssertGreaterThanOrEqual(
                    distance(p, other), minDistance * 0.99,
                    "\(p) landed too close to \(other)")
            }
            placed.append(p)
        }
    }

    /// The property that motivates the change: rejection sampling clumps
    /// because a rejected candidate is retried at random; Bridson grows
    /// outward from what is already placed.
    func testDistributionIsMoreEvenThanUniformRandom() {
        var rng = SeededRNG(seed: 11)
        var poisson: [CGPoint] = []
        for _ in 0..<12 {
            poisson.append(PoissonDiscSampler.nextPoint(
                existing: poisson, bounds: bounds, minDistance: 0.2,
                weight: { _ in 1 }, using: &rng))
        }

        var uniformRng = SeededRNG(seed: 11)
        let uniform = (0..<12).map { _ in
            CGPoint(x: uniformRng.nextCGFloat(in: bounds.minX...bounds.maxX),
                    y: uniformRng.nextCGFloat(in: bounds.minY...bounds.maxY))
        }

        func smallestGap(_ points: [CGPoint]) -> Double {
            var smallest = Double.infinity
            for i in points.indices {
                for j in (i + 1)..<points.count {
                    smallest = min(smallest, distance(points[i], points[j]))
                }
            }
            return smallest
        }

        XCTAssertGreaterThan(smallestGap(poisson), smallestGap(uniform))
    }

    // MARK: - Weighting

    /// The archetype hook. A field that favours the left half must actually
    /// pull the layout left.
    func testWeightBiasesPlacement() {
        var rng = SeededRNG(seed: 17)
        var placed: [CGPoint] = []
        for _ in 0..<10 {
            placed.append(PoissonDiscSampler.nextPoint(
                existing: placed, bounds: bounds, minDistance: 0.14,
                weight: { $0.x < 0.5 ? 1.0 : 0.05 }, using: &rng))
        }
        let leftCount = placed.filter { $0.x < 0.5 }.count
        XCTAssertGreaterThan(leftCount, 6, "Weight did not bias placement: \(placed)")
    }

    func testZeroWeightEverywhereStillReturnsAnInBoundsPoint() {
        var rng = SeededRNG(seed: 23)
        let p = PoissonDiscSampler.nextPoint(
            existing: [CGPoint(x: 0.5, y: 0.5)], bounds: bounds,
            minDistance: 0.2, weight: { _ in 0 }, using: &rng)
        XCTAssertTrue(bounds.contains(p))
    }

    // MARK: - Saturation

    func testSaturatedCanvasStillReturnsAnInBoundsPoint() {
        var placed: [CGPoint] = []
        for row in 0..<6 {
            for col in 0..<6 {
                placed.append(CGPoint(
                    x: bounds.minX + bounds.width * (Double(col) + 0.5) / 6,
                    y: bounds.minY + bounds.height * (Double(row) + 0.5) / 6))
            }
        }
        var rng = SeededRNG(seed: 5)
        let p = PoissonDiscSampler.nextPoint(
            existing: placed, bounds: bounds, minDistance: 0.3,
            weight: { _ in 1 }, using: &rng)
        XCTAssertTrue(bounds.contains(p))
    }

    func testSaturatedFallbackPicksTheRoomiestSpot() {
        let placed = (0..<10).map { i in
            CGPoint(x: 0.15 + Double(i % 3) * 0.02, y: 0.15 + Double(i / 3) * 0.02)
        }
        let clusterCentre = CGPoint(
            x: placed.map(\.x).reduce(0, +) / CGFloat(placed.count),
            y: placed.map(\.y).reduce(0, +) / CGFloat(placed.count))

        var rng = SeededRNG(seed: 21)
        let p = PoissonDiscSampler.nextPoint(
            existing: placed, bounds: bounds, minDistance: 0.5,
            weight: { _ in 1 }, using: &rng)

        XCTAssertGreaterThan(distance(p, clusterCentre), 0.3,
                             "Fallback \(p) hugged the cluster")
    }

    // MARK: - Bulk fill (stipple)

    func testFillRespectsMaxPoints() {
        var rng = SeededRNG(seed: 31)
        let points = PoissonDiscSampler.fill(
            bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
            minDistance: 0.05, maxPoints: 40,
            weight: { _ in 1 }, using: &rng)
        XCTAssertLessThanOrEqual(points.count, 40)
        XCTAssertGreaterThan(points.count, 10, "Should find plenty of room")
    }

    func testFillIsReproducible() {
        var rngA = SeededRNG(seed: 41)
        var rngB = SeededRNG(seed: 41)
        let unit = CGRect(x: 0, y: 0, width: 1, height: 1)
        let a = PoissonDiscSampler.fill(bounds: unit, minDistance: 0.08,
                                        maxPoints: 30, weight: { _ in 1 }, using: &rngA)
        let b = PoissonDiscSampler.fill(bounds: unit, minDistance: 0.08,
                                        maxPoints: 30, weight: { _ in 1 }, using: &rngB)
        XCTAssertEqual(a, b)
    }

    func testFillRespectsSpacing() {
        var rng = SeededRNG(seed: 51)
        let points = PoissonDiscSampler.fill(
            bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
            minDistance: 0.1, maxPoints: 50, weight: { _ in 1 }, using: &rng)
        for i in points.indices {
            for j in (i + 1)..<points.count {
                XCTAssertGreaterThanOrEqual(distance(points[i], points[j]), 0.09)
            }
        }
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

```bash
xcodebuild test -project Steps4.xcodeproj -scheme Steps4 \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:Steps4Tests/PoissonDiscSamplerTests 2>&1 | tail -20
```

Expected: `cannot find 'PoissonDiscSampler' in scope`.

- [ ] **Step 3: Write the sampler**

Create `StepsTrader/Utilities/PoissonDiscSampler.swift`:

```swift
import CoreGraphics
import Foundation

/// Incremental Poisson-disc sampling, adapted from Bridson's algorithm.
///
/// Two entry points, one algorithm. `nextPoint` adds a single well-spaced
/// point — the shape the canvas needs, since it gains one element per tap.
/// `fill` produces a whole set at once, which is what a stipple texture needs.
///
/// Both take a `weight` field in `0...1`. It biases *where* points prefer to
/// land without ever hard-excluding a region, so a composition archetype or a
/// texture density gradient can be expressed as one closure.
enum PoissonDiscSampler {

    /// Candidates drawn around each anchor before moving on. Sampling happens
    /// once per tap or once per cached texture, so a generous count costs
    /// nothing and keeps the relaxed fallback rounds rare.
    private static let candidatesPerAnchor = 20

    /// Spacing is relaxed by this factor per round when the region is full.
    private static let relaxationFactor = 0.75
    private static let relaxationRounds = 3

    /// The first point sits near the middle, jittered by this fraction of the
    /// bounds so an opening element is not pinned dead centre.
    private static let firstPointJitter = 0.25

    /// How strongly `weight` competes with spacing. A candidate's score is
    /// `clearance * (weightFloor + (1 - weightFloor) * weight)`, so a
    /// zero-weight region is heavily discouraged but never impossible.
    private static let weightFloor = 0.05

    /// One more point respecting `minDistance` from `existing`, clamped to
    /// `bounds` and biased by `weight`. Never fails: if the region is
    /// saturated it relaxes the spacing, and failing that returns the
    /// best-scoring candidate it saw.
    static func nextPoint(
        existing: [CGPoint],
        bounds: CGRect,
        minDistance: Double,
        weight: (CGPoint) -> Double,
        using rng: inout SeededRNG
    ) -> CGPoint {
        guard !existing.isEmpty else {
            return firstPoint(in: bounds, weight: weight, using: &rng)
        }

        // Callers pass element positions whose array order can shift after a
        // sync merge. Sorting makes the layout independent of that order.
        let anchors = existing.sorted {
            $0.y == $1.y ? $0.x < $1.x : $0.y < $1.y
        }

        var bestFallback = CGPoint(x: bounds.midX, y: bounds.midY)
        var bestScore = -1.0

        for round in 0..<relaxationRounds {
            let radius = minDistance * pow(relaxationFactor, Double(round))
            var bestAccepted: CGPoint?
            var bestAcceptedScore = -1.0

            for anchor in anchors {
                for _ in 0..<candidatesPerAnchor {
                    let candidate = annulusCandidate(
                        around: anchor, radius: radius, using: &rng)
                    guard bounds.contains(candidate) else { continue }

                    let clearance = anchors
                        .map { Double(hypot($0.x - candidate.x, $0.y - candidate.y)) }
                        .min() ?? .infinity
                    let score = clearance * biased(weight(candidate))

                    if clearance >= radius, score > bestAcceptedScore {
                        bestAcceptedScore = score
                        bestAccepted = candidate
                    }
                    if score > bestScore {
                        bestScore = score
                        bestFallback = candidate
                    }
                }
            }

            // Take the best-weighted candidate of this round rather than the
            // first that clears the radius — that is what lets `weight`
            // actually steer the layout.
            if let accepted = bestAccepted { return accepted }
        }
        return bestFallback
    }

    /// A whole set of well-spaced points. Used by the stipple texture, where
    /// `weight` carries the density gradient across the form.
    static func fill(
        bounds: CGRect,
        minDistance: Double,
        maxPoints: Int,
        weight: (CGPoint) -> Double,
        using rng: inout SeededRNG
    ) -> [CGPoint] {
        guard maxPoints > 0 else { return [] }
        var points = [firstPoint(in: bounds, weight: weight, using: &rng)]

        // Frontier of points still worth growing from — the active list in
        // Bridson's formulation.
        var active = [0]

        while !active.isEmpty, points.count < maxPoints {
            let activeIndex = active.count - 1
            let anchor = points[active[activeIndex]]
            var placed = false

            for _ in 0..<candidatesPerAnchor {
                let candidate = annulusCandidate(
                    around: anchor, radius: minDistance, using: &rng)
                guard bounds.contains(candidate) else { continue }

                let clearance = points
                    .map { Double(hypot($0.x - candidate.x, $0.y - candidate.y)) }
                    .min() ?? .infinity
                guard clearance >= minDistance else { continue }

                // Weight thins the field rather than gating it, so a low-weight
                // region ends up sparse instead of empty.
                guard rng.nextDouble() < biased(weight(candidate)) else { continue }

                points.append(candidate)
                active.append(points.count - 1)
                placed = true
                break
            }

            if !placed { active.remove(at: activeIndex) }
        }
        return points
    }

    // MARK: - Helpers

    private static func biased(_ weight: Double) -> Double {
        let clamped = min(max(weight, 0), 1)
        return weightFloor + (1 - weightFloor) * clamped
    }

    private static func firstPoint(
        in bounds: CGRect,
        weight: (CGPoint) -> Double,
        using rng: inout SeededRNG
    ) -> CGPoint {
        var best = CGPoint(x: bounds.midX, y: bounds.midY)
        var bestScore = -1.0
        for _ in 0..<candidatesPerAnchor {
            let candidate = CGPoint(
                x: bounds.midX + CGFloat(rng.nextDouble(in: -1...1))
                    * bounds.width * firstPointJitter,
                y: bounds.midY + CGFloat(rng.nextDouble(in: -1...1))
                    * bounds.height * firstPointJitter
            )
            guard bounds.contains(candidate) else { continue }
            let score = biased(weight(candidate))
            if score > bestScore {
                bestScore = score
                best = candidate
            }
        }
        return best
    }

    private static func annulusCandidate(
        around anchor: CGPoint,
        radius: Double,
        using rng: inout SeededRNG
    ) -> CGPoint {
        let angle = rng.nextDouble(in: 0...(2 * .pi))
        // Annulus [radius, 2*radius) — the Bridson construction.
        let reach = radius * (1.0 + rng.nextDouble())
        return CGPoint(
            x: anchor.x + CGFloat(cos(angle) * reach),
            y: anchor.y + CGFloat(sin(angle) * reach)
        )
    }
}
```

- [ ] **Step 4: Add both files to their Xcode targets**

`PoissonDiscSampler.swift` → `Steps4`; `PoissonDiscSamplerTests.swift` → `Steps4Tests`.

- [ ] **Step 5: Run the tests to verify they pass**

```bash
xcodebuild test -project Steps4.xcodeproj -scheme Steps4 \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:Steps4Tests/PoissonDiscSamplerTests 2>&1 | tail -20
```

Expected: all 14 tests PASS.

- [ ] **Step 6: Commit**

```bash
git add StepsTrader/Utilities/PoissonDiscSampler.swift Steps4Tests/PoissonDiscSamplerTests.swift Steps4.xcodeproj
git commit -m "feat: add weighted Poisson-disc sampler for placement and stipple"
```

---

### Task 4: Procedural Textures

**Files:**
- Create: `StepsTrader/Shapes/ProceduralTexture.swift`
- Modify: `StepsTrader/Views/Canvas/CanvasRenderCache.swift`
- Modify: `StepsTrader/Shapes/OrganicBlobShapeRenderer.swift:91-157`
- Modify: `StepsTrader/Views/GenerativeCanvasView.swift:414` — the sole caller of `OrganicBlobShapeRenderer.draw`, which gains the new `cache:` argument. `ShapeIconCache` and `CanvasShapePreview` are NOT touched: they call `organicBlobPath` directly and draw their own gradients.
- Test: `Steps4Tests/ProceduralTextureTests.swift`

**Interfaces:**
- Consumes: `SimplexNoise2D` (Task 1), `ProceduralShapeGenerator.organicBlobRadiusFactor` and `.closedPath(radii:center:radius:)` (Task 2), `PoissonDiscSampler.fill` (Task 3), `SeededRNG.derived` (Task 1).
- Produces:
  - `TextureKind` — `flat`, `gradient`, `rings`, `hatch`, `stipple`
  - `TextureSpec(kind:density:uniformity:angle:)` — `Codable`, `Hashable`
  - `TextureSpec.seeded(kind:seed:) -> TextureSpec`
  - `TextureGeometry` — the cacheable output: `rings: [[Double]]`, `lines: [TextureGeometry.Line]`, `dots: [TextureGeometry.Dot]`
  - `ProceduralTexture.geometry(spec:radii:seed:) -> TextureGeometry` — pure, in unit space
  - `ProceduralTexture.draw(_:spec:in:context:center:radius:color:color2:opacity:)`
  - `RenderCache.textureCache: [TextureCacheKey: TextureGeometry]`

Every form currently gets the same radial gradient, which is why a canvas reads as one repeated object. Five fills, each with a `uniformity` knob, give forms that are flat, graded, ringed, hatched or stippled — evenly or strongly graded.

**Geometry is generated in unit space and cached.** The renderer scales it per frame. This is what keeps textures off the per-frame budget.

- [ ] **Step 1: Write the failing tests**

Create `Steps4Tests/ProceduralTextureTests.swift`:

```swift
import XCTest
import SwiftUI
@testable import Steps4

/// Fills are the axis of visual variety: same contours, different interiors.
/// Everything here is geometry in unit space — colour and scale are applied at
/// draw time, so one cached texture serves every size.
final class ProceduralTextureTests: XCTestCase {

    private func radii(seed: UInt64 = 1) -> [Double] {
        ProceduralShapeGenerator.organicBlobRadiusFactor(
            seed: seed, complexity: 0.5, symmetry: 1, time: 0)
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
        for kind: TextureKind in [.rings, .hatch, .stipple] {
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
        XCTAssertTrue(g.dots.isEmpty)
    }

    func testGradientProducesNoSubGeometry() {
        let g = ProceduralTexture.geometry(
            spec: .seeded(kind: .gradient, seed: 1), radii: radii(), seed: 1)
        XCTAssertTrue(g.rings.isEmpty)
        XCTAssertTrue(g.lines.isEmpty)
        XCTAssertTrue(g.dots.isEmpty)
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
        let g = ProceduralTexture.geometry(
            spec: .seeded(kind: .hatch, seed: 19), radii: radii(), seed: 19)
        // Unit space: the contour never exceeds a factor of 1.32.
        for line in g.lines {
            XCTAssertLessThanOrEqual(hypot(line.start.x, line.start.y), 1.4)
            XCTAssertLessThanOrEqual(hypot(line.end.x, line.end.y), 1.4)
        }
    }

    func testStippleDotsStayInsideTheContour() {
        let g = ProceduralTexture.geometry(
            spec: .seeded(kind: .stipple, seed: 23), radii: radii(), seed: 23)
        XCTAssertGreaterThan(g.dots.count, 10)

        let contour = radii()
        for dot in g.dots {
            let angle = atan2(Double(dot.center.y), Double(dot.center.x))
            let normalised = angle < 0 ? angle + 2 * .pi : angle
            let index = Int(normalised / (2 * .pi) * Double(contour.count))
                % contour.count
            XCTAssertLessThanOrEqual(
                Double(hypot(dot.center.x, dot.center.y)), contour[index] + 0.01,
                "Dot at \(dot.center) escaped the contour")
        }
    }

    func testStippleDotRadiiArePositive() {
        let g = ProceduralTexture.geometry(
            spec: .seeded(kind: .stipple, seed: 29), radii: radii(), seed: 29)
        for dot in g.dots { XCTAssertGreaterThan(dot.radius, 0) }
    }

    // MARK: - Uniformity
    //
    // "Однородные и нет": the same fill must be able to read as even or as
    // strongly graded across the form.

    func testUniformStippleIsEvenlySpread() {
        let spec = TextureSpec(kind: .stipple, density: 0.7, uniformity: 1.0, angle: 0)
        let g = ProceduralTexture.geometry(spec: spec, radii: radii(), seed: 33)
        let left = g.dots.filter { $0.center.x < 0 }.count
        let right = g.dots.count - left
        XCTAssertLessThan(abs(left - right), max(4, g.dots.count / 3),
                          "Uniform stipple should not favour a side")
    }

    func testGradedStippleIsLopsided() {
        // Averaged over seeds: one field can happen to be flat.
        var lopsidedCount = 0
        var trials = 0
        for seed in stride(from: UInt64(0), to: 300, by: 17) {
            let spec = TextureSpec(kind: .stipple, density: 0.7,
                                   uniformity: 0.0, angle: 0)
            let g = ProceduralTexture.geometry(spec: spec, radii: radii(), seed: seed)
            guard g.dots.count > 12 else { continue }
            trials += 1
            let left = g.dots.filter { $0.center.x < 0 }.count
            let imbalance = abs(Double(left) - Double(g.dots.count) / 2)
            if imbalance > Double(g.dots.count) / 6 { lopsidedCount += 1 }
        }
        XCTAssertGreaterThan(trials, 5)
        XCTAssertGreaterThan(lopsidedCount, trials / 3,
                             "Graded stipple never developed a density gradient")
    }

    func testDensityDrivesCount() {
        func dotCount(_ density: Double) -> Int {
            let spec = TextureSpec(kind: .stipple, density: density,
                                   uniformity: 1.0, angle: 0)
            return ProceduralTexture.geometry(spec: spec, radii: radii(), seed: 61)
                .dots.count
        }
        XCTAssertLessThan(dotCount(0.2), dotCount(0.9))
    }

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
                XCTAssertLessThanOrEqual(g.dots.count, 90, "\(kind) dots")
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
```

- [ ] **Step 2: Run the tests to verify they fail**

```bash
xcodebuild test -project Steps4.xcodeproj -scheme Steps4 \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:Steps4Tests/ProceduralTextureTests 2>&1 | tail -20
```

Expected: `cannot find 'TextureKind' in scope`.

- [ ] **Step 3: Write the texture system**

Create `StepsTrader/Shapes/ProceduralTexture.swift`:

```swift
import SwiftUI

// MARK: - Kind

/// How the inside of a form is filled.
///
/// Every element used to get the same radial gradient, which is why a full
/// canvas read as one object repeated. These five give a canvas forms that are
/// flat, graded, ringed, hatched or stippled — and `TextureSpec.uniformity`
/// lets each of them read as even or as strongly graded across the form.
enum TextureKind: String, Codable, CaseIterable, Hashable {
    case flat       // solid colour, no falloff — the contrast anchor
    case gradient   // the existing radial falloff
    case rings      // concentric copies of the contour, stroked
    case hatch      // parallel lines clipped to the contour
    case stipple    // Poisson dot field inside the contour
}

// MARK: - Spec

/// Parameters of a fill. Doubles as a cache key, so its `Hashable` conformance
/// quantises: raw `Double` equality would miss the cache on every slider tick.
struct TextureSpec: Codable, Hashable {
    var kind: TextureKind
    /// How much of the fill there is — line count, dot count, ring count.
    var density: Double
    /// `1` = even across the form, `0` = strongly graded by a noise field.
    var uniformity: Double
    /// Direction, used by `hatch` and by the gradient's offset.
    var angle: Double

    init(kind: TextureKind, density: Double, uniformity: Double, angle: Double) {
        self.kind = kind
        self.density = min(max(density, 0), 1)
        self.uniformity = min(max(uniformity, 0), 1)
        self.angle = angle.truncatingRemainder(dividingBy: 2 * .pi)
            + (angle < 0 ? 2 * .pi : 0)
    }

    /// Sensible randomised parameters for a kind.
    static func seeded(kind: TextureKind, seed: UInt64) -> TextureSpec {
        var rng = SeededRNG.derived(from: seed, domain: "texture")
        return TextureSpec(
            kind: kind,
            density: rng.nextDouble(in: 0.3...1.0),
            uniformity: rng.nextDouble(in: 0.0...1.0),
            angle: rng.nextDouble(in: 0...(2 * .pi))
        )
    }

    // Quantise to 1e-4 so cache lookups survive floating-point drift.
    private var quantised: [Int] {
        [Int((density * 10_000).rounded()),
         Int((uniformity * 10_000).rounded()),
         Int((angle * 10_000).rounded())]
    }

    static func == (lhs: TextureSpec, rhs: TextureSpec) -> Bool {
        lhs.kind == rhs.kind && lhs.quantised == rhs.quantised
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(kind)
        hasher.combine(quantised)
    }
}

// MARK: - Geometry

/// The cacheable output of a fill, in **unit space**: the contour's radius is
/// `1.0`, so one cached texture serves the icon, the canvas and a 4K export.
struct TextureGeometry: Hashable {
    /// Normalised radii per nested ring, outermost first.
    var rings: [[Double]] = []
    /// Hatch segments, unit space.
    var lines: [Line] = []
    /// Stipple dots: centre and radius, unit space.
    var dots: [Dot] = []

    struct Line: Hashable {
        var start: CGPoint
        var end: CGPoint
    }

    struct Dot: Hashable {
        var center: CGPoint
        var radius: Double
    }
}

// MARK: - Generator

enum ProceduralTexture {

    // Budget ceilings, enforced by ProceduralTextureTests.
    private static let maxDots = 90
    private static let maxLines = 40
    private static let maxRings = 8

    /// Pure. `radii` is the element's contour from
    /// `ProceduralShapeGenerator.organicBlobRadiusFactor`.
    static func geometry(
        spec: TextureSpec,
        radii: [Double],
        seed: UInt64
    ) -> TextureGeometry {
        switch spec.kind {
        case .flat, .gradient:
            return TextureGeometry()
        case .rings:
            return TextureGeometry(rings: ringGeometry(spec: spec, radii: radii))
        case .hatch:
            return TextureGeometry(lines: hatchGeometry(spec: spec, radii: radii, seed: seed))
        case .stipple:
            return TextureGeometry(dots: stippleGeometry(spec: spec, radii: radii, seed: seed))
        }
    }

    // MARK: Rings

    /// Concentric copies of the contour, each strictly inside the last.
    /// `uniformity` controls the spacing: even rings versus rings that bunch
    /// towards the edge.
    private static func ringGeometry(spec: TextureSpec, radii: [Double]) -> [[Double]] {
        let count = max(3, min(maxRings, Int((spec.density * Double(maxRings)).rounded())))
        var rings = [[Double]]()
        rings.reserveCapacity(count)

        for i in 0..<count {
            let t = Double(i + 1) / Double(count + 1)
            // Even spacing at uniformity 1, edge-weighted at 0.
            let eased = spec.uniformity * t + (1 - spec.uniformity) * (t * t)
            let scale = 1.0 - eased * 0.85     // never reaches the centre
            rings.append(radii.map { $0 * scale })
        }
        return rings
    }

    // MARK: Hatch

    /// Parallel chords across the contour at `spec.angle`. Each scanline is
    /// clipped to the contour by walking the radius at both ends, which works
    /// because the contour is star-shaped (Task 2 guarantees a positive radius).
    private static func hatchGeometry(
        spec: TextureSpec,
        radii: [Double],
        seed: UInt64
    ) -> [TextureGeometry.Line] {
        let count = max(4, min(maxLines, Int((spec.density * Double(maxLines)).rounded())))
        let noise = SimplexNoise2D(seed: seed)

        let cosA = cos(spec.angle)
        let sinA = sin(spec.angle)

        // Offsets span the inscribed circle, not the full contour. Every
        // scanline then has a real chord, so none is wasted — and staying
        // inside the smallest radius guarantees the line never pokes out of
        // the form, whatever the contour does at that angle.
        let inner = (radii.min() ?? 1) * 0.95

        var lines = [TextureGeometry.Line]()
        lines.reserveCapacity(count)

        for i in 0..<count {
            let t = (Double(i) + 0.5) / Double(count)
            let offset = (t * 2 - 1) * inner

            // uniformity 1 → every line drawn; 0 → the noise field drops some,
            // so the hatch thins out across the form. Only thin a hatch that
            // has lines to spare: below 8 the dropout would leave too few to
            // read as a fill at all.
            if spec.uniformity < 1, count > 8 {
                let keep = (noise.value(offset * 1.7, 0.5) + 1) / 2
                if keep < (1 - spec.uniformity) * 0.5 { continue }
            }

            let span = (inner * inner - offset * offset).squareRoot()

            // The perpendicular axis carries the offset; the line runs along
            // `spec.angle`.
            let baseX = -sinA * offset
            let baseY = cosA * offset
            lines.append(TextureGeometry.Line(
                start: CGPoint(x: baseX - cosA * span, y: baseY - sinA * span),
                end:   CGPoint(x: baseX + cosA * span, y: baseY + sinA * span)
            ))
        }
        return lines
    }

    // MARK: Stipple

    /// A Poisson dot field inside the contour. `uniformity` decides whether the
    /// density is even or driven by a noise gradient across the form.
    private static func stippleGeometry(
        spec: TextureSpec,
        radii: [Double],
        seed: UInt64
    ) -> [TextureGeometry.Dot] {
        var rng = SeededRNG.derived(from: seed, domain: "stipple")
        let noise = SimplexNoise2D(seed: seed &+ 0x57)

        // Denser spec → smaller spacing → more dots.
        let spacing = 0.34 - spec.density * 0.22        // 0.34 … 0.12
        let bounds = CGRect(x: -1, y: -1, width: 2, height: 2)

        // Containment only. Weighting the sampler does NOT produce a density
        // gradient: `fill` uses weight as a Bernoulli accept gate and runs to
        // exhaustion, so a rejected candidate is merely delayed, not removed,
        // and final density ends up governed by `minDistance`. The gradient has
        // to come from thinning the result afterwards.
        let raw = PoissonDiscSampler.fill(
            bounds: bounds,
            minDistance: spacing,
            maxPoints: maxDots,
            weight: { containsPoint($0, radii: radii) ? 1 : 0 },
            using: &rng
        )

        // Separate stream so the thinning cannot perturb the placement above.
        var thinRng = SeededRNG.derived(from: seed, domain: "stipple-thin")

        return raw
            .filter { containsPoint($0, radii: radii) }
            .compactMap { point -> TextureGeometry.Dot? in
                if spec.uniformity < 1 {
                    // A dot where the field is low survives rarely, one where
                    // it is high survives outright — this is what makes the
                    // fill bunch to one side.
                    //
                    // The frequency is 0.4, deliberately much lower than the
                    // 1.3 used elsewhere: the stipple domain is only ~2 units
                    // across, and at 1.3 several noise lobes fit inside each
                    // half of the form, so any split averages them out — over
                    // an 18-seed sweep that produced no visible bunching at
                    // all. At 0.4 a single lobe spans the whole form, which is
                    // what "graded across the form" actually means.
                    let n = (noise.value(Double(point.x) * 0.4, Double(point.y) * 0.4) + 1) / 2
                    let survive = spec.uniformity + (1 - spec.uniformity) * n
                    guard thinRng.nextDouble() < survive else { return nil }
                }
                // Dots shrink towards the rim so the fill has an interior.
                let distance = Double(hypot(point.x, point.y))
                let falloff = 1.0 - min(1.0, distance) * 0.55
                return TextureGeometry.Dot(
                    center: point,
                    radius: max(0.008, spacing * 0.28 * falloff)
                )
            }
    }

    /// Star-shaped containment test: compare the point's radius against the
    /// contour's radius at the point's angle.
    static func containsPoint(_ point: CGPoint, radii: [Double]) -> Bool {
        guard !radii.isEmpty else { return false }
        let angle = atan2(Double(point.y), Double(point.x))
        let normalised = angle < 0 ? angle + 2 * .pi : angle
        let index = Int(normalised / (2 * .pi) * Double(radii.count)) % radii.count
        return Double(hypot(point.x, point.y)) <= radii[index]
    }

    // MARK: - Drawing

    /// Draws a cached texture into a context. Scaling happens here, so one
    /// cached `TextureGeometry` serves every size.
    static func draw(
        _ geometry: TextureGeometry,
        spec: TextureSpec,
        contour: Path,
        radii: [Double],
        context: inout GraphicsContext,
        center: CGPoint,
        radius: Double,
        color: Color,
        color2: Color?,
        gradientCenter: CGPoint
    ) {
        let second = color2 ?? color

        switch spec.kind {
        case .flat:
            context.fill(contour, with: .color(color.opacity(0.72)))

        case .gradient:
            let stops = color2 == nil
                ? [color.opacity(0.8), color.opacity(0.3), color.opacity(0)]
                : [color.opacity(0.8), second.opacity(0.4), second.opacity(0)]
            context.fill(contour, with: .radialGradient(
                Gradient(colors: stops), center: gradientCenter,
                startRadius: 0, endRadius: radius))

        case .rings:
            // A soft base so the rings read as structure on a body, not as
            // floating outlines.
            context.fill(contour, with: .color(color.opacity(0.18)))
            for (index, ring) in geometry.rings.enumerated() {
                let path = ProceduralShapeGenerator.closedPath(
                    radii: ring, center: center, radius: radius)
                let fade = 1.0 - Double(index) / Double(max(1, geometry.rings.count)) * 0.5
                context.stroke(
                    path,
                    with: .color((index.isMultiple(of: 2) ? color : second)
                        .opacity(0.55 * fade)),
                    style: StrokeStyle(lineWidth: 1.2, lineCap: .round))
            }

        case .hatch:
            context.fill(contour, with: .color(color.opacity(0.14)))
            var strokes = Path()
            for line in geometry.lines {
                strokes.move(to: CGPoint(
                    x: center.x + line.start.x * radius,
                    y: center.y + line.start.y * radius))
                strokes.addLine(to: CGPoint(
                    x: center.x + line.end.x * radius,
                    y: center.y + line.end.y * radius))
            }
            context.stroke(strokes, with: .color(second.opacity(0.6)),
                           style: StrokeStyle(lineWidth: 1.3, lineCap: .round))

        case .stipple:
            context.fill(contour, with: .color(color.opacity(0.12)))
            // One accumulated Path, one fill — 90 separate fills would blow
            // the frame budget.
            var field = Path()
            for dot in geometry.dots {
                let r = dot.radius * radius
                field.addEllipse(in: CGRect(
                    x: center.x + dot.center.x * radius - r,
                    y: center.y + dot.center.y * radius - r,
                    width: r * 2, height: r * 2))
            }
            context.fill(field, with: .color(second.opacity(0.75)))
        }
    }
}
```

- [ ] **Step 4: Add the texture cache**

In `StepsTrader/Views/Canvas/CanvasRenderCache.swift`, add inside `final class RenderCache`:

```swift
    /// Textures are geometry, not per-frame work. A stipple fill runs a
    /// Poisson sample of up to 90 points; at 20 fps across 15 elements that
    /// would be ~27k samples a second. Generated once per bucket and reused.
    struct TextureCacheKey: Hashable {
        let seed: UInt64
        let spec: TextureSpec
        /// The contour morphs slowly (0.012 noise units per second), so the
        /// texture is generated against a time-quantised contour. One bucket
        /// per `bucketSeconds` — the texture lags the outline by well under a
        /// bucket, which is invisible at this drift rate.
        let timeBucket: Int
    }

    /// Seconds per texture bucket. Small enough that a texture never visibly
    /// detaches from its contour, large enough that regeneration is rare.
    static let textureBucketSeconds: Double = 1.5

    static func textureBucket(for time: Double) -> Int {
        Int((time / textureBucketSeconds).rounded(.down))
    }

    var textureCache: [TextureCacheKey: TextureGeometry] = [:]
    var textureCacheLastPruneBucket: Int = .min

    /// Cached lookup. Generates on miss.
    func textureGeometry(
        seed: UInt64,
        spec: TextureSpec,
        radii: [Double],
        time: Double
    ) -> TextureGeometry {
        let bucket = Self.textureBucket(for: time)
        let key = TextureCacheKey(seed: seed, spec: spec, timeBucket: bucket)
        if let hit = textureCache[key] { return hit }

        // Drop entries from older buckets so the cache cannot grow unbounded
        // over a long-running canvas.
        if bucket != textureCacheLastPruneBucket {
            textureCache = textureCache.filter { $0.key.timeBucket >= bucket - 1 }
            textureCacheLastPruneBucket = bucket
        }

        let geometry = ProceduralTexture.geometry(spec: spec, radii: radii, seed: seed)
        textureCache[key] = geometry
        return geometry
    }
```

Note `flat` and `gradient` return an empty `TextureGeometry`, so they cost a
dictionary lookup and nothing else — no need to special-case them.

- [ ] **Step 5: Route the organic blob renderer through the texture system**

In `StepsTrader/Shapes/OrganicBlobShapeRenderer.swift`, replace the body of the `for layer in 0..<layerCount` loop's drawing section. Keep the existing centre, radius, layer scaling, opacity and blur logic exactly as it is; replace only the path construction and the `context.drawLayer` contents:

```swift
            let layerRadii = ProceduralShapeGenerator.organicBlobRadiusFactor(
                seed: layerSeed, complexity: complexity, symmetry: symmetry, time: layerT)
            let path = ProceduralShapeGenerator.closedPath(
                radii: layerRadii,
                center: CGPoint(x: cx, y: cy),
                radius: Double(radius))

            // Only the front layer carries the texture; the halo layers stay
            // soft gradients, which is what keeps the glow.
            let layerSpec = layer == layerCount - 1
                ? spec
                : TextureSpec(kind: .gradient, density: spec.density,
                              uniformity: spec.uniformity, angle: spec.angle)

            // Cached, not regenerated per frame — see the Global Constraint.
            // The contour above is still computed every frame (it has to
            // morph); only the fill geometry is bucketed.
            let textureGeometry = cache.textureGeometry(
                seed: layerSeed, spec: layerSpec, radii: layerRadii, time: layerT)

            let gradCenter = CGPoint(
                x: cx + cos(gradOffsetAngle) * Double(radius) * gradOffsetFraction,
                y: cy + sin(gradOffsetAngle) * Double(radius) * gradOffsetFraction)

            context.drawLayer { ctx in
                ctx.blendMode = blendMode
                ctx.opacity = max(0.05, layerOpacity)

                ProceduralTexture.draw(
                    textureGeometry, spec: layerSpec, contour: path, radii: layerRadii,
                    context: &ctx, center: CGPoint(x: cx, y: cy), radius: Double(radius),
                    color: color, color2: isTwoColor ? color2 : nil,
                    gradientCenter: gradCenter)

                if blurRadius > 1 {
                    ctx.addFilter(.blur(radius: blurRadius))
                }

                let strokeColor = isTwoColor ? color2 : color
                ctx.stroke(path, with: .color(strokeColor.opacity(0.6)),
                           style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
            }
```

Add two parameters to `OrganicBlobShapeRenderer.draw(...)`:

- `spec: TextureSpec`, defaulting to `TextureSpec(kind: .gradient, density: 0.5, uniformity: 1, angle: 0)`. The default is a deliberate two-step: it keeps the three existing call sites compiling while this task lands, and Task 6 supplies the real per-element spec. Leave the default in place — Task 6 relies on `ShapeIconCache` and `CanvasShapePreview` continuing to render plain gradients, since an icon is too small to carry a texture.
- `cache: RenderCache`. Both `OrganicBlobShapeRenderer` and `RenderCache` are already `@MainActor`, so passing it is free. `GenerativeCanvasView` already holds the cache and passes it to other renderers — follow the same call pattern.

`OrganicBlobShapeRenderer.draw` has exactly **one** caller: `GenerativeCanvasView.swift:414`. `ShapeIconCache.swift:159` and `CanvasShapePreview.swift:229` call `ProceduralShapeGenerator.organicBlobPath` directly and do their own gradient drawing — they never touch the renderer. Leave both alone: they need neither the spec nor a cache, and an icon is too small to carry a texture anyway.

- [ ] **Step 6: Run the tests to verify they pass**

```bash
xcodebuild test -project Steps4.xcodeproj -scheme Steps4 \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:Steps4Tests/ProceduralTextureTests 2>&1 | tail -20
```

Expected: all 17 tests PASS.

- [ ] **Step 7: Run the whole suite and measure**

```bash
xcodebuild test -project Steps4.xcodeproj -scheme Steps4 \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:Steps4Tests 2>&1 | tail -30
```

Then, on the simulator, force each texture kind in turn by temporarily changing the default `spec` in `OrganicBlobShapeRenderer.draw`, fill a canvas to 15 elements and check Instruments → Animation Hitches for each. Budget ≥18 fps.

Stipple is the one at risk — it draws up to 90 ellipses per element. Confirm the accumulated-`Path` batching in `ProceduralTexture.draw` is in place; if it still hitches, drop `maxDots` to 60 and re-run step 7.

- [ ] **Step 8: Verify visually**

Look at each of the five fills on a real canvas. What matters: `flat` and `gradient` next to each other should read as genuinely different objects; `rings` should not moiré at small sizes; `hatch` should not disappear on small elements; `stipple` at `uniformity: 0` should visibly bunch to one side.

- [ ] **Step 9: Commit**

```bash
git add StepsTrader/Shapes/ProceduralTexture.swift StepsTrader/Shapes/OrganicBlobShapeRenderer.swift StepsTrader/Views/Canvas/CanvasRenderCache.swift Steps4Tests/ProceduralTextureTests.swift Steps4.xcodeproj
git commit -m "feat: add five procedural fills with a uniformity gradient"
```

---

### Task 5: Day Composition

**Files:**
- Create: `StepsTrader/Models/DayComposition.swift`
- Test: `Steps4Tests/DayCompositionTests.swift`

**Interfaces:**
- Consumes: `SeededRNG.derived` (Task 1), `SimplexNoise2D` (Task 1), `TextureKind` (Task 4), `CanvasColorPalette.paletteHex` (existing), `CanvasElement.makeSeed` (existing).
- Produces:
  - `CompositionArchetype` — `centeredMass`, `diagonalSweep`, `horizonBand`, `cornerWeight`, `twoMasses`, `constellation`
  - `CompositionArchetype.weight(at: CGPoint) -> Double` — the density field handed to `PoissonDiscSampler`
  - `CompositionArchetype.sizeMultiplier(rank:count:) -> Double`
  - `ContrastKey` — `low`, `mid`, `high`
  - `TexturePolicy(dominant:accent:accentShare:)`
  - `TexturePolicy.kind(forRank:) -> TextureKind`
  - `DayComposition.forDay(dayKey:happeningCount:) -> DayComposition`
  - `DayComposition.color(forRank:) -> String`
  - `DayComposition.opacityRange(forRank:) -> ClosedRange<Double>`

This is where uniqueness actually lives. A fixed rule applied identically gives every canvas the same skeleton; varying the rule per day is what makes days differ structurally rather than just numerically.

- [ ] **Step 1: Write the failing tests**

Create `Steps4Tests/DayCompositionTests.swift`:

```swift
import XCTest
@testable import Steps4

/// One composition per day, derived from the day. Everything an element does
/// — where it lands, how big it is, which colour, which fill — follows from
/// this, so a canvas reads as one work and two days read as different works.
final class DayCompositionTests: XCTestCase {

    // MARK: - Determinism

    func testCompositionIsReproducibleFromTheDayKey() {
        let a = DayComposition.forDay(dayKey: "2026-08-10", happeningCount: 5)
        let b = DayComposition.forDay(dayKey: "2026-08-10", happeningCount: 5)
        XCTAssertEqual(a, b)
    }

    func testDifferentDaysGetDifferentCompositions() {
        let keys = (1...28).map { String(format: "2026-08-%02d", $0) }
        let archetypes = keys.map {
            DayComposition.forDay(dayKey: $0, happeningCount: 5).archetype
        }
        XCTAssertGreaterThan(Set(archetypes).count, 3,
                             "A month should not collapse to one archetype")
    }

    /// Adding a happening must not reshuffle the day's identity — the picture
    /// grows, it does not restart.
    func testArchetypeAndPaletteAreStableAsTheDayFills() {
        let first = DayComposition.forDay(dayKey: "2026-08-10", happeningCount: 1)
        for count in 2...10 {
            let later = DayComposition.forDay(dayKey: "2026-08-10", happeningCount: count)
            XCTAssertEqual(later.archetype, first.archetype, "at \(count)")
            XCTAssertEqual(later.palette, first.palette, "at \(count)")
            XCTAssertEqual(later.contrastKey, first.contrastKey, "at \(count)")
        }
    }

    func testAllArchetypesAreReachable() {
        var seen = Set<CompositionArchetype>()
        for day in 1...200 {
            seen.insert(DayComposition.forDay(
                dayKey: "2026-\(day % 12 + 1)-\(day % 28 + 1)",
                happeningCount: 5).archetype)
        }
        XCTAssertEqual(seen.count, CompositionArchetype.allCases.count,
                       "Unreachable archetypes: \(Set(CompositionArchetype.allCases).subtracting(seen))")
    }

    // MARK: - Weight fields

    func testEveryArchetypeProducesAUsableField() {
        for archetype in CompositionArchetype.allCases {
            var maxWeight = 0.0
            var minWeight = 1.0
            for xStep in 0...10 {
                for yStep in 0...10 {
                    let p = CGPoint(x: Double(xStep) / 10, y: Double(yStep) / 10)
                    let w = archetype.weight(at: p)
                    XCTAssertTrue((0...1).contains(w),
                                  "\(archetype) weight \(w) out of range at \(p)")
                    maxWeight = max(maxWeight, w)
                    minWeight = min(minWeight, w)
                }
            }
            XCTAssertGreaterThan(maxWeight, 0.6, "\(archetype) has no high ground")
        }
    }

    /// Constellation is the only even field. Every other archetype must
    /// actually concentrate mass somewhere — that is what makes it a
    /// composition rather than a scatter.
    func testNonConstellationArchetypesConcentrateMass() {
        for archetype in CompositionArchetype.allCases where archetype != .constellation {
            var weights = [Double]()
            for xStep in 0...10 {
                for yStep in 0...10 {
                    weights.append(archetype.weight(
                        at: CGPoint(x: Double(xStep) / 10, y: Double(yStep) / 10)))
                }
            }
            let spread = (weights.max() ?? 0) - (weights.min() ?? 0)
            XCTAssertGreaterThan(spread, 0.5, "\(archetype) field is too flat")
        }
    }

    func testConstellationIsEven() {
        var weights = [Double]()
        for xStep in 0...10 {
            for yStep in 0...10 {
                weights.append(CompositionArchetype.constellation.weight(
                    at: CGPoint(x: Double(xStep) / 10, y: Double(yStep) / 10)))
            }
        }
        XCTAssertLessThan((weights.max() ?? 0) - (weights.min() ?? 0), 0.2)
    }

    func testWeightFieldsAreDeterministic() {
        for archetype in CompositionArchetype.allCases {
            let p = CGPoint(x: 0.37, y: 0.62)
            XCTAssertEqual(archetype.weight(at: p), archetype.weight(at: p))
        }
    }

    // MARK: - Size hierarchy

    func testSizeMultipliersStayInRange() {
        for archetype in CompositionArchetype.allCases {
            for count in 1...15 {
                for rank in 0..<count {
                    let m = archetype.sizeMultiplier(rank: rank, count: count)
                    XCTAssertTrue((0.4...2.0).contains(m),
                                  "\(archetype) rank \(rank)/\(count) → \(m)")
                }
            }
        }
    }

    /// Centred mass means one dominant form; constellation means peers. The
    /// two must not produce the same size curve, or every canvas ends up with
    /// the same skeleton.
    func testArchetypesDifferInSizeCurve() {
        let centred = (0..<8).map {
            CompositionArchetype.centeredMass.sizeMultiplier(rank: $0, count: 8)
        }
        let constellation = (0..<8).map {
            CompositionArchetype.constellation.sizeMultiplier(rank: $0, count: 8)
        }
        func spread(_ v: [Double]) -> Double { (v.max() ?? 0) - (v.min() ?? 0) }
        XCTAssertGreaterThan(spread(centred), spread(constellation))
    }

    // MARK: - Palette

    func testPaletteIsSmallAndOnPalette() {
        for day in 1...60 {
            let composition = DayComposition.forDay(
                dayKey: "2026-03-\(day % 28 + 1)", happeningCount: 8)
            XCTAssertTrue((3...5).contains(composition.palette.count),
                          "Palette size \(composition.palette.count)")
            for hex in composition.palette {
                XCTAssertTrue(CanvasColorPalette.paletteHex.contains(hex),
                              "\(hex) is off-palette")
            }
            XCTAssertEqual(Set(composition.palette).count, composition.palette.count,
                           "Palette has duplicates")
        }
    }

    func testColourForRankCyclesThroughThePalette() {
        let composition = DayComposition.forDay(dayKey: "2026-08-10", happeningCount: 10)
        let used = Set((0..<10).map { composition.color(forRank: $0) })
        XCTAssertGreaterThan(used.count, 1, "A day must use more than one colour")
        for hex in used {
            XCTAssertTrue(composition.palette.contains(hex))
        }
    }

    // MARK: - Contrast

    func testContrastKeyShapesTheOpacityRange() {
        func range(_ key: ContrastKey) -> ClosedRange<Double> {
            var composition = DayComposition.forDay(dayKey: "2026-08-10", happeningCount: 5)
            composition.contrastKey = key
            return composition.opacityRange(forRank: 0)
        }
        XCTAssertLessThan(range(.low).upperBound - range(.low).lowerBound,
                          range(.high).upperBound - range(.high).lowerBound)
    }

    func testOpacityRangesStayRenderable() {
        for key in ContrastKey.allCases {
            var composition = DayComposition.forDay(dayKey: "2026-08-10", happeningCount: 5)
            composition.contrastKey = key
            for rank in 0..<12 {
                let range = composition.opacityRange(forRank: rank)
                XCTAssertGreaterThanOrEqual(range.lowerBound, 0.08)
                XCTAssertLessThanOrEqual(range.upperBound, 0.9)
                XCTAssertLessThan(range.lowerBound, range.upperBound)
            }
        }
    }

    // MARK: - Texture policy

    func testTexturePolicyMixesDominantAndAccent() {
        let policy = TexturePolicy(dominant: .gradient, accent: .hatch, accentShare: 0.3)
        let kinds = (0..<20).map { policy.kind(forRank: $0) }
        XCTAssertTrue(kinds.contains(.gradient))
        XCTAssertTrue(kinds.contains(.hatch))
        XCTAssertGreaterThan(kinds.filter { $0 == .gradient }.count,
                             kinds.filter { $0 == .hatch }.count,
                             "Dominant must dominate")
    }

    func testTexturePolicyIsDeterministic() {
        let policy = TexturePolicy(dominant: .stipple, accent: .flat, accentShare: 0.4)
        XCTAssertEqual((0..<20).map { policy.kind(forRank: $0) },
                       (0..<20).map { policy.kind(forRank: $0) })
    }

    func testDayPoliciesVaryAcrossTheMonth() {
        let policies = (1...28).map {
            DayComposition.forDay(dayKey: String(format: "2026-08-%02d", $0),
                                  happeningCount: 6).texturePolicy
        }
        XCTAssertGreaterThan(Set(policies.map(\.dominant)).count, 2,
                             "A month should not use one dominant fill")
    }

    func testAccentIsNeverTheDominant() {
        for day in 1...100 {
            let policy = DayComposition.forDay(
                dayKey: "2026-05-\(day % 28 + 1)", happeningCount: 6).texturePolicy
            XCTAssertNotEqual(policy.dominant, policy.accent)
        }
    }

    // MARK: - Codable

    func testCompositionRoundTrips() throws {
        let composition = DayComposition.forDay(dayKey: "2026-08-10", happeningCount: 7)
        let data = try JSONEncoder().encode(composition)
        XCTAssertEqual(try JSONDecoder().decode(DayComposition.self, from: data),
                       composition)
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

```bash
xcodebuild test -project Steps4.xcodeproj -scheme Steps4 \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:Steps4Tests/DayCompositionTests 2>&1 | tail -20
```

Expected: `cannot find 'DayComposition' in scope`.

- [ ] **Step 3: Write `DayComposition`**

Create `StepsTrader/Models/DayComposition.swift`:

```swift
import CoreGraphics
import Foundation

// MARK: - Archetype

/// The spatial schema of a canvas: where mass goes and how sizes relate.
///
/// This is what makes days differ. Randomising per-element parameters produces
/// numerically vast but perceptually identical output — every canvas ends up
/// the same kind of picture with different numbers. Varying the schema itself
/// is what produces structurally different work.
enum CompositionArchetype: String, Codable, CaseIterable, Hashable {
    case centeredMass    // one dominant form, satellites around it
    case diagonalSweep   // mass along a diagonal, two empty corners
    case horizonBand     // mass along a horizontal band, large empty above/below
    case cornerWeight    // weight in one corner, a long empty diagonal
    case twoMasses       // two groups in tension, emptiness between
    case constellation   // even scatter — one option among six, not the default

    /// Placement preference in `0...1` at a normalised canvas point. Handed
    /// straight to `PoissonDiscSampler` as its weight field.
    func weight(at point: CGPoint) -> Double {
        let x = Double(point.x)
        let y = Double(point.y)

        switch self {
        case .centeredMass:
            let d = hypot(x - 0.5, y - 0.5) / 0.707
            return clamp(1.0 - pow(d, 1.4))

        case .diagonalSweep:
            // Distance from the leading diagonal y = x.
            let d = abs(x - y) / 1.414
            return clamp(1.0 - pow(d / 0.42, 1.6))

        case .horizonBand:
            // A band slightly below centre reads better than dead middle.
            let d = abs(y - 0.58) / 0.30
            return clamp(1.0 - pow(d, 1.8))

        case .cornerWeight:
            // The peak sits near the corner and the falloff is tight. An
            // earlier draft used (0.26, 0.28) over a 0.95 normaliser, which
            // spread the high ground so broadly that dead-centre scored 0.72
            // against the true corner's 0.66 — the archetype did the opposite
            // of its name and correlated r~0.48 with centeredMass.
            let d = hypot(x - 0.18, y - 0.20) / 0.62
            return clamp(1.0 - pow(d, 1.1))

        case .twoMasses:
            let a = hypot(x - 0.30, y - 0.34) / 0.34
            let b = hypot(x - 0.72, y - 0.68) / 0.30
            return clamp(max(1.0 - pow(a, 1.5), 1.0 - pow(b, 1.5)))

        case .constellation:
            return 1.0
        }
    }

    /// Size multiplier by arrival order. Each archetype has its own curve —
    /// a centred mass has one dominant form, a constellation has peers.
    func sizeMultiplier(rank: Int, count: Int) -> Double {
        let total = max(1, count)
        let position = Double(rank) / Double(max(1, total - 1))   // 0…1

        switch self {
        case .centeredMass:
            // Steep: the first form leads, everything else is a satellite.
            return rank == 0 ? 1.75 : 0.62 + (1 - position) * 0.18

        case .diagonalSweep:
            // Graded along the sweep.
            return 1.35 - position * 0.65

        case .horizonBand:
            // Even along the band, with a couple of taller accents.
            return rank.isMultiple(of: 3) ? 1.25 : 0.85

        case .cornerWeight:
            // Convex decay, deliberately NOT a second straight ramp. An
            // earlier draft used `1.55 - position * 0.85`, which shares its
            // shape with diagonalSweep's line and converges on the same
            // endpoint — two of six archetypes producing one composition
            // skeleton, which defeats the reason archetypes exist. Guarded by
            // testCornerWeightDecaysRatherThanRamping, which measures
            // curvature (exactly 0 for any straight line, ~0.048 here).
            return 0.55 + 1.05 * pow(1 - position, 2.2)

        case .twoMasses:
            // Two leads, one per mass.
            return rank < 2 ? 1.45 : 0.70

        case .constellation:
            // Peers: a narrow spread is the point.
            return 1.05 - position * 0.25
        }
    }

    private func clamp(_ v: Double) -> Double { min(max(v, 0), 1) }
}

// MARK: - Contrast

/// How wide the day's opacity spread is. A low-key day is quiet and close in
/// value; a high-key day has strong darks and lights.
enum ContrastKey: String, Codable, CaseIterable, Hashable {
    case low, mid, high
}

// MARK: - Texture policy

/// Which fills a day uses. One dominant fill gives the canvas a signature; a
/// minority accent keeps it from being monotonous.
struct TexturePolicy: Codable, Hashable {
    var dominant: TextureKind
    var accent: TextureKind
    /// Fraction of elements that get the accent, `0...1`.
    var accentShare: Double

    init(dominant: TextureKind, accent: TextureKind, accentShare: Double) {
        self.dominant = dominant
        self.accent = accent
        // Capped at 0.45, not 1: above that the stride arithmetic in
        // `kind(forRank:)` saturates at every other element and the accent
        // stops being an accent.
        self.accentShare = min(max(accentShare, 0), 0.45)
    }

    /// Deterministic per-rank assignment. Spreads accents evenly rather than
    /// clustering them, which a per-element coin flip would not.
    func kind(forRank rank: Int) -> TextureKind {
        guard accentShare > 0 else { return dominant }
        let stride = max(2, Int((1.0 / accentShare).rounded()))
        return rank % stride == stride - 1 ? accent : dominant
    }
}

// MARK: - Composition

/// One composition per day, derived from the day. Never persisted — it is a
/// pure function of `dayKey`, so it survives reinstalls and syncs for free.
struct DayComposition: Codable, Hashable {
    var archetype: CompositionArchetype
    /// 3–5 hex colours, drawn from one region of the palette.
    var palette: [String]
    var contrastKey: ContrastKey
    var texturePolicy: TexturePolicy

    /// The day's identity. `happeningCount` is accepted so density decisions
    /// can respond to how full the day is, but archetype, palette and contrast
    /// deliberately ignore it: adding a happening must grow the picture, not
    /// restart it.
    ///
    /// Future hook: sleep and step fractions belong here too — a quiet day
    /// choosing a low-key, sparse composition is what would make the canvas a
    /// portrait of the day rather than decoration. Left out of this task so it
    /// stays testable without HealthKit.
    static func forDay(dayKey: String, happeningCount: Int) -> DayComposition {
        let seed = CanvasElement.makeSeed(optionId: "composition", dayKey: dayKey, index: 0)

        var archetypeRng = SeededRNG.derived(from: seed, domain: "archetype")
        let archetypes = CompositionArchetype.allCases   // CaseIterable order is stable
        let archetype = archetypes[archetypeRng.nextInt(in: 0...(archetypes.count - 1))]

        var contrastRng = SeededRNG.derived(from: seed, domain: "contrast")
        let keys = ContrastKey.allCases
        let contrastKey = keys[contrastRng.nextInt(in: 0...(keys.count - 1))]

        return DayComposition(
            archetype: archetype,
            palette: makePalette(seed: seed),
            contrastKey: contrastKey,
            texturePolicy: makeTexturePolicy(seed: seed)
        )
    }

    /// The colour for an element by arrival order. Cycling a small palette is
    /// what makes a canvas read as one work — independent sampling from all 29
    /// swatches is a sample, not a palette.
    func color(forRank rank: Int) -> String {
        palette[rank % palette.count]
    }

    /// Opacity range for an element, widened or narrowed by the contrast key.
    /// Early elements sit at the top of the range so the composition has
    /// something to read at a glance.
    func opacityRange(forRank rank: Int) -> ClosedRange<Double> {
        let spread: Double = switch contrastKey {
        case .low:  0.12
        case .mid:  0.26
        case .high: 0.42
        }
        let lead = rank < 2 ? 0.14 : 0.0
        let center = min(0.62, 0.30 + lead)
        return max(0.08, center - spread / 2)...min(0.9, center + spread / 2)
    }

    // MARK: - Derivation

    /// 3–5 colours from one contiguous stretch of `paletteHex`. The palette is
    /// already ordered by hue family, so a window over it is a hue-coherent
    /// selection without needing a colour-space conversion.
    private static func makePalette(seed: UInt64) -> [String] {
        var rng = SeededRNG.derived(from: seed, domain: "palette")
        let all = CanvasColorPalette.paletteHex
        let size = rng.nextInt(in: 3...5)
        // Window slightly wider than the palette size, so the picks inside it
        // are related but not simply consecutive.
        let window = min(all.count, size + 4)
        let start = rng.nextInt(in: 0...(all.count - window))

        var candidates = Array(all[start..<(start + window)])
        var picked = [String]()
        for _ in 0..<size {
            let index = rng.nextInt(in: 0...(candidates.count - 1))
            picked.append(candidates.remove(at: index))
        }
        return picked
    }

    private static func makeTexturePolicy(seed: UInt64) -> TexturePolicy {
        var rng = SeededRNG.derived(from: seed, domain: "texturePolicy")
        let kinds = TextureKind.allCases          // CaseIterable order is stable
        let dominant = kinds[rng.nextInt(in: 0...(kinds.count - 1))]
        var others = kinds.filter { $0 != dominant }
        let accent = others[rng.nextInt(in: 0...(others.count - 1))]
        return TexturePolicy(
            dominant: dominant,
            accent: accent,
            accentShare: rng.nextDouble(in: 0.15...0.4)
        )
    }
}
```

- [ ] **Step 4: Add both files to their Xcode targets**

`DayComposition.swift` → `Steps4`; `DayCompositionTests.swift` → `Steps4Tests`.

- [ ] **Step 5: Run the tests to verify they pass**

```bash
xcodebuild test -project Steps4.xcodeproj -scheme Steps4 \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:Steps4Tests/DayCompositionTests 2>&1 | tail -20
```

Expected: all 19 tests PASS. If `testAllArchetypesAreReachable` fails, the archetype draw is biased — check that `nextInt(in:)` covers the full range, not that the test is wrong.

- [ ] **Step 6: Commit**

```bash
git add StepsTrader/Models/DayComposition.swift Steps4Tests/DayCompositionTests.swift Steps4.xcodeproj
git commit -m "feat: derive one archetype, palette, contrast key and texture policy per day"
```

---

### Task 6: Wire Composition Into Spawn And Render

**Files:**
- Modify: `StepsTrader/Models/CanvasElement.swift:175-205` (`reroll`), `207-270` (`spawn`), `347-403` (delete `findOpenPosition`)
- Modify: `StepsTrader/Views/GenerativeCanvasView.swift` (pass the spec to the renderer)
- Modify: `StepsTrader/Views/GalleryView.swift:1206-1221`
- Test: `Steps4Tests/DayCompositionTests.swift` (extend)

**Interfaces:**
- Consumes: everything from Tasks 1–5.
- Produces:
  - `CanvasElement.spawnBounds: CGRect`
  - `CanvasElement.spawnMinDistance(existingCount: Int) -> Double`
  - `CanvasElement.baseSizeRange(for: CanvasShapeType) -> ClosedRange<Double>`
  - `CanvasElement.spawn(...)` — signature gains `composition: DayComposition`
  - `CanvasElement.reroll(rank:composition:)` — replaces `reroll(availableCount:)`, whose parameter was never read
  - `CanvasElement.textureSpec(rank:composition:) -> TextureSpec`

- [ ] **Step 1: Write the failing tests**

Append to `Steps4Tests/DayCompositionTests.swift`:

```swift
// MARK: - Spawn under a composition

final class ComposedSpawnTests: XCTestCase {

    private let dayKey = "2026-08-10"

    private func composition(_ count: Int = 0) -> DayComposition {
        DayComposition.forDay(dayKey: dayKey, happeningCount: count)
    }

    private func spawn(
        optionId: String = "happening_walk",
        existing: [CanvasElement] = [],
        shapes: [CanvasShapeType] = [.organicBlob]
    ) -> CanvasElement {
        CanvasElement.spawn(
            optionId: optionId,
            label: "Walk",
            existingElements: existing,
            allowedShapeTypes: shapes,
            dayKey: dayKey,
            composition: composition(existing.count)
        )
    }

    // MARK: Determinism

    /// The point of the change: given the same day, option and index, the whole
    /// element is reproducible. Before this, only the contour was — size,
    /// position, colour and motion all came from the global RNG.
    func testSpawnIsFullyReproducible() {
        let a = spawn()
        let b = spawn()
        XCTAssertEqual(a.shapeSeed, b.shapeSeed)
        XCTAssertEqual(a.frozenShapeType, b.frozenShapeType)
        XCTAssertEqual(a.basePosition, b.basePosition)
        XCTAssertEqual(a.size, b.size)
        XCTAssertEqual(a.hexColor, b.hexColor)
        XCTAssertEqual(a.opacity, b.opacity)
        XCTAssertEqual(a.phaseOffset, b.phaseOffset)
        XCTAssertEqual(a.driftSpeed, b.driftSpeed)
    }

    func testShapeChoiceIsSeededNotRandom() {
        let shapes: [CanvasShapeType] = [.circle, .snowflake, .rays, .organicBlob]
        let picks = (0..<12).map { _ in spawn(shapes: shapes).frozenShapeType }
        XCTAssertEqual(Set(picks).count, 1)
    }

    func testEmptyAllowedListFallsBackToCircle() {
        XCTAssertEqual(spawn(shapes: []).frozenShapeType, .circle)
    }

    // MARK: Colour comes from the day's palette

    func testElementColoursComeFromTheDayPalette() {
        let dayPalette = Set(composition().palette)
        var existing: [CanvasElement] = []
        for i in 0..<10 {
            let element = spawn(optionId: "happening_\(i)", existing: existing)
            XCTAssertTrue(dayPalette.contains(element.hexColor),
                          "\(element.hexColor) is off the day's palette")
            existing.append(element)
        }
    }

    func testACanvasUsesMoreThanOneColour() {
        var existing: [CanvasElement] = []
        for i in 0..<6 {
            existing.append(spawn(optionId: "happening_\(i)", existing: existing))
        }
        XCTAssertGreaterThan(Set(existing.map(\.hexColor)).count, 1)
    }

    // MARK: Placement follows the archetype

    func testSpawnStaysInsideTheMargin() {
        var existing: [CanvasElement] = []
        for i in 0..<15 {
            let element = spawn(optionId: "happening_\(i)", existing: existing)
            XCTAssertTrue(CanvasElement.spawnBounds.contains(element.basePosition),
                          "Element \(i) at \(element.basePosition) broke the margin")
            existing.append(element)
        }
    }

    /// Placement must actually follow the day's field, not ignore it.
    func testPlacementFavoursHighWeightRegions() {
        var existing: [CanvasElement] = []
        for i in 0..<12 {
            existing.append(spawn(optionId: "happening_\(i)", existing: existing))
        }
        let archetype = composition().archetype
        let meanWeight = existing
            .map { archetype.weight(at: $0.basePosition) }
            .reduce(0, +) / Double(existing.count)

        // A uniform scatter over the bounds would average the field's mean;
        // a weighted one must beat it.
        var uniformSum = 0.0
        var samples = 0
        for xStep in 0...20 {
            for yStep in 0...20 {
                let p = CGPoint(
                    x: CanvasElement.spawnBounds.minX
                        + CanvasElement.spawnBounds.width * Double(xStep) / 20,
                    y: CanvasElement.spawnBounds.minY
                        + CanvasElement.spawnBounds.height * Double(yStep) / 20)
                uniformSum += archetype.weight(at: p)
                samples += 1
            }
        }
        XCTAssertGreaterThan(meanWeight, uniformSum / Double(samples),
                             "\(archetype) placement ignored its own field")
    }

    func testSpacingRelaxesAsTheCanvasFills() {
        XCTAssertGreaterThan(CanvasElement.spawnMinDistance(existingCount: 0),
                             CanvasElement.spawnMinDistance(existingCount: 10))
        XCTAssertGreaterThanOrEqual(
            CanvasElement.spawnMinDistance(existingCount: 30), 0.09)
    }

    // MARK: Size follows the archetype

    func testSizeStaysRenderable() {
        var existing: [CanvasElement] = []
        for i in 0..<15 {
            let element = spawn(optionId: "happening_\(i)", existing: existing)
            XCTAssertGreaterThanOrEqual(element.size, 0.04)
            XCTAssertLessThanOrEqual(element.size, 0.48)
            existing.append(element)
        }
    }

    // MARK: Texture follows the policy

    func testTextureSpecFollowsTheDayPolicy() {
        let day = composition()
        for rank in 0..<12 {
            let spec = CanvasElement.textureSpec(rank: rank, composition: day)
            XCTAssertEqual(spec.kind, day.texturePolicy.kind(forRank: rank))
        }
    }

    func testTextureSpecIsDeterministic() {
        let day = composition()
        XCTAssertEqual(CanvasElement.textureSpec(rank: 3, composition: day),
                       CanvasElement.textureSpec(rank: 3, composition: day))
    }

    // MARK: Reroll

    func testRerollChangesTheSeed() {
        var element = spawn()
        let before = element.shapeSeed
        element.reroll(rank: 0, composition: composition())
        XCTAssertNotEqual(element.shapeSeed, before)
    }

    func testRerollKeepsTheColourOnTheDayPalette() {
        var element = spawn()
        for _ in 0..<20 {
            element.reroll(rank: 2, composition: composition())
            XCTAssertTrue(composition().palette.contains(element.hexColor))
        }
    }

    func testRerollClearsTheUserSizeOverride() {
        var element = spawn()
        element.userSize = 0.4
        element.reroll(rank: 1, composition: composition())
        XCTAssertNil(element.userSize)
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

```bash
xcodebuild test -project Steps4.xcodeproj -scheme Steps4 \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:Steps4Tests/ComposedSpawnTests 2>&1 | tail -20
```

Expected: `incorrect argument label` on `CanvasElement.spawn`.

- [ ] **Step 3: Add the placement constants to `CanvasElement`**

Insert immediately after `makeSeed(optionId:dayKey:index:)` (currently ending at line 169):

```swift
    // MARK: - Composition

    /// The normalised region new elements may occupy. The margin is deliberate
    /// negative space: it keeps the composition off the frame edge, where
    /// elements were previously cropped by the viewport.
    static let spawnBounds = CGRect(x: 0.12, y: 0.12, width: 0.76, height: 0.76)

    /// Target spacing, tightened as the canvas fills so late elements still
    /// land somewhere sensible instead of exhausting the sampler.
    static func spawnMinDistance(existingCount: Int) -> Double {
        max(0.09, 0.30 - Double(existingCount) * 0.012)
    }

    /// Per-shape base size range, before the archetype's multiplier.
    static func baseSizeRange(for shape: CanvasShapeType) -> ClosedRange<Double> {
        switch shape {
        case .blob:                0.16...0.32
        case .organicBlob:         0.16...0.34
        case .snowflake:           0.04...0.48
        case .rays:                0.20...0.28
        case .circle, .spirograph: 0.14...0.30
        }
    }

    /// The fill for an element at a given arrival order under a day's policy.
    static func textureSpec(rank: Int, composition: DayComposition) -> TextureSpec {
        let kind = composition.texturePolicy.kind(forRank: rank)
        // Seed on the day's palette so a day's textures share a character
        // while still differing element to element.
        let seed = UInt64(bitPattern: Int64(rank)) &* 0x9E37_79B9
            &+ UInt64(truncatingIfNeeded: composition.palette.joined().hashValue)
        return TextureSpec.seeded(kind: kind, seed: seed)
    }
```

- [ ] **Step 4: Rewrite `spawn`**

Replace the whole `static func spawn(...)` (currently lines 207-270) with:

```swift
    static func spawn(
        id: UUID = UUID(),
        optionId: String,
        label: String,
        existingElements: [CanvasElement],
        forcedVariant: Int? = nil,
        allowedShapeTypes: [CanvasShapeType] = CanvasShapeType.allowedByUser,
        dayKey: String? = nil,
        activityCount: Int? = nil,
        composition: DayComposition
    ) -> CanvasElement {
        // Arrival order within the day. Drives size, colour and texture.
        let rank = existingElements.count

        // The seed comes first: everything below derives from it, so the same
        // day + option + index reproduces the whole element, not just its
        // contour. Without a dayKey there is nothing stable to hash, so the
        // element gets a one-off random identity.
        let seed = dayKey.map { makeSeed(optionId: optionId, dayKey: $0, index: rank) }
            ?? UInt64.random(in: UInt64.min...UInt64.max)

        // `allowedByUser` returns its result in picker order, so indexing into
        // it is stable across launches. Never index into a Set here — Swift
        // randomises hash seeds per process.
        let choices = allowedShapeTypes.isEmpty ? [CanvasShapeType.circle] : allowedShapeTypes
        var shapeRng = SeededRNG.derived(from: seed, domain: "shape")
        let shapeType = choices[shapeRng.nextInt(in: 0...(choices.count - 1))]

        let kind: ElementKind = switch shapeType {
            case .blob, .organicBlob, .snowflake, .circle, .spirograph: .circle
            case .rays:                                                  .ray
        }

        // Placement follows the day's archetype field.
        var placementRng = SeededRNG.derived(from: seed, domain: "placement")
        let position = PoissonDiscSampler.nextPoint(
            existing: existingElements.map(\.basePosition),
            bounds: spawnBounds,
            minDistance: spawnMinDistance(existingCount: rank),
            weight: { composition.archetype.weight(at: $0) },
            using: &placementRng
        )

        // Size follows the archetype's curve, so a centred-mass day and a
        // constellation day do not share a skeleton.
        var sizeRng = SeededRNG.derived(from: seed, domain: "size")
        let base = sizeRng.nextDouble(in: baseSizeRange(for: shapeType))
        let multiplier = composition.archetype.sizeMultiplier(
            rank: rank, count: max(rank + 1, existingElements.count + 1))
        let size = CGFloat(min(0.48, max(0.04, base * multiplier)))

        // Colour comes from the day's palette, not from all 29 swatches.
        let color = composition.color(forRank: rank)

        var motionRng = SeededRNG.derived(from: seed, domain: "motion")
        let opacityRange = composition.opacityRange(forRank: rank)
        let isGrounded = shapeType == .blob || shapeType == .circle || shapeType == .spirograph
        let pulseFrequency = isGrounded
            ? motionRng.nextDouble(in: 0.08...0.2)
            : motionRng.nextDouble(in: 0.3...0.8)

        return CanvasElement(
            id: id,
            kind: kind,
            optionId: optionId,
            label: label,
            hexColor: color,
            hexColor2: composition.color(forRank: rank + 1),
            size: size,
            basePosition: position,
            phaseOffset: motionRng.nextDouble(in: 0...(2 * .pi)),
            driftSpeed: motionRng.nextDouble(in: 0.08...0.2),
            driftAmplitude: motionRng.nextCGFloat(in: 0.01...0.03),
            pulseFrequency: pulseFrequency,
            pulseAmplitude: motionRng.nextCGFloat(in: 0.01...0.03),
            rotationSpeed: motionRng.nextDouble(in: 3...10),
            opacity: motionRng.nextDouble(in: opacityRange),
            createdAt: .now,
            assetVariant: forcedVariant ?? 0,
            shapeSeed: seed,
            activityCount: activityCount,
            frozenShapeType: shapeType
        )
    }
```

- [ ] **Step 5: Update `reroll` and delete `findOpenPosition`**

Replace the `reroll` signature and size block (currently lines 175-191):

```swift
    /// Re-roll the visual variant of this element.
    ///
    /// Unlike `spawn` this is deliberately non-deterministic — the dice is a
    /// request for something new. It still obeys the day: size follows the
    /// archetype's curve and colour stays on the day's palette, so one re-roll
    /// cannot break the canvas's coherence.
    mutating func reroll(rank: Int, composition: DayComposition) {
        shapeSeed = UInt64.random(in: UInt64.min...UInt64.max)

        // Freeze one currently allowed shape so historical renders stay stable.
        let resolvedShape = CanvasShapeType.allowedByUser.randomElement() ?? .circle
        frozenShapeType = resolvedShape

        var rng = SeededRNG(seed: shapeSeed ?? 0)
        let base = rng.nextDouble(in: Self.baseSizeRange(for: resolvedShape))
        let multiplier = composition.archetype.sizeMultiplier(
            rank: rank, count: max(rank + 1, composition.palette.count))
        size = CGFloat(min(0.48, max(0.04, base * multiplier)))
        userSize = nil

        let shifted = rank + rng.nextInt(in: 1...composition.palette.count)
        hexColor = composition.color(forRank: shifted)
        hexColor2 = composition.color(forRank: shifted + 1)
```

Leave the rest of `reroll` (the snowflake phase-preservation block and `lastEditedAt = .now`) exactly as it is.

Then delete `private static func findOpenPosition(existing:)` in full — currently lines 347-403, from the doc comment through the closing brace.

- [ ] **Step 6: Update `GalleryView`**

In `addAndSpawnHappening`, delete the `let color2 = CanvasColorPalette.randomSecondColor(excluding: color)` line and the `color:` / `color2:` arguments, and add the composition:

```swift
        var element = CanvasElement.spawn(
            id: UUID(),
            optionId: optionId,
            label: model.resolveOptionTitle(for: optionId),
            existingElements: dayCanvas.elements,
            dayKey: transactionDayKey,
            composition: DayComposition.forDay(
                dayKey: transactionDayKey,
                happeningCount: dayCanvas.elements.count)
        )
```

This leaves `addAndSpawnHappening`'s `color:` parameter unused — the element's colour now comes from the day's palette. Delete the parameter and update its call sites; a parameter that is passed and ignored is a defect, not a courtesy. The happening's own chip colour is a separate concern that the palette UI reads directly from the happening, not through this function. Grep `addAndSpawnHappening` to find every caller.

Then rewrite `rerollElement` (lines 1206-1221):

```swift
    private func rerollElement(id: UUID) {
        guard let index = dayCanvas.elements.firstIndex(where: { $0.id == id }) else { return }
        let composition = DayComposition.forDay(
            dayKey: dayCanvas.dayKey, happeningCount: dayCanvas.elements.count)
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            dayCanvas.elements[index].reroll(rank: index, composition: composition)
            dayCanvas.elements[index].lastEditedAt = Date.now
        }
        dayCanvas.lastModified = Date.now
        localMutationCounter &+= 1
        saveCanvasLocally()
    }
```

- [ ] **Step 7: Pass the texture spec through the renderer**

In `StepsTrader/Views/GenerativeCanvasView.swift`, in `renderCanvas`, the organic-blob branch currently calls `OrganicBlobShapeRenderer.draw(...)`. Add the spec argument, using the element's index in the sorted render order as its rank:

```swift
                    spec: CanvasElement.textureSpec(
                        rank: cache.sortedIndexMap[e.id] ?? 0,
                        composition: dayComposition),
```

Add a `dayComposition` computed property to `GenerativeCanvasView`, derived once per render rather than per element:

```swift
    /// One composition per canvas. Derived, never stored — a pure function of
    /// the day key, so it survives reinstall and sync for free.
    private var dayComposition: DayComposition {
        DayComposition.forDay(dayKey: dayKey, happeningCount: elements.count)
    }
```

If `GenerativeCanvasView` does not already hold a `dayKey`, add it as a `let` property and pass it from the three call sites (`GalleryView`, `DayCanvasViewerView`, `CanvasPosterView`); grep for `GenerativeCanvasView(` to find them.

- [ ] **Step 8: Fix the remaining `spawn` call sites**

Four test files and `GenerativeCanvasView`'s preview data call `spawn` with the old `color:` label. Update each to pass a composition:

```bash
grep -rn "CanvasElement.spawn\|\.spawn(" --include="*.swift" . | grep -v worktrees
```

For each, drop `color:`/`color2:` and add:

```swift
            composition: DayComposition.forDay(dayKey: <the test's dayKey>, happeningCount: 0)
```

- [ ] **Step 9: Run the tests to verify they pass**

```bash
xcodebuild test -project Steps4.xcodeproj -scheme Steps4 \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:Steps4Tests/ComposedSpawnTests 2>&1 | tail -20
```

Expected: all 14 tests PASS.

- [ ] **Step 10: Run the whole suite**

```bash
xcodebuild test -project Steps4.xcodeproj -scheme Steps4 \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:Steps4Tests 2>&1 | tail -30
```

Expected: no new failures. `CanvasPersistenceRegressionTests`, `HappeningMigrationTests` and `HappeningLiquidLayoutTests` all call `spawn` and must still round-trip.

- [ ] **Step 11: Verify visually — the acceptance test for the whole plan**

Temporarily add a debug control that renders the same eight happenings under seven consecutive day keys. Confirm:

- The seven canvases are **structurally** different, not just differently coloured — mass sits in a different place, one has a dominant form, another has peers, another leaves a large empty region.
- Each single canvas reads as one work: colours are related, fills share a character with one minority accent.
- Within a canvas, forms differ visibly from one another — flat next to graded next to hatched.
- A canvas saved before this change still opens with its original layout, since `basePosition`, `size` and `hexColor` are persisted.

Then measure once more at 15 elements: ≥18 fps.

- [ ] **Step 12: Commit**

```bash
git add StepsTrader/Models/CanvasElement.swift StepsTrader/Views/GalleryView.swift StepsTrader/Views/GenerativeCanvasView.swift Steps4Tests Steps4.xcodeproj
git commit -m "feat: derive placement, size, colour and texture from the day's composition"
```

---

## Out of Scope

Recorded with the reasoning so a later reader does not treat these as oversights:

- **New shape families** (Voronoi cells, flow lines). Four families already ship, and variety now comes from fills and composition, which is cheaper and does not add a competing visual grammar.
- **Health data driving the composition.** The hook is documented in `DayComposition.forDay`. Deriving archetype and contrast from sleep and step fractions is what would turn the canvas from decoration into a portrait of the day — worth doing next, left out here so this plan stays testable without HealthKit.
- **Metal-based fills** (grain, dither, domain warp). They render blank under `ImageRenderer`, which would break wallpaper export and history thumbnails.
- **Clipper2 / polygon booleans.** `Path.subtracting` covers every case currently in sight.
- **`simplify-js` port.** Only matters once contours exceed the 200-point budget, which the budget tests now enforce.
- **`seedrandom`.** `SeededRNG` (SplitMix64) is already better than its ARC4 construction.
