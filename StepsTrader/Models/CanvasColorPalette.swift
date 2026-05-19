import Foundation

enum CanvasColorPalette {
    static let colorsPerGroup = 4
    static let groupCount = 6

    /// 24-color canvas palette — 5 saturated hue groups + 1 muted warm group.
    static let paletteHex: [String] = [
        // Hot (cherry / salmon / gold / fuchsia)
        "#CC5050", "#E89070", "#E8B060", "#C04878",
        // Rose (pink / mauve)
        "#D06880", "#C06090", "#E098A0", "#A85060",
        // Violet (lavender / plum)
        "#8878B8", "#7868A8", "#B060A8", "#684880",
        // Teal (dusty teal / ocean / slate)
        "#58A8A8", "#70B8B8", "#5088B0", "#486888",
        // Green (sage / moss / emerald / forest)
        "#509860", "#68A870", "#88C088", "#407848",
        // Warm (coral / amber — muted, single group)
        "#D07858", "#E09068", "#D09850", "#B08040",
    ]

    static func groupIndex(for hex: String) -> Int? {
        guard let idx = paletteHex.firstIndex(where: { $0.uppercased() == hex.uppercased() }) else {
            return nil
        }
        return idx / colorsPerGroup
    }

    static func groupColors(at group: Int) -> [String] {
        let start = group * colorsPerGroup
        guard start >= 0, start + colorsPerGroup <= paletteHex.count else { return [] }
        return Array(paletteHex[start..<(start + colorsPerGroup)])
    }

    /// Other colors in the same harmonious group as `primary`.
    static func groupColors(for primary: String) -> [String] {
        guard let group = groupIndex(for: primary) else { return paletteHex }
        return groupColors(at: group)
    }

    /// ~50% chance of a second color from the same group as `primary`.
    static func randomSecondColor(excluding primary: String) -> String? {
        guard Bool.random() else { return nil }
        let candidates = groupColors(for: primary).filter { $0.uppercased() != primary.uppercased() }
        return candidates.randomElement()
    }

    /// Deterministic second color from the same group as `primary`. ~50% nil.
    static func seededSecondColor(seed: UInt64, primary: String) -> String? {
        guard seed % 2 == 0 else { return nil }
        let candidates = groupColors(for: primary).filter { $0.uppercased() != primary.uppercased() }
        guard !candidates.isEmpty else { return nil }
        let idx = Int(seed / 2) % candidates.count
        return candidates[idx]
    }

    /// Three distinct hex colors from one palette group — for ray spotlight fills.
    static func seededGroupTriple(seed: UInt64) -> (String, String, String) {
        var rng = SeededRNG(seed: seed)
        let group = rng.nextInt(in: 0...(groupCount - 1))
        let groupHex = groupColors(at: group)
        var indices = Array(0..<colorsPerGroup)
        for i in stride(from: indices.count - 1, through: 1, by: -1) {
            let j = rng.nextInt(in: 0...i)
            indices.swapAt(i, j)
        }
        return (groupHex[indices[0]], groupHex[indices[1]], groupHex[indices[2]])
    }

    // MARK: - Legacy Migration

    private static let legacyToNew: [String: String] = [
        // Pre-palette era
        "#C3143B": "#CC5050",
        "#9BB6E0": "#5088B0",
        "#A7BF50": "#68A870",
        "#C3D7A3": "#88C088",
        "#01B6C4": "#58A8A8",
        "#7652AF": "#7868A8",
        "#F68D0C": "#E8B060",
        "#2C2E4D": "#486888",
        "#796C3C": "#B08040",
        "#FFD369": "#E8B060",
        "#49484D": "#684880",
        "#C7E0D8": "#88C088",
        "#222831": "#407848",
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
