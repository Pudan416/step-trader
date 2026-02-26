import SwiftUI

// MARK: - Settings Sheet (minimal hub -> glass detail pages)
struct SettingsSheet: View {
    @ObservedObject var model: AppModel
    var onDone: (() -> Void)? = nil
    var embeddedInTab: Bool = false

    @StateObject private var authService = AuthenticationService.shared
    @Environment(\.appTheme) private var theme
    @Environment(\.topCardHeight) private var topCardHeight
    @Environment(\.colorScheme) private var colorScheme
    @State private var showLogin = false
    @State private var showProfileEditor = false

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

                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Settings")
                            .font(.system(size: 28, weight: .bold, design: .rounded))
                            .foregroundColor(.primary)
                            .padding(.top, 8)

                        accountRow

                        settingsNavRow(icon: "paintpalette", title: "Appearance") {
                            SettingsAppearancePage(model: model)
                        }
                        settingsNavRow(icon: "bolt.fill", title: "Limits") {
                            SettingsEnergyPage(model: model)
                        }
                        settingsNavRow(icon: "arrow.down.app", title: "Wallpaper") {
                            SettingsShortcutPage(model: model)
                        }
                        settingsNavRow(icon: "info.circle", title: "About") {
                            SettingsAboutPage(model: model)
                        }

                        #if DEBUG
                        shieldDiagnosticsRow
                        #endif

                        Text("You are not nowhere. You are now here.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .frame(maxWidth: .infinity)
                            .padding(.top, 16)
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 96)
                }
            }
            .safeAreaInset(edge: .top, spacing: 0) {
                Color.clear.frame(height: embeddedInTab ? topCardHeight : 0)
            }
            .navigationBarHidden(true)
            .sheet(isPresented: $showLogin) {
                LoginView(authService: authService)
            }
            .sheet(isPresented: $showProfileEditor) {
                ProfileEditorView(authService: authService)
            }
        }
    }

    // MARK: - Account row

    @ViewBuilder
    private var accountRow: some View {
        if authService.isAuthenticated, let user = authService.currentUser {
            Button { showProfileEditor = true } label: {
                HStack(spacing: 12) {
                    accountAvatar(user: user)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(user.displayName)
                            .font(.subheadline.weight(.medium))
                            .foregroundColor(.primary)
                        if let email = user.email {
                            Text(email)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption2)
                        .foregroundColor(.secondary.opacity(0.5))
                }
                .padding(14)
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(colorScheme == .dark ? Color.black.opacity(0.28) : Color.primary.opacity(0.05))
                )
            }
            .buttonStyle(.plain)
        } else {
            Button { showLogin = true } label: {
                HStack(spacing: 8) {
                    Image(systemName: "apple.logo")
                        .font(.subheadline)
                    Text("Sign in with Apple")
                        .font(.subheadline.weight(.medium))
                    Spacer()
                }
                .foregroundColor(.primary)
                .padding(14)
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(colorScheme == .dark ? Color.black.opacity(0.28) : Color.primary.opacity(0.05))
                )
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Shield Diagnostics (DEBUG only)

    #if DEBUG
    @State private var diagCopied = false

    private var shieldDiagnosticsRow: some View {
        VStack(spacing: 8) {
            // Copy diagnostics
            Button {
                let text = model.blockingStore.dumpShieldDiagnostics()
                UIPasteboard.general.string = text
                diagCopied = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) { diagCopied = false }
            } label: {
                diagButton(
                    icon: "shield.lefthalf.filled",
                    text: diagCopied ? "Copied to clipboard!" : "Copy Shield Diagnostics",
                    color: .orange,
                    highlight: diagCopied,
                    trailing: "doc.on.clipboard"
                )
            }
            .buttonStyle(.plain)
        }
    }

    private func diagButton(icon: String, text: String, color: Color, highlight: Bool = false, trailing: String? = nil) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.subheadline)
                .foregroundColor(color)
                .frame(width: 24)
            Text(text)
                .font(.subheadline)
                .foregroundColor(highlight ? .green : .primary)
            Spacer()
            if let trailing {
                Image(systemName: trailing)
                    .font(.caption2)
                    .foregroundColor(.secondary.opacity(0.5))
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 14)
        .background(RoundedRectangle(cornerRadius: 12).fill(color.opacity(0.08)))
    }
    #endif

    // MARK: - Navigation row

    private func settingsNavRow<Dest: View>(icon: String, title: String, @ViewBuilder destination: () -> Dest) -> some View {
        NavigationLink(destination: destination) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .frame(width: 24)
                Text(title)
                    .font(.subheadline)
                    .foregroundColor(.primary)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption2)
                    .foregroundColor(.secondary.opacity(0.5))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(colorScheme == .dark ? Color.black.opacity(0.28) : Color.primary.opacity(0.05))
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Avatar

    @ViewBuilder
    private func accountAvatar(user: AppUser) -> some View {
        if let data = user.avatarData, let uiImage = UIImage(data: data) {
            Image(uiImage: uiImage)
                .resizable()
                .scaledToFill()
                .frame(width: 40, height: 40)
                .clipShape(Circle())
        } else {
            ZStack {
                Circle()
                    .fill(Color.primary.opacity(0.08))
                    .frame(width: 40, height: 40)
                Text(String(user.displayName.prefix(2)).uppercased())
                    .font(.caption.weight(.bold))
                    .foregroundColor(.primary)
            }
        }
    }
}

// MARK: - Detail page header (replaces hidden nav bar)

private struct DetailHeader: View {
    let title: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        HStack {
            Button { dismiss() } label: {
                HStack(spacing: 4) {
                    Image(systemName: "chevron.left")
                        .font(.subheadline.weight(.semibold))
                    Text("Back")
                        .font(.subheadline)
                }
                .foregroundColor(.primary)
            }
            Spacer()
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundColor(.primary)
            Spacer()
            Color.clear.frame(width: 50, height: 1)
        }
        .padding(.top, 4)
        .padding(.bottom, 8)
    }
}

// MARK: - Shared detail page helpers

private struct DetailDivider: View {
    var body: some View {
        Rectangle()
            .fill(Color.primary.opacity(0.08))
            .frame(height: 0.5)
            .padding(.leading, 14)
    }
}

private struct DetailInfoRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
                .font(.subheadline)
                .foregroundColor(.primary)
            Spacer()
            Text(value)
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }
}

// MARK: - Shared gradient background for detail pages

private struct SettingsGradientBG: View {
    @ObservedObject var model: AppModel

    var body: some View {
        EnergyGradientBackground(
            stepsPoints: model.stepsPointsToday,
            sleepPoints: model.sleepPointsToday,
            hasStepsData: model.hasStepsData,
            hasSleepData: model.hasSleepData
        )
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }
}

// MARK: - Appearance Page

private struct GradientPreviewConfig: Identifiable {
    let id = UUID()
    let style: GradientStyle
}

private struct SettingsAppearancePage: View {
    @ObservedObject var model: AppModel
    @AppStorage("appTheme") private var appThemeRaw: String = AppTheme.system.rawValue
    @AppStorage("gradientStyle_v1") private var gradientStyleRaw: String = GradientStyle.radial.rawValue
    @AppStorage("gradientPalette_v1") private var gradientPaletteRaw: String = GradientPalette.warmSunset.rawValue
    @Environment(\.topCardHeight) private var topCardHeight

    @State private var previewConfig: GradientPreviewConfig?

    private var activePalette: EnergyGradientRenderer.Palette {
        EnergyGradientRenderer.palette(for: GradientPalette(rawValue: gradientPaletteRaw) ?? .warmSunset)
    }

    var body: some View {
        ZStack {
            SettingsGradientBG(model: model)

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    DetailHeader(title: "Appearance")
                        .padding(.horizontal, 16)

                    // MARK: Theme — segmented pill
                    VStack(alignment: .leading, spacing: 10) {
                        sectionLabel("THEME")

                        HStack(spacing: 0) {
                            ForEach(AppTheme.selectableThemes, id: \.rawValue) { option in
                                let isSelected = appThemeRaw == option.rawValue
                                Button {
                                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                        appThemeRaw = option.rawValue
                                    }
                                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                } label: {
                                    Text(option.displayNameEn)
                                        .font(.caption.weight(isSelected ? .bold : .medium))
                                        .foregroundColor(isSelected ? .primary : .secondary)
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 10)
                                        .background(
                                            isSelected
                                                ? AnyShapeStyle(Color.primary.opacity(0.1))
                                                : AnyShapeStyle(Color.clear)
                                        )
                                        .clipShape(Capsule())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(3)
                        .background(Capsule().fill(Color.primary.opacity(0.04)))
                    }
                    .padding(.horizontal, 16)

                    // MARK: Palette — horizontal color row
                    VStack(alignment: .leading, spacing: 10) {
                        sectionLabel("COLORS")

                        HStack(spacing: 12) {
                            ForEach(GradientPalette.allCases, id: \.rawValue) { scheme in
                                let isSelected = gradientPaletteRaw == scheme.rawValue
                                Button {
                                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                        gradientPaletteRaw = scheme.rawValue
                                    }
                                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                } label: {
                                    VStack(spacing: 6) {
                                        let pal = EnergyGradientRenderer.palette(for: scheme)
                                        RoundedRectangle(cornerRadius: 10)
                                            .fill(LinearGradient(
                                                colors: [pal.bright, pal.warm, pal.cool, pal.dark],
                                                startPoint: .topLeading,
                                                endPoint: .bottomTrailing
                                            ))
                                            .frame(height: 44)
                                            .overlay(
                                                RoundedRectangle(cornerRadius: 10)
                                                    .strokeBorder(
                                                        isSelected ? AppColors.brandAccent : Color.clear,
                                                        lineWidth: 2
                                                    )
                                            )

                                        Text(scheme.displayName)
                                            .font(.system(size: 10, weight: isSelected ? .bold : .medium))
                                            .foregroundColor(isSelected ? .primary : .secondary)
                                    }
                                    .frame(maxWidth: .infinity)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .padding(.horizontal, 16)

                    // MARK: Gradient — visual swatch grid
                    VStack(alignment: .leading, spacing: 10) {
                        sectionLabel("GRADIENT")

                        let columns = [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)]
                        LazyVGrid(columns: columns, spacing: 10) {
                            ForEach(GradientStyle.allCases, id: \.rawValue) { style in
                                let isSelected = gradientStyleRaw == style.rawValue
                                Button {
                                    previewConfig = GradientPreviewConfig(style: style)
                                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                } label: {
                                    VStack(spacing: 6) {
                                        Canvas { context, size in
                                            let pal = activePalette
                                            let opacities = EnergyGradientRenderer.computeOpacities(
                                                smoothedS: 0.8,
                                                smoothedL: 0.6,
                                                hasStepsData: true,
                                                hasSleepData: true,
                                                isDaylight: false
                                            )
                                            EnergyGradientRenderer.draw(
                                                context: &context,
                                                size: size,
                                                opacities: opacities,
                                                baseColor: pal.dark,
                                                gradientStyle: style,
                                                colorPalette: pal
                                            )
                                        }
                                        .frame(height: 80)
                                        .clipShape(RoundedRectangle(cornerRadius: 10))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 10)
                                                .strokeBorder(
                                                    isSelected ? AppColors.brandAccent : Color.white.opacity(0.08),
                                                    lineWidth: isSelected ? 2 : 0.5
                                                )
                                        )

                                        Text(style.displayName)
                                            .font(.system(size: 10, weight: isSelected ? .bold : .medium))
                                            .foregroundColor(isSelected ? .primary : .secondary)
                                    }
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                }
                .padding(.bottom, 80)
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            Color.clear.frame(height: topCardHeight)
        }
        .navigationBarHidden(true)
        .sheet(item: $previewConfig) { config in
            GradientPreviewSheet(
                config: config,
                onApply: {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        gradientStyleRaw = config.style.rawValue
                    }
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    previewConfig = nil
                }
            )
            .presentationBackground(.clear)
        }
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(.caption2.weight(.heavy))
            .foregroundColor(.secondary)
    }
}

// MARK: - Gradient Preview Sheet (swipe-to-dismiss, shows 3 states)

private struct GradientPreviewSheet: View {
    let config: GradientPreviewConfig
    let onApply: () -> Void

    @Environment(\.dismiss) private var dismiss
    @AppStorage("gradientPalette_v1") private var gradientPaletteRaw: String = GradientPalette.warmSunset.rawValue
    @State private var isDaylight = false
    @State private var selectedState = 0

    private let states: [(steps: Double, sleep: Double, label: String)] = [
        (1.0, 1.0, "Full"),
        (0.0, 1.0, "Sleep only"),
        (1.0, 0.0, "Steps only"),
        (0.0, 0.0, "No data"),
    ]

    private var pal: EnergyGradientRenderer.Palette {
        EnergyGradientRenderer.palette(for: GradientPalette(rawValue: gradientPaletteRaw) ?? .warmSunset)
    }

    private var baseColor: Color {
        isDaylight ? pal.daylightBase : pal.dark
    }

    var body: some View {
        ZStack {
            Canvas { context, size in
                let st = states[selectedState]
                let Ss = EnergyGradientRenderer.smoothstep(st.steps)
                let Ls = EnergyGradientRenderer.smoothstep(st.sleep)
                let opacities = EnergyGradientRenderer.computeOpacities(
                    smoothedS: Ss,
                    smoothedL: Ls,
                    hasStepsData: st.steps > 0,
                    hasSleepData: st.sleep > 0,
                    isDaylight: isDaylight
                )
                EnergyGradientRenderer.draw(
                    context: &context,
                    size: size,
                    opacities: opacities,
                    baseColor: baseColor,
                    gradientStyle: config.style,
                    colorPalette: pal
                )
            }
            .ignoresSafeArea()
            .overlay {
                Image("grain 1")
                    .resizable()
                    .scaledToFill()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipped()
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
                    .opacity(0.4)
                    .blendMode(.overlay)
            }

            VStack(spacing: 0) {
                // Top bar: title left, close right
                HStack {
                    Text(config.style.displayName)
                        .font(.headline.weight(.semibold))
                        .foregroundColor(.white)
                    Spacer()
                    Button { dismiss() } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title2)
                            .symbolRenderingMode(.hierarchical)
                            .foregroundColor(.white.opacity(0.7))
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)

                Spacer()

                // State picker (2×2 grid)
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                    ForEach(Array(states.enumerated()), id: \.offset) { index, state in
                        Button {
                            withAnimation(.easeInOut(duration: 0.4)) { selectedState = index }
                        } label: {
                            VStack(spacing: 5) {
                                Canvas { context, size in
                                    let Ss = EnergyGradientRenderer.smoothstep(state.steps)
                                    let Ls = EnergyGradientRenderer.smoothstep(state.sleep)
                                    let opacities = EnergyGradientRenderer.computeOpacities(
                                        smoothedS: Ss,
                                        smoothedL: Ls,
                                        hasStepsData: state.steps > 0,
                                        hasSleepData: state.sleep > 0,
                                        isDaylight: isDaylight
                                    )
                                    EnergyGradientRenderer.draw(
                                        context: &context,
                                        size: size,
                                        opacities: opacities,
                                        baseColor: baseColor,
                                        gradientStyle: config.style,
                                        colorPalette: pal
                                    )
                                }
                                .frame(height: 72)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8)
                                        .strokeBorder(
                                            selectedState == index ? Color.white : Color.white.opacity(0.15),
                                            lineWidth: selectedState == index ? 2 : 0.5
                                        )
                                )

                                Text(state.label)
                                    .font(.system(size: 10, weight: selectedState == index ? .bold : .medium))
                                    .foregroundColor(selectedState == index ? .white : .white.opacity(0.5))
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 20)

                // Day / Night toggle
                HStack(spacing: 0) {
                    modeButton(title: "Night", icon: "moon.fill", isActive: !isDaylight) {
                        withAnimation(.easeInOut(duration: 0.6)) { isDaylight = false }
                    }
                    modeButton(title: "Daylight", icon: "sun.max.fill", isActive: isDaylight) {
                        withAnimation(.easeInOut(duration: 0.6)) { isDaylight = true }
                    }
                }
                .background(Capsule().fill(.ultraThinMaterial))
                .padding(.top, 16)

                // Apply button
                Button {
                    onApply()
                } label: {
                    Text("Apply")
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.black)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Capsule().fill(AppColors.brandAccent))
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 40)
                .padding(.top, 16)
                .padding(.bottom, 32)
            }
        }
    }

    @ViewBuilder
    private func modeButton(title: String, icon: String, isActive: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.caption)
                Text(title)
                    .font(.caption.weight(.semibold))
            }
            .foregroundColor(isActive ? .white : .white.opacity(0.5))
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(
                isActive ? AnyShapeStyle(Color.white.opacity(0.2)) : AnyShapeStyle(Color.clear)
            )
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Energy Page

private struct SettingsEnergyPage: View {
    @ObservedObject var model: AppModel
    @AppStorage("userStepsTarget") private var stepsTarget: Double = EnergyDefaults.stepsTarget
    @AppStorage("userSleepTarget") private var sleepTarget: Double = EnergyDefaults.sleepTargetHours
    @AppStorage("dayEndHour_v1") private var dayEndHourSetting: Int = 0
    @AppStorage("dayEndMinute_v1") private var dayEndMinuteSetting: Int = 0
    @Environment(\.topCardHeight) private var topCardHeight

    var body: some View {
        ZStack {
            SettingsGradientBG(model: model)

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    DetailHeader(title: "Limits")

                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Image(systemName: "figure.walk")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                                .frame(width: 24)
                            Text("Steps goal")
                                .font(.subheadline)
                                .foregroundColor(.primary)
                            Spacer()
                            Text(formatCompactNumber(Int(stepsTarget)))
                                .font(.subheadline.weight(.semibold).monospacedDigit())
                                .foregroundColor(.primary)
                        }
                        Slider(value: $stepsTarget, in: 5_000...15_000, step: 500)
                            .tint(AppColors.brandAccent)
                        HStack {
                            Text("5K").font(.caption2).foregroundColor(.secondary)
                            Spacer()
                            Text("15K").font(.caption2).foregroundColor(.secondary)
                        }
                    }
                    .padding(14)
                    .glassCard()
                    .onChange(of: stepsTarget) { _, _ in
                        UserDefaults.stepsTrader().set(stepsTarget, forKey: "userStepsTarget")
                        model.recalculateDailyEnergy()
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Image(systemName: "bed.double.fill")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                                .frame(width: 24)
                            Text("Sleep goal")
                                .font(.subheadline)
                                .foregroundColor(.primary)
                            Spacer()
                            Text(String(format: "%.1fh", sleepTarget))
                                .font(.subheadline.weight(.semibold).monospacedDigit())
                                .foregroundColor(.primary)
                        }
                        Slider(value: $sleepTarget, in: 6...10, step: 0.5)
                            .tint(AppColors.brandAccent)
                        HStack {
                            Text("6h").font(.caption2).foregroundColor(.secondary)
                            Spacer()
                            Text("10h").font(.caption2).foregroundColor(.secondary)
                        }
                    }
                    .padding(14)
                    .glassCard()
                    .onChange(of: sleepTarget) { _, _ in
                        UserDefaults.stepsTrader().set(sleepTarget, forKey: "userSleepTarget")
                        model.recalculateDailyEnergy()
                    }

                    NavigationLink {
                        DayEndSettingsView(model: model)
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "clock.arrow.circlepath")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                                .frame(width: 24)
                            Text("Day resets at")
                                .font(.subheadline)
                                .foregroundColor(.primary)
                            Spacer()
                            Text(formattedDayEnd)
                                .font(.subheadline.monospacedDigit())
                                .foregroundColor(.secondary)
                            Image(systemName: "chevron.right")
                                .font(.caption2)
                                .foregroundColor(.secondary.opacity(0.5))
                        }
                        .padding(14)
                        .glassCard()
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 32)
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            Color.clear.frame(height: topCardHeight)
        }
        .navigationBarHidden(true)
    }

    private var formattedDayEnd: String {
        var comps = DateComponents()
        comps.hour = dayEndHourSetting
        comps.minute = dayEndMinuteSetting
        let date = Calendar.current.date(from: comps) ?? Date()
        return CachedFormatters.hourMinute.string(from: date)
    }

}

// MARK: - Wallpaper Page

private struct SettingsShortcutPage: View {
    @ObservedObject var model: AppModel
    @Environment(\.topCardHeight) private var topCardHeight
    @Environment(\.openURL) private var openURL

    private let shortcutURL = URL(string: "https://www.icloud.com/shortcuts/e32b44858d5f4c829b35c9f8ad5f2756")!

    var body: some View {
        ZStack {
            SettingsGradientBG(model: model)

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    DetailHeader(title: "Wallpaper")

                    VStack(alignment: .leading, spacing: 12) {
                    Text("Set today's energy canvas as your Lock Screen wallpaper automatically each time you close the app.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    VStack(alignment: .leading, spacing: 6) {
                        Text("1. Tap the button to add the wallpaper shortcut")
                        Text("2. Open Shortcuts → Automation → + → App")
                        Text("3. Select this app, pick \"Is Closed\"")
                        Text("4. Set the action to the wallpaper shortcut")
                        Text("5. Turn off \"Ask Before Running\"")
                    }
                    .font(.caption)
                    .foregroundColor(.secondary.opacity(0.7))

                    Button {
                        openURL(shortcutURL)
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "square.and.arrow.down")
                                .font(.caption.weight(.semibold))
                            Text("Get Wallpaper Shortcut")
                                .font(.subheadline.weight(.semibold))
                        }
                        .foregroundColor(.black)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(Capsule().fill(AppColors.brandAccent))
                    }
                    .buttonStyle(.plain)
                }
                .padding(14)
                .glassCard()
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 32)
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            Color.clear.frame(height: topCardHeight)
        }
        .navigationBarHidden(true)
    }
}

// MARK: - About Page

private struct SettingsAboutPage: View {
    @ObservedObject var model: AppModel
    @Environment(\.topCardHeight) private var topCardHeight
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.openURL) private var openURL

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }

    var body: some View {
        ZStack {
            SettingsGradientBG(model: model)

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    DetailHeader(title: "About")

                    VStack(alignment: .leading, spacing: 0) {
                    DetailInfoRow(label: "Developer", value: "Konstantin Pudan")
                    DetailDivider()
                    DetailInfoRow(label: "Version", value: appVersion)
                    DetailDivider()
                    Button {
                        if let url = URL(string: "mailto:we.live.now.here@gmail.com") {
                            openURL(url)
                        }
                    } label: {
                        HStack {
                            Text("Feedback")
                                .font(.subheadline)
                                .foregroundColor(.primary)
                            Spacer()
                            Text("we.live.now.here@gmail.com")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Image(systemName: "envelope")
                                .font(.caption2)
                                .foregroundColor(.secondary.opacity(0.5))
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                    }
                    .buttonStyle(.plain)
                    DetailDivider()
                    Button {
                        if let url = URL(string: "https://t.me/now_here_admin") {
                            openURL(url)
                        }
                    } label: {
                        HStack {
                            Text("Telegram")
                                .font(.subheadline)
                                .foregroundColor(.primary)
                            Spacer()
                            Text("@now_here_admin")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Image(systemName: "paperplane")
                                .font(.caption2)
                                .foregroundColor(.secondary.opacity(0.5))
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                    }
                    .buttonStyle(.plain)
                    }
                .glassCard()

                    Text("You are not nowhere. You are now here.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 8)

                }
                .padding(.horizontal, 16)
                .padding(.bottom, 32)
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            Color.clear.frame(height: topCardHeight)
        }
        .navigationBarHidden(true)
    }
}
