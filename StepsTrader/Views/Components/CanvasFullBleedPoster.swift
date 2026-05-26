import SwiftUI

/// Full-bleed poster: canvas fills the entire frame, all metadata in white
/// overlaid on the painting.
///
/// Figma source: 595 × 842
struct CanvasFullBleedPoster<Content: View>: View {
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
    private static var nameSizeR: CGFloat     { 20.0 / 595.0 }
    private static var nameLeftR: CGFloat     { 17.0 / 595.0 }
    private static var nameTopR: CGFloat      { 19.0 / 842.0 }

    private static var statsSizeR: CGFloat    { 12.0 / 595.0 }
    private static var statsRightR: CGFloat   { 17.0 / 595.0 }
    private static var statsTopR: CGFloat     { 19.0 / 842.0 }

    private static var nowhereSizeR: CGFloat  { 96.0 / 595.0 }
    private static var nowhereLeftR: CGFloat  { 26.0 / 595.0 }
    private static var nowhereTopR: CGFloat   { 637.0 / 842.0 }

    private static var dateSizeR: CGFloat     { 12.0 / 595.0 }
    private static var dateLeftR: CGFloat     { 17.0 / 595.0 }
    private static var dateTopR: CGFloat      { 806.0 / 842.0 }

    private static var tagRightR: CGFloat     { 17.0 / 595.0 }
    private static var tagTopR: CGFloat       { 787.0 / 842.0 }

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height

            ZStack {
                // Full-bleed canvas
                content
                    .frame(width: w, height: h)
                    .clipped()

                // User name — top-left, 20px New York Semibold
                if let name = userName, !name.isEmpty {
                    Text(name)
                        .font(.system(size: max(6, w * Self.nameSizeR), weight: .semibold, design: .serif))
                        .foregroundStyle(.white)
                        .shadow(color: .black.opacity(0.5), radius: 4, y: 2)
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

                // Date — bottom area, 96px New York Black, centered
                Text(formattedDate)
                    .font(.system(size: max(10, w * Self.nowhereSizeR), weight: .black, design: .serif))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.5), radius: 6, y: 3)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    .padding(.top, h * Self.nowhereTopR)

                // "NOWHERE" — bottom-left, 12px New York Black
                Text("NOWHERE")
                    .font(.system(size: max(5, w * Self.dateSizeR), weight: .black, design: .serif))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.5), radius: 3, y: 1)
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
                    sleepHours.map { "\($0.formatted(.number.precision(.fractionLength(1)))) h. sleep" }
                ].compactMap { $0 }
                Text(parts.joined(separator: " / "))
                    .font(.system(size: fontSize, weight: .regular))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.5), radius: 3, y: 1)
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
                        .shadow(color: .black.opacity(0.5), radius: 3, y: 1)
                        .lineLimit(1)
                }
            }
        }
    }

    // MARK: - Tagline

    private func taglineView(fontSize: CGFloat) -> some View {
        VStack(alignment: .trailing, spacing: 1) {
            Text("«Nowhere» is an iOS app")
                .font(.system(size: fontSize, weight: .regular))
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.5), radius: 3, y: 1)
                .lineLimit(1)
            Text("by Kosta Pudan")
                .font(.system(size: fontSize, weight: .regular, design: .serif))
                .italic()
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.5), radius: 3, y: 1)
                .lineLimit(1)
        }
    }

    // MARK: - Date

    private var formattedDate: String {
        let cal = Calendar.current
        let y = cal.component(.year, from: date) % 100
        let m = cal.component(.month, from: date)
        let d = cal.component(.day, from: date)
        return String(format: "%02d/%02d/%02d", d, m, y)
    }
}

#Preview {
    CanvasFullBleedPoster(
        date: Date.now,
        userName: "Kosta",
        steps: 8432,
        sleepHours: 7.5,
        inkEarned: 72,
        inkSpent: 15
    ) {
        LinearGradient(
            colors: [.purple, .blue, .cyan],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
    .frame(width: 300, height: 424)
}
