import Foundation

struct CanvasRemixSnapshot {
    let dayKey: String
    let seed: UInt64
    let remixSeed: UInt64?
    let elements: [CanvasElement]
    let gradientStyle: String?
    let gradientPalette: String?
    let overlayStyle: String?
    let textureRaw: String?
    let soundWorldRaw: String?
    let soundMoodRaw: String?
    let guestSoundWorldRaw: String?
    let artworkRecipe: NativeAtlasRecipe?

    init(canvas: DayCanvas) {
        dayKey = canvas.dayKey
        seed = canvas.resolvedRemixSeed
        remixSeed = canvas.remixSeed
        elements = canvas.elements
        gradientStyle = canvas.gradientStyle
        gradientPalette = canvas.gradientPalette
        overlayStyle = canvas.overlayStyle
        textureRaw = canvas.textureRaw
        soundWorldRaw = canvas.soundWorldRaw
        soundMoodRaw = canvas.soundMoodRaw
        guestSoundWorldRaw = canvas.guestSoundWorldRaw
        artworkRecipe = canvas.artworkRecipe
    }
}

struct CanvasUnifiedRemixResult {
    let canvas: DayCanvas
    let previous: CanvasRemixSnapshot
    let musicSelection: DayObjectsWorldSelection
    let seed: UInt64
}

enum CanvasUnifiedRemix {
    static func next(
        canvas: DayCanvas,
        allowedShapes: [CanvasShapeType] = CanvasShapeType.allowedByUser,
        paletteCategories: Set<ModernPaletteCategory> = ModernPaletteSelection.all,
        at date: Date = .now
    ) -> CanvasUnifiedRemixResult {
        let seed = canvas.resolvedRemixSeed &+ 1
        let selection = DayObjectsWorldSelector.makeSelection(remixSeed: seed)
        var next = canvas
        next.remixSeed = seed
        next.soundWorldRaw = selection.world.rawValue
        next.soundMoodRaw = selection.mood.rawValue
        next.guestSoundWorldRaw = selection.guestWorld?.rawValue
        next.elements = CanvasRemix.remixed(
            canvas.elements,
            composition: .forDay(
                dayKey: canvas.dayKey, happeningCount: canvas.elements.count,
                allowedTextureKinds: TextureKind.allCases, remixSeed: seed
            ),
            remixSeed: seed, allowedShapes: allowedShapes, at: date
        )
        next.artworkRecipe = canvas.artworkRecipe?.remixed(seedKey: String(seed), dayKey: canvas.dayKey, paletteCategories: paletteCategories)
            .reconciled(eventIDs: next.elements.map { $0.id.uuidString.lowercased() })
        var style = SeededRNG.derived(from: seed, domain: "canvas.background.style")
        var palette = SeededRNG.derived(from: seed, domain: "canvas.background.palette")
        var texture = SeededRNG.derived(from: seed, domain: "canvas.background.texture")
        next.gradientStyle = GradientStyle.allCases[style.nextInt(in: 0...(GradientStyle.allCases.count - 1))].rawValue
        next.gradientPalette = GradientPalette.allCases[palette.nextInt(in: 0...(GradientPalette.allCases.count - 1))].rawValue
        next.textureRaw = CanvasTexture.allCases[texture.nextInt(in: 0...(CanvasTexture.allCases.count - 1))].rawValue
        next.lastModified = date
        return .init(canvas: next, previous: .init(canvas: canvas), musicSelection: selection, seed: seed)
    }

    static func restore(_ snapshot: CanvasRemixSnapshot, into canvas: DayCanvas) -> DayCanvas {
        guard snapshot.dayKey == canvas.dayKey else { return canvas }
        var restored = canvas
        // Preserve additions/deletions made since the snapshot. Undo concerns
        // appearance, never the health data or which happenings occurred.
        let oldElements = Dictionary(uniqueKeysWithValues: snapshot.elements.map { ($0.id, $0) })
        restored.elements = canvas.elements.map { oldElements[$0.id] ?? $0 }
        restored.remixSeed = snapshot.remixSeed
        restored.gradientStyle = snapshot.gradientStyle
        restored.gradientPalette = snapshot.gradientPalette
        restored.overlayStyle = snapshot.overlayStyle
        restored.textureRaw = snapshot.textureRaw
        restored.soundWorldRaw = snapshot.soundWorldRaw
        restored.soundMoodRaw = snapshot.soundMoodRaw
        restored.guestSoundWorldRaw = snapshot.guestSoundWorldRaw
        restored.artworkRecipe = snapshot.artworkRecipe?.reconciled(
            eventIDs: restored.elements.map { $0.id.uuidString.lowercased() }
        )
        return restored
    }
}

/// Owned by Gallery, with one history for visual and musical identity.
struct CanvasRemixHistory {
    private var snapshots: [CanvasRemixSnapshot] = []
    var canUndo: Bool { !snapshots.isEmpty }

    /// Persist the entire replacement once before publishing it. A failed
    /// write leaves both the visible canvas and Undo history available to retry.
    mutating func commitRemix(
        canvas: DayCanvas,
        allowedShapes: [CanvasShapeType] = CanvasShapeType.allowedByUser,
        paletteCategories: Set<ModernPaletteCategory> = ModernPaletteSelection.all,
        at date: Date = .now,
        persist: (DayCanvas) -> Bool
    ) -> CanvasUnifiedRemixResult? {
        var candidate = self
        let result = candidate.remix(canvas: canvas, allowedShapes: allowedShapes, paletteCategories: paletteCategories, at: date)
        guard persist(result.canvas) else { return nil }
        self = candidate
        return result
    }

    mutating func commitUndo(
        into canvas: DayCanvas,
        at date: Date = .now,
        persist: (DayCanvas) -> Bool
    ) -> DayCanvas? {
        var candidate = self
        guard var restored = candidate.undo(into: canvas) else { return nil }
        restored.lastModified = date
        for index in restored.elements.indices { restored.elements[index].lastEditedAt = date }
        guard persist(restored) else { return nil }
        self = candidate
        return restored
    }

    mutating func remix(
        canvas: DayCanvas,
        allowedShapes: [CanvasShapeType] = CanvasShapeType.allowedByUser,
        paletteCategories: Set<ModernPaletteCategory> = ModernPaletteSelection.all,
        at date: Date = .now
    ) -> CanvasUnifiedRemixResult {
        if snapshots.last?.dayKey != canvas.dayKey { snapshots.removeAll() }
        let result = CanvasUnifiedRemix.next(canvas: canvas, allowedShapes: allowedShapes, paletteCategories: paletteCategories, at: date)
        snapshots.append(result.previous)
        if snapshots.count > 10 { snapshots.removeFirst(snapshots.count - 10) }
        return result
    }

    mutating func undo(into canvas: DayCanvas) -> DayCanvas? {
        guard let snapshot = snapshots.popLast() else { return nil }
        guard snapshot.dayKey == canvas.dayKey else {
            snapshots.removeAll()
            return nil
        }
        return CanvasUnifiedRemix.restore(snapshot, into: canvas)
    }
}
