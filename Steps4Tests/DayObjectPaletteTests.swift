import Metal
import XCTest
@testable import Steps4

final class DayObjectPaletteTests: XCTestCase {
    func testDailyRadialFillUsesAStableSharedSubsetOfOneToThreePaletteColors() {
        var reachedColorCounts = Set<Int>()

        for index in 0..<2_048 {
            let input = DayObjectSceneInput(
                dayKey: "radial-fill-\(index)",
                identity: "tester",
                eventIDs: ["walk"],
                motionEnergy: 0.55,
                visualClarity: 0.55,
                reduceMotion: false
            )
            let scene = DayObjectScene.make(input: input)
            let enriched = DayObjectScene.make(input: DayObjectSceneInput(
                dayKey: input.dayKey,
                identity: input.identity,
                eventIDs: ["walk", "sleep", "read"],
                motionEnergy: input.motionEnergy,
                visualClarity: input.visualClarity,
                reduceMotion: input.reduceMotion
            ))
            let radial = scene.radialFillStyle

            XCTAssertEqual(enriched.radialFillStyle, radial, "day=\(index)")
            XCTAssertTrue((1...3).contains(radial.colors.count), "day=\(index)")
            XCTAssertEqual(radial.colors.count, scene.composition.fill.colorCount, "day=\(index)")
            let visiblePaletteColors = scene.palette.colors.map {
                $0.lightened(
                    toMinimumContrast: 1.35,
                    against: scene.palette.backgroundBase
                ).linearRGB
            }
            XCTAssertTrue(
                radial.colors.allSatisfy { visiblePaletteColors.contains($0) },
                "day=\(index)"
            )
            XCTAssertTrue(
                radial.colors.allSatisfy {
                    contrastRatio($0, scene.palette.backgroundBase) >= 1.35 - 0.000_001
                },
                "day=\(index)"
            )
            XCTAssertTrue((0.48...1.28).contains(radial.radius), "day=\(index)")
            XCTAssertTrue((0...0.82).contains(radial.focalDistance), "day=\(index)")
            XCTAssertTrue((0..<(2 * Double.pi)).contains(radial.focalAngle), "day=\(index)")
            XCTAssertTrue((-0.35...0.65).contains(radial.falloff), "day=\(index)")
            XCTAssertTrue((0.28...1).contains(radial.mixing), "day=\(index)")
            XCTAssertTrue((0...0.58).contains(radial.distortion), "day=\(index)")
            XCTAssertTrue((-0.72...0.72).contains(radial.distortionShift), "day=\(index)")
            XCTAssertTrue((2...12).contains(radial.distortionFrequency), "day=\(index)")
            XCTAssertTrue((0..<(2 * Double.pi)).contains(radial.rotation), "day=\(index)")
            XCTAssertTrue((-0.24...0.24).contains(radial.offset.x), "day=\(index)")
            XCTAssertTrue((-0.24...0.24).contains(radial.offset.y), "day=\(index)")
            reachedColorCounts.insert(radial.colors.count)
        }

        XCTAssertEqual(reachedColorCounts, [1, 2, 3])
    }

    func testDailyMeshReachesEveryArchetypeAndBothMotionDirections() {
        var archetypes = Set<DayObjectMeshGradientArchetype>()
        var directions = Set<Int>()

        for seed in UInt64(0)..<2_048 {
            let palette = DayObjectPalette.make(seed: seed)
            let style = DayObjectMeshGradientStyle.make(seed: seed, palette: palette)

            XCTAssertEqual(style, DayObjectMeshGradientStyle.make(seed: seed, palette: palette))
            archetypes.insert(style.archetype)
            directions.insert(Int(style.motionDirection))
            XCTAssertTrue((0.045...0.18).contains(style.speed), "seed=\(seed)")
            XCTAssertTrue((0.72...1.42).contains(style.scale), "seed=\(seed)")
            XCTAssertTrue((0...0.92).contains(style.distortion), "seed=\(seed)")
            XCTAssertTrue((-0.72...0.72).contains(style.swirl), "seed=\(seed)")
            XCTAssertTrue((-0.22...0.22).contains(style.offset.x), "seed=\(seed)")
            XCTAssertTrue((-0.22...0.22).contains(style.offset.y), "seed=\(seed)")
        }

        XCTAssertEqual(archetypes, Set(DayObjectMeshGradientArchetype.allCases))
        XCTAssertEqual(directions, [-1, 1])
    }

    func testEveryMeshArchetypeProducesADistinctSmoothMovingField() throws {
        let device = try XCTUnwrap(MTLCreateSystemDefaultDevice())
        let commandQueue = try XCTUnwrap(device.makeCommandQueue())
        let library = try XCTUnwrap(device.makeDefaultLibrary())
        let vertexFunction = try XCTUnwrap(library.makeFunction(name: "dayObjectsFullscreenVertex"))
        let fragmentFunction = try XCTUnwrap(library.makeFunction(name: "dayObjectsMeshGradientFragment"))
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = vertexFunction
        descriptor.fragmentFunction = fragmentFunction
        descriptor.colorAttachments[0].pixelFormat = .rgba16Float
        let pipeline = try device.makeRenderPipelineState(descriptor: descriptor)
        let plan = DayObjectsRenderTargetPlan(drawableWidth: 320, drawableHeight: 240)
        let colors = ["bcecf6", "00aaff", "00f7ff", "ffd447"].map {
            DayObjectRGB(hex: $0).linearRGB
        }

        var firstFrames = [[UInt16]]()
        for archetype in DayObjectMeshGradientArchetype.allCases {
            let style = DayObjectMeshGradientStyle(
                colors: colors,
                archetype: archetype,
                offset: SIMD2(0.08, -0.06),
                distortion: 0.58,
                swirl: 0.31,
                speed: 0.11,
                scale: 1.05,
                phase: 1.25,
                motionDirection: -1
            )
            let first = try renderMeshGradient(
                style: style,
                elapsedTime: 0,
                plan: plan,
                device: device,
                commandQueue: commandQueue,
                pipeline: pipeline
            )
            let later = try renderMeshGradient(
                style: style,
                elapsedTime: 20,
                plan: plan,
                device: device,
                commandQueue: commandQueue,
                pipeline: pipeline
            )
            let oppositeStyle = DayObjectMeshGradientStyle(
                colors: colors,
                archetype: archetype,
                offset: SIMD2(0.08, -0.06),
                distortion: 0.58,
                swirl: 0.31,
                speed: 0.11,
                scale: 1.05,
                phase: 1.25,
                motionDirection: 1
            )
            let oppositeFirst = try renderMeshGradient(
                style: oppositeStyle,
                elapsedTime: 0,
                plan: plan,
                device: device,
                commandQueue: commandQueue,
                pipeline: pipeline
            )
            let oppositeLater = try renderMeshGradient(
                style: oppositeStyle,
                elapsedTime: 20,
                plan: plan,
                device: device,
                commandQueue: commandQueue,
                pipeline: pipeline
            )
            let metrics = broadFieldMetrics(
                pixels: first,
                width: plan.background.width,
                height: plan.background.height
            )
            XCTAssertLessThanOrEqual(metrics.centralRowReversals, 10, "\(archetype): \(metrics)")
            XCTAssertLessThan(metrics.strongAdjacentRatio, 0.04, "\(archetype): \(metrics)")
            XCTAssertGreaterThan(metrics.luminanceRange, 0.06, "\(archetype): \(metrics)")
            XCTAssertGreaterThan(
                meanAbsoluteRGBDifference(first, later),
                0.008,
                "\(archetype) must keep moving"
            )
            XCTAssertEqual(first, oppositeFirst, "direction must not reroll the daily topology")
            XCTAssertGreaterThan(
                meanAbsoluteRGBDifference(later, oppositeLater),
                0.008,
                "\(archetype) must visibly move in both directions"
            )
            firstFrames.append(first)
        }

        for lhs in firstFrames.indices {
            for rhs in firstFrames.indices where rhs > lhs {
                XCTAssertGreaterThan(
                    meanAbsoluteRGBDifference(firstFrames[lhs], firstFrames[rhs]),
                    0.012,
                    "archetypes \(lhs) and \(rhs) collapsed into the same topology"
                )
            }
        }
    }

    func testDailyMeshUsesOneCompleteFourColorApplicationPalette() {
        let applicationPalettes: [[SIMD3<Float>]] = [
            ["FFBF65", "FD8973", "003A6C", "002646"],
            ["7FDBDA", "3A9FBF", "1A4B6E", "0B1E33"],
            ["C4B5FD", "7C6FBF", "1F6E5C", "0F1B2D"],
            ["EEDDC9", "C0AC98", "5E7282", "384856"],
            ["EBBFC8", "B87A92", "4A3568", "181430"],
            ["F07838", "D04428", "2E1858", "0C0A22"],
            ["D0A440", "2898A8", "105868", "0A2832"],
        ].map { palette in
            palette.map { DayObjectRGB(hex: $0).linearRGB }
        }
        var observedPaletteIndices = Set<Int>()

        for seed in UInt64(0)..<400 {
            let palette = DayObjectPalette.make(seed: seed)
            let mesh = DayObjectMeshGradientStyle.make(seed: seed, palette: palette)

            XCTAssertEqual(palette.colors.count, 4, "seed=\(seed)")
            XCTAssertEqual(mesh.colors.count, 4, "seed=\(seed)")
            guard let paletteIndex = applicationPalettes.firstIndex(of: mesh.colors) else {
                XCTFail("seed=\(seed) mixed colors from outside a complete application palette")
                continue
            }
            observedPaletteIndices.insert(paletteIndex)

            let uniforms = DayObjectsMeshGradientUniforms(
                style: mesh,
                resolution: SIMD2(320, 180),
                elapsedTime: 0
            )
            XCTAssertEqual(uniforms.colorCount, 4, "seed=\(seed)")
        }

        XCTAssertEqual(
            observedPaletteIndices,
            Set(applicationPalettes.indices),
            "Daily selection must be able to reach every four-color application palette"
        )
    }

    func testMeshGradientUniformLayoutExactlyMatchesMetalABI() {
        XCTAssertEqual(MemoryLayout<DayObjectsMeshGradientUniforms>.alignment, 16)
        XCTAssertEqual(MemoryLayout<DayObjectsMeshGradientUniforms>.size, 128)
        XCTAssertEqual(MemoryLayout<DayObjectsMeshGradientUniforms>.stride, 128)
        XCTAssertEqual(MemoryLayout<DayObjectsMeshGradientUniforms>.offset(of: \.color0), 0)
        XCTAssertEqual(MemoryLayout<DayObjectsMeshGradientUniforms>.offset(of: \.color1), 16)
        XCTAssertEqual(MemoryLayout<DayObjectsMeshGradientUniforms>.offset(of: \.color2), 32)
        XCTAssertEqual(MemoryLayout<DayObjectsMeshGradientUniforms>.offset(of: \.color3), 48)
        XCTAssertEqual(MemoryLayout<DayObjectsMeshGradientUniforms>.offset(of: \.color4), 64)
        XCTAssertEqual(MemoryLayout<DayObjectsMeshGradientUniforms>.offset(of: \.resolution), 80)
        XCTAssertEqual(MemoryLayout<DayObjectsMeshGradientUniforms>.offset(of: \.offset), 88)
        XCTAssertEqual(MemoryLayout<DayObjectsMeshGradientUniforms>.offset(of: \.time), 96)
        XCTAssertEqual(MemoryLayout<DayObjectsMeshGradientUniforms>.offset(of: \.distortion), 100)
        XCTAssertEqual(MemoryLayout<DayObjectsMeshGradientUniforms>.offset(of: \.swirl), 104)
        XCTAssertEqual(MemoryLayout<DayObjectsMeshGradientUniforms>.offset(of: \.scale), 108)
        XCTAssertEqual(MemoryLayout<DayObjectsMeshGradientUniforms>.offset(of: \.phase), 112)
        XCTAssertEqual(MemoryLayout<DayObjectsMeshGradientUniforms>.offset(of: \.colorCount), 116)
        XCTAssertEqual(MemoryLayout<DayObjectsMeshGradientUniforms>.offset(of: \.archetype), 120)
        XCTAssertEqual(MemoryLayout<DayObjectsMeshGradientUniforms>.offset(of: \.motionDirection), 124)
    }

    func testMeshGradientGPUProducesSmoothColorSpotsThatKeepMoving() throws {
        let device = try XCTUnwrap(MTLCreateSystemDefaultDevice())
        let commandQueue = try XCTUnwrap(device.makeCommandQueue())
        let library = try XCTUnwrap(device.makeDefaultLibrary())
        let vertexFunction = try XCTUnwrap(library.makeFunction(name: "dayObjectsFullscreenVertex"))
        let fragmentFunction = try XCTUnwrap(library.makeFunction(name: "dayObjectsMeshGradientFragment"))
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = vertexFunction
        descriptor.fragmentFunction = fragmentFunction
        descriptor.colorAttachments[0].pixelFormat = .rgba16Float
        let pipeline = try device.makeRenderPipelineState(descriptor: descriptor)
        let plan = DayObjectsRenderTargetPlan(drawableWidth: 320, drawableHeight: 240)
        let style = DayObjectMeshGradientStyle(
            colors: [
                DayObjectRGB(hex: "bcecf6").linearRGB,
                DayObjectRGB(hex: "00aaff").linearRGB,
                DayObjectRGB(hex: "00f7ff").linearRGB,
                DayObjectRGB(hex: "ffd447").linearRGB,
            ],
            distortion: 0.8,
            swirl: 0.35,
            speed: 0.1,
            scale: 1,
            phase: 1.25
        )

        let first = try renderMeshGradient(
            style: style,
            elapsedTime: 0,
            plan: plan,
            device: device,
            commandQueue: commandQueue,
            pipeline: pipeline
        )
        let later = try renderMeshGradient(
            style: style,
            elapsedTime: 20,
            plan: plan,
            device: device,
            commandQueue: commandQueue,
            pipeline: pipeline
        )
        let metrics = broadFieldMetrics(
            pixels: first,
            width: plan.background.width,
            height: plan.background.height
        )
        XCTAssertLessThanOrEqual(metrics.centralRowReversals, 8, "metrics=\(metrics)")
        XCTAssertLessThan(metrics.strongAdjacentRatio, 0.03, "metrics=\(metrics)")
        XCTAssertGreaterThan(metrics.luminanceRange, 0.08, "metrics=\(metrics)")
        XCTAssertGreaterThan(
            meanAbsoluteRGBDifference(first, later),
            0.01,
            "The background must keep moving even when no Day Objects actors exist"
        )
    }

    func testMeshGradientStyleUsesCuratedDailyParametersAndUnmutedDayColors() {
        let palette = DayObjectPalette.make(seed: 42)
        let style = DayObjectMeshGradientStyle.make(seed: 42, palette: palette)

        XCTAssertEqual(style, DayObjectMeshGradientStyle.make(seed: 42, palette: palette))
        XCTAssertEqual(style.colors, palette.colors.map(\.linearRGB))
        XCTAssertTrue((0..<(2 * Double.pi)).contains(style.phase))
        XCTAssertTrue([-1.0, 1.0].contains(style.motionDirection))

        let anotherDay = DayObjectMeshGradientStyle.make(seed: 43, palette: palette)
        XCTAssertNotEqual(anotherDay, style)
        XCTAssertEqual(anotherDay.colors, style.colors)
    }

    func testFigureRolesContrastWithBackgroundBase() {
        for seed in UInt64(0)..<400 {
            let palette = DayObjectPalette.make(seed: seed)
            XCTAssertGreaterThanOrEqual(palette.minimumFigureContrast, 1.35)
        }
    }

    func testSceneAndRendererUseTheDailyMeshGradientStyle() {
        let base = DayObjectScene.make(input: input(eventIDs: ["walk"]))
        let enriched = DayObjectScene.make(input: input(eventIDs: ["walk", "sleep", "read"]))

        XCTAssertEqual(
            base.meshGradientStyle,
            DayObjectMeshGradientStyle.make(seed: base.rootSeed, palette: base.palette)
        )
        XCTAssertEqual(enriched.meshGradientStyle, base.meshGradientStyle)

        let earlier = DayObjectsMeshGradientUniforms(
            scene: base,
            resolution: SIMD2(320, 180),
            elapsedTime: 10
        )
        let later = DayObjectsMeshGradientUniforms(
            scene: base,
            resolution: SIMD2(320, 180),
            elapsedTime: 12
        )
        XCTAssertEqual(
            later.time - earlier.time,
            Float(2 * base.meshGradientStyle.speed),
            accuracy: 0.0001
        )
        XCTAssertEqual(earlier.phase, Float(base.meshGradientStyle.phase), accuracy: 0.0001)
        XCTAssertEqual(
            earlier.offset,
            SIMD2(Float(base.meshGradientStyle.offset.x), Float(base.meshGradientStyle.offset.y))
        )
        XCTAssertEqual(earlier.archetype, base.meshGradientStyle.archetype.rawValue)
        XCTAssertEqual(earlier.motionDirection, Float(base.meshGradientStyle.motionDirection))
    }

    private func input(eventIDs: [String]) -> DayObjectSceneInput {
        DayObjectSceneInput(
            dayKey: "2026-08-20",
            identity: "tester",
            eventIDs: eventIDs,
            motionEnergy: 0.55,
            visualClarity: 0.55,
            reduceMotion: false
        )
    }

    private func renderMeshGradient(
        style: DayObjectMeshGradientStyle,
        elapsedTime: TimeInterval,
        plan: DayObjectsRenderTargetPlan,
        device: MTLDevice,
        commandQueue: MTLCommandQueue,
        pipeline: MTLRenderPipelineState
    ) throws -> [UInt16] {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba16Float,
            width: plan.background.width,
            height: plan.background.height,
            mipmapped: false
        )
        descriptor.storageMode = .shared
        descriptor.usage = [.renderTarget, .shaderRead]
        let texture = try XCTUnwrap(device.makeTexture(descriptor: descriptor))
        let renderPass = MTLRenderPassDescriptor()
        renderPass.colorAttachments[0].texture = texture
        renderPass.colorAttachments[0].loadAction = .clear
        renderPass.colorAttachments[0].storeAction = .store
        renderPass.colorAttachments[0].clearColor = MTLClearColorMake(0, 0, 0, 1)

        let commandBuffer = try XCTUnwrap(commandQueue.makeCommandBuffer())
        let encoder = try XCTUnwrap(commandBuffer.makeRenderCommandEncoder(descriptor: renderPass))
        var uniforms = DayObjectsMeshGradientUniforms(
            style: style,
            resolution: SIMD2(Float(plan.background.width), Float(plan.background.height)),
            elapsedTime: elapsedTime
        )
        encoder.setRenderPipelineState(pipeline)
        encoder.setFragmentBytes(
            &uniforms,
            length: MemoryLayout<DayObjectsMeshGradientUniforms>.stride,
            index: 0
        )
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        encoder.endEncoding()
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
        XCTAssertEqual(commandBuffer.status, .completed)
        XCTAssertNil(commandBuffer.error)

        var pixels = [UInt16](
            repeating: 0,
            count: plan.background.width * plan.background.height * 4
        )
        texture.getBytes(
            &pixels,
            bytesPerRow: plan.background.width * 4 * MemoryLayout<UInt16>.stride,
            from: MTLRegionMake2D(0, 0, plan.background.width, plan.background.height),
            mipmapLevel: 0
        )
        return pixels
    }

    private func meanAbsoluteRGBDifference(_ lhs: [UInt16], _ rhs: [UInt16]) -> Double {
        precondition(lhs.count == rhs.count)
        var total = 0.0
        var componentCount = 0
        for index in stride(from: 0, to: lhs.count, by: 4) {
            for component in 0..<3 {
                total += abs(
                    Double(Float(Float16(bitPattern: lhs[index + component])))
                        - Double(Float(Float16(bitPattern: rhs[index + component])))
                )
                componentCount += 1
            }
        }
        return total / Double(max(componentCount, 1))
    }

    private func broadFieldMetrics(
        pixels: [UInt16],
        width: Int,
        height: Int
    ) -> (centralRowReversals: Int, strongAdjacentRatio: Double, luminanceRange: Float) {
        func luminance(x: Int, y: Int) -> Float {
            let index = (y * width + x) * 4
            let red = Float(Float16(bitPattern: pixels[index]))
            let green = Float(Float16(bitPattern: pixels[index + 1]))
            let blue = Float(Float16(bitPattern: pixels[index + 2]))
            return red * 0.2126 + green * 0.7152 + blue * 0.0722
        }

        let centerY = height / 2
        var reversals = 0
        var previousDirection = 0
        for x in 1..<width {
            let delta = luminance(x: x, y: centerY) - luminance(x: x - 1, y: centerY)
            let direction = delta > 0.002 ? 1 : (delta < -0.002 ? -1 : 0)
            if direction != 0 {
                if previousDirection != 0, direction != previousDirection {
                    reversals += 1
                }
                previousDirection = direction
            }
        }

        var strongAdjacent = 0
        var adjacentCount = 0
        var minimum = Float.greatestFiniteMagnitude
        var maximum = -Float.greatestFiniteMagnitude
        for y in 0..<height {
            for x in 0..<width {
                let value = luminance(x: x, y: y)
                minimum = min(minimum, value)
                maximum = max(maximum, value)
                if x > 0 {
                    adjacentCount += 1
                    if abs(value - luminance(x: x - 1, y: y)) > 0.04 {
                        strongAdjacent += 1
                    }
                }
            }
        }

        return (
            centralRowReversals: reversals,
            strongAdjacentRatio: Double(strongAdjacent) / Double(max(adjacentCount, 1)),
            luminanceRange: maximum - minimum
        )
    }
}
