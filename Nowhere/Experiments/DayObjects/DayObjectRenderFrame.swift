import Foundation
import simd

enum DayObjectCanvasWall: Equatable, Sendable {
    case left
    case right
    case top
    case bottom
}

struct DayObjectWallImpact: Equatable, Sendable {
    let actorID: DayObjectActorID
    let eventID: String
    let wall: DayObjectCanvasWall
    let speed: Float
    let normalizedX: Float
}

@MainActor
enum DayObjectWallImpactDelivery {
    static func send(
        _ impacts: [DayObjectWallImpact],
        to sink: DayObjectWallImpactSink
    ) {
        for impact in impacts {
            sink.send(impact)
        }
    }
}

enum DayObjectLunarPhysicsOrientation: Equatable {
    case free
    case followsVelocity(bodyAngleOffset: Float)
}

enum DayObjectLunarCollisionGeometry: Equatable {
    case box
    case radial
}

struct DayObjectLunarPhysicsActor: Equatable {
    let id: DayObjectActorID
    let position: SIMD2<Float>
    let direction: SIMD2<Float>
    let halfSize: SIMD2<Float>
    let orientation: DayObjectLunarPhysicsOrientation
    let collisionGeometry: DayObjectLunarCollisionGeometry

    init(
        id: DayObjectActorID,
        position: SIMD2<Float>,
        direction: SIMD2<Float> = SIMD2(1, 0),
        halfSize: SIMD2<Float>,
        orientation: DayObjectLunarPhysicsOrientation = .free,
        collisionGeometry: DayObjectLunarCollisionGeometry = .box
    ) {
        self.id = id
        self.position = position
        self.direction = direction
        self.halfSize = halfSize
        self.orientation = orientation
        self.collisionGeometry = collisionGeometry
    }
}

struct DayObjectLunarPhysicsInfluence: Equatable {
    let impulse: SIMD2<Float>
    let applicationPoint: SIMD2<Float>
}

struct DayObjectLunarPhysicsOutput: Equatable {
    let positions: [DayObjectActorID: SIMD2<Float>]
    let directions: [DayObjectActorID: SIMD2<Float>]
    let impacts: [DayObjectWallImpact]
    let returnDidComplete: Bool

    init(
        positions: [DayObjectActorID: SIMD2<Float>],
        directions: [DayObjectActorID: SIMD2<Float>] = [:],
        impacts: [DayObjectWallImpact],
        returnDidComplete: Bool = false
    ) {
        self.positions = positions
        self.directions = directions
        self.impacts = impacts
        self.returnDidComplete = returnDidComplete
    }
}

/// Bridges SwiftUI's requested playback state and the renderer's frame-based
/// simulation. A Stop must be acknowledged even when it arrives before the
/// first active physics frame, while a restarted playback cancels the old
/// acknowledgement.
struct DayObjectLunarPhysicsReturnHandshake {
    private var playbackWasActive = false
    private var returnIsPending = false

    mutating func update(playbackIsActive: Bool) {
        if playbackIsActive {
            returnIsPending = false
        } else if playbackWasActive {
            // A suspended renderer resets the physics without drawing its return.
            // Keep the acknowledgement until a frame can deliver it, including
            // when the scene becomes inactive halfway through an animated return.
            returnIsPending = true
        }
        playbackWasActive = playbackIsActive
    }

    mutating func consumeCompletionIfReady(
        physicsIsDisplacingActors: Bool,
        returnDidComplete: Bool
    ) -> Bool {
        guard returnIsPending,
              returnDidComplete || !physicsIsDisplacingActors else { return false }
        returnIsPending = false
        return true
    }
}

struct DayObjectLunarInteractionField {
    static func influences(
        from startPoint: SIMD2<Float>,
        to endPoint: SIMD2<Float>,
        gestureImpulse rawImpulse: SIMD2<Float>,
        actors: [DayObjectLunarPhysicsActor]
    ) -> [DayObjectActorID: DayObjectLunarPhysicsInfluence] {
        guard startPoint.x.isFinite, startPoint.y.isFinite,
              endPoint.x.isFinite, endPoint.y.isFinite,
              rawImpulse.x.isFinite, rawImpulse.y.isFinite else { return [:] }
        let magnitude = simd_length(rawImpulse)
        guard magnitude > 0 else { return [:] }
        let impulse = bounded(rawImpulse)
        let impulseMagnitude = simd_length(impulse)
        var result = [DayObjectActorID: DayObjectLunarPhysicsInfluence]()
        for actor in actors {
            var applicationPoint = closestPoint(
                to: actor.position,
                onSegmentFrom: startPoint,
                to: endPoint
            )
            let reach = max(actor.halfSize.x, actor.halfSize.y) + 0.12
            guard simd_distance(actor.position, applicationPoint) <= reach else { continue }
            let impulseDirection = impulse / impulseMagnitude
            let perpendicular = SIMD2(-impulseDirection.y, impulseDirection.x)
            let lever = applicationPoint - actor.position
            let currentOffset = simd_dot(lever, perpendicular)
            let minimumOffset = max(actor.halfSize.x, actor.halfSize.y) * 0.32
            if abs(currentOffset) < minimumOffset {
                applicationPoint += perpendicular * (
                    spinSign(for: actor.id) * minimumOffset - currentOffset
                )
            }
            result[actor.id] = .init(
                impulse: impulse,
                applicationPoint: applicationPoint
            )
        }
        return result
    }

    static func impulses(
        from startPoint: SIMD2<Float>,
        to endPoint: SIMD2<Float>,
        gestureImpulse rawImpulse: SIMD2<Float>,
        actors: [DayObjectLunarPhysicsActor]
    ) -> [DayObjectActorID: SIMD2<Float>] {
        influences(
            from: startPoint,
            to: endPoint,
            gestureImpulse: rawImpulse,
            actors: actors
        ).mapValues(\.impulse)
    }

    static func canvasVector(
        _ normalizedVector: SIMD2<Float>,
        halfSpan: SIMD2<Float>
    ) -> SIMD2<Float> {
        normalizedVector * halfSpan
    }

    static func bounded(
        _ impulse: SIMD2<Float>,
        maximumMagnitude: Float = 0.48
    ) -> SIMD2<Float> {
        let magnitude = simd_length(impulse)
        guard magnitude.isFinite, magnitude > 0 else { return .zero }
        return impulse / magnitude * min(magnitude, max(maximumMagnitude, 0))
    }

    private static func closestPoint(
        to point: SIMD2<Float>,
        onSegmentFrom start: SIMD2<Float>,
        to end: SIMD2<Float>
    ) -> SIMD2<Float> {
        let segment = end - start
        let lengthSquared = simd_length_squared(segment)
        guard lengthSquared > 0.000_001 else { return end }
        let progress = min(max(simd_dot(point - start, segment) / lengthSquared, 0), 1)
        return start + segment * progress
    }

    static func spinSign(for actorID: DayObjectActorID) -> Float {
        var hash: UInt64 = 1_469_598_103_934_665_603
        for byte in actorID.eventID.utf8 {
            hash ^= UInt64(byte)
            hash &*= 1_099_511_628_211
        }
        hash ^= UInt64(bitPattern: Int64(actorID.memberIndex))
        return hash.isMultiple(of: 2) ? -1 : 1
    }
}

struct DayObjectLunarInteractionEvent: Sendable {
    let sequence: UInt64
    let startPoint: SIMD2<Float>
    let endPoint: SIMD2<Float>
    let impulse: SIMD2<Float>
}

final class DayObjectLunarInteractionBus: @unchecked Sendable {
    private let lock = NSLock()
    private var sequence: UInt64 = 0
    private var previousPoint: SIMD2<Float>?
    private var events = [DayObjectLunarInteractionEvent]()

    func begin(normalizedX: Double, normalizedY: Double) {
        lock.lock()
        previousPoint = Self.canvasPoint(x: normalizedX, y: normalizedY)
        lock.unlock()
    }

    func move(normalizedX: Double, normalizedY: Double, speed: Double) {
        let point = Self.canvasPoint(x: normalizedX, y: normalizedY)
        lock.lock()
        defer { lock.unlock() }
        guard let previousPoint else {
            self.previousPoint = point
            return
        }
        let delta = point - previousPoint
        self.previousPoint = point
        let directionMagnitude = simd_length(delta)
        guard directionMagnitude > 0.0001 else { return }
        let normalizedSpeed = Float(min(max(speed.isFinite ? speed : 0, 0) / 2.2, 1))
        sequence &+= 1
        events.append(.init(
            sequence: sequence,
            startPoint: previousPoint,
            endPoint: point,
            impulse: delta / directionMagnitude * (0.12 + 0.36 * normalizedSpeed)
        ))
        if events.count > 16 { events.removeFirst(events.count - 16) }
    }

    func end() {
        lock.lock()
        previousPoint = nil
        lock.unlock()
    }

    func events(after consumedSequence: UInt64) -> [DayObjectLunarInteractionEvent] {
        lock.lock()
        defer { lock.unlock() }
        return events.filter { $0.sequence > consumedSequence }
    }

    private static func canvasPoint(x: Double, y: Double) -> SIMD2<Float> {
        SIMD2(Float(min(max(x, 0), 1) * 2 - 1), Float(1 - min(max(y, 0), 1) * 2))
    }
}

/// A small deterministic simulation in the renderer's short-side canvas space.
/// Actors collide only with walls; overlap between actors is intentional.
struct DayObjectLunarPhysicsEngine {
    struct Configuration: Equatable {
        var acceleration: Float = 0.46
        var initialLinearSpeed: ClosedRange<Float> = 0.24...0.34
        var initialAngularSpeed: ClosedRange<Float> = 0.72...1.16
        var linearDrag: Float = 0.04
        var angularDrag: Float = 0.08
        var angularImpulseScale: Float = 1.2
        var wallAngularFriction: Float = 0.20
        var headingAlignmentStiffness: Float = 20
        var headingAlignmentDamping: Float = 8
        var maximumLinearSpeed: Float = 0.9
        var maximumAngularSpeed: Float = 4.2
        var restitution: Float = 0.84
        var minimumImpactSpeed: Float = 0.15
        var impactCooldown: TimeInterval = 0.28
        var returnDuration: TimeInterval = 0.72
        var maximumFrameDelta: TimeInterval = 1
        var integrationStep: TimeInterval = 1.0 / 60.0
    }

    private enum Phase: Equatable {
        case inactive
        case active
        case returning(startedAt: TimeInterval)
    }

    private struct Body: Equatable {
        var position: SIMD2<Float>
        var velocity: SIMD2<Float>
        var angle: Float
        var angularVelocity: Float
        var halfSize: SIMD2<Float>
        var returnOrigin: SIMD2<Float>
        var returnOriginAngle: Float
        var lastImpactAt: TimeInterval
        var orientation: DayObjectLunarPhysicsOrientation
        var collisionGeometry: DayObjectLunarCollisionGeometry
    }

    private let configuration: Configuration
    private var phase: Phase = .inactive
    private var bodies: [DayObjectActorID: Body] = [:]
    private var lastElapsed: TimeInterval?
    private var canvasHalfSpan = SIMD2<Float>(repeating: 1)
    private var angularMotionIsEnabled = true

    init(configuration: Configuration = .init()) {
        self.configuration = configuration
    }

    var isDisplacingActors: Bool { phase != .inactive }

    mutating func reset() {
        phase = .inactive
        bodies.removeAll(keepingCapacity: true)
        lastElapsed = nil
    }

    mutating func applyImpulse(_ impulse: SIMD2<Float>, to actorID: DayObjectActorID) {
        applyImpulse(impulse, at: bodies[actorID]?.position ?? .zero, to: actorID)
    }

    mutating func applyImpulse(
        _ impulse: SIMD2<Float>,
        at applicationPoint: SIMD2<Float>,
        to actorID: DayObjectActorID
    ) {
        guard phase == .active, impulse.x.isFinite, impulse.y.isFinite,
              applicationPoint.x.isFinite, applicationPoint.y.isFinite,
              var body = bodies[actorID] else { return }
        body.velocity = Self.clampedVelocity(
            body.velocity + impulse,
            maximum: configuration.maximumLinearSpeed
        )
        if angularMotionIsEnabled, body.orientation == .free {
            let lever = applicationPoint - body.position
            let torque = lever.x * impulse.y - lever.y * impulse.x
            body.angularVelocity = Self.clampedAngularVelocity(
                body.angularVelocity
                    + torque / Self.momentOfInertia(for: body.halfSize)
                    * configuration.angularImpulseScale,
                maximum: configuration.maximumAngularSpeed
            )
        }
        bodies[actorID] = body
    }

    mutating func update(
        actors: [DayObjectLunarPhysicsActor],
        gravity rawGravity: SIMD2<Float>,
        canvasHalfSpan rawCanvasHalfSpan: SIMD2<Float> = SIMD2(repeating: 1),
        elapsed rawElapsed: TimeInterval,
        playbackIsActive: Bool,
        angularMotionIsEnabled: Bool = true
    ) -> DayObjectLunarPhysicsOutput {
        let elapsed = rawElapsed.isFinite ? max(rawElapsed, 0) : (lastElapsed ?? 0)
        let gravity = Self.sanitizedGravity(rawGravity)
        canvasHalfSpan = Self.sanitizedCanvasHalfSpan(rawCanvasHalfSpan)
        self.angularMotionIsEnabled = angularMotionIsEnabled

        if playbackIsActive {
            if phase != .active {
                phase = .active
                bodies = Dictionary(uniqueKeysWithValues: actors.map { actor in
                    (actor.id, makeBody(for: actor))
                })
                lastElapsed = elapsed
                return .init(positions: positions, directions: directions, impacts: [])
            }

            synchronizeBodies(with: actors)
            let rawDelta = elapsed - (lastElapsed ?? elapsed)
            let delta = min(max(rawDelta.isFinite ? rawDelta : 0, 0), configuration.maximumFrameDelta)
            lastElapsed = elapsed
            let impacts = integrate(delta: delta, gravity: gravity, elapsed: elapsed)
            return .init(positions: positions, directions: directions, impacts: impacts)
        }

        switch phase {
        case .inactive:
            lastElapsed = elapsed
            return .init(positions: [:], impacts: [])
        case .active:
            for id in bodies.keys {
                guard var body = bodies[id] else { continue }
                body.returnOrigin = body.position
                body.returnOriginAngle = body.angle
                body.angularVelocity = 0
                bodies[id] = body
            }
            phase = .returning(startedAt: elapsed)
        case .returning:
            break
        }

        synchronizeBodies(with: actors)
        guard case let .returning(startedAt) = phase else {
            return .init(positions: [:], impacts: [])
        }
        let progress = configuration.returnDuration > 0
            ? min(max((elapsed - startedAt) / configuration.returnDuration, 0), 1)
            : 1
        if progress >= 1 {
            bodies.removeAll(keepingCapacity: true)
            phase = .inactive
            lastElapsed = elapsed
            return .init(positions: [:], impacts: [], returnDidComplete: true)
        }
        let eased = Float(progress * progress * (3 - 2 * progress))
        let bases = Dictionary(uniqueKeysWithValues: actors.map { ($0.id, $0.position) })
        let baseAngles = Dictionary(uniqueKeysWithValues: actors.map {
            ($0.id, Self.angle(for: $0.direction))
        })
        var returned = [DayObjectActorID: SIMD2<Float>]()
        var returnedDirections = [DayObjectActorID: SIMD2<Float>]()
        for (id, body) in bodies {
            guard let base = bases[id], let baseAngle = baseAngles[id] else { continue }
            returned[id] = simd_mix(body.returnOrigin, base, SIMD2(repeating: eased))
            let angle = Self.interpolateAngle(
                from: body.returnOriginAngle,
                to: baseAngle,
                progress: eased
            )
            returnedDirections[id] = SIMD2(cos(angle), sin(angle))
        }
        lastElapsed = elapsed
        return .init(positions: returned, directions: returnedDirections, impacts: [])
    }

    private var positions: [DayObjectActorID: SIMD2<Float>] {
        bodies.mapValues(\.position)
    }

    private var directions: [DayObjectActorID: SIMD2<Float>] {
        bodies.mapValues { SIMD2(cos($0.angle), sin($0.angle)) }
    }

    private mutating func synchronizeBodies(with actors: [DayObjectLunarPhysicsActor]) {
        let actorIDs = Set(actors.map(\.id))
        bodies = bodies.filter { actorIDs.contains($0.key) }
        for actor in actors {
            let halfSize = Self.sanitizedHalfSize(actor.halfSize)
            if bodies[actor.id] == nil {
                bodies[actor.id] = makeBody(for: actor)
            } else {
                bodies[actor.id]?.halfSize = halfSize
                bodies[actor.id]?.orientation = actor.orientation
                bodies[actor.id]?.collisionGeometry = actor.collisionGeometry
                if !angularMotionIsEnabled {
                    bodies[actor.id]?.angle = Self.angle(for: actor.direction)
                    bodies[actor.id]?.angularVelocity = 0
                }
            }
        }
    }

    private func makeBody(for actor: DayObjectLunarPhysicsActor) -> Body {
        let angle = Self.angle(for: actor.direction)
        let speed = Self.deterministicValue(
            in: configuration.initialLinearSpeed,
            for: actor.id,
            salt: 0xD1B5_4A32_D192_ED03
        )
        let velocityAngle: Float
        switch actor.orientation {
        case .free:
            velocityAngle = angle
        case let .followsVelocity(bodyAngleOffset):
            velocityAngle = angle - bodyAngleOffset
        }
        let angularVelocity: Float
        if angularMotionIsEnabled, actor.orientation == .free {
            angularVelocity = Self.deterministicValue(
                in: configuration.initialAngularSpeed,
                for: actor.id,
                salt: 0x94D0_49BB_1331_11EB
            ) * DayObjectLunarInteractionField.spinSign(for: actor.id)
        } else {
            angularVelocity = 0
        }
        return Body(
            position: actor.position,
            velocity: SIMD2(cos(velocityAngle), sin(velocityAngle)) * speed,
            angle: angle,
            angularVelocity: angularVelocity,
            halfSize: Self.sanitizedHalfSize(actor.halfSize),
            returnOrigin: actor.position,
            returnOriginAngle: angle,
            lastImpactAt: -.infinity,
            orientation: actor.orientation,
            collisionGeometry: actor.collisionGeometry
        )
    }

    private mutating func integrate(
        delta: TimeInterval,
        gravity: SIMD2<Float>,
        elapsed: TimeInterval
    ) -> [DayObjectWallImpact] {
        guard delta > 0 else { return [] }
        let stepCount = max(1, Int(ceil(delta / configuration.integrationStep)))
        let step = Float(delta / Double(stepCount))
        let damping = exp(-configuration.linearDrag * step)
        let angularDamping = exp(-configuration.angularDrag * step)
        var impacts = [DayObjectWallImpact]()

        let sortedIDs = bodies.keys.sorted()
        for _ in 0..<stepCount {
            for id in sortedIDs {
                guard var body = bodies[id] else { continue }
                body.velocity += gravity * configuration.acceleration * step
                body.velocity *= damping
                body.velocity = Self.clampedVelocity(
                    body.velocity,
                    maximum: configuration.maximumLinearSpeed
                )
                if angularMotionIsEnabled, body.orientation == .free {
                    body.angularVelocity *= angularDamping
                    body.angle += body.angularVelocity * step
                    body.angle.formTruncatingRemainder(dividingBy: 2 * .pi)
                }
                body.position += body.velocity * step
                resolveWalls(id: id, body: &body, elapsed: elapsed, impacts: &impacts)
                if angularMotionIsEnabled,
                   case let .followsVelocity(bodyAngleOffset) = body.orientation,
                   simd_length_squared(body.velocity) > 0.000_001 {
                    let targetAngle = atan2(body.velocity.y, body.velocity.x) + bodyAngleOffset
                    var angleDelta = Self.signedAngleDelta(from: body.angle, to: targetAngle)
                    if abs(abs(angleDelta) - .pi) < 0.001 {
                        let turnSign: Float = abs(body.angularVelocity) > 0.001
                            ? (body.angularVelocity < 0 ? -1 : 1)
                            : DayObjectLunarInteractionField.spinSign(for: id)
                        angleDelta = .pi * turnSign
                    }
                    let angularAcceleration = angleDelta * configuration.headingAlignmentStiffness
                        - body.angularVelocity * configuration.headingAlignmentDamping
                    body.angularVelocity = Self.clampedAngularVelocity(
                        body.angularVelocity + angularAcceleration * step,
                        maximum: configuration.maximumAngularSpeed
                    )
                    body.angle += body.angularVelocity * step
                    body.angle.formTruncatingRemainder(dividingBy: 2 * .pi)
                }
                bodies[id] = body
            }
        }
        return impacts
    }

    private func resolveWalls(
        id: DayObjectActorID,
        body: inout Body,
        elapsed: TimeInterval,
        impacts: inout [DayObjectWallImpact]
    ) {
        let extent: SIMD2<Float>
        switch body.collisionGeometry {
        case .box:
            extent = Self.rotatedExtent(halfSize: body.halfSize, angle: body.angle)
        case .radial:
            extent = SIMD2(repeating: max(body.halfSize.x, body.halfSize.y))
        }
        let available = simd_max(canvasHalfSpan - extent, .zero)
        let minX = -available.x
        let maxX = available.x
        let minY = -available.y
        let maxY = available.y

        if body.position.x < minX {
            let speed = abs(body.velocity.x)
            body.position.x = minX
            body.velocity.x = speed * configuration.restitution
            applyWallAngularFriction(
                .left, actorID: id, normalSpeed: speed, to: &body, extent: extent
            )
            recordImpact(.left, id: id, speed: speed, body: &body, elapsed: elapsed, impacts: &impacts)
        } else if body.position.x > maxX {
            let speed = abs(body.velocity.x)
            body.position.x = maxX
            body.velocity.x = -speed * configuration.restitution
            applyWallAngularFriction(
                .right, actorID: id, normalSpeed: speed, to: &body, extent: extent
            )
            recordImpact(.right, id: id, speed: speed, body: &body, elapsed: elapsed, impacts: &impacts)
        }

        if body.position.y < minY {
            let speed = abs(body.velocity.y)
            body.position.y = minY
            body.velocity.y = speed * configuration.restitution
            applyWallAngularFriction(
                .bottom, actorID: id, normalSpeed: speed, to: &body, extent: extent
            )
            recordImpact(.bottom, id: id, speed: speed, body: &body, elapsed: elapsed, impacts: &impacts)
        } else if body.position.y > maxY {
            let speed = abs(body.velocity.y)
            body.position.y = maxY
            body.velocity.y = -speed * configuration.restitution
            applyWallAngularFriction(
                .top, actorID: id, normalSpeed: speed, to: &body, extent: extent
            )
            recordImpact(.top, id: id, speed: speed, body: &body, elapsed: elapsed, impacts: &impacts)
        }
    }

    private func applyWallAngularFriction(
        _ wall: DayObjectCanvasWall,
        actorID: DayObjectActorID,
        normalSpeed: Float,
        to body: inout Body,
        extent: SIMD2<Float>
    ) {
        guard angularMotionIsEnabled, body.orientation == .free else { return }
        let tangentHalfSize: Float
        let normalImpulse: SIMD2<Float>
        let wallLever: SIMD2<Float>
        let tangent: SIMD2<Float>
        switch wall {
        case .left:
            tangentHalfSize = body.halfSize.y
            normalImpulse = SIMD2(normalSpeed * (1 + configuration.restitution), 0)
            wallLever = SIMD2(-extent.x, 0)
            tangent = SIMD2(0, body.velocity.y)
        case .right:
            tangentHalfSize = body.halfSize.y
            normalImpulse = SIMD2(-normalSpeed * (1 + configuration.restitution), 0)
            wallLever = SIMD2(extent.x, 0)
            tangent = SIMD2(0, body.velocity.y)
        case .bottom:
            tangentHalfSize = body.halfSize.x
            normalImpulse = SIMD2(0, normalSpeed * (1 + configuration.restitution))
            wallLever = SIMD2(0, -extent.y)
            tangent = SIMD2(body.velocity.x, 0)
        case .top:
            tangentHalfSize = body.halfSize.x
            normalImpulse = SIMD2(0, -normalSpeed * (1 + configuration.restitution))
            wallLever = SIMD2(0, extent.y)
            tangent = SIMD2(body.velocity.x, 0)
        }

        var torque: Float = 0
        if normalSpeed >= configuration.minimumImpactSpeed {
            var contactLever = wallLever
            let eccentricity = tangentHalfSize * 0.08
                * DayObjectLunarInteractionField.spinSign(for: actorID)
            if wall == .left || wall == .right {
                contactLever.y = eccentricity
            } else {
                contactLever.x = eccentricity
            }
            torque += contactLever.x * normalImpulse.y - contactLever.y * normalImpulse.x
        }

        let tangentSpeed = simd_length(tangent)
        if tangentSpeed > 0 {
            let frictionMagnitude = min(tangentSpeed, normalSpeed * (1 + configuration.restitution))
                * configuration.wallAngularFriction
            let frictionImpulse = -tangent / tangentSpeed * frictionMagnitude
            torque += wallLever.x * frictionImpulse.y - wallLever.y * frictionImpulse.x
        }
        body.angularVelocity = Self.clampedAngularVelocity(
            body.angularVelocity + torque / Self.momentOfInertia(for: body.halfSize),
            maximum: configuration.maximumAngularSpeed
        )
    }

    private func recordImpact(
        _ wall: DayObjectCanvasWall,
        id: DayObjectActorID,
        speed: Float,
        body: inout Body,
        elapsed: TimeInterval,
        impacts: inout [DayObjectWallImpact]
    ) {
        guard speed >= configuration.minimumImpactSpeed,
              elapsed - body.lastImpactAt >= configuration.impactCooldown else { return }
        body.lastImpactAt = elapsed
        impacts.append(.init(
            actorID: id,
            eventID: id.eventID,
            wall: wall,
            speed: speed,
            normalizedX: min(max(
                (body.position.x + canvasHalfSpan.x) / max(canvasHalfSpan.x * 2, 0.001),
                0
            ), 1)
        ))
    }

    private static func sanitizedGravity(_ gravity: SIMD2<Float>) -> SIMD2<Float> {
        guard gravity.x.isFinite, gravity.y.isFinite else { return .zero }
        let magnitude = simd_length(gravity)
        guard magnitude > 0.045 else { return .zero }
        return magnitude > 1 ? gravity / magnitude : gravity
    }

    private static func sanitizedHalfSize(_ halfSize: SIMD2<Float>) -> SIMD2<Float> {
        SIMD2(
            min(max(halfSize.x.isFinite ? halfSize.x : 0, 0.01), 0.95),
            min(max(halfSize.y.isFinite ? halfSize.y : 0, 0.01), 0.95)
        )
    }

    private static func sanitizedCanvasHalfSpan(_ span: SIMD2<Float>) -> SIMD2<Float> {
        SIMD2(
            span.x.isFinite ? max(span.x, 0.05) : 1,
            span.y.isFinite ? max(span.y, 0.05) : 1
        )
    }

    private static func angle(for direction: SIMD2<Float>) -> Float {
        guard direction.x.isFinite, direction.y.isFinite,
              simd_length_squared(direction) > 0.000_001 else { return 0 }
        return atan2(direction.y, direction.x)
    }

    private static func momentOfInertia(for halfSize: SIMD2<Float>) -> Float {
        max((halfSize.x * halfSize.x + halfSize.y * halfSize.y) / 3, 0.0025)
    }

    private static func clampedAngularVelocity(_ value: Float, maximum: Float) -> Float {
        guard value.isFinite else { return 0 }
        let limit = max(maximum, 0)
        return min(max(value, -limit), limit)
    }

    private static func clampedVelocity(
        _ value: SIMD2<Float>,
        maximum: Float
    ) -> SIMD2<Float> {
        guard value.x.isFinite, value.y.isFinite else { return .zero }
        let magnitude = simd_length(value)
        let limit = max(maximum, 0)
        guard magnitude > limit, magnitude > 0 else { return value }
        return value / magnitude * limit
    }

    private static func deterministicValue(
        in range: ClosedRange<Float>,
        for actorID: DayObjectActorID,
        salt: UInt64
    ) -> Float {
        let lower = min(range.lowerBound, range.upperBound)
        let upper = max(range.lowerBound, range.upperBound)
        var hash = 1_469_598_103_934_665_603 ^ salt
        for byte in actorID.eventID.utf8 {
            hash ^= UInt64(byte)
            hash &*= 1_099_511_628_211
        }
        hash ^= UInt64(bitPattern: Int64(actorID.memberIndex))
        hash ^= hash >> 30
        hash &*= 0xBF58_476D_1CE4_E5B9
        hash ^= hash >> 27
        hash &*= 0x94D0_49BB_1331_11EB
        hash ^= hash >> 31
        let unit = Float(hash >> 40) / Float(1 << 24)
        return lower + (upper - lower) * unit
    }

    private static func rotatedExtent(
        halfSize: SIMD2<Float>,
        angle: Float
    ) -> SIMD2<Float> {
        let cosine = abs(cos(angle))
        let sine = abs(sin(angle))
        return SIMD2(
            cosine * halfSize.x + sine * halfSize.y,
            sine * halfSize.x + cosine * halfSize.y
        )
    }

    private static func interpolateAngle(
        from start: Float,
        to end: Float,
        progress: Float
    ) -> Float {
        start + signedAngleDelta(from: start, to: end) * progress
    }

    private static func signedAngleDelta(from start: Float, to end: Float) -> Float {
        let fullTurn = 2 * Float.pi
        var delta = (end - start).truncatingRemainder(dividingBy: fullTurn)
        if delta > .pi { delta -= fullTurn }
        if delta < -.pi { delta += fullTurn }
        return delta
    }
}

struct DayObjectsSoundPulseEvent: Equatable, Sendable {
    let sequence: UInt64
    let eventID: String
}

final class DayObjectsSoundPulseBus: @unchecked Sendable {
    private static let capacity = 32
    private let lock = NSLock()
    private var sequence: UInt64 = 0
    private var bufferedEvents = [DayObjectsSoundPulseEvent]()

    func emit(eventID: String) {
        lock.lock()
        defer { lock.unlock() }
        sequence &+= 1
        bufferedEvents.append(.init(sequence: sequence, eventID: eventID))
        if bufferedEvents.count > Self.capacity {
            bufferedEvents.removeFirst(bufferedEvents.count - Self.capacity)
        }
    }

    func events(after consumedSequence: UInt64) -> [DayObjectsSoundPulseEvent] {
        lock.lock()
        defer { lock.unlock() }
        return bufferedEvents.filter { $0.sequence > consumedSequence }
    }

    var latestSequence: UInt64 {
        lock.lock()
        defer { lock.unlock() }
        return sequence
    }
}

struct DayObjectsSoundPulseTimeline {
    private(set) var lastConsumedSequence: UInt64 = 0
    private(set) var timestamps: [String: Double] = [:]

    init(startingAfter bus: DayObjectsSoundPulseBus? = nil) {
        lastConsumedSequence = bus?.latestSequence ?? 0
    }

    mutating func consume(_ bus: DayObjectsSoundPulseBus?, at elapsed: Double) {
        if let bus {
            for event in bus.events(after: lastConsumedSequence) {
                timestamps[event.eventID] = elapsed
                lastConsumedSequence = max(lastConsumedSequence, event.sequence)
            }
        }

        timestamps = timestamps.filter { _, startedAt in
            elapsed - startedAt < DayObjectSoundResonance.duration
        }
    }
}

enum DayObjectSoundResonance {
    static let duration = 0.75

    static func scale(elapsedSinceAttack rawElapsed: Double, depth rawDepth: Double) -> Double {
        guard rawElapsed.isFinite, rawDepth.isFinite,
              rawElapsed >= 0, rawElapsed < duration else { return 1 }
        let depth = min(max(rawDepth, 0), 1)
        let attackProgress = min(rawElapsed / 0.05, 1)
        let attack = attackProgress * attackProgress * (3 - 2 * attackProgress)
        let decay = exp(-4 * rawElapsed)
        let amplitude = 0.042 - 0.016 * depth
        let oscillation = sin(2 * .pi * 5 * rawElapsed)
        return 1 + amplitude * attack * decay * oscillation
    }
}

struct DayObjectEnvironment: Equatable {
    let motionEnergy: Double
    let visualClarity: Double

    init(motionEnergy: Double, visualClarity: Double) {
        self.motionEnergy = Self.clampedUnit(motionEnergy)
        self.visualClarity = Self.clampedUnit(visualClarity)
    }

    var tempoScale: Double {
        let progress = motionEnergy * motionEnergy * (3 - 2 * motionEnergy)
        return 0.035 + (1.25 - 0.035) * progress
    }

    private static func clampedUnit(_ value: Double) -> Double {
        guard value.isFinite else { return 0 }
        return min(max(value, 0), 1)
    }
}

struct DayObjectInsertionState: Equatable {
    let startedAt: Double
    let duration: Double

    init(startedAt rawStartedAt: Double, duration rawDuration: Double) {
        startedAt = rawStartedAt.isFinite ? rawStartedAt : 0
        duration = min(max(rawDuration.isFinite ? rawDuration : 0.8, 0.8), 1.4)
    }

    func envelope(at rawElapsed: Double) -> DayObjectInsertionEnvelope {
        let elapsed = rawElapsed.isFinite ? rawElapsed : 0
        let progress = min(max((elapsed - startedAt) / duration, 0), 1)
        let eased = progress * progress * (3 - 2 * progress)
        return DayObjectInsertionEnvelope(
            opacity: eased,
            scale: 0.7 + 0.3 * eased
        )
    }
}

struct DayObjectInsertionEnvelope: Equatable {
    let opacity: Double
    let scale: Double
}

struct DayObjectPostProcess: Equatable {
    let blurRadius: Double
    let contrast: Double
    let saturation: Double
    let grainIntensity: Double
    let grainPhase: Double

    init(visualClarity rawVisualClarity: Double, grainSeed _: UInt64, elapsed rawElapsed: Double = 0) {
        let visualClarity = Self.clampedUnit(rawVisualClarity)
        blurRadius = pow(1 - visualClarity, 1.4) * 18
        contrast = 0.84 + 0.16 * visualClarity
        saturation = 0.88 + 0.12 * visualClarity
        grainIntensity = 0.05

        let elapsed = rawElapsed.isFinite ? max(rawElapsed, 0) : 0
        // Drift the final monochrome grain by roughly one pixel per second.
        grainPhase = elapsed * 0.06
    }

    private static func clampedUnit(_ value: Double) -> Double {
        guard value.isFinite else { return 0 }
        return min(max(value, 0), 1)
    }

}

/// Compact per-frame pose data. Stable material parameters live in the
/// one-to-one `DayObjectGPUAppearance` buffer.
@_alignment(16)
struct DayObjectGPUActor: Equatable {
    static let metalAlignment = 16
    static let metalStride = 80

    let position: SIMD2<Float>       // bytes 0...7
    let direction: SIMD2<Float>      // bytes 8...15
    let halfSize: SIMD2<Float>       // bytes 16...23
    private let quadPadding: SIMD2<Float> // bytes 24...31
    let opacity: Float               // bytes 32...35
    let trailLength: Float           // bytes 36...39
    let shape: UInt32                // bytes 40...43
    let appearanceIndex: UInt32      // bytes 44...47
    let depth: Float                 // bytes 48...51
    let materialPhase: Float         // bytes 52...55
    let localDepthSoftness: Float    // bytes 56...59
    let silhouetteVariant: UInt32   // bytes 60...63; zero keeps curated legacy contours
    let paletteMorph: Float          // bytes 64...67
    let presentationSaturation: Float // bytes 68...71
    let removalEmphasis: Float       // bytes 72...75
    private let presentationPadding: Float // bytes 76...79

    init(
        position: SIMD2<Float>,
        direction: SIMD2<Float>,
        halfSize: SIMD2<Float>,
        opacity: Float,
        trailLength: Float,
        shape: UInt32,
        appearanceIndex: UInt32,
        depth: Float,
        materialPhase: Float,
        localDepthSoftness: Float,
        paletteMorph: Float = 1,
        presentationSaturation: Float = 1,
        removalEmphasis: Float = 0,
        silhouetteVariant: UInt32 = 0
    ) {
        self.position = Self.finite(position)
        self.direction = Self.normalized(direction)
        self.halfSize = Self.nonnegativeFinite(halfSize)
        quadPadding = .zero
        self.opacity = Self.clampedUnit(opacity)
        self.trailLength = max(0, trailLength.isFinite ? trailLength : 0)
        self.shape = min(shape, UInt32(DayObjectShape.allCases.count - 1))
        self.appearanceIndex = appearanceIndex
        self.depth = Self.clampedUnit(depth)
        self.materialPhase = Self.normalizedPhase(materialPhase)
        self.localDepthSoftness = min(
            max(localDepthSoftness.isFinite ? localDepthSoftness : 0, 0),
            1
        )
        self.silhouetteVariant = min(silhouetteVariant, 64)
        self.paletteMorph = Self.clampedUnit(paletteMorph)
        self.presentationSaturation = Self.clampedUnit(presentationSaturation)
        self.removalEmphasis = Self.clampedUnit(removalEmphasis)
        presentationPadding = 0
    }

    /// Compatibility initializer for focused legacy mask tests while their
    /// shared-radial fixtures are replaced by material fixtures in Task 8.
    init(
        position: SIMD2<Float>,
        direction: SIMD2<Float>,
        halfSize: SIMD2<Float>,
        color _: SIMD4<Float>,
        opacity: Float,
        trailLength: Float,
        shape: UInt32,
        fill _: UInt32,
        depth: Float,
        radialVariation: Float = 0
    ) {
        self.init(
            position: position,
            direction: direction,
            halfSize: halfSize,
            opacity: opacity,
            trailLength: trailLength,
            shape: shape,
            appearanceIndex: 0,
            depth: depth,
            materialPhase: (radialVariation + 1) * 0.5,
            localDepthSoftness: 0
        )
    }

    var color: SIMD4<Float> { SIMD4(repeating: 1) }
    var fill: UInt32 { 2 }
    var radialVariation: Float { materialPhase * 2 - 1 }

    func withAppearanceIndex(_ index: UInt32) -> DayObjectGPUActor {
        DayObjectGPUActor(
            position: position,
            direction: direction,
            halfSize: halfSize,
            opacity: opacity,
            trailLength: trailLength,
            shape: shape,
            appearanceIndex: index,
            depth: depth,
            materialPhase: materialPhase,
            localDepthSoftness: localDepthSoftness,
            paletteMorph: paletteMorph,
            presentationSaturation: presentationSaturation,
            removalEmphasis: removalEmphasis,
            silhouetteVariant: silhouetteVariant
        )
    }

    private static func finite(_ value: SIMD2<Float>) -> SIMD2<Float> {
        SIMD2(value.x.isFinite ? value.x : 0, value.y.isFinite ? value.y : 0)
    }

    private static func nonnegativeFinite(_ value: SIMD2<Float>) -> SIMD2<Float> {
        SIMD2(
            value.x.isFinite ? max(value.x, 0) : 0,
            value.y.isFinite ? max(value.y, 0) : 0
        )
    }

    private static func normalized(_ value: SIMD2<Float>) -> SIMD2<Float> {
        let finite = Self.finite(value)
        let length = simd_length(finite)
        return length > 0.000_001 ? finite / length : SIMD2(1, 0)
    }

    private static func clampedUnit(_ value: Float) -> Float {
        value.isFinite ? min(max(value, 0), 1) : 0
    }

    private static func normalizedPhase(_ value: Float) -> Float {
        guard value.isFinite else { return 0 }
        let remainder = value.truncatingRemainder(dividingBy: 1)
        return remainder >= 0 ? remainder : remainder + 1
    }
}

/// Stable material data uploaded once per rendered actor record.
struct DayObjectGPUAppearance: Equatable {
    static let metalAlignment = 16
    static let metalStride = 208

    let color0: SIMD4<Float>
    let color1: SIMD4<Float>
    let color2: SIMD4<Float>
    let radial0: SIMD4<Float>
    let radial1: SIMD4<Float>
    let radial2: SIMD4<Float>
    let field: SIMD4<Float>
    let optical0: SIMD4<Float>
    let optical1: SIMD4<Float>
    let light: SIMD4<Float>
    let recipe0: SIMD4<Float>
    let recipe1: SIMD4<Float>
    let metadata: SIMD4<UInt32>

    // Source compatibility for older focused tests. This is computed and does
    // not participate in the Metal ABI.
    var membrane: SIMD4<Float> { .zero }

    /// The fragment blur keeps its focused edge opposite the shader's blur
    /// axis. This offset lets physics point that focused edge along velocity.
    func fragmentBlurBodyAngleOffset(
        shape: UInt32,
        silhouetteVariant: UInt32
    ) -> Float? {
        guard (metadata.x == DayObjectMaterialFamily.gradient.rawValue
                || metadata.x == DayObjectMaterialFamily.glass.rawValue),
              UInt32(recipe1.x.rounded()) == 4 else { return nil }
        var blurAngle = recipe1.y
        if shape == 6 || (shape == 5 && silhouetteVariant > 0) {
            let sides: Float = shape == 6
                ? 4
                : 3 + Float((min(silhouetteVariant, 64) - 1) % 4)
            let sector = 2 * Float.pi / sides
            let focusOffset = sides == 3 ? sector * 0.5 : 0
            let focusNormal = ((Float.pi - blurAngle - focusOffset) / sector).rounded()
                * sector + focusOffset
            blurAngle = .pi - focusNormal
        }
        var offset = (blurAngle - .pi).truncatingRemainder(dividingBy: 2 * .pi)
        if offset > .pi { offset -= 2 * .pi }
        if offset < -.pi { offset += 2 * .pi }
        return offset
    }

    static let fallback = DayObjectGPUAppearance(
        color0: SIMD4(1, 1, 1, 1),
        color1: SIMD4(1, 1, 1, 1),
        color2: SIMD4(1, 1, 1, 1),
        radial0: SIMD4(0, 0, 1, 0.36),
        radial1: SIMD4(0.24, -0.16, 0.68, 0.42),
        radial2: SIMD4(0, 0, 0.42, 0.72),
        field: SIMD4(0, 1, 0, 0),
        optical0: SIMD4(0, 0, 1, 1),
        optical1: SIMD4(0.1, 0, 0, 0),
        light: SIMD4(0.7, 1, 0.42, 0),
        metadata: SIMD4(DayObjectMaterialFamily.gradient.rawValue, 1, 2, 0),
        recipe0: SIMD4(0.34, 0.68, 0.04, 0.72),
        recipe1: .zero
    )

    init(
        appearance: DayObjectAppearance,
        materialRawValue: UInt32? = nil
    ) {
        var colors = appearance.colorAssignment.colors.prefix(3).map {
            SIMD4(Self.clamped($0.linearRGB), 1)
        }
        let colorCount = colors.count
        let fallbackColor = colors.last ?? SIMD4<Float>(1, 1, 1, 1)
        while colors.count < 3 { colors.append(fallbackColor) }
        let paddedLayers = Array(appearance.layers.prefix(3))
        func radialDescriptor(at index: Int) -> SIMD4<Float> {
            guard paddedLayers.indices.contains(index) else {
                return SIMD4(0, 0, 0.42, 0.72)
            }
            let layer = paddedLayers[index]
            return SIMD4(
                Float(layer.focalOffset.x), Float(layer.focalOffset.y),
                Float(layer.radius), Float(layer.softness)
            )
        }
        let layerOpacities = (0..<3).map { index -> Float in
            paddedLayers.indices.contains(index) ? Float(paddedLayers[index].opacity) : 0
        }
        let optical0 = SIMD4(
            Float(appearance.innerGlow), Float(appearance.outerGlow),
            Float(appearance.bodyOpacity), Float(appearance.centerOpacity)
        )
        let optical1 = SIMD4(
            Float(appearance.rimOpacity), Float(appearance.refractionStrength),
            Float(appearance.refractionAngle), Float(appearance.localDepthSoftness)
        )
        let field = SIMD4(
            Float(appearance.distortion), Float(appearance.distortionFrequency),
            Float(appearance.distortionPhase), Float(appearance.edgeSoftness)
        )
        let light = SIMD4(
            Float(appearance.lightResponse),
            layerOpacities[0], layerOpacities[1], layerOpacities[2]
        )
        let requestedMaterial = materialRawValue ?? appearance.material.rawValue
        let material = DayObjectMaterialFamily(rawValue: requestedMaterial) ?? .gradient
        let recipe1: SIMD4<Float>
        switch material {
        case .outline:
            recipe1 = SIMD4(
                Float(appearance.outlineCount), Float(appearance.outlineWidth),
                Float(appearance.outlineSpacing), Float(appearance.outlineWobble)
            )
        case .counterform:
            recipe1 = SIMD4(
                Float(appearance.counterformRadius), Float(appearance.counterformSoftness),
                Float(appearance.coronaWidth), Float(appearance.coronaIntensity)
            )
        default:
            recipe1 = .zero
        }
        self.init(
            color0: colors[0], color1: colors[1], color2: colors[2],
            radial0: radialDescriptor(at: 0),
            radial1: radialDescriptor(at: 1),
            radial2: radialDescriptor(at: 2),
            field: field,
            optical0: optical0, optical1: optical1,
            light: light,
            metadata: SIMD4(
                material.rawValue,
                UInt32(min(max(colorCount, 1), 3)),
                UInt32(min(max(paddedLayers.count, 1), 3)),
                appearance.mutationRole.rawValue
            ),
            recipe0: SIMD4(
                Float(appearance.colorStopLocations.x),
                Float(appearance.colorStopLocations.y),
                Float(appearance.edgeSoftness),
                Float(appearance.minimumOpacity)
            ),
            recipe1: recipe1
        )
    }

    init(
        color0: SIMD4<Float>, color1: SIMD4<Float>, color2: SIMD4<Float>,
        radial0: SIMD4<Float>, radial1: SIMD4<Float>, radial2: SIMD4<Float>,
        field: SIMD4<Float>, optical0: SIMD4<Float>, optical1: SIMD4<Float>,
        light: SIMD4<Float>,
        metadata: SIMD4<UInt32>,
        recipe0: SIMD4<Float> = SIMD4(0.34, 0.68, 0.04, 0.72),
        recipe1: SIMD4<Float> = .zero
    ) {
        self.color0 = Self.clampedColor(color0)
        self.color1 = Self.clampedColor(color1)
        self.color2 = Self.clampedColor(color2)
        self.radial0 = Self.radialDescriptor(radial0)
        self.radial1 = Self.radialDescriptor(radial1)
        self.radial2 = Self.radialDescriptor(radial2)
        self.field = SIMD4(
            Self.bounded(field.x, 0...0.18),
            Self.bounded(field.y, 0.8...4),
            Self.bounded(field.z, -2 * .pi...2 * .pi),
            Self.bounded(field.w, 0...1)
        )
        self.optical0 = Self.clampedColor(optical0)
        self.optical1 = SIMD4(
            Self.bounded(optical1.x, 0...1),
            Self.bounded(optical1.y, 0...0.08),
            Self.bounded(optical1.z, -2 * .pi...2 * .pi),
            Self.bounded(optical1.w, 0...1)
        )
        self.light = SIMD4(
            Self.bounded(light.x, 0...1),
            Self.bounded(light.y, 0...1),
            Self.bounded(light.z, 0...1),
            Self.bounded(light.w, 0...1)
        )
        self.recipe0 = SIMD4(
            Self.bounded(recipe0.x, 0.18...0.72),
            Self.bounded(recipe0.y, 0.42...0.90),
            Self.bounded(recipe0.z, 0...0.42),
            Self.bounded(recipe0.w, 0.58...0.92)
        )
        let material = DayObjectMaterialFamily(rawValue: metadata.x) ?? .gradient
        switch material {
        case .outline:
            self.recipe1 = SIMD4(
                Float(min(max(Int(recipe1.x.rounded()), 1), 3)),
                Self.bounded(recipe1.y, 0.012...0.075),
                Self.bounded(recipe1.z, 0.02...0.09),
                Self.bounded(recipe1.w, 0.01...0.08)
            )
        case .counterform:
            self.recipe1 = SIMD4(
                Self.bounded(recipe1.x, 0.44...0.62),
                Self.bounded(recipe1.y, 0.01...0.08),
                Self.bounded(recipe1.z, 0.14...0.34),
                Self.bounded(recipe1.w, 0.58...0.98)
            )
        case .gradient, .glass:
            self.recipe1 = SIMD4(
                Float(min(max(Int(Self.bounded(recipe1.x, 0...5).rounded()), 0), 5)),
                Self.bounded(recipe1.y, -2 * .pi...2 * .pi),
                Self.bounded(recipe1.z, 0...1),
                Self.bounded(recipe1.w, 0...1)
            )
        default:
            self.recipe1 = .zero
        }
        self.metadata = SIMD4(
            material.rawValue,
            min(max(metadata.y, 1), 3),
            min(max(metadata.z, 1), 3),
            min(metadata.w, UInt32(DayObjectMutationRole.allCases.count - 1))
        )
    }

    /// Compatibility initializer for the previous two-vector radial ABI.
    init(
        color0: SIMD4<Float>, color1: SIMD4<Float>, color2: SIMD4<Float>,
        radial0 legacyRadial: SIMD4<Float>, radial1 legacyField: SIMD4<Float>,
        optical0: SIMD4<Float>, optical1: SIMD4<Float>, membrane: SIMD4<Float>,
        light: SIMD4<Float>, metadata: SIMD4<UInt32>
    ) {
        let distance = Self.bounded(legacyRadial.x, 0...0.68)
        let angle = Self.bounded(legacyRadial.y, -2 * .pi...2 * .pi)
        let focus = SIMD2<Float>(cos(angle), sin(angle)) * distance
        let radius = Self.bounded(legacyRadial.z, 0.42...1.18)
        let softness = Self.bounded(legacyRadial.w + 0.24, 0.12...0.72)
        let secondFocus = focus + SIMD2(membrane.x, membrane.y)
        self.init(
            color0: color0,
            color1: color1,
            color2: color2,
            radial0: SIMD4(focus.x, focus.y, radius, softness),
            radial1: SIMD4(
                secondFocus.x, secondFocus.y,
                max(radius * 0.72, 0.42), min(softness + 0.10, 0.72)
            ),
            radial2: SIMD4(-focus.x * 0.55, -focus.y * 0.55, 0.52, 0.48),
            field: SIMD4(
                legacyField.y, legacyField.w, legacyField.z * .pi,
                optical1.w
            ),
            optical0: optical0,
            optical1: optical1,
            light: SIMD4(light.x, legacyField.x, legacyField.x * 0.65, 0.32),
            metadata: metadata
        )
    }

    private static func radialDescriptor(_ value: SIMD4<Float>) -> SIMD4<Float> {
        let finiteFocus = SIMD2(
            value.x.isFinite ? value.x : 0,
            value.y.isFinite ? value.y : 0
        )
        let focusLength = simd_length(finiteFocus)
        let focus = focusLength > 0.68 ? finiteFocus / focusLength * 0.68 : finiteFocus
        return SIMD4(
            focus.x, focus.y,
            bounded(value.z, 0.42...1.80),
            bounded(value.w, 0.12...1.0)
        )
    }

    private static func finite(_ value: SIMD4<Float>) -> SIMD4<Float> {
        SIMD4(
            value.x.isFinite ? value.x : 0,
            value.y.isFinite ? value.y : 0,
            value.z.isFinite ? value.z : 0,
            value.w.isFinite ? value.w : 0
        )
    }

    private static func clampedColor(_ value: SIMD4<Float>) -> SIMD4<Float> {
        SIMD4(
            bounded(value.x, 0...1), bounded(value.y, 0...1),
            bounded(value.z, 0...1), bounded(value.w, 0...1)
        )
    }

    private static func bounded(_ value: Float, _ range: ClosedRange<Float>) -> Float {
        guard value.isFinite else { return min(max(0, range.lowerBound), range.upperBound) }
        return min(max(value, range.lowerBound), range.upperBound)
    }

    private static func clamped(_ value: SIMD3<Float>) -> SIMD3<Float> {
        SIMD3(
            value.x.isFinite ? min(max(value.x, 0), 1) : 0,
            value.y.isFinite ? min(max(value.y, 0), 1) : 0,
            value.z.isFinite ? min(max(value.z, 0), 1) : 0
        )
    }
}

struct DayObjectRenderActor: Equatable {
    let actorID: DayObjectActorID
    let eventID: String
    let gpuActor: DayObjectGPUActor
    let gpuAppearance: DayObjectGPUAppearance

    init(
        actorID: DayObjectActorID,
        eventID: String,
        gpuActor: DayObjectGPUActor,
        gpuAppearance: DayObjectGPUAppearance = .fallback
    ) {
        self.actorID = actorID
        self.eventID = eventID
        self.gpuActor = gpuActor
        self.gpuAppearance = gpuAppearance
    }

    var halfSize: SIMD2<Float> { gpuActor.halfSize }
    var opacity: Float { gpuActor.opacity }
    var trailLength: Float { gpuActor.trailLength }
    var depth: Float { gpuActor.depth }
}

struct DayObjectRenderFrame: Equatable {
    static let baseTempo = 0.8

    let choreographyTime: Double
    let actors: [DayObjectRenderActor]
    let postProcess: DayObjectPostProcess

    static func make(
        scene: DayObjectScene,
        environment: DayObjectEnvironment,
        elapsed rawElapsed: Double,
        insertions: [String: Double],
        removals: [String: Double] = [:],
        actorInsertions: [DayObjectActorID: Double] = [:],
        actorRemovals: [DayObjectActorID: Double] = [:],
        canvasAspect rawCanvasAspect: Double = 1,
        soundPulseTimestamps: [String: Double] = [:]
    ) -> DayObjectRenderFrame {
        let elapsed = rawElapsed.isFinite ? max(rawElapsed, 0) : 0
        let canvasAspect = rawCanvasAspect.isFinite && rawCanvasAspect > 0 ? rawCanvasAspect : 1
        if let recipe = scene.sceneRecipeV1 {
            return makeEditorial(
                scene: scene,
                recipe: recipe,
                environment: environment,
                elapsed: elapsed,
                insertions: insertions,
                removals: removals,
                actorInsertions: actorInsertions,
                actorRemovals: actorRemovals,
                canvasAspect: canvasAspect,
                soundPulseTimestamps: soundPulseTimestamps
            )
        }
        let choreographyTime = elapsed * baseTempo * environment.tempoScale
        let postProcess = DayObjectPostProcess(
            visualClarity: environment.visualClarity,
            grainSeed: scene.rootSeed,
            elapsed: elapsed
        )
        var actors = [DayObjectRenderActor]()
        actors.reserveCapacity(scene.actors.count)
        for actor in scene.actors {
            let pose = scene.score.pose(
                for: actor,
                at: choreographyTime,
                canvasAspect: canvasAspect,
                compositionPlan: scene.compositionPlan
            )
            let insertion: DayObjectInsertionEnvelope
            if let startedAt = actorInsertions[actor.id] ?? insertions[actor.eventID] {
                insertion = DayObjectInsertionState(
                    startedAt: startedAt,
                    duration: transitionDuration(for: actor)
                ).envelope(at: elapsed)
            } else {
                insertion = DayObjectInsertionEnvelope(opacity: 1, scale: 1)
            }
            let removal: DayObjectInsertionEnvelope
            if let startedAt = actorRemovals[actor.id] ?? removals[actor.eventID] {
                let forward = DayObjectInsertionState(
                    startedAt: startedAt,
                    duration: transitionDuration(for: actor)
                ).envelope(at: elapsed)
                removal = DayObjectInsertionEnvelope(
                    opacity: 1 - forward.opacity,
                    scale: 1 - 0.3 * forward.opacity
                )
            } else {
                removal = DayObjectInsertionEnvelope(opacity: 1, scale: 1)
            }
            let resonanceScale = soundResonanceScale(
                eventID: actor.eventID,
                depth: pose.depth,
                elapsed: elapsed,
                timestamps: soundPulseTimestamps
            )
            let envelopeScale = insertion.scale * removal.scale * resonanceScale
            let halfSize = bodyHalfSize(
                for: actor,
                pose: pose,
                leadership: 0,
                envelopeScale: envelopeScale
            )
            let depth = Float(pose.depth)
            let position = SIMD2<Float>(Float(pose.position.x), Float(pose.position.y))
            let direction = SIMD2<Float>(Float(pose.tangent.x), Float(pose.tangent.y))
            let gpuActor = DayObjectGPUActor(
                position: position,
                direction: direction,
                halfSize: halfSize,
                opacity: Float(pose.opacity * insertion.opacity * removal.opacity),
                trailLength: Float(pose.trailReach),
                shape: numericShape(actor.appearance.shape),
                appearanceIndex: 0,
                depth: depth,
                materialPhase: Float(pose.materialPhase),
                localDepthSoftness: Float(pose.localDepthSoftness)
            )
            actors.append(DayObjectRenderActor(
                actorID: actor.id,
                eventID: actor.eventID,
                gpuActor: gpuActor,
                gpuAppearance: DayObjectGPUAppearance(appearance: actor.appearance)
            ))
        }
        actors.sort { lhs, rhs in
            lhs.depth == rhs.depth ? lhs.actorID < rhs.actorID : lhs.depth < rhs.depth
        }
        actors = actors.enumerated().map { index, actor in
            DayObjectRenderActor(
                actorID: actor.actorID,
                eventID: actor.eventID,
                gpuActor: actor.gpuActor.withAppearanceIndex(UInt32(index)),
                gpuAppearance: actor.gpuAppearance
            )
        }

        return DayObjectRenderFrame(
            choreographyTime: choreographyTime,
            actors: actors,
            postProcess: postProcess
        )
    }

    private static func makeEditorial(
        scene: DayObjectScene,
        recipe: DayObjectSceneRecipeV1,
        environment: DayObjectEnvironment,
        elapsed: Double,
        insertions: [String: Double],
        removals: [String: Double],
        actorInsertions: [DayObjectActorID: Double],
        actorRemovals: [DayObjectActorID: Double],
        canvasAspect: Double,
        soundPulseTimestamps: [String: Double]
    ) -> DayObjectRenderFrame {
        let span = canvasAspect >= 1
            ? SIMD2<Double>(canvasAspect, 1)
            : SIMD2<Double>(1, 1 / canvasAspect)
        let actorByEventID = Dictionary(uniqueKeysWithValues: scene.actors.map { ($0.eventID, $0) })
        var rendered = [DayObjectRenderActor]()
        rendered.reserveCapacity(recipe.actors.count)

        for recipeActor in recipe.actors {
            guard let actor = actorByEventID[recipeActor.eventID] else { continue }
            let pose = recipeActor.motion.pose(
                elapsedTime: elapsed,
                energy: environment.motionEnergy
            )
            let insertion = editorialEnvelope(
                kind: .insertion,
                startedAt: actorInsertions[actor.id] ?? insertions[actor.eventID],
                elapsed: elapsed
            )
            let removal = editorialEnvelope(
                kind: .removal,
                startedAt: actorRemovals[actor.id] ?? removals[actor.eventID],
                elapsed: elapsed
            )
            let normalized = SIMD2(
                recipeActor.position.x + pose.positionOffset.x,
                recipeActor.position.y + pose.positionOffset.y
            )
            let position = SIMD2<Float>(
                Float((normalized.x - 0.5) * span.x),
                Float((normalized.y - 0.5) * span.y)
            )
            let motionLength = simd_length(pose.positionOffset)
            let direction = motionLength > 0.000_001
                ? SIMD2<Float>(Float(pose.positionOffset.x), Float(pose.positionOffset.y))
                : SIMD2<Float>(Float(cos(recipeActor.motion.directionBias)), Float(sin(recipeActor.motion.directionBias)))
            let transitionScale = insertion.scale * removal.scale
            let effectiveDepth = min(max(recipeActor.depth + pose.depthOffset, 0), 1)
            let resonanceScale = soundResonanceScale(
                eventID: actor.eventID,
                depth: effectiveDepth,
                elapsed: elapsed,
                timestamps: soundPulseTimestamps
            )
            let halfDiameter = Float(
                recipeActor.diameter * pose.scale * transitionScale * resonanceScale * 0.5
            )
            let foregroundSoftness = recipeActor.diameter > 0.4 && effectiveDepth > 0.65 ? 0.18 : 0
            let localSoftness = min(
                1,
                recipeActor.localBlur * 10 + effectiveDepth * 0.20 + foregroundSoftness
            )
            let silhouette = recipeActor.silhouette
            let silhouetteDirection = silhouette.variant == 0 ? direction
                : SIMD2<Float>(cos(silhouette.rotation), sin(silhouette.rotation))
            let gpuActor = DayObjectGPUActor(
                position: position,
                direction: silhouetteDirection,
                halfSize: SIMD2(halfDiameter, halfDiameter * silhouette.aspect),
                opacity: Float(insertion.opacity * removal.opacity),
                trailLength: 0,
                shape: recipeActor.shape.numericValue,
                appearanceIndex: 0,
                depth: Float(effectiveDepth),
                materialPhase: 0,
                localDepthSoftness: Float(localSoftness),
                silhouetteVariant: silhouette.variant
            )
            rendered.append(DayObjectRenderActor(
                actorID: actor.id,
                eventID: actor.eventID,
                gpuActor: gpuActor,
                gpuAppearance: recipeActor.material.gpuAppearance
            ))
        }

        rendered.sort { lhs, rhs in
            lhs.depth == rhs.depth ? lhs.actorID < rhs.actorID : lhs.depth < rhs.depth
        }
        rendered = rendered.enumerated().map { index, actor in
            DayObjectRenderActor(
                actorID: actor.actorID,
                eventID: actor.eventID,
                gpuActor: actor.gpuActor.withAppearanceIndex(UInt32(index)),
                gpuAppearance: actor.gpuAppearance
            )
        }
        let clarity = recipe.lowSleep ? min(environment.visualClarity, 0.42) : environment.visualClarity
        return DayObjectRenderFrame(
            choreographyTime: elapsed,
            actors: rendered,
            postProcess: DayObjectPostProcess(
                visualClarity: clarity,
                grainSeed: scene.rootSeed,
                elapsed: elapsed
            )
        )
    }

    private enum EditorialTransitionKind {
        case insertion
        case removal
    }

    private static func soundResonanceScale(
        eventID: String,
        depth: Double,
        elapsed: Double,
        timestamps: [String: Double]
    ) -> Double {
        guard let startedAt = timestamps[eventID] else { return 1 }
        return DayObjectSoundResonance.scale(
            elapsedSinceAttack: elapsed - startedAt,
            depth: depth
        )
    }

    private static func editorialEnvelope(
        kind: EditorialTransitionKind,
        startedAt: Double?,
        elapsed: Double
    ) -> DayObjectInsertionEnvelope {
        guard let startedAt else { return .init(opacity: 1, scale: 1) }
        let progress = min(max((elapsed - startedAt) / 1.1, 0), 1)
        let eased = progress * progress * progress * (progress * (progress * 6 - 15) + 10)
        switch kind {
        case .insertion:
            return .init(opacity: eased, scale: 0.96 + 0.04 * eased)
        case .removal:
            return .init(opacity: 1 - eased, scale: 1 - 0.04 * eased)
        }
    }

    static func transitionDuration(for actor: DayObjectActor) -> Double {
        0.8 + 0.6 * stableUnit(actor.seed, salt: 0xC6BC_2796_92B5_CC83)
    }

    static func leadershipEnvelopes(
        for actors: [DayObjectActor],
        at rawTime: Double,
        duration rawDuration: Double
    ) -> [DayObjectActorID: Double] {
        guard !actors.isEmpty else { return [:] }
        let duration = rawDuration.isFinite && rawDuration > 0 ? rawDuration : 1
        let time = rawTime.isFinite ? rawTime : 0
        let progress = time / duration
        let candidates = actors.map { actor -> (DayObjectActorID, Double) in
            let phase = 2 * Double.pi * stableUnit(
                actor.seed,
                salt: 0x243F_6A88_85A3_08D3
            )
            let value = 0.5 + 0.5 * cos(2 * Double.pi * progress - phase)
            return (actor.id, value)
        }
        let maximum = max(candidates.map(\.1).max() ?? 1, 0.000_001)
        return Dictionary(uniqueKeysWithValues: candidates.map {
            ($0.0, min(max($0.1 / maximum, 0), 1))
        })
    }

    private static func bodyHalfSize(
        for actor: DayObjectActor,
        pose: DayObjectPose,
        leadership: Double,
        envelopeScale: Double
    ) -> SIMD2<Float> {
        let aspect = DayObjectActorGeometry.aspectRatio(for: actor)
        _ = leadership
        let major = pose.scale * 0.5
        let baseHalfSize = SIMD2<Float>(Float(major), Float(major * aspect))
        return baseHalfSize * Float(envelopeScale)
    }

    private static func color(for actor: DayObjectActor, palette: DayObjectPalette) -> SIMD3<Float> {
        switch actor.role {
        case .focal, .satellite:
            return palette.figurePrimary
        case .support, .bridge:
            return palette.figureSecondary
        case .accent:
            return palette.accent
        }
    }

    private static func numericShape(_ shape: DayObjectShape) -> UInt32 {
        shape.numericValue
    }

    private static func stableUnit(_ seed: UInt64, salt: UInt64) -> Double {
        var value = seed ^ salt
        value &+= 0x9E37_79B9_7F4A_7C15
        value = (value ^ (value >> 30)) &* 0xBF58_476D_1CE4_E5B9
        value = (value ^ (value >> 27)) &* 0x94D0_49BB_1331_11EB
        value ^= value >> 31
        return Double(value >> 11) / Double(UInt64(1) << 53)
    }
}

extension DayObjectGPUActor {
    func replacingPose(
        position: SIMD2<Float>,
        direction: SIMD2<Float>
    ) -> Self {
        Self(
            position: position,
            direction: direction,
            halfSize: halfSize,
            opacity: opacity,
            trailLength: trailLength,
            shape: shape,
            appearanceIndex: appearanceIndex,
            depth: depth,
            materialPhase: materialPhase,
            localDepthSoftness: localDepthSoftness,
            paletteMorph: paletteMorph,
            presentationSaturation: presentationSaturation,
            removalEmphasis: removalEmphasis,
            silhouetteVariant: silhouetteVariant
        )
    }

    func replacingPosition(_ position: SIMD2<Float>) -> Self {
        replacingPose(position: position, direction: direction)
    }
}

extension DayObjectRenderFrame {
    func applyingLunarPhysics(_ output: DayObjectLunarPhysicsOutput) -> Self {
        guard !output.positions.isEmpty || !output.directions.isEmpty else { return self }
        return Self(
            choreographyTime: choreographyTime,
            actors: actors.map { actor in
                let position = output.positions[actor.actorID] ?? actor.gpuActor.position
                let direction = output.directions[actor.actorID] ?? actor.gpuActor.direction
                guard position != actor.gpuActor.position
                        || direction != actor.gpuActor.direction else { return actor }
                return DayObjectRenderActor(
                    actorID: actor.actorID,
                    eventID: actor.eventID,
                    gpuActor: actor.gpuActor.replacingPose(
                        position: position,
                        direction: direction
                    ),
                    gpuAppearance: actor.gpuAppearance
                )
            },
            postProcess: postProcess
        )
    }


    func applyingLunarPositions(_ positions: [DayObjectActorID: SIMD2<Float>]) -> Self {
        applyingLunarPhysics(.init(positions: positions, impacts: []))
    }
}
