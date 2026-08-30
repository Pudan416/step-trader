import SwiftUI

enum AppTypography {
    static let interfacePostScriptName = "Geist-Medium"
    static let posterMetadataPostScriptName = "GeistMono-Medium"

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
        relativeTo textStyle: Font.TextStyle = .body,
        compatibleWith traitCollection: UITraitCollection? = nil
    ) -> UIFont {
        let base = UIFont(name: interfacePostScriptName, size: size)
            ?? UIFont.systemFont(ofSize: size, weight: .medium)
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

/// App-wide typography: Geist Medium for interface text, Geist Mono Medium
/// for poster metadata, and Unbounded for short brand/display moments.
extension Font {
    static func geist(
        _ size: CGFloat,
        weight: Font.Weight = .medium,
        relativeTo textStyle: Font.TextStyle = .body
    ) -> Font {
        .custom(
            AppTypography.interfacePostScriptName,
            size: size,
            relativeTo: textStyle
        )
    }

    static func geist(
        size: CGFloat,
        weight: Font.Weight = .medium,
        design: Font.Design = .default
    ) -> Font {
        .custom(AppTypography.interfacePostScriptName, fixedSize: size)
    }

    static func geist(
        _ textStyle: Font.TextStyle,
        design: Font.Design = .default
    ) -> Font {
        .custom(
            AppTypography.interfacePostScriptName,
            size: AppTypography.pointSize(for: textStyle),
            relativeTo: textStyle
        )
    }

    static func geistMono(
        _ size: CGFloat,
        weight: Font.Weight = .medium,
        relativeTo textStyle: Font.TextStyle = .body
    ) -> Font {
        .custom(
            AppTypography.posterMetadataPostScriptName,
            size: size,
            relativeTo: textStyle
        )
    }

    static func geistMono(
        size: CGFloat,
        weight: Font.Weight = .medium,
        design: Font.Design = .default
    ) -> Font {
        .custom(AppTypography.posterMetadataPostScriptName, fixedSize: size)
    }

    static func geistMono(
        _ textStyle: Font.TextStyle,
        design: Font.Design = .default
    ) -> Font {
        .custom(
            AppTypography.posterMetadataPostScriptName,
            size: AppTypography.pointSize(for: textStyle),
            relativeTo: textStyle
        )
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
        .black: "Unbounded-Black",
    ]

    private static func unboundedPostScriptName(for weight: Font.Weight) -> String {
        unboundedPostScriptNames[weight] ?? "Unbounded-Regular"
    }
}

/// AppFonts — aliases for consistent typography across the codebase.
enum AppFonts {
    // MARK: - Headlines
    static let largeTitle = Font.geist(.largeTitle)
    static let title = Font.geist(.title)
    static let title2 = Font.geist(.title2)
    static let title3 = Font.geist(.title3)
    static let headline = Font.geist(.headline)

    // MARK: - Body text
    static let body = Font.geist(.body)
    static let subheadline = Font.geist(.subheadline)
    static let caption = Font.geist(.caption)
    static let caption2 = Font.geist(.caption2)
}
