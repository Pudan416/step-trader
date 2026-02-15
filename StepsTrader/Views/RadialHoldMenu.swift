import SwiftUI

// MARK: - Liquid Dots (organic, slowly drifting cluster)

/// Organic cluster of dots that drift like particles in liquid.
/// Each dot has its own slow orbit so the cluster breathes and flows.
struct LiquidDotsView: View {
    var color: Color = .white
    var dotCount: Int = 48
    var clusterRadius: CGFloat = 32

    // Pre-computed stable base positions (deterministic)
    private struct DotSeed {
        let baseX: CGFloat
        let baseY: CGFloat
        let orbitRx: CGFloat
        let orbitRy: CGFloat
        let speed: Double
        let phase: Double
        let baseSize: CGFloat
    }

    private let seeds: [DotSeed]

    init(color: Color = .white, dotCount: Int = 48, clusterRadius: CGFloat = 32) {
        self.color = color
        self.dotCount = dotCount
        self.clusterRadius = clusterRadius
        var s: [DotSeed] = []
        var rng: UInt64 = 42
        for _ in 0..<dotCount {
            rng = rng &* 6364136223846793005 &+ 1
            let u = CGFloat((rng >> 16) & 0xFFFF) / 65535.0
            rng = rng &* 6364136223846793005 &+ 1
            let v = CGFloat((rng >> 16) & 0xFFFF) / 65535.0
            rng = rng &* 6364136223846793005 &+ 1
            let w = CGFloat((rng >> 16) & 0xFFFF) / 65535.0
            let r = clusterRadius * (0.08 + 0.92 * sqrt(u))
            let theta = 2 * .pi * v
            let bx = r * cos(theta)
            let by = r * sin(theta)
            let orbitR = 2.0 + w * 5.0
            rng = rng &* 6364136223846793005 &+ 1
            let sp = 0.3 + Double((rng >> 16) & 0xFFFF) / 65535.0 * 0.7
            rng = rng &* 6364136223846793005 &+ 1
            let ph = Double((rng >> 16) & 0xFFFF) / 65535.0 * 2 * .pi
            let sz: CGFloat = 1.8 + (1.0 - sqrt(u)) * 2.5
            s.append(DotSeed(baseX: bx, baseY: by, orbitRx: orbitR, orbitRy: orbitR * 0.7, speed: sp, phase: ph, baseSize: sz))
        }
        self.seeds = s
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate

            Canvas { context, size in
                let cx = size.width / 2
                let cy = size.height / 2

                for dot in seeds {
                    let angle = t * dot.speed + dot.phase
                    let dx = cos(angle) * dot.orbitRx
                    let dy = sin(angle) * dot.orbitRy
                    let x = cx + dot.baseX + dx
                    let y = cy + dot.baseY + dy

                    let dist = sqrt((x - cx) * (x - cx) + (y - cy) * (y - cy))
                    let norm = min(1.0, dist / clusterRadius)
                    let pulse = 0.75 + 0.25 * sin(t * 1.8 + dot.phase)
                    let opacity = (1.0 - norm * norm) * pulse
                    let sz = dot.baseSize * (0.85 + 0.15 * sin(t * 2.0 + dot.phase * 1.3))

                    let rect = CGRect(x: x - sz / 2, y: y - sz / 2, width: sz, height: sz)
                    context.fill(
                        Circle().path(in: rect),
                        with: .color(color.opacity(opacity * 0.9))
                    )
                }
            }
            .allowsHitTesting(false)
        }
        .frame(width: clusterRadius * 2.4, height: clusterRadius * 2.4)
    }
}

// MARK: - Radial Hold Menu (tap to fan, or long-press+drag)

/// Tap shows 3 category buttons (Body / Mind / Heart) in a fan arc.
/// Long-press + drag also works: nodes appear and you can drag to select.
struct RadialHoldMenu: View {
    var labelColor: Color = .white
    let onCategorySelected: (EnergyCategory) -> Void

    @State private var isFanOpen = false
    @GestureState private var dragOffset: CGSize = .zero
    @State private var isHolding = false
    @State private var hoveredCategory: EnergyCategory? = nil

    private let nodes: [(category: EnergyCategory, label: String, icon: String, angle: Double)] = [
        (.body,   "Body",  "figure.walk",       135),  // upper-left
        (.heart,       "Heart", "heart.fill",         90),  // straight up
        (.mind, "Mind",  "brain.head.profile", 45),  // upper-right
    ]

    private let fanRadius: CGFloat = 80
    private let activationDistance: CGFloat = 55
    private let hapticMedium = UIImpactFeedbackGenerator(style: .medium)
    private let hapticLight = UIImpactFeedbackGenerator(style: .light)

    private func nodeOffset(angleDeg: Double) -> CGSize {
        let rad = angleDeg * .pi / 180
        return CGSize(width: cos(rad) * fanRadius, height: -sin(rad) * fanRadius)
    }

    var body: some View {
        ZStack {
            // Category nodes — visible in either fan-tap mode or hold-drag mode
            if isFanOpen || isHolding {
                ForEach(nodes, id: \.category) { node in
                    let offset = nodeOffset(angleDeg: node.angle)
                    categoryNode(
                        label: node.label,
                        icon: node.icon,
                        category: node.category,
                        isHovered: hoveredCategory == node.category,
                        offset: offset
                    )
                }
                .transition(.scale.combined(with: .opacity))
            }

            // + button with liquid dots
            plusButton
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.7), value: isFanOpen)
        .animation(.spring(response: 0.35, dampingFraction: 0.7), value: isHolding)
        .animation(.spring(response: 0.25, dampingFraction: 0.8), value: hoveredCategory)
    }

    // MARK: - Plus Button

    private var plusButton: some View {
        let holdAndDrag = LongPressGesture(minimumDuration: 0.3)
            .sequenced(before: DragGesture(minimumDistance: 0, coordinateSpace: .local))
            .updating($dragOffset) { value, state, _ in
                if case .second(true, let drag?) = value {
                    state = drag.translation
                }
            }
            .onChanged { value in
                if case .second(true, let drag) = value {
                    if !isHolding {
                        isFanOpen = false
                        isHolding = true
                        hapticMedium.impactOccurred()
                    }
                    if let drag = drag {
                        updateHoveredCategory(from: drag.translation)
                    }
                }
            }
            .onEnded { _ in
                if let category = hoveredCategory {
                    hapticMedium.impactOccurred()
                    onCategorySelected(category)
                }
                isHolding = false
                hoveredCategory = nil
            }

        let isActive = isFanOpen || isHolding

        return ZStack {
            Circle()
                .strokeBorder(labelColor.opacity(isActive ? 0.3 : 0.15), lineWidth: 1)
                .frame(width: 56, height: 56)

            Image(systemName: isActive ? "xmark" : "plus")
                .font(.system(size: 22, weight: .ultraLight))
                .foregroundStyle(labelColor.opacity(isActive ? 0.5 : 0.7))
                .rotationEffect(.degrees(isFanOpen ? 45 : 0))
        }
        .contentShape(Circle().size(width: 72, height: 72))
        .gesture(holdAndDrag)
        .simultaneousGesture(
            TapGesture().onEnded {
                hapticLight.impactOccurred()
                if isFanOpen {
                    isFanOpen = false
                } else {
                    isFanOpen = true
                }
            }
        )
    }

    // MARK: - Category Node

    private func categoryNode(
        label: String,
        icon: String,
        category: EnergyCategory,
        isHovered: Bool,
        offset: CGSize
    ) -> some View {
        Button {
            if isFanOpen {
                hapticMedium.impactOccurred()
                onCategorySelected(category)
                isFanOpen = false
            }
        } label: {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: isHovered ? 20 : 16, weight: .regular))
                    .foregroundStyle(labelColor.opacity(isHovered ? 0.9 : 0.6))
                    .frame(width: 40, height: 40)
                    .background(
                        Circle()
                            .fill(labelColor.opacity(isHovered ? 0.15 : 0.06))
                    )
                    .overlay(
                        Circle()
                            .stroke(labelColor.opacity(isHovered ? 0.4 : 0.12), lineWidth: 1)
                    )
                    .scaleEffect(isHovered ? 1.15 : 1.0)

                Text(label)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(labelColor.opacity(isHovered ? 0.7 : 0.4))
            }
        }
        .buttonStyle(.plain)
        .offset(offset)
    }

    // MARK: - Hit Testing (drag mode)

    private func updateHoveredCategory(from translation: CGSize) {
        var closest: EnergyCategory? = nil
        var closestDist: CGFloat = .infinity

        for node in nodes {
            let off = nodeOffset(angleDeg: node.angle)
            let dx = translation.width - off.width
            let dy = translation.height - off.height
            let dist = sqrt(dx * dx + dy * dy)
            if dist < activationDistance && dist < closestDist {
                closest = node.category
                closestDist = dist
            }
        }

        if closest != hoveredCategory {
            if closest != nil {
                hapticLight.impactOccurred()
            }
            hoveredCategory = closest
        }
    }
}

// MARK: - Preview

#Preview {
    ZStack {
        Color.black.ignoresSafeArea()

        VStack {
            Spacer()
            RadialHoldMenu(labelColor: .white) { category in
                print("Selected: \(category.rawValue)")
            }
            .padding(.bottom, 80)
        }
    }
}
