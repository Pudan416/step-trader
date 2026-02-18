import SwiftUI

// MARK: - Settings Sheet (minimal hub -> glass detail pages)
struct SettingsSheet: View {
    @ObservedObject var model: AppModel
    var onDone: (() -> Void)? = nil
    var embeddedInTab: Bool = false

    @StateObject private var authService = AuthenticationService.shared
    @Environment(\.appTheme) private var theme
    @Environment(\.topCardHeight) private var topCardHeight
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
                        settingsNavRow(icon: "arrow.down.app", title: "Shortcut") {
                            SettingsShortcutPage(model: model)
                        }
                        settingsNavRow(icon: "info.circle", title: "About") {
                            SettingsAboutPage(model: model)
                        }

                        Text("Less scrolling. More living.")
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
                .background(RoundedRectangle(cornerRadius: 16).fill(Color.primary.opacity(0.05)))
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
                .background(RoundedRectangle(cornerRadius: 16).fill(Color.primary.opacity(0.05)))
            }
            .buttonStyle(.plain)
        }
    }

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
            .background(RoundedRectangle(cornerRadius: 12).fill(Color.primary.opacity(0.05)))
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
    @AppStorage("testBgStepsNorm") private var testStepsNorm: Double = -1
    @AppStorage("testBgSleepNorm") private var testSleepNorm: Double = -1
    @Environment(\.topCardHeight) private var topCardHeight

    @State private var previewConfig: GradientPreviewConfig?

    var body: some View {
        ZStack {
            SettingsGradientBG(model: model)

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    DetailHeader(title: "Appearance")

                    VStack(alignment: .leading, spacing: 0) {
                        Text("THEME")
                            .font(.caption2.weight(.heavy))
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 14)
                            .padding(.top, 14)
                            .padding(.bottom, 8)

                        ForEach(Array(AppTheme.selectableThemes.enumerated()), id: \.element.rawValue) { index, option in
                            if index > 0 { DetailDivider() }
                            let isSelected = appThemeRaw == option.rawValue
                            Button {
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                    appThemeRaw = option.rawValue
                                }
                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            } label: {
                                HStack(spacing: 12) {
                                    Circle()
                                        .fill(swatchGradient(for: option))
                                        .frame(width: 28, height: 28)
                                        .overlay(Circle().strokeBorder(Color.primary.opacity(0.12), lineWidth: 1))

                                    Text(option.displayNameEn)
                                        .font(.subheadline.weight(isSelected ? .semibold : .regular))
                                        .foregroundColor(.primary)

                                    Spacer()

                                    if isSelected {
                                        Image(systemName: "checkmark")
                                            .font(.subheadline.weight(.semibold))
                                            .foregroundColor(AppColors.brandAccent)
                                    }
                                }
                                .padding(.horizontal, 14)
                                .padding(.vertical, 12)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .glassCard()

                    VStack(alignment: .leading, spacing: 0) {
                        Text("GRADIENT")
                            .font(.caption2.weight(.heavy))
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 14)
                            .padding(.top, 14)
                            .padding(.bottom, 8)

                        ForEach(Array(GradientStyle.allCases.enumerated()), id: \.element.rawValue) { index, style in
                            if index > 0 { DetailDivider() }
                            let isSelected = gradientStyleRaw == style.rawValue
                            Button {
                                previewConfig = GradientPreviewConfig(style: style)
                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            } label: {
                                HStack(spacing: 12) {
                                    gradientSwatch(for: style)
                                        .frame(width: 28, height: 28)
                                        .clipShape(RoundedRectangle(cornerRadius: 6))
                                        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color.primary.opacity(0.12), lineWidth: 1))

                                    Text(style.displayName)
                                        .font(.subheadline.weight(isSelected ? .semibold : .regular))
                                        .foregroundColor(.primary)

                                    Spacer()

                                    if isSelected {
                                        Image(systemName: "checkmark")
                                            .font(.subheadline.weight(.semibold))
                                            .foregroundColor(AppColors.brandAccent)
                                    }
                                }
                                .padding(.horizontal, 14)
                                .padding(.vertical, 12)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .glassCard()

                    // MARK: - TEST: All gradients × 3 states
                    VStack(alignment: .leading, spacing: 0) {
                        HStack {
                            Text("TEST")
                                .font(.caption2.weight(.heavy))
                                .foregroundColor(.secondary)
                            Spacer()
                            if testStepsNorm >= 0 {
                                Button {
                                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                        testStepsNorm = -1
                                        testSleepNorm = -1
                                    }
                                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                } label: {
                                    Text("Reset to live")
                                        .font(.caption2.weight(.semibold))
                                        .foregroundColor(AppColors.brandAccent)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, 14)
                        .padding(.top, 14)
                        .padding(.bottom, 8)

                        ForEach(Array(GradientStyle.allCases.enumerated()), id: \.element.rawValue) { index, style in
                            if index > 0 { DetailDivider() }
                            VStack(alignment: .leading, spacing: 6) {
                                Text(style.displayName)
                                    .font(.caption.weight(.semibold))
                                    .foregroundColor(.primary)

                                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                                    testGradientTile(style: style, stepsNorm: 1.0, sleepNorm: 1.0, label: "Full")
                                    testGradientTile(style: style, stepsNorm: 0.0, sleepNorm: 1.0, label: "Sleep only")
                                    testGradientTile(style: style, stepsNorm: 1.0, sleepNorm: 0.0, label: "Steps only")
                                    testGradientTile(style: style, stepsNorm: 0.0, sleepNorm: 0.0, label: "No data")
                                }
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                        }
                    }
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

    @ViewBuilder
    private func testGradientTile(style: GradientStyle, stepsNorm: Double, sleepNorm: Double, label: String) -> some View {
        let isActive = gradientStyleRaw == style.rawValue
            && testStepsNorm == stepsNorm
            && testSleepNorm == sleepNorm

        Button {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                gradientStyleRaw = style.rawValue
                testStepsNorm = stepsNorm
                testSleepNorm = sleepNorm
            }
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        } label: {
            VStack(spacing: 4) {
                Canvas { context, size in
                    let Ss = EnergyGradientRenderer.smoothstep(stepsNorm)
                    let Ls = EnergyGradientRenderer.smoothstep(sleepNorm)
                    let opacities = EnergyGradientRenderer.computeOpacities(
                        smoothedS: Ss,
                        smoothedL: Ls,
                        hasStepsData: stepsNorm > 0,
                        hasSleepData: sleepNorm > 0,
                        isDaylight: false
                    )
                    EnergyGradientRenderer.draw(
                        context: &context,
                        size: size,
                        opacities: opacities,
                        gradientStyle: style
                    )
                }
                .frame(height: 120)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(
                            isActive ? AppColors.brandAccent : Color.primary.opacity(0.1),
                            lineWidth: isActive ? 2 : 0.5
                        )
                )

                Text(label)
                    .font(.system(size: 9, weight: isActive ? .bold : .medium))
                    .foregroundColor(isActive ? AppColors.brandAccent : .secondary)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
    }

    private func swatchGradient(for option: AppTheme) -> some ShapeStyle {
        switch option {
        case .daylight:
            return LinearGradient(colors: [Color(white: 0.95), Color(white: 0.88)], startPoint: .topLeading, endPoint: .bottomTrailing)
        case .night:
            return LinearGradient(colors: [Color(red: 0.13, green: 0.16, blue: 0.19), Color(red: 0.08, green: 0.09, blue: 0.12)], startPoint: .topLeading, endPoint: .bottomTrailing)
        case .system:
            return LinearGradient(colors: [Color(white: 0.85), Color(red: 0.15, green: 0.17, blue: 0.21)], startPoint: .leading, endPoint: .trailing)
        }
    }

    @ViewBuilder
    private func gradientSwatch(for style: GradientStyle) -> some View {
        let darkToLight: [Color] = [
            EnergyGradientRenderer.night,
            EnergyGradientRenderer.navy,
            EnergyGradientRenderer.coral,
            EnergyGradientRenderer.gold
        ]
        switch style {
        case .radial:
            RadialGradient(
                colors: darkToLight.reversed(),
                center: .center,
                startRadius: 0,
                endRadius: 18
            )
        case .radialReversed:
            RadialGradient(
                colors: darkToLight,
                center: .center,
                startRadius: 0,
                endRadius: 18
            )
        case .linear:
            LinearGradient(colors: darkToLight, startPoint: .top, endPoint: .bottom)
        case .linearReversed:
            LinearGradient(colors: darkToLight.reversed(), startPoint: .top, endPoint: .bottom)
        }
    }
}

// MARK: - Gradient Preview Sheet (swipe-to-dismiss, shows 3 states)

private struct GradientPreviewSheet: View {
    let config: GradientPreviewConfig
    let onApply: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var isDaylight = false
    @State private var selectedState = 0

    private let states: [(steps: Double, sleep: Double, label: String)] = [
        (1.0, 1.0, "Full"),
        (0.0, 1.0, "Sleep only"),
        (1.0, 0.0, "Steps only"),
        (0.0, 0.0, "No data"),
    ]

    private var baseColor: Color {
        isDaylight ? EnergyGradientRenderer.daylightBase : EnergyGradientRenderer.night
    }

    var body: some View {
        ZStack {
            // Full-bleed gradient background for current state
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
                    gradientStyle: config.style
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
                                        gradientStyle: config.style
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

// MARK: - Shortcut Page

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
                    DetailHeader(title: "Shortcut")

                    VStack(alignment: .leading, spacing: 12) {
                    Text("Set today's energy canvas as your Lock Screen wallpaper automatically each time you close the app.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    VStack(alignment: .leading, spacing: 6) {
                        Text("1. Tap the button to add the shortcut")
                        Text("2. Open Shortcuts -> Automation -> + -> App")
                        Text("3. Select this app, pick \"Is Closed\"")
                        Text("4. Set the action to the shortcut")
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
                            Text("Get Shortcut")
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
                        if let url = URL(string: "mailto:kostill@gmail.com") {
                            openURL(url)
                        }
                    } label: {
                        HStack {
                            Text("Feedback")
                                .font(.subheadline)
                                .foregroundColor(.primary)
                            Spacer()
                            Text("kostill@gmail.com")
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
                }
                .glassCard()

                    Text("Less scrolling. More living.")
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
