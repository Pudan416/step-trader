import SwiftUI
import UIKit

/// System fonts (SF) as app-wide typography.
extension Font {
    static func systemSerif(
        _ size: CGFloat,
        weight: Font.Weight = .regular,
        relativeTo textStyle: Font.TextStyle = .body
    ) -> Font {
        .system(size: size, weight: weight, design: .default)
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
        return .system(size: size, weight: .bold)
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
