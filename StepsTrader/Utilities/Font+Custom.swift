import SwiftUI
import UIKit

/// System fonts (SF) as app-wide typography.
extension Font {
    static func notoSerif(
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

    // MARK: - Ticket card title fonts (sticker-style). Tries several PostScript names so fonts load.
    private static func customFromCandidates(_ names: [String], size: CGFloat, relativeTo textStyle: Font.TextStyle) -> Font {
        for name in names {
            if UIFont(name: name, size: size) != nil {
                return .custom(name, size: size, relativeTo: textStyle)
            }
        }
        return .system(size: size, weight: .bold)
    }

    static func bigShouldersStencil(_ size: CGFloat, relativeTo textStyle: Font.TextStyle = .title) -> Font {
        customFromCandidates(["BigShouldersStencil", "Big Shoulders Stencil", "BigShouldersStencil-Variable"], size: size, relativeTo: textStyle)
    }
    static func carterOne(_ size: CGFloat, relativeTo textStyle: Font.TextStyle = .title) -> Font {
        customFromCandidates(["CarterOne", "Carter One"], size: size, relativeTo: textStyle)
    }
    static func tourney(_ size: CGFloat, relativeTo textStyle: Font.TextStyle = .title) -> Font {
        customFromCandidates(["Tourney", "Tourney-Italic", "Tourney Italic"], size: size, relativeTo: textStyle)
    }
    static func unifrakturCook(_ size: CGFloat, relativeTo textStyle: Font.TextStyle = .title) -> Font {
        customFromCandidates(["UnifrakturCook-Bold", "Unifraktur Cook Bold"], size: size, relativeTo: textStyle)
    }
    static func vastShadow(_ size: CGFloat, relativeTo textStyle: Font.TextStyle = .title) -> Font {
        customFromCandidates(["VastShadow-Regular", "Vast Shadow"], size: size, relativeTo: textStyle)
    }
}

/// AppFonts — алиасы для единообразия в коде.
enum AppFonts {
    // MARK: - Заголовки
    static let largeTitle = Font.largeTitle
    static let title = Font.title
    static let title2 = Font.title2
    static let title3 = Font.title3
    static let headline = Font.headline

    // MARK: - Основной текст
    static let body = Font.body
    static let subheadline = Font.subheadline
    static let caption = Font.caption
    static let caption2 = Font.caption2
}
