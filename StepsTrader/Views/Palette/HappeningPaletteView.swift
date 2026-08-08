import SwiftUI

/// The palette. Tap a blob and the happening lands on the canvas immediately;
/// tap the `+` node to type a new one, which lands in the same action.
///
/// No categories anywhere in this flow — that is the point of the whole change.
///
/// Takes `[Happening]` and callbacks rather than an `AppModel`, so it can be
/// previewed and reasoned about on its own, and so it does not depend on the
/// additions rewrite landing first.
///
/// Styled well enough to ship. It gets restyled onto the token system in the
/// foundation spec; do not build a token system here.
struct HappeningPaletteView: View {

    /// Already ordered — the caller resolves the frozen daily order.
    let happenings: [Happening]
    let onPick: (Happening) -> Void
    let onCreate: (String) -> Void

    /// Seeds the blob shapes. The caller passes today's `dayKey` so a blob keeps
    /// its silhouette for as long as the frozen order holds.
    let dayKey: String

    @Environment(\.dismiss) private var dismiss
    @State private var isTypingNew = false
    @State private var draftTitle = ""

    /// One palette color per position. Keyed by index rather than by id so the
    /// cluster keeps a stable spread of colors as the order changes day to day.
    private func hex(at index: Int) -> String {
        let hexes = CanvasColorPalette.paletteHex
        guard !hexes.isEmpty else { return AppColors.goldFallbackHex }
        return hexes[index % hexes.count]
    }

    /// Relative luminance (WCAG), 0 = black, 1 = white.
    static func relativeLuminance(ofHex hex: String) -> Double {
        var raw = hex.trimmingCharacters(in: .whitespaces)
        if raw.hasPrefix("#") { raw.removeFirst() }
        guard raw.count == 6, let value = UInt32(raw, radix: 16) else { return 1 }

        func linear(_ channel: Double) -> Double {
            channel <= 0.03928 ? channel / 12.92 : pow((channel + 0.055) / 1.055, 2.4)
        }
        let r = linear(Double((value >> 16) & 0xFF) / 255)
        let g = linear(Double((value >> 8) & 0xFF) / 255)
        let b = linear(Double(value & 0xFF) / 255)
        return 0.2126 * r + 0.7152 * g + 0.0722 * b
    }

    /// The reference asks for dark labels set on the shapes, and that is the
    /// default. But the palette carries deep jewel tones (`#0E3A6E`, `#6E1A2E`)
    /// where dark-on-dark is unreadable, so those flip to light.
    static func labelColor(onHex hex: String) -> Color {
        relativeLuminance(ofHex: hex) < 0.22
            ? .white.opacity(0.92)
            : .black.opacity(0.8)
    }

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            // The `+` node occupies the slot after the last happening, so the
            // layout treats it as one more blob in the same cluster.
            let all = HappeningBlobLayout.blobs(count: happenings.count + 1, in: size)
            let height = HappeningBlobLayout.contentHeight(count: happenings.count + 1, in: size)

            ScrollView {
                ZStack(alignment: .topLeading) {
                    mergedContour(blobs: all, in: CGSize(width: size.width, height: height))

                    ForEach(Array(happenings.enumerated()), id: \.element.id) { index, happening in
                        if index < all.count {
                            blobNode(blob: all[index], happening: happening)
                        }
                    }

                    if let plus = all.last {
                        plusNode(blob: plus)
                    }
                }
                .frame(width: size.width, height: height, alignment: .topLeading)
            }
            .scrollIndicators(.hidden)
        }
        .safeAreaInset(edge: .bottom) {
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 17, weight: .medium))
                    .frame(width: 44, height: 44)
            }
            .accessibilityLabel(Text("Close", comment: "Palette close button"))
            .padding(.bottom, 12)
        }
        .presentationDetents([.large])
    }

    /// One merged contour behind everything, so neighbours read as a single
    /// organic cluster rather than a column of separate circles.
    private func mergedContour(blobs: [HappeningBlobLayout.Blob], in rect: CGSize) -> some View {
        ProceduralShapeGenerator.metaballPath(
            blobs: blobs.map {
                ProceduralShapeGenerator.BlobSource(center: $0.center, radius: $0.radius)
            },
            in: CGRect(origin: .zero, size: rect)
        )
        .fill(.white.opacity(0.06))
        .allowsHitTesting(false)
    }

    private func blobNode(blob: HappeningBlobLayout.Blob, happening: Happening) -> some View {
        let tintHex = hex(at: blob.index)
        let tint = Color(hex: tintHex)
        let diameter = blob.radius * 2

        return ZStack {
            ProceduralShapeGenerator.organicBlobPath(
                seed: CanvasElement.makeSeed(
                    optionId: happening.id, dayKey: dayKey, index: blob.index
                ),
                complexity: 0.45,
                in: CGRect(x: 0, y: 0, width: diameter, height: diameter)
            )
            .fill(
                RadialGradient(
                    colors: [tint.opacity(0.95), tint.opacity(0.55)],
                    center: .center, startRadius: 0, endRadius: blob.radius
                )
            )

            Text(happening.localizedTitle())
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundStyle(Self.labelColor(onHex: tintHex))
                .multilineTextAlignment(.center)
                .minimumScaleFactor(0.6)
                .lineLimit(3)
                .frame(width: blob.radius * 1.5)
        }
        .frame(width: diameter, height: diameter)
        .position(blob.center)
        .contentShape(Circle())
        .onTapGesture {
            onPick(happening)
            dismiss()
        }
        .accessibilityElement(children: .ignore)
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel(happening.localizedTitle())
    }

    private func plusNode(blob: HappeningBlobLayout.Blob) -> some View {
        let diameter = blob.radius * 2

        return ZStack {
            Circle()
                .strokeBorder(
                    .white.opacity(0.35),
                    style: StrokeStyle(lineWidth: 1.5, dash: [4, 4])
                )

            if isTypingNew {
                HappeningFreeTextField(text: $draftTitle) { title in
                    onCreate(title)
                    draftTitle = ""
                    isTypingNew = false
                    dismiss()
                }
                .frame(width: blob.radius * 1.6)
            } else {
                Image(systemName: "plus")
                    .font(.system(size: 22, weight: .light))
                    .foregroundStyle(.white.opacity(0.75))
            }
        }
        .frame(width: diameter, height: diameter)
        .position(blob.center)
        .contentShape(Circle())
        .onTapGesture { isTypingNew = true }
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel(Text("Add a happening", comment: "Palette free-text node"))
    }
}

#Preview {
    HappeningPaletteView(
        happenings: HappeningDefaults.builtIns,
        onPick: { _ in },
        onCreate: { _ in },
        dayKey: "2026-08-08"
    )
    .background(Color.black)
}
