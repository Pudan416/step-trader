import Foundation

/// Decorative identity from the happening shape catalog; independent of personal events.
/// The bundled snapshots are exported by MetalShapeGenomeRenderer, not a second generator.
struct GateArtwork: Codable, Equatable {
    let seed: UInt32

    // Keep ordering stable: persisted seeds identify the same image in both processes.
    static let presetIDs = [
        "genome.concave-square", "genome.soft-clover", "genome.windflower",
        "genome.snowflake", "legacy.soft-square", "legacy.rounded-triangle",
        "legacy.rounded-hexagon",
    ]
    // One quiet two-color material; hue variants reuse the canvas color rotation.
    static let colorVariants: [Int?] = [nil, 0, 1, 2, 3, 4, 5]
    static let colorwayCount = 3
    static var variantCount: Int { presetIDs.count * colorwayCount }
    var variantIndex: Int { Int(seed % UInt32(Self.variantCount)) }
    var presetID: String { Self.presetIDs[variantIndex % Self.presetIDs.count] }
    var materialID: String { "sideLight" }
    var renderSeed: UInt64 { 64 }
    var colorVariant: Int? {
        let shape = variantIndex % Self.presetIDs.count
        let colorway = variantIndex / Self.presetIDs.count
        return Self.colorVariants[(shape + colorway * 2) % Self.colorVariants.count]
    }
    var resourceName: String {
        let color = colorVariant.map(String.init) ?? "original"
        return "\(presetID)-\(materialID)-\(renderSeed)-c\(color)"
    }

    static func random(excluding previous: GateArtwork? = nil) -> GateArtwork {
        var candidate = GateArtwork(seed: .random(in: 0...UInt32.max))
        while candidate.variantIndex == previous?.variantIndex {
            candidate = GateArtwork(seed: .random(in: 0...UInt32.max))
        }
        return candidate
    }
}

/// Small App Group record lets the shield, its action extension and PayGate
/// share an object without rendering the user's canvas or loading its data.
final class GateArtworkStore {
    private struct Preview: Codable {
        let artwork: GateArtwork
        let createdAt: Date
    }

    private struct Handoff: Codable {
        let target: String
        let groupID: String?
        let preview: Preview
        let requestedAt: Date
    }

    private static let lock = NSLock()
    private let defaults: UserDefaults
    private let previewsKey = "gateArtwork.previews.v1"
    private let handoffKey = "gateArtwork.handoff.v1"
    private let lastKey = "gateArtwork.last.v1"

    init(defaults: UserDefaults) { self.defaults = defaults }

    func shieldArtwork(for target: String, now: Date = .now) -> GateArtwork {
        Self.lock.lock()
        defer { Self.lock.unlock() }
        return preview(for: target, now: now).artwork
    }

    func prepareHandoff(from target: String, groupID: String?, now: Date = .now) {
        Self.lock.lock()
        defer { Self.lock.unlock() }
        // Keep the displayed object even when the user spent a while on the shield.
        let displayed = (read(previewsKey) as [String: Preview]?)?[target] ?? preview(for: target, now: now)
        var previews: [String: Preview] = read(previewsKey) ?? [:]
        previews[target] = Preview(artwork: displayed.artwork, createdAt: now)
        write(previews, to: previewsKey)
        write(Handoff(target: target, groupID: groupID, preview: displayed, requestedAt: now), to: handoffKey)
    }

    func takeHandoff(for groupID: String, now: Date = .now) -> GateArtwork? {
        Self.lock.lock()
        defer { Self.lock.unlock() }
        guard let handoff: Handoff = read(handoffKey) else { return nil }
        let age = now.timeIntervalSince(handoff.requestedAt)
        guard age >= 0, age < 300 else {
            defaults.removeObject(forKey: handoffKey)
            return nil
        }
        guard handoff.groupID == nil || handoff.groupID == groupID else { return nil }
        defaults.removeObject(forKey: handoffKey)
        removePreview(for: handoff.target)
        return handoff.preview.artwork
    }

    func endShield(for target: String) {
        Self.lock.lock()
        defer { Self.lock.unlock() }
        removePreview(for: target)
        if let pending: Handoff = read(handoffKey), pending.target == target {
            defaults.removeObject(forKey: handoffKey)
        }
    }

    private func preview(for target: String, now: Date) -> Preview {
        var previews: [String: Preview] = read(previewsKey) ?? [:]
        // iOS may ask for configuration repeatedly for the same visible shield.
        // A short cache prevents those refreshes from becoming a visual shuffle.
        if let existing = previews[target] {
            let age = now.timeIntervalSince(existing.createdAt)
            if age >= 0, age < 90 { return existing }
        }
        let last: GateArtwork? = read(lastKey)
        let next = Preview(artwork: .random(excluding: last), createdAt: now)
        previews = previews.filter { now.timeIntervalSince($0.value.createdAt) < 300 }
        if previews.count >= 12, let oldest = previews.min(by: { $0.value.createdAt < $1.value.createdAt }) {
            previews.removeValue(forKey: oldest.key)
        }
        previews[target] = next
        write(previews, to: previewsKey)
        write(next.artwork, to: lastKey)
        return next
    }

    private func removePreview(for target: String) {
        var previews: [String: Preview] = read(previewsKey) ?? [:]
        previews.removeValue(forKey: target)
        write(previews, to: previewsKey)
    }

    private func read<T: Decodable>(_ key: String) -> T? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }

    private func write<T: Encodable>(_ value: T, to key: String) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        defaults.set(data, forKey: key)
    }
}
