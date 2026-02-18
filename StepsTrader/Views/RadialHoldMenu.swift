import SwiftUI

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
        (.mind,   "Mind",  "brain.head.profile", 90),  // straight up
        (.heart,  "Heart", "heart.fill",         45),  // upper-right
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
                AppLogger.ui.debug("Selected: \(category.rawValue)")
            }
            .padding(.bottom, 80)
        }
    }
}
