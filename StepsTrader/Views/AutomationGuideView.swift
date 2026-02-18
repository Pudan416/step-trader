import SwiftUI
#if canImport(FamilyControls)
import FamilyControls
#endif
import UIKit

#if DEBUG
struct AutomationGuideView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @Environment(\.appTheme) private var theme
    let app: GuideItem
    @ObservedObject var model: AppModel
    let markPending: (String) -> Void
    let deleteModule: (String) -> Void
    @State private var showDeactivateAlert = false
    @State private var showTimeAccessPicker = false
    @State private var timeAccessSelection = FamilyActivitySelection()
    @State private var showEntrySettings = false
    @State private var showConnectionRequired = false
    // appLanguage removed — English only for v1
    
    private var accent: Color { Color(red: 0.88, green: 0.51, blue: 0.85) }
    private var timeAccessEnabled: Bool { model.isTimeAccessEnabled(for: app.bundleId) }
    private var minuteModeEnabled: Bool { model.isFamilyControlsModeEnabled(for: app.bundleId) }

    var body: some View {
        NavigationView {
                ScrollView {
                VStack(spacing: 16) {
                    // Compact header
                    compactHeader

                if app.status == .configured || app.status == .pending {
                        // Connection status (moved to top)
                        connectionCard
                        
                        // Mode selector
                        modeCard
                        
                        // Entry settings (expandable, only for entry mode)
                        if !minuteModeEnabled {
                            entrySettingsCard
                        }
                        
                        // Setup instructions for pending
                        if app.status == .pending {
                            setupCard
                        }
                } else {
                        // Setup instructions for new shields
                        setupCard
                    }
                    
                    // Shortcut button
                    shortcutButton
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, 100)
            }
            .background(theme.backgroundColor)
            .overlay(alignment: .bottom) {
                if app.status != .none {
                    deactivateButton
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(theme.backgroundColor, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(AppFonts.title2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .onAppear {
                timeAccessSelection = model.timeAccessSelection(for: app.bundleId)
            }
            .sheet(isPresented: $showTimeAccessPicker, onDismiss: {
                model.saveTimeAccessSelection(timeAccessSelection, for: app.bundleId)
                if model.isFamilyControlsModeEnabled(for: app.bundleId) {
                    model.applyFamilyControlsSelection(for: app.bundleId)
                } else {
                    model.rebuildFamilyControlsShield()
                }
            }) {
                TimeAccessPickerSheet(
                    selection: $timeAccessSelection,
                    appName: app.name
                )
            }
            .alert("Deactivate ticket", isPresented: $showDeactivateAlert) {
                Button("Open Shortcuts") {
                    if let url = URL(string: "shortcuts://automation") ?? URL(string: "shortcuts://") {
                        openURL(url)
                    }
                    deleteModule(app.bundleId)
                    dismiss()
                }
                Button("Cancel", role: .cancel) { showDeactivateAlert = false }
            } message: {
                Text("Remove the automation from Shortcuts app to fully deactivate.")
            }
            .alert("Connection required", isPresented: $showConnectionRequired) {
                Button("Connect") {
                    Task {
                        try? await model.familyControlsService.requestAuthorization()
                        showTimeAccessPicker = true
                    }
                }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("To use minute mode, connect the app via Family Controls. This allows tracking real usage time.")
            }
        }
    }
    
    // MARK: - Compact Header
    private var compactHeader: some View {
        HStack(spacing: 14) {
            // App icon
                guideIconView()
                .frame(width: 52, height: 52)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .shadow(color: .black.opacity(0.1), radius: 6, y: 3)
            
                VStack(alignment: .leading, spacing: 4) {
                    Text(app.name)
                    .font(AppFonts.headline)
                
                // Status badge
                HStack(spacing: 5) {
                    Circle()
                        .fill(app.status == .configured ? Color.green : (app.status == .pending ? Color.orange : Color.gray))
                        .frame(width: 6, height: 6)
                    Text(statusText)
                        .font(AppFonts.caption)
                            .foregroundColor(.secondary)
                    }
                }
            
                Spacer()
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.secondarySystemBackground))
        )
    }
    
    private var statusText: String {
        switch app.status {
        case .configured: return "Active"
        case .pending: return "Pending"
        case .none: return "Not connected"
        }
    }
    
    @ViewBuilder
    private func guideIconView() -> some View {
        if let imageName = app.imageName,
           let uiImage = UIImage(named: imageName) {
            Image(uiImage: uiImage)
                .resizable()
                .scaledToFit()
        } else {
            Text(app.icon)
                .font(.systemSerif(28))
        }
    }
    
    // MARK: - Connection Card (moved to top)
    private var connectionCard: some View {
        Button {
            Task {
                try? await model.familyControlsService.requestAuthorization()
                showTimeAccessPicker = true
            }
        } label: {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(timeAccessEnabled ? Color.green.opacity(0.15) : Color.orange.opacity(0.15))
                        .frame(width: 44, height: 44)
                    
                    #if canImport(FamilyControls)
                    if let token = timeAccessSelection.applicationTokens.first {
                        Label(token)
                            .labelStyle(.iconOnly)
                            .frame(width: 26, height: 26)
                } else {
                        Image(systemName: "plus")
                            .font(AppFonts.body.bold())
                            .foregroundColor(.orange)
                    }
                    #else
                    Image(systemName: timeAccessEnabled ? "checkmark" : "plus")
                        .font(AppFonts.body.bold())
                        .foregroundColor(timeAccessEnabled ? .green : .orange)
                    #endif
                }
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("App Connection")
                        .font(AppFonts.subheadline)
                        .foregroundColor(.primary)
                    Text(timeAccessEnabled ? "Connected" : "Tap to connect")
                        .font(AppFonts.caption)
                        .foregroundColor(timeAccessEnabled ? .green : .secondary)
                }
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .font(AppFonts.caption.bold())
                    .foregroundColor(.secondary)
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color(.secondarySystemBackground))
            )
        }
        .buttonStyle(.plain)
    }
    
    // MARK: - Mode Card
    private var modeCard: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                // Entry mode
                modeButton(
                    icon: "door.left.hand.open",
                    title: "Entry",
                    subtitle: "Pay once per session",
                    isSelected: !minuteModeEnabled,
                    isEnabled: true
                ) {
                    setMinuteModeEnabled(false)
                }
                
                // Minute mode
                modeButton(
                    icon: "clock.fill",
                    title: "Minute",
                    subtitle: "Pay per minute used",
                    isSelected: minuteModeEnabled,
                    isEnabled: timeAccessEnabled
                ) {
                    if timeAccessEnabled {
                        setMinuteModeEnabled(true)
                    } else {
                        showConnectionRequired = true
                    }
                }
            }
            
            // Mode description
                HStack(spacing: 8) {
                Image(systemName: "info.circle")
                    .font(AppFonts.caption)
                    .foregroundColor(.secondary)
                Text(minuteModeEnabled 
                    ? "Ink is deducted for each minute I spend in the app"
                    : "Choose a time window (5min, 1h, day) and pay once for unlimited access")
                    .font(AppFonts.caption)
                    .foregroundColor(.secondary)
                Spacer()
            }
            .padding(.horizontal, 4)
        }
    }
    
    private func modeButton(icon: String, title: String, subtitle: String, isSelected: Bool, isEnabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 6) {
                HStack(spacing: 6) {
                    Image(systemName: icon)
                        .font(AppFonts.body)
                    Text(title)
                        .font(AppFonts.subheadline)
                }
                Text(subtitle)
                    .font(AppFonts.caption2)
                    .foregroundColor(isSelected ? accent.opacity(0.8) : .secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(isSelected ? accent.opacity(0.15) : Color(.secondarySystemBackground))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(isSelected ? accent : Color.clear, lineWidth: 2)
                    )
            )
            .foregroundColor(isSelected ? accent : (isEnabled ? .primary : .secondary))
            .opacity(isEnabled ? 1 : 0.5)
        }
        .buttonStyle(.plain)
    }

    private func windowCost(for window: AccessWindow) -> Int {
        switch window {
        case .minutes10: return 4
        case .minutes30: return 10
        case .hour1: return 20
        }
    }

    private func setMinuteModeEnabled(_ enabled: Bool) {
        model.setFamilyControlsModeEnabled(enabled, for: app.bundleId)
        model.setMinuteTariffEnabled(enabled, for: app.bundleId)
        if enabled && timeAccessEnabled {
            model.applyFamilyControlsSelection(for: app.bundleId)
                        } else {
            model.rebuildFamilyControlsShield()
        }
    }
    
    // MARK: - Entry Settings Card (Expandable)
    private var entrySettingsCard: some View {
        VStack(spacing: 0) {
            // Header (tappable)
            Button {
                withAnimation(.spring(response: 0.3)) {
                    showEntrySettings.toggle()
                }
            } label: {
                HStack {
                    Image(systemName: "slider.horizontal.3")
                        .font(AppFonts.body)
                        .foregroundColor(.secondary)
                    Text("Entry settings")
                        .font(AppFonts.subheadline)
                    Spacer()
                    Image(systemName: showEntrySettings ? "chevron.up" : "chevron.down")
                        .font(AppFonts.caption.bold())
                        .foregroundColor(.secondary)
                }
                .padding(14)
            }
            .buttonStyle(.plain)

            // Expandable content
            if showEntrySettings {
                Divider()
                    .padding(.horizontal, 14)
                
                VStack(spacing: 0) {
                    windowRow(title: "1 hour", window: .hour1, cost: windowCost(for: .hour1), isLast: false)
                    windowRow(title: "30 min", window: .minutes30, cost: windowCost(for: .minutes30), isLast: false)
                    windowRow(title: "10 min", window: .minutes10, cost: windowCost(for: .minutes10), isLast: true)
                }
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.secondarySystemBackground))
        )
    }
    
    private func windowRow(title: String, window: AccessWindow, cost: Int, isLast: Bool) -> some View {
        let isEnabled = model.allowedAccessWindows(for: app.bundleId).contains(window)
        
        return VStack(spacing: 0) {
            HStack {
                Text(title)
                    .font(AppFonts.subheadline)
                    
                    Spacer()
                    
                Text("\(cost)")
                    .font(AppFonts.caption)
                    .foregroundColor(.secondary)
                
                Toggle("", isOn: Binding(
                    get: { isEnabled },
                    set: { model.updateAccessWindow(window, enabled: $0, for: app.bundleId) }
                ))
                .labelsHidden()
                .tint(accent)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            
            if !isLast {
                Divider()
                    .padding(.leading, 14)
            }
        }
    }
    
    // MARK: - Setup Card
    private var setupCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: "list.number")
                    .font(AppFonts.body)
                    .foregroundColor(.blue)
                Text(app.status == .pending ? "Finish setup" : "How to set up")
                    .font(AppFonts.subheadline)
            }
            
            VStack(alignment: .leading, spacing: 10) {
                if app.status == .pending {
                    setupStep(num: 1, text: "Shortcuts → Automation → +")
                    setupStep(num: 2, text: "App → \(app.name) → Is Opened")
                    setupStep(num: 3, text: "Run Immediately → select shortcut")
                } else {
                    setupStep(num: 1, text: "Tap \"Get ticket\" below")
                    setupStep(num: 2, text: "Add shortcut to library")
                    setupStep(num: 3, text: "Create automation")
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.secondarySystemBackground))
        )
    }
    
    private func setupStep(num: Int, text: String) -> some View {
        HStack(alignment: .center, spacing: 10) {
            Text("\(num)")
                .font(AppFonts.caption2.bold())
                .foregroundColor(.white)
                .frame(width: 18, height: 18)
                .background(Circle().fill(accent))
            
            Text(text)
                .font(AppFonts.caption)
                .foregroundColor(.primary)
        }
    }
    
    // MARK: - Shortcut Button
    @ViewBuilder
    private var shortcutButton: some View {
        if let link = app.link, let url = URL(string: link) {
            Button {
                markPending(app.bundleId)
                openURL(url)
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: app.status == .configured ? "arrow.triangle.2.circlepath" : "arrow.down.circle.fill")
                        .font(AppFonts.body)
                    Text(app.status == .configured ? "Update" : "Get ticket")
                        .font(AppFonts.subheadline)
                    Spacer()
                    Image(systemName: "arrow.up.right")
                        .font(AppFonts.caption)
                }
                .padding(14)
        .background(
                    RoundedRectangle(cornerRadius: 14)
                        .fill(
                            LinearGradient(
                                colors: [accent, accent.opacity(0.7)],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                )
                .foregroundColor(.white)
            }
            .buttonStyle(.plain)
        }
    }
    
    // MARK: - Deactivate Button
    private var deactivateButton: some View {
        Button {
            if app.status == .configured {
                showDeactivateAlert = true
            } else {
                deleteModule(app.bundleId)
                dismiss()
            }
        } label: {
            Text("Deactivate")
                .font(AppFonts.caption)
                .foregroundColor(.red.opacity(0.8))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
        .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.red.opacity(0.08))
                )
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 20)
        .padding(.bottom, 16)
        .background(
            LinearGradient(
                colors: [Color(.systemGroupedBackground).opacity(0), Color(.systemGroupedBackground)],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 70)
            .allowsHitTesting(false)
        )
    }
}
#endif
