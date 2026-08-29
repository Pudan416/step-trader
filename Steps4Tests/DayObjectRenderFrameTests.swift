import CoreGraphics
import ImageIO
import Metal
import MetalKit
import UIKit
import UniformTypeIdentifiers
import XCTest
import simd
@testable import Steps4

final class DayObjectRenderFrameTests: XCTestCase {
    private func fixtureScene(ids: [String]) -> DayObjectScene {
        DayObjectScene.make(input: .init(
            dayKey: "2026-08-20", identity: "tester", eventIDs: ids,
            motionEnergy: 0.55, visualClarity: 0.55, reduceMotion: false
        ))
    }

    private func capacityFixtureScene(dayKey: String, ids: [String]) -> DayObjectScene {
        DayObjectScene.make(input: .init(
            dayKey: dayKey, identity: "tester", eventIDs: ids,
            motionEnergy: 0.55, visualClarity: 0.55, reduceMotion: false
        ))
    }

    func testRepresentativeSceneUsesApprovedOrbScaleHierarchy() {
        let scene = fixtureScene(ids: (0..<8).map { "orb-\($0)" })
        let environment = DayObjectEnvironment(
            motionEnergy: 1,
            visualClarity: 1,
            reduceMotion: false
        )

        for elapsed in stride(from: 0.0, through: scene.score.duration, by: 0.25) {
            let frame = DayObjectRenderFrame.make(
                scene: scene,
                environment: environment,
                elapsed: elapsed,
                insertions: [:]
            )
            let diameters = frame.actors.map { Double($0.halfSize.x * 2) }
            XCTAssertTrue(diameters.contains { (0.26...0.34).contains($0) }, "elapsed=\(elapsed)")
            XCTAssertTrue(diameters.allSatisfy { (0.08...0.34).contains($0) }, "elapsed=\(elapsed) \(diameters)")
        }
    }

    func testVisualLeadershipMovesBetweenActorsWithoutRerollingTheScene() throws {
        let scene = fixtureScene(ids: (0..<8).map { "orb-\($0)" })
        let environment = DayObjectEnvironment(
            motionEnergy: 1,
            visualClarity: 1,
            reduceMotion: false
        )
        var leaders = Set<DayObjectActorID>()

        for elapsed in stride(from: 0.0, to: scene.score.duration, by: 0.25) {
            let frame = DayObjectRenderFrame.make(
                scene: scene,
                environment: environment,
                elapsed: elapsed,
                insertions: [:]
            )
            let envelopes = DayObjectRenderFrame.leadershipEnvelopes(
                for: scene.actors,
                at: frame.choreographyTime,
                duration: scene.score.duration
            )
            XCTAssertEqual(try XCTUnwrap(envelopes.values.max()), 1, accuracy: 0.000_001)
            XCTAssertTrue(envelopes.values.allSatisfy { (0...1).contains($0) })
            leaders.insert(try XCTUnwrap(frame.actors.max { $0.halfSize.x < $1.halfSize.x }).actorID)
        }

        XCTAssertGreaterThanOrEqual(leaders.count, 3)
        XCTAssertEqual(scene, fixtureScene(ids: (0..<8).map { "orb-\($0)" }))
    }

    func testMotionEnergyMapsToSpecifiedTempo() {
        XCTAssertEqual(DayObjectEnvironment(motionEnergy: 0, visualClarity: 1, reduceMotion: false).tempoScale, 0.035, accuracy: 0.0001)
        XCTAssertEqual(DayObjectEnvironment(motionEnergy: 1, visualClarity: 1, reduceMotion: false).tempoScale, 1.25, accuracy: 0.0001)
        XCTAssertEqual(DayObjectEnvironment(motionEnergy: 1, visualClarity: 1, reduceMotion: true).tempoScale, 0.02, accuracy: 0.0001)
    }

    func testEnvironmentClampsNonFiniteInputs() {
        for value in [Double.nan, .infinity, -.infinity] {
            let environment = DayObjectEnvironment(
                motionEnergy: value,
                visualClarity: value,
                reduceMotion: false
            )
            XCTAssertEqual(environment.motionEnergy, 0)
            XCTAssertEqual(environment.visualClarity, 0)
            XCTAssertTrue(environment.tempoScale.isFinite)
        }

        XCTAssertEqual(
            DayObjectEnvironment(motionEnergy: -1, visualClarity: 2, reduceMotion: false),
            DayObjectEnvironment(motionEnergy: 0, visualClarity: 1, reduceMotion: false)
        )
    }

    func testNonFiniteFrameAndGPUInputsClampBeforeShaderUpload() {
        let scene = fixtureScene(ids: ["a"])
        let environment = DayObjectEnvironment(
            motionEnergy: 1,
            visualClarity: 1,
            reduceMotion: false
        )
        let invalidFrame = DayObjectRenderFrame.make(
            scene: scene,
            environment: environment,
            elapsed: .nan,
            insertions: ["a": .infinity],
            canvasAspect: -.infinity
        )
        let zeroFrame = DayObjectRenderFrame.make(
            scene: scene,
            environment: environment,
            elapsed: 0,
            insertions: ["a": 0],
            canvasAspect: 1
        )
        XCTAssertEqual(invalidFrame, zeroFrame)

        let gpuActor = DayObjectGPUActor(
            position: SIMD2(.nan, .infinity),
            direction: SIMD2(-.infinity, .nan),
            halfSize: SIMD2(.nan, -.infinity),
            color: SIMD4(.nan, .infinity, -.infinity, .nan),
            opacity: .nan,
            trailLength: .infinity,
            shape: 6,
            fill: 1,
            depth: .nan
        )
        let numericValues = [
            gpuActor.position.x, gpuActor.position.y,
            gpuActor.direction.x, gpuActor.direction.y,
            gpuActor.halfSize.x, gpuActor.halfSize.y,
            gpuActor.color.x, gpuActor.color.y, gpuActor.color.z, gpuActor.color.w,
            gpuActor.opacity, gpuActor.trailLength, gpuActor.depth,
        ]
        XCTAssertTrue(numericValues.allSatisfy(\.isFinite))
        XCTAssertEqual(gpuActor.position, .zero)
        XCTAssertEqual(gpuActor.direction, SIMD2(1, 0))
        XCTAssertEqual(gpuActor.halfSize, .zero)
        XCTAssertEqual(gpuActor.color, .zero)
        XCTAssertEqual(gpuActor.opacity, 0)
        XCTAssertEqual(gpuActor.trailLength, 0)
        XCTAssertEqual(gpuActor.depth, 0)
        XCTAssertEqual(gpuActor.shape, 6)
        XCTAssertEqual(gpuActor.fill, 1)
    }

    func testZeroEventFrameKeepsGenerativePostProcessWithoutActors() {
        let scene = fixtureScene(ids: [])
        let environment = DayObjectEnvironment(
            motionEnergy: 0,
            visualClarity: 0.5,
            reduceMotion: false
        )
        let frame = DayObjectRenderFrame.make(
            scene: scene,
            environment: environment,
            elapsed: 12,
            insertions: [:]
        )

        XCTAssertTrue(frame.actors.isEmpty)
        XCTAssertTrue(frame.choreographyTime.isFinite)
        XCTAssertGreaterThan(frame.postProcess.grainIntensity, 0)
        XCTAssertTrue(frame.postProcess.grainPhase.isFinite)
    }

    func testSleepFocusIsMonotonicAndLeavesGrainIndependent() {
        let clear = DayObjectPostProcess(visualClarity: 1, reduceMotion: false, grainSeed: 9)
        let tired = DayObjectPostProcess(visualClarity: 0, reduceMotion: false, grainSeed: 9)
        XCTAssertEqual(clear.blurRadius, 0, accuracy: 0.0001)
        XCTAssertEqual(tired.blurRadius, 18, accuracy: 0.0001)
        XCTAssertEqual(clear.contrast, 1, accuracy: 0.0001)
        XCTAssertEqual(tired.contrast, 0.84, accuracy: 0.0001)
        XCTAssertEqual(clear.saturation, 1, accuracy: 0.0001)
        XCTAssertEqual(tired.saturation, 0.88, accuracy: 0.0001)
        XCTAssertEqual(clear.grainIntensity, tired.grainIntensity)
    }

    func testPostUniformsUseExactMetalLayoutAndBoundPointScaledBlur() {
        let resolution = SIMD2<Float>(1_179, 2_556)
        let clear = DayObjectsPostUniforms(
            postProcess: DayObjectPostProcess(
                visualClarity: 1,
                reduceMotion: false,
                grainSeed: 9
            ),
            resolution: resolution,
            pointToPixelScale: 3,
            grainSeed: 0xFEDC_BA98_7654_3210,
            paletteLuminance: 0.2
        )
        let middle = DayObjectsPostUniforms(
            postProcess: DayObjectPostProcess(
                visualClarity: 0.5,
                reduceMotion: false,
                grainSeed: 9
            ),
            resolution: resolution,
            pointToPixelScale: 3,
            grainSeed: 0xFEDC_BA98_7654_3210,
            paletteLuminance: 0.2
        )
        let tired = DayObjectsPostUniforms(
            postProcess: DayObjectPostProcess(
                visualClarity: 0,
                reduceMotion: false,
                grainSeed: 9
            ),
            resolution: resolution,
            pointToPixelScale: 3,
            grainSeed: 0xFEDC_BA98_7654_3210,
            paletteLuminance: 0.2
        )

        XCTAssertEqual(DayObjectsPostUniforms.metalAlignment, 8)
        XCTAssertEqual(DayObjectsPostUniforms.metalStride, 32)
        XCTAssertEqual(MemoryLayout<DayObjectsPostUniforms>.alignment, 8)
        XCTAssertEqual(MemoryLayout<DayObjectsPostUniforms>.size, 32)
        XCTAssertEqual(MemoryLayout<DayObjectsPostUniforms>.stride, 32)
        XCTAssertEqual(MemoryLayout<DayObjectsPostUniforms>.offset(of: \.resolution), 0)
        XCTAssertEqual(MemoryLayout<DayObjectsPostUniforms>.offset(of: \.blurRadiusPixels), 8)
        XCTAssertEqual(MemoryLayout<DayObjectsPostUniforms>.offset(of: \.contrast), 12)
        XCTAssertEqual(MemoryLayout<DayObjectsPostUniforms>.offset(of: \.saturation), 16)
        XCTAssertEqual(MemoryLayout<DayObjectsPostUniforms>.offset(of: \.grainIntensity), 20)
        XCTAssertEqual(MemoryLayout<DayObjectsPostUniforms>.offset(of: \.grainPhase), 24)
        XCTAssertEqual(MemoryLayout<DayObjectsPostUniforms>.offset(of: \.grainSeed), 28)
        XCTAssertEqual(clear.blurRadiusPixels, 0, accuracy: 0.000_001)
        XCTAssertGreaterThan(middle.blurRadiusPixels, clear.blurRadiusPixels)
        XCTAssertLessThan(middle.blurRadiusPixels, tired.blurRadiusPixels)
        XCTAssertEqual(
            tired.blurRadiusPixels,
            DayObjectsPostUniforms.maximumBlurRadiusPixels,
            accuracy: 0.000_001
        )
    }

    func testProceduralGrainUsesOneStableTexturedIntensityForEveryDayAndPalette() {
        for seed in UInt64(0)..<64 {
            let postProcess = DayObjectPostProcess(
                visualClarity: 0.4,
                reduceMotion: false,
                grainSeed: seed
            )
            XCTAssertEqual(postProcess.grainIntensity, 0.05, accuracy: 0.000_001)

            let dark = DayObjectsPostUniforms(
                postProcess: postProcess,
                resolution: SIMD2(160, 112),
                pointToPixelScale: 2,
                grainSeed: seed,
                paletteLuminance: 0.2
            )
            let light = DayObjectsPostUniforms(
                postProcess: postProcess,
                resolution: SIMD2(160, 112),
                pointToPixelScale: 2,
                grainSeed: seed,
                paletteLuminance: 0.96
            )
            XCTAssertEqual(dark.grainIntensity, 0.05, accuracy: 0.000_001)
            XCTAssertEqual(light.grainIntensity, 0.05, accuracy: 0.000_001)
        }

        let seeded = DayObjectPostProcess(
            visualClarity: 0.4,
            reduceMotion: false,
            grainSeed: 9
        )
        let dark = DayObjectsPostUniforms(
            postProcess: seeded,
            resolution: SIMD2(160, 112),
            pointToPixelScale: 2,
            grainSeed: 9,
            paletteLuminance: 0.2
        )
        let light = DayObjectsPostUniforms(
            postProcess: seeded,
            resolution: SIMD2(160, 112),
            pointToPixelScale: 2,
            grainSeed: 9,
            paletteLuminance: 0.96
        )
        XCTAssertEqual(light.grainIntensity, dark.grainIntensity)
    }

    func testLightestAvailableDailyPaletteKeepsTheStableTexturedGrainIntensity() throws {
        let scenes = (0..<512).map { index in
            DayObjectScene.make(input: .init(
                dayKey: "light-palette-\(index)",
                identity: "tester",
                eventIDs: [],
                motionEnergy: 0.5,
                visualClarity: 0.5,
                reduceMotion: false
            ))
        }
        let scene = try XCTUnwrap(scenes.max { lhs, rhs in
            averagePaletteLuminance(lhs) < averagePaletteLuminance(rhs)
        })
        XCTAssertGreaterThan(
            averagePaletteLuminance(scene),
            DayObjectsPostUniforms.lightPaletteLuminanceStart
        )

        let environment = DayObjectEnvironment(
            motionEnergy: 0.5,
            visualClarity: 0.5,
            reduceMotion: false
        )
        let frame = DayObjectRenderFrame.make(
            scene: scene,
            environment: environment,
            elapsed: 12,
            insertions: [:]
        )
        let uniforms = DayObjectsPostUniforms(
            frame: frame,
            scene: scene,
            resolution: SIMD2(160, 112),
            pointToPixelScale: 2
        )

        XCTAssertEqual(uniforms.grainIntensity, 0.05, accuracy: 0.000_001)
        XCTAssertEqual(uniforms.grainIntensity, Float(frame.postProcess.grainIntensity))
    }

    func testGrainPhaseAdvancesAtNoMoreThanTwelveHertzAndReduceMotionFreezesIndependently() {
        let start = DayObjectPostProcess(
            visualClarity: 0.5,
            reduceMotion: false,
            grainSeed: 9,
            elapsed: 10.001
        )
        let withinFrame = DayObjectPostProcess(
            visualClarity: 0.5,
            reduceMotion: false,
            grainSeed: 9,
            elapsed: 10.08
        )
        let nextFrame = DayObjectPostProcess(
            visualClarity: 0.5,
            reduceMotion: false,
            grainSeed: 9,
            elapsed: 10.084
        )
        XCTAssertEqual(start.grainPhase, withinFrame.grainPhase)
        XCTAssertEqual(nextFrame.grainPhase - start.grainPhase, 1 / 12, accuracy: 0.000_001)

        let frozenEarly = DayObjectPostProcess(
            visualClarity: 0.5,
            reduceMotion: true,
            grainSeed: 9,
            elapsed: 1
        )
        let frozenLate = DayObjectPostProcess(
            visualClarity: 0.5,
            reduceMotion: true,
            grainSeed: 9,
            elapsed: 1_000
        )
        XCTAssertEqual(frozenEarly.grainPhase, frozenLate.grainPhase)

        let scene = fixtureScene(ids: ["a", "b"])
        let reduced = DayObjectEnvironment(
            motionEnergy: 1,
            visualClarity: 0.5,
            reduceMotion: true
        )
        let earlyFrame = DayObjectRenderFrame.make(
            scene: scene,
            environment: reduced,
            elapsed: 1,
            insertions: [:]
        )
        let lateFrame = DayObjectRenderFrame.make(
            scene: scene,
            environment: reduced,
            elapsed: 2,
            insertions: [:]
        )
        XCTAssertEqual(earlyFrame.postProcess.grainPhase, lateFrame.postProcess.grainPhase)
        XCTAssertGreaterThan(lateFrame.choreographyTime, earlyFrame.choreographyTime)
    }

    func testPostUniformGrainSeedUsesSceneRootRatherThanActorCount() {
        let empty = fixtureScene(ids: [])
        let populated = fixtureScene(ids: (0..<20).map { "event-\($0)" })
        let environment = DayObjectEnvironment(
            motionEnergy: 0.5,
            visualClarity: 0.5,
            reduceMotion: false
        )
        let emptyFrame = DayObjectRenderFrame.make(
            scene: empty,
            environment: environment,
            elapsed: 12,
            insertions: [:]
        )
        let populatedFrame = DayObjectRenderFrame.make(
            scene: populated,
            environment: environment,
            elapsed: 12,
            insertions: [:]
        )
        let emptyUniforms = DayObjectsPostUniforms(
            frame: emptyFrame,
            scene: empty,
            resolution: SIMD2(160, 112),
            pointToPixelScale: 2
        )
        let populatedUniforms = DayObjectsPostUniforms(
            frame: populatedFrame,
            scene: populated,
            resolution: SIMD2(160, 112),
            pointToPixelScale: 2
        )

        XCTAssertEqual(empty.rootSeed, populated.rootSeed)
        XCTAssertEqual(emptyUniforms.grainSeed, populatedUniforms.grainSeed)
        XCTAssertEqual(emptyUniforms.grainIntensity, populatedUniforms.grainIntensity)
    }

    func testPostPipelinesUseExactShaderEntryPoints() throws {
        let device = try XCTUnwrap(MTLCreateSystemDefaultDevice())
        let library = try XCTUnwrap(device.makeDefaultLibrary())
        let horizontal = try XCTUnwrap(DayObjectsPostRendering.blurPipelineDescriptor(
            library: library,
            horizontal: true,
            pixelFormat: .rgba16Float
        ))
        let vertical = try XCTUnwrap(DayObjectsPostRendering.blurPipelineDescriptor(
            library: library,
            horizontal: false,
            pixelFormat: .rgba16Float
        ))
        let display = try XCTUnwrap(DayObjectsPostRendering.displayPipelineDescriptor(
            library: library,
            pixelFormat: .rgba16Float
        ))

        XCTAssertEqual(horizontal.fragmentFunction?.name, "dayObjectsBlurHorizontal")
        XCTAssertEqual(vertical.fragmentFunction?.name, "dayObjectsBlurVertical")
        XCTAssertEqual(display.fragmentFunction?.name, "dayObjectsDisplayFragment")
        XCTAssertNoThrow(try device.makeRenderPipelineState(descriptor: horizontal))
        XCTAssertNoThrow(try device.makeRenderPipelineState(descriptor: vertical))
        XCTAssertNoThrow(try device.makeRenderPipelineState(descriptor: display))
    }

    func testDefaultLibraryDoesNotExposeUnusedScaffoldEntryPoints() throws {
        let device = try XCTUnwrap(MTLCreateSystemDefaultDevice())
        let library = try XCTUnwrap(device.makeDefaultLibrary())

        XCTAssertNil(library.makeFunction(name: "dayObjectsScaffoldVertex"))
        XCTAssertNil(library.makeFunction(name: "dayObjectsScaffoldFragment"))
    }

    func testProductionDrawableUsesExplicitSRGBTransferAndLayerColorSpace() throws {
        XCTAssertEqual(DayObjectsRenderer.colorPixelFormat, .bgra8Unorm_srgb)

        let view = MTKView(frame: CGRect(x: 0, y: 0, width: 8, height: 8))
        DayObjectsRenderer.configureDisplay(view)
        XCTAssertEqual(view.colorPixelFormat, .bgra8Unorm_srgb)
        let metalLayer = try XCTUnwrap(view.layer as? CAMetalLayer)
        XCTAssertEqual(
            metalLayer.colorspace?.name as String?,
            CGColorSpace(name: CGColorSpace.sRGB)?.name as String?
        )

        let readback = try DisplayTransferReadbackHarness().render(
            linearRGB: SIMD3<Float>(0.18, 0.50, 0.80)
        )
        XCTAssertEqual(readback.linearBytes, SIMD3<UInt8>(46, 128, 204))
        XCTAssertEqual(readback.sRGBBytes, SIMD3<UInt8>(118, 188, 231))
    }

    func testPostGPUDefocusesCompleteSceneMonotonicallyWhileGrainStaysSharp() throws {
        let scene = fixtureScene(ids: (0..<12).map { "gpu-event-\($0)" })
        let harness = try PostRenderHarness(width: 160, height: 112)
        var structuralSharpness = [Double]()

        for clarity in [0.0, 0.5, 1.0] {
            let first = try harness.render(scene: scene, clarity: clarity, elapsed: 8.375)
            let second = try harness.render(scene: scene, clarity: clarity, elapsed: 8.375)
            XCTAssertEqual(first.output.checksum, second.output.checksum)
            XCTAssertEqual(first.noGrain.checksum, second.noGrain.checksum)

            let sharpness = first.noGrain.structuralSharpness
            let grain = first.output.difference(from: first.noGrain)
            let fineEnergy = grain.neighborDifferenceEnergy
            let coarseEnergy = grain.boxBlurred(radius: 2).neighborDifferenceEnergy
            let sharpGrainRatio = fineEnergy / max(coarseEnergy, 0.000_000_1)
            structuralSharpness.append(sharpness)

            XCTAssertGreaterThan(grain.meanAbsoluteLuminance, 0.000_01)
            XCTAssertGreaterThan(sharpGrainRatio, 1.5)
            print(
                "DAY_OBJECTS_POST_GPU clarity=\(clarity) "
                    + "checksum=\(first.output.checksum) "
                    + "blurPixels=\(first.uniforms.blurRadiusPixels) "
                    + "structuralSharpness=\(sharpness) "
                    + "grainFine=\(fineEnergy) grainCoarse=\(coarseEnergy) "
                    + "grainSharpRatio=\(sharpGrainRatio)"
            )
        }

        XCTAssertLessThan(structuralSharpness[0], structuralSharpness[1])
        XCTAssertLessThan(structuralSharpness[1], structuralSharpness[2])
    }

    func testLabFixtureProducesVisibleActorsThroughActorAndPostPasses() throws {
        let eventIDs = (0..<8).map { "lab-event-\($0)" }
        let scene = DayObjectScene.make(input: .init(
            dayKey: "2026-01-01",
            identity: "day-objects-lab",
            eventIDs: eventIDs,
            motionEnergy: 0.55,
            visualClarity: 0.55,
            reduceMotion: false
        ))
        let emptyScene = DayObjectScene.make(input: .init(
            dayKey: "2026-01-01",
            identity: "day-objects-lab",
            eventIDs: [],
            motionEnergy: 0.55,
            visualClarity: 0.55,
            reduceMotion: false
        ))
        let environment = DayObjectEnvironment(
            motionEnergy: 0.55,
            visualClarity: 0.55,
            reduceMotion: false
        )
        let frame = DayObjectRenderFrame.make(
            scene: scene,
            environment: environment,
            elapsed: 12,
            insertions: [:],
            canvasAspect: 201.0 / 437.0
        )

        XCTAssertEqual(scene.actors.count, 8)
        XCTAssertEqual(frame.actors.count, 8)
        XCTAssertTrue(frame.actors.allSatisfy { $0.opacity > 0 })
        XCTAssertGreaterThanOrEqual(scene.palette.minimumFigureContrast, 1.35)

        let actorHarness = try ActorRenderHarness(width: 201, height: 437)
        let actorCapture = try actorHarness.render(DayObjectsActorUpload(
            actors: frame.actors,
            resolution: SIMD2(201, 437),
            radialFillStyle: scene.radialFillStyle
        ))
        XCTAssertGreaterThan(actorCapture.nonzeroPixelCount, 0)
        XCTAssertGreaterThan(actorCapture.total, 0)

        let postHarness = try PostRenderHarness(width: 201, height: 437)
        let populated = try postHarness.render(
            scene: scene,
            clarity: 0.55,
            elapsed: 12,
            motionEnergy: 0.55
        )
        let empty = try postHarness.render(
            scene: emptyScene,
            clarity: 0.55,
            elapsed: 12,
            motionEnergy: 0.55
        )
        let actorDifference = populated.noGrain.difference(from: empty.noGrain)
        XCTAssertGreaterThan(empty.noGrain.luminanceField.maximumAbsoluteLuminance, 0.01)
        XCTAssertGreaterThan(actorDifference.meanAbsoluteLuminance, 0.000_1)
        print(
            "DAY_OBJECTS_LAB_GPU sceneActors=\(scene.actors.count) "
                + "frameActors=\(frame.actors.count) "
                + "actorCoverage=\(actorCapture.nonzeroPixelCount) "
                + "actorAlpha=\(actorCapture.total) "
                + "minimumContrast=\(scene.palette.minimumFigureContrast) "
                + "postActorDifference=\(actorDifference.meanAbsoluteLuminance) "
                + "postActorMaximum=\(actorDifference.maximumAbsoluteLuminance) "
                + "postActorStrongPixels=\(actorDifference.pixelCount(above: 0.01))"
        )
    }

    func testDeterministicVisualAcceptanceMatrix() throws {
        let scene = fixtureScene(ids: (0..<40).map { "matrix-event-\($0)" })
        XCTAssertEqual(scene.actors.count, 40)

        let layouts = [
            (name: "phone-portrait", width: 402, height: 874),
            (name: "tablet-landscape", width: 1_024, height: 768),
        ]
        for layout in layouts {
            let harness = try PostRenderHarness(width: layout.width, height: layout.height)
            for clarity in [0.0, 0.5, 1.0] {
                for motionEnergy in [0.0, 1.0] {
                    let empty = try harness.render(
                        scene: scene,
                        clarity: clarity,
                        elapsed: 11.25,
                        motionEnergy: motionEnergy,
                        actorLimit: 0
                    )
                    for actorCount in [1, 10, 24, 40] {
                        let result = try harness.render(
                            scene: scene,
                            clarity: clarity,
                            elapsed: 11.25,
                            motionEnergy: motionEnergy,
                            actorLimit: actorCount
                        )
                        let outputLuminance = result.output.luminanceField.values
                        let outputDynamicRange = (outputLuminance.max() ?? 0) - (outputLuminance.min() ?? 0)
                        let paintedLuminance = result.noGrain.luminanceField
                        let paintedDynamicRange = (paintedLuminance.values.max() ?? 0)
                            - (paintedLuminance.values.min() ?? 0)
                        let actorContribution = result.noGrain.difference(from: empty.noGrain)
                        let grain = result.output.difference(from: result.noGrain)
                        let sharpGrainRatio = grain.neighborDifferenceEnergy
                            / max(grain.boxBlurred(radius: 2).neighborDifferenceEnergy, 0.000_000_1)

                        XCTAssertEqual(result.renderedActorCount, actorCount)
                        XCTAssertGreaterThan(outputDynamicRange, 0.01)
                        XCTAssertGreaterThan(paintedLuminance.maximumAbsoluteLuminance, 0.001)
                        XCTAssertGreaterThan(paintedDynamicRange, 0.001)
                        XCTAssertGreaterThan(actorContribution.maximumAbsoluteLuminance, 0.000_01)
                        XCTAssertGreaterThan(grain.meanAbsoluteLuminance, 0.000_01)
                        XCTAssertGreaterThan(sharpGrainRatio, 1.5)

                        let clarityLabel = Int((clarity * 10).rounded())
                        let motionLabel = Int(motionEnergy.rounded())
                        let attachment = XCTAttachment(
                            data: try result.output.pngData(),
                            uniformTypeIdentifier: UTType.png.identifier
                        )
                        attachment.name = "task-10-matrix-\(layout.name)-a\(actorCount)-c\(clarityLabel)-m\(motionLabel)"
                        attachment.lifetime = .keepAlways
                        add(attachment)

                        print(
                            "DAY_OBJECTS_MATRIX layout=\(layout.name) "
                                + "actors=\(actorCount) clarity=\(clarity) motion=\(motionEnergy) "
                                + "checksum=\(result.output.checksum) outputRange=\(outputDynamicRange) "
                                + "paintedRange=\(paintedDynamicRange) "
                                + "actorPeak=\(actorContribution.maximumAbsoluteLuminance) "
                                + "grainSharpRatio=\(sharpGrainRatio)"
                        )
                    }
                }
            }
        }
    }

    func testCommittedPerceptualSignaturesCoverProductionTransferCompositionAndPalette() throws {
        let scene = fixtureScene(ids: (0..<40).map { "signature-event-\($0)" })
        for fixture in DayObjectsPerceptualBaselines.fixtures {
            let harness = try PostRenderHarness(width: fixture.width, height: fixture.height)
            let populated = try harness.render(
                scene: scene,
                clarity: 1,
                elapsed: 11.25,
                motionEnergy: 0.75
            )
            let empty = try harness.render(
                scene: scene,
                clarity: 1,
                elapsed: 11.25,
                motionEnergy: 0.75,
                actorLimit: 0
            )
            let signature = DayObjectsPerceptualSignature(
                capture: populated.output,
                actorDifference: populated.noGrain.difference(from: empty.noGrain),
                negativeSpaceRegion: scene.compositionPlan.negativeSpaceRegion,
                exclusionRegion: scene.compositionPlan.uiExclusionRegion
            )

            XCTAssertEqual(
                signature.mismatches(from: fixture.signature),
                [],
                "fixture=\(fixture.name) signature=\(signature)"
            )
            XCTAssertLessThanOrEqual(
                populated.productionSRGB.maximumDisplayByteDifference(from: populated.output),
                2,
                "Offscreen PNG conversion must match production sRGB storage"
            )
            for (suffix, capture) in [("grain", populated.output), ("painted", populated.noGrain)] {
                let attachment = XCTAttachment(
                    data: try capture.pngData(),
                    uniformTypeIdentifier: UTType.png.identifier
                )
                attachment.name = "day-objects-radial-\(fixture.name)-\(suffix)"
                attachment.lifetime = .keepAlways
                add(attachment)
            }
        }

        let drawable = try DisplayTransferReadbackHarness().renderActualDrawable(
            linearRGB: SIMD3<Float>(0.18, 0.50, 0.80)
        )
        XCTAssertTrue(drawable.usedActualMTKDrawable)
        XCTAssertLessThanOrEqual(drawable.maximumDifference(from: SIMD3<UInt8>(118, 188, 231)), 2)
    }

    func testInsertionAndRemovalTriptychsMatchCommittedPerceptualSignatures() throws {
        let base = fixtureScene(ids: ["a", "b", "c", "d"])
        let expanded = fixtureScene(ids: ["a", "b", "c", "d", "e"])
        let harness = try PostRenderHarness(width: 201, height: 437)

        var insertionTimeline = DayObjectInsertionTimeline(scene: base)
        let insertionBefore = insertionTimeline.renderState(activeScene: base, elapsed: 19.9)
        insertionTimeline.update(scene: expanded, elapsed: 20)
        let insertionDuring = insertionTimeline.renderState(activeScene: expanded, elapsed: 20.55)
        let insertionAfter = insertionTimeline.renderState(activeScene: expanded, elapsed: 21.5)

        var removalTimeline = DayObjectInsertionTimeline(scene: expanded)
        let removalBefore = removalTimeline.renderState(activeScene: expanded, elapsed: 29.9)
        removalTimeline.update(scene: base, elapsed: 30)
        let removalDuring = removalTimeline.renderState(activeScene: base, elapsed: 30.55)
        let removalAfter = removalTimeline.renderState(activeScene: base, elapsed: 31.5)

        let capped = fixtureScene(ids: (0..<40).map { "capped-\($0)" })
        let cappedReplacement = fixtureScene(ids: (1...40).map { "capped-\($0)" })
        var cappedTimeline = DayObjectInsertionTimeline(scene: capped)
        let cappedBefore = cappedTimeline.renderState(activeScene: capped, elapsed: 39.9)
        cappedTimeline.update(scene: cappedReplacement, elapsed: 40)
        let cappedDuring = cappedTimeline.renderState(activeScene: cappedReplacement, elapsed: 40.55)
        _ = cappedTimeline.renderState(activeScene: cappedReplacement, elapsed: 41.5)
        let cappedAfter = cappedTimeline.renderState(activeScene: cappedReplacement, elapsed: 42.05)

        let phases = [
            ("insertion-before", insertionBefore, 19.9, base),
            ("insertion-during", insertionDuring, 20.55, base),
            ("insertion-after", insertionAfter, 21.5, base),
            ("removal-before", removalBefore, 29.9, base),
            ("removal-during", removalDuring, 30.55, base),
            ("removal-after", removalAfter, 31.5, base),
            ("capped-replacement-before", cappedBefore, 39.9, capped),
            ("capped-replacement-during", cappedDuring, 40.55, capped),
            ("capped-replacement-after", cappedAfter, 42.05, cappedReplacement),
        ]
        var signatures = [DayObjectsTransitionPerceptualSignature]()
        for (name, state, elapsed, referenceScene) in phases {
            let capture = try harness.render(
                scene: state.scene,
                clarity: 0.55,
                elapsed: elapsed,
                motionEnergy: 0.55,
                insertions: state.insertions,
                removals: state.removals
            )
            let reference = try harness.render(
                scene: referenceScene,
                clarity: 0.55,
                elapsed: elapsed,
                motionEnergy: 0.55
            )
            signatures.append(DayObjectsTransitionPerceptualSignature(
                name: name,
                renderedActorCount: capture.renderedActorCount,
                affectedEnergy: capture.noGrain.difference(from: reference.noGrain).meanAbsoluteLuminance,
                capture: capture.output
            ))

            let attachment = XCTAttachment(
                data: try capture.output.pngData(),
                uniformTypeIdentifier: UTType.png.identifier
            )
            attachment.name = "final-fix-wave-\(name)"
            attachment.lifetime = .keepAlways
            add(attachment)
        }

        XCTAssertEqual(
            DayObjectsPerceptualBaselines.transitionMismatches(signatures),
            [],
            "signatures=\(signatures)"
        )
    }

    func testAddingActorDoesNotChangeExistingFrameStates() {
        let before = fixtureScene(ids: ["a", "b"])
        let after = fixtureScene(ids: ["a", "b", "c"])
        let environment = DayObjectEnvironment(motionEnergy: 0.55, visualClarity: 0.55, reduceMotion: false)
        let frameA = DayObjectRenderFrame.make(scene: before, environment: environment, elapsed: 12, insertions: [:])
        let frameB = DayObjectRenderFrame.make(scene: after, environment: environment, elapsed: 12, insertions: ["c": 11.5])
        XCTAssertEqual(frameA.actors, frameB.actors.filter { $0.eventID != "c" })
        XCTAssertTrue(frameB.actors.filter { $0.eventID == "c" }.allSatisfy { $0.opacity > 0 && $0.opacity < 1 })

        let enrichedByID = Dictionary(uniqueKeysWithValues: frameB.actors.map { ($0.actorID, $0) })
        for actor in frameA.actors {
            guard let enriched = enrichedByID[actor.actorID] else {
                XCTFail("Missing stable actor \(actor.actorID)")
                continue
            }
            let beforeBytes = withUnsafeBytes(of: actor.gpuActor) { Array($0) }
            let afterBytes = withUnsafeBytes(of: enriched.gpuActor) { Array($0) }
            XCTAssertEqual(afterBytes, beforeBytes)
        }
    }

    func testInsertionTimelineRetainsExistingTimestampsAndMarksOnlyNewEvents() {
        let initial = fixtureScene(ids: ["a", "b"])
        var timeline = DayObjectInsertionTimeline(scene: initial)
        XCTAssertEqual(timeline.timestamps, [:])

        timeline.update(scene: fixtureScene(ids: ["a", "b", "c"]), elapsed: 12)
        _ = timeline.renderState(
            activeScene: fixtureScene(ids: ["a", "b", "c"]),
            elapsed: 12
        )
        XCTAssertEqual(timeline.timestamps, ["c": 12])

        timeline.update(scene: fixtureScene(ids: ["a", "b", "c", "d"]), elapsed: 15)
        _ = timeline.renderState(
            activeScene: fixtureScene(ids: ["a", "b", "c", "d"]),
            elapsed: 15
        )
        XCTAssertEqual(timeline.timestamps, ["c": 12, "d": 15])

        timeline.update(scene: fixtureScene(ids: ["a", "b", "c", "d"]), elapsed: 30)
        _ = timeline.renderState(
            activeScene: fixtureScene(ids: ["a", "b", "c", "d"]),
            elapsed: 30
        )
        XCTAssertEqual(timeline.timestamps, ["c": 12, "d": 15])
    }

    func testInsertionTimelineResetsForADifferentDayWithoutFadingTheWholeScene() {
        var timeline = DayObjectInsertionTimeline(scene: fixtureScene(ids: ["a"]))
        timeline.update(scene: fixtureScene(ids: ["a", "b"]), elapsed: 8)
        _ = timeline.renderState(activeScene: fixtureScene(ids: ["a", "b"]), elapsed: 8)
        XCTAssertEqual(timeline.timestamps, ["b": 8])

        let nextDay = DayObjectScene.make(input: .init(
            dayKey: "2026-08-21",
            identity: "tester",
            eventIDs: ["a", "b"],
            motionEnergy: 0.55,
            visualClarity: 0.55,
            reduceMotion: false
        ))
        timeline.update(scene: nextDay, elapsed: 9)

        XCTAssertEqual(timeline.timestamps, [:])
    }

    func testRemovalRetainsActorsThroughReversedLocalEnvelopeThenReleasesThem() throws {
        let original = fixtureScene(ids: ["a", "b"])
        let active = fixtureScene(ids: ["a"])
        let environment = DayObjectEnvironment(
            motionEnergy: 0.55,
            visualClarity: 1,
            reduceMotion: false
        )
        var timeline = DayObjectInsertionTimeline(scene: original)
        timeline.update(scene: active, elapsed: 10)

        let beforeState = timeline.renderState(activeScene: active, elapsed: 10)
        let before = DayObjectRenderFrame.make(
            scene: beforeState.scene,
            environment: environment,
            elapsed: 10,
            insertions: beforeState.insertions,
            removals: beforeState.removals
        )
        let duringState = timeline.renderState(activeScene: active, elapsed: 10.5)
        let during = DayObjectRenderFrame.make(
            scene: duringState.scene,
            environment: environment,
            elapsed: 10.5,
            insertions: duringState.insertions,
            removals: duringState.removals
        )
        let afterState = timeline.renderState(activeScene: active, elapsed: 11.5)

        let beforeRemoved = before.actors.filter { $0.eventID == "b" }
        let duringRemoved = during.actors.filter { $0.eventID == "b" }
        XCTAssertFalse(beforeRemoved.isEmpty)
        XCTAssertEqual(beforeState.removals, ["b": 10])
        XCTAssertEqual(beforeRemoved.map(\.opacity), DayObjectRenderFrame.make(
            scene: original,
            environment: environment,
            elapsed: 10,
            insertions: [:]
        ).actors.filter { $0.eventID == "b" }.map(\.opacity))
        XCTAssertTrue(duringRemoved.allSatisfy { $0.opacity > 0 && $0.opacity < 1 })
        XCTAssertTrue(duringRemoved.allSatisfy { $0.trailLength > 0 })
        XCTAssertFalse(afterState.scene.actors.contains { $0.eventID == "b" })
        XCTAssertTrue(afterState.removals.isEmpty)

        let activeDuring = during.actors.filter { $0.eventID == "a" }
        let activeReference = DayObjectRenderFrame.make(
            scene: active,
            environment: environment,
            elapsed: 10.5,
            insertions: [:]
        ).actors
        XCTAssertEqual(activeDuring, activeReference)
    }

    func testReduceMotionRemovalChangesOpacityOnlyAndDisablesTrails() {
        let original = fixtureScene(ids: ["a", "b"])
        let active = fixtureScene(ids: ["a"])
        let environment = DayObjectEnvironment(
            motionEnergy: 1,
            visualClarity: 1,
            reduceMotion: true
        )
        var timeline = DayObjectInsertionTimeline(scene: original)
        timeline.update(scene: active, elapsed: 4)
        let state = timeline.renderState(activeScene: active, elapsed: 4.5)
        let departing = DayObjectRenderFrame.make(
            scene: state.scene,
            environment: environment,
            elapsed: 4.5,
            insertions: state.insertions,
            removals: state.removals
        ).actors.filter { $0.eventID == "b" }
        let reference = DayObjectRenderFrame.make(
            scene: original,
            environment: environment,
            elapsed: 4.5,
            insertions: [:]
        ).actors.filter { $0.eventID == "b" }

        XCTAssertEqual(departing.map(\.halfSize), reference.map(\.halfSize))
        XCTAssertTrue(departing.allSatisfy { $0.opacity > 0 && $0.opacity < 1 })
        XCTAssertTrue(departing.allSatisfy { $0.trailLength == 0 })
    }

    func testReaddingDuringRemovalCancelsDepartureWithoutDuplicatesOrReroll() {
        let original = fixtureScene(ids: ["a", "b"])
        let removed = fixtureScene(ids: ["a"])
        var timeline = DayObjectInsertionTimeline(scene: original)
        timeline.update(scene: removed, elapsed: 7)
        XCTAssertEqual(
            timeline.renderState(activeScene: removed, elapsed: 7.2).removals,
            ["b": 7]
        )

        timeline.update(scene: original, elapsed: 7.2)
        let restored = timeline.renderState(activeScene: original, elapsed: 7.2)
        XCTAssertTrue(restored.removals.isEmpty)
        XCTAssertFalse(restored.insertions.keys.contains("b"))
        XCTAssertEqual(restored.scene.actors, original.actors)
        XCTAssertEqual(Set(restored.scene.actorIDs).count, restored.scene.actors.count)
    }

    func testCappedReplacementWaitsForDepartureThenStartsInsertionOnItsFirstRenderedFrame() throws {
        let initialIDs = (0...40).map { "event-\($0)" }
        let replacementIDs = Array(initialIDs.dropFirst())
        let initial = capacityFixtureScene(dayKey: "cap-fixture-2", ids: initialIDs)
        let replacement = capacityFixtureScene(dayKey: "cap-fixture-2", ids: replacementIDs)
        XCTAssertEqual(initial.composition.flockSize, 1)
        XCTAssertEqual(initial.actors.count, 40)
        XCTAssertEqual(replacement.actors.count, 40)

        let departingID = DayObjectActorID(eventID: "event-0", memberIndex: 0)
        let replacementID = DayObjectActorID(eventID: "event-40", memberIndex: 0)
        let departingActor = try XCTUnwrap(initial.actors.first { $0.id == departingID })
        let departureDuration = DayObjectRenderFrame.transitionDuration(for: departingActor)
        var timeline = DayObjectInsertionTimeline(scene: initial)
        timeline.update(scene: replacement, elapsed: 10)

        let waitingTime = 10 + departureDuration * 0.5
        let waiting = timeline.renderState(activeScene: replacement, elapsed: waitingTime)
        XCTAssertEqual(waiting.scene.actors.count, 40)
        XCTAssertTrue(waiting.scene.actorIDs.contains(departingID))
        XCTAssertFalse(waiting.scene.actorIDs.contains(replacementID))
        XCTAssertNil(waiting.actorInsertions[replacementID])
        XCTAssertEqual(waiting.actorRemovals[departingID], 10)

        let admittedAt = 10 + departureDuration + 0.001
        let admitted = timeline.renderState(activeScene: replacement, elapsed: admittedAt)
        XCTAssertEqual(admitted.scene.actors.count, 40)
        XCTAssertFalse(admitted.scene.actorIDs.contains(departingID))
        XCTAssertTrue(admitted.scene.actorIDs.contains(replacementID))
        XCTAssertEqual(admitted.actorInsertions[replacementID], admittedAt)
        XCTAssertNil(admitted.actorRemovals[departingID])

        let reduceMotion = DayObjectEnvironment(
            motionEnergy: 1,
            visualClarity: 1,
            reduceMotion: true
        )
        let firstFrame = DayObjectRenderFrame.make(
            scene: admitted.scene,
            environment: reduceMotion,
            elapsed: admittedAt,
            insertions: admitted.insertions,
            removals: admitted.removals,
            actorInsertions: admitted.actorInsertions,
            actorRemovals: admitted.actorRemovals
        )
        let firstReplacement = try XCTUnwrap(firstFrame.actors.first { $0.actorID == replacementID })
        XCTAssertEqual(firstReplacement.opacity, 0)
        XCTAssertEqual(firstReplacement.trailLength, 0)

        let replacementActor = try XCTUnwrap(replacement.actors.first { $0.id == replacementID })
        let insertionDuration = DayObjectRenderFrame.transitionDuration(for: replacementActor)
        let duringTime = admittedAt + insertionDuration * 0.5
        let during = timeline.renderState(activeScene: replacement, elapsed: duringTime)
        XCTAssertEqual(during.actorInsertions[replacementID], admittedAt)
        let duringFrame = DayObjectRenderFrame.make(
            scene: during.scene,
            environment: reduceMotion,
            elapsed: duringTime,
            insertions: during.insertions,
            removals: during.removals,
            actorInsertions: during.actorInsertions,
            actorRemovals: during.actorRemovals
        )
        let duringReplacement = try XCTUnwrap(duringFrame.actors.first { $0.actorID == replacementID })
        let unanimatedFrame = DayObjectRenderFrame.make(
            scene: replacement,
            environment: reduceMotion,
            elapsed: duringTime,
            insertions: [:]
        )
        let unanimatedReplacement = try XCTUnwrap(
            unanimatedFrame.actors.first { $0.actorID == replacementID }
        )
        XCTAssertGreaterThan(duringReplacement.opacity, 0)
        XCTAssertLessThan(duringReplacement.opacity, unanimatedReplacement.opacity)
        XCTAssertEqual(duringReplacement.halfSize, unanimatedReplacement.halfSize)
        XCTAssertEqual(duringReplacement.trailLength, 0)
    }

    func testCappedOrbAdmissionDoesNotRestartAlreadyRenderedActors() throws {
        let initialIDs = (0..<40).map { "event-\($0)" }
        let replacementIDs = Array(initialIDs.dropFirst()) + ["event-40"]
        let initial = capacityFixtureScene(dayKey: "partial-fixture-1", ids: initialIDs)
        let replacement = capacityFixtureScene(dayKey: "partial-fixture-1", ids: replacementIDs)
        XCTAssertEqual(initial.composition.flockSize, 1)
        XCTAssertEqual(initial.actors.count, 40)
        XCTAssertEqual(replacement.actors.count, 40)

        let retainedID = DayObjectActorID(eventID: "event-13", memberIndex: 0)
        let pendingID = DayObjectActorID(eventID: "event-40", memberIndex: 0)
        let departureDurations = initial.actors
            .filter { $0.eventID == "event-0" }
            .map(DayObjectRenderFrame.transitionDuration(for:))
            .sorted()
        XCTAssertEqual(departureDurations.count, 1)

        var timeline = DayObjectInsertionTimeline(scene: initial)
        timeline.update(scene: replacement, elapsed: 20)
        let firstAdmissionTime = 20 + departureDurations[0] + 0.001
        let firstAdmission = timeline.renderState(
            activeScene: replacement,
            elapsed: firstAdmissionTime
        )
        XCTAssertEqual(firstAdmission.scene.actors.count, 40)
        XCTAssertNil(firstAdmission.actorInsertions[retainedID])
        XCTAssertEqual(firstAdmission.actorInsertions[pendingID], firstAdmissionTime)
        XCTAssertTrue(firstAdmission.scene.actorIDs.contains(pendingID))

        timeline.update(scene: replacement, elapsed: firstAdmissionTime + 0.01)
        let repeated = timeline.renderState(
            activeScene: replacement,
            elapsed: firstAdmissionTime + 0.02
        )
        XCTAssertEqual(repeated.actorInsertions[pendingID], firstAdmissionTime)

        let environment = DayObjectEnvironment(
            motionEnergy: 0.55,
            visualClarity: 1,
            reduceMotion: false
        )
        let frame = DayObjectRenderFrame.make(
            scene: firstAdmission.scene,
            environment: environment,
            elapsed: firstAdmissionTime,
            insertions: firstAdmission.insertions,
            removals: firstAdmission.removals,
            actorInsertions: firstAdmission.actorInsertions,
            actorRemovals: firstAdmission.actorRemovals
        )
        let reference = DayObjectRenderFrame.make(
            scene: replacement,
            environment: environment,
            elapsed: firstAdmissionTime,
            insertions: [:]
        )
        XCTAssertEqual(
            frame.actors.first { $0.actorID == retainedID },
            reference.actors.first { $0.actorID == retainedID }
        )
        XCTAssertEqual(frame.actors.first { $0.actorID == pendingID }?.opacity, 0)
    }

    func testCappedPendingQueueIsDeterministicAcrossConcurrentChangesAndReadd() throws {
        let initialIDs = (0...41).map { "event-\($0)" }
        let initial = capacityFixtureScene(dayKey: "cap-fixture-2", ids: initialIDs)
        let firstReplacementIDs = Array(initialIDs.dropFirst(2))
        let firstReplacement = capacityFixtureScene(
            dayKey: "cap-fixture-2",
            ids: firstReplacementIDs
        )
        let replacement40 = DayObjectActorID(eventID: "event-40", memberIndex: 0)
        let replacement41 = DayObjectActorID(eventID: "event-41", memberIndex: 0)
        let departures = initial.actors
            .filter { $0.eventID == "event-0" || $0.eventID == "event-1" }
            .map { ($0.id, DayObjectRenderFrame.transitionDuration(for: $0)) }
            .sorted { $0.1 < $1.1 }
        XCTAssertEqual(departures.count, 2)

        var timeline = DayObjectInsertionTimeline(scene: initial)
        timeline.update(scene: firstReplacement, elapsed: 30)
        let oneSlotTime = 30 + (departures[0].1 + departures[1].1) * 0.5
        let oneSlot = timeline.renderState(activeScene: firstReplacement, elapsed: oneSlotTime)
        XCTAssertEqual(oneSlot.scene.actors.count, 40)
        XCTAssertEqual(oneSlot.actorInsertions[replacement40], oneSlotTime)
        XCTAssertNil(oneSlot.actorInsertions[replacement41])

        let concurrentIDs = Array(initialIDs.dropFirst(2).dropLast()) + ["event-42"]
        let concurrent = capacityFixtureScene(dayKey: "cap-fixture-2", ids: concurrentIDs)
        let replacement42 = DayObjectActorID(eventID: "event-42", memberIndex: 0)
        timeline.update(scene: concurrent, elapsed: oneSlotTime + 0.01)
        let allSlotsTime = 30 + departures[1].1 + 0.001
        let allSlots = timeline.renderState(activeScene: concurrent, elapsed: allSlotsTime)
        XCTAssertEqual(allSlots.scene.actors.count, 40)
        XCTAssertEqual(allSlots.actorInsertions[replacement40], oneSlotTime)
        XCTAssertNil(allSlots.actorInsertions[replacement41])
        XCTAssertEqual(allSlots.actorInsertions[replacement42], allSlotsTime)

        var readdTimeline = DayObjectInsertionTimeline(scene: initial)
        readdTimeline.update(scene: firstReplacement, elapsed: 40)
        let readdTime = 40 + departures[0].1 * 0.5
        _ = readdTimeline.renderState(activeScene: firstReplacement, elapsed: readdTime)
        readdTimeline.update(scene: initial, elapsed: readdTime)
        let restored = readdTimeline.renderState(activeScene: initial, elapsed: readdTime)
        XCTAssertEqual(restored.scene.actors, initial.actors)
        XCTAssertEqual(restored.scene.actors.count, 40)
        XCTAssertTrue(restored.actorInsertions.isEmpty)
        XCTAssertTrue(restored.actorRemovals.isEmpty)
    }

    func testRemovalStateResetsAcrossDailyRootSwitch() {
        let original = fixtureScene(ids: ["a", "b"])
        var timeline = DayObjectInsertionTimeline(scene: original)
        timeline.update(scene: fixtureScene(ids: ["a"]), elapsed: 3)

        let nextDay = DayObjectScene.make(input: .init(
            dayKey: "2026-08-21",
            identity: "tester",
            eventIDs: ["a"],
            motionEnergy: 0.55,
            visualClarity: 0.55,
            reduceMotion: false
        ))
        timeline.update(scene: nextDay, elapsed: 3.2)
        let state = timeline.renderState(activeScene: nextDay, elapsed: 3.2)

        XCTAssertEqual(state.scene, nextDay)
        XCTAssertTrue(state.insertions.isEmpty)
        XCTAssertTrue(state.removals.isEmpty)
    }

    func testInsertionEnvelopeStartsAtZeroOpacityAndSeventyPercentScale() {
        let scene = fixtureScene(ids: ["new"])
        let environment = DayObjectEnvironment(motionEnergy: 0.55, visualClarity: 0.55, reduceMotion: false)
        let scoreState = DayObjectRenderFrame.make(scene: scene, environment: environment, elapsed: 5, insertions: [:])
        let insertedState = DayObjectRenderFrame.make(scene: scene, environment: environment, elapsed: 5, insertions: ["new": 5])

        XCTAssertTrue(insertedState.actors.allSatisfy { $0.opacity == 0 })
        for (scoreActor, insertedActor) in zip(scoreState.actors, insertedState.actors) {
            XCTAssertEqual(insertedActor.halfSize, scoreActor.halfSize * 0.7)
        }
    }

    func testReduceMotionDisablesTrailsAndIsDeterministic() {
        let scene = fixtureScene(ids: ["a", "b"])
        let environment = DayObjectEnvironment(motionEnergy: 1, visualClarity: 0.4, reduceMotion: true)
        let first = DayObjectRenderFrame.make(scene: scene, environment: environment, elapsed: 12, insertions: [:])
        let second = DayObjectRenderFrame.make(scene: scene, environment: environment, elapsed: 12, insertions: [:])

        XCTAssertEqual(first, second)
        XCTAssertTrue(first.actors.allSatisfy { $0.trailLength == 0 })
        XCTAssertTrue(first.postProcess.grainPhase == 0)
    }

    func testReduceMotionInsertionUsesOpacityWithoutScaleAnimation() {
        let scene = fixtureScene(ids: ["new"])
        let environment = DayObjectEnvironment(
            motionEnergy: 1,
            visualClarity: 0.4,
            reduceMotion: true
        )
        let scoreState = DayObjectRenderFrame.make(
            scene: scene,
            environment: environment,
            elapsed: 5,
            insertions: [:]
        )
        let insertedState = DayObjectRenderFrame.make(
            scene: scene,
            environment: environment,
            elapsed: 5,
            insertions: ["new": 5]
        )

        XCTAssertTrue(insertedState.actors.allSatisfy { $0.opacity == 0 })
        for (scoreActor, insertedActor) in zip(scoreState.actors, insertedState.actors) {
            XCTAssertEqual(insertedActor.halfSize, scoreActor.halfSize)
        }
    }

    func testActorsAreSortedByDepthThenStableID() {
        let scene = fixtureScene(ids: ["z", "a", "m"])
        let environment = DayObjectEnvironment(motionEnergy: 0.55, visualClarity: 0.55, reduceMotion: false)
        let actors = DayObjectRenderFrame.make(scene: scene, environment: environment, elapsed: 12, insertions: [:]).actors

        XCTAssertEqual(actors, actors.sorted { lhs, rhs in
            lhs.depth == rhs.depth ? lhs.actorID < rhs.actorID : lhs.depth < rhs.depth
        })
    }

    func testGPUActorHasStableExplicitMetalLayout() {
        XCTAssertEqual(DayObjectGPUActor.metalAlignment, 16)
        XCTAssertEqual(DayObjectGPUActor.metalStride, 80)
        XCTAssertEqual(MemoryLayout<DayObjectGPUActor>.alignment, DayObjectGPUActor.metalAlignment)
        XCTAssertEqual(MemoryLayout<DayObjectGPUActor>.size, DayObjectGPUActor.metalStride)
        XCTAssertEqual(MemoryLayout<DayObjectGPUActor>.stride, DayObjectGPUActor.metalStride)
        XCTAssertEqual(MemoryLayout<DayObjectGPUActor>.offset(of: \DayObjectGPUActor.position), 0)
        XCTAssertEqual(MemoryLayout<DayObjectGPUActor>.offset(of: \DayObjectGPUActor.direction), 8)
        XCTAssertEqual(MemoryLayout<DayObjectGPUActor>.offset(of: \DayObjectGPUActor.halfSize), 16)
        XCTAssertEqual(MemoryLayout<DayObjectGPUActor>.offset(of: \DayObjectGPUActor.color), 32)
        XCTAssertEqual(MemoryLayout<DayObjectGPUActor>.offset(of: \DayObjectGPUActor.opacity), 48)
        XCTAssertEqual(MemoryLayout<DayObjectGPUActor>.offset(of: \DayObjectGPUActor.trailLength), 52)
        XCTAssertEqual(MemoryLayout<DayObjectGPUActor>.offset(of: \DayObjectGPUActor.shape), 56)
        XCTAssertEqual(MemoryLayout<DayObjectGPUActor>.offset(of: \DayObjectGPUActor.fill), 60)
        XCTAssertEqual(MemoryLayout<DayObjectGPUActor>.offset(of: \DayObjectGPUActor.depth), 64)
    }

    func testActorUniformsUseInverseSquareRootEnergyAndScreenPixelScale() {
        let fixtures: [(count: Int, expected: Float)] = [
            (0, 0),
            (1, 1),
            (4, 0.5),
            (16, 0.25),
            (40, 0.158_113_88),
        ]

        for fixture in fixtures {
            let uniforms = DayObjectsActorUniforms(
                resolution: SIMD2(1_179, 2_556),
                visibleActorCount: fixture.count
            )
            XCTAssertEqual(
                uniforms.energyNormalization,
                fixture.expected,
                accuracy: 0.000_001
            )
            XCTAssertTrue(uniforms.energyNormalization.isFinite)
            XCTAssertEqual(uniforms.shortSidePixels, 1_179)
        }

        XCTAssertEqual(MemoryLayout<DayObjectsActorUniforms>.size, 128)
        XCTAssertEqual(MemoryLayout<DayObjectsActorUniforms>.stride, 128)
        XCTAssertEqual(MemoryLayout<DayObjectsActorUniforms>.offset(of: \.resolution), 0)
        XCTAssertEqual(MemoryLayout<DayObjectsActorUniforms>.offset(of: \.energyNormalization), 8)
        XCTAssertEqual(MemoryLayout<DayObjectsActorUniforms>.offset(of: \.shortSidePixels), 12)
    }

    func testStaticRadialActorUniformsMatchMetalABIAndPreserveDailyParameters() {
        let style = DayObjectRadialFillStyle(
            colors: [
                DayObjectRGB(hex: "ff3355").linearRGB,
                DayObjectRGB(hex: "33ddaa").linearRGB,
                DayObjectRGB(hex: "4455ff").linearRGB,
            ],
            radius: 0.83,
            focalDistance: 0.42,
            focalAngle: 1.1,
            falloff: 0.24,
            mixing: 0.68,
            distortion: 0.31,
            distortionShift: -0.27,
            distortionFrequency: 7,
            rotation: 0.74,
            offset: SIMD2(0.12, -0.08),
            preset: .crossSections,
            banding: 0.22
        )
        let uniforms = DayObjectsActorUniforms(
            resolution: SIMD2(1_179, 2_556),
            visibleActorCount: 4,
            radialFillStyle: style
        )

        XCTAssertEqual(MemoryLayout<DayObjectsActorUniforms>.alignment, 16)
        XCTAssertEqual(MemoryLayout<DayObjectsActorUniforms>.size, 128)
        XCTAssertEqual(MemoryLayout<DayObjectsActorUniforms>.stride, 128)
        XCTAssertEqual(MemoryLayout<DayObjectsActorUniforms>.offset(of: \.resolution), 0)
        XCTAssertEqual(MemoryLayout<DayObjectsActorUniforms>.offset(of: \.energyNormalization), 8)
        XCTAssertEqual(MemoryLayout<DayObjectsActorUniforms>.offset(of: \.shortSidePixels), 12)
        XCTAssertEqual(MemoryLayout<DayObjectsActorUniforms>.offset(of: \.radialColor0), 16)
        XCTAssertEqual(MemoryLayout<DayObjectsActorUniforms>.offset(of: \.radialColor1), 32)
        XCTAssertEqual(MemoryLayout<DayObjectsActorUniforms>.offset(of: \.radialColor2), 48)
        XCTAssertEqual(MemoryLayout<DayObjectsActorUniforms>.offset(of: \.radialParameters0), 64)
        XCTAssertEqual(MemoryLayout<DayObjectsActorUniforms>.offset(of: \.radialParameters1), 80)
        XCTAssertEqual(MemoryLayout<DayObjectsActorUniforms>.offset(of: \.radialParameters2), 96)
        XCTAssertEqual(MemoryLayout<DayObjectsActorUniforms>.offset(of: \.radialParameters3), 112)
        XCTAssertEqual(uniforms.radialColor0, SIMD4(style.colors[0], 1))
        XCTAssertEqual(uniforms.radialColor1, SIMD4(style.colors[1], 1))
        XCTAssertEqual(uniforms.radialColor2, SIMD4(style.colors[2], 1))
        XCTAssertEqual(uniforms.radialParameters0, SIMD4(0.83, 0.42, 1.1, 0.24))
        XCTAssertEqual(uniforms.radialParameters1, SIMD4(0.68, 0.31, -0.27, 7))
        XCTAssertEqual(uniforms.radialParameters2, SIMD4(0.74, 0.12, -0.08, 3))
        XCTAssertEqual(uniforms.radialParameters3, SIMD4(3, 0.22, 0.18, 0.16))
    }

    func testActorRadialVariationIsStableBoundedAndIndependentPerActor() {
        let ids = (0..<24).map { "event-\($0)" }
        let scene = DayObjectScene.make(input: DayObjectSceneInput(
            dayKey: "radial-actor-variation",
            identity: "tester",
            eventIDs: ids,
            motionEnergy: 0.55,
            visualClarity: 0.55,
            reduceMotion: false
        ))
        let frame = DayObjectRenderFrame.make(
            scene: scene,
            environment: .init(motionEnergy: 0.55, visualClarity: 0.55, reduceMotion: false),
            elapsed: 12,
            insertions: [:]
        )
        let repeated = DayObjectRenderFrame.make(
            scene: scene,
            environment: .init(motionEnergy: 0.55, visualClarity: 0.55, reduceMotion: false),
            elapsed: 12,
            insertions: [:]
        )
        let variations = frame.actors.map(\.gpuActor.radialVariation)

        XCTAssertEqual(frame, repeated)
        XCTAssertTrue(variations.allSatisfy { (-1...1).contains($0) })
        XCTAssertGreaterThan(Set(variations).count, 8)
        XCTAssertEqual(MemoryLayout<DayObjectGPUActor>.offset(of: \.radialVariation), 68)
        XCTAssertEqual(MemoryLayout<DayObjectGPUActor>.stride, 80)
    }

    func testStaticRadialGPUUsesOneTwoAndThreeColorsWithoutChangingTheBodyMask() throws {
        let harness = try ActorRenderHarness(width: 128, height: 128)
        let actor = DayObjectGPUActor(
            position: .zero,
            direction: SIMD2(1, 0),
            halfSize: SIMD2(0.34, 0.27),
            color: SIMD4(1, 1, 1, 1),
            opacity: 1,
            trailLength: 0,
            shape: 1,
            fill: 2,
            depth: 0,
            radialVariation: 0.63
        )
        let sourceColors = [
            DayObjectRGB(hex: "ff3355").linearRGB,
            DayObjectRGB(hex: "33ddaa").linearRGB,
            DayObjectRGB(hex: "4455ff").linearRGB,
        ]
        let captures = try (1...3).map { count in
            try harness.render(
                [actor],
                radialFillStyle: DayObjectRadialFillStyle(
                    colors: Array(sourceColors.prefix(count)),
                    radius: 0.83,
                    focalDistance: 0.42,
                    focalAngle: 1.1,
                    falloff: 0.24,
                    mixing: 0.68,
                    distortion: 0.31,
                    distortionShift: -0.27,
                    distortionFrequency: 7,
                    rotation: 0.74,
                    offset: SIMD2(0.12, -0.08)
                )
            )
        }

        XCTAssertEqual(captures[0].alpha, captures[1].alpha)
        XCTAssertEqual(captures[1].alpha, captures[2].alpha)
        XCTAssertGreaterThan(captures[0].meanAbsoluteRGBDifference(from: captures[1]), 0.01)
        XCTAssertGreaterThan(captures[1].meanAbsoluteRGBDifference(from: captures[2]), 0.01)

        let alternateActor = DayObjectGPUActor(
            position: .zero,
            direction: SIMD2(1, 0),
            halfSize: SIMD2(0.34, 0.27),
            color: SIMD4(1, 1, 1, 1),
            opacity: 1,
            trailLength: 0,
            shape: 1,
            fill: 2,
            depth: 0,
            radialVariation: -0.63
        )
        let alternate = try harness.render(
            [alternateActor],
            radialFillStyle: DayObjectRadialFillStyle(
                colors: sourceColors,
                radius: 0.83,
                focalDistance: 0.42,
                focalAngle: 1.1,
                falloff: 0.24,
                mixing: 0.68,
                distortion: 0.31,
                distortionShift: -0.27,
                distortionFrequency: 7,
                rotation: 0.74,
                offset: SIMD2(0.12, -0.08)
            )
        )
        XCTAssertEqual(captures[2].alpha, alternate.alpha)
        XCTAssertGreaterThan(captures[2].meanAbsoluteRGBDifference(from: alternate), 0.005)
    }

    func testActorPipelineUsesPremultipliedAlphaAndExactShaderABI() throws {
        let device = try XCTUnwrap(MTLCreateSystemDefaultDevice())
        let library = try XCTUnwrap(device.makeDefaultLibrary())
        let descriptor = try XCTUnwrap(DayObjectsActorRendering.pipelineDescriptor(
            library: library,
            pixelFormat: .rgba16Float
        ))
        let attachment = try XCTUnwrap(descriptor.colorAttachments[0])

        XCTAssertEqual(descriptor.vertexFunction?.name, "dayObjectsActorVertex")
        XCTAssertEqual(descriptor.fragmentFunction?.name, "dayObjectsActorFragment")
        XCTAssertTrue(attachment.isBlendingEnabled)
        XCTAssertEqual(attachment.sourceRGBBlendFactor, .one)
        XCTAssertEqual(attachment.destinationRGBBlendFactor, .oneMinusSourceAlpha)
        XCTAssertEqual(attachment.sourceAlphaBlendFactor, .one)
        XCTAssertEqual(attachment.destinationAlphaBlendFactor, .oneMinusSourceAlpha)
        XCTAssertNoThrow(try device.makeRenderPipelineState(descriptor: descriptor))
    }

    func testActorShaderTrailsOpposeForwardAndReversedVelocity() throws {
        let harness = try ActorRenderHarness(width: 128, height: 64)
        let forward = gpuActor(direction: SIMD2(1, 0), trailLength: 0.22)
        let reversed = gpuActor(direction: SIMD2(-1, 0), trailLength: 0.22)
        let forwardAlpha = try harness.render([forward])
        let reversedAlpha = try harness.render([reversed])
        let centerX = harness.width / 2

        XCTAssertGreaterThan(forwardAlpha[centerX, harness.height / 2], 0.5)
        XCTAssertGreaterThan(reversedAlpha[centerX, harness.height / 2], 0.5)
        XCTAssertLessThan(forwardAlpha.weightedMeanX, Double(centerX) - 0.75)
        XCTAssertGreaterThan(reversedAlpha.weightedMeanX, Double(centerX) + 0.75)
    }

    func testActorEnergyNormalizationPreservesBodiesWhileDimmingTrails() throws {
        let harness = try ActorRenderHarness(width: 128, height: 64)
        let actor = gpuActor(direction: SIMD2(1, 0), trailLength: 0.22)
        let sparse = try harness.render([actor], visibleActorCount: 1)
        let dense = try harness.render([actor], visibleActorCount: 40)
        let centerX = harness.width / 2
        let centerY = harness.height / 2

        XCTAssertGreaterThan(dense[centerX, centerY], 0.8)
        XCTAssertLessThan(dense[centerX - 12, centerY], sparse[centerX - 12, centerY])
    }

    func testActorShaderRendersOnlyCircleDerivedOrbFamilies() throws {
        let harness = try ActorRenderHarness(width: 192, height: 160)

        for shape in UInt32(0)...UInt32(3) {
            let actor = DayObjectGPUActor(
                position: .zero,
                direction: SIMD2(1, 0),
                halfSize: SIMD2(0.28, 0.22),
                color: SIMD4(0.9, 0.3, 0.1, 1),
                opacity: 1,
                trailLength: 0,
                shape: shape,
                fill: 2,
                depth: 0
            )
            let alpha = try harness.render([actor])
            XCTAssertGreaterThan(alpha[harness.width / 2, harness.height / 2], 0.8)
            XCTAssertGreaterThan(alpha.nonzeroPixelCount, 2_500)
            XCTAssertLessThan(alpha[0, 0], 0.01)
            XCTAssertLessThan(alpha[harness.width - 1, harness.height - 1], 0.01)
        }
    }

    func testCloseOrbMergeFieldsCreateSoftBridgeWhileSeparatedBodiesStayDistinct() throws {
        let harness = try ActorRenderHarness(width: 256, height: 128)
        func actor(x: Float) -> DayObjectGPUActor {
            DayObjectGPUActor(
                position: SIMD2(x, 0),
                direction: SIMD2(1, 0),
                halfSize: SIMD2(0.16, 0.15),
                color: SIMD4(0.9, 0.3, 0.1, 1),
                opacity: 1,
                trailLength: 0,
                shape: 0,
                fill: 2,
                depth: 0
            )
        }

        let isolated = try harness.render([actor(x: -0.18)])
        let close = try harness.render([actor(x: -0.18), actor(x: 0.18)])
        let separated = try harness.render([actor(x: -0.28), actor(x: 0.28)])
        let midpoint = (x: harness.width / 2, y: harness.height / 2)

        XCTAssertGreaterThan(close[midpoint.x, midpoint.y], isolated[midpoint.x, midpoint.y] + 0.025)
        XCTAssertLessThan(separated[midpoint.x, midpoint.y], 0.01)
    }

    func testActorShaderRendersDeterministicOneTenTwentyFourAndFortyActorFixtures() throws {
        let scene = fixtureScene(ids: (0..<40).map { "fixture-\($0)" })
        let environment = DayObjectEnvironment(
            motionEnergy: 0.8,
            visualClarity: 1,
            reduceMotion: false
        )
        let frame = DayObjectRenderFrame.make(
            scene: scene,
            environment: environment,
            elapsed: 11.25,
            insertions: [:],
            canvasAspect: 1.5
        )
        XCTAssertEqual(frame.actors.count, 40)

        let harness = try ActorRenderHarness(width: 192, height: 128)
        var coverages = [Int]()
        var alphaEnergies = [Double]()
        for count in [1, 10, 24, 40] {
            let prefix = Array(frame.actors.prefix(count))
            let upload = DayObjectsActorUpload(
                actors: prefix,
                resolution: SIMD2(Float(harness.width), Float(harness.height))
            )
            XCTAssertEqual(upload.actors, prefix.map(\.gpuActor))
            XCTAssertEqual(upload.actors.count, count)
            XCTAssertTrue(upload.uniforms.energyNormalization.isFinite)

            let alpha = try harness.render(upload)
            coverages.append(alpha.nonzeroPixelCount)
            alphaEnergies.append(alpha.total)
            XCTAssertGreaterThan(alpha.nonzeroPixelCount, 0)
            XCTAssertGreaterThan(alpha.total, 0)
            print(
                "DAY_OBJECTS_ACTOR_FIXTURE count=\(count) "
                    + "coverage=\(alpha.nonzeroPixelCount) alpha=\(alpha.total)"
            )
        }

        for (earlier, later) in zip(coverages, coverages.dropFirst()) {
            XCTAssertGreaterThan(later, earlier)
        }
        for (earlier, later) in zip(alphaEnergies, alphaEnergies.dropFirst()) {
            XCTAssertGreaterThan(later, earlier)
        }
    }

    func testInFlightSchedulerRecyclesOnlyCompletedSlotsDeterministically() {
        let scheduler = DayObjectsInFlightScheduler(slotCount: 3)
        XCTAssertEqual(scheduler.slotCount, 3)

        let first = scheduler.acquire()
        let second = scheduler.acquire()
        let third = scheduler.acquire()
        XCTAssertEqual([first, second, third].compactMap { $0 }, [0, 1, 2])
        XCTAssertNil(scheduler.acquire())

        scheduler.complete(1)
        XCTAssertEqual(scheduler.acquire(), 1)
        XCTAssertNil(scheduler.acquire())

        scheduler.complete(0)
        scheduler.complete(0)
        XCTAssertEqual(scheduler.acquire(), 0)
        XCTAssertNil(scheduler.acquire())
    }

    func testActorBufferRingUsesThreeDistinctABIBuffersUntilGPUCompletion() throws {
        let device = try XCTUnwrap(MTLCreateSystemDefaultDevice())
        let queue = try XCTUnwrap(device.makeCommandQueue())
        let ring = try XCTUnwrap(DayObjectsActorBufferRing(
            device: device,
            slotCount: 3,
            actorCapacity: DayObjectScene.maxActors
        ))
        XCTAssertEqual(ring.slotCount, 3)
        XCTAssertEqual(ring.bufferLength, DayObjectGPUActor.metalStride * 40)

        let leases = try (0..<3).map { _ in
            try XCTUnwrap(ring.acquire())
        }
        XCTAssertEqual(Set(leases.map { ObjectIdentifier($0.buffer) }).count, 3)
        XCTAssertNil(ring.acquire())

        let commandBuffers = try leases.map { lease -> MTLCommandBuffer in
            let commandBuffer = try XCTUnwrap(queue.makeCommandBuffer())
            ring.submit(lease, on: commandBuffer)
            return commandBuffer
        }
        XCTAssertNil(ring.acquire())
        commandBuffers.forEach { $0.commit() }
        commandBuffers.forEach { $0.waitUntilCompleted() }
        XCTAssertTrue(commandBuffers.allSatisfy { $0.status == .completed })

        let recycled = try (0..<3).map { _ in
            try XCTUnwrap(ring.acquire())
        }
        XCTAssertEqual(Set(recycled.map(\.slot)), Set([0, 1, 2]))
        recycled.forEach(ring.abandon)
    }

    func testRenderTargetPlanUsesBoundedHalfResolutionBackgroundAndFullSizeSceneTargets() {
        let plan = DayObjectsRenderTargetPlan(drawableWidth: 1_179, drawableHeight: 2_556)

        XCTAssertEqual(plan.background.width, 589)
        XCTAssertEqual(plan.background.height, 1_278)
        XCTAssertLessThanOrEqual(plan.background.width, 1_179 / 2)
        XCTAssertLessThanOrEqual(plan.background.height, 2_556 / 2)
        XCTAssertLessThanOrEqual(plan.background.pixelCount, 1_000_000)
        XCTAssertEqual(plan.scene, DayObjectsRenderTargetDescriptor(width: 1_179, height: 2_556))
        XCTAssertEqual(plan.blurPingPong, [
            DayObjectsRenderTargetDescriptor(width: 1_179, height: 2_556),
            DayObjectsRenderTargetDescriptor(width: 1_179, height: 2_556),
        ])
    }

    func testRenderTargetPlanCapsLargeBackgroundTargetsAtOneMillionPixels() {
        let plan = DayObjectsRenderTargetPlan(drawableWidth: 8_000, drawableHeight: 6_000)

        XCTAssertEqual(plan.background, DayObjectsRenderTargetDescriptor(width: 1_154, height: 866))
        XCTAssertLessThanOrEqual(plan.background.pixelCount, 1_000_000)
    }

    func testRenderTargetPlanRemainsWithinPixelBudgetForExtremeIntegerInputs() {
        for dimensions in [
            (Int.max, Int.max),
            (Int.max, 1),
            (1, Int.max),
            (Int.max, 2_556),
            (1_179, Int.max),
        ] {
            let plan = DayObjectsRenderTargetPlan(
                drawableWidth: dimensions.0,
                drawableHeight: dimensions.1
            )
            XCTAssertGreaterThanOrEqual(plan.background.width, 1)
            XCTAssertGreaterThanOrEqual(plan.background.height, 1)
            XCTAssertLessThanOrEqual(
                plan.background.pixelCount,
                DayObjectsRenderTargetPlan.maximumBackgroundPixels,
                "dimensions=\(dimensions) background=\(plan.background)"
            )
        }
    }

    func testStaticRendererRequestsItsFrameOnlyAfterLayoutHasANonzeroDrawable() {
        XCTAssertFalse(DayObjectsRenderer.shouldDrawStaticFrame(
            isPaused: true,
            drawableSize: .zero
        ))
        XCTAssertTrue(DayObjectsRenderer.shouldDrawStaticFrame(
            isPaused: true,
            drawableSize: CGSize(width: 402, height: 524)
        ))
        XCTAssertFalse(DayObjectsRenderer.shouldDrawStaticFrame(
            isPaused: false,
            drawableSize: CGSize(width: 402, height: 524)
        ))
    }

    func testRendererClockDoesNotWrapAtOneHour() {
        var now = 10_000.0
        let clock = DayObjectsClock(now: { now })

        XCTAssertEqual(clock.elapsedTime, 0, accuracy: 0.000_001)
        now += 3_601.25
        XCTAssertEqual(clock.elapsedTime, 3_601.25, accuracy: 0.000_001)
    }

    func testRendererClockRetainsElapsedTimeWhilePaused() {
        var now = 100.0
        let clock = DayObjectsClock(now: { now })

        now = 112.0
        clock.setPaused(true)
        now = 212.0
        XCTAssertEqual(clock.elapsedTime, 12, accuracy: 0.000_001)

        clock.setPaused(false)
        now = 215.5
        XCTAssertEqual(clock.elapsedTime, 15.5, accuracy: 0.000_001)
    }

    private func gpuActor(
        direction: SIMD2<Float>,
        trailLength: Float
    ) -> DayObjectGPUActor {
        DayObjectGPUActor(
            position: .zero,
            direction: direction,
            halfSize: SIMD2(0.08, 0.025),
            color: SIMD4(0.9, 0.3, 0.1, 1),
            opacity: 1,
            trailLength: trailLength,
            shape: 0,
            fill: 0,
            depth: 0
        )
    }

    private func averagePaletteLuminance(_ scene: DayObjectScene) -> Double {
        scene.palette.colors.reduce(0) {
            $0 + relativeLuminance($1.linearRGB)
        } / Double(scene.palette.colors.count)
    }
}

private final class ActorRenderHarness {
    let width: Int
    let height: Int

    private let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    private let pipeline: MTLRenderPipelineState
    private let quadBuffer: MTLBuffer

    init(width: Int, height: Int) throws {
        self.width = width
        self.height = height
        let renderDevice = try XCTUnwrap(MTLCreateSystemDefaultDevice())
        let renderCommandQueue = try XCTUnwrap(renderDevice.makeCommandQueue())
        let library = try XCTUnwrap(renderDevice.makeDefaultLibrary())
        let descriptor = try XCTUnwrap(DayObjectsActorRendering.pipelineDescriptor(
            library: library,
            pixelFormat: .rgba16Float
        ))
        let renderPipeline = try renderDevice.makeRenderPipelineState(descriptor: descriptor)

        let vertices: [SIMD2<Float>] = [
            SIMD2(-1, -1),
            SIMD2(1, -1),
            SIMD2(-1, 1),
            SIMD2(1, 1),
        ]
        let renderQuadBuffer = try XCTUnwrap(vertices.withUnsafeBytes { bytes -> MTLBuffer? in
            guard let baseAddress = bytes.baseAddress else { return nil }
            return renderDevice.makeBuffer(
                bytes: baseAddress,
                length: bytes.count,
                options: .storageModeShared
            )
        })
        device = renderDevice
        commandQueue = renderCommandQueue
        pipeline = renderPipeline
        quadBuffer = renderQuadBuffer
    }

    func render(_ actors: [DayObjectGPUActor]) throws -> ActorAlphaCapture {
        try render(actors, visibleActorCount: actors.filter { $0.opacity > 0 }.count)
    }

    func render(
        _ actors: [DayObjectGPUActor],
        visibleActorCount: Int
    ) throws -> ActorAlphaCapture {
        let uniforms = DayObjectsActorUniforms(
            resolution: SIMD2(Float(width), Float(height)),
            visibleActorCount: visibleActorCount
        )
        return try render(actors: actors, uniforms: uniforms)
    }

    func render(
        _ actors: [DayObjectGPUActor],
        radialFillStyle: DayObjectRadialFillStyle
    ) throws -> ActorAlphaCapture {
        let uniforms = DayObjectsActorUniforms(
            resolution: SIMD2(Float(width), Float(height)),
            visibleActorCount: actors.filter { $0.opacity > 0 }.count,
            radialFillStyle: radialFillStyle
        )
        return try render(actors: actors, uniforms: uniforms)
    }

    func render(_ upload: DayObjectsActorUpload) throws -> ActorAlphaCapture {
        try render(actors: upload.actors, uniforms: upload.uniforms)
    }

    private func render(
        actors: [DayObjectGPUActor],
        uniforms rawUniforms: DayObjectsActorUniforms
    ) throws -> ActorAlphaCapture {
        let textureDescriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba16Float,
            width: width,
            height: height,
            mipmapped: false
        )
        textureDescriptor.storageMode = .shared
        textureDescriptor.usage = [.renderTarget, .shaderRead]
        let texture = try XCTUnwrap(device.makeTexture(descriptor: textureDescriptor))
        let actorBuffer = try XCTUnwrap(actors.withUnsafeBytes { bytes -> MTLBuffer? in
            guard let baseAddress = bytes.baseAddress, !bytes.isEmpty else {
                return device.makeBuffer(length: DayObjectGPUActor.metalStride)
            }
            return device.makeBuffer(
                bytes: baseAddress,
                length: bytes.count,
                options: .storageModeShared
            )
        })

        let renderPass = MTLRenderPassDescriptor()
        renderPass.colorAttachments[0].texture = texture
        renderPass.colorAttachments[0].loadAction = .clear
        renderPass.colorAttachments[0].storeAction = .store
        renderPass.colorAttachments[0].clearColor = MTLClearColorMake(0, 0, 0, 0)

        let commandBuffer = try XCTUnwrap(commandQueue.makeCommandBuffer())
        let encoder = try XCTUnwrap(commandBuffer.makeRenderCommandEncoder(descriptor: renderPass))
        var uniforms = rawUniforms
        encoder.setRenderPipelineState(pipeline)
        encoder.setVertexBuffer(quadBuffer, offset: 0, index: 0)
        encoder.setVertexBuffer(actorBuffer, offset: 0, index: 1)
        encoder.setVertexBytes(
            &uniforms,
            length: MemoryLayout<DayObjectsActorUniforms>.stride,
            index: 2
        )
        encoder.setFragmentBytes(
            &uniforms,
            length: MemoryLayout<DayObjectsActorUniforms>.stride,
            index: 2
        )
        if !actors.isEmpty {
            encoder.drawPrimitives(
                type: .triangleStrip,
                vertexStart: 0,
                vertexCount: 4,
                instanceCount: actors.count
            )
        }
        encoder.endEncoding()
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
        XCTAssertEqual(commandBuffer.status, .completed)
        XCTAssertNil(commandBuffer.error)

        var pixels = [UInt16](repeating: 0, count: width * height * 4)
        texture.getBytes(
            &pixels,
            bytesPerRow: width * 4 * MemoryLayout<UInt16>.stride,
            from: MTLRegionMake2D(0, 0, width, height),
            mipmapLevel: 0
        )
        let alpha = stride(from: 3, to: pixels.count, by: 4).map {
            Float(Float16(bitPattern: pixels[$0]))
        }
        let rgb = stride(from: 0, to: pixels.count, by: 4).map { index in
            SIMD3<Float>(
                Float(Float16(bitPattern: pixels[index])),
                Float(Float16(bitPattern: pixels[index + 1])),
                Float(Float16(bitPattern: pixels[index + 2]))
            )
        }
        return ActorAlphaCapture(width: width, height: height, alpha: alpha, rgb: rgb)
    }
}

private struct ActorAlphaCapture {
    let width: Int
    let height: Int
    let alpha: [Float]
    let rgb: [SIMD3<Float>]

    subscript(x: Int, y: Int) -> Float {
        alpha[y * width + x]
    }

    var total: Double {
        alpha.reduce(0) { $0 + Double($1) }
    }

    var nonzeroPixelCount: Int {
        alpha.filter { $0 > 0.002 }.count
    }

    func meanAbsoluteRGBDifference(from other: ActorAlphaCapture) -> Double {
        guard rgb.count == other.rgb.count, !rgb.isEmpty else { return 0 }
        let total = zip(rgb, other.rgb).reduce(0.0) { result, pair in
            result
                + Double(abs(pair.0.x - pair.1.x))
                + Double(abs(pair.0.y - pair.1.y))
                + Double(abs(pair.0.z - pair.1.z))
        }
        return total / Double(rgb.count * 3)
    }

    var weightedMeanX: Double {
        let weight = total
        guard weight > 0 else { return 0 }
        var moment = 0.0
        for y in 0..<height {
            for x in 0..<width {
                moment += Double(x) * Double(self[x, y])
            }
        }
        return moment / weight
    }

    func maximum(inXRange rawRange: Range<Int>) -> Float {
        let range = max(rawRange.lowerBound, 0)..<min(rawRange.upperBound, width)
        guard !range.isEmpty else { return 0 }
        var result: Float = 0
        for y in 0..<height {
            for x in range {
                result = max(result, self[x, y])
            }
        }
        return result
    }
}

private final class DisplayTransferReadbackHarness {
    private let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    private let library: MTLLibrary
    private let sampler: MTLSamplerState

    init() throws {
        device = try XCTUnwrap(MTLCreateSystemDefaultDevice())
        commandQueue = try XCTUnwrap(device.makeCommandQueue())
        library = try XCTUnwrap(device.makeDefaultLibrary())
        let descriptor = MTLSamplerDescriptor()
        descriptor.minFilter = .nearest
        descriptor.magFilter = .nearest
        sampler = try XCTUnwrap(device.makeSamplerState(descriptor: descriptor))
    }

    func render(linearRGB: SIMD3<Float>) throws -> (
        linearBytes: SIMD3<UInt8>,
        sRGBBytes: SIMD3<UInt8>
    ) {
        (
            linearBytes: try render(linearRGB: linearRGB, pixelFormat: .bgra8Unorm),
            sRGBBytes: try render(linearRGB: linearRGB, pixelFormat: .bgra8Unorm_srgb)
        )
    }

    func renderActualDrawable(linearRGB: SIMD3<Float>) throws -> ActualDrawableReadback {
        let view = MTKView(frame: CGRect(x: 0, y: 0, width: 8, height: 8), device: device)
        view.framebufferOnly = false
        view.autoResizeDrawable = false
        view.drawableSize = CGSize(width: 1, height: 1)
        DayObjectsRenderer.configureDisplay(view)

        let window = UIWindow(frame: view.frame)
        window.addSubview(view)
        window.isHidden = false
        view.layoutIfNeeded()
        defer {
            view.removeFromSuperview()
            window.isHidden = true
        }

        let drawable = try XCTUnwrap(view.currentDrawable)
        XCTAssertEqual(drawable.texture.pixelFormat, DayObjectsRenderer.colorPixelFormat)
        let source = try makeSource(linearRGB: linearRGB)
        let pipelineDescriptor = try XCTUnwrap(DayObjectsPostRendering.displayPipelineDescriptor(
            library: library,
            pixelFormat: drawable.texture.pixelFormat
        ))
        let pipeline = try device.makeRenderPipelineState(descriptor: pipelineDescriptor)
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = drawable.texture
        pass.colorAttachments[0].loadAction = .dontCare
        pass.colorAttachments[0].storeAction = .store

        let commandBuffer = try XCTUnwrap(commandQueue.makeCommandBuffer())
        let encoder = try XCTUnwrap(commandBuffer.makeRenderCommandEncoder(descriptor: pass))
        var uniformBytes = PostUniformBytes(
            DayObjectsPostUniforms(
                postProcess: DayObjectPostProcess(
                    visualClarity: 1,
                    reduceMotion: true,
                    grainSeed: 0
                ),
                resolution: SIMD2<Float>(1, 1),
                pointToPixelScale: 1,
                grainSeed: 0,
                paletteLuminance: 0
            ),
            grainIntensity: 0
        )
        encoder.setRenderPipelineState(pipeline)
        encoder.setFragmentTexture(source, index: 0)
        encoder.setFragmentSamplerState(sampler, index: 0)
        encoder.setFragmentBytes(
            &uniformBytes,
            length: MemoryLayout<PostUniformBytes>.stride,
            index: 0
        )
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        encoder.endEncoding()

        let readback = try XCTUnwrap(device.makeBuffer(length: 256, options: .storageModeShared))
        let blit = try XCTUnwrap(commandBuffer.makeBlitCommandEncoder())
        blit.copy(
            from: drawable.texture,
            sourceSlice: 0,
            sourceLevel: 0,
            sourceOrigin: MTLOrigin(x: 0, y: 0, z: 0),
            sourceSize: MTLSize(width: 1, height: 1, depth: 1),
            to: readback,
            destinationOffset: 0,
            destinationBytesPerRow: 256,
            destinationBytesPerImage: 256
        )
        blit.endEncoding()
        commandBuffer.present(drawable)
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
        XCTAssertEqual(commandBuffer.status, .completed)
        XCTAssertNil(commandBuffer.error)

        let bytes = readback.contents().assumingMemoryBound(to: UInt8.self)
        return ActualDrawableReadback(
            rgb: SIMD3(bytes[2], bytes[1], bytes[0]),
            usedActualMTKDrawable: true
        )
    }

    private func makeSource(linearRGB: SIMD3<Float>) throws -> MTLTexture {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba16Float,
            width: 1,
            height: 1,
            mipmapped: false
        )
        descriptor.storageMode = .shared
        descriptor.usage = .shaderRead
        let source = try XCTUnwrap(device.makeTexture(descriptor: descriptor))
        var words = [
            Float16(linearRGB.x).bitPattern,
            Float16(linearRGB.y).bitPattern,
            Float16(linearRGB.z).bitPattern,
            Float16(1).bitPattern,
        ]
        source.replace(
            region: MTLRegionMake2D(0, 0, 1, 1),
            mipmapLevel: 0,
            withBytes: &words,
            bytesPerRow: 4 * MemoryLayout<UInt16>.stride
        )
        return source
    }

    private func render(
        linearRGB: SIMD3<Float>,
        pixelFormat: MTLPixelFormat
    ) throws -> SIMD3<UInt8> {
        let source = try makeSource(linearRGB: linearRGB)

        let targetDescriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: pixelFormat,
            width: 1,
            height: 1,
            mipmapped: false
        )
        targetDescriptor.storageMode = .shared
        targetDescriptor.usage = .renderTarget
        let target = try XCTUnwrap(device.makeTexture(descriptor: targetDescriptor))
        let pipelineDescriptor = try XCTUnwrap(DayObjectsPostRendering.displayPipelineDescriptor(
            library: library,
            pixelFormat: pixelFormat
        ))
        let pipeline = try device.makeRenderPipelineState(descriptor: pipelineDescriptor)
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = target
        pass.colorAttachments[0].loadAction = .dontCare
        pass.colorAttachments[0].storeAction = .store

        let commandBuffer = try XCTUnwrap(commandQueue.makeCommandBuffer())
        let encoder = try XCTUnwrap(commandBuffer.makeRenderCommandEncoder(descriptor: pass))
        let post = DayObjectPostProcess(
            visualClarity: 1,
            reduceMotion: true,
            grainSeed: 0
        )
        let uniforms = DayObjectsPostUniforms(
            postProcess: post,
            resolution: SIMD2<Float>(1, 1),
            pointToPixelScale: 1,
            grainSeed: 0,
            paletteLuminance: 0
        )
        var uniformBytes = PostUniformBytes(uniforms, grainIntensity: 0)
        encoder.setRenderPipelineState(pipeline)
        encoder.setFragmentTexture(source, index: 0)
        encoder.setFragmentSamplerState(sampler, index: 0)
        encoder.setFragmentBytes(
            &uniformBytes,
            length: MemoryLayout<PostUniformBytes>.stride,
            index: 0
        )
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        encoder.endEncoding()
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
        XCTAssertEqual(commandBuffer.status, .completed)
        XCTAssertNil(commandBuffer.error)

        var bytes = [UInt8](repeating: 0, count: 4)
        target.getBytes(
            &bytes,
            bytesPerRow: 4,
            from: MTLRegionMake2D(0, 0, 1, 1),
            mipmapLevel: 0
        )
        return SIMD3(bytes[2], bytes[1], bytes[0])
    }
}

private struct ActualDrawableReadback {
    let rgb: SIMD3<UInt8>
    let usedActualMTKDrawable: Bool

    func maximumDifference(from expected: SIMD3<UInt8>) -> Int {
        [
            abs(Int(rgb.x) - Int(expected.x)),
            abs(Int(rgb.y) - Int(expected.y)),
            abs(Int(rgb.z) - Int(expected.z))
        ].max() ?? 0
    }
}

private final class PostRenderHarness {
    let width: Int
    let height: Int

    private let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    private let meshGradientPipeline: MTLRenderPipelineState
    private let sceneUpscalePipeline: MTLRenderPipelineState
    private let actorPipeline: MTLRenderPipelineState
    private let horizontalBlurPipeline: MTLRenderPipelineState
    private let verticalBlurPipeline: MTLRenderPipelineState
    private let displayPipeline: MTLRenderPipelineState
    private let productionDisplayPipeline: MTLRenderPipelineState
    private let sampler: MTLSamplerState
    private let quadBuffer: MTLBuffer

    init(width: Int, height: Int) throws {
        self.width = width
        self.height = height

        let renderDevice = try XCTUnwrap(MTLCreateSystemDefaultDevice())
        let renderCommandQueue = try XCTUnwrap(renderDevice.makeCommandQueue())
        let library = try XCTUnwrap(renderDevice.makeDefaultLibrary())
        let fullscreenVertex = try XCTUnwrap(library.makeFunction(name: "dayObjectsFullscreenVertex"))
        let meshGradientFragment = try XCTUnwrap(library.makeFunction(name: "dayObjectsMeshGradientFragment"))
        let presentFragment = try XCTUnwrap(library.makeFunction(name: "dayObjectsBackgroundPresentFragment"))

        let meshGradientDescriptor = MTLRenderPipelineDescriptor()
        meshGradientDescriptor.vertexFunction = fullscreenVertex
        meshGradientDescriptor.fragmentFunction = meshGradientFragment
        meshGradientDescriptor.colorAttachments[0].pixelFormat = .rgba16Float

        let upscaleDescriptor = MTLRenderPipelineDescriptor()
        upscaleDescriptor.vertexFunction = fullscreenVertex
        upscaleDescriptor.fragmentFunction = presentFragment
        upscaleDescriptor.colorAttachments[0].pixelFormat = .rgba16Float

        let actorDescriptor = try XCTUnwrap(DayObjectsActorRendering.pipelineDescriptor(
            library: library,
            pixelFormat: .rgba16Float
        ))
        let horizontalDescriptor = try XCTUnwrap(DayObjectsPostRendering.blurPipelineDescriptor(
            library: library,
            horizontal: true,
            pixelFormat: .rgba16Float
        ))
        let verticalDescriptor = try XCTUnwrap(DayObjectsPostRendering.blurPipelineDescriptor(
            library: library,
            horizontal: false,
            pixelFormat: .rgba16Float
        ))
        let displayDescriptor = try XCTUnwrap(DayObjectsPostRendering.displayPipelineDescriptor(
            library: library,
            pixelFormat: .rgba16Float
        ))
        let productionDisplayDescriptor = try XCTUnwrap(DayObjectsPostRendering.displayPipelineDescriptor(
            library: library,
            pixelFormat: DayObjectsRenderer.colorPixelFormat
        ))

        let samplerDescriptor = MTLSamplerDescriptor()
        samplerDescriptor.minFilter = .linear
        samplerDescriptor.magFilter = .linear
        samplerDescriptor.sAddressMode = .clampToEdge
        samplerDescriptor.tAddressMode = .clampToEdge

        let vertices: [SIMD2<Float>] = [
            SIMD2(-1, -1),
            SIMD2(1, -1),
            SIMD2(-1, 1),
            SIMD2(1, 1),
        ]

        device = renderDevice
        commandQueue = renderCommandQueue
        meshGradientPipeline = try renderDevice.makeRenderPipelineState(descriptor: meshGradientDescriptor)
        sceneUpscalePipeline = try renderDevice.makeRenderPipelineState(descriptor: upscaleDescriptor)
        actorPipeline = try renderDevice.makeRenderPipelineState(descriptor: actorDescriptor)
        horizontalBlurPipeline = try renderDevice.makeRenderPipelineState(descriptor: horizontalDescriptor)
        verticalBlurPipeline = try renderDevice.makeRenderPipelineState(descriptor: verticalDescriptor)
        displayPipeline = try renderDevice.makeRenderPipelineState(descriptor: displayDescriptor)
        productionDisplayPipeline = try renderDevice.makeRenderPipelineState(
            descriptor: productionDisplayDescriptor
        )
        sampler = try XCTUnwrap(renderDevice.makeSamplerState(descriptor: samplerDescriptor))
        quadBuffer = try XCTUnwrap(vertices.withUnsafeBytes { bytes -> MTLBuffer? in
            guard let baseAddress = bytes.baseAddress else { return nil }
            return renderDevice.makeBuffer(
                bytes: baseAddress,
                length: bytes.count,
                options: .storageModeShared
            )
        })
    }

    func render(
        scene: DayObjectScene,
        clarity: Double,
        elapsed: Double,
        motionEnergy: Double = 0.75,
        actorLimit: Int? = nil,
        insertions: [String: TimeInterval] = [:],
        removals: [String: TimeInterval] = [:]
    ) throws -> PostRenderResult {
        let environment = DayObjectEnvironment(
            motionEnergy: motionEnergy,
            visualClarity: clarity,
            reduceMotion: false
        )
        let frame = DayObjectRenderFrame.make(
            scene: scene,
            environment: environment,
            elapsed: elapsed,
            insertions: insertions,
            removals: removals,
            canvasAspect: Double(width) / Double(height)
        )
        var postUniforms = DayObjectsPostUniforms(
            frame: frame,
            scene: scene,
            resolution: SIMD2(Float(width), Float(height)),
            pointToPixelScale: 2
        )

        let backgroundTexture = try makeTexture(width: width / 2, height: height / 2)
        let sceneTexture = try makeTexture(width: width, height: height)
        let blurA = try makeTexture(width: width, height: height)
        let blurB = try makeTexture(width: width, height: height)
        let output = try makeTexture(width: width, height: height)
        let noGrainOutput = try makeTexture(width: width, height: height)
        let productionOutput = try makeTexture(
            width: width,
            height: height,
            pixelFormat: DayObjectsRenderer.colorPixelFormat
        )
        let commandBuffer = try XCTUnwrap(commandQueue.makeCommandBuffer())

        var meshGradientUniforms = DayObjectsMeshGradientUniforms(
            scene: scene,
            resolution: SIMD2(Float(backgroundTexture.width), Float(backgroundTexture.height)),
            elapsedTime: elapsed
        )
        let meshGradientPass = renderPass(
            texture: backgroundTexture,
            clearColor: MTLClearColorMake(0, 0, 0, 1)
        )
        let meshGradientEncoder = try XCTUnwrap(
            commandBuffer.makeRenderCommandEncoder(descriptor: meshGradientPass)
        )
        meshGradientEncoder.setRenderPipelineState(meshGradientPipeline)
        meshGradientEncoder.setFragmentBytes(
            &meshGradientUniforms,
            length: MemoryLayout<DayObjectsMeshGradientUniforms>.stride,
            index: 0
        )
        meshGradientEncoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        meshGradientEncoder.endEncoding()

        let renderActors = actorLimit.map {
            Array(frame.actors.prefix(max($0, 0)))
        } ?? frame.actors
        let upload = DayObjectsActorUpload(
            actors: renderActors,
            resolution: SIMD2(Float(width), Float(height)),
            radialFillStyle: scene.radialFillStyle
        )
        let actorBuffer = try XCTUnwrap(upload.actors.withUnsafeBytes { bytes -> MTLBuffer? in
            guard let baseAddress = bytes.baseAddress, !bytes.isEmpty else {
                return device.makeBuffer(length: DayObjectGPUActor.metalStride)
            }
            return device.makeBuffer(
                bytes: baseAddress,
                length: bytes.count,
                options: .storageModeShared
            )
        })
        let scenePass = renderPass(texture: sceneTexture, clearColor: MTLClearColorMake(0, 0, 0, 1))
        let sceneEncoder = try XCTUnwrap(commandBuffer.makeRenderCommandEncoder(descriptor: scenePass))
        sceneEncoder.setRenderPipelineState(sceneUpscalePipeline)
        sceneEncoder.setFragmentTexture(backgroundTexture, index: 0)
        sceneEncoder.setFragmentSamplerState(sampler, index: 0)
        sceneEncoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)

        if !upload.actors.isEmpty {
            var actorUniforms = upload.uniforms
            sceneEncoder.setRenderPipelineState(actorPipeline)
            sceneEncoder.setVertexBuffer(quadBuffer, offset: 0, index: 0)
            sceneEncoder.setVertexBuffer(actorBuffer, offset: 0, index: 1)
            sceneEncoder.setVertexBytes(
                &actorUniforms,
                length: MemoryLayout<DayObjectsActorUniforms>.stride,
                index: 2
            )
            sceneEncoder.setFragmentBytes(
                &actorUniforms,
                length: MemoryLayout<DayObjectsActorUniforms>.stride,
                index: 2
            )
            sceneEncoder.drawPrimitives(
                type: .triangleStrip,
                vertexStart: 0,
                vertexCount: 4,
                instanceCount: upload.actors.count
            )
        }
        sceneEncoder.endEncoding()

        var postSource = sceneTexture
        if postUniforms.blurRadiusPixels >= 0.01 {
            encodeFullscreenPass(
                commandBuffer: commandBuffer,
                target: blurA,
                source: sceneTexture,
                pipeline: horizontalBlurPipeline,
                uniforms: &postUniforms
            )
            encodeFullscreenPass(
                commandBuffer: commandBuffer,
                target: blurB,
                source: blurA,
                pipeline: verticalBlurPipeline,
                uniforms: &postUniforms
            )
            postSource = blurB
        }

        encodeFullscreenPass(
            commandBuffer: commandBuffer,
            target: output,
            source: postSource,
            pipeline: displayPipeline,
            uniforms: &postUniforms
        )
        encodeFullscreenPass(
            commandBuffer: commandBuffer,
            target: productionOutput,
            source: postSource,
            pipeline: productionDisplayPipeline,
            uniforms: &postUniforms
        )
        var noGrainUniforms = PostUniformBytes(postUniforms, grainIntensity: 0)
        encodeFullscreenPass(
            commandBuffer: commandBuffer,
            target: noGrainOutput,
            source: postSource,
            pipeline: displayPipeline,
            uniforms: &noGrainUniforms
        )

        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
        XCTAssertEqual(commandBuffer.status, .completed)
        XCTAssertNil(commandBuffer.error)

        return PostRenderResult(
            uniforms: postUniforms,
            renderedActorCount: upload.actors.count,
            output: read(texture: output),
            noGrain: read(texture: noGrainOutput),
            productionSRGB: readDisplay(texture: productionOutput)
        )
    }

    private func encodeFullscreenPass(
        commandBuffer: MTLCommandBuffer,
        target: MTLTexture,
        source: MTLTexture,
        pipeline: MTLRenderPipelineState,
        uniforms: inout DayObjectsPostUniforms
    ) {
        withUnsafeBytes(of: &uniforms) { bytes in
            encodeFullscreenPass(
                commandBuffer: commandBuffer,
                target: target,
                source: source,
                pipeline: pipeline,
                uniformBytes: bytes
            )
        }
    }

    private func encodeFullscreenPass(
        commandBuffer: MTLCommandBuffer,
        target: MTLTexture,
        source: MTLTexture,
        pipeline: MTLRenderPipelineState,
        uniforms: inout PostUniformBytes
    ) {
        withUnsafeBytes(of: &uniforms) { bytes in
            encodeFullscreenPass(
                commandBuffer: commandBuffer,
                target: target,
                source: source,
                pipeline: pipeline,
                uniformBytes: bytes
            )
        }
    }

    private func encodeFullscreenPass(
        commandBuffer: MTLCommandBuffer,
        target: MTLTexture,
        source: MTLTexture,
        pipeline: MTLRenderPipelineState,
        uniformBytes: UnsafeRawBufferPointer
    ) {
        let pass = renderPass(texture: target, clearColor: MTLClearColorMake(0, 0, 0, 1))
        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: pass) else {
            XCTFail("Could not create Day Objects post encoder")
            return
        }
        encoder.setRenderPipelineState(pipeline)
        encoder.setFragmentTexture(source, index: 0)
        encoder.setFragmentSamplerState(sampler, index: 0)
        if let baseAddress = uniformBytes.baseAddress {
            encoder.setFragmentBytes(
                baseAddress,
                length: uniformBytes.count,
                index: 0
            )
        } else {
            XCTFail("Day Objects post uniforms were empty")
        }
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        encoder.endEncoding()
    }

    private func makeTexture(
        width: Int,
        height: Int,
        pixelFormat: MTLPixelFormat = .rgba16Float
    ) throws -> MTLTexture {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: pixelFormat,
            width: width,
            height: height,
            mipmapped: false
        )
        descriptor.storageMode = .shared
        descriptor.usage = [.renderTarget, .shaderRead]
        return try XCTUnwrap(device.makeTexture(descriptor: descriptor))
    }

    private func renderPass(texture: MTLTexture, clearColor: MTLClearColor) -> MTLRenderPassDescriptor {
        let descriptor = MTLRenderPassDescriptor()
        descriptor.colorAttachments[0].texture = texture
        descriptor.colorAttachments[0].loadAction = .clear
        descriptor.colorAttachments[0].storeAction = .store
        descriptor.colorAttachments[0].clearColor = clearColor
        return descriptor
    }

    private func read(texture: MTLTexture) -> PostPixelCapture {
        var words = [UInt16](repeating: 0, count: width * height * 4)
        texture.getBytes(
            &words,
            bytesPerRow: width * 4 * MemoryLayout<UInt16>.stride,
            from: MTLRegionMake2D(0, 0, width, height),
            mipmapLevel: 0
        )
        let rgb = stride(from: 0, to: words.count, by: 4).map { index in
            SIMD3<Float>(
                Float(Float16(bitPattern: words[index])),
                Float(Float16(bitPattern: words[index + 1])),
                Float(Float16(bitPattern: words[index + 2]))
            )
        }
        var checksum: UInt64 = 1_469_598_103_934_665_603
        for word in words {
            checksum ^= UInt64(word)
            checksum &*= 1_099_511_628_211
        }
        return PostPixelCapture(width: width, height: height, rgb: rgb, checksum: checksum)
    }

    private func readDisplay(texture: MTLTexture) -> DisplayPixelCapture {
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        texture.getBytes(
            &bytes,
            bytesPerRow: width * 4,
            from: MTLRegionMake2D(0, 0, width, height),
            mipmapLevel: 0
        )
        let rgb = stride(from: 0, to: bytes.count, by: 4).map { index in
            SIMD3(bytes[index + 2], bytes[index + 1], bytes[index])
        }
        return DisplayPixelCapture(width: width, height: height, rgb: rgb)
    }
}

private struct PostUniformBytes {
    let resolution: SIMD2<Float>
    let blurRadiusPixels: Float
    let contrast: Float
    let saturation: Float
    let grainIntensity: Float
    let grainPhase: Float
    let grainSeed: UInt32

    init(_ uniforms: DayObjectsPostUniforms, grainIntensity: Float) {
        resolution = uniforms.resolution
        blurRadiusPixels = uniforms.blurRadiusPixels
        contrast = uniforms.contrast
        saturation = uniforms.saturation
        self.grainIntensity = grainIntensity
        grainPhase = uniforms.grainPhase
        grainSeed = uniforms.grainSeed
    }
}

private struct PostRenderResult {
    let uniforms: DayObjectsPostUniforms
    let renderedActorCount: Int
    let output: PostPixelCapture
    let noGrain: PostPixelCapture
    let productionSRGB: DisplayPixelCapture
}

private struct DisplayPixelCapture {
    let width: Int
    let height: Int
    let rgb: [SIMD3<UInt8>]

    func maximumDisplayByteDifference(from linearCapture: PostPixelCapture) -> Int {
        precondition(width == linearCapture.width && height == linearCapture.height)
        return zip(rgb, linearCapture.displayRGBBytes).reduce(0) { maximum, pair in
            max(maximum, [
                abs(Int(pair.0.x) - Int(pair.1.x)),
                abs(Int(pair.0.y) - Int(pair.1.y)),
                abs(Int(pair.0.z) - Int(pair.1.z))
            ].max() ?? 0)
        }
    }
}

private struct PostPixelCapture {
    let width: Int
    let height: Int
    let rgb: [SIMD3<Float>]
    let checksum: UInt64

    var structuralSharpness: Double {
        luminanceField.boxBlurred(radius: 1).neighborDifferenceEnergy
    }

    var luminanceField: PostLuminanceField {
        PostLuminanceField(
            width: width,
            height: height,
            values: rgb.map {
                Double($0.x) * 0.2126 + Double($0.y) * 0.7152 + Double($0.z) * 0.0722
            }
        )
    }

    func difference(from other: PostPixelCapture) -> PostLuminanceField {
        precondition(width == other.width && height == other.height)
        let lhs = luminanceField.values
        let rhs = other.luminanceField.values
        return PostLuminanceField(
            width: width,
            height: height,
            values: zip(lhs, rhs).map(-)
        )
    }

    var displayRGBBytes: [SIMD3<UInt8>] {
        rgb.map { color in
            SIMD3(
                Self.displayByte(color.x),
                Self.displayByte(color.y),
                Self.displayByte(color.z)
            )
        }
    }

    func pngData() throws -> Data {
        let displayBytes = displayRGBBytes.flatMap { color -> [UInt8] in
            [color.x, color.y, color.z, 255]
        }
        let provider = try XCTUnwrap(CGDataProvider(data: Data(displayBytes) as CFData))
        let image = try XCTUnwrap(CGImage(
            width: width,
            height: height,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue),
            provider: provider,
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent
        ))
        let output = NSMutableData()
        let destination = try XCTUnwrap(CGImageDestinationCreateWithData(
            output,
            UTType.png.identifier as CFString,
            1,
            nil
        ))
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else {
            throw NSError(domain: "DayObjectsVisualMatrix", code: 1)
        }
        return output as Data
    }

    private static func displayByte(_ component: Float) -> UInt8 {
        let linear = min(max(component.isFinite ? component : 0, 0), 1)
        let display = linear <= 0.003_130_8
            ? linear * 12.92
            : 1.055 * pow(linear, 1 / 2.4) - 0.055
        return UInt8((min(max(display, 0), 1) * 255).rounded())
    }
}

private struct DayObjectsPerceptualSignature: CustomStringConvertible {
    let meanRGB: SIMD3<Double>
    let meanLuminance: Double
    let luminanceDeviation: Double
    let lowLuminance: Double
    let highLuminance: Double
    let edgeEnergy: Double
    let colorfulness: Double
    let coarseLuminance: [Double]
    let actorInkFraction: Double
    let actorEnergy: Double
    let borderActorPeak: Double
    let negativeSpaceActorPeak: Double
    let exclusionActorPeak: Double

    init(
        capture: PostPixelCapture,
        actorDifference: PostLuminanceField,
        negativeSpaceRegion: DayObjectNormalizedRect,
        exclusionRegion: DayObjectNormalizedRect
    ) {
        let count = Double(max(capture.rgb.count, 1))
        meanRGB = capture.rgb.reduce(.zero) { partial, color in
            partial + SIMD3(Double(color.x), Double(color.y), Double(color.z))
        } / count
        let luminance = capture.luminanceField
        meanLuminance = luminance.mean
        luminanceDeviation = luminance.standardDeviation
        lowLuminance = luminance.percentile(0.10)
        highLuminance = luminance.percentile(0.90)
        edgeEnergy = luminance.neighborDifferenceEnergy
        colorfulness = capture.rgb.reduce(0) { partial, color in
            partial + Double(max(color.x, max(color.y, color.z)) - min(color.x, min(color.y, color.z)))
        } / count
        coarseLuminance = luminance.coarseAverages(columns: 4, rows: 3)
        actorInkFraction = Double(actorDifference.pixelCount(above: 0.002))
            / Double(max(actorDifference.values.count, 1))
        actorEnergy = actorDifference.meanAbsoluteLuminance
        borderActorPeak = actorDifference.maximumAbsoluteLuminance(borderWidth: 2)
        negativeSpaceActorPeak = actorDifference.maximumAbsoluteLuminance(in: negativeSpaceRegion)
        exclusionActorPeak = actorDifference.maximumAbsoluteLuminance(in: exclusionRegion)
    }

    init(
        meanRGB: SIMD3<Double>,
        meanLuminance: Double,
        luminanceDeviation: Double,
        lowLuminance: Double,
        highLuminance: Double,
        edgeEnergy: Double,
        colorfulness: Double,
        coarseLuminance: [Double],
        actorInkFraction: Double,
        actorEnergy: Double,
        borderActorPeak: Double,
        negativeSpaceActorPeak: Double,
        exclusionActorPeak: Double
    ) {
        self.meanRGB = meanRGB
        self.meanLuminance = meanLuminance
        self.luminanceDeviation = luminanceDeviation
        self.lowLuminance = lowLuminance
        self.highLuminance = highLuminance
        self.edgeEnergy = edgeEnergy
        self.colorfulness = colorfulness
        self.coarseLuminance = coarseLuminance
        self.actorInkFraction = actorInkFraction
        self.actorEnergy = actorEnergy
        self.borderActorPeak = borderActorPeak
        self.negativeSpaceActorPeak = negativeSpaceActorPeak
        self.exclusionActorPeak = exclusionActorPeak
    }

    func mismatches(from baseline: Self) -> [String] {
        var result = [String]()
        func compare(_ name: String, _ actual: Double, _ expected: Double, tolerance: Double) {
            if abs(actual - expected) > tolerance {
                result.append("\(name)=\(actual) expected=\(expected)±\(tolerance)")
            }
        }
        for index in 0..<3 {
            compare("meanRGB[\(index)]", meanRGB[index], baseline.meanRGB[index], tolerance: 0.03)
        }
        compare("meanLuminance", meanLuminance, baseline.meanLuminance, tolerance: 0.025)
        compare("luminanceDeviation", luminanceDeviation, baseline.luminanceDeviation, tolerance: 0.02)
        compare("lowLuminance", lowLuminance, baseline.lowLuminance, tolerance: 0.03)
        compare("highLuminance", highLuminance, baseline.highLuminance, tolerance: 0.035)
        compare("edgeEnergy", edgeEnergy, baseline.edgeEnergy, tolerance: 0.005)
        compare("colorfulness", colorfulness, baseline.colorfulness, tolerance: 0.025)
        if coarseLuminance.count != baseline.coarseLuminance.count {
            result.append("coarseLuminance.count=\(coarseLuminance.count) expected=\(baseline.coarseLuminance.count)")
        } else {
            for index in coarseLuminance.indices {
                compare(
                    "coarseLuminance[\(index)]",
                    coarseLuminance[index],
                    baseline.coarseLuminance[index],
                    tolerance: 0.045
                )
            }
        }
        compare("actorInkFraction", actorInkFraction, baseline.actorInkFraction, tolerance: 0.03)
        compare("actorEnergy", actorEnergy, baseline.actorEnergy, tolerance: 0.004)
        compare("borderActorPeak", borderActorPeak, baseline.borderActorPeak, tolerance: 0.003)
        compare(
            "negativeSpaceActorPeak",
            negativeSpaceActorPeak,
            baseline.negativeSpaceActorPeak,
            tolerance: 0.003
        )
        compare("exclusionActorPeak", exclusionActorPeak, baseline.exclusionActorPeak, tolerance: 0.003)
        return result
    }

    var description: String {
        "meanRGB=\(meanRGB) meanLuminance=\(meanLuminance) "
            + "luminanceDeviation=\(luminanceDeviation) low=\(lowLuminance) high=\(highLuminance) "
            + "edge=\(edgeEnergy) colorfulness=\(colorfulness) coarse=\(coarseLuminance) "
            + "actorInkFraction=\(actorInkFraction) actorEnergy=\(actorEnergy) "
            + "borderPeak=\(borderActorPeak) negativePeak=\(negativeSpaceActorPeak) "
            + "exclusionPeak=\(exclusionActorPeak)"
    }
}

private struct DayObjectsTransitionPerceptualSignature: CustomStringConvertible {
    let name: String
    let renderedActorCount: Int
    let affectedEnergy: Double
    let meanLuminance: Double
    let edgeEnergy: Double

    init(
        name: String,
        renderedActorCount: Int,
        affectedEnergy: Double,
        capture: PostPixelCapture
    ) {
        self.name = name
        self.renderedActorCount = renderedActorCount
        self.affectedEnergy = affectedEnergy
        meanLuminance = capture.luminanceField.mean
        edgeEnergy = capture.luminanceField.neighborDifferenceEnergy
    }

    init(
        name: String,
        renderedActorCount: Int,
        affectedEnergy: Double,
        meanLuminance: Double,
        edgeEnergy: Double
    ) {
        self.name = name
        self.renderedActorCount = renderedActorCount
        self.affectedEnergy = affectedEnergy
        self.meanLuminance = meanLuminance
        self.edgeEnergy = edgeEnergy
    }

    var description: String {
        "\(name){actors=\(renderedActorCount), affected=\(affectedEnergy), "
            + "mean=\(meanLuminance), edge=\(edgeEnergy)}"
    }
}

private enum DayObjectsPerceptualBaselines {
    struct Fixture {
        let name: String
        let width: Int
        let height: Int
        let signature: DayObjectsPerceptualSignature
    }

    static let fixtures = [
        Fixture(
            name: "phone-portrait",
            width: 180,
            height: 390,
            signature: DayObjectsPerceptualSignature(
                meanRGB: SIMD3(0.0586782, 0.2634250, 0.3414791),
                meanLuminance: 0.2255313,
                luminanceDeviation: 0.0794455,
                lowLuminance: 0.1382190,
                highLuminance: 0.3094268,
                edgeEnergy: 0.0082018,
                colorfulness: 0.2828009,
                coarseLuminance: [
                    0.1518564, 0.2687296, 0.3085676, 0.2817738,
                    0.1823705, 0.2169048, 0.2212242, 0.1717899,
                    0.2501617, 0.2384825, 0.2174592, 0.1970558,
                ],
                actorInkFraction: 0.0603276,
                actorEnergy: 0.0074700,
                borderActorPeak: 0,
                negativeSpaceActorPeak: 0,
                exclusionActorPeak: 0
            )
        ),
        Fixture(
            name: "tablet-landscape",
            width: 256,
            height: 192,
            signature: DayObjectsPerceptualSignature(
                meanRGB: SIMD3(0.0493951, 0.2364840, 0.3201828),
                meanLuminance: 0.2027520,
                luminanceDeviation: 0.0760749,
                lowLuminance: 0.1140938,
                highLuminance: 0.2841789,
                edgeEnergy: 0.0083634,
                colorfulness: 0.2707877,
                coarseLuminance: [
                    0.2106625, 0.2037208, 0.2235792, 0.2019335,
                    0.1842887, 0.1827392, 0.2082788, 0.1507439,
                    0.2226899, 0.2241475, 0.2428638, 0.1773754,
                ],
                actorInkFraction: 0.0773519,
                actorEnergy: 0.0097094,
                borderActorPeak: 0,
                negativeSpaceActorPeak: 0,
                exclusionActorPeak: 0
            )
        ),
    ]

    static let transitionSignatures = [
        DayObjectsTransitionPerceptualSignature(
            name: "insertion-before", renderedActorCount: 4,
            affectedEnergy: 0, meanLuminance: 0.2334781, edgeEnergy: 0.0073681
        ),
        DayObjectsTransitionPerceptualSignature(
            name: "insertion-during", renderedActorCount: 5,
            affectedEnergy: 0, meanLuminance: 0.2330055, edgeEnergy: 0.0073362
        ),
        DayObjectsTransitionPerceptualSignature(
            name: "insertion-after", renderedActorCount: 5,
            affectedEnergy: 0.0015230, meanLuminance: 0.2341458, edgeEnergy: 0.0073366
        ),
        DayObjectsTransitionPerceptualSignature(
            name: "removal-before", renderedActorCount: 5,
            affectedEnergy: 0.0003307, meanLuminance: 0.2339733, edgeEnergy: 0.0073021
        ),
        DayObjectsTransitionPerceptualSignature(
            name: "removal-during", renderedActorCount: 5,
            affectedEnergy: 0.0001015, meanLuminance: 0.2344866, edgeEnergy: 0.0073297
        ),
        DayObjectsTransitionPerceptualSignature(
            name: "removal-after", renderedActorCount: 4,
            affectedEnergy: 0, meanLuminance: 0.2350607, edgeEnergy: 0.0073204
        ),
        DayObjectsTransitionPerceptualSignature(
            name: "capped-replacement-before", renderedActorCount: 40,
            affectedEnergy: 0, meanLuminance: 0.2380478, edgeEnergy: 0.0073235
        ),
        DayObjectsTransitionPerceptualSignature(
            name: "capped-replacement-during", renderedActorCount: 40,
            affectedEnergy: 0.0000007, meanLuminance: 0.2382795, edgeEnergy: 0.0073625
        ),
        DayObjectsTransitionPerceptualSignature(
            name: "capped-replacement-after", renderedActorCount: 40,
            affectedEnergy: 0.0000293, meanLuminance: 0.2389202, edgeEnergy: 0.0073280
        ),
    ]

    static func transitionMismatches(
        _ actual: [DayObjectsTransitionPerceptualSignature]
    ) -> [String] {
        var result = [String]()
        let actualByName = Dictionary(uniqueKeysWithValues: actual.map { ($0.name, $0) })
        let expectedNames = Set(transitionSignatures.map(\.name))
        for name in actualByName.keys.sorted() where !expectedNames.contains(name) {
            result.append("unexpected \(name)")
        }
        for expected in transitionSignatures {
            guard let value = actualByName[expected.name] else {
                result.append("missing \(expected.name)")
                continue
            }
            if value.renderedActorCount != expected.renderedActorCount {
                result.append("\(expected.name).actors=\(value.renderedActorCount) expected=\(expected.renderedActorCount)")
            }
            let affectedTolerance = max(0.000_15, expected.affectedEnergy * 0.25)
            if abs(value.affectedEnergy - expected.affectedEnergy) > affectedTolerance {
                result.append("\(expected.name).affected=\(value.affectedEnergy) expected=\(expected.affectedEnergy)±\(affectedTolerance)")
            }
            if abs(value.meanLuminance - expected.meanLuminance) > 0.025 {
                result.append("\(expected.name).mean=\(value.meanLuminance) expected=\(expected.meanLuminance)±0.025")
            }
            if abs(value.edgeEnergy - expected.edgeEnergy) > 0.005 {
                result.append("\(expected.name).edge=\(value.edgeEnergy) expected=\(expected.edgeEnergy)±0.005")
            }
        }
        return result
    }

}

private struct PostLuminanceField {
    let width: Int
    let height: Int
    let values: [Double]

    var meanAbsoluteLuminance: Double {
        values.reduce(0) { $0 + abs($1) } / Double(max(values.count, 1))
    }

    var maximumAbsoluteLuminance: Double {
        values.reduce(0) { max($0, abs($1)) }
    }

    var mean: Double {
        values.reduce(0, +) / Double(max(values.count, 1))
    }

    var standardDeviation: Double {
        let average = mean
        return sqrt(values.reduce(0) { $0 + pow($1 - average, 2) } / Double(max(values.count, 1)))
    }

    func percentile(_ fraction: Double) -> Double {
        guard !values.isEmpty else { return 0 }
        let sorted = values.sorted()
        let index = min(max(Int((fraction * Double(sorted.count - 1)).rounded()), 0), sorted.count - 1)
        return sorted[index]
    }

    func pixelCount(above threshold: Double) -> Int {
        values.reduce(0) { $0 + (abs($1) > threshold ? 1 : 0) }
    }

    func maximumAbsoluteLuminance(borderWidth rawBorderWidth: Int) -> Double {
        let borderWidth = min(max(rawBorderWidth, 1), min(width, height))
        var maximum = 0.0
        for y in 0..<height {
            for x in 0..<width
            where x < borderWidth || x >= width - borderWidth
                || y < borderWidth || y >= height - borderWidth {
                maximum = max(maximum, abs(self[x, y]))
            }
        }
        return maximum
    }

    func maximumAbsoluteLuminance(in region: DayObjectNormalizedRect) -> Double {
        let minX = min(max(Int((region.minX * Double(width)).rounded(.down)), 0), width)
        let maxX = min(max(Int((region.maxX * Double(width)).rounded(.up)), 0), width)
        let minY = min(max(Int((region.minY * Double(height)).rounded(.down)), 0), height)
        let maxY = min(max(Int((region.maxY * Double(height)).rounded(.up)), 0), height)
        guard minX < maxX, minY < maxY else { return 0 }
        var maximum = 0.0
        for y in minY..<maxY {
            for x in minX..<maxX {
                maximum = max(maximum, abs(self[x, y]))
            }
        }
        return maximum
    }

    func coarseAverages(columns: Int, rows: Int) -> [Double] {
        precondition(columns > 0 && rows > 0)
        return (0..<rows).flatMap { row in
            (0..<columns).map { column in
                let minX = column * width / columns
                let maxX = max((column + 1) * width / columns, minX + 1)
                let minY = row * height / rows
                let maxY = max((row + 1) * height / rows, minY + 1)
                var total = 0.0
                for y in minY..<min(maxY, height) {
                    for x in minX..<min(maxX, width) {
                        total += self[x, y]
                    }
                }
                let sampleCount = max((min(maxX, width) - minX) * (min(maxY, height) - minY), 1)
                return total / Double(sampleCount)
            }
        }
    }

    var neighborDifferenceEnergy: Double {
        var total = 0.0
        var count = 0
        for y in 0..<height {
            for x in 0..<width {
                let value = self[x, y]
                if x + 1 < width {
                    total += abs(value - self[x + 1, y])
                    count += 1
                }
                if y + 1 < height {
                    total += abs(value - self[x, y + 1])
                    count += 1
                }
            }
        }
        return total / Double(max(count, 1))
    }

    subscript(x: Int, y: Int) -> Double {
        values[y * width + x]
    }

    func boxBlurred(radius: Int) -> PostLuminanceField {
        guard radius > 0 else { return self }
        var blurred = [Double](repeating: 0, count: values.count)
        for y in 0..<height {
            for x in 0..<width {
                var total = 0.0
                var count = 0
                for sampleY in max(y - radius, 0)...min(y + radius, height - 1) {
                    for sampleX in max(x - radius, 0)...min(x + radius, width - 1) {
                        total += self[sampleX, sampleY]
                        count += 1
                    }
                }
                blurred[y * width + x] = total / Double(count)
            }
        }
        return PostLuminanceField(width: width, height: height, values: blurred)
    }
}
