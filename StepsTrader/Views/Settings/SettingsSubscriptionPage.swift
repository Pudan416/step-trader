import SwiftUI

/// Subscription / Pro management screen reachable from the Settings hub.
/// - Shows current plan status (incl. grandfathered)
/// - "Redeem promo code" → presents Apple's offer-code redemption sheet via RC
/// - "Restore purchases"
/// - "Manage subscription" → opens iOS Manage Subscriptions
/// - For free users: a "View plans" CTA that opens the main `PaywallView`
struct SettingsSubscriptionPage: View {
    @ObservedObject var model: AppModel
    @ObservedObject var store: SubscriptionStore

    @Environment(\.topCardHeight) private var topCardHeight
    @Environment(\.appTheme) private var theme

    @State private var showPaywall = false
    @State private var showRestoreResult: RestoreResult?
    @State private var isRestoring = false

    private enum RestoreResult: Identifiable {
        case success
        case nothingToRestore
        case failed(String)
        var id: String {
            switch self {
            case .success: return "success"
            case .nothingToRestore: return "nothing"
            case .failed(let msg): return "failed-\(msg)"
            }
        }
    }

    var body: some View {
        ZStack {
            SettingsGradientBG(model: model)

            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    DetailHeader(title: String(localized: "Subscription"))
                        .padding(.horizontal, 16)

                    statusCard
                        .padding(.horizontal, 16)

                    DetailDivider().padding(.horizontal, 16)

                    actionsCard
                        .padding(.horizontal, 16)

                    if !store.isPro {
                        upgradeCTA
                            .padding(.horizontal, 16)
                    }

                    #if DEBUG
                    debugPaywallPreview
                        .padding(.horizontal, 16)
                    debugResetGrandfathering
                        .padding(.horizontal, 16)
                    debugResetWelcomePaywall
                        .padding(.horizontal, 16)
                    #endif

                    SettingsFooter(text: footerCopy)
                        .padding(.horizontal, 20)
                        .padding(.top, 4)
                }
                .padding(.bottom, 80)
            }
        }
        .overlay { }
        .safeAreaInset(edge: .top, spacing: 0) {
            Color.clear.frame(height: topCardHeight)
        }
        .toolbar(.hidden, for: .navigationBar)
        .detailSwipeBack()
        .fullScreenCover(isPresented: $showPaywall) {
            PaywallView(model: model, store: store, source: .general)
        }
        .alert(
            restoreAlertTitle,
            isPresented: Binding(
                get: { showRestoreResult != nil },
                set: { if !$0 { showRestoreResult = nil } }
            ),
            actions: { Button("OK") { showRestoreResult = nil } },
            message: { Text(restoreAlertMessage) }
        )
        .task {
            await store.refresh()
        }
        .sensoryFeedback(.impact(weight: .heavy), trigger: didResetGrandfathering)
        .sensoryFeedback(.impact(weight: .light), trigger: didResetWelcomePaywall)
    }

    // MARK: - Alert Helpers

    private var restoreAlertTitle: String {
        switch showRestoreResult {
        case .success: String(localized: "Restored!")
        case .nothingToRestore: String(localized: "Nothing to restore")
        case .failed: String(localized: "Restore failed")
        case .none: ""
        }
    }

    private var restoreAlertMessage: String {
        switch showRestoreResult {
        case .success: String(localized: "Your Pro subscription is now active.")
        case .nothingToRestore: String(localized: "No active subscription was found on this Apple ID.")
        case .failed(let msg): msg
        case .none: ""
        }
    }

    // MARK: - Cards

    private var statusCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: statusIcon)
                    .font(.title3)
                    .foregroundStyle(statusTint)
                Text(statusTitle)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(theme.adaptivePrimaryText)
                Spacer()
            }

            Text(statusDetail)
                .font(.footnote)
                .foregroundStyle(theme.adaptiveSecondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 4)
    }

    private var actionsCard: some View {
        VStack(spacing: 0) {
            Button {
                store.presentRedeemCodeSheet()
            } label: {
                SettingsLinkRow(
                    icon: "ticket",
                    title: String(localized: "Redeem promo code"),
                    detail: nil,
                    trailingIcon: "chevron.right"
                )
            }
            .buttonStyle(MattePressStyle())

            DetailDivider()

            Button {
                Task { await runRestore() }
            } label: {
                HStack(spacing: 12) {
                    if isRestoring {
                        ProgressView()
                            .frame(width: 24)
                    } else {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 15))
                            .foregroundStyle(theme.adaptiveSecondaryText)
                            .frame(width: 24)
                    }
                    Text(String(localized: "Restore purchases"))
                        .font(.subheadline)
                        .foregroundStyle(theme.adaptivePrimaryText)
                    Spacer()
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 13)
                .contentShape(Rectangle())
            }
            .buttonStyle(MattePressStyle())
            .disabled(isRestoring)

            if showManageSubscriptionRow {
                DetailDivider()
                Button {
                    store.presentManageSubscriptions()
                } label: {
                    SettingsLinkRow(
                        icon: "creditcard",
                        title: String(localized: "Manage subscription"),
                        detail: nil,
                        trailingIcon: "arrow.up.right"
                    )
                }
                .buttonStyle(MattePressStyle())
            }
        }
    }

    #if DEBUG
    private var debugPaywallPreview: some View {
        Button {
            showPaywall = true
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "ladybug")
                    .font(.headline)
                Text(String(localized: "Preview Paywall (debug)"))
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Image(systemName: "arrow.up.right")
                    .font(.subheadline.weight(.bold))
            }
            .foregroundStyle(.purple)
            .padding(.horizontal, 14)
            .padding(.vertical, 13)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.purple.opacity(0.12))
                    .overlay {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(Color.purple.opacity(0.4), lineWidth: 1)
                    }
            )
        }
        .buttonStyle(.plain)
    }

    @State private var didResetGrandfathering: Bool = false

    private var debugResetGrandfathering: some View {
        Button {
            UserDefaults.standard.set(false, forKey: SharedKeys.isGrandfathered)
            UserDefaults.standard.set(Date.now, forKey: SharedKeys.grandfatherEvaluatedAt)
            UserDefaults.standard.set(false, forKey: SharedKeys.cachedHasProEntitlement)
            didResetGrandfathering = true
        } label: {
            HStack(spacing: 12) {
                Image(systemName: didResetGrandfathering ? "checkmark.circle.fill" : "xmark.seal")
                    .font(.headline)
                Text(didResetGrandfathering
                     ? String(localized: "Grandfathering reset — restart app")
                     : String(localized: "Reset Grandfathering (debug)"))
                    .font(.subheadline.weight(.semibold))
                Spacer()
            }
            .foregroundStyle(.red)
            .padding(.horizontal, 14)
            .padding(.vertical, 13)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.red.opacity(0.08))
                    .overlay {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(Color.red.opacity(0.3), lineWidth: 1)
                    }
            )
        }
        .buttonStyle(.plain)
    }

    @State private var didResetWelcomePaywall: Bool = false

    private var debugResetWelcomePaywall: some View {
        Button {
            UserDefaults.standard.removeObject(forKey: SubscriptionGate.postOnboardingPaywallShownKey)
            didResetWelcomePaywall = true
        } label: {
            HStack(spacing: 12) {
                Image(systemName: didResetWelcomePaywall ? "checkmark.circle.fill" : "arrow.counterclockwise.circle")
                    .font(.headline)
                Text(didResetWelcomePaywall
                     ? String(localized: "Welcome paywall reset — re-onboard to see")
                     : String(localized: "Reset Welcome Paywall (debug)"))
                    .font(.subheadline.weight(.semibold))
                Spacer()
            }
            .foregroundStyle(.purple)
            .padding(.horizontal, 14)
            .padding(.vertical, 13)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.purple.opacity(0.08))
                    .overlay {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(Color.purple.opacity(0.3), lineWidth: 1)
                    }
            )
        }
        .buttonStyle(.plain)
    }
    #endif

    private var upgradeCTA: some View {
        Button {
            showPaywall = true
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "sparkles")
                    .font(.headline)
                    .foregroundStyle(AppAccentInk.primary)
                Text(String(localized: "View plans"))
                    .font(.headline)
                    .foregroundStyle(AppAccentInk.primary)
                Spacer()
                Image(systemName: "arrow.right")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(AppAccentInk.primary)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 16)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(AppColors.brandAccent)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Status copy

    private var statusIcon: String {
        switch store.state {
        case .grandfathered:        return "gift.fill"
        case .lifetime:             return "infinity.circle.fill"
        case .subscribed:           return "checkmark.seal.fill"
        case .free:                 return "circle.dashed"
        case .loadingFromCache:     return "ellipsis.circle"
        case .unknown:              return "ellipsis.circle"
        }
    }

    private var statusTint: Color {
        switch store.state {
        case .grandfathered, .lifetime, .subscribed: return AppColors.brandAccent
        case .loadingFromCache(let isPro): return isPro ? AppColors.brandAccent : theme.adaptiveSecondaryText
        case .free, .unknown: return theme.adaptiveSecondaryText
        }
    }

    private var statusTitle: String {
        switch store.state {
        case .grandfathered:
            return String(localized: "Pro — gifted")
        case .lifetime:
            return String(localized: "Pro — lifetime")
        case .subscribed(_, let willRenew, _):
            return willRenew
                ? String(localized: "Pro — active")
                : String(localized: "Pro — cancelled")
        case .free:
            return String(localized: "Free plan")
        case .loadingFromCache:
            return String(localized: "Refreshing…")
        case .unknown:
            return String(localized: "Loading…")
        }
    }

    private var statusDetail: String {
        switch store.state {
        case .grandfathered:
            return String(localized: "You were here before. Pro is yours, free, forever. Thanks for being early.")
        case .lifetime:
            return String(localized: "One-time purchase — yours forever. Thank you.")
        case .subscribed(let productId, let willRenew, let expires):
            let expiryString: String = expires.map {
                let f = DateFormatter()
                f.dateStyle = .medium
                f.timeStyle = .none
                return f.string(from: $0)
            } ?? String(localized: "—")
            let planName = friendlyPlanName(for: productId)
            if willRenew {
                return String(localized: "\(planName) — renews on \(expiryString).")
            } else {
                return String(localized: "\(planName) — access until \(expiryString). Auto-renew is off.")
            }
        case .free:
            return String(localized: "Upgrade to Pro for unlimited app limits, all wallpapers, and full history.")
        case .loadingFromCache:
            return String(localized: "Confirming your subscription with the App Store…")
        case .unknown:
            return String(localized: "Checking your subscription with the App Store…")
        }
    }

    /// Manage Subscription row only makes sense for renewing subscriptions —
    /// not for lifetime, gifted, or free. We deliberately keep it visible for
    /// `subscribed(willRenew: false)` (cancelled but still active) so users can
    /// re-enable auto-renew from iOS Settings.
    private var showManageSubscriptionRow: Bool {
        if case .subscribed = store.state { return true }
        return false
    }

    /// Map raw RC `productIdentifier` → user-facing plan name. We avoid leaking
    /// raw IDs into the localized string above; if the ID is unknown we just
    /// return the generic "Pro" tag so the sentence still reads cleanly.
    private func friendlyPlanName(for productId: String) -> String {
        switch productId {
        case SubscriptionIDs.Product.monthly: return String(localized: "Monthly plan")
        case SubscriptionIDs.Product.annual:  return String(localized: "Yearly plan")
        case SubscriptionIDs.Product.lifetime: return String(localized: "Lifetime")
        default: return String(localized: "Pro")
        }
    }

    private var footerCopy: String {
        String(localized: "Subscriptions auto-renew unless cancelled at least 24h before the period ends. Manage or cancel anytime in iOS Settings → Apple ID → Subscriptions.")
    }

    private func runRestore() async {
        isRestoring = true
        defer { isRestoring = false }
        let result = await store.restore()
        switch result {
        case .success:
            showRestoreResult = store.isPro ? .success : .nothingToRestore
        case .failed(let err):
            showRestoreResult = .failed(err.localizedDescription)
        case .userCancelled, .pending:
            break
        }
    }
}

#Preview {
    let model = DIContainer.shared.makeAppModel()
    NavigationStack {
        SettingsSubscriptionPage(
            model: model,
            store: model.subscriptionStore
        )
    }
}
