import SwiftUI

/// Bench for the ray generator.
///
/// The grid is the point of it. One pretty frame proves nothing about a
/// generative system — the question is whether thirty seeds give thirty
/// pictures that are clearly different yet clearly one family, and that is
/// only answerable when you see them side by side.
struct DayRaysLabView: View {
    @State private var dayOffset = 0
    @State private var happenings: Double = 5
    @State private var showsGrid = false
    @State private var showControls = true

    private var dayKey: String {
        // Synthetic keys: the lab explores the space, it does not report today.
        String(format: "2026-%02d-%02d", (dayOffset / 28) % 12 + 1, dayOffset % 28 + 1)
    }

    private var composition: DayRayComposition {
        DayRayComposition.forDay(dayKey: dayKey)
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            if showsGrid {
                grid
            } else {
                DayRaysView(
                    composition: composition,
                    happeningCount: Int(happenings),
                    dayKey: dayKey
                )
                .ignoresSafeArea()
            }

            if showControls {
                controls.transition(.move(edge: .bottom).combined(with: .opacity))
            }
            toggleButton
        }
        .animation(.easeInOut(duration: 0.2), value: showControls)
        .navigationTitle("Day Rays")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
    }

    // MARK: - Grid

    private var grid: some View {
        GeometryReader { geo in
            let columns = 3
            let rows = 5
            let w = geo.size.width / CGFloat(columns)
            let h = geo.size.height / CGFloat(rows)

            VStack(spacing: 0) {
                ForEach(0..<rows, id: \.self) { row in
                    HStack(spacing: 0) {
                        ForEach(0..<columns, id: \.self) { column in
                            let index = dayOffset + row * columns + column
                            let key = String(format: "2026-%02d-%02d",
                                             (index / 28) % 12 + 1, index % 28 + 1)
                            DayRaysView(
                                composition: DayRayComposition.forDay(dayKey: key),
                                happeningCount: Int(happenings),
                                dayKey: key,
                                // Fifteen animated shader passes at once tells
                                // you about the GPU, not about the design.
                                isAnimating: false
                            )
                            .frame(width: w, height: h)
                            .clipped()
                        }
                    }
                }
            }
        }
        .ignoresSafeArea()
    }

    // MARK: - Controls

    private var controls: some View {
        VStack(spacing: 12) {
            HStack(spacing: 10) {
                Button {
                    dayOffset += showsGrid ? 15 : 1
                } label: {
                    Label(showsGrid ? "Next 15" : "Next day", systemImage: "dice")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)

                Button {
                    showsGrid.toggle()
                } label: {
                    Label(showsGrid ? "Single" : "Grid", systemImage: "square.grid.3x3")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }

            VStack(spacing: 2) {
                HStack {
                    Text("Happenings").font(.geist(.caption))
                    Spacer()
                    Text("\(Int(happenings))").font(.geist(.caption).monospacedDigit())
                }
                .foregroundStyle(.white.opacity(0.85))
                Slider(value: $happenings, in: 0...10, step: 1)
            }

            if !showsGrid {
                Text(composition.summary)
                    .font(.geist(.caption2).monospaced())
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.white.opacity(0.6))
            }
        }
        .padding(16)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 22))
        .padding(.horizontal, 12)
        .padding(.bottom, 60)
        .tint(AppColors.brandAccent)
    }

    private var toggleButton: some View {
        VStack {
            HStack {
                Spacer()
                Button {
                    showControls.toggle()
                } label: {
                    Image(systemName: showControls ? "slider.horizontal.3" : "eye")
                        .padding(10)
                        .background(.ultraThinMaterial, in: Circle())
                }
                .tint(.white)
                .padding(.trailing, 16)
            }
            Spacer()
        }
    }
}

#Preview {
    NavigationStack { DayRaysLabView() }
}
