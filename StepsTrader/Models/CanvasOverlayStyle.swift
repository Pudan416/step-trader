import SwiftUI

/// User-selectable interactive overlay rendered on top of the gallery canvas.
/// Persisted via `SharedKeys.canvasOverlayStyle` in the App-Group defaults so
/// the choice is mirrored to widgets / future extensions.
enum CanvasOverlayStyle: String, CaseIterable, Identifiable {
    /// No overlay — pure canvas, no Metal layer.
    case none
    /// Original "fingerprint" smudge — paint-on-glass distortion + ripples.
    case smudge
    /// Procedural raymarched shape (FBM-coloured torus⇌sphere with mirrored
    /// inner frame) inspired by ShaderPark; see `ShaderParkShader.metal`.
    case cosmic

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .none:
            String(localized: "Off",
                   comment: "Canvas animation picker – no overlay")
        case .smudge:
            String(localized: "Smudge",
                   comment: "Canvas animation picker – smudge option")
        case .cosmic:
            String(localized: "Cosmic",
                   comment: "Canvas animation picker – cosmic shader option")
        }
    }

    var subtitle: String {
        switch self {
        case .none:
            String(localized: "No overlay on the canvas.",
                   comment: "Canvas animation picker – off subtitle")
        case .smudge:
            String(localized: "Drag to smudge the canvas.",
                   comment: "Canvas animation picker – smudge subtitle")
        case .cosmic:
            String(localized: "Drifting field — tap and drag to morph it.",
                   comment: "Canvas animation picker – cosmic subtitle")
        }
    }

    var iconName: String {
        switch self {
        case .none:   "circle.slash"
        case .smudge: "hand.draw"
        case .cosmic: "sparkles"
        }
    }
}

// MARK: - Canvas Texture

/// Selectable grain overlay for the canvas.
/// Each case corresponds to a pre-composited image in the asset catalog.
enum CanvasTexture: String, CaseIterable, Identifiable {
    case none
    case grainSmall    = "grain (small)"
    case grainMedium   = "grain (medium)"
    case grainIntense  = "grain (intense)"
    case grainDigital  = "grain (digital)"
    case plastic       = "Plastic"
    case glass         = "glass"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .none:          String(localized: "Off", comment: "Texture picker – no texture")
        case .grainSmall:    String(localized: "Small", comment: "Texture picker – small grain")
        case .grainMedium:   String(localized: "Medium", comment: "Texture picker – medium grain")
        case .grainIntense:  String(localized: "Intense", comment: "Texture picker – intense grain")
        case .grainDigital:  String(localized: "Digital", comment: "Texture picker – digital grain")
        case .plastic:       String(localized: "Plastic", comment: "Texture picker – plastic")
        case .glass:         String(localized: "Glass", comment: "Texture picker – glass")
        }
    }

    var assetName: String? {
        switch self {
        case .none: nil
        default:    rawValue
        }
    }

    var blendMode: BlendMode {
        switch self {
        case .none:         .normal
        case .grainSmall:   .overlay
        case .grainMedium:  .colorDodge
        case .grainIntense: .colorDodge
        case .grainDigital: .overlay
        case .plastic:      .overlay
        case .glass:        .overlay
        }
    }

    var defaultOpacity: Double {
        switch self {
        case .none:         0
        case .grainSmall:   0.4
        case .grainDigital: 0.2
        case .plastic:      0.15
        case .glass:        0.5
        default:            0.35
        }
    }

    /// All texture options (excludes `.none`).
    static let textures: [CanvasTexture] = allCases.filter { $0 != .none }

    static func seeded(seed: UInt64) -> CanvasTexture {
        let pool = textures
        return pool[Int(seed) % pool.count]
    }

    var isPro: Bool {
        switch self {
        case .none, .grainSmall: false
        default: true
        }
    }

    /// Migrates legacy raw values to the current enum.
    /// Returns `.grainSmall` for unknown/legacy values.
    static func fromStored(_ raw: String) -> CanvasTexture {
        if let known = CanvasTexture(rawValue: raw) { return known }
        switch raw {
        case "grain":     return .grainSmall
        case "texture 1": return .grainMedium
        case "texture 3": return .grainIntense
        case "texture 5": return .grainDigital
        default:          return .grainSmall
        }
    }

    static func hasImage(named name: String) -> Bool {
        #if canImport(UIKit)
        return UIImage(named: name) != nil
        #else
        return false
        #endif
    }
}

// MARK: - Texture Overlay View

/// Renders a `CanvasTexture` as a full-bleed overlay.
/// Drop this into any `ZStack` after the content it should overlay.
struct TextureOverlayView: View {
    let texture: CanvasTexture
    var opacity: Double? = nil

    var body: some View {
        if let name = texture.assetName {
            Image(name)
                .resizable()
                .scaledToFill()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()
                .blendMode(texture.blendMode)
                .opacity(opacity ?? texture.defaultOpacity)
                .ignoresSafeArea()
                .allowsHitTesting(false)
        }
    }
}
