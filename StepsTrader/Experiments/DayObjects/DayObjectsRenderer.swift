import Foundation
import Metal
import MetalKit
import QuartzCore
import simd

/// Swift counterpart of Metal's 128-byte mesh-gradient uniform block.
struct DayObjectsMeshGradientUniforms: Equatable {
    static let metalAlignment = 16
    static let metalStride = 128

    let color0: SIMD4<Float>             // bytes 0...15
    let color1: SIMD4<Float>             // bytes 16...31
    let color2: SIMD4<Float>             // bytes 32...47
    let color3: SIMD4<Float>             // bytes 48...63
    let color4: SIMD4<Float>             // bytes 64...79
    let resolution: SIMD2<Float>         // bytes 80...87
    let offset: SIMD2<Float>             // bytes 88...95
    let time: Float                      // bytes 96...99
    let distortion: Float                // bytes 100...103
    let swirl: Float                     // bytes 104...107
    let scale: Float                     // bytes 108...111
    let phase: Float                     // bytes 112...115
    let colorCount: UInt32               // bytes 116...119
    let archetype: UInt32                // bytes 120...123
    let motionDirection: Float           // bytes 124...127

    init(scene: DayObjectScene, resolution: SIMD2<Float>, elapsedTime: TimeInterval) {
        self.init(
            style: scene.meshGradientStyle,
            resolution: resolution,
            elapsedTime: elapsedTime
        )
    }

    init(
        style: DayObjectMeshGradientStyle,
        resolution rawResolution: SIMD2<Float>,
        elapsedTime: TimeInterval
    ) {
        var colors = style.colors.prefix(5).map(Self.packedLinearColor)
        let fallback = colors.last ?? SIMD4<Float>(0, 0, 0, 1)
        while colors.count < 3 {
            colors.append(fallback)
        }
        color0 = colors[0]
        color1 = colors[1]
        color2 = colors[2]
        color3 = colors.count > 3 ? colors[3] : colors[2]
        color4 = colors.count > 4 ? colors[4] : color3
        resolution = SIMD2(
            Self.positiveFinite(rawResolution.x),
            Self.positiveFinite(rawResolution.y)
        )
        offset = SIMD2(Self.finite(Float(style.offset.x)), Self.finite(Float(style.offset.y)))
        let elapsed = elapsedTime.isFinite ? max(elapsedTime, 0) : 0
        let speed = style.speed.isFinite ? max(style.speed, 0) : 0
        time = Self.finite(Float(elapsed * speed))
        distortion = Self.finite(Float(style.distortion))
        swirl = Self.finite(Float(style.swirl))
        scale = Self.finite(Float(style.scale))
        phase = Self.finite(Float(style.phase))
        colorCount = UInt32(min(max(style.colors.count, 3), 5))
        archetype = style.archetype.rawValue
        motionDirection = style.motionDirection < 0 ? -1 : 1
    }

    private static func packedLinearColor(_ color: SIMD3<Float>) -> SIMD4<Float> {
        SIMD4(clampedUnit(color.x), clampedUnit(color.y), clampedUnit(color.z), 1)
    }

    private static func clampedUnit(_ value: Float) -> Float {
        value.isFinite ? min(max(value, 0), 1) : 0
    }

    private static func positiveFinite(_ value: Float) -> Float {
        value.isFinite ? max(value, 1) : 1
    }

    private static func finite(_ value: Float) -> Float {
        value.isFinite ? value : 0
    }
}

/// Per-draw values shared by every instanced actor quad.
///
/// Signed-distance values are converted from short-side coordinates to
/// physical screen pixels before the shader evaluates `fwidth`, keeping edge
/// antialiasing stable across canvas sizes and aspect ratios.
struct DayObjectsActorUniforms: Equatable {
    let resolution: SIMD2<Float>       // bytes 0...7
    let energyNormalization: Float     // bytes 8...11
    let shortSidePixels: Float         // bytes 12...15
    let radialColor0: SIMD4<Float>      // bytes 16...31
    let radialColor1: SIMD4<Float>      // bytes 32...47
    let radialColor2: SIMD4<Float>      // bytes 48...63
    let radialParameters0: SIMD4<Float> // bytes 64...79
    let radialParameters1: SIMD4<Float> // bytes 80...95
    let radialParameters2: SIMD4<Float> // bytes 96...111

    init(
        resolution rawResolution: SIMD2<Float>,
        visibleActorCount: Int,
        radialFillStyle: DayObjectRadialFillStyle = .fallback
    ) {
        let resolution = SIMD2(
            Self.positiveFinite(rawResolution.x),
            Self.positiveFinite(rawResolution.y)
        )
        self.resolution = resolution
        shortSidePixels = min(resolution.x, resolution.y)
        energyNormalization = visibleActorCount > 0
            ? 1 / sqrt(Float(visibleActorCount))
            : 0

        var colors = radialFillStyle.colors.prefix(3).map(Self.packedColor)
        let fallback = colors.last ?? SIMD4<Float>(1, 1, 1, 1)
        while colors.count < 3 {
            colors.append(fallback)
        }
        radialColor0 = colors[0]
        radialColor1 = colors[1]
        radialColor2 = colors[2]
        radialParameters0 = SIMD4(
            Self.finite(Float(radialFillStyle.radius), fallback: 0.9),
            Self.finite(Float(radialFillStyle.focalDistance)),
            Self.finite(Float(radialFillStyle.focalAngle)),
            Self.finite(Float(radialFillStyle.falloff))
        )
        radialParameters1 = SIMD4(
            Self.finite(Float(radialFillStyle.mixing), fallback: 0.6),
            Self.finite(Float(radialFillStyle.distortion)),
            Self.finite(Float(radialFillStyle.distortionShift)),
            Float(min(max(radialFillStyle.distortionFrequency, 2), 12))
        )
        radialParameters2 = SIMD4(
            Self.finite(Float(radialFillStyle.rotation)),
            Self.finite(Float(radialFillStyle.offset.x)),
            Self.finite(Float(radialFillStyle.offset.y)),
            Float(min(max(radialFillStyle.colors.count, 1), 3))
        )
    }

    private static func packedColor(_ color: SIMD3<Float>) -> SIMD4<Float> {
        SIMD4(
            color.x.isFinite ? min(max(color.x, 0), 1) : 0,
            color.y.isFinite ? min(max(color.y, 0), 1) : 0,
            color.z.isFinite ? min(max(color.z, 0), 1) : 0,
            1
        )
    }

    private static func positiveFinite(_ value: Float) -> Float {
        value.isFinite ? max(value, 1) : 1
    }

    private static func finite(_ value: Float, fallback: Float = 0) -> Float {
        value.isFinite ? value : fallback
    }
}

/// Swift counterpart of Metal's `DayObjectsPostUniforms`.
///
/// The first sixteen bytes contain focus controls, and the second sixteen
/// contain display/grain controls. Metal's `float2` alignment makes the exact
/// shared stride 32 bytes without implicit padding.
struct DayObjectsPostUniforms: Equatable {
    static let metalAlignment = 8
    static let metalStride = 32
    static let maximumBlurRadiusPixels: Float = 32
    static let lightPaletteLuminanceStart = 0.34
    static let lightPaletteLuminanceWidth = 0.12

    let resolution: SIMD2<Float>       // bytes 0...7
    let blurRadiusPixels: Float        // bytes 8...11
    let contrast: Float                // bytes 12...15
    let saturation: Float              // bytes 16...19
    let grainIntensity: Float          // bytes 20...23
    let grainPhase: Float              // bytes 24...27
    let grainSeed: UInt32              // bytes 28...31

    init(
        frame: DayObjectRenderFrame,
        scene: DayObjectScene,
        resolution: SIMD2<Float>,
        pointToPixelScale: Float
    ) {
        let paletteLuminance: Double
        if scene.palette.colors.isEmpty {
            paletteLuminance = 0
        } else {
            paletteLuminance = scene.palette.colors.reduce(0) {
                $0 + relativeLuminance($1.linearRGB)
            } / Double(scene.palette.colors.count)
        }
        self.init(
            postProcess: frame.postProcess,
            resolution: resolution,
            pointToPixelScale: pointToPixelScale,
            grainSeed: scene.rootSeed,
            paletteLuminance: paletteLuminance
        )
    }

    init(
        postProcess: DayObjectPostProcess,
        resolution rawResolution: SIMD2<Float>,
        pointToPixelScale rawPointToPixelScale: Float,
        grainSeed rawGrainSeed: UInt64,
        paletteLuminance rawPaletteLuminance: Double
    ) {
        resolution = SIMD2(
            Self.positiveFinite(rawResolution.x),
            Self.positiveFinite(rawResolution.y)
        )

        let pointToPixelScale = rawPointToPixelScale.isFinite && rawPointToPixelScale > 0
            ? rawPointToPixelScale
            : 1
        let pointRadius = postProcess.blurRadius.isFinite
            ? max(Float(postProcess.blurRadius), 0)
            : 0
        blurRadiusPixels = min(
            pointRadius * pointToPixelScale,
            Self.maximumBlurRadiusPixels
        )
        contrast = Self.nonnegativeFinite(Float(postProcess.contrast))
        saturation = Self.nonnegativeFinite(Float(postProcess.saturation))

        _ = rawPaletteLuminance
        grainIntensity = 0.05

        grainPhase = postProcess.grainPhase.isFinite
            ? max(Float(postProcess.grainPhase), 0)
            : 0
        let foldedSeed = rawGrainSeed ^ (rawGrainSeed >> 32)
        grainSeed = UInt32(truncatingIfNeeded: foldedSeed)
    }

    private static func positiveFinite(_ value: Float) -> Float {
        value.isFinite ? max(value, 1) : 1
    }

    private static func nonnegativeFinite(_ value: Float) -> Float {
        value.isFinite ? max(value, 0) : 0
    }

}

/// A depth-sorted frame snapshot ready for a single instanced actor draw.
struct DayObjectsActorUpload: Equatable {
    let actors: [DayObjectGPUActor]
    let uniforms: DayObjectsActorUniforms

    init(
        actors renderActors: [DayObjectRenderActor],
        resolution: SIMD2<Float>,
        radialFillStyle: DayObjectRadialFillStyle = .fallback
    ) {
        let boundedActors = Array(renderActors.prefix(DayObjectScene.maxActors))
        self.init(
            gpuActors: boundedActors.map(\.gpuActor),
            visibleActorCount: boundedActors.filter { $0.opacity > 0 }.count,
            resolution: resolution,
            radialFillStyle: radialFillStyle
        )
    }

    private init(
        gpuActors: [DayObjectGPUActor],
        visibleActorCount: Int,
        resolution: SIMD2<Float>,
        radialFillStyle: DayObjectRadialFillStyle
    ) {
        actors = Array(gpuActors.prefix(DayObjectScene.maxActors))
        uniforms = DayObjectsActorUniforms(
            resolution: resolution,
            visibleActorCount: min(max(visibleActorCount, 0), actors.count),
            radialFillStyle: radialFillStyle
        )
    }
}

enum DayObjectsActorRendering {
    static func pipelineDescriptor(
        library: MTLLibrary,
        pixelFormat: MTLPixelFormat
    ) -> MTLRenderPipelineDescriptor? {
        guard let vertexFunction = library.makeFunction(name: "dayObjectsActorVertex"),
              let fragmentFunction = library.makeFunction(name: "dayObjectsActorFragment")
        else { return nil }

        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.label = "Day Objects instanced actor pipeline"
        descriptor.vertexFunction = vertexFunction
        descriptor.fragmentFunction = fragmentFunction

        let attachment = descriptor.colorAttachments[0]
        attachment?.pixelFormat = pixelFormat
        attachment?.isBlendingEnabled = true
        attachment?.rgbBlendOperation = .add
        attachment?.alphaBlendOperation = .add
        attachment?.sourceRGBBlendFactor = .one
        attachment?.destinationRGBBlendFactor = .oneMinusSourceAlpha
        attachment?.sourceAlphaBlendFactor = .one
        attachment?.destinationAlphaBlendFactor = .oneMinusSourceAlpha
        return descriptor
    }
}

enum DayObjectsPostRendering {
    static func blurPipelineDescriptor(
        library: MTLLibrary,
        horizontal: Bool,
        pixelFormat: MTLPixelFormat
    ) -> MTLRenderPipelineDescriptor? {
        pipelineDescriptor(
            library: library,
            fragmentName: horizontal
                ? "dayObjectsBlurHorizontal"
                : "dayObjectsBlurVertical",
            label: horizontal
                ? "Day Objects horizontal focus blur pipeline"
                : "Day Objects vertical focus blur pipeline",
            pixelFormat: pixelFormat
        )
    }

    static func displayPipelineDescriptor(
        library: MTLLibrary,
        pixelFormat: MTLPixelFormat
    ) -> MTLRenderPipelineDescriptor? {
        pipelineDescriptor(
            library: library,
            fragmentName: "dayObjectsDisplayFragment",
            label: "Day Objects contrast, saturation, and grain pipeline",
            pixelFormat: pixelFormat
        )
    }

    private static func pipelineDescriptor(
        library: MTLLibrary,
        fragmentName: String,
        label: String,
        pixelFormat: MTLPixelFormat
    ) -> MTLRenderPipelineDescriptor? {
        guard let vertexFunction = library.makeFunction(name: "dayObjectsFullscreenVertex"),
              let fragmentFunction = library.makeFunction(name: fragmentName)
        else { return nil }

        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.label = label
        descriptor.vertexFunction = vertexFunction
        descriptor.fragmentFunction = fragmentFunction
        descriptor.colorAttachments[0].pixelFormat = pixelFormat
        return descriptor
    }
}

struct DayObjectsRenderTargetDescriptor: Equatable {
    let width: Int
    let height: Int

    var pixelCount: Int {
        let result = width.multipliedReportingOverflow(by: height)
        return result.overflow ? .max : result.partialValue
    }
}

struct DayObjectsRenderTargetPlan: Equatable {
    static let maximumBackgroundPixels = 1_000_000

    let background: DayObjectsRenderTargetDescriptor
    let scene: DayObjectsRenderTargetDescriptor
    let blurPingPong: [DayObjectsRenderTargetDescriptor]

    init(drawableWidth rawWidth: Int, drawableHeight rawHeight: Int) {
        let width = max(rawWidth, 1)
        let height = max(rawHeight, 1)
        let fullSize = DayObjectsRenderTargetDescriptor(width: width, height: height)

        let halfWidth = max(Double(width) * 0.5, 1)
        let halfHeight = max(Double(height) * 0.5, 1)
        let halfPixelCount = halfWidth * halfHeight
        let scale = halfPixelCount > Double(Self.maximumBackgroundPixels)
            ? sqrt(Double(Self.maximumBackgroundPixels) / halfPixelCount)
            : 1
        var backgroundWidth = max(
            Int(min(halfWidth * scale, Double(Self.maximumBackgroundPixels)).rounded(.down)),
            1
        )
        var backgroundHeight = max(
            Int(min(halfHeight * scale, Double(Self.maximumBackgroundPixels)).rounded(.down)),
            1
        )

        // The final integer clamp makes the invariant independent of floating-point
        // rounding and remains safe even for theoretical Int.max drawable inputs.
        backgroundWidth = min(backgroundWidth, Self.maximumBackgroundPixels)
        backgroundHeight = min(
            backgroundHeight,
            Self.maximumBackgroundPixels / backgroundWidth
        )

        background = DayObjectsRenderTargetDescriptor(
            width: backgroundWidth,
            height: backgroundHeight
        )
        scene = fullSize
        blurPingPong = [fullSize, fullSize]
    }
}

/// Small deterministic ownership state machine used by the renderer's shared
/// upload buffers. A slot stays occupied until the command buffer which reads
/// it has completed, including GPU error completion.
final class DayObjectsInFlightScheduler {
    let slotCount: Int

    private let lock = NSLock()
    private var occupied: [Bool]

    init(slotCount: Int) {
        self.slotCount = max(slotCount, 3)
        occupied = Array(repeating: false, count: self.slotCount)
    }

    func acquire() -> Int? {
        lock.lock()
        defer { lock.unlock() }
        guard let slot = occupied.firstIndex(of: false) else { return nil }
        occupied[slot] = true
        return slot
    }

    func complete(_ slot: Int) {
        lock.lock()
        defer { lock.unlock() }
        guard occupied.indices.contains(slot), occupied[slot] else { return }
        occupied[slot] = false
    }
}

final class DayObjectsActorBufferRing {
    struct Lease {
        let slot: Int
        let buffer: MTLBuffer
    }

    let slotCount: Int
    let bufferLength: Int

    private let scheduler: DayObjectsInFlightScheduler
    private let buffers: [MTLBuffer]

    init?(
        device: MTLDevice,
        slotCount requestedSlotCount: Int = 3,
        actorCapacity: Int
    ) {
        scheduler = DayObjectsInFlightScheduler(slotCount: requestedSlotCount)
        slotCount = scheduler.slotCount
        let capacity = min(max(actorCapacity, 1), DayObjectScene.maxActors)
        bufferLength = DayObjectGPUActor.metalStride * capacity

        var allocated = [MTLBuffer]()
        allocated.reserveCapacity(slotCount)
        for slot in 0..<slotCount {
            guard let buffer = device.makeBuffer(
                length: bufferLength,
                options: .storageModeShared
            ) else { return nil }
            buffer.label = "Day Objects actors in-flight \(slot) (capacity \(capacity))"
            allocated.append(buffer)
        }
        buffers = allocated
    }

    func acquire() -> Lease? {
        guard let slot = scheduler.acquire() else { return nil }
        return Lease(slot: slot, buffer: buffers[slot])
    }

    func abandon(_ lease: Lease) {
        scheduler.complete(lease.slot)
    }

    func submit(_ lease: Lease, on commandBuffer: MTLCommandBuffer) {
        commandBuffer.addCompletedHandler { [scheduler] _ in
            scheduler.complete(lease.slot)
        }
    }
}

/// Monotonic elapsed time owned by one renderer instance.
///
/// Pausing retains elapsed time and moves the local origin when playback
/// resumes, so neither long-running sessions nor pauses cause a reset or wrap.
final class DayObjectsClock {
    typealias Now = () -> TimeInterval

    private let now: Now
    private var runningOrigin: TimeInterval
    private var retainedElapsed: TimeInterval = 0
    private var lastReportedElapsed: TimeInterval = 0
    private var isPaused = false

    init(now: @escaping Now = { CACurrentMediaTime() }) {
        self.now = now
        runningOrigin = Self.finiteTime(now())
    }

    var elapsedTime: TimeInterval {
        let candidate: TimeInterval
        if isPaused {
            candidate = retainedElapsed
        } else {
            candidate = retainedElapsed + max(Self.finiteTime(now()) - runningOrigin, 0)
        }
        lastReportedElapsed = max(lastReportedElapsed, candidate)
        return lastReportedElapsed
    }

    func setPaused(_ paused: Bool) {
        guard paused != isPaused else { return }
        let elapsed = elapsedTime
        retainedElapsed = elapsed
        isPaused = paused
        if !paused {
            runningOrigin = Self.finiteTime(now())
        }
    }

    private static func finiteTime(_ time: TimeInterval) -> TimeInterval {
        time.isFinite ? time : 0
    }
}

struct DayObjectTransitionRenderState: Equatable {
    let scene: DayObjectScene
    let insertions: [String: TimeInterval]
    let removals: [String: TimeInterval]
    let actorInsertions: [DayObjectActorID: TimeInterval]
    let actorRemovals: [DayObjectActorID: TimeInterval]
}

/// Tracks actor-local entrances and departures within one immutable daily
/// root. Departing actors retain their exact actor values until the longest
/// local exit envelope has completed. A root switch clears all live state.
struct DayObjectInsertionTimeline: Equatable {
    private(set) var timestamps: [String: TimeInterval] = [:]
    private(set) var removalTimestamps: [String: TimeInterval] = [:]
    private(set) var actorTimestamps: [DayObjectActorID: TimeInterval] = [:]
    private(set) var actorRemovalTimestamps: [DayObjectActorID: TimeInterval] = [:]

    private var rootSeed: UInt64
    private var admittedActorIDs: Set<DayObjectActorID>
    private var admittedActorsByID: [DayObjectActorID: DayObjectActor]
    private var pendingActorIDs: [DayObjectActorID] = []
    private var departingActorsByID: [DayObjectActorID: DayObjectActor] = [:]
    private var departureOrder: [DayObjectActorID] = []

    init(scene: DayObjectScene) {
        rootSeed = scene.rootSeed
        admittedActorIDs = Set(scene.actorIDs)
        admittedActorsByID = Dictionary(uniqueKeysWithValues: scene.actors.map { ($0.id, $0) })
    }

    mutating func update(scene: DayObjectScene, elapsed rawElapsed: TimeInterval) {
        guard scene.rootSeed == rootSeed else {
            reset(to: scene)
            return
        }

        let elapsed = rawElapsed.isFinite ? max(rawElapsed, 0) : 0
        let desiredActorsByID = Dictionary(
            uniqueKeysWithValues: scene.actors.map { ($0.id, $0) }
        )
        let desiredActorIDs = Set(desiredActorsByID.keys)

        pendingActorIDs.removeAll { !desiredActorIDs.contains($0) }
        for actorID in admittedActorIDs.subtracting(desiredActorIDs).sorted() {
            guard let actor = admittedActorsByID.removeValue(forKey: actorID) else { continue }
            admittedActorIDs.remove(actorID)
            actorTimestamps.removeValue(forKey: actorID)
            departingActorsByID[actorID] = actor
            actorRemovalTimestamps[actorID] = elapsed
            departureOrder.append(actorID)
        }

        for actor in scene.actors {
            if departingActorsByID.removeValue(forKey: actor.id) != nil {
                actorRemovalTimestamps.removeValue(forKey: actor.id)
                departureOrder.removeAll { $0 == actor.id }
                admittedActorIDs.insert(actor.id)
                admittedActorsByID[actor.id] = actor
                continue
            }
            if admittedActorIDs.contains(actor.id) {
                admittedActorsByID[actor.id] = actor
            }
        }

        let pendingSet = Set(pendingActorIDs)
        for actor in scene.actors
        where !admittedActorIDs.contains(actor.id)
            && departingActorsByID[actor.id] == nil
            && !pendingSet.contains(actor.id) {
            pendingActorIDs.append(actor.id)
        }
        refreshEventSummaries(renderedActors: Array(admittedActorsByID.values))
    }

    mutating func renderState(
        activeScene: DayObjectScene,
        elapsed rawElapsed: TimeInterval
    ) -> DayObjectTransitionRenderState {
        guard activeScene.rootSeed == rootSeed else {
            self = DayObjectInsertionTimeline(scene: activeScene)
            return DayObjectTransitionRenderState(
                scene: activeScene,
                insertions: [:],
                removals: [:],
                actorInsertions: [:],
                actorRemovals: [:]
            )
        }

        let elapsed = rawElapsed.isFinite ? max(rawElapsed, 0) : 0
        let expiredActorIDs = departureOrder.filter { actorID in
            guard let actor = departingActorsByID[actorID],
                  let startedAt = actorRemovalTimestamps[actorID]
            else { return true }
            return elapsed - startedAt >= DayObjectRenderFrame.transitionDuration(for: actor)
        }
        for actorID in expiredActorIDs {
            actorRemovalTimestamps.removeValue(forKey: actorID)
            departingActorsByID.removeValue(forKey: actorID)
        }
        departureOrder.removeAll { departingActorsByID[$0] == nil }

        let desiredActorsByID = Dictionary(
            uniqueKeysWithValues: activeScene.actors.map { ($0.id, $0) }
        )
        let desiredActorIDs = Set(desiredActorsByID.keys)
        pendingActorIDs.removeAll { !desiredActorIDs.contains($0) }
        var occupiedCount = admittedActorIDs.count + departingActorsByID.count
        precondition(occupiedCount <= DayObjectScene.maxActors)
        while occupiedCount < DayObjectScene.maxActors, !pendingActorIDs.isEmpty {
            let actorID = pendingActorIDs.removeFirst()
            guard let actor = desiredActorsByID[actorID] else { continue }
            admittedActorIDs.insert(actorID)
            admittedActorsByID[actorID] = actor
            actorTimestamps[actorID] = elapsed
            occupiedCount += 1
        }

        for actor in activeScene.actors where admittedActorIDs.contains(actor.id) {
            admittedActorsByID[actor.id] = actor
        }
        let admitted = activeScene.actors.filter {
            admittedActorIDs.contains($0.id)
        }
        let departures = departureOrder.compactMap {
            departingActorsByID[$0]
        }
        let actors = admitted + departures
        precondition(actors.count <= DayObjectScene.maxActors)
        refreshEventSummaries(renderedActors: actors)

        return DayObjectTransitionRenderState(
            scene: activeScene.replacingActors(actors),
            insertions: timestamps,
            removals: removalTimestamps,
            actorInsertions: actorTimestamps,
            actorRemovals: actorRemovalTimestamps
        )
    }

    private mutating func reset(to scene: DayObjectScene) {
        rootSeed = scene.rootSeed
        admittedActorIDs = Set(scene.actorIDs)
        admittedActorsByID = Dictionary(uniqueKeysWithValues: scene.actors.map { ($0.id, $0) })
        pendingActorIDs.removeAll(keepingCapacity: true)
        departingActorsByID.removeAll(keepingCapacity: true)
        departureOrder.removeAll(keepingCapacity: true)
        actorTimestamps.removeAll(keepingCapacity: true)
        actorRemovalTimestamps.removeAll(keepingCapacity: true)
        timestamps.removeAll(keepingCapacity: true)
        removalTimestamps.removeAll(keepingCapacity: true)
    }

    private mutating func refreshEventSummaries(renderedActors: [DayObjectActor]) {
        timestamps = Self.eventSummary(
            actorTimestamps,
            renderedActors: renderedActors
        )
        removalTimestamps = Self.eventSummary(
            actorRemovalTimestamps,
            renderedActors: renderedActors
        )
    }

    private static func eventSummary(
        _ actorTimes: [DayObjectActorID: TimeInterval],
        renderedActors: [DayObjectActor]
    ) -> [String: TimeInterval] {
        var result = [String: TimeInterval]()
        for (eventID, actors) in Dictionary(grouping: renderedActors, by: \.eventID) {
            let values = actors.compactMap { actorTimes[$0.id] }
            guard values.count == actors.count,
                  let first = values.first,
                  values.allSatisfy({ $0 == first })
            else { continue }
            result[eventID] = first
        }
        return result
    }
}

final class DayObjectsRenderer: NSObject, MTKViewDelegate {
    static let actorCapacity = DayObjectScene.maxActors
    static let colorPixelFormat: MTLPixelFormat = .bgra8Unorm_srgb

    /// The post shader writes linear light. An sRGB drawable performs the
    /// single display transfer on store, while the explicit layer color space
    /// keeps Core Animation from treating the encoded bytes as device RGB.
    static func configureDisplay(_ view: MTKView) {
        view.colorPixelFormat = colorPixelFormat
        (view.layer as? CAMetalLayer)?.colorspace = CGColorSpace(
            name: CGColorSpace.sRGB
        )
    }

    let device: MTLDevice

    private let commandQueue: MTLCommandQueue
    private let meshGradientPipeline: MTLRenderPipelineState
    private let sceneUpscalePipeline: MTLRenderPipelineState
    private let actorPipeline: MTLRenderPipelineState
    private let horizontalBlurPipeline: MTLRenderPipelineState
    private let verticalBlurPipeline: MTLRenderPipelineState
    private let displayPipeline: MTLRenderPipelineState
    private let linearSampler: MTLSamplerState
    private let quadBuffer: MTLBuffer
    private let actorBufferRing: DayObjectsActorBufferRing
    private let clock: DayObjectsClock

    private var scene: DayObjectScene
    private var environment: DayObjectEnvironment
    private var insertionTimeline: DayObjectInsertionTimeline
    private var attemptedTargetPlan: DayObjectsRenderTargetPlan?
    private var renderTargets: RenderTargets?
    private(set) var currentFrame: DayObjectRenderFrame?

    private struct RenderTargets {
        let background: MTLTexture
        let scene: MTLTexture
        let blurPingPong: [MTLTexture]
    }

    @available(*, unavailable)
    private override init() {
        fatalError("Use DayObjectsRenderer.create(scene:environment:clock:)")
    }

    private init(
        device: MTLDevice,
        commandQueue: MTLCommandQueue,
        meshGradientPipeline: MTLRenderPipelineState,
        sceneUpscalePipeline: MTLRenderPipelineState,
        actorPipeline: MTLRenderPipelineState,
        horizontalBlurPipeline: MTLRenderPipelineState,
        verticalBlurPipeline: MTLRenderPipelineState,
        displayPipeline: MTLRenderPipelineState,
        linearSampler: MTLSamplerState,
        quadBuffer: MTLBuffer,
        actorBufferRing: DayObjectsActorBufferRing,
        clock: DayObjectsClock,
        scene: DayObjectScene,
        environment: DayObjectEnvironment
    ) {
        self.device = device
        self.commandQueue = commandQueue
        self.meshGradientPipeline = meshGradientPipeline
        self.sceneUpscalePipeline = sceneUpscalePipeline
        self.actorPipeline = actorPipeline
        self.horizontalBlurPipeline = horizontalBlurPipeline
        self.verticalBlurPipeline = verticalBlurPipeline
        self.displayPipeline = displayPipeline
        self.linearSampler = linearSampler
        self.quadBuffer = quadBuffer
        self.actorBufferRing = actorBufferRing
        self.clock = clock
        self.scene = scene
        self.environment = environment
        insertionTimeline = DayObjectInsertionTimeline(scene: scene)
        super.init()
    }

    static func create(
        scene: DayObjectScene,
        environment: DayObjectEnvironment,
        clock: DayObjectsClock = DayObjectsClock()
    ) -> DayObjectsRenderer? {
        guard let device = MTLCreateSystemDefaultDevice(),
              let commandQueue = device.makeCommandQueue(),
              let library = device.makeDefaultLibrary(),
              let fullscreenVertex = library.makeFunction(name: "dayObjectsFullscreenVertex"),
              let meshGradientFragment = library.makeFunction(name: "dayObjectsMeshGradientFragment"),
              let sceneUpscaleFragment = library.makeFunction(name: "dayObjectsBackgroundPresentFragment")
        else {
            AppLogger.ui.error("[DAY_OBJECTS] Metal setup unavailable; using static fallback")
            return nil
        }

        let meshGradientDescriptor = MTLRenderPipelineDescriptor()
        meshGradientDescriptor.label = "Day Objects Mesh Gradient pipeline"
        meshGradientDescriptor.vertexFunction = fullscreenVertex
        meshGradientDescriptor.fragmentFunction = meshGradientFragment
        meshGradientDescriptor.colorAttachments[0].pixelFormat = .rgba16Float

        let sceneUpscaleDescriptor = MTLRenderPipelineDescriptor()
        sceneUpscaleDescriptor.label = "Day Objects background scene upscale pipeline"
        sceneUpscaleDescriptor.vertexFunction = fullscreenVertex
        sceneUpscaleDescriptor.fragmentFunction = sceneUpscaleFragment
        sceneUpscaleDescriptor.colorAttachments[0].pixelFormat = .rgba16Float

        guard let actorDescriptor = DayObjectsActorRendering.pipelineDescriptor(
            library: library,
            pixelFormat: .rgba16Float
        ), let horizontalBlurDescriptor = DayObjectsPostRendering.blurPipelineDescriptor(
            library: library,
            horizontal: true,
            pixelFormat: .rgba16Float
        ), let verticalBlurDescriptor = DayObjectsPostRendering.blurPipelineDescriptor(
            library: library,
            horizontal: false,
            pixelFormat: .rgba16Float
        ), let displayDescriptor = DayObjectsPostRendering.displayPipelineDescriptor(
            library: library,
            pixelFormat: colorPixelFormat
        ) else {
            AppLogger.ui.error("[DAY_OBJECTS] Actor or post shaders unavailable; using static fallback")
            return nil
        }

        let meshGradientPipeline: MTLRenderPipelineState
        let sceneUpscalePipeline: MTLRenderPipelineState
        let actorPipeline: MTLRenderPipelineState
        let horizontalBlurPipeline: MTLRenderPipelineState
        let verticalBlurPipeline: MTLRenderPipelineState
        let displayPipeline: MTLRenderPipelineState
        do {
            meshGradientPipeline = try device.makeRenderPipelineState(descriptor: meshGradientDescriptor)
            sceneUpscalePipeline = try device.makeRenderPipelineState(descriptor: sceneUpscaleDescriptor)
            actorPipeline = try device.makeRenderPipelineState(descriptor: actorDescriptor)
            horizontalBlurPipeline = try device.makeRenderPipelineState(
                descriptor: horizontalBlurDescriptor
            )
            verticalBlurPipeline = try device.makeRenderPipelineState(
                descriptor: verticalBlurDescriptor
            )
            displayPipeline = try device.makeRenderPipelineState(descriptor: displayDescriptor)
        } catch {
            AppLogger.ui.error("[DAY_OBJECTS] Pipeline setup failed; using static fallback: \(error)")
            return nil
        }

        let samplerDescriptor = MTLSamplerDescriptor()
        samplerDescriptor.minFilter = .linear
        samplerDescriptor.magFilter = .linear
        samplerDescriptor.sAddressMode = .clampToEdge
        samplerDescriptor.tAddressMode = .clampToEdge
        guard let linearSampler = device.makeSamplerState(descriptor: samplerDescriptor) else {
            AppLogger.ui.error("[DAY_OBJECTS] Sampler setup failed; using static fallback")
            return nil
        }

        let quadVertices: [SIMD2<Float>] = [
            SIMD2(-1, -1),
            SIMD2(1, -1),
            SIMD2(-1, 1),
            SIMD2(1, 1),
        ]
        let quadBuffer = quadVertices.withUnsafeBytes { bytes -> MTLBuffer? in
            guard let baseAddress = bytes.baseAddress else { return nil }
            return device.makeBuffer(bytes: baseAddress, length: bytes.count, options: .storageModeShared)
        }
        guard let quadBuffer,
              let actorBufferRing = DayObjectsActorBufferRing(
                  device: device,
                  slotCount: 3,
                  actorCapacity: actorCapacity
              )
        else {
            AppLogger.ui.error("[DAY_OBJECTS] Buffer allocation failed; using static fallback")
            return nil
        }
        quadBuffer.label = "Day Objects immutable quad"

        return DayObjectsRenderer(
            device: device,
            commandQueue: commandQueue,
            meshGradientPipeline: meshGradientPipeline,
            sceneUpscalePipeline: sceneUpscalePipeline,
            actorPipeline: actorPipeline,
            horizontalBlurPipeline: horizontalBlurPipeline,
            verticalBlurPipeline: verticalBlurPipeline,
            displayPipeline: displayPipeline,
            linearSampler: linearSampler,
            quadBuffer: quadBuffer,
            actorBufferRing: actorBufferRing,
            clock: clock,
            scene: scene,
            environment: environment
        )
    }

    func update(scene: DayObjectScene, environment: DayObjectEnvironment) {
        insertionTimeline.update(scene: scene, elapsed: clock.elapsedTime)
        self.scene = scene
        self.environment = environment
    }

    func setAnimating(_ isAnimating: Bool) {
        clock.setPaused(!isAnimating)
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        resizeRenderTargets(to: size)
        if Self.shouldDrawStaticFrame(isPaused: view.isPaused, drawableSize: size) {
            view.setNeedsDisplay()
        }
    }

    static func shouldDrawStaticFrame(isPaused: Bool, drawableSize: CGSize) -> Bool {
        isPaused
            && pixelDimension(drawableSize.width) != nil
            && pixelDimension(drawableSize.height) != nil
    }

    func draw(in view: MTKView) {
        resizeRenderTargets(to: view.drawableSize)

        let height = max(view.drawableSize.height, 1)
        let elapsedTime = clock.elapsedTime
        let transitionState = insertionTimeline.renderState(
            activeScene: scene,
            elapsed: elapsedTime
        )
        let renderScene = transitionState.scene
        let frame = DayObjectRenderFrame.make(
            scene: renderScene,
            environment: environment,
            elapsed: elapsedTime,
            insertions: transitionState.insertions,
            removals: transitionState.removals,
            actorInsertions: transitionState.actorInsertions,
            actorRemovals: transitionState.actorRemovals,
            canvasAspect: view.drawableSize.width / height
        )
        currentFrame = frame

        guard let drawable = view.currentDrawable,
              let renderPass = view.currentRenderPassDescriptor,
              let renderTargets,
              let commandBuffer = commandQueue.makeCommandBuffer()
        else { return }

        let backgroundPass = MTLRenderPassDescriptor()
        backgroundPass.colorAttachments[0].texture = renderTargets.background
        backgroundPass.colorAttachments[0].loadAction = .clear
        backgroundPass.colorAttachments[0].storeAction = .store
        backgroundPass.colorAttachments[0].clearColor = MTLClearColorMake(0, 0, 0, 1)

        var uniforms = DayObjectsMeshGradientUniforms(
            scene: renderScene,
            resolution: SIMD2(
                Float(renderTargets.background.width),
                Float(renderTargets.background.height)
            ),
            elapsedTime: elapsedTime
        )
        guard let backgroundEncoder = commandBuffer.makeRenderCommandEncoder(
            descriptor: backgroundPass
        ) else {
            return
        }
        backgroundEncoder.label = "Day Objects half-resolution Mesh Gradient pass"
        backgroundEncoder.setRenderPipelineState(meshGradientPipeline)
        backgroundEncoder.setFragmentBytes(
            &uniforms,
            length: MemoryLayout<DayObjectsMeshGradientUniforms>.stride,
            index: 0
        )
        backgroundEncoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        backgroundEncoder.endEncoding()

        let actorUpload = DayObjectsActorUpload(
            actors: frame.actors,
            resolution: SIMD2(
                Float(renderTargets.scene.width),
                Float(renderTargets.scene.height)
            ),
            radialFillStyle: renderScene.radialFillStyle
        )
        guard let actorBufferLease = actorBufferRing.acquire() else { return }
        var submittedActorBuffer = false
        defer {
            if !submittedActorBuffer {
                actorBufferRing.abandon(actorBufferLease)
            }
        }
        uploadActors(actorUpload.actors, to: actorBufferLease.buffer)

        let scenePass = MTLRenderPassDescriptor()
        scenePass.colorAttachments[0].texture = renderTargets.scene
        scenePass.colorAttachments[0].loadAction = .clear
        scenePass.colorAttachments[0].storeAction = .store
        scenePass.colorAttachments[0].clearColor = MTLClearColorMake(0, 0, 0, 1)
        guard let sceneEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: scenePass) else {
            return
        }
        sceneEncoder.label = "Day Objects full-resolution scene composite"
        sceneEncoder.setRenderPipelineState(sceneUpscalePipeline)
        sceneEncoder.setFragmentTexture(renderTargets.background, index: 0)
        sceneEncoder.setFragmentSamplerState(linearSampler, index: 0)
        sceneEncoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)

        if !actorUpload.actors.isEmpty {
            var actorUniforms = actorUpload.uniforms
            sceneEncoder.setRenderPipelineState(actorPipeline)
            sceneEncoder.setVertexBuffer(quadBuffer, offset: 0, index: 0)
            sceneEncoder.setVertexBuffer(actorBufferLease.buffer, offset: 0, index: 1)
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
                instanceCount: actorUpload.actors.count
            )
        }
        sceneEncoder.endEncoding()

        var postUniforms = DayObjectsPostUniforms(
            frame: frame,
            scene: renderScene,
            resolution: SIMD2(
                Float(renderTargets.scene.width),
                Float(renderTargets.scene.height)
            ),
            pointToPixelScale: Float(view.contentScaleFactor)
        )
        var postSource = renderTargets.scene
        if postUniforms.blurRadiusPixels >= 0.01 {
            guard encodePostPass(
                commandBuffer: commandBuffer,
                target: renderTargets.blurPingPong[0],
                source: renderTargets.scene,
                pipeline: horizontalBlurPipeline,
                uniforms: &postUniforms,
                label: "Day Objects horizontal focus blur"
            ), encodePostPass(
                commandBuffer: commandBuffer,
                target: renderTargets.blurPingPong[1],
                source: renderTargets.blurPingPong[0],
                pipeline: verticalBlurPipeline,
                uniforms: &postUniforms,
                label: "Day Objects vertical focus blur"
            ) else { return }
            postSource = renderTargets.blurPingPong[1]
        }

        renderPass.colorAttachments[0].loadAction = .clear
        renderPass.colorAttachments[0].storeAction = .store
        renderPass.colorAttachments[0].clearColor = MTLClearColorMake(0, 0, 0, 0)
        guard let presentEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPass) else {
            return
        }

        presentEncoder.label = "Day Objects sharp grain and display pass"
        presentEncoder.setRenderPipelineState(displayPipeline)
        presentEncoder.setFragmentTexture(postSource, index: 0)
        presentEncoder.setFragmentSamplerState(linearSampler, index: 0)
        presentEncoder.setFragmentBytes(
            &postUniforms,
            length: MemoryLayout<DayObjectsPostUniforms>.stride,
            index: 0
        )
        presentEncoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        presentEncoder.endEncoding()

        commandBuffer.present(drawable)
        actorBufferRing.submit(actorBufferLease, on: commandBuffer)
        commandBuffer.commit()
        submittedActorBuffer = true
    }

    private func encodePostPass(
        commandBuffer: MTLCommandBuffer,
        target: MTLTexture,
        source: MTLTexture,
        pipeline: MTLRenderPipelineState,
        uniforms: inout DayObjectsPostUniforms,
        label: String
    ) -> Bool {
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = target
        pass.colorAttachments[0].loadAction = .dontCare
        pass.colorAttachments[0].storeAction = .store

        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: pass) else {
            return false
        }
        encoder.label = label
        encoder.setRenderPipelineState(pipeline)
        encoder.setFragmentTexture(source, index: 0)
        encoder.setFragmentSamplerState(linearSampler, index: 0)
        encoder.setFragmentBytes(
            &uniforms,
            length: MemoryLayout<DayObjectsPostUniforms>.stride,
            index: 0
        )
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        encoder.endEncoding()
        return true
    }

    private func uploadActors(_ actors: [DayObjectGPUActor], to actorBuffer: MTLBuffer) {
        actors.withUnsafeBytes { bytes in
            guard let baseAddress = bytes.baseAddress, !bytes.isEmpty else { return }
            actorBuffer.contents().copyMemory(from: baseAddress, byteCount: bytes.count)
        }
    }

    private func resizeRenderTargets(to drawableSize: CGSize) {
        guard let width = Self.pixelDimension(drawableSize.width),
              let height = Self.pixelDimension(drawableSize.height)
        else {
            attemptedTargetPlan = nil
            renderTargets = nil
            return
        }

        let plan = DayObjectsRenderTargetPlan(drawableWidth: width, drawableHeight: height)
        guard plan != attemptedTargetPlan else { return }
        attemptedTargetPlan = plan
        renderTargets = nil

        guard let background = makeTexture(
                  for: plan.background,
                  label: "Day Objects Mesh Gradient target"
              ),
              let scene = makeTexture(for: plan.scene, label: "Day Objects scene target"),
              plan.blurPingPong.count == 2,
              let blurA = makeTexture(for: plan.blurPingPong[0], label: "Day Objects blur A"),
              let blurB = makeTexture(for: plan.blurPingPong[1], label: "Day Objects blur B")
        else {
            AppLogger.ui.error("[DAY_OBJECTS] Render-target allocation failed; using static fallback")
            return
        }

        renderTargets = RenderTargets(
            background: background,
            scene: scene,
            blurPingPong: [blurA, blurB]
        )
    }

    private func makeTexture(
        for target: DayObjectsRenderTargetDescriptor,
        label: String
    ) -> MTLTexture? {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba16Float,
            width: target.width,
            height: target.height,
            mipmapped: false
        )
        descriptor.storageMode = .private
        descriptor.usage = [.renderTarget, .shaderRead]
        let texture = device.makeTexture(descriptor: descriptor)
        texture?.label = label
        return texture
    }

    private static func pixelDimension(_ value: CGFloat) -> Int? {
        guard value.isFinite, value >= 1, value <= CGFloat(Int.max) else { return nil }
        return Int(value.rounded(.down))
    }
}
