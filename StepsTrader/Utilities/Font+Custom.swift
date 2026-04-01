import SwiftUI
import UIKit

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

    static func reenie(
        _ size: CGFloat,
        relativeTo textStyle: Font.TextStyle = .body
    ) -> Font {
        .custom("ReenieBeanie", size: size, relativeTo: textStyle)
    }

    // MARK: - Ticket card title fonts (sticker-style)

    /// Resolves the first available PostScript name from candidates, caching the result.
    @MainActor private static var resolvedFontNames: [String: String?] = [:]

    @MainActor private static func resolvedName(for candidates: [String]) -> String? {
        let key = candidates.joined(separator: "|")
        if let cached = resolvedFontNames[key] {
            return cached
        }
        let found = candidates.first { UIFont(name: $0, size: 12) != nil }
        resolvedFontNames[key] = found
        return found
    }

    @MainActor private static func customFromCandidates(_ names: [String], size: CGFloat, relativeTo textStyle: Font.TextStyle) -> Font {
        if let name = resolvedName(for: names) {
            return .custom(name, size: size, relativeTo: textStyle)
        }
        return systemSerif(size, weight: .bold, relativeTo: textStyle)
    }

    @MainActor static func bigShouldersStencil(_ size: CGFloat, relativeTo textStyle: Font.TextStyle = .title) -> Font {
        customFromCandidates(["BigShouldersStencil", "Big Shoulders Stencil", "BigShouldersStencil-Variable"], size: size, relativeTo: textStyle)
    }
    @MainActor static func carterOne(_ size: CGFloat, relativeTo textStyle: Font.TextStyle = .title) -> Font {
        customFromCandidates(["CarterOne", "Carter One"], size: size, relativeTo: textStyle)
    }
    @MainActor static func tourney(_ size: CGFloat, relativeTo textStyle: Font.TextStyle = .title) -> Font {
        customFromCandidates(["Tourney", "Tourney-Italic", "Tourney Italic"], size: size, relativeTo: textStyle)
    }
    @MainActor static func unifrakturCook(_ size: CGFloat, relativeTo textStyle: Font.TextStyle = .title) -> Font {
        customFromCandidates(["UnifrakturCook-Bold", "Unifraktur Cook Bold"], size: size, relativeTo: textStyle)
    }
    @MainActor static func vastShadow(_ size: CGFloat, relativeTo textStyle: Font.TextStyle = .title) -> Font {
        customFromCandidates(["VastShadow-Regular", "Vast Shadow"], size: size, relativeTo: textStyle)
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
