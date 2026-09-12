import SwiftUI

enum AppTypography {
    static let interfacePostScriptName = "Onest-Regular"
    static let posterMetadataPostScriptName = "Onest-Medium"

    static func interfacePostScriptName(for weight: Font.Weight) -> String {
        let faces: [Font.Weight: String] = [
            .ultraLight: "Onest-Thin", .thin: "Onest-ExtraLight", .light: "Onest-Light",
            .regular: "Onest-Regular", .medium: "Onest-Medium", .semibold: "Onest-SemiBold",
            .bold: "Onest-Bold", .heavy: "Onest-ExtraBold", .black: "Onest-Black",
        ]
        return faces[weight] ?? interfacePostScriptName
    }

    static func displayPostScriptName(for weight: Font.Weight) -> String {
        [.semibold, .bold, .heavy, .black].contains(weight)
            ? "NowhereDisplay04-Bold" : "NowhereDisplay04-Regular"
    }

    static func pointSize(for style: Font.TextStyle) -> CGFloat {
        switch style {
        case .largeTitle: return 34
        case .title: return 28
        case .title2: return 22
        case .title3: return 20
        case .headline, .body: return 17
        case .callout: return 16
        case .subheadline: return 15
        case .footnote: return 13
        case .caption: return 12
        case .caption2: return 11
        @unknown default: return 17
        }
    }

    static func scaledUIFont(
        size: CGFloat,
        weight: Font.Weight = .regular,
        relativeTo textStyle: Font.TextStyle = .body,
        compatibleWith traitCollection: UITraitCollection? = nil
    ) -> UIFont {
        let base = UIFont(name: interfacePostScriptName(for: weight), size: size)
            ?? UIFont.systemFont(ofSize: size, weight: .regular)
        return UIFontMetrics(forTextStyle: uiFontTextStyle(from: textStyle))
            .scaledFont(for: base, compatibleWith: traitCollection)
    }

    private static func uiFontTextStyle(from style: Font.TextStyle) -> UIFont.TextStyle {
        switch style {
        case .largeTitle: return .largeTitle
        case .title: return .title1
        case .title2: return .title2
        case .title3: return .title3
        case .headline: return .headline
        case .subheadline: return .subheadline
        case .body: return .body
        case .callout: return .callout
        case .footnote: return .footnote
        case .caption: return .caption1
        case .caption2: return .caption2
        @unknown default: return .body
        }
    }
}

/// Onest for interface and poster text; Nowhere Display for brand accents.
extension Font {
    static func onest(
        _ size: CGFloat,
        weight: Font.Weight = .regular,
        relativeTo textStyle: Font.TextStyle = .body
    ) -> Font {
        .custom(AppTypography.interfacePostScriptName(for: weight), size: size, relativeTo: textStyle)
    }

    static func onest(size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .custom(AppTypography.interfacePostScriptName(for: weight), fixedSize: size)
    }

    static func onest(_ textStyle: Font.TextStyle) -> Font {
        let weight: Font.Weight = textStyle == .headline ? .semibold : .regular
        return .onest(AppTypography.pointSize(for: textStyle), weight: weight, relativeTo: textStyle)
    }

    /// Fixed-size display text scales with the exported artwork.
    static func nowhereDisplay(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .custom(AppTypography.displayPostScriptName(for: weight), fixedSize: size)
    }

    static func nowhereDisplay(
        _ size: CGFloat,
        weight: Font.Weight = .regular,
        relativeTo textStyle: Font.TextStyle
    ) -> Font {
        .custom(AppTypography.displayPostScriptName(for: weight), size: size, relativeTo: textStyle)
    }

    // Compatibility names for existing screens. All resolve to the new font pair.
    // `design` is retained for source compatibility; custom faces keep their own design.
    static func geist(
        _ size: CGFloat,
        weight: Font.Weight = .regular,
        relativeTo textStyle: Font.TextStyle = .body
    ) -> Font {
        .onest(size, weight: weight, relativeTo: textStyle)
    }

    static func geist(
        size: CGFloat,
        weight: Font.Weight = .regular,
        design: Font.Design = .default
    ) -> Font {
        .onest(size: size, weight: weight)
    }

    static func geist(_ textStyle: Font.TextStyle, design: Font.Design = .default) -> Font {
        .onest(textStyle)
    }

    static func geistMono(
        _ size: CGFloat,
        weight: Font.Weight = .medium,
        relativeTo textStyle: Font.TextStyle = .body
    ) -> Font {
        .onest(size, weight: weight, relativeTo: textStyle)
    }

    static func geistMono(
        size: CGFloat,
        weight: Font.Weight = .medium,
        design: Font.Design = .default
    ) -> Font {
        .onest(size: size, weight: weight)
    }

    static func geistMono(_ textStyle: Font.TextStyle, design: Font.Design = .default) -> Font {
        .onest(AppTypography.pointSize(for: textStyle), weight: .medium, relativeTo: textStyle)
    }

    static func unbounded(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .nowhereDisplay(size, weight: weight)
    }

    static func unbounded(
        _ size: CGFloat,
        weight: Font.Weight = .regular,
        relativeTo textStyle: Font.TextStyle
    ) -> Font {
        .nowhereDisplay(size, weight: weight, relativeTo: textStyle)
    }
}

/// AppFonts — aliases for consistent typography across the codebase.
enum AppFonts {
    // MARK: - Headlines
    static let largeTitle = Font.onest(.largeTitle)
    static let title = Font.onest(.title)
    static let title2 = Font.onest(.title2)
    static let title3 = Font.onest(.title3)
    static let headline = Font.onest(.headline)

    // MARK: - Body text
    static let body = Font.onest(.body)
    static let subheadline = Font.onest(.subheadline)
    static let caption = Font.onest(.caption)
    static let caption2 = Font.onest(.caption2)
}
