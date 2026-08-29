import SwiftUI

// MARK: - Inline Ticket Settings (Expandable)
struct InlineTicketSettingsView: View {
    @ObservedObject var model: AppModel
    @Binding var group: TicketGroup
    let onEditApps: () -> Void
    var onAfterDelete: (() -> Void)? = nil

    var body: some View {
        TicketSettingsContentView(
            group: $group,
            onEditApps: onEditApps,
            onAfterDelete: onAfterDelete ?? {},
            updateGroup: { model.updateTicketGroup($0) },
            deleteTicketGroup: { model.deleteTicketGroup($0) },
            isUsageBudgetActive: { model.isGroupUsageBudgetActive($0) },
            unspentUsageBudget: { model.unspentUsageBudgetMatchingShield(for: $0) },
            availableStepsBalance: { model.userEconomyStore.totalStepsBalance },
            handlePayGatePayment: { groupId, window, cost in
                await model.handlePayGatePaymentForGroup(
                    groupId: groupId,
                    window: window,
                    costOverride: cost
                )
            }
        )
    }
}

/// The settings surface is independent of persistence so production and the
/// isolated UI fixture exercise the same controls and confirmation flow.
struct TicketSettingsContentView: View {
    @Binding var group: TicketGroup
    let onEditApps: () -> Void
    let onAfterDelete: () -> Void
    let updateGroup: (TicketGroup) -> Void
    let deleteTicketGroup: (String) -> Void
    let isUsageBudgetActive: (String) -> Bool
    let unspentUsageBudget: (String) -> Int
    let availableStepsBalance: () -> Int
    let handlePayGatePayment: (String, AccessWindow, Int) async -> Void

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isUnlocking = false
    @State private var showEditSettings = false
    @State private var showDeleteConfirmation = false
    @State private var unlockHapticTick = 0

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
                withMotionAnimation(.easeInOut(duration: 0.25), reduceMotion: reduceMotion) {
                    showEditSettings.toggle()
                }
            } label: {
                rowButtonLabel(icon: "gearshape.fill", title: String(localized: "Edit settings"), showChevron: true, expanded: showEditSettings, surface: surface, separator: separator)
            }
            .buttonStyle(.plain)

            if showEditSettings {
                VStack(alignment: .leading, spacing: 16) {
                    Divider()
                        .background(separator)
                    inlineIntervalsSection
                }
                .transition(reduceMotion ? .opacity : .opacity.combined(with: .move(edge: .top)))
            }

            Button {
                onEditApps()
            } label: {
                rowButtonLabel(icon: "square.grid.2x2", title: String(localized: "Edit Apps"), showChevron: true, expanded: false, surface: surface, separator: separator)
            }
            .buttonStyle(.plain)

            Button {
                showDeleteConfirmation = true
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "trash")
                        .font(.geist(.body))
                        .foregroundStyle(.red)
                        .frame(width: 24)
                    Text(String(localized: "Delete"))
                        .font(.geist(.subheadline).weight(.medium))
                        .foregroundStyle(.red)
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
            .accessibilityIdentifier("settings.feed.delete")
        }
        .padding(.top, 8)
        .sensoryFeedback(.impact(weight: .medium), trigger: unlockHapticTick)
        .confirmationDialog(
            String(localized: "Delete \(group.name.isEmpty ? "Feed" : group.name)?"),
            isPresented: $showDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button(String(localized: "Delete Feed"), role: .destructive) { confirmDelete() }
            Button(String(localized: "Cancel"), role: .cancel) {}
        } message: {
            Text(String(localized: "This removes the Feed and its access options. This action cannot be undone."))
        }
    }

    private func rowButtonLabel(icon: String, title: String, showChevron: Bool, expanded: Bool, surface: Color, separator: Color) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.geist(.body))
                .foregroundStyle(.primary)
                .frame(width: 24)
            Text(title)
                .font(.geist(.subheadline).weight(.medium))
                .foregroundStyle(.primary)
            Spacer()
            if showChevron {
                Image(systemName: "chevron.down")
                    .font(.geist(.caption).weight(.semibold))
                    .foregroundStyle(.secondary)
                    .rotationEffect(.degrees(expanded ? 180 : 0))
            } else {
                Image(systemName: "chevron.right")
                    .font(.geist(.caption))
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

    // MARK: - Time intervals
    private var inlineIntervalsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(String(localized: "Time options"))
                .font(.geist(.subheadline).weight(.semibold))
                .foregroundStyle(.primary)

            ForEach(intervals, id: \.self) { interval in
                Toggle(interval.displayName, isOn: Binding(
                    get: { group.enabledIntervals.contains(interval) },
                    set: { enabled in
                        if enabled {
                            group.enabledIntervals.insert(interval)
                        } else if group.enabledIntervals.count > 1 {
                            group.enabledIntervals.remove(interval)
                        }
                        updateGroup(group)
                    }
                ))
                .font(.geist(.subheadline))
                .foregroundStyle(.primary)
                .tint(accent)
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

    private func confirmDelete() {
        let groupId = group.id
        deleteTicketGroup(groupId)
        onAfterDelete()
    }

    @ViewBuilder
    private var unlockButtonsSection: some View {
        if isUsageBudgetActive(group.id) {
            // Same accessor the Feeds surface uses: the wall-clock-floored one
            // reports time already spent when the phone merely sat idle.
            let budget = unspentUsageBudget(group.id)
            HStack(spacing: 12) {
                Image(systemName: "lock.open.fill")
                    .font(.geist(.title2))
                    .foregroundStyle(accent)
                VStack(alignment: .leading, spacing: 2) {
                    Text(String(localized: "Open", comment: "Unlock status label"))
                        .font(.geist(.headline))
                        .foregroundStyle(.primary)
                    Text(String(localized: "\(budget) min remaining"))
                        .font(.geist(.caption))
                        .foregroundStyle(.secondary)
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
        } else {
            VStack(alignment: .leading, spacing: 10) {
                Text(String(localized: "Spend colors on", comment: "Unlock section header"))
                    .font(.geist(.caption).weight(.semibold))
                    .foregroundStyle(.secondary)
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
        let canAfford = availableStepsBalance() >= cost
        let timeLabel = interval.displayName

        return Button {
            guard canAfford, !isUnlocking else { return }
            unlockHapticTick &+= 1

            Task {
                isUnlocking = true
                await handlePayGatePayment(group.id, interval, cost)
                isUnlocking = false
            }
        } label: {
            HStack(spacing: 12) {
                Text(timeLabel)
                    .font(.geist(.headline))
                    .foregroundStyle(canAfford ? Color.primary : Color.primary.opacity(0.5))

                Spacer()

                HStack(spacing: 4) {
                    Text("\(cost)")
                        .font(.geist(.headline))
                        .monospacedDigit()
                    Text(String(localized: "colors"))
                        .font(.geist(.subheadline))
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
