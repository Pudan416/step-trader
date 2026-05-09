import SwiftUI

// MARK: - Gradient-Tinted Asset View
// Takes a PNG asset, desaturates to grayscale, then overlays a gradient tint via blend.

enum GradientMode {
    case linear(Angle)
    case radial(center: UnitPoint)
}

struct GradientTintedAsset: View {
    let assetName: String
    let colors: [Color]
    var mode: GradientMode = .linear(.degrees(180))

    var body: some View {
        Image(assetName)
            .resizable()
            .scaledToFit()
            .saturation(0)
            .brightness(-0.15)
            .overlay(gradientView.blendMode(.color))
            .overlay(gradientView.blendMode(.overlay))
            .mask(Image(assetName).resizable().scaledToFit())
    }

    @ViewBuilder
    private var gradientView: some View {
        switch mode {
        case .linear(let angle):
            LinearGradient(
                colors: colors,
                startPoint: unitPoint(for: angle),
                endPoint: unitPoint(for: angle + .degrees(180))
            )
        case .radial(let center):
            GeometryReader { geo in
                let r = min(geo.size.width, geo.size.height) / 2
                RadialGradient(
                    gradient: Gradient(stops: gradientStops(radius: r)),
                    center: center,
                    startRadius: 0,
                    endRadius: r * 1.1
                )
            }
        }
    }

    private func gradientStops(radius: CGFloat) -> [Gradient.Stop] {
        switch colors.count {
        case 2:
            return [
                .init(color: colors[0], location: 0.0),
                .init(color: colors[1], location: 0.7),
            ]
        case 3:
            return [
                .init(color: colors[0], location: 0.0),
                .init(color: colors[1], location: 0.35),
                .init(color: colors[2], location: 0.75),
            ]
        default:
            return colors.enumerated().map { i, c in
                .init(color: c, location: Double(i) / Double(max(1, colors.count - 1)))
            }
        }
    }

    private func unitPoint(for angle: Angle) -> UnitPoint {
        let rad = angle.radians
        let x = 0.5 + 0.5 * cos(rad)
        let y = 0.5 + 0.5 * sin(rad)
        return UnitPoint(x: x, y: y)
    }
}

// MARK: - Gradient Palettes

// MARK: - Random Color Generator

enum RandomPalette {
    private static let warm: [Color] = [
        Color(red: 0.92, green: 0.78, blue: 0.42),
        Color(red: 0.90, green: 0.58, blue: 0.35),
        Color(red: 0.88, green: 0.48, blue: 0.55),
        Color(red: 0.82, green: 0.42, blue: 0.62),
        Color(red: 0.75, green: 0.35, blue: 0.48),
        Color(red: 0.90, green: 0.70, blue: 0.48),
        Color(red: 0.80, green: 0.52, blue: 0.60),
        Color(red: 0.88, green: 0.55, blue: 0.65),
        Color(red: 0.78, green: 0.85, blue: 0.55),
    ]

    private static let cool: [Color] = [
        Color(red: 0.62, green: 0.42, blue: 0.82),
        Color(red: 0.50, green: 0.42, blue: 0.85),
        Color(red: 0.40, green: 0.55, blue: 0.85),
        Color(red: 0.38, green: 0.65, blue: 0.82),
        Color(red: 0.38, green: 0.75, blue: 0.65),
        Color(red: 0.42, green: 0.78, blue: 0.55),
        Color(red: 0.48, green: 0.72, blue: 0.75),
        Color(red: 0.55, green: 0.75, blue: 0.48),
        Color(red: 0.40, green: 0.60, blue: 0.50),
    ]

    static func randomColors(seed: Int, count: Int = 3) -> [Color] {
        var rng = SeededRNG(seed: UInt64(seed))
        let outerIsWarm = rng.next() % 2 == 0
        let outerPool = shuffle(outerIsWarm ? warm : cool, rng: &rng)
        let centerPool = shuffle(outerIsWarm ? cool : warm, rng: &rng)

        if count == 2 {
            return [outerPool[0], centerPool[0]]
        }
        return [outerPool[0], centerPool[0], outerPool[1]]
    }

    private static func shuffle(_ array: [Color], rng: inout SeededRNG) -> [Color] {
        var a = array
        for i in stride(from: a.count - 1, through: 1, by: -1) {
            let j = Int(rng.next() % UInt64(i + 1))
            a.swapAt(i, j)
        }
        return a
    }
}

// MARK: - Procedural Body Blob

struct BodyBlobPreview: View {
    let seed: UInt64
    let colors: [Color]

    var body: some View {
        Canvas { ctx, size in
            let rect = CGRect(origin: .zero, size: size).insetBy(dx: 8, dy: 8)
            let path = ProceduralShapeGenerator.bodyPath(seed: seed, complexity: 0.5, time: 0, in: rect)
            let center = CGPoint(x: rect.midX, y: rect.midY)
            let radius = min(rect.width, rect.height) / 2

            let gradient = Gradient(colors: colors)
            ctx.fill(
                path,
                with: .radialGradient(gradient, center: center, startRadius: 0, endRadius: radius)
            )
            ctx.addFilter(.blur(radius: 4))
        }
    }
}

// MARK: - Preview

#Preview("Random Variety") {
    ScrollView {
        VStack(alignment: .leading, spacing: 24) {

            Text("Heart — Random")
                .font(.title3.bold())
                .padding(.horizontal)

            LazyVGrid(columns: [
                GridItem(.flexible(), spacing: 8),
                GridItem(.flexible(), spacing: 8),
                GridItem(.flexible(), spacing: 8),
            ], spacing: 12) {
                ForEach(0..<15, id: \.self) { i in
                    let colors = RandomPalette.randomColors(seed: i * 6271 + 1009, count: i % 3 == 0 ? 2 : 3)
                    VStack(spacing: 4) {
                        GradientTintedAsset(
                            assetName: "heart 1",
                            colors: colors,
                            mode: .linear(.degrees(180))
                        )
                        .frame(width: 100, height: 100)
                        Text("\(colors.count)c")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
            }
            .padding(.horizontal)

            Divider().padding(.horizontal)

            Text("Mind Filled — Random")
                .font(.title3.bold())
                .padding(.horizontal)

            LazyVGrid(columns: [
                GridItem(.flexible(), spacing: 8),
                GridItem(.flexible(), spacing: 8),
                GridItem(.flexible(), spacing: 8),
            ], spacing: 12) {
                ForEach(0..<15, id: \.self) { i in
                    let colors = RandomPalette.randomColors(seed: i * 7919 + 5381, count: 3)
                    VStack(spacing: 4) {
                        GradientTintedAsset(
                            assetName: "mind 1",
                            colors: colors,
                            mode: .radial(center: .init(x: 0.5, y: 0.7))
                        )
                        .frame(width: 100, height: 100)
                        Text("3c")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
            }
            .padding(.horizontal)

            Divider().padding(.horizontal)

            Text("Mind Ring — Random")
                .font(.title3.bold())
                .padding(.horizontal)

            LazyVGrid(columns: [
                GridItem(.flexible(), spacing: 8),
                GridItem(.flexible(), spacing: 8),
                GridItem(.flexible(), spacing: 8),
            ], spacing: 12) {
                ForEach(0..<15, id: \.self) { i in
                    let colors = RandomPalette.randomColors(seed: i * 6113 + 3571, count: 3)
                    VStack(spacing: 4) {
                        GradientTintedAsset(
                            assetName: "mind 14",
                            colors: colors,
                            mode: .radial(center: .init(x: 0.5, y: 0.7))
                        )
                        .frame(width: 100, height: 100)
                        Text("3c")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
            }
            .padding(.horizontal)
            Divider().padding(.horizontal)

            Text("Body — Random")
                .font(.title3.bold())
                .padding(.horizontal)

            LazyVGrid(columns: [
                GridItem(.flexible(), spacing: 8),
                GridItem(.flexible(), spacing: 8),
                GridItem(.flexible(), spacing: 8),
            ], spacing: 12) {
                ForEach(0..<15, id: \.self) { i in
                    let colors = RandomPalette.randomColors(seed: i * 4973 + 7307, count: i % 2 == 0 ? 2 : 3)
                    VStack(spacing: 4) {
                        BodyBlobPreview(
                            seed: UInt64(i * 31337 + 42),
                            colors: colors
                        )
                        .frame(width: 100, height: 100)
                        Text("\(colors.count)c")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
            }
            .padding(.horizontal)
        }
        .padding(.vertical)
    }
    .background(Color.black)
    .preferredColorScheme(.dark)
}
