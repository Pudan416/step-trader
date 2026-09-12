# Day Objects Digital Impact Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add deterministic cumulative glitch damage to the Day Objects experiment, driven only by absolute colors spent from 0 through 100.

**Architecture:** A pure Swift impact model maps cumulative spend to monotonic art-directed levels and derives twelve stable daily scar bands from the existing scene seed. The MetalKit renderer passes those levels and bands into the existing final display pass, where an adaptation of SwiftUIShaders' `bcs_glitch` corrupts the composed scene before sharp grain without adding a render pass. The lab owns temporary controls; production payment and persistence systems remain untouched.

**Tech Stack:** Swift, SwiftUI, MetalKit, Metal Shading Language, XCTest, XCUITest.

**Spec:** `docs/superpowers/specs/2026-08-24-day-objects-digital-impact-design.md`

## Global Constraints

- Damage is `clamp(spentColorsToday, 0, 100) / 100`; earned colors and transaction history must not enter the model.
- Zero spent colors must render the natural Day Objects canvas with no scanlines, RGB shift, or displaced sampling.
- One hundred spent colors must remain roughly 25–30% readable.
- Scar geometry is derived from the existing daily root seed in a separate domain and never changes when spend changes.
- There is no purchase burst, transaction observer, payment event, healing animation, or missed-event replay.
- Ambient impulses are capped at 1.5 Hz and must not introduce full-screen luminance flashes.
- Reduce Motion freezes temporal displacement while preserving static cumulative damage.
- The effect runs inside the existing final display pass after sleep blur and before grain; no render target or render pass is added.
- The first implementation remains inside the Day Objects lab and does not connect to AppModel, PayGate, Supabase, history, widgets, wallpaper, or export.
- Do not add the SwiftUIShaders package dependency; adapt only `bcs_glitch` from revision `6b644a8bd4f3131401bd6765990e476352d3cdef` and include its full MIT notice.
- Keep the renderer at 30 FPS and preserve the existing physical-device p95 GPU frame-time target below 25 ms at 40 actors.
- Preserve all unrelated modified and untracked files in the current dirty worktree; stage only files belonging to the current task.

---

## File Structure

### Modify

- `StepsTrader/Experiments/DayObjects/DayObjectTypes.swift` — cumulative-spend curves and deterministic daily scar layout; using an already-targeted file avoids touching the dirty Xcode project.
- `StepsTrader/Experiments/DayObjects/DayObjectsRenderer.swift` — glitch GPU ABI, cached band upload, and final-pass bindings.
- `StepsTrader/Experiments/DayObjects/DayObjectsMetalView.swift` — carry the impact value through `UIViewRepresentable`.
- `StepsTrader/Experiments/DayObjects/DayObjectsView.swift` — accept an independent zero-default impact input.
- `StepsTrader/Metal/DayObjectsPostShader.metal` — adapt cumulative scars, block displacement, RGB split, scanlines, and ambient twitch into `dayObjectsDisplayFragment`.
- `Steps4Tests/DayObjectRenderFrameTests.swift` — uniform ABI, display binding, GPU determinism, monotonic corruption, readability, and Reduce Motion checks.
- `StepsTrader/Experiments/DayObjects/DayObjectsLabView.swift` — spent slider, adjustment buttons, and presets.
- `Steps4UITests/DayObjectsLabUITests.swift` — lab control, clamp, refund, and grid propagation checks.
- `THIRD_PARTY_NOTICES.md` — append the SwiftUIShaders copyright and MIT license.

---

### Task 1: Pure cumulative impact and stable daily scar layout

**Files:**
- Modify: `StepsTrader/Experiments/DayObjects/DayObjectTypes.swift`
- Modify: `Steps4Tests/DayObjectRenderFrameTests.swift`

**Interfaces:**
- Produces: `DayObjectDigitalImpact.init(spentColors:)`, `.none`, `.damage`, `.scarStrength`, `.signalCorruption`, `.ambientMotion`.
- Produces: `DayObjectGlitchBand`, `DayObjectGlitchLayout.make(seed:)`, and `DayObjectGlitchLayout.bandCount == 12`.
- Consumes: `SeededRNG.derived(from:domain:)` and, in later tasks, `DayObjectScene.rootSeed`.

- [ ] **Step 1: Write failing model and layout tests**

Add these methods to `DayObjectRenderFrameTests`:

```swift
func testSpentColorsClampAndMapToAbsoluteDamage() {
    XCTAssertEqual(DayObjectDigitalImpact(spentColors: -4).spentColors, 0)
    XCTAssertEqual(DayObjectDigitalImpact(spentColors: 140).spentColors, 100)
    XCTAssertEqual(DayObjectDigitalImpact(spentColors: 10).damage, 0.10, accuracy: 0.000_001)
    XCTAssertEqual(DayObjectDigitalImpact(spentColors: 50).signalCorruption, pow(0.5, 1.6), accuracy: 0.000_001)
    XCTAssertEqual(DayObjectDigitalImpact(spentColors: 100).ambientMotion, 1, accuracy: 0.000_001)
    XCTAssertEqual(DayObjectDigitalImpact.none, DayObjectDigitalImpact(spentColors: 0))
}

func testLabPresetsProduceExpectedAbsoluteDamage() {
    let expected: [(Int, Double)] = [
        (0, 0), (10, 0.10), (25, 0.25),
        (50, 0.50), (75, 0.75), (100, 1)
    ]
    for (spent, damage) in expected {
        XCTAssertEqual(DayObjectDigitalImpact(spentColors: spent).damage,
                       damage, accuracy: 0.000_001)
    }
}

func testEveryAdditionalColorMonotonicallyIncreasesDamageLevels() {
    for spent in 0..<DayObjectDigitalImpact.maximumSpentColors {
        let before = DayObjectDigitalImpact(spentColors: spent)
        let after = DayObjectDigitalImpact(spentColors: spent + 1)
        XCTAssertGreaterThan(after.damage, before.damage)
        XCTAssertGreaterThanOrEqual(after.scarStrength, before.scarStrength)
        XCTAssertGreaterThanOrEqual(after.signalCorruption, before.signalCorruption)
        XCTAssertGreaterThanOrEqual(after.ambientMotion, before.ambientMotion)
    }
}

func testGlitchLayoutIsStableBoundedAndIndependentOfSpend() {
    let first = DayObjectGlitchLayout.make(seed: 0x1234_5678)
    XCTAssertEqual(first, DayObjectGlitchLayout.make(seed: 0x1234_5678))
    XCTAssertNotEqual(first, DayObjectGlitchLayout.make(seed: 0x1234_5679))
    XCTAssertEqual(first.bands.count, 12)
    XCTAssertTrue(first.bands.allSatisfy {
        (0...1).contains($0.centerY)
            && (0.008...0.040).contains($0.halfHeight)
            && (0.45...1.0).contains($0.displacementScale)
            && (0...1).contains($0.activationThreshold)
            && $0.phaseOffset >= 0
            && $0.phaseOffset <= 2 * .pi
    })
}
```

- [ ] **Step 2: Run the focused tests and verify RED**

```bash
xcodebuild test -project Steps4.xcodeproj -scheme Steps4 \
  -destination 'platform=iOS Simulator,id=00349825-3076-4659-80E4-50B9CFF9090F' \
  -only-testing:Steps4Tests/DayObjectRenderFrameTests/testSpentColorsClampAndMapToAbsoluteDamage \
  -only-testing:Steps4Tests/DayObjectRenderFrameTests/testLabPresetsProduceExpectedAbsoluteDamage \
  -only-testing:Steps4Tests/DayObjectRenderFrameTests/testEveryAdditionalColorMonotonicallyIncreasesDamageLevels \
  -only-testing:Steps4Tests/DayObjectRenderFrameTests/testGlitchLayoutIsStableBoundedAndIndependentOfSpend \
  CODE_SIGNING_ALLOWED=NO
```

Expected: compilation fails because the impact and layout types do not exist.

- [ ] **Step 3: Implement the pure model and deterministic layout**

Add the following focused types to `DayObjectTypes.swift`:

```swift
import Foundation

struct DayObjectDigitalImpact: Equatable {
    static let maximumSpentColors = 100
    static let none = DayObjectDigitalImpact(spentColors: 0)
    let spentColors: Int

    init(spentColors: Int) {
        self.spentColors = min(max(spentColors, 0), Self.maximumSpentColors)
    }

    var damage: Double { Double(spentColors) / Double(Self.maximumSpentColors) }
    var scarStrength: Double { damage }
    var signalCorruption: Double { pow(damage, 1.6) }
    var ambientMotion: Double { pow(damage, 1.35) }
}

struct DayObjectGlitchBand: Equatable {
    let centerY: Double
    let halfHeight: Double
    let displacementScale: Double
    let displacementDirection: Double
    let rgbDirection: Double
    let activationThreshold: Double
    let phaseOffset: Double
}

struct DayObjectGlitchLayout: Equatable {
    static let bandCount = 12
    let bands: [DayObjectGlitchBand]

    static func make(seed: UInt64) -> DayObjectGlitchLayout {
        var geometryRNG = SeededRNG.derived(from: seed, domain: "dayObjectGlitchGeometry")
        var activationRNG = SeededRNG.derived(from: seed, domain: "dayObjectGlitchActivation")
        let ranked = (0..<bandCount).map { ($0, activationRNG.next()) }
            .sorted { $0.1 == $1.1 ? $0.0 < $1.0 : $0.1 < $1.1 }
        let ranks = Dictionary(uniqueKeysWithValues:
            ranked.enumerated().map { ($0.element.0, $0.offset) })

        return DayObjectGlitchLayout(bands: (0..<bandCount).map { index in
            let slotCenter = (Double(index) + 0.5) / Double(bandCount)
            let rank = ranks[index] ?? index
            return DayObjectGlitchBand(
                centerY: min(max(slotCenter + geometryRNG.nextDouble(in: -0.025...0.025), 0.01), 0.99),
                halfHeight: geometryRNG.nextDouble(in: 0.008...0.040),
                displacementScale: geometryRNG.nextDouble(in: 0.45...1.0),
                displacementDirection: geometryRNG.nextInt(in: 0...1) == 0 ? -1 : 1,
                rgbDirection: geometryRNG.nextInt(in: 0...1) == 0 ? -1 : 1,
                activationThreshold: Double(rank) / Double(bandCount - 1),
                phaseOffset: geometryRNG.nextDouble(in: 0...(2 * .pi))
            )
        })
    }
}
```

Do not add earned-color or transaction arguments.

- [ ] **Step 4: Run focused and scene tests**

Run the Task 1 command, then:

```bash
xcodebuild test -project Steps4.xcodeproj -scheme Steps4 \
  -destination 'platform=iOS Simulator,id=00349825-3076-4659-80E4-50B9CFF9090F' \
  -only-testing:Steps4Tests/DayObjectSceneTests CODE_SIGNING_ALLOWED=NO
```

Expected: both runs pass.

- [ ] **Step 5: Commit Task 1 only**

```bash
git add -- StepsTrader/Experiments/DayObjects/DayObjectTypes.swift \
  Steps4Tests/DayObjectRenderFrameTests.swift
git commit -m 'feat: model cumulative day object damage'
```

---

### Task 2: Glitch GPU ABI and renderer input plumbing

**Files:**
- Modify: `StepsTrader/Experiments/DayObjects/DayObjectsRenderer.swift`
- Modify: `StepsTrader/Experiments/DayObjects/DayObjectsMetalView.swift`
- Modify: `StepsTrader/Experiments/DayObjects/DayObjectsView.swift`
- Modify: `Steps4Tests/DayObjectRenderFrameTests.swift`

**Interfaces:**
- Consumes: `DayObjectDigitalImpact` and `DayObjectGlitchLayout`.
- Produces: `DayObjectsGlitchBandUniform`, `DayObjectsGlitchUniforms`, and a zero-default `digitalImpact` argument through View → bridge → renderer.
- Produces: display fragment buffers 1 (scalar uniforms) and 2 (twelve bands).

- [ ] **Step 1: Write failing ABI tests**

Add beside the existing post-uniform tests:

```swift
func testGlitchUniformsMatchMetalLayoutAndFreezeForReduceMotion() {
    let impact = DayObjectDigitalImpact(spentColors: 50)
    let moving = DayObjectsGlitchUniforms(impact: impact, elapsedTime: 12.5,
        reduceMotion: false, seed: 0xFEDC_BA98_7654_3210)
    let frozen = DayObjectsGlitchUniforms(impact: impact, elapsedTime: 900,
        reduceMotion: true, seed: 0xFEDC_BA98_7654_3210)
    XCTAssertEqual(MemoryLayout<DayObjectsGlitchUniforms>.alignment, 16)
    XCTAssertEqual(MemoryLayout<DayObjectsGlitchUniforms>.stride, 48)
    XCTAssertEqual(MemoryLayout<DayObjectsGlitchUniforms>.offset(of: \.levels), 0)
    XCTAssertEqual(MemoryLayout<DayObjectsGlitchUniforms>.offset(of: \.rendering), 16)
    XCTAssertEqual(MemoryLayout<DayObjectsGlitchUniforms>.offset(of: \.metadata), 32)
    XCTAssertEqual(moving.levels.x, 0.5, accuracy: 0.000_001)
    XCTAssertEqual(frozen.rendering.x, 0, accuracy: 0.000_001)
    XCTAssertEqual(frozen.metadata.z, 1)
}

func testGlitchBandUniformsAreFixedSizeAndBounded() {
    let uniforms = DayObjectGlitchLayout.make(seed: 42).bands.map(DayObjectsGlitchBandUniform.init)
    XCTAssertEqual(uniforms.count, 12)
    XCTAssertEqual(MemoryLayout<DayObjectsGlitchBandUniform>.alignment, 16)
    XCTAssertEqual(MemoryLayout<DayObjectsGlitchBandUniform>.stride, 32)
    XCTAssertTrue(uniforms.allSatisfy { $0.geometry.x.isFinite && $0.motion.z.isFinite })
}
```

- [ ] **Step 2: Run the two tests and verify RED**

```bash
xcodebuild test -project Steps4.xcodeproj -scheme Steps4 \
  -destination 'platform=iOS Simulator,id=00349825-3076-4659-80E4-50B9CFF9090F' \
  -only-testing:Steps4Tests/DayObjectRenderFrameTests/testGlitchUniformsMatchMetalLayoutAndFreezeForReduceMotion \
  -only-testing:Steps4Tests/DayObjectRenderFrameTests/testGlitchBandUniformsAreFixedSizeAndBounded \
  CODE_SIGNING_ALLOWED=NO
```

Expected: compilation fails because the GPU types do not exist.

- [ ] **Step 3: Add exact Swift GPU structs**

Place beside `DayObjectsPostUniforms`:

```swift
struct DayObjectsGlitchBandUniform: Equatable {
    static let metalAlignment = 16
    static let metalStride = 32
    let geometry: SIMD4<Float>
    let motion: SIMD4<Float>

    init(_ band: DayObjectGlitchBand) {
        geometry = SIMD4(Float(band.centerY), Float(band.halfHeight),
                         Float(band.displacementScale), Float(band.activationThreshold))
        motion = SIMD4(Float(band.displacementDirection), Float(band.rgbDirection),
                       Float(band.phaseOffset), 0)
    }
}

struct DayObjectsGlitchUniforms: Equatable {
    static let metalAlignment = 16
    static let metalStride = 48
    static let maximumDisplacementPixels: Float = 42
    static let maximumColorShiftPixels: Float = 14
    static let maximumScanLineStrength: Float = 0.35
    let levels: SIMD4<Float>
    let rendering: SIMD4<Float>
    let metadata: SIMD4<UInt32>

    init(impact: DayObjectDigitalImpact, elapsedTime: TimeInterval,
         reduceMotion: Bool, seed: UInt64) {
        levels = SIMD4(Float(impact.damage), Float(impact.scarStrength),
                       Float(impact.signalCorruption), Float(impact.ambientMotion))
        let elapsed = elapsedTime.isFinite ? max(elapsedTime, 0) : 0
        rendering = SIMD4(reduceMotion ? 0 : Float(elapsed),
                          Self.maximumDisplacementPixels,
                          Self.maximumColorShiftPixels,
                          Self.maximumScanLineStrength)
        let folded = seed ^ (seed >> 32)
        metadata = SIMD4(UInt32(truncatingIfNeeded: folded),
                         UInt32(DayObjectGlitchLayout.bandCount),
                         reduceMotion ? 1 : 0, 0)
    }
}
```

- [ ] **Step 4: Thread impact through View, bridge, and renderer**

Use this source-compatible boundary:

```swift
init(sceneInput: DayObjectSceneInput,
     digitalImpact: DayObjectDigitalImpact = .none,
     isAnimating: Bool = true)
```

Add the same value to `DayObjectsMetalView`. Extend `DayObjectsRenderer.create`
and `update` with a default `.none`. The renderer stores the impact and caches
`DayObjectGlitchLayout.make(seed:)` as `[DayObjectsGlitchBandUniform]`, rebuilding
only when `scene.rootSeed` changes. Do not add spend to `DayObjectSceneInput`.
Keep the canvas as one accessibility element and expose the current cumulative
value on it with `.accessibilityValue("Spent colors \(digitalImpact.spentColors)")`;
this makes lab propagation testable without creating decorative VoiceOver nodes.

- [ ] **Step 5: Bind cached glitch bytes in the existing display encoder**

After post buffer 0:

```swift
presentEncoder.setFragmentBytes(&glitchUniforms,
    length: MemoryLayout<DayObjectsGlitchUniforms>.stride, index: 1)
glitchBandUniforms.withUnsafeBytes { bytes in
    guard let baseAddress = bytes.baseAddress else { return }
    presentEncoder.setFragmentBytes(baseAddress, length: bytes.count, index: 2)
}
```

Do not allocate the band array inside `draw(in:)` and do not add a render pass.

- [ ] **Step 6: Run renderer, ABI, and scene suites**

```bash
xcodebuild test -project Steps4.xcodeproj -scheme Steps4 \
  -destination 'platform=iOS Simulator,id=00349825-3076-4659-80E4-50B9CFF9090F' \
  -only-testing:Steps4Tests/DayObjectRenderFrameTests \
  -only-testing:Steps4Tests/DayObjectSceneTests CODE_SIGNING_ALLOWED=NO
```

Expected: PASS; visual output is unchanged until Task 3.

- [ ] **Step 7: Commit Task 2 only**

```bash
git add -- StepsTrader/Experiments/DayObjects/DayObjectsRenderer.swift \
  StepsTrader/Experiments/DayObjects/DayObjectsMetalView.swift \
  StepsTrader/Experiments/DayObjects/DayObjectsView.swift \
  Steps4Tests/DayObjectRenderFrameTests.swift
git commit -m 'feat: pass cumulative damage to day object renderer'
```

---

### Task 3: Cumulative glitch shader, GPU evidence, and attribution

**Files:**
- Modify: `StepsTrader/Metal/DayObjectsPostShader.metal`
- Modify: `Steps4Tests/DayObjectRenderFrameTests.swift`
- Modify: `THIRD_PARTY_NOTICES.md`

**Interfaces:**
- Consumes: buffers 0 `DayObjectsPostUniforms`, 1 `DayObjectsGlitchUniforms`, and 2 `[DayObjectsGlitchBandUniform]`.
- Produces: zero-cost natural branch, twelve deterministic scars, capped RGB displacement, scanlines, and day-seeded ambient twitch in `dayObjectsDisplayFragment`.

- [ ] **Step 1: Extend the GPU harness and write failing behavior tests**

Extend `PostRenderHarness.render` with:

```swift
digitalImpact: DayObjectDigitalImpact = .none,
reduceMotion: Bool = false
```

Use that `reduceMotion` argument when constructing the harness's
`DayObjectEnvironment` instead of its current hard-coded `false`, and construct
`DayObjectsGlitchUniforms` from the same flag. This keeps actor/post behavior
and glitch phase under one accessibility setting.

Create and bind the scalar and band uniforms at indices 1 and 2 in every display
invocation: normal output, no-grain output, production sRGB output, and
`DisplayTransferReadbackHarness`. Add this helper:

```swift
func meanAbsoluteDifference(from other: PostPixelCapture) -> Double {
    precondition(width == other.width && height == other.height)
    let total = zip(rgb, other.rgb).reduce(0.0) { result, pair in
        result + Double(abs(pair.0.x - pair.1.x)
            + abs(pair.0.y - pair.1.y)
            + abs(pair.0.z - pair.1.z)) / 3
    }
    return total / Double(max(rgb.count, 1))
}
```

Add the core GPU assertions:

```swift
func testDamageGrowsMonotonicallyFromNaturalDisplay() throws {
    let harness = try PostRenderHarness(width: 192, height: 256)
    let scene = fixtureScene(ids: ["a", "b", "c"])
    let natural = try harness.render(scene: scene, clarity: 0.7, elapsed: 8,
        digitalImpact: .none).output
    var previousDifference = 0.0
    for spent in [10, 25, 50, 75, 100] {
        let damaged = try harness.render(scene: scene, clarity: 0.7, elapsed: 8,
            digitalImpact: .init(spentColors: spent)).output
        let difference = damaged.meanAbsoluteDifference(from: natural)
        XCTAssertGreaterThan(difference, previousDifference, "spent=\(spent)")
        previousDifference = difference
    }
}

func testGlitchIsDeterministicAndReduceMotionFreezesPhase() throws {
    let harness = try PostRenderHarness(width: 192, height: 256)
    let scene = fixtureScene(ids: ["a", "b"])
    let impact = DayObjectDigitalImpact(spentColors: 75)
    let first = try harness.render(scene: scene, clarity: 0.5, elapsed: 20,
        digitalImpact: impact).output
    let repeated = try harness.render(scene: scene, clarity: 0.5, elapsed: 20,
        digitalImpact: impact).output
    let frozenEarly = try harness.render(scene: scene, clarity: 0.5, elapsed: 1,
        digitalImpact: impact, reduceMotion: true).output
    let frozenLate = try harness.render(scene: scene, clarity: 0.5, elapsed: 900,
        digitalImpact: impact, reduceMotion: true).output
    XCTAssertEqual(first.checksum, repeated.checksum)
    XCTAssertEqual(frozenEarly.checksum, frozenLate.checksum)
}

func testMaximumDamageRetainsSourceStructure() throws {
    let harness = try PostRenderHarness(width: 192, height: 256)
    let scene = fixtureScene(ids: (0..<10).map { "event-\($0)" })
    let natural = try harness.render(scene: scene, clarity: 1, elapsed: 12,
        digitalImpact: .none).output
    let damaged = try harness.render(scene: scene, clarity: 1, elapsed: 12,
        digitalImpact: .init(spentColors: 100)).output
    XCTAssertGreaterThan(
        damaged.luminanceField.correlation(with: natural.luminanceField),
        0.25
    )
    XCTAssertGreaterThan(damaged.structuralSharpness, 0)
}

func testSameSpendUsesDifferentStableScarsForDifferentDays() throws {
    let harness = try PostRenderHarness(width: 192, height: 256)
    let ids = ["a", "b", "c"]
    let firstScene = capacityFixtureScene(dayKey: "2026-08-20", ids: ids)
    let secondScene = capacityFixtureScene(dayKey: "2026-08-21", ids: ids)
    let impact = DayObjectDigitalImpact(spentColors: 50)
    let first = try harness.render(scene: firstScene, clarity: 0.7, elapsed: 8,
        digitalImpact: impact).output
    let repeated = try harness.render(scene: firstScene, clarity: 0.7, elapsed: 8,
        digitalImpact: impact).output
    let second = try harness.render(scene: secondScene, clarity: 0.7, elapsed: 8,
        digitalImpact: impact).output
    XCTAssertEqual(first.checksum, repeated.checksum)
    XCTAssertNotEqual(first.checksum, second.checksum)
}
```

Add normalized Pearson correlation to `PostLuminanceField`:

```swift
func correlation(with other: PostLuminanceField) -> Double {
    precondition(width == other.width && height == other.height)
    let lhsMean = mean
    let rhsMean = other.mean
    var numerator = 0.0
    var lhsEnergy = 0.0
    var rhsEnergy = 0.0
    for (lhs, rhs) in zip(values, other.values) {
        let centeredLHS = lhs - lhsMean
        let centeredRHS = rhs - rhsMean
        numerator += centeredLHS * centeredRHS
        lhsEnergy += centeredLHS * centeredLHS
        rhsEnergy += centeredRHS * centeredRHS
    }
    let denominator = sqrt(lhsEnergy * rhsEnergy)
    return denominator > 0 ? numerator / denominator : 0
}
```

- [ ] **Step 2: Run the four tests and verify RED**

```bash
xcodebuild test -project Steps4.xcodeproj -scheme Steps4 \
  -destination 'platform=iOS Simulator,id=00349825-3076-4659-80E4-50B9CFF9090F' \
  -only-testing:Steps4Tests/DayObjectRenderFrameTests/testDamageGrowsMonotonicallyFromNaturalDisplay \
  -only-testing:Steps4Tests/DayObjectRenderFrameTests/testGlitchIsDeterministicAndReduceMotionFreezesPhase \
  -only-testing:Steps4Tests/DayObjectRenderFrameTests/testMaximumDamageRetainsSourceStructure \
  -only-testing:Steps4Tests/DayObjectRenderFrameTests/testSameSpendUsesDifferentStableScarsForDifferentDays \
  CODE_SIGNING_ALLOWED=NO
```

Expected: the non-zero renders still equal natural output because the shader
ignores buffers 1 and 2.

- [ ] **Step 3: Add the exact matching Metal ABI**

```metal
struct DayObjectsGlitchUniforms {
    float4 levels;
    float4 rendering;
    uint4 metadata;
};

struct DayObjectsGlitchBandUniform {
    float4 geometry;
    float4 motion;
};

static_assert(alignof(DayObjectsGlitchUniforms) == 16, "Glitch uniforms require 16-byte alignment");
static_assert(sizeof(DayObjectsGlitchUniforms) == 48, "Glitch uniforms must match Swift");
static_assert(alignof(DayObjectsGlitchBandUniform) == 16, "Glitch bands require 16-byte alignment");
static_assert(sizeof(DayObjectsGlitchBandUniform) == 32, "Glitch bands must match Swift");
constant uint dayObjectsGlitchBandCapacity = 12;
```

Extend `dayObjectsDisplayFragment` with buffers 1 and 2. Keep buffer 0,
texture 0, and sampler 0 unchanged.

- [ ] **Step 4: Adapt the glitch algorithm into the existing display pass**

Add helpers in declaration order:

```metal
static float dayObjectsGlitchHash(float2 value, uint seed) {
    float seeded = float(seed & 0x00FFFFFFu) * 0.0000001;
    return fract(sin(dot(value + seeded, float2(127.1, 311.7))) * 43758.5453);
}

static float dayObjectsGlitchBandCoverage(
    float y,
    constant DayObjectsGlitchBandUniform &band,
    float damage
) {
    float halfHeight = max(band.geometry.y, 0.0001);
    // The +0.01 bias makes the first color reveal the first band and lets the
    // final band begin revealing exactly at the 100-color ceiling.
    float reveal = saturate((damage - band.geometry.w + 0.01) * 12.0);
    float vertical = 1.0 - smoothstep(
        halfHeight * 0.55,
        halfHeight,
        abs(y - band.geometry.x)
    );
    return reveal * vertical;
}
```

Inside the fragment:

1. Sample the untouched source first.
2. For `levels.x <= 0`, preserve the current contrast/saturation/grain path and
   perform no displaced samples.
3. Loop over `min(metadata.y, 12u)` bands, accumulating coverage, signed
   displacement, RGB direction, and phase-offset twitch.
4. Use ambient frequency `0.15 + 1.35 * levels.w`, never above 1.5 Hz. When
   `metadata.z == 1`, use fixed phase and zero twitch displacement.
5. Quantize vertical position into blocks and mix the upstream `bcs_glitch`
   block-displacement technique with the daily folded seed.
6. Clamp displaced coordinates to the source texture bounds.
7. Sample red, green, and blue separately only on the non-zero branch.
8. Preserve at least 28% original source:

```metal
float mixAmount = min(0.72, coverage * (0.25 * levels.y + 0.47 * levels.z));
color = mix(original.rgb, corrupted.rgb, mixAmount);
```

9. Apply scanlines using `rendering.w` as the maximum; never add a white flash
   or animate total screen luminance.
10. Apply the existing contrast, saturation, and sharp grain after corruption.

- [ ] **Step 5: Append complete attribution**

Append to `THIRD_PARTY_NOTICES.md`:

```markdown
## SwiftUIShaders — Glitch

The Day Objects digital-impact shader adapts the block displacement, RGB
channel separation, scanline, and hash techniques from `bcs_glitch` in
[SwiftUIShaders](https://github.com/krispuckett/SwiftUIShaders), revision
`6b644a8bd4f3131401bd6765990e476352d3cdef`.

Copyright (c) 2026 Kris Puckett

MIT License

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

`THIRD_PARTY_NOTICES.md` is already an untracked user file containing an
unrelated Rich Canvas notice. Preserve that content and leave this shared file
unstaged; report the appended SwiftUIShaders section in the final handoff so the
user can include the complete notice with their existing legal-file work.

- [ ] **Step 6: Run GPU and post-process suites**

```bash
xcodebuild test -project Steps4.xcodeproj -scheme Steps4 \
  -destination 'platform=iOS Simulator,id=00349825-3076-4659-80E4-50B9CFF9090F' \
  -only-testing:Steps4Tests/DayObjectRenderFrameTests CODE_SIGNING_ALLOWED=NO
```

Expected: PASS, including existing blur, grain, transfer, pipeline, and visual
matrix tests. Inspect 0, 10, 50, and 100 attachments before accepting constants.

- [ ] **Step 7: Commit Task 3 only**

```bash
git add -- StepsTrader/Metal/DayObjectsPostShader.metal \
  Steps4Tests/DayObjectRenderFrameTests.swift
git commit -m 'feat: glitch spent colors on day objects canvas'
```

---

### Task 4: Lab controls and cumulative-state UI coverage

**Files:**
- Modify: `StepsTrader/Experiments/DayObjects/DayObjectsLabView.swift`
- Modify: `Steps4UITests/DayObjectsLabUITests.swift`

**Interfaces:**
- Consumes: `DayObjectDigitalImpact(spentColors:)` and `DayObjectsView.digitalImpact`.
- Produces: IDs `dayObjects.spentColors`, `dayObjects.spend.plus1`, `.plus5`, `.plus10`, `.refund10`, and `dayObjects.spend.preset.<value>`; canvas and grid accessibility values mirror the same spend.

- [ ] **Step 1: Write a failing cumulative-control UI test**

```swift
func testSpentColorControlsClampRefundAndReachTheGrid() throws {
    let app = XCUIApplication()
    app.launchArguments = ["-uiLab", "dayObjects",
                           "-AppleLanguages", "(en)",
                           "-AppleLocale", "en_US"]
    app.launch()

    let spent = app.sliders["dayObjects.spentColors"]
    XCTAssertTrue(spent.waitForExistence(timeout: 5))
    let canvas = app.otherElements["dayObjects.canvas"]
    spent.adjust(toNormalizedSliderPosition: 0.5)
    XCTAssertTrue(String(describing: spent.value).contains("50 / 100"))
    XCTAssertTrue(String(describing: canvas.value).contains("Spent colors 50"))
    for preset in [0, 10, 25, 50, 75, 100] {
        app.buttons["dayObjects.spend.preset.\(preset)"].tap()
        XCTAssertTrue(String(describing: spent.value).contains("\(preset) / 100"))
        XCTAssertTrue(String(describing: canvas.value).contains("Spent colors \(preset)"))
    }
    app.buttons["dayObjects.spend.plus10"].tap()
    XCTAssertTrue(String(describing: spent.value).contains("100 / 100"))
    app.buttons["dayObjects.spend.refund10"].tap()
    XCTAssertTrue(String(describing: spent.value).contains("90 / 100"))
    app.buttons["dayObjects.spend.preset.0"].tap()
    app.buttons["dayObjects.spend.refund10"].tap()
    XCTAssertTrue(String(describing: spent.value).contains("0 / 100"))
    app.buttons["dayObjects.spend.preset.75"].tap()
    app.buttons["dayObjects.gridToggle"].tap()
    let grid = app.otherElements["dayObjects.grid"]
    XCTAssertTrue(grid.waitForExistence(timeout: 5))
    XCTAssertTrue(String(describing: grid.value).contains("Spent colors 75"))
}
```

- [ ] **Step 2: Run the UI test and verify RED**

```bash
xcodebuild test -project Steps4.xcodeproj -scheme Steps4 \
  -destination 'platform=iOS Simulator,id=00349825-3076-4659-80E4-50B9CFF9090F' \
  -only-testing:Steps4UITests/DayObjectsLabUITests/testSpentColorControlsClampRefundAndReachTheGrid \
  CODE_SIGNING_ALLOWED=NO
```

Expected: FAIL because the spent slider does not exist.

- [ ] **Step 3: Add one non-persisted cumulative lab state**

```swift
@State private var spentColors: Double = 0

private var spentColorCount: Int {
    min(max(Int(spentColors.rounded()), 0), DayObjectDigitalImpact.maximumSpentColors)
}

private var digitalImpact: DayObjectDigitalImpact {
    DayObjectDigitalImpact(spentColors: spentColorCount)
}

private func adjustSpent(by delta: Int) {
    spentColors = Double(min(max(spentColorCount + delta, 0),
                             DayObjectDigitalImpact.maximumSpentColors))
}
```

Pass `digitalImpact` to the single canvas and every frozen grid canvas. Do not
add AppModel observation, persistence, or a transaction event.

Set the existing grid accessibility element's value without creating children:

```swift
.accessibilityValue("Spent colors \(spentColorCount)")
```

- [ ] **Step 4: Add compact slider, adjustment buttons, and presets**

Reuse the existing slider helper:

```swift
slider("Spent colors", value: $spentColors,
       range: 0...Double(DayObjectDigitalImpact.maximumSpentColors), step: 1,
       readout: "\(spentColorCount) / 100",
       identifier: "dayObjects.spentColors")
```

Add `−10`, `+1`, `+5`, and `+10` bordered buttons wired to `adjustSpent`. Add a
horizontally scrollable preset row for `[0, 10, 25, 50, 75, 100]`; each button
sets the same state directly and exposes `dayObjects.spend.preset.<value>`.

- [ ] **Step 5: Run both Day Objects UI tests**

```bash
xcodebuild test -project Steps4.xcodeproj -scheme Steps4 \
  -destination 'platform=iOS Simulator,id=00349825-3076-4659-80E4-50B9CFF9090F' \
  -only-testing:Steps4UITests/DayObjectsLabUITests CODE_SIGNING_ALLOWED=NO
```

Expected: PASS. Retain screenshots for 0, 50, 100, and grid as attachments;
confirm the controls do not cover themselves at accessibility text size.

- [ ] **Step 6: Run focused unit and GPU suites**

```bash
xcodebuild test -project Steps4.xcodeproj -scheme Steps4 \
  -destination 'platform=iOS Simulator,id=00349825-3076-4659-80E4-50B9CFF9090F' \
  -only-testing:Steps4Tests/DayObjectSceneTests \
  -only-testing:Steps4Tests/DayObjectRenderFrameTests \
  CODE_SIGNING_ALLOWED=NO
```

Expected: PASS.

- [ ] **Step 7: Commit Task 4 only**

```bash
git add -- StepsTrader/Experiments/DayObjects/DayObjectsLabView.swift \
  Steps4UITests/DayObjectsLabUITests.swift
git commit -m 'feat: tune spent color damage in day objects lab'
```

---

### Task 5: Full regression, visual review, and device budget

**Files:**
- Modify only if evidence requires tuning: `DayObjectTypes.swift`, `DayObjectsRenderer.swift`, `DayObjectsPostShader.metal`, and `DayObjectRenderFrameTests.swift`.
- Do not commit screenshots, `.xcresult` bundles, or Instruments traces.

**Interfaces:**
- Consumes: completed Tasks 1–4.
- Produces: simulator regression evidence, visual matrix, physical-device build, and GPU-budget evidence.

- [ ] **Step 1: Run the complete unit target**

```bash
xcodebuild test -project Steps4.xcodeproj -scheme Steps4 \
  -destination 'platform=iOS Simulator,id=00349825-3076-4659-80E4-50B9CFF9090F' \
  -only-testing:Steps4Tests CODE_SIGNING_ALLOWED=NO
```

Expected: PASS.

- [ ] **Step 2: Run the Day Objects UI suite**

```bash
xcodebuild test -project Steps4.xcodeproj -scheme Steps4 \
  -destination 'platform=iOS Simulator,id=00349825-3076-4659-80E4-50B9CFF9090F' \
  -only-testing:Steps4UITests/DayObjectsLabUITests \
  CODE_SIGNING_ALLOWED=NO
```

Expected: PASS.

- [ ] **Step 3: Review the fixed visual matrix**

Inspect 0, 10, 25, 50, 75, and 100 in portrait and landscape:

```text
0   natural, no digital residue
10  a few quiet stable scars
25  visible on inspection without dominating
50  immediately legible digital influence
75  most of the image participates
100 severe corruption, underlying day still recognizable
```

Compare two day seeds at 50: scar positions differ but damage strength is
equivalent.

- [ ] **Step 4: Build for the connected iPhone**

```bash
xcodebuild build -project Steps4.xcodeproj -scheme Steps4 \
  -destination 'platform=iOS,id=00008130-001E3CE622C0001C'
```

Expected: BUILD SUCCEEDED with the device Metal toolchain.

- [ ] **Step 5: Profile the maximum case**

On `iPhone Costa`, run the lab at 40 actors and spent 100 for five minutes with
Instruments Metal System Trace. Verify:

```text
p95 GPU frame time < 25 ms
30 FPS remains stable
no sustained thermal escalation
no per-frame heap growth
no extra render pass versus spent 0
```

Capture spent 0 briefly and confirm the natural branch skips displaced RGB
samples.

- [ ] **Step 6: Tune only against failed evidence**

If readability misses the agreed floor, keep the maximum mix within 0.70...0.75
or update the spec before leaving that range. If p95 misses 25 ms, first skip
inactive bands or reduce dynamic band-loop work; do not add a lower-resolution
pass or render target. Rerun Steps 1–5 after any tuning.

If tuning changes source, commit only those exact files:

```bash
git add -- StepsTrader/Experiments/DayObjects/DayObjectTypes.swift \
  StepsTrader/Experiments/DayObjects/DayObjectsRenderer.swift \
  StepsTrader/Metal/DayObjectsPostShader.metal \
  Steps4Tests/DayObjectRenderFrameTests.swift
git commit -m 'perf: tune day object digital impact'
```

- [ ] **Step 7: Confirm final repository state**

```bash
git status --short
git log -5 --oneline
```

Expected: only the user's pre-existing unrelated changes remain. Four feature
commits, plus an optional evidence-driven tuning commit, are present. No
screenshots, result bundles, or traces are staged.
