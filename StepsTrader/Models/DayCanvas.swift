import Foundation

/// Local-only recovery journal. Its presence means the file is editable but
/// does not yet contain all of the remote day's artwork.
struct CanvasPendingRemoteHydration: Codable, Equatable {
    var deletedElementIDs: Set<UUID> = []
    var artworkWasEdited = false
}

/// Resolves a locally editable draft only after a conclusive cloud read.
/// Whole-document sync remains last-write-wins; this merge preserves the remote
/// version that was fetched, rather than replacing it with an empty placeholder.
enum CanvasDraftRecovery {
    static func resolve(local: DayCanvas, remote: DayCanvasFetchResult, at now: Date = .now) -> DayCanvas? {
        guard let journal = local.pendingRemoteHydration else { return local }
        var resolved: DayCanvas
        switch remote {
        case .failed:
            return nil
        case .confirmedAbsent:
            resolved = local
        case .found(let remoteCanvas):
            guard remoteCanvas.dayKey == local.dayKey else { return nil }
            resolved = remoteCanvas
            var elements = [UUID: CanvasElement]()
            for element in remoteCanvas.elements where !journal.deletedElementIDs.contains(element.id) {
                elements[element.id] = element
            }
            for element in local.elements where !journal.deletedElementIDs.contains(element.id) {
                if let old = elements[element.id],
                   (old.lastEditedAt ?? old.createdAt) > (element.lastEditedAt ?? element.createdAt) { continue }
                elements[element.id] = element
            }
            var seen = Set<UUID>()
            let ordered = (local.elements + remoteCanvas.elements).compactMap { element -> CanvasElement? in
                guard seen.insert(element.id).inserted else { return nil }
                return elements[element.id]
            }
            if journal.artworkWasEdited {
                resolved.artworkRecipe = local.artworkRecipe
                resolved.remixSeed = local.remixSeed
                resolved.soundWorldRaw = local.soundWorldRaw
                resolved.soundMoodRaw = local.soundMoodRaw
                resolved.guestSoundWorldRaw = local.guestSoundWorldRaw
                resolved.visualStyleRaw = local.visualStyleRaw
                resolved.gradientStyle = local.gradientStyle
                resolved.gradientPalette = local.gradientPalette
                resolved.overlayStyle = local.overlayStyle
                resolved.textureRaw = local.textureRaw
            }
            let recipe = mergedRecipe(base: resolved.artworkRecipe, local: local.artworkRecipe,
                remote: remoteCanvas.artworkRecipe, eventIDs: ordered.map { $0.id.uuidString.lowercased() },
                artworkWasEdited: journal.artworkWasEdited)
            resolved.elements = ordered
            resolved.artworkRecipe = recipe
            if local.lastModified >= remoteCanvas.lastModified {
                resolved.sleepPoints = local.sleepPoints
                resolved.stepsPoints = local.stepsPoints
                resolved.sleepColorHex = local.sleepColorHex
                resolved.stepsColorHex = local.stepsColorHex
                resolved.inkEarned = local.inkEarned
                resolved.inkSpent = local.inkSpent
                resolved.hasStepsData = local.hasStepsData
                resolved.hasSleepData = local.hasSleepData
            }
        }
        resolved.pendingRemoteHydration = nil
        resolved.pendingCloudUpload = true
        resolved.localCloudOwnerID = local.localCloudOwnerID
        resolved.lastModified = now
        return resolved
    }

    /// Keep frozen shapes/materials from both files. Remote placements retain
    /// their slots; an offline addition may need a free slot in the merged day.
    private static func mergedRecipe(base: NativeAtlasRecipe?, local: NativeAtlasRecipe?,
                                     remote: NativeAtlasRecipe?, eventIDs: [String],
                                     artworkWasEdited: Bool) -> NativeAtlasRecipe? {
        guard var recipe = base, recipe.isSupported else { return base }
        let ids = Array(eventIDs.prefix(10))
        let localActors = Dictionary((local?.actors ?? []).map { ($0.eventID, $0) },
                                     uniquingKeysWith: { first, _ in first })
        let remoteActors = (remote?.actors ?? []).filter { ids.contains($0.eventID) }
        var sources = remoteActors.map { actor in
            artworkWasEdited ? (localActors[actor.eventID] ?? actor) : actor
        }
        let remoteIDs = Set(remoteActors.map(\.eventID))
        sources += (local?.actors ?? []).filter { ids.contains($0.eventID) && !remoteIDs.contains($0.eventID) }
        recipe.actors = []
        var assignedIDs = Set<String>()
        for source in sources where assignedIDs.insert(source.eventID).inserted {
            let occupied = Set(recipe.actors.map(\.slot))
            let remoteActor = remoteActors.first { $0.eventID == source.eventID }
            let preferredSlot = remoteActor?.slot ?? source.slot
            let position = preferredSlot == source.slot ? source.position : (remoteActor?.position ?? source.position)
            if !occupied.contains(preferredSlot) {
                recipe.actors.append(copyActor(source, slot: preferredSlot, position: position))
            } else if let placement = recipe.reconciled(eventIDs: recipe.actors.map(\.eventID) + [source.eventID])
                .actors.first(where: { $0.eventID == source.eventID }) {
                recipe.actors.append(copyActor(source, slot: placement.slot, position: placement.position))
            }
        }
        return recipe.reconciled(eventIDs: ids)
    }

    private static func copyActor(_ actor: NativeAtlasRecipe.Actor, slot: Int,
                                  position: SIMD2<Float>) -> NativeAtlasRecipe.Actor {
        NativeAtlasRecipe.Actor(eventID: actor.eventID, presetID: actor.presetID,
            materialID: actor.materialID, seedHex: actor.seedHex, geometry: actor.geometry,
            material: actor.material, position: position, size: actor.size,
            rotation: actor.rotation, slot: slot)
    }
}

struct DayCanvas: Codable {
    var dayKey: String                          // "2026-02-12"
    var elements: [CanvasElement] {             // spawned from activities
        didSet {
            let previousIDs = Set(oldValue.map { $0.id.uuidString.lowercased() })
            let eventIDs = elements.map { $0.id.uuidString.lowercased() }
            artworkRecipe = artworkRecipe?.reconciled(
                eventIDs: eventIDs, addingEventIDs: Set(eventIDs).subtracting(previousIDs)
            )
        }
    }
    var sleepPoints: Int
    var stepsPoints: Int
    var sleepColorHex: String
    var stepsColorHex: String
    var inkEarned: Int
    var inkSpent: Int
    let createdAt: Date
    var lastModified: Date
    var gradientStyle: String?
    var gradientPalette: String?
    var overlayStyle: String?
    var textureRaw: String?
    var visualStyleRaw: String?
    var hasStepsData: Bool?
    var hasSleepData: Bool?
    /// Absent in historical artwork. Never synthesize during decoding.
    var artworkRecipe: NativeAtlasRecipe?
    /// Optional so historical canvases retain their exact pre-Remix artwork.
    var remixSeed: UInt64?
    var soundWorldRaw: String?
    var soundMoodRaw: String?
    var guestSoundWorldRaw: String?
    var pendingRemoteHydration: CanvasPendingRemoteHydration?
    /// Retained after a recovered draft is committed locally, until that exact
    /// version is acknowledged by the server. Neither field is sent to cloud.
    var pendingCloudUpload: Bool?
    /// Binds recovered local work to the account whose remote baseline was
    /// fetched. Legacy local canvases remain unscoped for compatibility.
    var localCloudOwnerID: String?

    var needsRemoteHydration: Bool { pendingRemoteHydration != nil }

    var cloudSnapshot: DayCanvas {
        var snapshot = self
        snapshot.pendingRemoteHydration = nil
        snapshot.pendingCloudUpload = nil
        snapshot.localCloudOwnerID = nil
        return snapshot
    }

    func belongsToCloudUser(_ userID: String) -> Bool {
        localCloudOwnerID == nil || localCloudOwnerID == userID
    }

    mutating func recordExplicitArtworkEdit() {
        pendingRemoteHydration?.artworkWasEdited = true
    }

    var resolvedRemixSeed: UInt64 {
        remixSeed ?? CanvasElement.makeSeed(
            optionId: "dayObjects:primary-canvas", dayKey: dayKey, index: 0
        )
    }

    var resolvedMusicSelection: DayObjectsWorldSelection {
        let fallback = DayObjectsWorldSelector.makeSelection(remixSeed: resolvedRemixSeed)
        return .init(
            world: soundWorldRaw.flatMap(DayObjectsSoundWorld.init(rawValue:)) ?? fallback.world,
            mood: soundMoodRaw.flatMap(DayObjectsSoundMood.init(rawValue:)) ?? fallback.mood,
            guestWorld: soundWorldRaw == nil
                ? fallback.guestWorld
                : guestSoundWorldRaw.flatMap(DayObjectsSoundWorld.init(rawValue:))
        )
    }

    /// Preferences continue to style untouched days. A Remix owns its saved
    /// background, so later health refreshes cannot replace it.
    @discardableResult
    mutating func applyVisualPreferences(
        gradientStyle: String, gradientPalette: String,
        overlayStyle: String, textureRaw: String
    ) -> Bool {
        guard remixSeed == nil else { return false }
        let changed = self.gradientStyle != gradientStyle
            || self.gradientPalette != gradientPalette
            || self.overlayStyle != overlayStyle || self.textureRaw != textureRaw
        self.gradientStyle = gradientStyle
        self.gradientPalette = gradientPalette
        self.overlayStyle = overlayStyle
        self.textureRaw = textureRaw
        return changed
    }

    /// 0.0 = pristine (nothing spent), 1.0 = fully degraded (all colors spent)
    var decayNorm: Double {
        guard inkEarned > 0 else { return 0 }
        return min(1.0, Double(inkSpent) / Double(inkEarned))
    }

    /// Resolved flag: prefers stored boolean, falls back to points > 0 for legacy canvases.
    var resolvedHasStepsData: Bool {
        hasStepsData ?? (stepsPoints > 0)
    }

    /// Resolved flag: prefers stored boolean, falls back to points > 0 for legacy canvases.
    var resolvedHasSleepData: Bool {
        hasSleepData ?? (sleepPoints > 0)
    }

    /// Canvases written before the Editorial promotion are historical Legacy
    /// canvases. Only the one-time active-day migration may promote a missing
    /// value; ordinary decoding never changes old artwork retroactively.
    var resolvedVisualStyle: CanvasVisualStyle {
        CanvasVisualStyle(rawValue: visualStyleRaw ?? "") ?? .legacy
    }

    init(dayKey: String) {
        self.dayKey = dayKey
        self.elements = []
        self.sleepPoints = 0
        self.stepsPoints = 0
        self.sleepColorHex = "#000000"
        self.stepsColorHex = "#FED415"
        self.inkEarned = 0
        self.inkSpent = 0
        self.createdAt = .now
        self.lastModified = .now
        self.gradientStyle = nil
        self.gradientPalette = nil
        self.overlayStyle = nil
        self.textureRaw = nil
        self.visualStyleRaw = nil
        self.hasStepsData = nil
        self.hasSleepData = nil
        self.artworkRecipe = nil
    }

    @discardableResult
    mutating func freezeNativeBackgroundIfNeeded() -> Bool {
        guard var recipe = artworkRecipe, recipe.isSupported,
              recipe.backgroundStyle == nil else { return false }
        recipe.backgroundStyle = recipe.resolvedBackgroundStyle(dayKey: dayKey)
        artworkRecipe = recipe
        return true
    }

    /// Explicit appearance edits update only the canvas selected by the caller.
    /// Loading or rendering saved artwork never reapplies current preferences.
    @discardableResult
    mutating func applyNativeBackground(paletteCategories: Set<ModernPaletteCategory>) -> Bool {
        guard var recipe = artworkRecipe, recipe.isSupported,
              !recipe.locks.contains("artwork") else { return false }
        let background = NativeAtlasRecipe.makeBackgroundStyle(
            dayKey: dayKey, recipeSeed: UInt64(recipe.seedHex, radix: 16) ?? 0,
            paletteCategories: paletteCategories
        )
        guard recipe.backgroundStyle != background else { return false }
        recipe.backgroundStyle = background
        artworkRecipe = recipe
        recordExplicitArtworkEdit()
        lastModified = .now
        return true
    }

    static func newDailyCanvas(
        dayKey: String,
        paletteCategories: Set<ModernPaletteCategory> = ModernPaletteSelection.all
    ) -> Self {
        var canvas = Self(dayKey: dayKey)
        canvas.visualStyleRaw = CanvasVisualStyle.editorial.rawValue
        canvas.artworkRecipe = .make(dayKey: dayKey, paletteCategories: paletteCategories)
        return canvas
    }
}
