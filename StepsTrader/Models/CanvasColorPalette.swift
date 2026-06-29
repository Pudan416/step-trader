import Foundation

enum CanvasColorPalette {
    /// 29-color canvas palette — no greens, near-duplicates removed, with deep jewel
    /// tones for contrast. Gradients mix any color with any other (no group constraint).
    static let paletteHex: [String] = [
        // Reds / Pinks
        "#CC5050", "#E89070", "#C04878", "#D06880",
        "#C06090", "#E098A0", "#A85060", "#D07858",
        // Yellows / Earth
        "#E8B060", "#D09850", "#D8C078", "#B08040",
        // Purples
        "#8878B8", "#B060A8", "#684880", "#6058A0",
        // Blues / Teal
        "#6098CC", "#5078B8", "#8088C8", "#486888", "#58A8A8",
        // Deep / Jewel tones
        "#6E1A2E", "#8A1F38", "#8A2A14", "#3A1660",
        "#5C1648", "#1E2E78", "#0E3A6E", "#0E4A4E",
    ]

    /// ~50% chance of a second color — any other palette color (mix all with all).
    static func randomSecondColor(excluding primary: String) -> String? {
        guard Bool.random() else { return nil }
        let candidates = paletteHex.filter { $0.uppercased() != primary.uppercased() }
        return candidates.randomElement()
    }

    /// Deterministic second color from anywhere in the palette. ~50% nil.
    static func seededSecondColor(seed: UInt64, primary: String) -> String? {
        guard seed % 2 == 0 else { return nil }
        let candidates = paletteHex.filter { $0.uppercased() != primary.uppercased() }
        guard !candidates.isEmpty else { return nil }
        let idx = Int(seed / 2) % candidates.count
        return candidates[idx]
    }

    /// Three distinct hex colors from anywhere in the palette — for ray spotlight fills.
    static func seededColorTriple(seed: UInt64) -> (String, String, String) {
        var rng = SeededRNG(seed: seed)
        var indices = Array(0..<paletteHex.count)
        for i in stride(from: indices.count - 1, through: 1, by: -1) {
            let j = rng.nextInt(in: 0...i)
            indices.swapAt(i, j)
        }
        return (paletteHex[indices[0]], paletteHex[indices[1]], paletteHex[indices[2]])
    }

    // MARK: - Legacy Migration

    /// Maps colors no longer in the palette (legacy data, removed greens, deduped
    /// shades) to the closest current palette color.
    private static let legacyToNew: [String: String] = [
        // Removed greens → nearest cool tone (no green in palette anymore)
        "#509860": "#58A8A8", "#68A870": "#58A8A8",
        "#88C088": "#58A8A8", "#407848": "#0E4A4E",
        // Deduped shades → kept neighbor
        "#7868A8": "#8878B8", // → lavender
        "#70B8B8": "#58A8A8", // → teal
        "#5088B0": "#5078B8", // → cobalt
        "#E09068": "#E89070", // → salmon
        // Pre-palette era
        "#C3143B": "#CC5050",
        "#9BB6E0": "#5078B8",
        "#A7BF50": "#58A8A8",
        "#C3D7A3": "#58A8A8",
        "#01B6C4": "#58A8A8",
        "#7652AF": "#8878B8",
        "#F68D0C": "#E8B060",
        "#2C2E4D": "#486888",
        "#796C3C": "#B08040",
        "#FFD369": "#E8B060",
        "#49484D": "#684880",
        "#C7E0D8": "#58A8A8",
        "#222831": "#0E4A4E",
        "#955530": "#D07858",
        "#FEAAC2": "#E098A0",
        "#EBE4D7": "#D06880",
    ]

    /// Maps a legacy hex color to the closest new palette color.
    /// Returns the input unchanged if it's already in the current palette.
    static func migrateLegacyColor(_ hex: String) -> String {
        let upper = hex.uppercased()
        if paletteHex.contains(where: { $0.uppercased() == upper }) { return hex }
        return legacyToNew[upper] ?? paletteHex[0]
    }
}
