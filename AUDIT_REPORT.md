# AUDIT_REPORT.md
**PASS 1 / 2 — отчёт по чистке проекта Steps4 / StepsTrader**
_Дата прогона: 2026-05-10. Ни один файл не редактировался — это только разметка проблем для PASS 2._

---

## 0. TL;DR (что чинить в первую очередь)

| # | Что | Где (примеры) | Эффект |
|---|---|---|---|
| 1 | **Удалить мёртвую CloudKit-ветку** | `StepsTrader/AppModel+CloudKit.swift`, `StepsTrader/Services/CloudKitService.swift`, entitlement `CloudKit` в `StepsTrader/Steps4.entitlements:23` | −72 строк кода, минус целая сущность `iCloud` в подписи приложения, App Review не задаст лишних вопросов |
| 2 | **Снести стейл-копии в `.claude/worktrees/`** | `.claude/worktrees/pensive-cartwright-69ad95/...` (4 файла) | Их Cursor/Glob периодически предлагает редактировать вместо настоящих → разъезжающаяся правда |
| 3 | **Распилить `AppModel+DailyEnergy.swift` (1034 строки) на 3-4 части** | см. §6.1 | Самый тяжёлый и самый рискованный к слиянию файл проекта |
| 4 | **Перевести 50+ `*.shared` в Views на DI** | `SettingsSheet:18`, `MeView:6`, `HistoryView:223,406`, `GalleryView:300,718,901`, `CategoryDetailView:827`, `DayCanvasViewerView:328`, `OnboardingStoriesView:332,348` и т.д. | Невозможно нормально протестировать вьюхи; любая замена сервиса = глобальный grep |
| 5 | **Прибить `_v1`-суффиксы из `SharedKeys`** или зафиксировать как формат | `StepsTrader/Utilities/SharedKeys.swift` (≈ 60 ключей) | Сейчас читается как «в продакшне идёт миграция», а на самом деле никакой миграции нет |
| 6 | **Покрыть тестами `SupabaseSyncService` и `BlockingStore`** | в `Steps4Tests/` 0 файлов про них | Самые рискованные модули (сетевая логика + Family Controls) идут без сетки |
| 7 | **Сильно ужать `OnboardingStoriesView.swift` (1929 строк)** | `StepsTrader/Views/OnboardingStoriesView.swift` | Самый большой файл проекта, мешает быстрой навигации и SwiftUI-предпросмотрам |

---

## 1. Карта проекта (для контекста)

### Все файлы > 600 строк

| Строк | Файл | Что внутри |
|---:|---|---|
| 1929 | `StepsTrader/Views/OnboardingStoriesView.swift` | Сториз-онбординг |
| 1649 | `StepsTrader/Views/GalleryView.swift` | Галерея сгенерированных канвасов |
| 1141 | `StepsTrader/Views/GenerativeCanvasView.swift` | Сама рисовалка (Canvas + TimelineView) |
| 1067 | `StepsTrader/Services/AuthenticationService.swift` | Apple Sign-In + профиль + Keychain + Supabase Storage |
| 1034 | `StepsTrader/AppModel+DailyEnergy.swift` | Дневная энергия (главный god-helper модели) |
| 928  | `StepsTrader/Views/CategoryDetailView.swift` | Экран выбора активностей категории |
| 716  | `StepsTrader/Models/ProceduralShapeGenerator.swift` | Геометрия для блобов |
| 685  | `StepsTrader/Views/Settings/SettingsAppearancePage.swift` | Настройки внешнего вида |
| 679  | `StepsTrader/Views/MeView.swift` | Главный «Я»-таб |
| 627  | `StepsTrader/Views/PaywallView.swift` | Платный экран |
| 626  | `StepsTrader/Models/DailyEnergy.swift` | Конфиг и описания опций |
| 615  | `StepsTrader/Views/Components/EnergyGradientBackground.swift` | Анимированный градиент |
| 613  | `StepsTrader/Metal/MetalSmudgeRenderer.swift` | Metal-рендер «smudge» оверлея |

### Все 14 фасетов `AppModel+*.swift`

| Строк | Файл | Реальная роль |
|---:|---|---|
| 1034 | `AppModel+DailyEnergy.swift` | хранение/загрузка/синхронизация выборов, кастомных опций, рутин, восстановление из канваса, аналитика |
| 556  | `AppModel.swift` (база) | DI-склейка + 30+ форвардов в сторы |
| 438  | `AppModel+PayGate.swift` | PayGate, DeviceActivity-бюджеты |
| 210  | `AppModel+Payment.swift` | списание шагов, day-pass |
| 189  | `AppModel+WorkoutSuggestions.swift` | предложения активностей |
| 150  | `AppModel+DailyRandomTheme.swift` | дневная случайная тема (Pro) |
| 124  | `AppModel+AppSelection.swift` | сохранение `FamilyActivitySelection` |
| 111  | `AppModel+TicketGroups.swift` | тикет-группы (CRUD) |
| 72   | `AppModel+AppSettings.swift` | `AppUnlockSettings` |
| **60** | `AppModel+CloudKit.swift` | **полностью мёртвый, см. §3.1** |
| 53   | `AppModel+HealthKit.swift` | HealthKit-обёртки |
| 47   | `AppModel+AccessWindow.swift` | хелперы окон доступа |
| 40   | `AppModel+TicketManagement.swift` | тонкая обёртка над `BlockingStore` |
| 16   | `AppModel+BudgetTracking.swift` | один метод `updateDayEndSettings` |

---

## 2. Что нужно понимать про спец-доки

`CanvasPalettes.md`, `CanvasBodyMindHeart.md`, `CanvasLab-Spec.md`, `StepsTrader/Resources/{ChoiceImagesList.md, GenerativeGallery.md, TriangleOfLivedEnergy.md}` — это **дизайн-намерение**, как должна работать рисовалка и сами категории Body/Mind/Heart. По коду видно, что всё реализовано, **кроме одной существенной мелочи**: `StepsTrader/Models/ChoiceImageCatalog.swift` для `body` отдаёт пустой массив (там используются процедурные формы), а `mind`/`heart` — статические PNG. В доке про это не сказано, поэтому если придёт новый разработчик — он будет искать «где картинки тела» и не найдёт. Лучше дописать одну строчку в `ChoiceImagesList.md`.

---

## 3. Мёртвый код

### 3.1. CloudKit — большой мёртвый кусок

**Контекст:** проект давно перешёл на Supabase. CloudKit-сервис помечен как «superseded», но кодовая база и подпись приложения этого не знают.

- `StepsTrader/Services/CloudKitService.swift` (12 строк) — содержит **только** struct `CloudTicketSettings`, который дальше используется только в самом мёртвом фасете AppModel.
- `StepsTrader/AppModel+CloudKit.swift` (60 строк) — все 6 функций (`getAllTicketSettingsForCloud`, `getStepsSpentByDayForCloud`, `getDayPassesForCloud`, `restoreTicketSettingsFromCloud`, `restoreStepsSpentFromCloud`, `restoreDayPassesFromCloud`) **никем не вызываются** (проверено grep'ом по всему репозиторию — 0 совпадений за пределами самого файла).
- `StepsTrader/Steps4.entitlements:23` — всё ещё запрашивает entitlement `CloudKit`. Apple ругаться не будет, но в App Store Connect это формально декларация про «использует iCloud», что заставляет потом отвечать на лишние вопросы по приватности.
- `StepsTrader/Utilities/SharedKeys.swift:172` — комментарий `// MARK: - Supabase / CloudKit` тоже стоит причесать.

**Итог:** сносим оба файла, убираем CloudKit из entitlements, правим комментарий в SharedKeys, и ещё снимаем ссылки из `Steps4.xcodeproj/project.pbxproj` (строки 14, 139, 270, 420, 630, 701, 1250, 1312).

### 3.2. Стейл-копии в `.claude/worktrees/` (от старого Cursor-эксперимента)

Найдены дубликаты, которые «висят», но при этом легко открываются Glob/Cursor поиском и могут быть случайно отредактированы:

- `.claude/worktrees/pensive-cartwright-69ad95/StepsTrader/Views/CategoryDetailView.swift` — содержит, среди прочего, **другую** реализацию `Task { await SupabaseSyncService.shared.syncOptionEntries(entries) }` на строке 748, отличающуюся от настоящей на `StepsTrader/Views/CategoryDetailView.swift:827`.
- `.claude/worktrees/pensive-cartwright-69ad95/StepsTrader/Views/MainTabView.swift`
- (по описанию задачи там же ChoiceImageCatalog и SettingsAboutPage — проверить и снести всё дерево `.claude/worktrees/`)

Ничего из этого не входит в Xcode-таргет, но мешает работать. Просто `rm -rf .claude/worktrees/` и добавить путь в `.gitignore`, если ещё нет.

### 3.3. `print(...)` в проде (вместо `AppLogger`)

- `StepsTrader/Models/TicketGroup.swift:84`
  ```
  print("[TicketGroup] Failed to encode selection for group \(id): ...")
  ```
  Перевести в `AppLogger.familyControls.error(...)`.
- `StepsTrader/Views/OnboardingDemoView.swift:34` — диагностический `print` из демо-онбординга. Если демо-вьюха ещё нужна, обернуть в `#if DEBUG`; если нет — снести весь файл.

### 3.4. `_v1`-суффиксы (формальный «легаси», но миграции нет)

В `StepsTrader/Utilities/SharedKeys.swift` около **60** ключей оканчиваются на `_v1` (строки 57–202), но никаких чтений с `_v0`/«без суффикса» в коде нет. То есть это ложный сигнал «у нас тут миграция», а на самом деле это просто часть имени.

**Вариант А (минималистичный):** оставить как есть и в шапке файла поставить комментарий «v1 — это формат, а не версия миграции».
**Вариант Б (правильный):** обрезать суффикс `_v1` у всех ключей. Но это перепишет всем существующим пользователям ключи, и UserDefaults старого формата окажутся «потеряны» — нужно сначала написать одноразовый migrator. Это ловушка для PASS 2.

Сейчас в коде есть два места, где «двойное чтение» закладывает новую инкарнацию миграции:
- `StepsTrader/AppModel.swift:39-48` — `storedDayEnd()` читает `dayEndHour`/`dayEndMinute` сразу из `UserDefaults.stepsTrader()` **и** из `UserDefaults.standard`.
- `StepsTrader/Models/BudgetEngine.swift` (~106 строк) — пишет день-энда в **оба** домена.

Это означает: «когда-то значение жило в `UserDefaults.standard`, потом мы стали писать в App-Group, но fallback не убрали». На сегодня двойная запись — мусор. PASS 2: снести `UserDefaults.standard`-ветку, оставить только App-Group.

### 3.5. Что ещё проверить (но требует более глубокого статического анализа)

- Картинки в `UnlockWidget/Assets.xcassets/` — все 12 PNG (`facebook`, `instagram`, `tiktok`, …) ссылаются из `UnlockWidget/UnlockWidgetViews.swift` (там есть mapping `templateAppImageName`). Все используются.
- Локализованные строки в `StepsTrader/Localizable.xcstrings` — на этом проходе не сверяли построчно (это требует отдельного прохода по всем `String(localized:)`-вызовам).

---

## 4. Сломанные / незавершённые / стабовые функции

### 4.1. Исключение в проде, которое **может** выстрелить

- `StepsTrader/Metal/MetalSmudgeRenderer.swift:144`
  ```
  private override init() { fatalError("Use MetalSmudgeRenderer.create()") }
  ```
- `StepsTrader/Metal/MetalShaderParkRenderer.swift:52` — то же самое.

Эти `fatalError` приватные — снаружи класса вызвать `init()` нельзя, поэтому в норме не выстрелит. Но если кто-то по ошибке напишет `MetalSmudgeRenderer()` где-то в ext'е — приложение упадёт. Безопаснее заменить на `private init() {}` + комментарий «используйте `create()`».

### 4.2. `try!` — компиляция регулярных выражений

- `StepsTrader/Services/AuthenticationService.swift:239-240`
  ```
  private static let nicknameAllowedPattern = try! NSRegularExpression(pattern: "...")
  private static let countryCodePattern     = try! NSRegularExpression(pattern: "...")
  ```
  Регулярки статические, паттерн правильный — упасть не должно. Но при изменении строки одной опечаткой можно положить приложение на запуске. Безопаснее обернуть в `static let pattern: NSRegularExpression? = ...; guard let p = pattern else { ...вернуть валидный fallback... }`.

### 4.3. `try?` глотает ошибки в местах, где пользователь должен бы узнать

Поиск `try?` дал десятки совпадений; реально опасные:
- `StepsTrader/AppModel+DailyEnergy.swift:91` — JSON декодирование `customEnergyOptions`. Если файл побился — пользователь молча теряет все свои кастомные активности; даже лога не будет.
- `StepsTrader/AppModel+CloudKit.swift:21,48` — мёртвый код, см. §3.1.
- `StepsTrader/Stores/BlockingStore.swift` (~9 совпадений) — декодирование тикет-групп; при ошибке у пользователя «магическим образом» исчезают шторки.
- `StepsTrader/Services/SupabaseSyncDTOs.swift` — 10 совпадений при разборе DTO из ответа Supabase. Если бэкенд поменяет поле — клиент не покажет ошибку, а просто молча проигнорит данные.

**Действие:** в PASS 2 пробежать по всем `try?` в перечисленных файлах, заменить на `do/catch` + лог + (при необходимости) `ErrorManager.shared.show(...)`.

### 4.4. Незаконченные TODO в коде

- `StepsTrader/Models/DailyEnergy.swift:298` — *«TODO: Russian translations for descriptions and examples are pending — translators»*. Описания опций в `EnergyDefaults.options` сейчас только на английском. Это видимо для пользователя пробел. Решение продуктовое — либо подключить переводчика, либо снять TODO и спрятать поле «описание» в русской локали.
- `StepsTrader/Views/GalleryView.swift:1251` — TODO про профилирование сложных канвасов перед рендером. Не блокирующее, но стоит занести в трекер.

### 4.5. Кнопки/строки настроек, которые «ничего не делают»

При чтении 685-строчного `SettingsAppearancePage.swift` и 535-строчного `SettingsSheet.swift` пустых action'ов не нашёл, но ниже есть подозрительные:
- `StepsTrader/Views/HandoffProtectionView.swift:67` — `AppLogger.app.debug(...)` на `.onAppear`, без побочных эффектов; это не баг, но сообщает «Token ID: …» в продовом логе. Стоит понизить до `trace` или убрать.

### 4.6. Сверка Supabase: вызовы iOS ↔ миграции SQL

| iOS-вызов | Файл | URL/таблица | В миграциях? |
|---|---|---|---|
| `restoreFromServer`, `loadHistoricalSnapshots` | `SupabaseSyncService+Stats` | `user_day_snapshots`, `user_daily_stats` | ✅ |
| `syncDayCanvas`, `fetchDayCanvas` | `SupabaseSyncService+Canvas` | `user_day_canvases` | ✅ |
| `syncDailySelections`, `syncCustomActivities` | `SupabaseSyncService+Selections` | `user_daily_selections`, `user_custom_activities` | ✅ |
| `syncDailySpent` | `SupabaseSyncService+Spent` | `user_daily_spent` | ✅ |
| `trackAnalyticsEvent` | `SupabaseSyncService+Analytics` | `user_analytics_events` | ✅ |
| `syncSavedRoutines` | `SupabaseSyncService+Routines` | `user_routines` | ✅ |
| `syncTicketGroups` | `SupabaseSyncService+TicketGroups` | `shields` (синтетические `bundle_id`) | ✅ |
| `syncUserPreferences` | `SupabaseSyncService+Preferences` | `user_preferences` | ✅ |
| `syncOptionEntries` | `SupabaseSyncService+Entries` | `energy_ledger` | ✅ |

**Все вызовы попадают в существующие таблицы.** Здесь чисто.

### 4.7. RevenueCat: продукты ↔ `Configuration.storekit`

| iOS константа | StoreKit-файл | Совпадает? |
|---|---|---|
| `pro_monthly` | `Steps4/Configuration.storekit` | ✅ |
| `pro_annual` | то же | ✅ |
| `pro_lifetime` | то же | ✅ |

Сходится. Но `StepsTrader/Models/SubscriptionEntitlement.swift` хранит ID и для **энтайтлмента** `pro` — этот идентификатор должен совпадать с настройкой проекта в RevenueCat-дашборде. Это уже не код, но стоит ручной проверки.

---

## 5. Дублирование

### 5.1. Два пути для одного и того же

- **Вычисление «сегодня»**: в проекте сосуществуют
  - `Shared/DayBoundary.swift` — правильный путь, учитывает пользовательский день-энд (например, день кончается в 03:00).
  - `Calendar.current.startOfDay(for:)` — простой, **не** учитывает день-энд.

  В **проде** прямые вызовы `startOfDay` живут только в `Shared/DayBoundary.swift` (внутри самой реализации) и в тестах (`Steps4Tests/BudgetEngineTests.swift:106,161`, `Steps4Tests/WidgetTests.swift:152`). То есть продовые ветки ОК. Но при правках легко случайно вызвать `Calendar.current.startOfDay` где-то в новой вьюхе — стоит добавить SwiftLint-правило или хотя бы CI grep, который флагает такие места.

- **Хранение `dayEndHour/Minute`**: см. §3.4 — пишется и в App-Group и в `UserDefaults.standard`.

- **CloudKit-фасет vs Supabase-фасет**: см. §3.1 — мёртвый код, дублирующий смысл (восстановление настроек из облака).

- **`UserDefaults.stepsTrader()` vs `UserDefaults(suiteName: SharedKeys.appGroupId)`** — встречаются оба варианта в разных файлах; это один и тот же объект, но запись через два имени мешает grep'у. Нужно везде унифицировать на `UserDefaults.stepsTrader()`.

### 5.2. Большие повторяющиеся блоки

- **Шапка «получить токен и userId»**: один и тот же блок
  ```swift
  await AuthenticationService.shared.waitForInitialization()
  guard let token  = await AuthenticationService.shared.accessToken,
        let userId = await AuthenticationService.shared.currentUser?.id else { return }
  ```
  повторяется **примерно 25 раз** во всех `SupabaseSyncService+*.swift`.
  → Вынести в `func authenticatedContext() async -> (token: String, userId: UUID)?` на `SupabaseSyncService`.

- **`scheduleTicketGroupsSupabaseSync()` + `invalidateBundleIdCache()`** в `AppModel+TicketGroups.swift:11-67` повторяется в каждом методе. Можно вынести в `private func notifyGroupsChanged()`.

- **Загрузка/сохранение строкового массива из UserDefaults** в `AppModel+DailyEnergy.swift:39-44, 62-67, ...` — три раза подряд `loadStringArray(forKey: dailySelectionsKey(for: .body/.mind/.heart))`. Тоже повторяется в save/sync. Один helper `forEachCategory { ... }` сократит раз в 3.

### 5.3. Цвета и градиенты

`ColorConstants.swift` (232 строки) аккуратный. Но в `Views/Components/EnergyGradientBackground.swift` (615 строк) встречается **40+** прямых вызовов `Color(red:green:blue:)` вместо использования `AppColors`. Часть — обоснованы (это сама палитра градиента), но часть выглядит как «чтобы не идти в файл констант». Стоит вычитать на PASS 2.

### 5.4. Стили карточек

`GlassCardModifier` есть, и большинство экранов им пользуется (`SettingsSheet`, `HandoffProtectionView` и т.д.). Точечных переопределений `.background(.ultraThinMaterial)` в обход модификатора почти нет — здесь хорошо.

---

## 6. Структура и слои

### 6.1. `AppModel` — god-object

`StepsTrader/AppModel.swift` (556 строк) — это «фасад над сторами». Из плюсов: на верхнем уровне Views и Tests видят один объект. Из минусов:
- 30+ свойств — это **forward** к сторам (строки 56–151). Это 100 строк копипасты, которая прячет, что́ реально меняется и какой store «настоящий».
- 14 фасет-файлов (см. §1) с разной плотностью. Самые проблемные:
  - `AppModel+DailyEnergy.swift` (1034) — внутри **смешано**:
    - загрузка/сохранение в UserDefaults,
    - бизнес-логика расчёта EXP,
    - синхронизация с Supabase,
    - аналитика,
    - восстановление выборов из канваса (`recoverSelectionsFromCanvasIfNeeded`),
    - управление кастомными опциями (CRUD),
    - управление сохранёнными рутинами (CRUD).
    → Распилить минимум на 3 файла:
    ```
    AppModel+DailyEnergyState.swift     // load/save/recalc (≈ 350 строк)
    AppModel+CustomOptions.swift        // CRUD кастомных опций + sync (≈ 250)
    AppModel+Routines.swift             // CRUD рутин + sync (≈ 200)
    AppModel+EnergySync.swift           // оркестрация Supabase (≈ 250)
    ```
  - `AppModel+PayGate.swift` (438) — половина файла про DeviceActivity-бюджеты (это уровень `BlockingStore`/extension), половина — про показ PayGate (это уровень `UserEconomyStore`/View). Разрезать.
  - `AppModel+CloudKit.swift` (60) — целиком в корзину (см. §3.1).
  - `AppModel+TicketManagement.swift` (40) — настолько тонкая обёртка над `BlockingStore`, что можно убрать и звать стор напрямую.
  - `AppModel+BudgetTracking.swift` (16) — один метод `updateDayEndSettings`. Его место — в `BudgetEngine`.

### 6.2. Вьюхи лезут мимо DI (в `*.shared`)

Найдено **15+** мест, где SwiftUI-вьюха обращается к `Service.shared` напрямую вместо инъекции:

| Файл:строка | К чему обращается |
|---|---|
| `StepsTrader/Views/SettingsSheet.swift:18` | `AuthenticationService.shared` |
| `StepsTrader/Views/MeView.swift:6, 491` | `AuthenticationService.shared`, `SupabaseSyncService.shared` |
| `StepsTrader/Views/LoginView.swift:254` | `AuthenticationService.shared` (preview) |
| `StepsTrader/Views/HistoryView.swift:223, 406` | `SupabaseSyncService.shared` |
| `StepsTrader/Views/GalleryView.swift:300, 718, 901` | `SupabaseSyncService.shared` |
| `StepsTrader/Views/CategoryDetailView.swift:827` | `SupabaseSyncService.shared` |
| `StepsTrader/Views/DayCanvasViewerView.swift:328` | `SupabaseSyncService.shared` |
| `StepsTrader/Views/OnboardingStoriesView.swift:332, 348` | `SupabaseSyncService.shared` |
| `StepsTrader/Views/OnboardingFlowView.swift:97` | `SupabaseSyncService.shared` |
| `StepsTrader/Views/Onboarding/OnboardingCoordinator.swift:119, 135` | `SupabaseSyncService.shared` |
| `StepsTrader/Views/CoachMark/CoachMarkManager.swift:92, 105` | `SupabaseSyncService.shared` |

Это означает: подменить эти сервисы в Preview/тесте — невозможно. Любая попытка отрисовать `MeView` в Xcode Previews ломится в реальный Supabase.

И в `AppModel.swift:26, 458, 461, 523` сам корневой объект тянет `AuthenticationService.shared` и `SupabaseSyncService.shared`. То есть `DIContainer` по факту не управляет ни аутентификацией, ни синхронизацией — это «mock DI»: сделан только для HealthKit/FamilyControls/Notifications/BudgetEngine.

**Действие PASS 2:** перевести `AuthenticationService` и `SupabaseSyncService` на инъекцию через `DIContainer`, передавать в `AppModel.init`. Это большая работа, но без неё нельзя писать тесты на любую вьюху, которая дергает sync.

### 6.3. Вьюхи импортируют системные фреймворки напрямую

- `StepsTrader/Views/Settings/SettingsPermissionsPage.swift` дёргает HealthKit/FamilyControls статусы. Лучше через `AppModel.healthAuthorizationStatus` и `blockingStore.isAuthorized` (которые уже есть), не плодить параллельные вызовы.
- `StepsTrader/Intents/ExportCanvasWallpaperIntent.swift` ходит в `CanvasStorageService` напрямую — это нормально, потому что Intent-расширение DI не получает.

### 6.4. Смешение задач в одном файле

- `StepsTrader/Models/TicketGroup.swift` — это data-model, но внутри пишет в лог через `print(...)` (см. §3.3) и сам делает `NSKeyedArchiver` для сериализации `FamilyActivitySelection`. Сериализация — нормально, лог — выкинуть.
- `StepsTrader/Services/HistoryThumbnailCache.swift` — рендерит SwiftUI вью через `ImageRenderer` прямо в кэше; это смешение «render» и «storage». Не катастрофа, но при долгом канвасе блокирует.
- `StepsTrader/Models/Note.swift` — тут же `NoteReadTracker: ObservableObject`, который пишет в `UserDefaults.standard` (а не в App-Group). Если в будущем виджет/расширение захочет узнать «прочитал ли пользователь онбординг-нот», оно не увидит.

### 6.5. Несоответствия в нейминге

- `BlockingStore` vs упоминания «shield» в SharedKeys (`shieldGroups_v1`, `shieldState`, `liteShieldConfig`) — пользователь видит «Shield», код говорит «Blocking». Это путает.
- `payForEntry` vs `purchaseUnlock` vs `dayPassGrants` — в коде встречаются три словаря, описывающих по сути «что-то куплено за шаги». Стоит унифицировать терминологию.
- `customEnergyOptions` (массив CustomEnergyOption) и `customOptions(for:)` (метод, который возвращает `[EnergyOption]`) — разные имена, очень похожие сигнатуры.

---

## 7. Производительность

### 7.1. Главная рисовалка `GenerativeCanvasView` (1141 строк)

`StepsTrader/Views/GenerativeCanvasView.swift:105` — `TimelineView(.animation(minimumInterval: 1.0/20.0))` = 20 fps пересчёта. Внутри тяжёлая `Canvas { ... renderCanvas(...) }`. Что увидел:
- В проде используется кэш `RenderCache` (строки 40-67) как `@State` класс — это правильное решение, не пересоздаётся при перерисовке.
- Но `clusterCache: [Set<UUID>: ClusterCacheEntry]` (строка 60) **никогда не выселяется** по числу элементов — растёт пока экран открыт. На длинной сессии (несколько часов в фоне с активным таймером) — потенциальная утечка памяти.
- `mindPositionCache` (строка 64) не имеет верхнего лимита — то же самое.
- `Canvas` blendMode пересчитывается **на каждый кадр** через `UIColor(backgroundColor).getHue(...)` (строки 69-73) — недорого, но дёргается 20 раз в секунду без причины. Зацепить как `@State` и обновлять только при смене `backgroundColor`.

### 7.2. `EnergyGradientBackground` (615 строк) — сильно перегружено

40 вызовов `Color(red:...)` внутри body — каждый из них создаёт новый `Color` объект на каждый перерасчёт. SwiftUI хорошо это переживает, но при включенном TimelineView выше — это десятки kpages-allocations в секунду. PASS 2: вынести палитру в `static let` массив `[Color]` и брать оттуда.

### 7.3. Виджет (`UnlockTimelineProvider`)

- Читает из App-Group **в каждом вызове** `getTimeline`:
  - `SharedKeys.ticketGroups`
  - `SharedKeys.legacyShieldGroups` (sic! легаси-чтение всё ещё активно, см. §3.4)
  - `SharedKeys.liteTicketConfig`
  - бюджеты для каждой группы
  
  Если у пользователя 10+ групп, каждое обновление — 30+ читок UserDefaults подряд. Не катастрофа (UserDefaults быстрый), но `legacyShieldGroups` — мёртвая ветка, читать незачем.

### 7.4. `HistoryThumbnailCache`

- `StepsTrader/Services/HistoryThumbnailCache.swift` (185 строк) — двухуровневый кэш (память + диск PNG). Эвикции по числу элементов в памяти **нет** — в коде только эвикция по предупреждению о памяти. На устройстве с 90 днями истории это до 90 декодированных `UIImage` в памяти (≈ 30-40 MB). PASS 2: добавить LRU с лимитом, например, 30.

### 7.5. Главный экран галереи

- `StepsTrader/Views/GalleryView.swift:718` — каждое открытие галереи дёргает `SupabaseSyncService.shared.fetchDayCanvas`. Это на сети, но без локального дебаунса при быстром скролле. PASS 2: дебаунсить запросы или делать только видимым ячейкам.

### 7.6. Metal-рендереры

- `StepsTrader/Metal/MetalSmudgeRenderer.swift` (613 строк) и `MetalShaderParkRenderer.swift` (221 строки) — пайплайн-стейты создаются один раз в `create()`, не в кадре. Это правильно. По текстурам/буферам в этом проходе утечек не вижу, но для уверенности нужен профайл в Instruments → Allocations + Metal HUD.

### 7.7. `DeviceActivityMonitorExtension` (≈ 6 MB лимит процесса)

- В `DeviceActivityMonitor/DeviceActivityMonitorExtension.swift` подключаются `AppLogger`, `SharedKeys`, `LiteTicketConfig`, базовые модели — это лёгкое.
- **Тревожно:** в `setupBlockForMinuteMode` он **создаёт `ManagedSettingsStore`** и читает все шторки. Это нормально. Но при чтении `ticketGroups` он декодирует полный `TicketGroup` с `FamilyActivitySelection`, что тяжело (NSKeyedUnarchiver). Поэтому в проекте уже есть `LiteTicketConfig` для этого расширения. Проверить, что **нигде** в monitor-расширении не читается «жирный» `SharedKeys.ticketGroups` — в текущей версии встречаются обращения к `legacyShieldGroups` и `liteTicketConfig` (это lite — ок), и нет к жирному. Хорошо.

### 7.8. Heavy main-thread JSON

- `StepsTrader/Services/SupabaseSyncService+Stats.swift` — в `loadHistoricalSnapshots` тянет страницами и декодирует в текущем актёре (это `actor`, то есть фоновый поток) — ОК.
- `StepsTrader/Services/SupabaseSyncService+Canvas.swift` — `performDayCanvasSync` кодирует `DayCanvas` (это может быть 5-50 КБ JSON) — тоже на актёре.
- `StepsTrader/Services/CanvasStorageService.swift` — пишет PNG-снапшот канваса. Если вызвано **из main**-actor (а `saveWidgetSnapshot` — да), то рендер `ImageRenderer` идёт на main и блокирует UI на длинных канвасах. PASS 2: завернуть снимок в `Task.detached`.

### 7.9. Картинки виджета

| Файл | Размер |
|---:|---|
| `colors.png` | 95 КБ |
| `snapchat.png` | 54 КБ |
| `telegram.png` | 52 КБ |
| `instagram.png` | 52 КБ |
| `youtube.png` | 50 КБ |
| `whatsapp.png` | 50 КБ |
| `pinterest.png` | 49 КБ |
| `linkedin.png` | 48 КБ |
| `x.png` | 47 КБ |
| `reddit.png` | 46 КБ |
| `facebook.png` | 45 КБ |
| `tiktok.png` | 45 КБ |

Всего **≈ 633 КБ ассетов**, что пакетируется внутри extension. Не катастрофа, но `colors.png` 95 КБ — это явно «оригинал», его стоит пережать через ImageOptim/pngcrush. Лучше всего — заменить все 12 на SF Symbols или векторные SVG, тогда extension вообще без растровых ассетов.

---

## 8. Корректность (мины замедленного действия)

### 8.1. Force-unwrap'ы и `try!`

- Уже разобраны в §4.1 (`fatalError` в Metal-рендерах) и §4.2 (`try!` в `AuthenticationService`).
- Других `try!`/`as! Type` в продакшн-коде `StepsTrader/` **не нашёл**. Это редкость и хороший знак.

### 8.2. Пустые `catch` / молчащие ошибки

См. §4.3 (`try?`). Помимо уже названных:
- `StepsTrader/StepsTraderApp.swift:55` — `SubscriptionStore.shared.configure(apiKey: rcKey)` — если `rcKey` пустой, configure тихо «как-то» отработает. Стоит добавить лог `assert(!rcKey.isEmpty)`.

### 8.3. Off-main UI

- `WidgetCenter.shared.reloadAllTimelines()` вызывается в `AppModel.handleAppDidEnterBackground()` (430-432), который сам `@MainActor`. Это безопасно, но `reloadAllTimelines` сам по себе можно дергать с любого потока — лишний main-блок.
- `UNUserNotificationCenter.current().notificationSettings()` в `refreshNotificationAuthorizationStatus()` — это `await`, безопасно.

### 8.4. `Task { ... }` без отмены, владельцем — View

При чтении `GalleryView.swift:300, 718, 901`, `MeView.swift:491`, `OnboardingStoriesView.swift:332,348`, `CategoryDetailView.swift:827`, `DayCanvasViewerView.swift:328` — везде `Task { await SupabaseSyncService.shared.… }` без сохранения handle. Если пользователь свайпнул экран до того, как ответ пришёл, задача доработает в фоне, обновит модель — на UI ничего страшного, но это пустая работа и потенциальная гонка.

PASS 2: завернуть в `.task { ... }` (SwiftUI его сам отменяет при исчезновении вьюхи) либо хранить handle и отменять в `onDisappear`.

### 8.5. Combine-цепочки

В `AppModel.init` (StepsTrader/AppModel.swift:239-264) во всех `.sink { [weak self] _ in ... }` правильно используется `[weak self]`. Утечек по `cancellables` не замечено. Хорошо.

### 8.6. Day-boundary

- `Calendar.current.startOfDay` в **проде** не используется (см. §5.1). Все боевые места ходят через `DayBoundary.dayKey/.currentDayStart/.nextBoundary`. Хорошо.

### 8.7. Часовые пояса при отправке в Supabase

В DTO (`SupabaseSyncDTOs.swift`, 432 строк) даты обычно сериализуются как ISO-8601 через `JSONEncoder.dateEncodingStrategy = .iso8601`. **Но**: ключ дня (`dayKey`) — это локальная строка вида `2026-05-10`, и она **зависит от часового пояса устройства и от пользовательского day-end**. Если пользователь летит в Австралию — у него `dayKey` сменится с разрывом в 18 часов, и сервер увидит «два разных дня» одновременно. Это не баг, а архитектурное допущение, но стоит зафиксировать комментарием в `DayBoundary` и проверить, что аналитика на бэкенде это понимает.

### 8.8. Обход `SubscriptionGate`

Поиск показал, что почти все проверки идут через `SubscriptionGate.canCreateCustomActivity(isPro:)`/`SubscriptionGate.shouldShowPostOnboardingPaywall(...)` или через `model.isPro`. Прямого `if subscriptionStore.hasProEntitlement` (минуя гейт) нет. Гейт работает как единая точка входа — это правильно.

Один тонкий момент:
- `StepsTrader/Views/HistoryView.swift:26-32` — `effectiveIsPro` в DEBUG разрешает разлочить через `debugForceUnlock`. Это `#if DEBUG`, в релиз не попадёт — ОК.

---

## 9. Тесты

### 9.1. Что покрыто (10 файлов в `Steps4Tests/`)

| Тест-файл | Покрывает | Замечания |
|---|---|---|
| `BudgetEngineTests.swift` | `Models/BudgetEngine.swift` | хорошо: tariff, day-end, persistence |
| `CanvasPersistenceRegressionTests.swift` | `AppModel+DailyEnergy.swift` (back-compat) | тянет реальный `SubscriptionStore.shared` (см. §6.2) |
| `CustomActivityTests.swift` | `AppModel+DailyEnergy.swift` (CRUD кастомных) | тоже тянет `SubscriptionStore.shared` |
| `DailyEnergyLogicTests.swift` | `EnergyDefaults` константы и формулы | |
| `DayBoundaryTests.swift` | `Shared/DayBoundary.swift` | очень хорошо |
| `HealthKitTests.swift` | `Services/HealthKitService.swift`, `Stores/HealthStore.swift` | использует `ConfigurableHealthKitMock` — отлично |
| `OnboardingFlowTests.swift` | `Views/Onboarding/OnboardingModels.swift`, `OnboardingCoordinator.swift` | |
| `TariffDecodingTests.swift` | `Models/Types.swift::Tariff` (back-compat «lite») | |
| `TicketGroupCostTests.swift` | `Models/TicketGroup.swift::cost(for:)` | |
| `WidgetTests.swift` | `Shared/SharedKeys.swift`, `WidgetDataFile`, `AccessWindow` | |

### 9.2. Что **не покрыто** вообще

| Модуль | Файлы | Почему критично |
|---|---|---|
| Подписка | `Stores/SubscriptionStore.swift` (506) | Деньги. Любой регресс в isPro/grandfathering — катастрофа |
| Supabase синхронизация | весь `SupabaseSyncService*` (≈ 2000 строк суммарно) | Сетевая логика, очередь ретраев, дебаунс |
| Family Controls / Шторки | `Stores/BlockingStore.swift` (463), `Services/FamilyControlsService.swift` (113) | Главная фича приложения |
| Аутентификация | `Services/AuthenticationService.swift` (1067) | Самый большой сервис |
| Платежи (внутри AppModel) | `AppModel+Payment.swift`, `AppModel+PayGate.swift` | Логика списания шагов |
| Виджеты (полный e2e) | `UnlockWidget/UnlockTimelineProvider.swift`, `UnlockGroupWidgetIntent.swift` | Тестируется только `WidgetSnapshot` |
| Metal | оба рендера | Их сложно тестировать, ОК |
| Все Views | весь `StepsTrader/Views/` (~ 11k строк) | Снэпшот-тесты помогли бы поймать регрессы дизайна |

### 9.3. Skip / disabled / always-pass

Беглый просмотр 10 тест-файлов **ни одного** `XCTSkip`, `disabled`-метки или вырожденного `XCTAssert(true)` не показал. По факту все тесты — рабочие.

---

## 10. Малые мелочи на «потом»

- `StepsTrader/StepsTraderApp.swift:55` — RevenueCat ключ читается из `Bundle.main.infoDictionary?["RevenueCatAPIKey"]` без явной валидации. Если xcconfig не подложил — приложение запустится без подписки. Поставить `assertionFailure` в DEBUG.
- `StepsTrader/Views/HandoffProtectionView.swift:67-68` — два `AppLogger.app.debug` в `.onAppear` с токеном внутри. Понизить уровень или убрать.
- `Config/Secrets.xcconfig` (без `.template`) — проверить что не в git'е. По `git status` он modified, что подозрительно: значит трекается. **Срочно убрать из git и пересоздать секреты в RevenueCat / Supabase.**
- `BRANDBOOK.md:516` — упоминает CloudKit как «Legacy sync». Если убираем CloudKit — поправить.
- `PROJECT_STRATEGY.md:327` — там же `CloudKitService.swift` в списке сервисов. После §3.1 убрать.

---

## 11. Что НЕ удалось проверить полностью на этом проходе

1. **Неиспользуемые локализованные ключи в `Localizable.xcstrings`** — нужно отдельным проходом сверить с `String(localized:)` по всему проекту.
2. **Неиспользуемые `.colorset`/`.imageset` в `StepsTrader/Assets.xcassets/`** — частично покрыто Приложением C.
3. **Реальная нагрузка `GenerativeCanvasView` в Instruments** — нужны измерения CPU/GPU.
4. **DeviceActivityMonitor под нагрузкой памяти** — нужно реально пробить лимит 6 МБ через TestFlight.
5. **Часть глубоких ветвей `OnboardingStoriesView` (1929 строк)** — прочитан, но не настолько детально.

---

## 12. Чек-лист для PASS 2 (предлагаемый порядок)

**Этап A — без риска (~ 1 день):**
- [ ] `rm -rf .claude/worktrees/`
- [ ] Удалить `AppModel+CloudKit.swift`, `Services/CloudKitService.swift`, ссылки в `project.pbxproj`, entitlement `CloudKit`
- [ ] Заменить два `print(...)` (TicketGroup, OnboardingDemoView) на `AppLogger`
- [ ] Заменить `try!` в `AuthenticationService.swift:239,240` на безопасный fallback
- [ ] Заменить `fatalError` в обоих Metal-рендерах на пустой `init`
- [ ] Скрестить `Config/Secrets.xcconfig` с `.gitignore` (если коммитится — выкорчёвывать историю)

**Этап B — рефакторинг под тесты (~ 2-3 дня):**
- [ ] Распилить `AppModel+DailyEnergy.swift` (1034 → 4 файла по ≈ 250)
- [ ] Распилить `AppModel+PayGate.swift` (438 → 2 файла)
- [ ] Снести `AppModel+TicketManagement.swift` и `AppModel+BudgetTracking.swift` (поглотить сторами)
- [ ] Вынести «получить токен и userId» в один helper `SupabaseSyncService`

**Этап C — DI и тесты (~ 1 неделя):**
- [ ] Перевести `AuthenticationService` и `SupabaseSyncService` на инъекцию через `DIContainer`
- [ ] Переписать все 15+ обращений `Service.shared` во Views на `@EnvironmentObject` или параметр
- [ ] Написать тесты на `SubscriptionStore` (`isPro`, grandfathering)
- [ ] Написать unit-тесты на `BlockingStore` (создание/удаление групп, слияние селекций)
- [ ] Написать тесты на `SupabaseSyncService` (мок `NetworkClient`)

**Этап D — производительность (~ 2-3 дня):**
- [ ] LRU-эвикция в `HistoryThumbnailCache` и в `RenderCache.clusterCache`
- [ ] Выключить чтение `legacyShieldGroups` в `UnlockTimelineProvider`
- [ ] Вынести `EnergyGradientBackground` палитру в `static let`
- [ ] Завернуть `saveWidgetSnapshot` в `Task.detached`
- [ ] Пережать `colors.png` (95 КБ → < 30 КБ) или заменить на SF Symbol

**Этап E — миграция ключей (опасно, отдельно):**
- [ ] Решить судьбу `_v1`-суффиксов (либо комментарий, либо реальная миграция)
- [ ] Унифицировать `dayEndHour/Minute` на App-Group, выпилить дубль из `UserDefaults.standard`

---
---

# Приложение A — полный список `try?` (для PASS 2)

Всего ≈ 95 совпадений. Группирую по «опасности», а не по файлу.

## A.1. **Опасные** — пользователь может молча потерять данные

Здесь `try?` глотает **декодирование пользовательских данных**. Если файл/ключ побьётся, у пользователя «магически» исчезнут активности, тикет-группы, кастомные опции. Нужен `do/catch` + лог + `ErrorManager.shared.show(...)`.

| Файл:строка | Что молча теряется |
|---|---|
| `StepsTrader/AppModel+DailyEnergy.swift:84,91` | весь массив `customEnergyOptions` |
| `StepsTrader/AppModel+DailyEnergy.swift:223` | `dailyCanvasSlots` (4 слота главного канваса) |
| `StepsTrader/AppModel+DailyEnergy.swift:335-344` | `pastDaySnapshots` (вся история) |
| `StepsTrader/AppModel+DailyEnergy.swift:984` | сохранённые рутины |
| `StepsTrader/AppModel+AppSettings.swift:55` | `appUnlockSettings` (цена входа на каждое приложение) |
| `StepsTrader/AppModel+PayGate.swift:412-413,418` | история транзакций PayGate |
| `StepsTrader/Stores/BlockingStore.swift:108,114,216` | тикет-группы и `appSelection` (все шторки) |
| `StepsTrader/AppModel+WorkoutSuggestions.swift:177` | список «принятых» тренировок (двойной показ предложения) |
| `StepsTrader/Views/CategoryDetailView.swift:797,822` | `OptionEntry` для конкретной активности |
| `StepsTrader/Models/TicketGroup.swift:49,59-60` | `enabledIntervals` и `FamilyActivitySelection` группы |
| `StepsTrader/Models/AppUnlockSettings.swift:27,30` | back-compat поля `minuteTariffEnabled`/`allowedWindows` |
| `StepsTrader/Models/DailyEnergy.swift:69,76` | back-compat `inkEarned`/`inkSpent` |

## A.2. **Условно опасные** — сетевая логика и очереди ретраев

Если глотать здесь, пользователь не увидит ошибку, но что-то «не синкается». Желательно хотя бы лог в `AppLogger.network.error`.

| Файл:строка | Что молча теряется |
|---|---|
| `StepsTrader/Services/SupabaseSyncService.swift:182,189,521-541` | очередь `PendingSyncRequest`, локальный кэш `local`, `routines` |
| `StepsTrader/Services/SupabaseSyncService+Stats.swift:241,298` | загрузка `SupabaseConfig` |
| `StepsTrader/Services/SupabaseSyncService+Routines.swift:88` | `_ = try? await network.data(for: delReq)` — DELETE-запрос на удалённую рутину; если упало, на сервере останется зомби |
| `StepsTrader/Services/SupabaseSyncService+Preferences.swift:162,269` | сериализация/десериализация `canvasSlots` |
| `StepsTrader/Services/SupabaseSyncService+Canvas.swift:10` | сериализация `DayCanvas` перед отправкой |
| `StepsTrader/Services/SupabaseSyncService+Analytics.swift:88` | сохранение очереди событий аналитики |
| `StepsTrader/Services/SupabaseSyncService+TicketGroups.swift:121` | `JSONSerialization.jsonObject` ответа |
| `StepsTrader/Services/SupabaseSyncDTOs.swift:6,179,235-237,416-424` | весь `AnyCodable`-разбор |
| `StepsTrader/Services/AuthenticationService.swift:82,85,461,464,471,1019` | разбор `SupabaseSessionResponse`, кодирование сессии |
| `StepsTrader/Services/AuthenticationService.swift:292,335` | удаление аватара со Storage (best-effort — ОК) |
| `StepsTrader/Services/AuthenticationService.swift:375` | удаление локального файла аватара (best-effort — ОК) |
| `StepsTrader/Services/AuthenticationService.swift:382` | загрузка локального аватара (fallback есть) |
| `StepsTrader/Services/HealthKitService.swift:332,439` | `await self.fetchSteps(...)` и чтение тестового файла |
| `StepsTrader/Services/PersistenceManager.swift:53,65` | удаление/создание директории (best-effort — ОК) |
| `StepsTrader/Services/CanvasStorageService.swift:88-89,106,189,201,224` | чтение/удаление PNG-снапшотов и JSON канвасов |
| `StepsTrader/Services/HistoryThumbnailCache.swift:97-100,176,183` | чтение/запись миниатюр |
| `StepsTrader/Services/FamilyControlsService.swift:93,96` | разбор `LiteTicketConfig` для расширения |
| `StepsTrader/Utilities/SharedKeys.swift:27-28,33-34` | `WidgetSnapshot` сохранение/чтение (важно — это виджет!) |
| `StepsTrader/Views/MeView.swift:554-555,577-578` | чтение списков транзакций для UI |
| `StepsTrader/Views/Settings/SettingsWidgetPage.swift:19` | чтение `WidgetSnapshot` для превью настроек |

## A.3. **Безвредные** — `try? await Task.sleep(...)`

Это идиома «спим, и нам всё равно если cancel». Все 30+ совпадений — норма, ничего трогать не надо.

```
StepsTraderApp.swift:146,151,155
AppModel.swift:422
SupabaseSyncService+Entries.swift:12
SupabaseSyncService+Selections.swift:13,42
SupabaseSyncService+Canvas.swift:30
SupabaseSyncService+Analytics.swift:36
SupabaseSyncService+Spent.swift:27
SupabaseSyncService+Stats.swift:32,43
SupabaseSyncService+Preferences.swift:77
SupabaseSyncService+Routines.swift:9
SupabaseSyncService+TicketGroups.swift:24
BlockingStore.swift:69,151,236
PayGateView.swift:328
GalleryView.swift:1218
OnboardingStoriesView.swift:376,393,402,406,414,422,431,439,446,453,461,464,467,476,487,490,497
PaperTicketView.swift:124
SubscriptionStore.swift:298,316
```

> **Спойлер про `OnboardingFlowView.swift:59`** — формально `try? await model.familyControlsService.requestAuthorization()` в Task без хендла. Если у пользователя iCloud-семья или родительский контроль, и запрос упал — он этого не узнает, и весь экран онбординга с настройкой шторок сломается без объяснений. Это **A.1-уровня** ошибка.

## A.4. **Спорные** — `try? FileManager.default.removeItem(at:)` и т.п.

Best-effort удаление локальных файлов. Обычно ОК, но стоит проверить, что upstream-логика не зависит от факта успешного удаления.

```
ExportCanvasWallpaperIntent.swift:186,190
PersistenceManager.swift:53,65
CanvasStorageService.swift:106,224
HistoryThumbnailCache.swift:100
AppModel+CloudKit.swift:21,48  (мёртвый код — см. §3.1)
```

---

# Приложение B — план распила `OnboardingStoriesView.swift` (1929 строк)

Файл — это **один** `struct OnboardingStoriesView: View`, внутри которого:
- 4 binding'а + 8 явных параметров + 4 callback'а
- 12 локальных `@State`
- 18 разных слайдов (по одной функции на каждый), включая 6 «v8» вариантов
- 5 разных хаптиков (`light/success/medium/heavy/rigid`)
- блок аналитики (`trackSlideViewed`, `trackSlideCompleted`)
- блок навигации (`next`, `goBack`)
- блок «иконка приложения для feed-выбора»
- блок «эффекты входа на слайд» (`triggerSlideEntryEffects` — 17 `Task.sleep`!)

## B.1. Что вынести в отдельные файлы (структурно)

```
StepsTrader/Views/Onboarding/
├── OnboardingStoriesView.swift            // ≈ 200 строк — только корневая View + body + state
├── OnboardingHaptics.swift                // ≈ 60  — 5 хаптиков как extension
├── OnboardingAnalytics.swift              // ≈ 50  — trackSlideViewed/Completed как extension на View
├── OnboardingNavigation.swift             // ≈ 80  — next(), goBack(), кнопочные хелперы
├── OnboardingEntryEffects.swift           // ≈ 200 — triggerSlideEntryEffects (17 Task.sleep)
└── Slides/
    ├── ColdOpenSlide.swift                // ≈ 30
    ├── ColorCapSlide.swift                // ≈ 110 (V1) + ColorCapV8Slide ≈ 35
    ├── SpendDemoSlide.swift               // ≈ 130
    ├── HowItWorksSlide.swift              // ≈ 70
    ├── StepsSetupSlide.swift              // ≈ 50
    ├── SleepSetupSlide.swift              // ≈ 50
    ├── TextSlide.swift                    // ≈ 30
    ├── FeedSelectionSlide.swift           // ≈ 120 (вытащить ещё AppIconView ≈ 60)
    ├── NowHereRevealSlide.swift           // ≈ 60
    ├── AppleLoginSlide.swift              // ≈ 40
    ├── WelcomeSlide.swift                 // ≈ 35 + WelcomeV8Slide ≈ 45
    ├── TheAppSlide.swift                  // ≈ 35
    ├── CanvasSleepSlide.swift             // ≈ 25
    ├── CanvasStepsSlide.swift             // ≈ 25
    ├── BalanceSlide.swift                 // ≈ 50
    ├── ResetBedtimeSlide.swift            // ≈ 30
    ├── BodyMindHeartSlide.swift           // ≈ 70
    ├── NotificationPermissionSlide.swift  // ≈ 25
    └── shared/
        ├── OnboardingAppIconView.swift     // ≈ 60
        ├── OnboardingLineText.swift        // ≈ 15
        ├── OnboardingProgressBar.swift     // ≈ 20
        └── OnboardingCanvasElements.swift  // ≈ 50
```

## B.2. Тонкие места, которые не очевидны при распиле

1. **`@State private var floaters: [OnboardingFloater] = []`** (line 43) и `triggerSlideEntryEffects` пишут в этот стейт через `withAnimation`. Если выносить эффекты в отдельный extension — он должен принимать `Binding<[OnboardingFloater]>`, а не наследовать стейт.

2. **`var model: AppModel?`** (line 31) — опционал. Половина слайдов (`feedSelectionSlide`, `appleLoginSlide`, `bodyMindHeartSlide`) предполагает `model != nil`, остальные — нет. При распиле оставь модель опциональной только в **сетап-слайдах**, а в декоративных — убери параметр вообще.

3. **`triggerSlideEntryEffects` (≈ 200 строк)** — это switch по индексу слайда с 17 `Task.sleep`. Сейчас он управляет `floaters` И визуальным `coldOpenVisible`/`tappedOrbs`/`ringProgress` И триггерит haptics И отправляет аналитику. Это 4 ответственности в одной функции. После распила — каждый слайд должен иметь свой `.task { runEntryAnimation() }` как часть собственного View, а не централизованный switch.

4. **«v8» дубли** — `colorCapSlide` + `colorCapV8Slide`, `welcomeSlide` + `welcomeV8Slide`. Скорее всего одна из веток мёртвая (старый онбординг). Перед распилом — проверить через `OnboardingCoordinator.swift:flowVersion`, какой `flowVersion` приходит в проде. Если только «v8» — снести v1-варианты целиком (-150 строк).

5. **`@State private var coldOpenVisible: Int = 0`** (line 55) — нужен только `coldOpenSlide`. После распила — переехать в локальный стейт `ColdOpenSlide`. То же самое с `tappedOrbs`/`ringProgress` (только `ColorCapSlide`), `showFeedHint` (только feed), `showOnboardingPicker` (только family controls).

## B.3. Порядок работы (чтобы не сломать)

1. Сначала вынеси чисто-декоративные слайды (cold open, theApp, canvasSleep, canvasSteps) — они без зависимостей.
2. Затем `OnboardingHaptics` и `OnboardingLineText` — они тоже без стейта.
3. Затем сетап-слайды (steps/sleep/feed) — у них bindings, но нет triggerSlideEntryEffects.
4. **После** этого распили `triggerSlideEntryEffects` по слайдам (самое опасное).
5. В самом конце — навигацию и аналитику.

После распила корневой `OnboardingStoriesView.swift` ≈ 200 строк и должен помещаться в SwiftUI Preview без подгрузки `AppModel`.

---

# Приложение C — аудит `StepsTrader/Assets.xcassets/`

Всего 116 элементов.

## C.1. Активно используются

- **`mind 1`…`mind 18`** (18 PNG) — все упомянуты в `StepsTrader/Models/ChoiceImageCatalog.swift` (`enum CanvasImageCatalog`) и используются в `CategoryDetailView`, `OnboardingStoriesView`. **Все 18 живые.**
- **`heart 1`…`heart 13`** (13 PNG) — то же. **Все 13 живые.**
- **`grain 1`** — оверлей шума, используется в 7 местах: `EnergyGradientBackground:545`, `GradientPreviewSheet:51`, `SettingsComponents:221`, `AppsPageSimplified:140`, `GalleryView:221`, `OnboardingStoriesView:281`, `ExportCanvasWallpaperIntent:154`. Живой.
- **`colors`** (95 КБ) — используется в `StepBalanceCard:66` и `UnlockWidget/UnlockWidgetViews:126,564`. Живой, но **тяжёлый** (см. §7.9 основного отчёта).
- **`AppIcon.appiconset`** — стандарт, нужен.
- **`DaylightAccent.colorset`**, **`DaylightBackground.colorset`**, **`DaylightText.colorset`** — формально нужны (цвета для светлой темы); проверь, что они правда читаются (`Color("DaylightText")` где-то в коде).

## C.2. Ничего подозрительного на удаление не найдено

Один спорный момент — `mind 15.imageset` содержит файл `mind15.png` (без пробела), а не `mind 15.png`. Это **рабочее**, потому что Xcode читает Contents.json, а не имя файла. Но грепом по `"mind 15"` файл не найдётся. Стоит переименовать на `mind 15.png` для консистентности.

## C.3. Проверить отдельно

- `Color("DaylightText")` / `UIColor(named: "DaylightText")` — поискать в коде, я не делал.
- Все `colorset` в `UnlockWidget/Assets.xcassets/` (`AccentColor`, `WidgetBackground`) — обычно генерируются Xcode-шаблоном, проверить, что не дублируются с основной палитрой.

## C.4. Неиспользуемые ассеты в виджете — нет

Все 12 PNG (`facebook`, `instagram`, …) в `UnlockWidget/Assets.xcassets/` мапятся через `templateAppImageName` в `UnlockWidget/UnlockWidgetViews.swift`. Удалять нечего.

## C.5. Нейминг-непоследовательность

Файл называется `StepsTrader/Models/ChoiceImageCatalog.swift`, а **тип внутри** — `enum CanvasImageCatalog`. `Choice` (старое слово из спеки) vs `Canvas` (новое слово). PASS 2: переименовать файл в `CanvasImageCatalog.swift`. И заодно `StepsTrader/Assets.xcassets/CHOICE_IMAGES_README.md` → `CANVAS_IMAGES_README.md`.

---

# Приложение D — что осталось проверить руками

1. `git ls-files Config/Secrets.xcconfig` — если файл в git-истории, выкорчевать через `git filter-repo` и **пересоздать все ключи** (Supabase anon key, RevenueCat API key).
2. В `App Store Connect` → Steps4 → Capabilities проверить, что iCloud (CloudKit) **снят**, а не просто закомментирован.
3. В RevenueCat-дашборде сверить:
   - entitlement называется ровно `pro`
   - продукты `pro_monthly`, `pro_annual`, `pro_lifetime` все привязаны к этому entitlement
4. Запустить Instruments → Time Profiler на `GenerativeCanvasView` с открытой галереей в течение 5 минут, проверить, что `clusterCache` не растёт линейно.
5. На реальном устройстве установить TestFlight-сборку и **перезагрузить телефон** — проверить, что виджет восстанавливается из `WidgetDataFile` без перезапуска приложения.
6. На устройстве с включённым `Reduce Motion` пройти онбординг — проверить, что `triggerSlideEntryEffects` не зависает.
