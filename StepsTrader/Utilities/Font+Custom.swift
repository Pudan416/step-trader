import SwiftUI

/// App-wide typography: SF Pro Rounded for interface text and Unbounded for
/// short brand/display moments.
extension Font {
    static func appRounded(
        _ size: CGFloat,
        weight: Font.Weight = .regular,
        relativeTo textStyle: Font.TextStyle = .body
    ) -> Font {
        let base = UIFont.systemFont(ofSize: size, weight: uiFontWeight(from: weight))
        let descriptor = base.fontDescriptor.withDesign(.rounded) ?? base.fontDescriptor
        let rounded = UIFont(descriptor: descriptor, size: size)
        let scaled = UIFontMetrics(forTextStyle: uiFontTextStyle(from: textStyle)).scaledFont(for: rounded)
        return Font(scaled)
    }

    /// Fixed-size brand type for canvas/poster compositions whose typography
    /// scales with the exported artwork rather than Dynamic Type.
    static func unbounded(
        _ size: CGFloat,
        weight: Font.Weight = .regular
    ) -> Font {
        .custom(unboundedPostScriptName(for: weight), fixedSize: size)
    }

    /// Dynamic-Type-aware brand type for short headings in the app UI.
    static func unbounded(
        _ size: CGFloat,
        weight: Font.Weight = .regular,
        relativeTo textStyle: Font.TextStyle
    ) -> Font {
        .custom(
            unboundedPostScriptName(for: weight),
            size: size,
            relativeTo: textStyle
        )
    }

    private static let unboundedPostScriptNames: [Font.Weight: String] = [
        .ultraLight: "Unbounded-Regular_ExtraLight",
        .thin: "Unbounded-Regular_ExtraLight",
        .light: "Unbounded-Regular_Light",
        .regular: "Unbounded-Regular",
        .medium: "Unbounded-Regular_Medium",
        .semibold: "Unbounded-Regular_SemiBold",
        .bold: "Unbounded-Regular_Bold",
        .heavy: "Unbounded-Regular_ExtraBold",
        .black: "Unbounded-Regular_Black",
    ]

    private static func unboundedPostScriptName(for weight: Font.Weight) -> String {
        unboundedPostScriptNames[weight] ?? "Unbounded-Regular"
    }

    private static let fontWeightMap: [Font.Weight: UIFont.Weight] = [
        .ultraLight: .ultraLight, .thin: .thin, .light: .light,
        .regular: .regular, .medium: .medium, .semibold: .semibold,
        .bold: .bold, .heavy: .heavy, .black: .black,
    ]

    private static func uiFontWeight(from weight: Font.Weight) -> UIFont.Weight {
        fontWeightMap[weight] ?? .regular
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

/// AppFonts — aliases for consistent typography across the codebase.
enum AppFonts {
    // MARK: - Headlines
    static let largeTitle = Font.system(.largeTitle, design: .rounded)
    static let title = Font.system(.title, design: .rounded)
    static let title2 = Font.system(.title2, design: .rounded)
    static let title3 = Font.system(.title3, design: .rounded)
    static let headline = Font.system(.headline, design: .rounded)

    // MARK: - Body text
    static let body = Font.system(.body, design: .rounded)
    static let subheadline = Font.system(.subheadline, design: .rounded)
    static let caption = Font.system(.caption, design: .rounded)
    static let caption2 = Font.system(.caption2, design: .rounded)
}
