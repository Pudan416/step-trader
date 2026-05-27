# Nowhere (StepsTrader) Code Audit

Generated 2026-05-26. Scope: ~52,000 LOC across 219 Swift files + 3 Metal kernels across 7 targets (Steps4, DeviceActivityMonitor, ShieldConfiguration, ShieldAction, UnlockWidgetExtension, Steps4Tests, Steps4UITests). The local SPM package `OnboardingPreview` is included. `admin-panel/`, `tg-admin/`, `web/`, `build/`, `output/`, `tmp/`, `docs/`, and `Scripts/` are excluded.

Findings cite `path/to/file.swift:LINE` so you can jump straight to them in Xcode. Each item has a recommended action and a one-line «Что это значит на практике» that translates the technical finding into user/developer impact in plain Russian.

A clean Debug build of the `Steps4` scheme against iPhone 17 (iOS 26.1) initially produced one compiler warning — that warning was closed in the post-audit hygiene pass (§4.2). Project now builds with 0 warnings. The codebase compiles in Swift 5 mode without strict-concurrency enabled, so most concurrency findings below are latent — they'll begin to fire when the project upgrades to Swift 6 / `SWIFT_STRICT_CONCURRENCY=complete`. Treat them as preparatory work for that migration.

There are **no Critical findings** in this audit. Several Agent-flagged "Critical" items were demoted during verification (see §12).

**Resolved as of this commit:** §3.3, §4.2, §4.5, §5.5, §9.1, §9.10. The prior PR-scoped audit was preserved at `CODE_AUDIT_PR_moment.md`.

---

## 1. Executive summary

Top items to address, in priority order (✅ = already resolved):

1. ✅ **[High] Dead service `ProfileLocationManager` (118 LOC) with zero references** — §9.1. Resolved in `f610933`.
2. **[High] `UnsafeSendableBox` (`@unchecked Sendable`) used to bridge the HK auth-timeout pattern** — §3.2 — `StepsTrader/Services/HealthKitService.swift:29-32`. Will fail Swift 6 strict mode and is a real data-race surface if the timeout races a resume.
3. **[High] PayGate monitoring failure refunds silently with no UI feedback** — §5.1 — `StepsTrader/AppModel+PayGate.swift:101-110`. User is charged, then refunded, but the PayGate sheet stays up showing the same balance — confusing flow that masks a real DeviceActivity error.
4. **[High] No Debug/Release Supabase URL split — single `Secrets.xcconfig` shared by both** — §6.1 — `Config/Debug.xcconfig`, `Config/Release.xcconfig`.
5. **[High] 24 outstanding "Migrate to .sensoryFeedback()" TODOs across the UI** — §4.1.
6. **[High] Oversized SwiftUI views (1974 / 1657 / 1119 LOC) couple state, network, and rendering** — §9.2 — `OnboardingStoriesView.swift`, `GalleryView.swift`, `MeView.swift`.
7. **[High] App-Group `UserDefaults` read-modify-write between app and DeviceActivity extension is unsynchronized** — §5.2 — `BlockingStore.swift:87-93` + `DeviceActivityMonitorExtension.swift:172-192`.
8. ✅ **[High] `UNUserNotificationCenter.add(_:withCompletionHandler:)` async migration** — §3.3. Resolved in `7a73f38`.
9. **[High] Unused HealthKit observer/initial-fetch task is not stored, so `stopObservingSteps()` cannot cancel an in-flight initial fetch** — §5.3 — `HealthKitService.swift:385-410`.
10. ✅ **[Medium] One canonical compiler warning** — §4.2. Resolved in `83b8475`.

---

## 2. Quick wins (≤30 min each)

Items left after the hygiene pass:

- **Consolidate the 8 private `_dailyEnergy…Key` constants into `SharedKeys`** — `AppModel+DailyEnergy.swift:5-13`. The comment at line 5 ("file-scope to avoid `@MainActor` isolation on static lets") is no longer load-bearing; `SharedKeys` is a `nonisolated enum`.
- **Add `[weak self]` guards (or `Task.isCancelled`) to short Combine `sink` tasks** — `AppModel.swift:251-255`. Pattern repeats; one-line fix per call site.
- **Wrap or remove the 4 `print()` calls in `OnboardingDemoView.swift`** behind `#if DEBUG`. Demo-only views still ship in Release.

(Other quick wins from the original list — file deletions, gitignore, marketing doc move, warning fix — were completed in the post-audit hygiene PR.)

---

## 3. Concurrency

The project compiles in Swift 5 mode without strict concurrency. Everything below is **latent** — it'll surface when the project flips on `SWIFT_STRICT_CONCURRENCY=complete` or upgrades to Swift 6 language mode. Triage these in advance of that upgrade rather than treating them as live bugs.

### 3.1 Post-login Task fans out from a `@MainActor`-isolated context without checking `Task.isCancelled` between awaits
- **Location:** `StepsTrader/Services/AuthenticationService.swift:399-408`
- **What:** A nested `Task { [weak self] in … }` is spawned from an already-`@MainActor` context; `Task.isCancelled` is checked once after `SubscriptionStore.shared.logIn(…)` but not between subsequent awaits.
- **Why:** Cancellation only takes effect at the one checkpoint; a sign-out racing with sign-in can leave a stale full-sync running against the wrong user.
- **Action:** Add `guard !Task.isCancelled else { return }` after each `await`, and drop the redundant outer `Task { @MainActor in … }` wrapper.
- **Severity:** Medium
- **Что это значит на практике:** Юзер быстро вышел из аккаунта и зашёл снова (например, переключение тестового и реального) — старая фоновая задача синка может писать в Supabase под старым userID параллельно с новой. Затирание свежих данных. Сегодня редкое, при Swift 6 — будет ловиться компилятором.

### 3.2 ✅ _RESOLVED 2026-05-26: `UnsafeSendableBox` deleted, HK auth uses async overload directly_

Был `@unchecked Sendable` бокс + ручной 10-секундный timeout + `Task.detached` — workaround для древнего бага в iOS, где async-overload `HKHealthStore.requestAuthorization` мог зависнуть. На современных iOS этого нет. Сейчас просто `try await store.requestAuthorization(toShare: [], read: readTypes)` — на 20 строк короче, data race surface исчез, Swift 6 strict-concurrency больше не имеет претензий. Заодно §4.4 закрыта (континуация HK auth убрана).

`.authorizationTimeout` case в `HealthKitServiceError` оставлен в API на случай если timeout-обёртку придётся вернуть в будущем (тогда уже через `withTimeout` или `TaskGroup`, без @unchecked); ветка `catch` в `HealthStore.swift:32` стала недостижимой но не сломанной — defensive code.

### 3.3 ✅ _RESOLVED 2026-05-26 (commit `7a73f38`): UNUserNotificationCenter.add() переведён на async overload_

Все 10 сайтов в `NotificationManager.swift` заменены на `try await ... .add(request)` обёрнутые в `Task { do { ... } catch { } }`. Внешний API методов остался sync (звонящие места не меняются). Под Swift 6 эта находка бы стрельнула на каждом сайте — теперь чисто.

### 3.4 `SupabaseSyncService` is an actor but exposes a `nonisolated static let shared`
- **Location:** `StepsTrader/Services/SupabaseSyncService.swift:6-8`
- **What:** The actor singleton is exposed without `await` — normalizes "just call shared from anywhere," which on Swift 6 obscures whether call points are properly suspending.
- **Why:** Callers occasionally forget the `await` and the compiler only catches that in strict mode.
- **Action:** Keep the singleton but audit call sites once strict-concurrency lands. Convert truly thread-safe pure helpers (formatters, key builders) to `nonisolated`.
- **Severity:** Medium
- **Что это значит на практике:** Сейчас работает корректно (хотя выглядит «небезопасно»). Риск косвенный — звонящие забывают `await`, читают stale-данные. В Swift 6 компилятор подсветит каждое забытое место.

### 3.5 Combine `sink` closures spawn untracked `Task` blocks
- **Location:** `StepsTrader/AppModel.swift:251-255`, `StepsTrader/Stores/SubscriptionStore.swift:129-133`, plus several other sites
- **What:** Each sink does `Task { @MainActor in self?.… }` without storing the Task handle, so the closure cannot be cancelled when the model is torn down or reconfigured.
- **Why:** On `DIContainer` recreate prior tasks continue running with stale `[weak self]` captures.
- **Action:** Promote these to stored `Task<Void, Never>?` properties or `Set<Task<Void, Never>>` and cancel them in `deinit` / on reconfigure.
- **Severity:** Medium
- **Что это значит на практике:** Если AppModel пересоздаётся (DIContainer reset, тесты, debug live-reload) — старые задачи продолжают жить и фигачить в призрак. В проде сейчас не критично, но тесты с пересозданием стейта будут флёкать.

### 3.6 ✅ _RESOLVED 2026-05-26: HK observer re-fetch task now gates on `isObserving`_

Решено через cancellation-aware гейтинг: после `await fetchSteps(...)` в observer-обработчике делается `let stillObserving = await MainActor.run { self.isObserving }` — если за время fetch'а `stopObservingSteps()` уже сбросил флаг, результат отбрасывается и обновление UI не уходит. Связано с §3.9 и §5.3 — закрыты тем же коммитом.

### 3.7 ✅ _RESOLVED 2026-05-26: Diagnostic block wrapped in `#if DEBUG`_

Раньше каждый `fetchSteps` запускал второй HK-запрос (source breakdown logging) через `Task.detached` — в Release этот код фигачил без причины, удваивая HK-нагрузку. Сейчас обёрнут в `#if DEBUG` в `HealthKitService.swift:243-267`, в Release-сборке блок не компилируется вообще. Closes §7.1 заодно.

### 3.8 `DeviceActivityMonitor` extension callbacks call `ShieldRebuildHelper.rebuild()` on the system-chosen thread
- **Location:** `DeviceActivityMonitor/DeviceActivityMonitorExtension.swift:148-160, 158-306`
- **What:** Extension lifecycle methods call into `Shared/ShieldRebuildHelper.rebuild()` which touches `ManagedSettingsStore`. Not annotated as `Sendable`.
- **Why:** Works today. Under strict concurrency, calling a non-`Sendable` API from an unknown actor context will warn.
- **Action:** Make `ShieldRebuildHelper` a stateless enum with explicitly `Sendable`-friendly inputs/outputs, document the threading contract.
- **Severity:** Medium
- **Что это значит на практике:** Работает на Swift 5. При апгрейде на strict concurrency компилятор не сможет проверить thread-safety extension'а который живёт в отдельном процессе. Время явно пометить контракты.

### 3.9 ✅ _RESOLVED 2026-05-26: Initial-fetch Task tracked via `initialFetchTask`, cancelled in `stopObservingSteps()`_

Закрыто тем же коммитом что §3.6 и §5.3. После каждого `await` в initial-fetch Task'е стоит `guard !Task.isCancelled else { return }` — наблюдение не стартует если caller уже остановил teardown.

### 3.10 ✅ _RESOLVED (already fixed in swiftui-pro review prior to this audit)_

`BlockingStore.swift:70` уже содержит `guard let self = self, !Task.isCancelled else { return }` после `Task.sleep`. Аудит-агент пропустил этот guard при первом сканировании — фикс был сделан в коммите `c5377a5` ранее.

### 3.11 `UIWindowScene.windows` accessed directly
- **Location:** `StepsTrader/Views/Onboarding/AppleSignInCoordinator.swift`, `StepsTrader/Stores/SubscriptionStore.swift:323-330`
- **What:** Code reaches for `scene.windows.first` to find a presentation anchor.
- **Action:** Use `UIApplication.shared.connectedScenes` pattern.
- **Severity:** Low
- **Что это значит на практике:** Сегодня работает. На iPad с двумя окнами/Split View может найти не то окно (например, Apple Sign-In popup появится не в активной сцене). Никто пока не жаловался — но если в будущем поддержка iPad Split View будет важна, нужно править.

### 3.12 `Timer.scheduledTimer` callback for the day-boundary check
- **Location:** `StepsTrader/AppModel.swift:344-355`
- **What:** Timer block hops to `Task { @MainActor [weak self] in … }`. Recursive re-schedule silently stops if `self` is nil between fires.
- **Action:** Replace with `AsyncStream` + `Task.sleep(until:)` and explicit cancel in `deinit`.
- **Severity:** Low
- **Что это значит на практике:** В реальной жизни не воспроизведётся (AppModel живёт сколько живёт приложение). В юнит-тестах с пересозданием — таймер «теряется», переход дня не срабатывает для нового инстанса.

---

## 4. API modernity

### 4.1 ✅ _RESOLVED 2026-05-26: All 16 files migrated to `.sensoryFeedback`_

Все 30 TODO-маркеров закрыты, ~60 imperative haptic-вызовов заменены на declarative `.sensoryFeedback` модификаторы. Паттерн в каждом файле один и тот же: `@State [name]HapticTick = 0` + `.sensoryFeedback(.impact(weight: .X), trigger: tick)` на body + `tick &+= 1` в обработчике.

Затронуты (14 файлов с обычным паттерном): `WorkoutSuggestionBanner`, `PaywallView`, `SettingsSubscriptionPage`, `SettingsWidgetPage`, `InlineTicketSettingsView`, `AppsPageSimplified`, `PaperTicketView`, `StepGoalDrumPicker`, `SleepGoalArcPicker`, `SettingsAppearancePage` (10 сайтов), `OnboardingStoriesView` (14 call-сайтов через 5 helper-функций, теперь удалены).

Финальные 2 файла с enum-Haptics паттерном (`private enum Haptics { static let light = UIImpactFeedbackGenerator(...) }` + `prepareAll()` + множество call-сайтов внутри файла) тоже закрыты:
- `CategoryDetailView` — enum удалён (light/medium/success), 10 call-сайтов заменены, `Haptics.prepareAll()` из `.onAppear` убран.
- `GalleryView` — enum удалён (light/medium), 16 call-сайтов заменены (включая один тройной кейс с условным `prepareAll`), 3 `.sensoryFeedback` модификатора на body.

`SmudgeCanvasView` и `ShaderParkOverlayView` — TODO заменён на пояснение: это `UIViewRepresentable`, хаптика стреляет внутри UIView touch handlers, `.sensoryFeedback` (SwiftUI-модификатор) физически не дотягивается до этих callback'ов. UIKit-генератор здесь архитектурно корректен.

### 4.2 ✅ _RESOLVED 2026-05-26 (commit `83b8475`): Vestigial `await` removed in post-login task_

Был единственный compiler warning в clean Debug build — закрыт. Project builds with 0 warnings.

### 4.3 `@Published` + `ObservableObject` still used where `@Observable` would do
- **Location:** `StepsTrader/AppModel.swift:18-20`, every file in `StepsTrader/Stores/*.swift`, `AuthenticationService.swift:62-63`
- **What:** Stores and services use `@MainActor final class … : ObservableObject` with `@Published`. Deployment target is iOS 17.5, so `@Observable` is supported.
- **Why:** `@Observable` removes Combine dependency, gives finer-grained dirty tracking.
- **Action:** Migrate incrementally — `AppModel` and stores are the biggest payoff.
- **Severity:** Medium
- **Что это значит на практике:** При любом изменении step count или sleep — перерисовывается ВСЁ дерево вьюх, которые смотрят на AppModel (а это полприложения). Невидимая трата CPU и батареи. С `@Observable` SwiftUI перерисует только то, что реально зависит от изменённого значения. Связано с §7.4.

### 4.4 ✅ _RESOLVED — см. §3.2_

Закрыта тем же коммитом. Континуация HK auth удалена, используется async overload.

### 4.5 ✅ _RESOLVED — см. §3.3_

Та же находка что §3.3, закрыта тем же коммитом.

### 4.6 No `@available(iOS X, *)` guards below the deployment target found
- **Location:** N/A
- **What:** Codebase clean — все @available-гарды актуальны для iOS 17.5+.
- **Action:** None.
- **Severity:** Low
- **Что это значит на практике:** Хорошие новости — нечего убирать. Информационный пункт.

---

## 5. Bugs / logic errors

### 5.1 ✅ _RESOLVED 2026-05-26: PayGate failure now surfaces an alert + dismisses the sheet_

`AppModel+PayGate.swift` refund-ветка теперь делает три вещи: рефанд + clear keys (как и раньше), плюс выставляет `payGateError` (новое `@Published` на `UserEconomyStore`) и зовёт `dismissPayGate(reason: .programmatic)`. На уровне `StepsTraderApp.body` повешен `.alert` который слушает этот error и показывает «Couldn't start the timer. Your colors were refunded — please try again in a moment.» (с локализацией). После закрытия alert'а сообщение клирится. `openPayGate` тоже клирит stale-state перед открытием.

Lifecycle: error выставляется ПЕРЕД dismiss → alert находится на корневом ZStack (а не внутри PayGateView) → виден после dismissal. Type-checker `body` пришлось разгружать — binding вынесен в `payGateErrorBinding` computed property (SwiftUI body уже был на пределе сложности).

### 5.2 App-Group `UserDefaults` compound mutations are not synchronized between app and DeviceActivity extension
- **Location:** `StepsTrader/Stores/BlockingStore.swift:87-93`, `DeviceActivityMonitor/DeviceActivityMonitorExtension.swift:172-192, 263-294`
- **What:** Individual `set`/`get` is atomic, but read-modify-write sequences (load → decode JSON → mutate → re-encode → set) have no cross-process coordination.
- **Why:** When the extension fires concurrently with app mid-save, extension can resurrect stale state. Sticky.
- **Action:** Move compound state to a `Shared/AppGroupStateStore` actor with `NSFileCoordinator` locking.
- **Severity:** High
- **Что это значит на практике:** Когда DeviceActivity extension стреляет (например, исчерпался time-budget) одновременно с пользователем в приложении (меняет настройки блокировки), может произойти что extension переписывает свежие настройки старой версией. Юзер видит: «я только что добавил приложение в группу — оно пропало». Узкое окно срабатывания, но залипает после — состояние не восстанавливается само.

### 5.3 ✅ _RESOLVED 2026-05-26: HK initial fetch can no longer write past `stopObservingSteps()`_

Закрыто тем же коммитом что §3.6 и §3.9. UX-сценарий sign-out → sign-in больше не показывает step count предыдущего юзера на новом аккаунте.

### 5.4 Day-boundary recompute can run with stale `dayEndHour` / `dayEndMinute`
- **Location:** `StepsTrader/AppModel+DailyEnergy.swift:36-38`, `StepsTrader/AppModel.swift:284-315`
- **What:** Settings sheet writes `dayEndHour/Minute` while recompute is in flight — part of recompute uses old boundary, part new.
- **Action:** Snapshot `(dayEndHour, dayEndMinute)` once at the top of any recompute.
- **Severity:** Medium
- **Что это значит на практике:** Юзер меняет время «конца дня» в настройках — на пару кадров canvas может прыгнуть в неожиданный день и обратно. Данные не теряются, но мерцание выглядит как баг. Юзер может репортить «настройка глюканула».

### 5.5 _RESOLVED 2026-05-26: Moment IDs now filtered at every Supabase sync boundary._

Original finding (now fixed): the local-only Moment feature was leaking `moment_<uuid>` IDs to `user_day_snapshots.body_ids/mind_ids/heart_ids` and `user_daily_selections.activity_ids/rest_ids/joys_ids`. The label was never sent, so a second device — or a fresh install restoring from server — would see opaque `moment_abc123` strings in `MeView` history.

What changed:
- `StepsTrader/Models/EphemeralMoment.swift` — centralized `idPrefix` constant and added `isMomentId(_:)` / `filteredOutOfSync(_:)` helpers.
- `StepsTrader/AppModel+DailyEnergy.swift` — `resolveOptionTitle` uses helper; `saveCurrentAsRoutine` strips moment IDs.
- `StepsTrader/Services/SupabaseSyncService+Stats.swift` — `performDaySnapshotSync` strips moment IDs; `loadDaySnapshotsFromServer` and `loadHistoricalSnapshots` strip on receive.
- `StepsTrader/Services/SupabaseSyncService+Selections.swift` — `performDailySelectionsSync` strips moment IDs.

Cross-device persistence remains a separate feature (would need a `moments` JSONB column on `user_day_snapshots`, restore + merge logic).

- **Severity:** Medium → **Resolved**
- **Что это значит на практике (для контекста):** До фикса юзер на втором устройстве видел в истории Me строку «moment_abc123» вместо своего лейбла («Wedding»). Теперь Moment-ID не уходят на сервер вообще — UI-копирайт «just for today, on this device» теперь правда.

### 5.6 Keychain migration silently keeps a UserDefaults shadow on Keychain failure
- **Location:** `StepsTrader/Services/AuthenticationService.swift:629-639`
- **What:** One-time migration writes session to Keychain. On failure, logs but keeps UserDefaults copy. `loadStoredSession` reads from Keychain only — fallback is never consulted.
- **Action:** Either fall back to UserDefaults if Keychain returns nil, or delete legacy and surface re-auth prompt.
- **Severity:** Medium
- **Что это значит на практике:** Первый запуск после ребута устройства, если Keychain ещё не разблокирован (узкое окно при загрузке) — юзер вылетит из аккаунта, хотя локальная сессия в UserDefaults сохранена. По логике должно бы откатиться к UserDefaults и не выкидывать. Редкое, но воспроизводимое.

### 5.7 ✅ _RESOLVED 2026-05-26: bundleId now validated against reverse-DNS regex_

`handleWidgetOpenApp` в `StepsTraderApp.swift:485-499` теперь сначала прогоняет `bundleId` через `^[a-zA-Z0-9](?:[a-zA-Z0-9\-]*\.)*[a-zA-Z0-9][a-zA-Z0-9\-]*$` перед передачей в `TargetResolver`. Только реально похожие на bundle-ID строки доходят до резолвера, остальное молча отбрасывается.

### 5.8 ✅ _RESOLVED 2026-05-26: re-entrancy guard added via `_openingBundleIds` Set_

Файл-scope `@MainActor private var _openingBundleIds: Set<String>` в `HandoffManager.swift` отслеживает какие bundleId сейчас в процессе открытия. `openTargetApp` пропускает дубликат, `attemptOpenScheme` чистит Set на success / на финальном failure / на «нет схем». Два быстрых открытия одного приложения подряд через Shortcuts больше не гонщатся.

### 5.9 ✅ _RESOLVED 2026-05-26: sleep-merge now reads `merged.last` first_

Цикл merge в `HealthKitService.swift:194-207` теперь делает `if let last = merged.last, interval.start <= last.end { ... }` вместо force-indexed `merged[merged.count - 1].end` для чтения. Сама запись остаётся через индекс (Swift не позволяет mutate через `last`), но read через optional делает refactor-safe.

### 5.10 Recursive timer rescheduling silently stops on `self == nil`
- **Location:** `StepsTrader/AppModel.swift:344-355`
- **What:** If `self?.scheduleDayBoundaryTimer()` fires when self deallocated, the chain ends with no log.
- **Action:** Guard log or move to `AsyncStream` scoped to model lifetime.
- **Severity:** Low
- **Что это значит на практике:** Только в тестах. В проде AppModel живёт всю жизнь приложения — баг недостижим.

---

## 6. Security

### 6.1 No Debug/Release split for Supabase credentials
- **Location:** `Config/Debug.xcconfig`, `Config/Release.xcconfig` (both `#include "Secrets.xcconfig"`)
- **What:** Single secrets file shared by both configurations. No environment isolation.
- **Action:** Split into `Secrets-Debug.xcconfig` / `Secrets-Release.xcconfig`. Add runtime URL host assertion in Release.
- **Severity:** High
- **Что это значит на практике:** Если решишь сделать staging-Supabase (для безопасных тестов миграций или фич без риска убить prod-данные пользователей) — придётся переделывать всю конфигурацию. Сейчас все dev-эксперименты идут в prod-базу. Случайно повредишь schema в dev — пользователи увидят сломанное приложение.

### 6.2 No hardcoded secrets in client code
- **Location:** Repo-wide grep
- **What:** All `Bearer …` use validated session tokens; Supabase anon key и RevenueCat key — публичные client-keys.
- **Action:** Document the contract in `README.md`.
- **Severity:** Low
- **Что это значит на практике:** Хорошие новости — секретов в клиенте нет. «Всё чисто», а не «надо чинить». Просто отметить в доках чтобы будущий контрибьютор не положил случайно service-role key в Secrets.xcconfig.

### 6.3 `supabase/functions/send-push/index.ts` is well-hardened
- **Location:** `supabase/functions/send-push/index.ts:1-275`
- **What:** Env-var validation, constant-time bearer compare, CORS closed, narrow APNs cleanup heuristic.
- **Action:** None. Use as template for future Edge Functions.
- **Severity:** Low
- **Что это значит на практике:** Хорошие новости. Push-функция сделана аккуратно — поведение под нагрузкой и злоупотреблением предусмотрено.

### 6.4 Handoff token is locally generated and locally verified — by design
- **Location:** `StepsTrader/Models/HandoffToken.swift:1-13`
- **What:** Local-only token, no privilege boundary crossed.
- **Action:** Document trust model in header.
- **Severity:** Low
- **Что это значит на практике:** Хорошие новости. Параноить не нужно — токен живёт на одном устройстве, юзер если хочет «обмануть» — обманывает сам себя. Просто прописать в комментарии, чтобы будущий аудитор не пугался.

### 6.5 Retry queue stores raw request bodies without integrity check
- **Location:** `StepsTrader/Services/SupabaseSyncService.swift:164-179`
- **What:** No CRC/HMAC on persisted requests; corrupted entry replays as malformed.
- **Action:** Optional — add CRC to envelope.
- **Severity:** Low
- **Что это значит на практике:** Если локальный UserDefaults внезапно повредится (что почти не бывает) — следующий ретрай улетит мусором, сервер вернёт 4xx, запись удалится. Тихий graceful fail. Хочется ловить корректнее — нужен checksum, но это belt-and-suspenders.

### 6.6 Print/log redaction
- **Location:** `StepsTrader/Services/AuthenticationService.swift` throughout
- **What:** Truncated user IDs, no raw tokens in logs.
- **Action:** None.
- **Severity:** Low
- **Что это значит на практике:** Хорошие новости. Токены в логах не лежат, аккаунты пользователей не утекут через crash-репорты или OSLog-экспорт.

### 6.7 Entitlements files were not opened
- **Location:** `Steps4/Steps4.entitlements`, extension entitlements
- **What:** Out of scope for this audit run.
- **Action:** Verify App Group present on every target.
- **Severity:** Low
- **Что это значит на практике:** Не значит что entitlements плохие — значит что их аудит требует отдельной проверки (сверка с Apple Developer portal). Можно пробежать глазами за 10 минут.

---

## 7. Performance

### 7.1 ✅ _RESOLVED — см. §3.7_

Закрыто тем же фиксом — диагностический HK-запрос обёрнут в `#if DEBUG`, в Release не компилируется.

### 7.2 Widget timeline provider does substantial work per entry
- **Location:** `UnlockWidget/UnlockTimelineProvider.swift:1-791`
- **What:** Snapshot + timeline computation reads App-Group keys, decodes ticket groups, formats per-locale strings. Per refresh.
- **Action:** Extract `WidgetBudgetCompute` value type; cache formatters at module scope.
- **Severity:** Medium
- **Что это значит на практике:** Виджет на home screen может расходовать чуть больше батареи, чем нужно. Профилировать нужно на реальном устройстве — может оказаться что не критично. Юзер не пожалуется напрямую, но в Battery → Usage by App цифра у виджета может быть выше типичной.

### 7.3 Hot SwiftUI views recompute heavy state in body
- **Location:** `StepsTrader/Views/GalleryView.swift`, `MeView.swift`, `CategoryDetailView.swift`
- **What:** Large `body` functions compute layout, sort, format, render in one pass without memoization.
- **Action:** Profile with SwiftUI Instruments; extract leaf views with `Equatable`; precompute heavy state.
- **Severity:** Medium
- **Что это значит на практике:** Видел лаги в Gallery/Me/CategoryDetail при скролле или анимациях? Скорее всего отсюда. Особенно заметно на старых устройствах (iPhone 11, SE) или при заполненных днях с большой историей. Нужно профилирование Instruments чтобы подтвердить.

### 7.4 Combine + `@MainActor` recalc fan-out
- **Location:** `StepsTrader/AppModel.swift:243-256`
- **Action:** Linked to `@Observable` migration (§4.3).
- **Severity:** Low
- **Что это значит на практике:** То же что §4.3 — без миграции на @Observable невозможно улучшить. Связано.

### 7.5 No fresh `CIContext` per-frame; Metal renderer uses static factory
- **Location:** `StepsTrader/Metal/MetalSmudgeRenderer.swift:140-160`
- **What:** Renderers constructed via static factory, reused properly.
- **Action:** None.
- **Severity:** Low
- **Что это значит на практике:** Хорошие новости. Метал-рендер canvas сделан правильно — нет per-frame allocations, которые могли бы лагать canvas-анимации.

---

## 8. SwiftUI / UI

A dedicated SwiftUI pass was not re-run for this audit — `git log` shows commit `c5377a5 refactor: apply swiftui-pro review fixes` landed recently on this branch.

### 8.1 Oversized view files — see §9.2 for the split proposal
- **Location:** `OnboardingStoriesView.swift`, `GalleryView.swift`, `MeView.swift`, `CategoryDetailView.swift`
- **Severity:** High
- **Что это значит на практике:** см. §9.2 — те же файлы.

### 8.2 Hardcoded animation durations scattered across files
- **Location:** `OnboardingStoriesView.swift` (~25 occurrences), `GalleryView.swift` (7), и 7 других файлов
- **What:** `.animation(.easeInOut(duration: 0.8), value: …)` с магическими числами.
- **Action:** Create `Utilities/AnimationDurations.swift` with named constants.
- **Severity:** Low
- **Что это значит на практике:** Если когда-нибудь решишь поменять общий «темп» анимаций приложения (например ускорить на 20% после A/B-теста) — придётся пробежать по 25+ файлам. Не блокирует ничего, но больно при глобальных правках.

### 8.3 Inconsistent date-helper usage in views
- **Location:** `StepsTrader/Views/DayCanvasViewerView.swift` (inline `endOfDay`), `DayBoundary.swift` (canonical)
- **Action:** Delete local helper, route through `DayBoundary`.
- **Severity:** Low
- **Что это значит на практике:** Если случайно поменяешь date-логику в одном месте и забудешь в другом — даты будут расходиться по экранам, особенно вокруг полуночи и кастомного «конца дня».

---

## 9. Dead code / duplication / refactor

### 9.1 ✅ _RESOLVED 2026-05-26 (commit `f610933`): ProfileLocationManager.swift + root artifacts deleted_

118 LOC dead code + 2 случайно закоммиченных .txt файла удалены. Освобождено ~120 LOC и одна permission-API surface (CoreLocation).

### 9.2 Oversized files (>500 LOC) — refactor candidates
Severity for the category overall: **High** (testability + change risk).

- **`StepsTrader/Views/OnboardingStoriesView.swift:1-1974`** — 31 `@State` vars, 10+ slide variants. Propose: extract per-slide views (`ColdOpenSlide`, `CanvasSleepSlide`, …) into `Views/Onboarding/Slides/`.
- **`StepsTrader/Views/GalleryView.swift:1-1657`** — couples canvas loading, sync, toolbar, edit mode. Propose: `CanvasToolbarState`/`CanvasEditState` view-models; `CanvasLoaderManager`; sub-views.
- **`StepsTrader/Services/AuthenticationService.swift:1-1307`** — 41 methods. Propose: split into `+PasswordReset`, `+Profile`, `+SessionManagement` extensions; extract `SupabaseAuthClient`.
- **`StepsTrader/AppModel+DailyEnergy.swift:1-1146`** — split into `+CustomActivities`, `+Moments`, `+CanvasSlots`. Fold 8 file-scope keys into `SharedKeys` (§9.4).
- **`StepsTrader/Views/MeView.swift:1-1119`** — extract `RadarLayout`, `RadarBackgroundRenderer`; `MeViewModel` for state.
- **`StepsTrader/Views/CategoryDetailView.swift:1-900`** — extract `ActivityGridView`, `UsageBreakdownView`, `UnlockSheetView`.
- **`UnlockWidget/UnlockWidgetViews.swift:1-808`** — extract `BudgetBar`, `AppGridItem`, `TicketGroupLabel`.
- **`UnlockWidget/UnlockTimelineProvider.swift:1-791`** — extract `WidgetBudgetCompute`; module-scope formatters.
- Smaller (`PaywallView`, `SettingsAppearancePage`, `StepsTraderApp`) — borderline, split if you touch them.

**Что это значит на практике:** Чтобы добавить новый слайд в onboarding, новый блок в Me, или новую секцию в Gallery — нужно орудовать в файле на 1000+ строк. Высокий когнитивный барьер, выше шанс случайно что-то задеть. Тесты писать на такие монолиты практически невозможно. Если планируешь активно развивать какую-то из этих фич — рефактор окупится в первой же следующей итерации.

### 9.3 `OnboardingPreview/Sources/OnboardingStoriesView.swift` is a symlink, not a duplicate
- **Location:** symlink to canonical `StepsTrader/Views/OnboardingStoriesView.swift`
- **Action:** Document the symlink in `README.md` or `Package.swift`.
- **Severity:** Low
- **Что это значит на практике:** Если новый разработчик «увидит дубликат» и попробует исправить — поломается preview-таргет. Документации сейчас нет, только git-история.

### 9.4 ✅ _RESOLVED 2026-05-26: 8 file-scope keys folded into `SharedKeys`_

`AppModel+DailyEnergy.swift` теперь использует только `SharedKeys.dailyEnergyAnchor` / `.dailySleepHours` / `.baseEnergyToday` / `.pastDaySnapshots` / `.dailyCanvasSlots` / `.customEnergyOptions` / `.savedRoutines` / `.dailyMoments`. Заодно `savedEnergyRoutines_v1` как raw-строка убран из `SupabaseSyncService.swift:576` и `Steps4Tests/EnergyRecalcTests.swift:214`. Single source of truth для всех 8 ключей теперь действительно single.

### 9.5 ✅ _RESOLVED 2026-05-26: URL moved to `AppConstants.URLs.wallpaperShortcut`_

`SettingsShortcutPage` теперь ссылается на `AppConstants.URLs.wallpaperShortcut` (новый namespace в `Utilities/AppConstants.swift`). Force-unwrap по-прежнему есть, но в одном месте, рядом с другими константами. Если будут добавляться URL'ы — теперь есть куда их складывать.

### 9.6 `fatalError()` in unavailable inits — intentional
- **Location:** `StepsTrader/Metal/MetalSmudgeRenderer.swift:144`, `MetalShaderParkRenderer.swift:52`
- **Action:** None.
- **Severity:** Low
- **Что это значит на практике:** Не баг, не надо трогать. Это паттерн для запрета no-arg init в singleton-фабриках. Информационный.

### 9.7 Unresolved TODOs / FIXMEs
- **Location:** ~33 TODO across the project. 24 — sensoryFeedback (§4.1).
- **Action:** Close sensoryFeedback bulk; convert rest to GitHub issues.
- **Severity:** Medium
- **Что это значит на практике:** TODO накапливается. Часть устарела (сделано но маркер забыли убрать), часть актуальна. Не критично сейчас, но если их станет 100+ — поиск реально важных пунктов превращается в шум.

### 9.8 Magic constants that should be named
- **Location:** Spread across UI
- **Action:** Extract constants that appear 3+ times.
- **Severity:** Low
- **Что это значит на практике:** Если решишь подстроить общий «вид» (opacity, JPEG quality, anim timing) — придётся искать grep'ом по всему проекту. Незаметно, пока не начнёшь массово править.

### 9.9 ✅ _RESOLVED 2026-05-26: OnboardingDemoView prints wrapped in `#if DEBUG`_

Четыре `print()` в `OnboardingDemoView.swift` (callback'и `onHealthSlide`, `onNotificationSlide`, `onFamilyControlsSlide`, `onFinish`) теперь обёрнуты в `#if DEBUG`. В Release-сборке вылетают целиком. `OnboardingPreview/Stubs.swift` оставлен — это SPM preview-only.

### 9.10 ✅ _RESOLVED 2026-05-26 (commit `26feba7`): Marketing docs moved to `docs/marketing/`_

6 маркетинговых .md файлов перенесены: BRANDBOOK, MARKETING_COMPETITOR_RESEARCH, ARTICLE_BLOG, POSITIONING_ANGLES_SKILL, TONE_OF_VOICE, MANUALS_TEXTS.

### 9.11 Naming / organization observations
- **Location:** Repo-wide
- **What:** `Energy*` (model), `daily*` (temporal), `spent*` (deduction) — coherent vocabulary, under-documented.
- **Action:** Add «Domain vocabulary» paragraph to `README.md` or `CLAUDE.md`.
- **Severity:** Low
- **Что это значит на практике:** Новому контрибьютору (или будущему тебе через полгода) нужно прочитать домен-логику чтобы понять разницу между Energy/daily/spent префиксами. Сейчас эти правила в голове только у тебя — записать однажды дёшево.

---

## 10. Cross-cutting recommendations

Patterns worth applying repo-wide rather than one finding at a time:

1. **Plan the Swift 6 strict-concurrency upgrade as a single focused PR.** Most of §3 is latent — `@unchecked Sendable` boxes, untracked `Task` handles, Combine sink → Task patterns. None is urgent in Swift 5 mode, but they'll cascade when the language mode flips. Make one branch that turns on strict concurrency, fix until clean, then merge.
2. **Migrate `ObservableObject` + `@Published` → `@Observable` for stores and `AppModel`.** Unlocks finer-grained invalidation (mitigates the fan-out in §7.4), removes Combine sink fan-out (§3.5), prerequisite for `@Bindable`.
3. **Centralize App-Group state behind a single actor in `Shared/`.** Multiple processes read/write the same `UserDefaults(suiteName:)`. A `Shared/AppGroupStore.swift` actor with typed accessors would (a) make the contract explicit, (b) be unit-testable, (c) hold `NSFileCoordinator` locking when that matters.
4. **Split `Secrets.xcconfig` per build configuration (§6.1).** Table-stakes for CI signing keys and staging databases.
5. **Bulk-migrate UIKit haptics → `.sensoryFeedback`.** 24 known sites (§4.1) in one PR.
6. **Add `[weak self]` + `Task.isCancelled` checks as a code-review pattern.** Several findings (§3.5, §3.6, §3.9, §3.10, §5.3) trace to the same anti-pattern. A short style note prevents recurrences.
7. **Document the threading contract on cross-process helpers.** `ShieldRebuildHelper`, `SharedKeys`, anything in `Shared/` should carry a header comment about which processes call them and from which actor.

---

## 11. What was NOT audited

- `admin-panel/` (Next.js + Supabase admin dashboard) — out of scope.
- `tg-admin/` (Cloudflare Worker Telegram bot) — out of scope.
- `web/` and the standalone marketing site — out of scope.
- Build settings and Xcode project structure beyond shared schemes and the four `*.xcconfig` files.
- Third-party dependency internals — `RevenueCat 5.72.0` and Supabase JS are black boxes.
- `Steps4Tests/` and `Steps4UITests/` — light scan only.
- Algorithmic correctness of Metal kernels — surface checks only.
- Entitlements XML files — see §6.7.
- StoreKit configuration — `.storekit` file structure not opened.
- Localization correctness — not assessed.
- Instruments profiling — perf findings are potential, not verified by trace.
- A separate SwiftUI-expert pass was not re-run (recent `c5377a5` already did one).
- Shield extension targets got light coverage.
- `supabase/migrations/` SQL not audited beyond the Edge Function in §6.3.

---

## 12. Verification

Spot-check pattern: open Xcode, command-click the `path:line` reference — it should land on the cited line.

### High findings — verified file:line

- **§3.2** — `StepsTrader/Services/HealthKitService.swift:29-32`. Confirmed `private final class UnsafeSendableBox: @unchecked Sendable`.
- **§3.3** — RESOLVED. Confirmed all 10 sites converted in `7a73f38`.
- **§4.1** — Repo-wide grep returns 24 matches; spot-verified 5.
- **§5.1** — `StepsTrader/AppModel+PayGate.swift:101-110`. Confirmed refund branch with no UI feedback.
- **§5.2** — `StepsTrader/Stores/BlockingStore.swift:87-93` + `DeviceActivityMonitorExtension.swift:172-192, 263-294`. No locking.
- **§5.3** — `StepsTrader/Services/HealthKitService.swift:396-409`. Task not stored.
- **§6.1** — `Config/Debug.xcconfig:4`, `Config/Release.xcconfig:4` both include same `Secrets.xcconfig`.
- **§9.1** — RESOLVED. Confirmed deletion in `f610933`.
- **§9.2** — File sizes confirmed via `wc -l`.

### Demotions from agent-flagged Critical

- **`handleAuthorization` missing `@MainActor`** (Agent A, Critical) — DROPPED. Class is `@MainActor`-isolated.
- **`Timer.scheduledTimer` not on MainActor** (Agent A, Critical) — DEMOTED to Low (§3.12). Closure does hop to MainActor.
- **HKObserverQuery races MainActor** (Agent A, Critical) — DEMOTED to Medium (§3.6). Handler does guard and dispatch correctly.
- **HKSampleQuery continuation violation** (Agent A, Critical) — DROPPED. Idiomatic continuation pattern.
- **DeviceActivityMonitor rebuild() background** (Agent A, Critical) — DEMOTED to Medium (§3.8). Standard extension pattern.
- **Release ships dev URL** (Agent C, Critical) — DEMOTED to High (§6.1). No env split, but not "ships wrong URL".
- **Handoff token forgery** (Agent C, High) — DEMOTED to Low (§6.4). Local-only trust boundary.
- **DeviceActivityMonitor print()** (Agent B, Low) — DROPPED. Properly DEBUG-guarded.

If any finding doesn't reproduce when you visit the line, ping me with the specific reference and I'll re-investigate.
