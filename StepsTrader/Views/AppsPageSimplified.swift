import SwiftUI
#if canImport(FamilyControls)
import FamilyControls
#endif
import Foundation

struct TicketGroupId: Identifiable {
    let id: String
}

/// Single accent for primary actions (Create Ticket, unlock). Rest uses system colors.
enum TicketsPalette {
    // Accent yellow: #FFD369
    static let accent = AppColors.brandAccent

    // Theme accents (used on the flipped side for controls).
    static let themes: [Color] = [
        Color(red: 0.20, green: 0.45, blue: 0.95), // blue
        Color(red: 0.62, green: 0.29, blue: 0.98), // purple
        Color(red: 0.05, green: 0.68, blue: 0.45), // teal/green
        Color(red: 0.95, green: 0.33, blue: 0.35), // red
        Color(red: 0.98, green: 0.55, blue: 0.15), // orange
        Color(red: 0.15, green: 0.75, blue: 0.95)  // cyan
    ]

    static func themeColor(for index: Int) -> Color {
        let safe = abs(index)
        return themes.isEmpty ? .blue : themes[safe % themes.count]
    }

    // (intentionally no longer used for back surface; back surface follows day/night theme)
}

struct AppsPageSimplified: View {
    @ObservedObject var model: AppModel
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.appTheme) private var theme
    @Environment(\.topCardHeight) private var topCardHeight
    @State private var selection = FamilyActivitySelection()
    @State private var showPicker = false
    @State private var selectedGroupId: TicketGroupId? = nil
    @State private var showTemplatePicker = false
    @State private var expandedSheetGroupId: TicketGroupId? = nil
    @State private var isReordering = false

    /// Tint for the + button: dark in daylight, light at night, so it stays visible on the gradient.
    private var buttonTint: Color {
        switch theme {
        case .daylight: return theme.textPrimary
        case .night: return AppColors.Night.textPrimary
        case .system: return colorScheme == .dark ? AppColors.Night.textPrimary : theme.textPrimary
        }
    }
    @State private var showCustomNamePrompt = false
    @State private var customTicketName = ""
    @State private var showPickerAfterDismiss = false
    @State private var groupIdToDelete: String? = nil

    var body: some View {
        NavigationStack {
            ZStack {
                VStack(spacing: 0) {
                    HStack {
                        Text(String(localized: "My Feeds", comment: "Feeds page title"))
                            .font(.system(size: 17, weight: .light, design: .rounded))
                            .foregroundStyle(Color.primary.opacity(0.7))
                        Spacer()
                        if isReordering {
                            Button {
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                    isReordering = false
                                }
                            } label: {
                                Text(String(localized: "Done"))
                                    .font(.system(size: 15, weight: .regular, design: .rounded))
                                    .foregroundStyle(buttonTint)
                            }
                        } else {
                            if visibleGroups.count > 1 {
                                Button {
                                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                        isReordering = true
                                    }
                                } label: {
                                    ZStack {
                                        Circle()
                                            .fill(.ultraThinMaterial)
                                            .opacity(0.5)
                                            .frame(width: 36, height: 36)
                                        Circle()
                                            .strokeBorder(buttonTint.opacity(0.4), lineWidth: 1)
                                            .frame(width: 36, height: 36)
                                        Image(systemName: "arrow.up.arrow.down")
                                            .font(.system(size: 14, weight: .ultraLight))
                                            .foregroundStyle(buttonTint)
                                    }
                                }
                            }
                            Button {
                                showTemplatePicker = true
                            } label: {
                                ZStack {
                                    Circle()
                                        .fill(.ultraThinMaterial)
                                        .opacity(0.5)
                                        .frame(width: 36, height: 36)
                                    Circle()
                                        .strokeBorder(buttonTint.opacity(0.4), lineWidth: 1)
                                        .frame(width: 36, height: 36)
                                    Image(systemName: "plus")
                                        .font(.system(size: 16, weight: .ultraLight))
                                        .foregroundStyle(buttonTint)
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 32)
                    .padding(.bottom, 8)

                    if model.blockingStore.ticketGroups.isEmpty {
                        emptyTicketsContent
                    } else {
                        ScrollView {
                            ticketStack
                                .padding(.horizontal, 16)
                                .padding(.top, 8)
                                .padding(.bottom, 96)
                        }
                        .frame(maxHeight: .infinity)
                    }
                }
                .zIndex(0)

                Image("grain 1")
                    .resizable()
                    .scaledToFill()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipped()
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
                    .opacity(0.28)
                    .blendMode(.overlay)
                    .zIndex(10)
            }
            .energyGradientBackground(model: model)
            .background(Color.clear)
            .safeAreaInset(edge: .top, spacing: 0) {
                Color.clear.frame(height: topCardHeight)
            }
            .toolbar(.hidden, for: .navigationBar)
            .sheet(item: $expandedSheetGroupId, onDismiss: {
                if showPickerAfterDismiss {
                    showPickerAfterDismiss = false
                    showPicker = true
                }
            }) { groupId in
                if model.blockingStore.ticketGroups.contains(where: { $0.id == groupId.id }) {
                    let groupBinding = Binding<TicketGroup>(
                        get: {
                            guard let group = model.blockingStore.ticketGroups.first(where: { $0.id == groupId.id }) else {
                                return TicketGroup(name: "", settings: AppUnlockSettings(entryCostSteps: 10, dayPassCostSteps: 100))
                            }
                            return group
                        },
                        set: { updated in model.updateTicketGroup(updated) }
                    )
                    ticketSettingsSheet(group: groupBinding, onDismiss: { expandedSheetGroupId = nil })
                }
            }
            .sheet(isPresented: $showPicker, onDismiss: {
                if let groupId = selectedGroupId {
                    if let group = model.blockingStore.ticketGroups.first(where: { $0.id == groupId.id }) {
                        let hasApps = !group.selection.applicationTokens.isEmpty || !group.selection.categoryTokens.isEmpty
                        if !hasApps { model.deleteTicketGroup(groupId.id) }
                    }
                    selectedGroupId = nil
                }
            }) {
                #if canImport(FamilyControls)
                AppSelectionSheet(
                    selection: $selection,
                    templateApp: selectedGroupId.flatMap { gid in model.blockingStore.ticketGroups.first(where: { $0.id == gid.id })?.templateApp },
                    onDone: {
                        if let groupId = selectedGroupId {
                            let hasApps = !selection.applicationTokens.isEmpty || !selection.categoryTokens.isEmpty
                            if hasApps {
                                model.addAppsToGroup(groupId.id, selection: selection)
                                showPicker = false; selectedGroupId = nil
                            } else {
                                model.deleteTicketGroup(groupId.id)
                                showPicker = false; selectedGroupId = nil
                            }
                        } else {
                            model.syncFamilyControlsCards(from: selection)
                            showPicker = false; selectedGroupId = nil
                        }
                    }
                )
                #else
                Text(String(localized: "Family Controls not available")).padding()
                #endif
            }
            .sheet(isPresented: $showTemplatePicker) {
                TicketTemplatePickerView(
                    model: model,
                    onTemplateSelected: { templateApp in
                        showTemplatePicker = false
                        let displayName = TargetResolver.displayName(for: templateApp)
                        let group = model.createTicketGroup(name: displayName, templateApp: templateApp, stickerThemeIndex: 0)
                        selection = FamilyActivitySelection()
                        selectedGroupId = TicketGroupId(id: group.id)
                        showPicker = true
                    },
                    onCustomSelected: {
                        showTemplatePicker = false
                        customTicketName = ""
                        showCustomNamePrompt = true
                    }
                )
            }
            .onAppear { selection = model.appSelection }
            .onChange(of: model.blockingStore.ticketGroups.count) {
                if visibleGroups.count <= 1 { isReordering = false }
            }
            .alert(String(localized: "Name your ticket"), isPresented: $showCustomNamePrompt) {
                TextField(String(localized: "e.g. Social, Games…", comment: "Placeholder for ticket name"), text: $customTicketName)
                Button(String(localized: "Create")) {
                    let name = customTicketName.trimmingCharacters(in: .whitespacesAndNewlines)
                    let group = model.createTicketGroup(
                        name: name.isEmpty ? String(localized: "New Ticket") : name,
                        stickerThemeIndex: 0
                    )
                    selection = FamilyActivitySelection()
                    selectedGroupId = TicketGroupId(id: group.id)
                    showPicker = true
                }
                Button(String(localized: "Cancel"), role: .cancel) {}
            }
            .alert(String(localized: "Delete this ticket?"), isPresented: Binding(
                get: { groupIdToDelete != nil },
                set: { if !$0 { groupIdToDelete = nil } }
            )) {
                Button(String(localized: "Delete"), role: .destructive) {
                    if let id = groupIdToDelete {
                        UINotificationFeedbackGenerator().notificationOccurred(.warning)
                        deleteAndCleanup(id)
                    }
                    groupIdToDelete = nil
                }
                Button(String(localized: "Cancel"), role: .cancel) {
                    groupIdToDelete = nil
                }
            }
        }
    }

    // MARK: - Ticket Stack

    private var ticketStack: some View {
        LazyVStack(spacing: 14) {
            ForEach(visibleGroups) { group in
                PaperTicketView(
                    model: model,
                    group: group,
                    colorScheme: colorScheme,
                    onSettings: {
                        guard !isReordering else { return }
                        expandedSheetGroupId = TicketGroupId(id: group.id)
                    }
                )
                .overlay(alignment: .trailing) {
                    if isReordering {
                        VStack(spacing: 0) {
                            Button {
                                moveTicket(group.id, up: true)
                            } label: {
                                Image(systemName: "chevron.up")
                                    .font(.system(size: 12, weight: .semibold))
                                    .frame(width: 34, height: 28)
                                    .contentShape(Rectangle())
                            }
                            .disabled(visibleGroups.first?.id == group.id)

                            Divider().frame(width: 20)

                            Button {
                                moveTicket(group.id, up: false)
                            } label: {
                                Image(systemName: "chevron.down")
                                    .font(.system(size: 12, weight: .semibold))
                                    .frame(width: 34, height: 28)
                                    .contentShape(Rectangle())
                            }
                            .disabled(visibleGroups.last?.id == group.id)
                        }
                        .foregroundStyle(Color.primary.opacity(0.5))
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(.ultraThinMaterial)
                        )
                        .padding(.trailing, 10)
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                    }
                }
                .contextMenu {
                    if !isReordering {
                        Button {
                            expandedSheetGroupId = TicketGroupId(id: group.id)
                        } label: {
                            Label(String(localized: "Settings", comment: "Context menu action"), systemImage: "gearshape")
                        }
                        Button(role: .destructive) {
                            groupIdToDelete = group.id
                        } label: {
                            Label(String(localized: "Delete"), systemImage: "trash")
                        }
                    }
                }
            }
        }
    }

    // MARK: - Empty state
    private var emptyTicketsContent: some View {
        VStack(spacing: 28) {
            Spacer()
            Image(systemName: "ticket")
                .font(.system(size: 52, weight: .ultraLight))
                .foregroundStyle(Color.primary.opacity(0.25))
            VStack(spacing: 8) {
                Text(String(localized: "No feeds connected yet"))
                    .font(.system(size: 20, weight: .light, design: .rounded))
                    .foregroundStyle(Color.primary.opacity(0.7))
                Text(String(localized: "Create one when you're ready."))
                    .font(.system(size: 14, weight: .light, design: .rounded))
                    .foregroundStyle(Color.primary.opacity(0.4))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }
            Button {
                showTemplatePicker = true
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "plus")
                        .font(.system(size: 14, weight: .ultraLight))
                    Text(String(localized: "New Ticket"))
                        .font(.system(size: 15, weight: .light, design: .rounded))
                }
                .foregroundStyle(Color.primary.opacity(0.7))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.15), lineWidth: 1)
                )
            }
            .padding(.horizontal, 40)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    /// Sheet for full ticket settings
    private func ticketSettingsSheet(group: Binding<TicketGroup>, onDismiss: @escaping () -> Void) -> some View {
        NavigationStack {
            ScrollView {
                InlineTicketSettingsView(
                    model: model, group: group,
                    onEditApps: {
                        selectedGroupId = TicketGroupId(id: group.wrappedValue.id)
                        selection = group.wrappedValue.selection
                        showPickerAfterDismiss = true
                        expandedSheetGroupId = nil
                    },
                    onAfterDelete: onDismiss
                )
                .padding()
            }
            .background(theme.backgroundColor)
            .navigationTitle(group.wrappedValue.name.isEmpty ? String(localized: "Ticket") : group.wrappedValue.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(theme.backgroundColor, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "Done")) { onDismiss() }
                }
            }
        }
    }

    private var visibleGroups: [TicketGroup] {
        model.blockingStore.ticketGroups.filter { group in
            !group.selection.applicationTokens.isEmpty || !group.selection.categoryTokens.isEmpty
        }
    }

    private func moveTicket(_ groupId: String, up: Bool) {
        let visible = visibleGroups
        guard let visibleIdx = visible.firstIndex(where: { $0.id == groupId }) else { return }
        let targetIdx = up ? visibleIdx - 1 : visibleIdx + 1
        guard targetIdx >= 0, targetIdx < visible.count else { return }

        let targetId = visible[targetIdx].id
        guard let fromIdx = model.blockingStore.ticketGroups.firstIndex(where: { $0.id == groupId }),
              let toIdx = model.blockingStore.ticketGroups.firstIndex(where: { $0.id == targetId })
        else { return }

        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
            model.blockingStore.ticketGroups.swapAt(fromIdx, toIdx)
        }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        model.blockingStore.persistTicketGroups()
    }

    private func deleteAndCleanup(_ groupId: String) {
        if expandedSheetGroupId?.id == groupId { expandedSheetGroupId = nil }
        PaperTicketView.removeCachedTitle(forGroupId: groupId)
        model.deleteTicketGroup(groupId)
    }
}
