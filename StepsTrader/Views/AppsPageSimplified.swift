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
    static let accent = Color(red: 0xFF/255.0, green: 0xD3/255.0, blue: 0x69/255.0)

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
    private let appLanguage = "en"
    @State private var expandedSheetGroupId: TicketGroupId? = nil
    @State private var flippedTicketId: String? = nil
    @State private var showCustomNamePrompt = false
    @State private var customTicketName = ""

    var body: some View {
        NavigationStack {
            ZStack {
                EnergyGradientBackground(
                    stepsPoints: model.stepsPointsToday,
                    sleepPoints: model.sleepPointsToday,
                    hasStepsData: model.hasStepsData,
                    hasSleepData: model.hasSleepData
                )
                .ignoresSafeArea()
                .allowsHitTesting(false)

                VStack(spacing: 0) {
                    HStack {
                        Text("My Tickets")
                            .font(.system(size: 17, weight: .light, design: .rounded))
                            .foregroundStyle(Color.primary.opacity(0.7))
                        Spacer()
                        Button {
                            showTemplatePicker = true
                        } label: {
                            ZStack {
                                Circle()
                                    .strokeBorder(Color.primary.opacity(0.15), lineWidth: 1)
                                    .frame(width: 36, height: 36)
                                Image(systemName: "plus")
                                    .font(.system(size: 16, weight: .ultraLight))
                                    .foregroundStyle(Color.primary.opacity(0.7))
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 20)
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
            .background(Color.clear)
            .safeAreaInset(edge: .top, spacing: 0) {
                Color.clear.frame(height: topCardHeight)
            }
            .navigationBarHidden(true)
            .sheet(item: $expandedSheetGroupId) { groupId in
                if model.blockingStore.ticketGroups.contains(where: { $0.id == groupId.id }) {
                    let groupBinding = Binding<TicketGroup>(
                        get: {
                            model.blockingStore.ticketGroups.first(where: { $0.id == groupId.id })
                                ?? TicketGroup(name: "", settings: AppUnlockSettings(entryCostSteps: 10, dayPassCostSteps: 100))
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
                Text("Family Controls not available").padding()
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
            .alert("Name your ticket", isPresented: $showCustomNamePrompt) {
                TextField("e.g. Social, Games…", text: $customTicketName)
                Button("Create") {
                    let name = customTicketName.trimmingCharacters(in: .whitespacesAndNewlines)
                    let group = model.createTicketGroup(
                        name: name.isEmpty ? "New Ticket" : name,
                        stickerThemeIndex: 0
                    )
                    selection = FamilyActivitySelection()
                    selectedGroupId = TicketGroupId(id: group.id)
                    showPicker = true
                }
                Button("Cancel", role: .cancel) {}
            }
        }
    }

    // MARK: - Ticket Stack

    private var ticketStack: some View {
        LazyVStack(spacing: 14) {
            ForEach(visibleGroups) { group in
                let isFlipped = flippedTicketId == group.id

                PaperTicketView(
                    model: model,
                    group: group,
                    colorScheme: colorScheme,
                    isFlipped: isFlipped,
                    onSettings: {
                        expandedSheetGroupId = TicketGroupId(id: group.id)
                    },
                    onFlip: {
                        withAnimation(.spring(response: 0.5, dampingFraction: 0.75)) {
                            if isFlipped {
                                flippedTicketId = nil
                            } else {
                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                flippedTicketId = group.id
                            }
                        }
                    }
                )
                .zIndex(isFlipped ? 10 : 0)
                .contextMenu {
                    Button {
                        expandedSheetGroupId = TicketGroupId(id: group.id)
                    } label: {
                        Label("Settings", systemImage: "gearshape")
                    }
                    Button(role: .destructive) {
                        UINotificationFeedbackGenerator().notificationOccurred(.warning)
                        deleteAndCleanup(group.id)
                    } label: {
                        Label("Delete", systemImage: "trash")
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
                Text("No tickets yet")
                    .font(.system(size: 20, weight: .light, design: .rounded))
                    .foregroundStyle(Color.primary.opacity(0.7))
                Text("Create one when you're ready.")
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
                    Text("New Ticket")
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
                        expandedSheetGroupId = nil
                        // Delay picker presentation to let the settings sheet fully dismiss,
                        // avoiding "presenting while dismissing" warnings (audit fix #34)
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                            showPicker = true
                        }
                    },
                    onAfterDelete: onDismiss
                )
                .padding()
            }
            .background(theme.backgroundColor)
            .navigationTitle(group.wrappedValue.name.isEmpty ? "Ticket" : group.wrappedValue.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(theme.backgroundColor, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { onDismiss() }
                }
            }
        }
    }

    private var visibleGroups: [TicketGroup] {
        model.blockingStore.ticketGroups.filter { group in
            !group.selection.applicationTokens.isEmpty || !group.selection.categoryTokens.isEmpty
        }
    }

    private func deleteAndCleanup(_ groupId: String) {
        if flippedTicketId == groupId { flippedTicketId = nil }
        if expandedSheetGroupId?.id == groupId { expandedSheetGroupId = nil }
        model.deleteTicketGroup(groupId)
    }
}
