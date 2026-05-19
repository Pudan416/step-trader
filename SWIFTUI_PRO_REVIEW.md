# Steps4 — SwiftUI Pro Review

**173 файла проверены | ~200 проблем найдено | 9 категорий**

---

## Что нужно исправить (по приоритету)

---

### 🔴 КРИТИЧНО — исправить сейчас

#### 1. `@MainActor` отсутствует на Observable классах
Два класса хранят UI-состояние без изоляции — потенциальный data race.

> **Если не исправить:** Случайные крэши и глитчи UI при одновременном доступе из разных потоков. Под strict concurrency (Swift 6) — ошибки компиляции. Баги трудновоспроизводимые, ловятся только на реальных устройствах под нагрузкой.

| Файл | Что сделать |
|------|-------------|
| `Views/Gallery/CanvasStateManagers.swift` | Добавить `@Observable @MainActor` на `CanvasEditState` |
| `Views/Gallery/CanvasStateManagers.swift` | Добавить `@Observable @MainActor` на `CanvasToolbarState` |

#### 2. GCD (DispatchQueue) — запрещён в Swift Concurrency

> **Если не исправить:** При переходе на strict concurrency (Swift 6) — ошибки компиляции. Смешивание GCD и async/await создаёт неочевидные deadlock-ситуации. Apple активно deprecate'ит GCD в пользу structured concurrency.

Заменить на `Task` + `Task.sleep(for:)`. **~10 мест:**

| Файл | Строки |
|------|--------|
| `StepsTraderApp.swift` | 192, 495 |
| `MainTabView.swift` | 352, 356 |
| `SettingsSheet.swift` | 353, 417, 435 |
| `GalleryView.swift` | 449 |
| `OnboardingStoriesView.swift` | 263 |
| `RadialHoldMenu.swift` | 136 |

```swift
// ❌ Было
DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { doSomething() }

// ✅ Стало
Task { @MainActor in
    try? await Task.sleep(for: .milliseconds(800))
    doSomething()
}
```

#### 3. `Task.sleep(nanoseconds:)` — deprecated

> **Если не исправить:** Компилятор уже выдаёт deprecation warning. В будущей версии Swift API будет удалён — код перестанет компилироваться. Наносекунды нечитаемы и легко ошибиться на порядок (1 секунда = 1_000_000_000 нс).

Заменить на `Task.sleep(for:)`. **~20 мест:**

| Файл | Кол-во |
|------|--------|
| `StepsTraderApp.swift` | 3 |
| `AppModel.swift` | 1 |
| `BlockingStore.swift` | 3 |
| `NetworkClient.swift` | 1 |
| `SupabaseSyncService+*.swift` (8 файлов) | 10 |

```swift
// ❌ Было
try? await Task.sleep(nanoseconds: 2_000_000_000)

// ✅ Стало
try? await Task.sleep(for: .seconds(2))
```

#### 4. Force unwraps — потенциальные крэши

> **Если не исправить:** Каждый `!` — это потенциальный крэш в продакшене. Один невалидный URL, пустой массив или отсутствующий ключ в словаре = мгновенный вылет приложения. Apple ревью может заметить крэши в аналитике.

| Файл | Строка | Проблема |
|------|--------|----------|
| `EnergyGradientBackground.swift` | 67 | `palettes[.warmSunset]!` |
| `StepGoalDrumPicker.swift` | 12 | `Int(String($0))!` |
| `SettingsShortcutPage.swift` | 9 | `URL(string: "...")!` |
| `OnboardingFloaters.swift` | 128-129 | `points.last!` |

---

### 🟠 ВАЖНО — исправить в ближайшее время

#### 5. `foregroundColor` → `foregroundStyle` (~80+ мест)

> **Если не исправить:** `foregroundColor` deprecated с iOS 17. Сейчас — жёлтые warnings при компиляции (~80 штук засоряют лог). В будущих SDK может быть удалён. `foregroundStyle` поддерживает градиенты и hierarchical styles, а `foregroundColor` — нет.

Самое массовое изменение. Глобальный find-and-replace.

**Топ файлы:**
- `OnboardingStoriesView.swift` (~20 мест)
- `HandoffProtectionView.swift` (6)
- `StepBalanceCard.swift` (7)
- `ManualsPage.swift` (5)
- `QuickStatusView.swift` (4)
- `PayGateView.swift` (4)
- `SettingsSheet.swift` (4)
- `SettingsAppearancePage.swift` (3)
- `SettingsShortcutPage.swift` (3)
- `DayEndSettingsView.swift` (3)
- + ещё ~15 файлов

```swift
// ❌ Было
.foregroundColor(.secondary)

// ✅ Стало
.foregroundStyle(.secondary)
```

#### 6. `UIImpactFeedbackGenerator` → `sensoryFeedback()` (~15 файлов)

> **Если не исправить:** Каждый вызов `UIImpactFeedbackGenerator(style:).impactOccurred()` создаёт новый объект — лишние аллокации при каждом тапе. UIKit API не уважает системные настройки accessibility (Reduce Haptics). `sensoryFeedback()` автоматически интегрирован с SwiftUI lifecycle и Apple Watch.

Заменить UIKit-хаптику на SwiftUI-модификатор:

`GalleryView`, `SettingsAppearancePage`, `SettingsSubscriptionPage`, `SettingsWidgetPage`, `PayGateView`, `CategoryDetailView`, `OnboardingStoriesView`, `PaperTicketView`, `SleepGoalArcPicker`, `StepGoalDrumPicker`, `WorkoutSuggestionBanner`, `RadialHoldMenu`, `InlineTicketSettingsView`, `AppsPageSimplified`

```swift
// ❌ Было
UIImpactFeedbackGenerator(style: .light).impactOccurred()

// ✅ Стало (на вьюхе)
.sensoryFeedback(.impact(flexibility: .solid, intensity: 0.4), trigger: someValue)
```

#### 7. `Binding(get:set:)` в body — 7 файлов

> **Если не исправить:** Ручные биндинги создаются заново при каждом рендере body — лишняя работа. Хрупкий паттерн: легко забыть обновить get или set при рефакторинге → рассинхрон UI и данных. SwiftUI не может оптимизировать такие биндинги.

Заменить на `@State` + `onChange` или `.alert(item:)`:

| Файл | Проблема |
|------|----------|
| `SettingsAppearancePage.swift` | Toggle binding |
| `NotificationSettingsView.swift` | canvasTimeBinding |
| `PaywallView.swift` | errorBinding |
| `MeView.swift` | fullScreenCover binding |
| `AppsPageSimplified.swift` | alert binding |
| `InlineTicketSettingsView.swift` | Toggle binding |
| `ProfileEditorView.swift` | alert bindings |

#### 8. `showsIndicators: false` → `.scrollIndicators(.hidden)` (~10 мест)

> **Если не исправить:** Параметр инициализатора deprecated. Компилятор показывает warning. Модификатор `.scrollIndicators()` даёт больше контроля (`.automatic`, `.visible`, `.never`) и работает одинаково на всех осях.

`GalleryView`, `PaywallView`, `MeView` (×2), `HistoryView`, `ManualsPage`, `SettingsAppearancePage` (×3)

```swift
// ❌ Было
ScrollView(.horizontal, showsIndicators: false) { ... }

// ✅ Стало
ScrollView(.horizontal) { ... }
    .scrollIndicators(.hidden)
```

#### 9. `overlay(_:alignment:)` — deprecated форма (~20 мест)

> **Если не исправить:** Deprecated API — компилятор warning. Старая форма не поддерживает `@ViewBuilder`, что ограничивает сложность overlay-контента. В iOS 26 Liquid Glass анимации работают корректнее с новым синтаксисом.

Settings-страницы, `CanvasShapePreview`, `CanvasFramedDarkPoster`

```swift
// ❌ Было
.overlay(RoundedRectangle(cornerRadius: 10).stroke(...))

// ✅ Стало
.overlay { RoundedRectangle(cornerRadius: 10).stroke(...) }
```

#### 10. `onTapGesture` вместо `Button` — проблема VoiceOver

> **Если не исправить:** Элементы полностью невидимы для VoiceOver — слепые пользователи не могут использовать эти функции. Нарушение Apple Accessibility Guidelines может привести к отклонению в App Store Review. Также не работает с Voice Control и Switch Control.

| Файл | Строка | Что |
|------|--------|-----|
| `PaperTicketView.swift` | 101 | Тап по карточке |
| `MainTabView.swift` | 386 | Dismiss overlay |
| `GalleryView.swift` | 1358 | Metric popover dismiss |
| `DayCanvasViewerView.swift` | 97-101 | Canvas tap |
| `SettingsAppearancePage.swift` | 139-144 | Paywall gate |

---

### 🟡 СРЕДНИЙ ПРИОРИТЕТ — при работе с файлами

#### 11. `Date()` → `Date.now` (~60 мест по проекту)

> **Если не исправить:** Функциональной разницы нет — это чисто стилистическое улучшение. Но `Date.now` читается яснее ("текущий момент"), а `Date()` выглядит как "создать пустую дату". При code review и онбординге новых разработчиков `.now` сразу понятен.

Главные файлы: `AppModel.swift` (15), `SupabaseSyncService` (10), `HealthStore`, `UserEconomyStore`, `SubscriptionStore`, `BudgetEngine`, `OnboardingFlowView`, `OnboardingStoriesView`, `Date+Today.swift`

```swift
// ❌  Date()
// ✅  Date.now  или  .now
```

#### 12. `String(format:)` → FormatStyle (~25 мест)

> **Если не исправить:** C-style форматирование не уважает локаль пользователя (разделители тысяч, десятичный знак). Русский пользователь увидит "3.5" вместо "3,5". `FormatStyle` автоматически адаптируется под локаль, Dynamic Type и accessibility. Также `String(format:)` не проверяется компилятором — несоответствие типов = крэш в рантайме.

`FormattingHelpers`, `StatusViewHelpers`, `HealthStore`, `BlockingStore`, `StepBalanceCard`, `SleepGoalArcPicker`, `GalleryView`, `MeView`, poster views, `OnboardingFlowView`, `OnboardingStoriesView`

```swift
// ❌ Было
String(format: "%.1f", value)

// ✅ Стало
value.formatted(.number.precision(.fractionLength(1)))
```

#### 13. FileManager → современный URL API (4 файла)

> **Если не исправить:** Старый API возвращает опциональный массив URL — лишний guard/if let код, который никогда не фейлится на iOS. `URL.documentsDirectory` гарантированно non-nil, что убирает мёртвые ветки fallback-логики и упрощает код.

| Файл | Замена |
|------|--------|
| `AuthenticationService.swift` | `URL.documentsDirectory` |
| `CanvasStorageService.swift` | `URL.applicationSupportDirectory`, `URL.documentsDirectory` |
| `PersistenceManager.swift` | `URL.applicationSupportDirectory` |
| `HistoryThumbnailCache.swift` | `URL.cachesDirectory` |

#### 14. `.synchronize()` — удалить (no-op на современном iOS)

> **Если не исправить:** Ничего плохого не случится — метод уже ничего не делает с iOS 12+. Но создаёт ложное впечатление что нужен "ручной сейв", запутывает новых разработчиков, и засоряет код.

| Файл | Строка |
|------|--------|
| `AppModel+Payment.swift` | 91, 114 |
| `AppModel+DailyEnergy.swift` | 755 |
| `UserEconomyStore.swift` | 65 |

#### 15. `@Entry` макрос для EnvironmentValues (5 ключей)

> **Если не исправить:** Функционально идентично. Но старый паттерн — 8-10 строк бойлерплейта на каждый ключ. `@Entry` — 1 строка. При добавлении новых environment values будет копипаститься старый паттерн, увеличивая технический долг.

| Файл | Ключи |
|------|-------|
| `MainTabView.swift` | `topCardHeight`, `tabBarHeight` |
| `GlassCardModifier.swift` | `glassShimmerColor` |
| `ThemeModifiers.swift` | `appTheme`, `resolvedAppTheme` |

```swift
// ❌ Было (4 строки на ключ)
private struct AppThemeKey: EnvironmentKey {
    static let defaultValue: AppTheme = .night
}
extension EnvironmentValues {
    var appTheme: AppTheme { get { self[AppThemeKey.self] } set { ... } }
}

// ✅ Стало (1 строка)
extension EnvironmentValues {
    @Entry var appTheme: AppTheme = .night
}
```

#### 16. `ObservableObject` → `@Observable` миграция

> **Если не исправить:** `ObservableObject` перерисовывает ВСЕ вьюхи при изменении ЛЮБОГО `@Published` свойства. `@Observable` перерисовывает только вьюхи, которые РЕАЛЬНО используют изменённое свойство. На сложных экранах (Gallery, Canvas) это разница в десятках лишних перерисовок. Также `@Observable` убирает зависимость от Combine.

**Простые (начать с них):**
- `NoteReadTracker` — маленький, изолированный
- `CoachMarkManager` — каскадно уберёт `@ObservedObject` из overlay-вьюх
- `OnboardingCoordinator`

**Средние:**
- `BudgetEngine` (есть протокол-зависимость)

**Отложить:**
- `AppModel` — весь DI завязан
- `AuthenticationService` — наследует NSObject
- `ProfileLocationManager` — наследует NSObject (CLLocationManagerDelegate)

---

### 🟢 НИЗКИЙ — улучшать постепенно

#### 17. OnboardingStoriesView.swift — 1926 строк

> **Если не исправить:** Xcode previews тормозят/не работают на таких файлах. Autocomplete заметно лагает. Merge conflicts при работе в команде гарантированы. SwiftUI не может эффективно diff'ить тело из 240 строк — лишние перерисовки.

Самый большой файл проекта. 240-строчный body, 20+ `@ViewBuilder` методов.
→ Каждый слайд вынести в отдельный `View` struct в отдельном файле.

#### 18. Computed `some View` properties → отдельные View structs

> **Если не исправить:** Computed properties пересчитываются при каждом вызове body. Отдельные View structs дают SwiftUI structural identity — он может пропускать перерисовку если props не изменились. На экранах с анимациями (Gallery, Canvas) это ощутимая разница в производительности.

`MainTabView` (4), `GalleryView` (много), `CategoryDetailView` (много), `CoachMarkOverlay` (9), `RadialHoldMenu` (2), `EnergyGradientBackground`

#### 19. Несколько типов в одном файле

> **Если не исправить:** Затрудняет навигацию по проекту — Cmd+Shift+O не найдёт тип по имени файла. Merge conflicts чаще. Xcode file inspector показывает неправильное имя. При росте проекта проблема усугубляется.

| Файл | Типов |
|------|-------|
| `CanvasShapePreview.swift` | 9 |
| `SettingsComponents.swift` | 12 |
| `OnboardingModels.swift` | 5 |
| `EnergyOption.swift` | 4 |
| `AutomationUIModels.swift` | 4 |
| `CanvasOverlayStyle.swift` | 3 |
| `SharedUIComponents.swift` | 4 |

#### 20. `CGFloat` → `Double` (не-optional свойства)

> **Если не исправить:** Ничего не сломается — Swift автоматически бриджит. Но `Double` — каноничный тип Swift, а `CGFloat` — наследие Objective-C. Исключения: optional CGFloat и inout параметры — там бридж не работает.

`CanvasElement.swift` (×3), `PosterStyle.swift` (×1)

#### 21. Убрать лишний `return` в switch-выражениях

> **Если не исправить:** Чисто стилистическое. Код работает идентично. Но implicit return — идиоматический Swift с 5.9+, и его отсутствие выглядит устаревшим на ревью.

~50 `return` в ~10 файлах: `GradientPalette`, `CanvasOverlayStyle`, `ShapeStyles`, `PosterStyle`, `Tariff`, `AccessWindow`, `ActivitySuggestion`

#### 22. `.caption2` шрифт — слишком мелкий

> **Если не исправить:** При включённом Dynamic Type (Large/AX sizes) текст всё равно останется крохотным — пользователи с плохим зрением не смогут прочитать. Apple HIG рекомендует `.caption` как минимальный размер для читаемого текста.

`CanvasShapePreview`, `StepBalanceCard` (×3), `RadialHoldMenu`, `OnboardingStoriesView` (×2)
→ Заменить на `.caption` минимум.

#### 23. `@Animatable` макрос вместо ручного `animatableData`

> **Если не исправить:** Ручная реализация `animatableData` через `AnimatablePair` — хрупкая вложенная конструкция. При добавлении нового анимируемого свойства нужно менять nested pair. `@Animatable` макрос делает это автоматически и помечает неанимируемые свойства через `@AnimatableIgnored`.

`EnergyGradientAnimator` в `EnergyGradientBackground.swift`

#### 24. Лишний `import UIKit` (6 файлов)

> **Если не исправить:** Ничего не сломается. Лишний import просто добавляет шум. Но может путать — создаёт впечатление что файл использует UIKit напрямую, хотя всё идёт через SwiftUI.

`StepsTraderApp`, `AppModel`, `OnboardingFlowView`, `ProfileEditorView`, `TicketTemplatePickerView`, `Font+Custom`

#### 25. Мелкое

> **Если не исправить:** Каждый пункт — маленькое улучшение. `Task.detached` теряет actor context (может вызвать неожиданный поток). Legacy `Alert()` не поддерживает новые стили iOS 16+. `@unchecked Sendable` обходит проверки компилятора. `ContentUnavailableView` даёт системный look, а кастомный — нет. `bold()` лучше адаптируется под accessibility weight.

- `Task.detached` → `Task` в `ExportCanvasWallpaperIntent.swift`
- Legacy `Alert()` в `SettingsSubscriptionPage.swift` → modern `.alert()`
- `@unchecked Sendable` на `NetworkClient` → просто `Sendable`
- `ContentUnavailableView` вместо кастомного `EmptyStateView`
- `fontWeight(.bold)` → `bold()` в `QuickStatusView`, `HandoffProtectionView`

---

## Чистые файлы (всё ок ✅)

Shapes (все 10 рендереров/генераторов), Metal (оба), DIContainer, TargetResolver, все Protocols, SubscriptionGate, ErrorManager, SupabaseSyncDTOs, NotificationDelegate, LoginView, SettingsEnergyPage, AppleSignInCoordinator, SharedKeys, SeededRNG, AppLogger, AppTheme, AppColors, Color+Hex, EnergyCategory+Helpers, AppShortcuts, Localization, UserDefaults+StepsTrader, DayBoundary+App

---

## Быстрый план действий

| # | Что | Время | Эффект |
|---|-----|-------|--------|
| 1 | `.foregroundColor(` → `.foregroundStyle(` | 10 мин | 80+ warnings |
| 2 | `Task.sleep(nanoseconds:)` → `Task.sleep(for:)` | 10 мин | 20 мест |
| 3 | `DispatchQueue` → `Task` | 15 мин | 10 мест |
| 4 | `Date()` → `Date.now` | 15 мин | 60 мест |
| 5 | `showsIndicators: false` → `.scrollIndicators(.hidden)` | 5 мин | 10 мест |
| 6 | Удалить `.synchronize()` | 2 мин | 4 места |
| 7 | `@MainActor` на CanvasEditState/CanvasToolbarState | 1 мин | safety |
| 8 | `@Entry` для EnvironmentValues | 10 мин | 5 ключей |
| **Итого** | | **~1 час** | **~200 мест** |
