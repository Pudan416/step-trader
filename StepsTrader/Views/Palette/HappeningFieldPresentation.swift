import SwiftUI
import UIKit

enum HappeningFieldPhase: Equatable {
    case idle
    case previewing
    case committing
    case reflowing
}

enum HappeningFieldTapDecision: Equatable {
    case preview
    case switchPreview(previousID: String)
    case commit
    case ignored
}

struct HappeningFieldTransitionState: Equatable {
    private(set) var phase: HappeningFieldPhase = .idle
    private(set) var selectedID: String?

    mutating func handleTap(id: String) -> HappeningFieldTapDecision {
        switch phase {
        case .idle:
            selectedID = id
            phase = .previewing
            return .preview
        case .previewing:
            if selectedID == id {
                phase = .committing
                return .commit
            }
            let previousID = selectedID
            selectedID = id
            return previousID.map(HappeningFieldTapDecision.switchPreview(previousID:)) ?? .preview
        case .committing, .reflowing:
            return .ignored
        }
    }

    var isInteractionLocked: Bool {
        phase == .committing || phase == .reflowing
    }

    mutating func resolveCommit(id: String, accepted: Bool) -> Bool {
        guard phase == .committing, selectedID == id else { return false }
        guard accepted else {
            phase = .previewing
            return false
        }
        phase = .reflowing
        return true
    }

    mutating func finishCommit(id: String) -> Bool {
        guard phase == .reflowing, selectedID == id else { return false }
        phase = .idle
        selectedID = nil
        return true
    }

    mutating func cancelSelection() {
        phase = .idle
        selectedID = nil
    }
}

/// Session presentation state shared by the field and its surrounding controls.
/// Parent updates refresh metadata, while ids consumed in this mounted session
/// stay consumed even if `onPick` synchronously republishes its old array.
struct HappeningFieldPresentationState: Equatable {
    private(set) var slotHappenings: [Happening]
    private(set) var presentedHappenings: [Happening]

    private var sessionRemovedIDs: Set<String> = []
    private var pendingParentHappenings: [Happening]?

    init(happenings: [Happening]) {
        let initial = Array(happenings.prefix(10))
        slotHappenings = initial
        presentedHappenings = initial
    }

    var presentedCount: Int {
        presentedHappenings.count
    }

    func layout(
        in size: CGSize,
        safeInsets: EdgeInsets,
        dynamicTypeSize: DynamicTypeSize = .large,
        contentTopInset: CGFloat? = nil,
        dockCenterY: CGFloat? = nil
    ) -> HappeningFieldLayout.Layout {
        HappeningFieldLayout.layout(
            count: presentedCount,
            in: size,
            safeInsets: safeInsets,
            dynamicTypeSize: dynamicTypeSize,
            contentTopInset: contentTopInset,
            dockCenterY: dockCenterY
        )
    }

    mutating func remove(id: String) -> Bool {
        guard presentedHappenings.contains(where: { $0.id == id }) else { return false }
        sessionRemovedIDs.insert(id)
        presentedHappenings.removeAll { $0.id == id }
        return true
    }

    mutating func receiveParent(_ happenings: [Happening], whileTransitioning: Bool) {
        if whileTransitioning {
            pendingParentHappenings = happenings
        } else {
            mergeParent(happenings)
        }
    }

    mutating func finishTransition() {
        guard let pendingParentHappenings else { return }
        self.pendingParentHappenings = nil
        mergeParent(pendingParentHappenings)
    }

    mutating func reset(with happenings: [Happening]) {
        let initial = Array(happenings.prefix(10))
        slotHappenings = initial
        presentedHappenings = initial
        sessionRemovedIDs.removeAll()
        pendingParentHappenings = nil
    }

    private mutating func mergeParent(_ happenings: [Happening]) {
        let removedIDs = sessionRemovedIDs
        let eligible = Array(
            happenings
                .filter { !removedIDs.contains($0.id) }
                .prefix(10)
        )
        let replacements = Dictionary(uniqueKeysWithValues: happenings.map { ($0.id, $0) })

        slotHappenings = slotHappenings.map { replacements[$0.id] ?? $0 }
        var slotIDs = Set(slotHappenings.map(\.id))
        for happening in eligible where slotIDs.insert(happening.id).inserted {
            slotHappenings.append(happening)
        }
        presentedHappenings = eligible
    }
}

struct HappeningFieldLabelTreatment: Equatable {
    enum Foreground: Equatable {
        case black
        case white
    }

    static let primaryWeight = 0.72
    static let accentWeight = 0.28
    static let fieldZoneOpacity = 0.74

    let red: Double
    let green: Double
    let blue: Double
    let backingLuminance: Double
    let fieldZoneLuminance: Double
    let foreground: Foreground

    init(primaryHex: String, accentHex: String) {
        let primary = Self.rgb(ofHex: primaryHex)
        let accent = Self.rgb(ofHex: accentHex)
        red = Self.primaryWeight * primary.red + Self.accentWeight * accent.red
        green = Self.primaryWeight * primary.green + Self.accentWeight * accent.green
        blue = Self.primaryWeight * primary.blue + Self.accentWeight * accent.blue
        backingLuminance = Self.relativeLuminance(red: red, green: green, blue: blue)
        fieldZoneLuminance = Self.relativeLuminance(
            red: Self.fieldZoneOpacity * red + (1 - Self.fieldZoneOpacity) * primary.red,
            green: Self.fieldZoneOpacity * green + (1 - Self.fieldZoneOpacity) * primary.green,
            blue: Self.fieldZoneOpacity * blue + (1 - Self.fieldZoneOpacity) * primary.blue
        )

        // Every circle is deliberately lifted into a bright, milky color zone,
        // so one dark ink treatment stays coherent across the whole field.
        foreground = .black
    }

    var backingColor: Color {
        Color(.sRGB, red: red, green: green, blue: blue, opacity: 1)
    }

    var fieldZoneColor: Color { backingColor }

    var fieldZoneOpacity: Double { Self.fieldZoneOpacity }

    /// Keeps the shared dark ink readable without washing out every circle.
    /// Only low-luminance color pairs receive the minimum milky lift needed
    /// to reach 4.5:1 against the actual 90%-opaque ink used by the labels.
    var circleLiftOpacity: Double {
        var lift = 0.08
        while lift < 0.60, contrastRatio(afterWhiteLift: lift) < 4.5 {
            lift += 0.01
        }
        return min(lift, 0.60)
    }

    var liftedCircleContrastRatio: Double {
        contrastRatio(afterWhiteLift: circleLiftOpacity)
    }

    /// The radial zone uses the same local two-color mix as the field source.
    /// Its soft edge is translucent; this center value models the pixels under
    /// the glyphs instead of the removed opaque ellipse.
    var fieldZoneContrastRatio: Double {
        let textLuminance = foreground == .black ? 0.0 : 1.0
        return (max(fieldZoneLuminance, textLuminance) + 0.05)
            / (min(fieldZoneLuminance, textLuminance) + 0.05)
    }

    var foregroundColor: Color {
        foreground == .black ? .black : .white
    }

    static func inscribedTextSize(in labelSize: CGSize) -> CGSize {
        // Words are allowed to breathe beyond their independent tap frames.
        // This keeps the longest 15-character title intact without enlarging
        // or overlapping the actual hit regions used by the dense layout.
        CGSize(width: labelSize.width * 0.88, height: labelSize.height * 0.82)
    }

    static func relativeLuminance(ofHex hex: String) -> Double {
        let color = rgb(ofHex: hex)
        return relativeLuminance(red: color.red, green: color.green, blue: color.blue)
    }

    private static func rgb(ofHex hex: String) -> (red: Double, green: Double, blue: Double) {
        var raw = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if raw.hasPrefix("#") { raw.removeFirst() }
        guard raw.count == 6, let value = UInt32(raw, radix: 16) else {
            return (1, 1, 1)
        }
        return (
            Double((value >> 16) & 0xFF) / 255,
            Double((value >> 8) & 0xFF) / 255,
            Double(value & 0xFF) / 255
        )
    }

    private static func relativeLuminance(red: Double, green: Double, blue: Double) -> Double {
        func linear(_ channel: Double) -> Double {
            channel <= 0.03928
                ? channel / 12.92
                : pow((channel + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linear(red) + 0.7152 * linear(green) + 0.0722 * linear(blue)
    }

    private func contrastRatio(afterWhiteLift lift: Double) -> Double {
        let backgroundRed = red * (1 - lift) + lift
        let backgroundGreen = green * (1 - lift) + lift
        let backgroundBlue = blue * (1 - lift) + lift
        let backgroundLuminance = Self.relativeLuminance(
            red: backgroundRed,
            green: backgroundGreen,
            blue: backgroundBlue
        )

        let inkOpacity = 0.90
        let inkRed = 16.0 / 255.0
        let inkGreen = 45.0 / 255.0
        let inkBlue = 44.0 / 255.0
        let textLuminance = Self.relativeLuminance(
            red: inkRed * inkOpacity + backgroundRed * (1 - inkOpacity),
            green: inkGreen * inkOpacity + backgroundGreen * (1 - inkOpacity),
            blue: inkBlue * inkOpacity + backgroundBlue * (1 - inkOpacity)
        )
        return (max(backgroundLuminance, textLuminance) + 0.05)
            / (min(backgroundLuminance, textLuminance) + 0.05)
    }
}

enum HappeningFieldLabelTypography {
    static let pointSize: CGFloat = 13

    static func maximumLines(for dynamicTypeSize: DynamicTypeSize) -> Int {
        dynamicTypeSize.isAccessibilitySize ? 4 : 2
    }

    static func minimumScaleFactor(for _: DynamicTypeSize) -> CGFloat {
        1
    }

    static func scaledUIFont(for dynamicTypeSize: DynamicTypeSize) -> UIFont {
        AppTypography.scaledUIFont(
            size: pointSize,
            weight: .semibold,
            relativeTo: .footnote,
            compatibleWith: UITraitCollection(
                preferredContentSizeCategory: contentSizeCategory(for: dynamicTypeSize)
            )
        )
    }

    private static func contentSizeCategory(
        for dynamicTypeSize: DynamicTypeSize
    ) -> UIContentSizeCategory {
        switch dynamicTypeSize {
        case .xSmall: .extraSmall
        case .small: .small
        case .medium: .medium
        case .large: .large
        case .xLarge: .extraLarge
        case .xxLarge: .extraExtraLarge
        case .xxxLarge: .extraExtraExtraLarge
        case .accessibility1: .accessibilityMedium
        case .accessibility2: .accessibilityLarge
        case .accessibility3: .accessibilityExtraLarge
        case .accessibility4: .accessibilityExtraExtraLarge
        case .accessibility5: .accessibilityExtraExtraExtraLarge
        @unknown default: .large
        }
    }
}

enum HappeningFieldContourHitRegion {
    /// Covers the seven-point luminance blur plus antialiasing at the rendered
    /// contour edge. `strokedPath` expands by half its line width.
    private static let haloOutset: CGFloat = 12

    static func path(
        sources: [HappeningFieldLayout.Source],
        in rect: CGRect
    ) -> Path {
        expandedContour(sources: sources, in: rect)
    }

    static func path(
        currentSources: [HappeningFieldLayout.Source],
        transitionSources: [HappeningFieldLayout.Source],
        in rect: CGRect
    ) -> Path {
        guard !transitionSources.isEmpty else {
            return expandedContour(sources: currentSources, in: rect)
        }

        var hitRegion = Path()
        let interpolationSteps = 4
        for step in 0...interpolationSteps {
            let progress = CGFloat(step) / CGFloat(interpolationSteps)
            let sourceCount = max(currentSources.count, transitionSources.count)
            let sources = (0..<sourceCount).compactMap { index -> HappeningFieldLayout.Source? in
                let oldSource = index < transitionSources.count ? transitionSources[index] : nil
                let newSource = index < currentSources.count ? currentSources[index] : nil
                guard let old = oldSource ?? newSource else { return nil }
                let new = newSource ?? old
                return HappeningFieldLayout.Source(
                    index: index,
                    center: CGPoint(
                        x: old.center.x + (new.center.x - old.center.x) * progress,
                        y: old.center.y + (new.center.y - old.center.y) * progress
                    ),
                    radius: old.radius + (new.radius - old.radius) * progress
                )
            }
            hitRegion.addPath(expandedContour(sources: sources, in: rect))
        }
        return hitRegion
    }

    private static func expandedContour(
        sources: [HappeningFieldLayout.Source],
        in rect: CGRect
    ) -> Path {
        let contour = ProceduralShapeGenerator.metaballPath(
            blobs: sources.map {
                ProceduralShapeGenerator.BlobSource(
                    center: $0.center,
                    radius: $0.radius
                )
            },
            in: rect,
            gridResolution: 58
        )
        var hitRegion = contour
        hitRegion.addPath(
            contour.strokedPath(
                StrokeStyle(
                    lineWidth: haloOutset * 2,
                    lineCap: .round,
                    lineJoin: .round
                )
            )
        )
        return hitRegion
    }
}

struct HappeningFieldRemovalStart {
    let happening: Happening
    let source: HappeningFieldLayout.Source
    let transitionSources: [HappeningFieldLayout.Source]
}

enum HappeningFieldRemovalResolver {
    static func resolve(
        id: String,
        presentation: HappeningFieldPresentationState,
        size: CGSize,
        safeInsets: EdgeInsets,
        dynamicTypeSize: DynamicTypeSize
    ) -> HappeningFieldRemovalStart? {
        guard let index = presentation.presentedHappenings.firstIndex(where: { $0.id == id }) else {
            return nil
        }
        let layout = presentation.layout(
            in: size,
            safeInsets: safeInsets,
            dynamicTypeSize: dynamicTypeSize
        )
        guard index < layout.sources.count else { return nil }
        return HappeningFieldRemovalStart(
            happening: presentation.presentedHappenings[index],
            source: layout.sources[index],
            transitionSources: layout.sources
        )
    }
}

/// Native, transparent renderer for the palette's Living island.
///
/// Domain state changes at breakthrough through `onPick`; the field and parent
/// share session presentation state while surviving sources reflow to the next
/// deterministic layout.
