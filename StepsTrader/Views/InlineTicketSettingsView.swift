import SwiftUI

// MARK: - Inline Ticket Settings (Expandable)
struct InlineTicketSettingsView: View {
    @ObservedObject var model: AppModel
    @Binding var group: TicketGroup
    let appLanguage: String = "en"
    let onEditApps: () -> Void
    var onAfterDelete: (() -> Void)? = nil
    @Environment(\.colorScheme) private var colorScheme
    @State private var isUnlocking = false
    @State private var showEditSettings = false

    private let intervals: [AccessWindow] = [.minutes10, .minutes30, .hour1]

    private var surface: Color { Color(.secondarySystemGroupedBackground) }
    private var separator: Color { Color(.separator) }
    private var accent: Color { TicketsPalette.accent }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            unlockButtonsSection

            Divider()
                .background(separator)

            Button {
                withAnimation(.easeInOut(duration: 0.25)) {
                    showEditSettings.toggle()
                }
            } label: {
                rowButtonLabel(icon: "gearshape.fill", title: "Edit settings", showChevron: true, expanded: showEditSettings, surface: surface, separator: separator)
            }
            .buttonStyle(.plain)

            if showEditSettings {
                VStack(alignment: .leading, spacing: 16) {
                    Divider()
                        .background(separator)
                    inlineIntervalsSection
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }

            Button {
                onEditApps()
            } label: {
                rowButtonLabel(icon: "square.grid.2x2", title: "Edit Apps", showChevron: true, expanded: false, surface: surface, separator: separator)
            }
            .buttonStyle(.plain)

            Button {
                let groupId = group.id
                onAfterDelete?()
                model.deleteTicketGroup(groupId)
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "trash")
                        .font(.body)
                        .foregroundColor(.red)
                        .frame(width: 24)
                    Text("Delete")
                        .font(.subheadline.weight(.medium))
                        .foregroundColor(.red)
                    Spacer()
                }
                .padding(.vertical, 12)
                .padding(.horizontal, 16)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(surface)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(separator.opacity(0.5), lineWidth: 1)
                        )
                )
            }
            .buttonStyle(.plain)
        }
        .padding(.top, 8)
    }

    private func rowButtonLabel(icon: String, title: String, showChevron: Bool, expanded: Bool, surface: Color, separator: Color) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.body)
                .foregroundStyle(.primary)
                .frame(width: 24)
            Text(title)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.primary)
            Spacer()
            if showChevron {
                Image(systemName: "chevron.down")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .rotationEffect(.degrees(expanded ? 180 : 0))
            } else {
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(surface)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(separator.opacity(0.5), lineWidth: 1)
                )
        )
    }

    private var appsCount: Int {
        group.selection.applicationTokens.count + group.selection.categoryTokens.count
    }

    // MARK: - Time intervals
    private var inlineIntervalsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Time options")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)

            ForEach(intervals, id: \.self) { interval in
                HStack {
                    Text(interval.displayName)
                        .font(.subheadline)
                        .foregroundStyle(.primary)
                    Spacer()
                    Toggle("", isOn: Binding(
                        get: { group.enabledIntervals.contains(interval) },
                        set: { enabled in
                            if enabled {
                                group.enabledIntervals.insert(interval)
                            } else if group.enabledIntervals.count > 1 {
                                group.enabledIntervals.remove(interval)
                            }
                            model.updateTicketGroup(group)
                        }
                    ))
                    .tint(accent)
                }
                .padding(.vertical, 6)
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(surface)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(separator.opacity(0.5), lineWidth: 1)
                )
        )
    }

    @ViewBuilder
    private var unlockButtonsSection: some View {
        if model.isGroupUnlocked(group.id) {
            if let remaining = model.remainingUnlockTime(for: group.id) {
                HStack(spacing: 12) {
                    Image(systemName: "lock.open.fill")
                        .font(.title2)
                        .foregroundColor(accent)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Open")
                            .font(.headline)
                            .foregroundStyle(.primary)
                        Text("\(formatRemainingTime(remaining)) left")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                }
                .padding(.vertical, 16)
                .padding(.horizontal, 16)
                .background(
                    RoundedRectangle(cornerRadius: 14)
                        .fill(accent.opacity(0.12))
                        .overlay(
                            RoundedRectangle(cornerRadius: 14)
                                .stroke(accent.opacity(0.3), lineWidth: 2)
                        )
                )
            }
        } else {
            VStack(alignment: .leading, spacing: 10) {
                Text("Spend ink on")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.secondary)

                ForEach(intervals, id: \.self) { interval in
                    if group.enabledIntervals.contains(interval) {
                        quickUnlockButton(interval: interval)
                    }
                }
            }
        }
    }

    private func quickUnlockButton(interval: AccessWindow) -> some View {
        let cost = group.cost(for: interval)
        let canAfford = model.userEconomyStore.totalStepsBalance >= cost
        let timeLabel = interval.displayName

        return Button {
            guard canAfford, !isUnlocking else { return }
            let generator = UIImpactFeedbackGenerator(style: .medium)
            generator.impactOccurred()

            Task {
                isUnlocking = true
                await model.handlePayGatePaymentForGroup(groupId: group.id, window: interval, costOverride: cost)
                isUnlocking = false
            }
        } label: {
            HStack(spacing: 12) {
                Text(timeLabel)
                    .font(.headline)
                    .foregroundStyle(canAfford ? Color.primary : Color.primary.opacity(0.5))

                Spacer()

                HStack(spacing: 4) {
                    Text("\(cost)")
                        .font(.headline)
                        .monospacedDigit()
                    Text("ink")
                        .font(.subheadline)
                }
                .foregroundStyle(canAfford ? Color.primary : Color.primary.opacity(0.5))
            }
            .padding(.vertical, 16)
            .padding(.horizontal, 18)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(canAfford ? accent : surface)
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(canAfford ? Color.clear : separator.opacity(0.5), lineWidth: 1)
                    )
            )
            .shadow(color: canAfford ? accent.opacity(0.3) : Color.clear, radius: 8, x: 0, y: 4)
        }
        .disabled(!canAfford || isUnlocking)
        .buttonStyle(.plain)
        .opacity(canAfford ? 1.0 : 0.6)
        .scaleEffect(isUnlocking ? 0.95 : 1.0)
        .animation(.easeInOut(duration: 0.15), value: isUnlocking)
    }
}
