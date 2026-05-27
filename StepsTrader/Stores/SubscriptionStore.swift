import Foundation
import Combine
import StoreKit
#if canImport(RevenueCat)
import RevenueCat
#endif

// MARK: - Public state

enum SubscriptionState: Equatable {
    case unknown                            // SDK not yet loaded, no cache
    case loadingFromCache(isPro: Bool)      // cached entitlement; refresh in flight
    case free                               // not subscribed, not grandfathered
    case grandfathered                      // legacy user — Pro for free, forever
    case lifetime(productId: String)        // one-time non-consumable purchase
    case subscribed(productId: String, willRenew: Bool, expiresAt: Date?)

    var isPro: Bool {
        switch self {
        case .grandfathered, .lifetime, .subscribed: return true
        case .loadingFromCache(let isPro): return isPro
        case .free, .unknown: return false
        }
    }
}

enum SubscriptionPurchaseResult {
    case success
    case userCancelled
    case pending
    case failed(Error)
}

/// Wraps RevenueCat's SDK so the rest of the app can stay platform-agnostic.
/// Also handles grandfathering: any user that had launched the app *before*
/// the subscription system shipped is permanently granted Pro for free.
@MainActor
final class SubscriptionStore: ObservableObject {
    // Published state — drive UI gates from these.
    @Published private(set) var state: SubscriptionState = .unknown
    @Published private(set) var isLoading: Bool = false
    @Published private(set) var packages: [PurchasePackage] = []
    @Published private(set) var lastError: String?

    var isPro: Bool { SubscriptionGate.allFeaturesUnlocked || state.isPro }

    /// Clear any sticky error string. Call from UI before retrying a fetch
    /// so the loading state is unambiguous.
    func clearLastError() { lastError = nil }

    private let defaults: UserDefaults
    private var refreshTask: Task<Void, Never>?

    /// Long-running listener for `Purchases.customerInfoStream`. Stored so the
    /// store can stop listening on `deinit` — without this, a recreated store
    /// (DI reset / test teardown) would leave the prior listener consuming
    /// entitlement updates against a phantom instance. (§3.5)
    private var customerInfoStreamTask: Task<Void, Never>?

    // MARK: - Bootstrap detection

    /// Heuristic: did the user exist before we shipped the subscription system?
    /// Anything that proves prior usage counts: completed onboarding, prior launches,
    /// any persisted ticket groups, etc. Evaluated exactly once and pinned.
    ///
    /// `appLaunchCount` threshold is `> 1` (not `> 0`) so this method gives the
    /// same answer regardless of whether the StepsTraderApp.init() launch-count
    /// increment runs before or after `configure()`. A brand-new install has
    /// either 0 (incremented later) or 1 (incremented earlier); a user with any
    /// prior launches has ≥ 2 by the time the next launch's increment runs.
    private static func detectExistingUser(_ defaults: UserDefaults = .standard) -> Bool {
        if defaults.bool(forKey: "hasCompletedOnboarding_v1") { return true }
        if defaults.integer(forKey: "onboarding_state_v1") >= 1 { return true }
        if defaults.integer(forKey: "appLaunchCount") > 1 { return true }
        // Anything in our App Group also counts (existing ticket groups, etc.)
        let g = SharedKeys.appGroupDefaults()
        if g.data(forKey: SharedKeys.ticketGroups) != nil { return true }
        if g.data(forKey: SharedKeys.legacyShieldGroups) != nil { return true }
        return false
    }

    // MARK: - Init

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        // Restore cached entitlement so UI doesn't flash "Free" while RC loads.
        let cachedPro = defaults.bool(forKey: SharedKeys.cachedHasProEntitlement)
        let grandfathered = defaults.bool(forKey: SharedKeys.isGrandfathered)
        if grandfathered {
            state = .grandfathered
        } else if cachedPro {
            // Optimistic — will be re-validated on next refresh. We use a
            // dedicated `loadingFromCache` state instead of a fake `subscribed`
            // entry so the UI never has to render a placeholder productId.
            state = .loadingFromCache(isPro: true)
        }
    }

    // MARK: - Configuration

    /// Call exactly once at app launch with your RC public SDK key.
    /// Safe to call before the user signs in — RC starts anonymous, then we
    /// `logIn(userId:)` after Sign in with Apple completes.
    func configure(apiKey: String, appUserID: String? = nil) {
        // Grandfathering MUST be evaluated regardless of whether RC is linked
        // or whether the API key is configured. Otherwise a misconfigured build
        // (empty key, missing SDK) silently strips legacy users of their gifted Pro.
        evaluateGrandfatheringIfNeeded()

        #if canImport(RevenueCat)
        guard !apiKey.isEmpty, !apiKey.hasPrefix("$(") else {
            AppLogger.app.error("🚨 SubscriptionStore.configure: RC API key is empty or unresolved ('\(apiKey)'). Create Config/Secrets.xcconfig with a valid appl_… key.")
            return
        }

        Purchases.logLevel = {
            #if DEBUG
            return .verbose
            #else
            return .warn
            #endif
        }()

        Purchases.configure(
            with: Configuration.Builder(withAPIKey: apiKey)
                .with(appUserID: appUserID)
                .build()
        )

        // Persist the resolved app user ID for diagnostics.
        defaults.set(Purchases.shared.appUserID, forKey: SharedKeys.rcAppUserID)

        // Listen for entitlement changes pushed by the SDK (e.g. renewal, expiry).
        // §3.5: tracked so deinit can cancel — otherwise the loop runs forever
        // against a stale `self` after DI reset / test teardown.
        customerInfoStreamTask?.cancel()
        customerInfoStreamTask = Task { @MainActor [weak self] in
            for await info in Purchases.shared.customerInfoStream {
                guard let self = self, !Task.isCancelled else { return }
                self.applyCustomerInfo(info)
            }
        }

        // Initial fetch.
        Task { await self.refresh() }
        #else
        AppLogger.app.error("⚠️ RevenueCat SDK not linked. Add the SPM package to the app target.")
        #endif
    }

    // MARK: - Grandfathering

    /// Runs once, on first launch after the subscription feature is added.
    /// If the user already used the app, mark them grandfathered forever.
    private func evaluateGrandfatheringIfNeeded() {
        guard defaults.object(forKey: SharedKeys.grandfatherEvaluatedAt) == nil else {
            // Already evaluated; nothing to do.
            return
        }

        let isExisting = Self.detectExistingUser(defaults)
        defaults.set(Date.now, forKey: SharedKeys.grandfatherEvaluatedAt)
        defaults.set(isExisting, forKey: SharedKeys.isGrandfathered)

        if isExisting {
            AppLogger.app.debug("🎁 Grandfathered existing user into Pro")
            state = .grandfathered
            cacheProFlag(true)
            #if canImport(RevenueCat)
            // Tag in RC so dashboard can segment grandfathered users.
            Purchases.shared.attribution.setAttributes([
                SubscriptionIDs.Attribute.grandfathered: "true",
                SubscriptionIDs.Attribute.grandfatheredAt: ISO8601DateFormatter().string(from: Date.now),
                SubscriptionIDs.Attribute.appLaunchCount: String(defaults.integer(forKey: "appLaunchCount"))
            ])
            #endif
        } else {
            AppLogger.app.debug("🆕 New user — grandfathering not granted")
        }
    }

    // MARK: - Identity

    /// Call after Sign in with Apple completes so RC links anonymous purchases
    /// to the canonical user ID (Supabase user.id). Idempotent.
    func logIn(supabaseUserID: String) async {
        #if canImport(RevenueCat)
        do {
            let result = try await Purchases.shared.logIn(supabaseUserID)
            defaults.set(Purchases.shared.appUserID, forKey: SharedKeys.rcAppUserID)
            Purchases.shared.attribution.setAttributes([
                SubscriptionIDs.Attribute.supabaseUserID: supabaseUserID
            ])
            applyCustomerInfo(result.customerInfo)
            await refresh()
        } catch {
            AppLogger.app.error("RC logIn failed: \(error.localizedDescription)")
        }
        #endif
    }

    func logOut() async {
        #if canImport(RevenueCat)
        guard !Purchases.shared.isAnonymous else { return }
        do {
            let info = try await Purchases.shared.logOut()
            applyCustomerInfo(info)
            defaults.set(Purchases.shared.appUserID, forKey: SharedKeys.rcAppUserID)
        } catch {
            AppLogger.app.error("RC logOut failed: \(error.localizedDescription)")
        }
        #endif
    }

    // MARK: - Refresh / Restore

    func refresh() async {
        #if canImport(RevenueCat)
        isLoading = true
        defer { isLoading = false }

        // Entitlement state — best-effort; offerings can still load if this fails.
        do {
            let info = try await Purchases.shared.customerInfo()
            applyCustomerInfo(info)
        } catch {
            AppLogger.app.error("RC customerInfo failed: \(error.localizedDescription)")
        }

        var offeringsError: Error?

        // Preferred path: RevenueCat offering → packages (preserves RC package metadata).
        do {
            let offerings = try await Purchases.shared.offerings()
            let offering: Offering? = {
                if let id = SubscriptionIDs.currentOffering {
                    return offerings.offering(identifier: id) ?? offerings.current
                }
                return offerings.current
            }()
            let fromOffering = (offering?.availablePackages ?? []).map(PurchasePackage.init(rcPackage:))
            if !fromOffering.isEmpty {
                packages = fromOffering
                lastError = nil
                return
            }
            if offering == nil {
                AppLogger.app.error("RC offerings: no current offering — mark one as Current in the RevenueCat dashboard")
            } else {
                AppLogger.app.error("RC offerings: offering '\(offering!.identifier)' has no available packages")
            }
        } catch {
            offeringsError = error
            AppLogger.app.error("RC offerings failed: \(error.localizedDescription)")
        }

        // Fallback: fetch StoreProducts directly by product ID. Often succeeds when
        // offerings() fails with CONFIGURATION_ERROR but ASC / StoreKit products exist.
        await loadPackagesFromStoreProducts(fallbackError: offeringsError)
        #endif
    }

    func restore() async -> SubscriptionPurchaseResult {
        #if canImport(RevenueCat)
        isLoading = true
        defer { isLoading = false }
        do {
            let info = try await Purchases.shared.restorePurchases()
            applyCustomerInfo(info)
            lastError = nil
            return .success
        } catch {
            lastError = error.localizedDescription
            return .failed(error)
        }
        #else
        return .failed(NSError(domain: "Subscription", code: -1, userInfo: [NSLocalizedDescriptionKey: "RevenueCat not linked"]))
        #endif
    }

    // MARK: - Purchase

    func purchase(_ package: PurchasePackage) async -> SubscriptionPurchaseResult {
        #if canImport(RevenueCat)
        isLoading = true
        defer { isLoading = false }
        do {
            if let rc = package.rcPackage {
                let result = try await Purchases.shared.purchase(package: rc)
                if result.userCancelled { return .userCancelled }
                applyCustomerInfo(result.customerInfo)
            } else if let product = package.storeProduct {
                let result = try await Purchases.shared.purchase(product: product)
                if result.userCancelled { return .userCancelled }
                applyCustomerInfo(result.customerInfo)
            } else {
                return .failed(NSError(
                    domain: "Subscription",
                    code: -2,
                    userInfo: [NSLocalizedDescriptionKey: "Missing store product"]
                ))
            }
            lastError = nil
            return .success
        } catch {
            // RC bridges errors as NSError with `ErrorCode.errorDomain` (synthesized
            // from `CustomNSError`). Match on the typed domain instead of substring
            // checks so we don't break if RC ever renames the module.
            let ns = error as NSError
            if ns.domain == RevenueCat.ErrorCode.errorDomain,
               ns.code == RevenueCat.ErrorCode.paymentPendingError.rawValue {
                return .pending
            }
            lastError = error.localizedDescription
            return .failed(error)
        }
        #else
        return .failed(NSError(domain: "Subscription", code: -1, userInfo: [NSLocalizedDescriptionKey: "RevenueCat not linked"]))
        #endif
    }

    // MARK: - Promo code redemption

    /// Presents the system "Redeem code" sheet. iOS 16+ uses StoreKit 2;
    /// older OS would fall back to legacy SKPaymentQueue (we require 18+).
    func presentRedeemCodeSheet() {
        #if canImport(RevenueCat)
        Purchases.shared.presentCodeRedemptionSheet()
        #else
        if #available(iOS 16.0, *) {
            Task { @MainActor in
                if let scene = UIApplication.shared.connectedScenes
                    .compactMap({ $0 as? UIWindowScene })
                    .first(where: { $0.activationState == .foregroundActive })
                {
                    try? await AppStore.presentOfferCodeRedeemSheet(in: scene)
                }
            }
        }
        #endif
    }

    /// Opens iOS "Manage Subscriptions" sheet so user can cancel / change plan.
    func presentManageSubscriptions() {
        #if canImport(RevenueCat)
        Purchases.shared.showManageSubscriptions { _ in }
        #else
        if #available(iOS 15.0, *) {
            Task { @MainActor in
                if let scene = UIApplication.shared.connectedScenes
                    .compactMap({ $0 as? UIWindowScene })
                    .first
                {
                    try? await AppStore.showManageSubscriptions(in: scene)
                }
            }
        }
        #endif
    }

    // MARK: - Private

    #if canImport(RevenueCat)
    /// Loads products by ID when offerings are empty or misconfigured.
    private func loadPackagesFromStoreProducts(fallbackError: Error?) async {
        let storeProducts = await Purchases.shared.products(SubscriptionIDs.allProductIdentifiers)
        let byID = Dictionary(uniqueKeysWithValues: storeProducts.map { ($0.productIdentifier, $0) })
        let ordered = SubscriptionIDs.allProductIdentifiers.compactMap { byID[$0] }

        if ordered.isEmpty {
            packages = []
            lastError = Self.userFacingOfferingsError(fallbackError)
            let ids = SubscriptionIDs.allProductIdentifiers.joined(separator: ", ")
            AppLogger.app.error("RC: no StoreProducts for [\(ids)]. Verify App Store Connect, RevenueCat offering, and Paid Apps agreement.")
            return
        }

        packages = ordered.map(PurchasePackage.init(storeProduct:))
        lastError = nil
        if fallbackError != nil {
            AppLogger.app.debug("Loaded \(ordered.count) plan(s) via StoreProduct fallback")
        }
    }

    private static func userFacingOfferingsError(_ error: Error?) -> String {
        guard let error else {
            return String(localized: "No subscription plans are available right now.")
        }
        let description = error.localizedDescription
        if description.localizedCaseInsensitiveContains("configuration") {
            return String(
                localized: "Plans couldn't be loaded. Check that pro_monthly, pro_annual, and pro_lifetime exist in App Store Connect and are attached to a Current offering in RevenueCat."
            )
        }
        return description
    }

    private func applyCustomerInfo(_ info: CustomerInfo) {
        // Grandfathering trumps RC entitlement — once granted, never revoke.
        // Before the local check, try to restore grandfathered status from the
        // Apple receipt's `originalApplicationVersion`. This is the *only* path
        // that survives uninstall/reinstall (UserDefaults & App Group are wiped,
        // but the receipt persists with the user's Apple ID).
        restoreGrandfatherFromReceiptIfNeeded(info)

        if defaults.bool(forKey: SharedKeys.isGrandfathered) {
            state = .grandfathered
            cacheProFlag(true)
            return
        }
        if let entitlement = info.entitlements[SubscriptionIDs.proEntitlement], entitlement.isActive {
            // Non-consumable purchases come back as entitlements with no expirationDate
            // and `productIdentifier` listed under `info.nonSubscriptions`.
            let isLifetime = entitlement.expirationDate == nil &&
                info.nonSubscriptions.contains(where: { $0.productIdentifier == entitlement.productIdentifier })
            if isLifetime {
                state = .lifetime(productId: entitlement.productIdentifier)
            } else {
                state = .subscribed(
                    productId: entitlement.productIdentifier,
                    willRenew: entitlement.willRenew,
                    expiresAt: entitlement.expirationDate
                )
            }
            cacheProFlag(true)
        } else {
            state = .free
            cacheProFlag(false)
        }
    }
    #endif

    private func cacheProFlag(_ value: Bool) {
        defaults.set(value, forKey: SharedKeys.cachedHasProEntitlement)
    }

    #if canImport(RevenueCat)
    /// Re-grandfather a user whose receipt was issued by a build PRIOR to the
    /// paywall release. This is the failsafe for the reinstall scenario where
    /// the local `isGrandfathered` flag was wiped along with UserDefaults.
    ///
    /// The mapping uses `SubscriptionIDs.grandfatherBeforeBuild` — when set to 0,
    /// this method is a no-op (receipt-based grandfather restore disabled).
    private func restoreGrandfatherFromReceiptIfNeeded(_ info: CustomerInfo) {
        // Already grandfathered locally — nothing to do.
        guard !defaults.bool(forKey: SharedKeys.isGrandfathered) else { return }

        let threshold = SubscriptionIDs.grandfatherBeforeBuild
        guard threshold > 0 else { return }

        // `originalApplicationVersion` is the build number string from the
        // receipt of the *first* version the user ever installed. Sandbox &
        // TestFlight may report it as nil — accept gracefully.
        guard let raw = info.originalApplicationVersion,
              let originalBuild = Int(raw) else { return }

        guard originalBuild < threshold else { return }

        AppLogger.app.debug("🎁 Re-grandfathered user from receipt — originalBuild=\(originalBuild) < threshold=\(threshold)")
        defaults.set(true, forKey: SharedKeys.isGrandfathered)
        if defaults.object(forKey: SharedKeys.grandfatherEvaluatedAt) == nil {
            defaults.set(Date.now, forKey: SharedKeys.grandfatherEvaluatedAt)
        }
        cacheProFlag(true)

        Purchases.shared.attribution.setAttributes([
            SubscriptionIDs.Attribute.grandfathered: "true",
            SubscriptionIDs.Attribute.grandfatheredAt: ISO8601DateFormatter().string(from: Date.now),
            "grandfather_source": "receipt_originalApplicationVersion",
            "grandfather_originalBuild": String(originalBuild)
        ])
    }
    #endif

    deinit {
        let refresh = refreshTask
        let stream = customerInfoStreamTask
        MainActor.assumeIsolated {
            refresh?.cancel()
            stream?.cancel()
        }
    }
}

// MARK: - Package wrapper

/// Thin wrapper over `RevenueCat.Package` so view code never imports RC directly.
struct PurchasePackage: Identifiable, Equatable {
    let id: String
    let title: String
    let priceString: String
    let pricePerMonthString: String?
    let productId: String
    let durationDays: Int?
    let introOfferDescription: String?

    /// Underlying RC package — kept opaque to view layer.
    fileprivate let rcPackageRef: AnyObject?
    /// Store product used when loaded outside an offering (fallback path).
    fileprivate let storeProductRef: AnyObject?

    static func == (lhs: PurchasePackage, rhs: PurchasePackage) -> Bool {
        lhs.id == rhs.id && lhs.priceString == rhs.priceString
    }
}

#if canImport(RevenueCat)
extension PurchasePackage {
    init(rcPackage: Package) {
        self.id = rcPackage.identifier
        self.title = rcPackage.storeProduct.localizedTitle
        self.priceString = rcPackage.storeProduct.localizedPriceString
        self.productId = rcPackage.storeProduct.productIdentifier
        self.durationDays = rcPackage.packageType.approxDurationDays
        self.pricePerMonthString = rcPackage.storeProduct.pricePerMonthString
        self.introOfferDescription = rcPackage.storeProduct.introductoryDiscount.flatMap {
            $0.localizedDescription
        }
        self.rcPackageRef = rcPackage
        self.storeProductRef = nil
    }

    init(storeProduct: StoreProduct) {
        self.id = storeProduct.productIdentifier
        self.title = storeProduct.localizedTitle
        self.priceString = storeProduct.localizedPriceString
        self.productId = storeProduct.productIdentifier
        self.durationDays = storeProduct.subscriptionPeriod?.approxDurationDays
        self.pricePerMonthString = storeProduct.pricePerMonthString
        self.introOfferDescription = storeProduct.introductoryDiscount.flatMap {
            $0.localizedDescription
        }
        self.rcPackageRef = nil
        self.storeProductRef = storeProduct
    }

    fileprivate var rcPackage: Package? { rcPackageRef as? Package }
    fileprivate var storeProduct: StoreProduct? { storeProductRef as? StoreProduct }
}

private extension RevenueCat.SubscriptionPeriod {
    var approxDurationDays: Int? {
        switch unit {
        case .day: return value
        case .week: return value * 7
        case .month: return value * 30
        case .year: return value * 365
        @unknown default: return nil
        }
    }
}

private extension PackageType {
    var approxDurationDays: Int? {
        switch self {
        case .annual: return 365
        case .sixMonth: return 180
        case .threeMonth: return 90
        case .twoMonth: return 60
        case .monthly: return 30
        case .weekly: return 7
        case .lifetime: return nil
        case .custom, .unknown: return nil
        @unknown default: return nil
        }
    }
}

private extension StoreProduct {
    var pricePerMonthString: String? {
        guard let period = subscriptionPeriod else { return nil }
        let months: Decimal
        switch period.unit {
        case .day:   months = Decimal(period.value) / 30
        case .week:  months = Decimal(period.value) / 4
        case .month: months = Decimal(period.value)
        case .year:  months = Decimal(period.value) * 12
        @unknown default: return nil
        }
        guard months > 0 else { return nil }
        let perMonth = (price as NSDecimalNumber).dividing(by: months as NSDecimalNumber)
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.locale = priceFormatter?.locale ?? Locale.current
        return formatter.string(from: perMonth)
    }
}

private extension StoreProductDiscount {
    var localizedDescription: String? {
        switch self.paymentMode {
        case .freeTrial:
            return "Free for \(subscriptionPeriod.value) \(subscriptionPeriod.unit.shortLabel)"
        case .payAsYouGo, .payUpFront:
            return "Intro: \(localizedPriceString) for \(subscriptionPeriod.value) \(subscriptionPeriod.unit.shortLabel)"
        @unknown default:
            return nil
        }
    }
}

private extension RevenueCat.SubscriptionPeriod.Unit {
    var shortLabel: String {
        switch self {
        case .day: return "days"
        case .week: return "weeks"
        case .month: return "months"
        case .year: return "years"
        @unknown default: return ""
        }
    }
}
#endif

#if canImport(UIKit)
import UIKit
#endif
