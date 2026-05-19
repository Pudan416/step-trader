import SwiftUI
import AuthenticationServices
#if canImport(UIKit)
import UIKit
#endif

struct PaywallView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var store: SubscriptionStore
    var source: PaywallSource = .general

    @Environment(\.dismiss) private var dismiss
    @Environment(\.appTheme) private var theme
    @Environment(\.openURL) private var openURL

    @State private var selectedPackageID: String?
    @State private var purchaseInFlight = false
    @State private var purchaseError: String?
    @State private var didPurchaseSucceed = false
    @State private var showPostPurchaseLogin = false
    @State private var appeared = false

    private var authService: AuthenticationService { .shared }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            backgroundGradient
                .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 0) {
                    hero
                        .padding(.top, 60)
                        .padding(.horizontal, 24)

                    benefits
                        .padding(.top, 40)
                        .padding(.horizontal, 28)

                    plans
                        .padding(.top, 36)
                        .padding(.horizontal, 20)

                    Spacer(minLength: 180)
                }
            }
            .scrollIndicators(.hidden)

            closeButton
                .padding(.top, 8)
                .padding(.trailing, 8)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            stickyBottom
        }
        .task {
            if store.packages.isEmpty {
                await store.refresh()
            }
            if selectedPackageID == nil {
                selectedPackageID = preferredDefaultPackage()?.id
            }
            withAnimation(.easeOut(duration: 0.6).delay(0.1)) {
                appeared = true
            }
        }
        .alert("Purchase Failed", isPresented: errorBinding) {
            Button("OK", role: .cancel) { purchaseError = nil }
        } message: {
            Text(purchaseError ?? "")
        }
        .onChange(of: store.isPro) { _, isPro in
            if isPro && didPurchaseSucceed {
                if authService.isAuthenticated {
                    dismiss()
                } else {
                    showPostPurchaseLogin = true
                }
            }
        }
        .sheet(isPresented: $showPostPurchaseLogin, onDismiss: { dismiss() }) {
            PostPurchaseLoginPrompt(authService: authService)
        }
    }

    // MARK: - Background

    private var backgroundGradient: some View {
        LinearGradient(
            colors: [
                Color(red: 0.06, green: 0.07, blue: 0.14),
                Color(red: 0.08, green: 0.10, blue: 0.20),
                Color(red: 0.05, green: 0.05, blue: 0.12)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
        .overlay(alignment: .top) {
            Ellipse()
                .fill(
                    RadialGradient(
                        colors: [
                            AppColors.brandAccent.opacity(0.18),
                            AppColors.brandAccent.opacity(0.04),
                            Color.clear
                        ],
                        center: .center,
                        startRadius: 10,
                        endRadius: 260
                    )
                )
                .frame(width: 500, height: 400)
                .offset(y: -80)
                .blur(radius: 30)
        }
    }

    // MARK: - Close

    private var closeButton: some View {
        Button { dismiss() } label: {
            Image(systemName: "xmark")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white.opacity(0.5))
                .frame(width: 30, height: 30)
                .background(.white.opacity(0.08), in: Circle())
        }
        .buttonStyle(.plain)
        .frame(width: 44, height: 44)
        .contentShape(Circle())
        .accessibilityLabel(String(localized: "Close"))
    }

    // MARK: - Hero

    private var hero: some View {
        VStack(spacing: 16) {
            Image(systemName: "sparkles")
                .font(.system(size: 36, weight: .medium))
                .foregroundStyle(AppColors.brandAccent)
                .symbolRenderingMode(.hierarchical)
                .opacity(appeared ? 1 : 0)
                .scaleEffect(appeared ? 1 : 0.6)

            Text(headline)
                .font(.systemSerif(38, weight: .bold, relativeTo: .largeTitle))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .opacity(appeared ? 1 : 0)
                .offset(y: appeared ? 0 : 12)

            Text(subheadline)
                .font(.callout)
                .foregroundStyle(.white.opacity(0.55))
                .multilineTextAlignment(.center)
                .lineLimit(3)
                .padding(.horizontal, 12)
                .opacity(appeared ? 1 : 0)
                .offset(y: appeared ? 0 : 8)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Benefits

    private var benefits: some View {
        VStack(alignment: .leading, spacing: 20) {
            benefitRow(icon: "infinity", text: String(localized: "Unlimited app blocks"))
            benefitRow(icon: "paintpalette", text: String(localized: "Custom activities & themes"))
            benefitRow(icon: "calendar.badge.clock", text: String(localized: "Full 90-day history"))
            benefitRow(icon: "heart.fill", text: String(localized: "Support indie development"))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared ? 0 : 16)
    }

    private func benefitRow(icon: String, text: String) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(AppColors.brandAccent)
                .frame(width: 22)
            Text(text)
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.85))
        }
    }

    // MARK: - Plans

    @ViewBuilder
    private var plans: some View {
        if store.packages.isEmpty {
            if let err = store.lastError {
                packagesErrorState(message: err)
            } else {
                HStack(spacing: 10) {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .tint(AppColors.brandAccent)
                    Text(String(localized: "Loading plans…"))
                        .font(.footnote)
                        .foregroundStyle(.white.opacity(0.4))
                }
                .frame(maxWidth: .infinity, minHeight: 100)
            }
        } else {
            VStack(spacing: 10) {
                ForEach(orderedPackages) { package in
                    planCard(package: package)
                }
            }
            .opacity(appeared ? 1 : 0)
            .offset(y: appeared ? 0 : 20)
        }
    }

    private func planCard(package: PurchasePackage) -> some View {
        let isSelected = selectedPackageID == package.id
        let badge: String? = {
            if isLifetime(package) { return String(localized: "Forever") }
            if (package.durationDays ?? 0) >= 300 { return String(localized: "Best value") }
            return nil
        }()

        // TODO: Migrate to .sensoryFeedback() modifiers
        return Button {
            #if canImport(UIKit)
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            #endif
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                selectedPackageID = package.id
            }
        } label: {
            HStack(spacing: 14) {
                // Radio
                ZStack {
                    Circle()
                        .stroke(
                            isSelected ? AppColors.brandAccent : .white.opacity(0.2),
                            lineWidth: 1.5
                        )
                        .frame(width: 20, height: 20)
                    if isSelected {
                        Circle()
                            .fill(AppColors.brandAccent)
                            .frame(width: 10, height: 10)
                            .transition(.scale.combined(with: .opacity))
                    }
                }
                .animation(.spring(response: 0.25, dampingFraction: 0.7), value: isSelected)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 8) {
                        Text(packageDisplayTitle(package))
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white)
                        if let badge {
                            Text(badge)
                                .font(.system(size: 9, weight: .heavy))
                                .tracking(0.3)
                                .textCase(.uppercase)
                                .foregroundStyle(AppAccentInk.primary)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2.5)
                                .background(Capsule().fill(AppColors.brandAccent))
                        }
                    }
                    if let secondary = packageSecondaryLine(package) {
                        Text(secondary)
                            .font(.caption)
                            .foregroundStyle(secondaryLineColor(for: package))
                    }
                }

                Spacer(minLength: 4)

                VStack(alignment: .trailing, spacing: 1) {
                    Text(package.priceString)
                        .font(.system(size: 17, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                    if !isLifetime(package),
                       let perMonth = package.pricePerMonthString,
                       !isMonthly(package) {
                        Text(String(localized: "\(perMonth)/mo"))
                            .font(.caption2)
                            .foregroundStyle(.white.opacity(0.4))
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(isSelected ? .white.opacity(0.08) : .white.opacity(0.03))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(
                        isSelected ? AppColors.brandAccent.opacity(0.8) : .white.opacity(0.08),
                        lineWidth: isSelected ? 1.5 : 0.5
                    )
            )
        }
        .buttonStyle(ScaleButtonStyle())
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? [.isSelected, .isButton] : [.isButton])
    }

    private func packagesErrorState(message: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "wifi.exclamationmark")
                .font(.system(size: 24, weight: .regular))
                .foregroundStyle(.white.opacity(0.3))
            Text(String(localized: "Couldn't load plans"))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white.opacity(0.8))
            Text(message)
                .font(.caption)
                .foregroundStyle(.white.opacity(0.4))
                .multilineTextAlignment(.center)
                .lineLimit(3)
            // TODO: Migrate to .sensoryFeedback() modifiers
            Button {
                store.clearLastError()
                Task { await store.refresh() }
                #if canImport(UIKit)
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                #endif
            } label: {
                Text(String(localized: "Retry"))
                    .font(.footnote.weight(.bold))
                    .foregroundStyle(AppAccentInk.primary)
                    .padding(.horizontal, 22)
                    .padding(.vertical, 10)
                    .background(Capsule().fill(AppColors.brandAccent))
            }
            .buttonStyle(ScaleButtonStyle())
        }
        .padding(24)
        .frame(maxWidth: .infinity)
    }

    // MARK: - Sticky bottom

    private var stickyBottom: some View {
        VStack(spacing: 6) {
            Button {
                Task { await purchaseSelected() }
            } label: {
                ZStack {
                    if purchaseInFlight {
                        ProgressView().tint(AppAccentInk.primary)
                    } else {
                        Text(purchaseButtonTitle)
                            .font(.headline.weight(.bold))
                            .foregroundStyle(AppAccentInk.primary)
                    }
                }
                .frame(maxWidth: .infinity, minHeight: 52)
                .background(
                    Capsule()
                        .fill(canPurchase
                              ? AppColors.brandAccent
                              : AppColors.brandAccent.opacity(0.35))
                )
            }
            .buttonStyle(ScaleButtonStyle())
            .disabled(!canPurchase || purchaseInFlight)
            .padding(.horizontal, 20)

            Text(microDisclosure)
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.35))
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .padding(.horizontal, 28)

            HStack(spacing: 0) {
                footerLink(String(localized: "Restore")) {
                    Task { await restore() }
                }
                footerDot
                footerLink(String(localized: "Terms")) {
                    if let url = URL(string: "https://nowhere.pudan.me/terms.html") {
                        openURL(url)
                    }
                }
                footerDot
                footerLink(String(localized: "Privacy")) {
                    if let url = URL(string: "https://nowhere.pudan.me/privacy.html") {
                        openURL(url)
                    }
                }
                footerDot
                footerLink(String(localized: "Code")) {
                    store.presentRedeemCodeSheet()
                }
            }
            .padding(.horizontal, 12)
        }
        .padding(.top, 14)
        .padding(.bottom, 6)
        .background {
            Rectangle()
                .fill(.ultraThinMaterial)
                .overlay(alignment: .top) {
                    Rectangle()
                        .fill(.white.opacity(0.06))
                        .frame(height: 0.5)
                }
                .ignoresSafeArea(edges: .bottom)
        }
    }

    private var footerDot: some View {
        Text("·")
            .font(.caption)
            .foregroundStyle(.white.opacity(0.25))
    }

    private func footerLink(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.white.opacity(0.45))
                .frame(maxWidth: .infinity, minHeight: 36)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Logic

    private var orderedPackages: [PurchasePackage] {
        store.packages.sorted { lhs, rhs in
            if isLifetime(lhs) && !isLifetime(rhs) { return true }
            if !isLifetime(lhs) && isLifetime(rhs) { return false }
            return (lhs.durationDays ?? 0) > (rhs.durationDays ?? 0)
        }
    }

    private func preferredDefaultPackage() -> PurchasePackage? {
        orderedPackages.first(where: { ($0.durationDays ?? 0) >= 300 })
            ?? orderedPackages.first(where: { !isLifetime($0) })
            ?? orderedPackages.first
    }

    private func isLifetime(_ package: PurchasePackage) -> Bool {
        package.productId == SubscriptionIDs.Product.lifetime
            || (package.durationDays == nil && package.productId.contains("lifetime"))
    }

    private var canPurchase: Bool {
        selectedPackageID != nil && !store.packages.isEmpty
    }

    private var purchaseButtonTitle: String {
        if let pkg = selectedPackage(), pkg.introOfferDescription != nil {
            return String(localized: "Start Free Trial")
        }
        return String(localized: "Continue")
    }

    private func selectedPackage() -> PurchasePackage? {
        guard let id = selectedPackageID else { return nil }
        return store.packages.first(where: { $0.id == id })
    }

    private func purchaseSelected() async {
        guard let pkg = selectedPackage() else { return }
        purchaseInFlight = true
        defer { purchaseInFlight = false }
        let result = await store.purchase(pkg)
        switch result {
        case .success:
            didPurchaseSucceed = true
        case .userCancelled:
            break
        case .pending:
            purchaseError = String(localized: "Your purchase is pending approval (Ask to Buy?). It will activate once approved.")
        case .failed(let error):
            purchaseError = error.localizedDescription
        }
    }

    private func restore() async {
        purchaseInFlight = true
        defer { purchaseInFlight = false }
        let result = await store.restore()
        switch result {
        case .success:
            if store.isPro {
                didPurchaseSucceed = true
            } else {
                purchaseError = String(localized: "No active subscription found on this Apple ID.")
            }
        case .failed(let error):
            purchaseError = error.localizedDescription
        case .userCancelled, .pending:
            break
        }
    }

    private func packageDisplayTitle(_ package: PurchasePackage) -> String {
        if isLifetime(package) { return String(localized: "Lifetime") }
        if let days = package.durationDays {
            switch days {
            case 365: return String(localized: "Yearly")
            case 180: return String(localized: "6 months")
            case 90:  return String(localized: "3 months")
            case 30:  return String(localized: "Monthly")
            case 7:   return String(localized: "Weekly")
            default:  return package.title
            }
        }
        return package.title
    }

    private func packageSecondaryLine(_ package: PurchasePackage) -> String? {
        if isLifetime(package) { return String(localized: "One-time payment") }
        if let intro = package.introOfferDescription { return intro }
        return nil
    }

    private func secondaryLineColor(for package: PurchasePackage) -> Color {
        if isLifetime(package) || package.introOfferDescription != nil {
            return AppColors.brandAccent
        }
        return .white.opacity(0.45)
    }

    private func isMonthly(_ package: PurchasePackage) -> Bool {
        guard let days = package.durationDays else { return false }
        return days <= 31
    }

    // MARK: - Copy

    private var headline: String {
        switch source {
        case .general:   return String(localized: "Stay here.")
        case .feature:   return String(localized: "Unlock Pro.")
        case .promotion: return String(localized: "Welcome offer.")
        }
    }

    private var subheadline: String {
        String(localized: "Less screen. More now.\nSupport a tool that doesn't sell your attention.")
    }

    private var microDisclosure: String {
        guard let pkg = selectedPackage() else {
            return String(localized: "Cancel anytime in iOS Settings.")
        }
        if isLifetime(pkg) {
            return String(localized: "\(pkg.priceString) one-time. Yours forever.")
        }
        let priceClause: String = {
            if let noun = canonicalPeriodShorthand(pkg) {
                return "\(pkg.priceString)/\(noun)"
            }
            if let days = pkg.durationDays {
                return String(localized: "\(pkg.priceString) every \(days) days")
            }
            return pkg.priceString
        }()
        if pkg.introOfferDescription != nil {
            return String(localized: "Free trial, then \(priceClause). Auto-renews. Cancel anytime.")
        }
        return String(localized: "\(priceClause). Auto-renews. Cancel anytime.")
    }

    private func canonicalPeriodShorthand(_ package: PurchasePackage) -> String? {
        guard let days = package.durationDays else { return nil }
        switch days {
        case 365: return String(localized: "year")
        case 30:  return String(localized: "month")
        case 7:   return String(localized: "week")
        default:  return nil
        }
    }

    private var errorBinding: Binding<Bool> {
        Binding(
            get: { purchaseError != nil },
            set: { newValue in if !newValue { purchaseError = nil } }
        )
    }
}

enum PaywallSource {
    case general
    case feature
    case promotion
}

// MARK: - Post-Purchase Login Prompt

struct PostPurchaseLoginPrompt: View {
    @ObservedObject var authService: AuthenticationService
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appTheme) private var theme
    @Environment(\.resolvedAppTheme) private var resolvedTheme
    @State private var showError = false

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title2)
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(theme.adaptiveSecondaryText)
                        .minimumHitTarget()
                }
                .padding()
            }

            Spacer()

            VStack(spacing: 20) {
                ZStack {
                    Circle()
                        .fill(AppColors.brandAccent.opacity(0.15))
                        .frame(width: 72, height: 72)
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 32, weight: .semibold))
                        .foregroundStyle(AppColors.brandAccent)
                }

                Text(String(localized: "You're Pro!"))
                    .font(.systemSerif(28, weight: .bold, relativeTo: .title))
                    .foregroundStyle(theme.adaptivePrimaryText)

                Text(String(localized: "Sign in with Apple to keep your subscription safe across devices and reinstalls."))
                    .font(.subheadline)
                    .foregroundStyle(theme.adaptiveSecondaryText)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }

            Spacer()

            VStack(spacing: 16) {
                SignInWithAppleButton(.signIn) { request in
                    authService.configureAppleRequest(request)
                } onCompletion: { result in
                    switch result {
                    case .success(let authorization):
                        authService.handleAuthorization(authorization)
                    case .failure(let error):
                        authService.error = error.localizedDescription
                        showError = true
                    }
                }
                .signInWithAppleButtonStyle(resolvedTheme.isLight ? .black : .white)
                .frame(height: 54)
                .shadow(color: .black.opacity(0.12), radius: 12, x: 0, y: 6)

                Button {
                    dismiss()
                } label: {
                    Text(String(localized: "Maybe later"))
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(theme.adaptiveSecondaryText)
                }
            }
            .padding(.horizontal, 32)
            .padding(.bottom, 50)
        }
        .alert(String(localized: "Error"), isPresented: $showError) {
            Button("OK") { showError = false }
        } message: {
            Text(authService.error ?? String(localized: "Something went wrong"))
        }
        .onChange(of: authService.isAuthenticated) { _, isAuth in
            if isAuth { dismiss() }
        }
    }
}

#Preview {
    let model = DIContainer.shared.makeAppModel()
    PaywallView(
        model: model,
        store: model.subscriptionStore
    )
}
