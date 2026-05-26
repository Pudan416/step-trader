import SwiftUI

/// System fonts (SF) as app-wide typography.
extension Font {
    static func systemSerif(
        _ size: CGFloat,
        weight: Font.Weight = .regular,
        relativeTo textStyle: Font.TextStyle = .body
    ) -> Font {
        let base = UIFont.systemFont(ofSize: size, weight: uiFontWeight(from: weight))
        let scaled = UIFontMetrics(forTextStyle: uiFontTextStyle(from: textStyle)).scaledFont(for: base)
        return Font(scaled)
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
    static let largeTitle = Font.largeTitle
    static let title = Font.title
    static let title2 = Font.title2
    static let title3 = Font.title3
    static let headline = Font.headline

    // MARK: - Body text
    static let body = Font.body
    static let subheadline = Font.subheadline
    static let caption = Font.caption
    static let caption2 = Font.caption2
}
