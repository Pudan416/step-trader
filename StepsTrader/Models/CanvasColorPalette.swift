import Foundation

enum CanvasColorPalette {
    /// 20-color activity palette — balanced across the full hue wheel.
    /// 4 warm coral/amber + 4 hot red/gold/fuchsia + 4 violet + 4 rose + 4 teal/sage.
    static let paletteHex: [String] = [
        // Warm (coral / amber)
        "#D07858", "#E09068", "#D09850", "#B08040",
        // Hot (cherry / salmon / gold / fuchsia)
        "#CC5050", "#E89070", "#E8B060", "#C04878",
        // Violet (lavender / plum)
        "#8878B8", "#7868A8", "#B060A8", "#684880",
        // Rose (pink / mauve)
        "#D06880", "#C06090", "#E098A0", "#A85060",
        // Cool (teal / sage / ocean / mint)
        "#58A8A8", "#68A870", "#5088B0", "#88C088",
    ]

    /// ~50% chance of returning a second color different from `primary` for a gradient fill.
    static func randomSecondColor(excluding primary: String) -> String? {
        guard Bool.random() else { return nil }
        let candidates = paletteHex.filter { $0 != primary }
        return candidates.randomElement()
    }

    // MARK: - Legacy Migration

    private static let legacyToNew: [String: String] = [
        // Pre-palette era
        "#C3143B": "#CC5050",  // red → cherry red
        "#9BB6E0": "#5088B0",  // light blue → ocean blue
        "#A7BF50": "#68A870",  // lime → sage green
        "#C3D7A3": "#88C088",  // pale green → mint
        "#01B6C4": "#58A8A8",  // cyan → dusty teal
        "#7652AF": "#7868A8",  // purple → warm violet
        "#F68D0C": "#E8B060",  // orange → warm gold
        "#2C2E4D": "#5088B0",  // dark navy → ocean blue
        "#796C3C": "#B08040",  // olive → warm amber
        "#FFD369": "#E8B060",  // yellow → warm gold
        "#49484D": "#684880",  // dark gray → deep plum
        "#C7E0D8": "#88C088",  // mint → mint
        "#222831": "#68A870",  // near-black → sage
        "#955530": "#D07858",  // brown → warm coral
        "#FEAAC2": "#E098A0",  // pink → light rose
        "#EBE4D7": "#D06880",  // cream → dusty rose
        // Palette v1 → v2 (removed tones)
        "#70B8B8": "#88C088",  // light sage-teal → mint
        "#486888": "#5088B0",  // deep slate → ocean blue
        "#509860": "#68A870",  // medium green → sage
        "#407848": "#68A870",  // dark forest → sage
    ]

    /// Maps a legacy hex color to the closest new palette color.
    /// Returns the input unchanged if it's already in the current palette.
    static func migrateLegacyColor(_ hex: String) -> String {
        let upper = hex.uppercased()
        if paletteHex.contains(where: { $0.uppercased() == upper }) { return hex }
        return legacyToNew[upper] ?? paletteHex[0]
    }

    /// Deterministic second color from a seed. ~50% nil.
    static func seededSecondColor(seed: UInt64, primary: String) -> String? {
        guard seed % 2 == 0 else { return nil }
        let candidates = paletteHex.filter { $0 != primary }
        guard !candidates.isEmpty else { return nil }
        let idx = Int(seed / 2) % candidates.count
        return candidates[idx]
    }
}
