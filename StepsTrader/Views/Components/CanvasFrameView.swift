import SwiftUI

/// Museum-poster frame matching the Figma reference (604 × 842):
/// cream #F7F5EC background, "NOWHERE" top-left, date top-right,
/// thin separator lines, canvas inset in center with rotated tagline,
/// user name bottom-left, stats bottom-right.
struct CanvasFrameView<Content: View>: View {
    let content: Content
    let date: Date
    let userName: String?
    let steps: Int?
    let sleepHours: Double?
    let inkEarned: Int?
    var inkSpent: Int?
    var isCompact: Bool = false

    private let frameColor = Color(red: 0.969, green: 0.961, blue: 0.925) // #F7F5EC

    init(
        date: Date,
        userName: String? = nil,
        steps: Int? = nil,
        sleepHours: Double? = nil,
        inkEarned: Int? = nil,
        inkSpent: Int? = nil,
        borderFraction: CGFloat = 0.065,
        isCompact: Bool = false,
        @ViewBuilder content: () -> Content
    ) {
        self.content = content()
        self.date = date
        self.userName = userName
        self.steps = steps
        self.sleepHours = sleepHours
        self.inkEarned = inkEarned
        self.inkSpent = inkSpent
        self.isCompact = isCompact
    }

    // Figma 604 × 842: font sizes relative to width
    private static var brandSizeR: CGFloat   { 48.0 / 604.0 }
    private static var dateSizeR: CGFloat    { 20.0 / 604.0 }
    private static var nameSizeR: CGFloat    { 24.0 / 604.0 }
    private static var statsSizeR: CGFloat   { 12.0 / 604.0 }
    private static var taglineSizeR: CGFloat { 14.0 / 604.0 }

    // Vertical layout: Y positions as fractions of total height (842)
    private static var headerBottomR: CGFloat { 104.6 / 842.0 }
    private static var canvasTopR: CGFloat    { 114.09 / 842.0 }
    private static var canvasBotR: CGFloat    { 760.59 / 842.0 }
    private static var lineBottomR: CGFloat   { 770.96 / 842.0 }

    // Horizontal: side padding and canvas/line widths
    private static var sidePadR: CGFloat      { 39.0 / 604.0 }
    private static var lineLeftR: CGFloat     { 38.72 / 604.0 }
    private static var lineWidthR: CGFloat    { 527.02 / 604.0 }
    private static var canvasLeftR: CGFloat   { 65.86 / 604.0 }
    private static var canvasWidthR: CGFloat  { 472.286 / 604.0 }

    // Tagline X: just outside canvas right edge (538) with small gap
    private static var tagCenterXR: CGFloat   { 548.0 / 604.0 }
    private static var tagCenterYR: CGFloat   { 572.79 / 842.0 }
    private static var tagSpanR: CGFloat      { 335.58 / 842.0 }

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height

            let sidePad = w * Self.sidePadR
            let lineThickness = max(1, w * 0.004)
            let lineW = w * Self.lineWidthR
            let lineLeft = w * Self.lineLeftR

            let headerH = h * Self.headerBottomR
            let canvasTopGap = h * (Self.canvasTopR - Self.headerBottomR)
            let canvasH = h * (Self.canvasBotR - Self.canvasTopR)
            let canvasW = w * Self.canvasWidthR
            let canvasLeft = w * Self.canvasLeftR
            let botGap = h * (Self.lineBottomR - Self.canvasBotR)
            let footerH = h * (1.0 - Self.lineBottomR)

            ZStack {
                frameColor

                VStack(spacing: 0) {
                    // Header: date (big) + user name (small italic)
                    HStack(alignment: .lastTextBaseline) {
                        Text(formattedDate)
                            .font(.system(size: max(6, w * Self.brandSizeR), weight: .black, design: .serif))
                            .foregroundStyle(Color.black)
                            .lineLimit(1)

                        Spacer(minLength: 4)

                        if let name = userName, !name.isEmpty {
                            Text(name)
                                .font(.system(size: max(5, w * Self.dateSizeR), weight: .regular, design: .serif))
                                .italic()
                                .foregroundStyle(Color.black)
                                .lineLimit(1)
                        }
                    }
                    .padding(.horizontal, sidePad)
                    .frame(height: headerH, alignment: .bottom)
                    .padding(.bottom, 2)

                    // Top separator line
                    Rectangle()
                        .fill(Color.black)
                        .frame(width: lineW, height: lineThickness)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.leading, lineLeft)

                    // Gap between top line and canvas
                    Color.clear.frame(height: canvasTopGap)

                    // Canvas painting
                    content
                        .frame(width: canvasW, height: canvasH)
                        .clipped()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.leading, canvasLeft)

                    // Gap between canvas and bottom line
                    Color.clear.frame(height: botGap)

                    // Bottom separator line
                    Rectangle()
                        .fill(Color.black)
                        .frame(width: lineW, height: lineThickness)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.leading, lineLeft)

                    // Footer: NOWHERE + stats
                    HStack(alignment: .firstTextBaseline) {
                        Text("NOWHERE")
                            .font(.system(size: max(5, w * Self.nameSizeR), weight: .black, design: .serif))
                            .foregroundStyle(Color.black)
                            .lineLimit(1)
                            .minimumScaleFactor(0.5)

                        Spacer(minLength: 4)

                        statsBlock(fontSize: max(4, w * Self.statsSizeR))
                    }
                    .padding(.horizontal, sidePad)
                    .frame(height: footerH, alignment: .top)
                    .padding(.top, footerH * 0.15)
                }

                // Tagline — rotated 90° along right edge of canvas
                Text("«Nowhere» is an iOS app by Kosta Pudan")
                    .font(.system(size: max(4, w * Self.taglineSizeR), design: .serif))
                    .italic()
                    .foregroundStyle(Color.black)
                    .lineLimit(1)
                    .fixedSize()
                    .rotationEffect(.degrees(90))
                    .position(x: w * Self.tagCenterXR, y: h * Self.tagCenterYR)
            }
            .frame(width: w, height: h)
        }
    }

    // MARK: - Stats

    @ViewBuilder
    private func statsBlock(fontSize: CGFloat) -> some View {
        let hasAny = (steps ?? 0) > 0 || (sleepHours ?? 0) > 0 || (inkEarned ?? 0) > 0

        if hasAny {
            VStack(alignment: .trailing, spacing: 1) {
                if (steps ?? 0) > 0 || (sleepHours ?? 0) > 0 {
                    let parts = [
                        steps.map { "\(formatCompactNumber($0)) steps" },
                        sleepHours.map { "\($0.formatted(.number.precision(.fractionLength(1)))) h. sleep" }
                    ].compactMap { $0 }

                    Text(parts.joined(separator: " / "))
                        .font(.system(size: fontSize, weight: .medium))
                        .foregroundStyle(Color.black)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }

                if (inkEarned ?? 0) > 0 || (inkSpent ?? 0) > 0 {
                    let parts = [
                        inkEarned.map { "\($0) colors earned" },
                        inkSpent.flatMap { $0 > 0 ? "\($0) colors spent" : nil }
                    ].compactMap { $0 }

                    if !parts.isEmpty {
                        Text(parts.joined(separator: " / "))
                            .font(.system(size: fontSize, weight: .medium))
                            .foregroundStyle(Color.black)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                }
            }
        }
    }

    // MARK: - Date formatting

    private var formattedDate: String {
        let cal = Calendar.current
        let y = cal.component(.year, from: date) % 100
        let m = cal.component(.month, from: date)
        let d = cal.component(.day, from: date)
        return String(format: "%02d/%02d/%02d", d, m, y)
    }
}
