import SwiftUI

/// Framed-dark poster: black background, canvas inset with white border,
/// "NOWHERE" overlapping the bottom of the canvas, metadata in white.
///
/// Figma source: 595 × 842
struct CanvasFramedDarkPoster<Content: View>: View {
    let content: Content
    let date: Date
    let userName: String?
    let steps: Int?
    let sleepHours: Double?
    let inkEarned: Int?
    var inkSpent: Int?

    init(
        date: Date,
        userName: String? = nil,
        steps: Int? = nil,
        sleepHours: Double? = nil,
        inkEarned: Int? = nil,
        inkSpent: Int? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.content = content()
        self.date = date
        self.userName = userName
        self.steps = steps
        self.sleepHours = sleepHours
        self.inkEarned = inkEarned
        self.inkSpent = inkSpent
    }

    // Figma 595 × 842 absolute coordinates → ratios
    private static var canvasLeftR: CGFloat   { 69.3 / 595.0 }
    private static var canvasTopR: CGFloat    { 86.0 / 842.0 }
    private static var canvasWR: CGFloat      { 456.47 / 595.0 }
    private static var canvasHR: CGFloat      { 662.109 / 842.0 }
    private static var borderR: CGFloat       { 5.0 / 595.0 }

    private static var nameSizeR: CGFloat     { 20.0 / 595.0 }
    private static var nameLeftR: CGFloat     { 15.0 / 595.0 }
    private static var nameTopR: CGFloat      { 22.0 / 842.0 }

    private static var statsSizeR: CGFloat    { 12.0 / 595.0 }
    private static var statsRightR: CGFloat   { 16.0 / 595.0 }
    private static var statsTopR: CGFloat     { 22.0 / 842.0 }

    private static var nowhereSizeR: CGFloat  { 70.0 / 595.0 }
    private static var nowhereLeftR: CGFloat  { 99.0 / 595.0 }
    private static var nowhereTopR: CGFloat   { 653.0 / 842.0 }

    private static var dateSizeR: CGFloat     { 12.0 / 595.0 }
    private static var dateLeftR: CGFloat     { 16.0 / 595.0 }
    private static var dateTopR: CGFloat      { 790.0 / 842.0 }

    private static var tagRightR: CGFloat     { 16.0 / 595.0 }
    private static var tagTopR: CGFloat       { 780.0 / 842.0 }

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height

            let cLeft = w * Self.canvasLeftR
            let cTop = h * Self.canvasTopR
            let cW = w * Self.canvasWR
            let cH = h * Self.canvasHR
            let bW = max(1, w * Self.borderR)

            ZStack {
                Color.black

                // Canvas with white border
                content
                    .frame(width: cW, height: cH)
                    .clipped()
                    .overlay(
                        Rectangle()
                            .strokeBorder(.white, lineWidth: bW)
                            .blendMode(.hardLight)
                    )
                    .position(x: cLeft + cW / 2, y: cTop + cH / 2)

                // User name — top-left, 20px New York Semibold
                if let name = userName, !name.isEmpty {
                    Text(name)
                        .font(.system(size: max(6, w * Self.nameSizeR), weight: .semibold, design: .serif))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                        .padding(.leading, w * Self.nameLeftR)
                        .padding(.top, h * Self.nameTopR)
                }

                // Stats — top-right, 12px SF Pro Regular
                statsView(fontSize: max(5, w * Self.statsSizeR))
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                    .padding(.trailing, w * Self.statsRightR)
                    .padding(.top, h * Self.statsTopR)

                // "NOWHERE" — overlapping bottom of canvas, 70px New York Black
                Text("NOWHERE")
                    .font(.system(size: max(10, w * Self.nowhereSizeR), weight: .black, design: .serif))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .padding(.leading, w * Self.nowhereLeftR)
                    .padding(.top, h * Self.nowhereTopR)

                // Date — bottom-left, 12px New York Regular Italic
                Text(formattedDate)
                    .font(.system(size: max(5, w * Self.dateSizeR), weight: .regular, design: .serif))
                    .italic()
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .padding(.leading, w * Self.dateLeftR)
                    .padding(.top, h * Self.dateTopR)

                // Tagline — bottom-right, two lines
                taglineView(fontSize: max(5, w * Self.dateSizeR))
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                    .padding(.trailing, w * Self.tagRightR)
                    .padding(.top, h * Self.tagTopR)
            }
            .frame(width: w, height: h)
        }
    }

    // MARK: - Stats

    @ViewBuilder
    private func statsView(fontSize: CGFloat) -> some View {
        VStack(alignment: .trailing, spacing: 1) {
            if (steps ?? 0) > 0 || (sleepHours ?? 0) > 0 {
                let parts = [
                    steps.map { "\(formatCompactNumber($0)) steps" },
                    sleepHours.map { String(format: "%.1f h. sleep", $0) }
                ].compactMap { $0 }
                Text(parts.joined(separator: " / "))
                    .font(.system(size: fontSize, weight: .regular))
                    .foregroundStyle(.white)
                    .lineLimit(1)
            }

            if (inkEarned ?? 0) > 0 || (inkSpent ?? 0) > 0 {
                let parts = [
                    inkEarned.map { "\($0) colors earned" },
                    inkSpent.flatMap { $0 > 0 ? "\($0) colors spent" : nil }
                ].compactMap { $0 }
                if !parts.isEmpty {
                    Text(parts.joined(separator: " / "))
                        .font(.system(size: fontSize, weight: .regular))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                }
            }
        }
    }

    // MARK: - Tagline

    private func taglineView(fontSize: CGFloat) -> some View {
        VStack(alignment: .trailing, spacing: 1) {
            Text("«Nowhere — Now Here» iOS app")
                .font(.system(size: fontSize, weight: .regular))
                .foregroundStyle(.white)
                .lineLimit(1)
            Text("by Kosta Pudan")
                .font(.system(size: fontSize, weight: .regular, design: .serif))
                .italic()
                .foregroundStyle(.white)
                .lineLimit(1)
        }
    }

    // MARK: - Date

    private var formattedDate: String {
        let cal = Calendar.current
        let y = cal.component(.year, from: date)
        let m = cal.component(.month, from: date)
        let d = cal.component(.day, from: date)
        return String(format: "%04d/%02d/%02d", y, m, d)
    }
}
