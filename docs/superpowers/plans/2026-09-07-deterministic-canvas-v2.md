# Deterministic Canvas V2 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking. Work inline unless the user separately requests delegation.

**Goal:** Встроить пять утверждённых сценариев и библиотеку из 12 материалов в приложение через сохраняемый рецепт дня, с устойчивым ростом, историей и единым экспортом.

**Architecture:** Чистый Swift-планировщик создаёт Codable-рецепт и окончательные параметры принятых событий. Адаптер передаёт их существующему Metal-рендереру, обходя генераторы V1. Версия рецепта определяет путь отрисовки; состояние сна, шагов и трат передаётся отдельно.

**Tech Stack:** Существующие Swift/SwiftUI, Codable, Metal, XCTest, JSON-синхронизация DayCanvas; без новых графических зависимостей.

**Spec:** `docs/superpowers/specs/2026-09-07-deterministic-canvas-v2-design.md`

## Global Constraints

- Все продуктовые ограничения — из связанной spec; не изменять библиотеку или число сценариев без отдельного решения пользователя.
- Максимум 10 активных объектов; 5 сценариев; 12 материалов; 37 × 12 контрольных сочетаний.
- Фигуры aspect = 1. Координаты композиции нормализованы относительно art viewport 300:440, радиусы относительно короткой стороны.
- Каноническое время статичного экспорта: 4 секунды.
- Не менять deployment targets, пакеты, музыку, экономику или каталог happenings ради этой работы.
- В рабочем дереве уже есть изменения Metal, палитры, UI и тестов. При исполнении сохранить diff-базу и включить актуальные согласованные изменения; не делать reset и не переносить только HEAD, теряя локальный материал.
- Сейчас задача — планирование. Приведённые команды тестирования/миграции относятся к будущему исполнению и ещё не запускались.
- Каждый этап заканчивается проверяемым результатом и отдельным commit только своих файлов. Не коммитить чужой накопленный diff.

## Проверенный исходный код

| Файл | Роль и изменение |
|---|---|
| `StepsTrader/Models/DayCanvas.swift` | Добавить optional версионированный рецепт; старое декодирование сохранить |
| `StepsTrader/Experiments/DayObjects/EditorialCanvasInputFactory.swift` | Передать сохранённый V2 и отдельное состояние отображения |
| `StepsTrader/Experiments/DayObjects/DayObjectScene.swift` | Ранний маршрут V2; V1 planners не запускать для V2 |
| `StepsTrader/Experiments/DayObjects/DayObjectRenderFrame.swift` | Паковать готовую геометрию/материалы V2 |
| `StepsTrader/Experiments/DayObjects/DayObjectsRenderer.swift` | Использовать существующие pipeline, добавить нужные passes и cache |
| `StepsTrader/Metal/DayObjectsActorShader.metal` | Сохранить V1, добавить версионированный dispatch геометрии/материалов V2 |
| `StepsTrader/Views/Gallery/GalleryNotifications.swift` | Атомарное принятие/удаление объекта вместе с рецептом |
| `StepsTrader/Views/GalleryView.swift` | Создание дня, hydration, merge, сохранение пустого V2; не растить planner внутри View |
| `StepsTrader/Models/HappeningShapeAssignment.swift` | Согласовать preview выбранной фигуры с фактически добавленной |
| `StepsTrader/Experiments/DayObjects/HappeningPaletteRenderFrame.swift` | Preview из того же candidate spec; сохранить отсутствие глитча в chooser |
| `StepsTrader/Services/CanvasStorageService.swift` | Рецепт и снимки; стабильная идентичность кэша |
| `StepsTrader/Services/SupabaseSyncService+Canvas.swift` | Версионное слияние и подтверждение записи |
| `StepsTrader/Experiments/DayObjects/DayObjectsImageRenderer.swift` | Общий V2 input для offscreen |
| `StepsTrader/Intents/ExportCanvasWallpaperIntent.swift` | Проверить end-to-end путь wallpaper |
| `StepsTrader/Views/Components/DayCanvasArtworkView.swift` | Диспетчер маршрута; сохранить исторический V1 |

Новые независимые единицы разместить в `StepsTrader/Experiments/DayObjects/RecipeV2/`: `CanvasRecipeV2.swift`, `CanvasRecipeCatalogV1.swift`, `CanvasRecipeSeed.swift`, `CanvasRecipeScheduler.swift`, `CanvasRecipeIdentity.swift`, `CanvasGrowthPlanner.swift`, `CanvasRecipeMutation.swift`, `CanvasRecipeMerge.swift`, `CanvasRecipeRendererBridge.swift`, `CanvasMaterialPackerV2.swift`, `CanvasOverlapPolicyV2.swift`, `CanvasRecipeFeaturePolicy.swift`, `CanvasRecipeLabView.swift`. Это отдельные обязанности, а не копия всего старого движка.

## Общие интерфейсы

Контракты для реализации; типы объявляются на этапе 1 и затем используются без переименования:

```swift
enum CanvasScenarioV2: String, Codable, CaseIterable {
    case air, proximity, fragment, equilibrium, flow
}
enum CanvasMaterialIDV1: String, Codable, CaseIterable {
    case solid, sideLight, colorFlow, transparentLayers, outline
    case directionalBlur, radialTwo, radialThree
    case proceduralLight, proceduralFlow, proceduralGesture, glowingOutline
}
enum CanvasShapeIDV1: String, Codable, CaseIterable {
    case circle, superellipse, softStar, triangle, hexagon
}
enum CanvasOverlapIDV1: String, Codable, CaseIterable {
    case normal, glowingSeam, inversion, cutout, transparentMix
}
// CanvasRecipeV2: Codable + Equatable, содержит поля раздела «Что сохраняется» spec.
// CanvasActorSpecV2: Codable + Equatable, окончательные position/scale/turn,
// shape parameters, material parameters, motion, slotID, eventID, happeningID.
// CanvasRecipeOperation: Codable + Equatable; add/update/remove, logicalCounter,
// writerID, operationID и соответствующий actor spec / tombstone.
// CanvasRecipeSeed: fixed hash + domain separation; hex roundtrip UInt64.
// CanvasRecipeCatalogV1: стабильные ID и диапазоны каталога; никакого allCases-index storage.
// CanvasRecipeRenderState: elapsedTime, stepsProgress, sleepProgress,
// spentProgress, reduceMotion, viewport, presentationMode.
// CanvasRecipeMergeResult: merged(CanvasRecipeV2) или versionConflict(local, remote).

CanvasRecipeSeed.hex(_ seed: UInt64) -> String
CanvasRecipeSeed.decodeHex(_ text: String) throws -> UInt64
CanvasOverlapPolicyV2.resolve(_ a: CanvasMaterialIDV1, _ b: CanvasMaterialIDV1,
    requested: CanvasOverlapIDV1) -> CanvasOverlapIDV1
CanvasGrowthPlanner.make(daySeed: UInt64, scenario: CanvasScenarioV2) -> CanvasRecipeV2
CanvasGrowthPlanner.candidate(recipe: CanvasRecipeV2, eventID: String,
    happeningID: String, variant: Int) throws -> CanvasActorSpecV2
CanvasRecipeMutation.apply(_ operation: CanvasRecipeOperation,
    to recipe: CanvasRecipeV2) throws -> CanvasRecipeV2
CanvasRecipeMerge.merge(_ a: CanvasRecipeV2, _ b: CanvasRecipeV2) -> CanvasRecipeMergeResult
CanvasRecipeRendererBridge.frame(recipe: CanvasRecipeV2,
    state: CanvasRecipeRenderState) throws -> DayObjectRenderFrame
```

Схема рецепта: `schemaVersion: 2`, `generatorVersion: "2.0"`, `catalogVersion: "atlas-20260907-v1"`, `dayKey`, `daySeedHex`, `personalSeedHex`, `scenario`, `scenarioParameters`, `palette`, `materialPolicy`, `slots`, `actors`, `tombstones`, `revision`. Позиции/цвета кодировать явными числовыми компонентами, не платформенными объектами. Неизвестные версии возвращают отдельный unsupported-load result с исходными байтами для сохранности.

## Проверки и команды

Новые тесты находятся в `Steps4Tests`, target — `Steps4Tests`, scheme — `Steps4`. В начале исполнения выбрать доступный simulator через `xcrun simctl list devices available` и сохранить его UDID в `CANVAS_V2_SIM_ID`; не использовать старый UUID из истории диалога. Пример запуска группы:

```sh
xcodebuild test -project Steps4.xcodeproj -scheme Steps4 \
  -destination "platform=iOS Simulator,id=$CANVAS_V2_SIM_ID" \
  -derivedDataPath /tmp/nowhere-canvas-v2-dd \
  -only-testing:Steps4Tests/CanvasRecipeV2Tests
```

Для остальных групп заменять только имя класса после `Steps4Tests/`. До каждой реализации написать указанные проверки и увидеть ожидаемый fail, затем реализовать и получить pass. Не повторять весь тяжёлый набор после изменения только документации. Подключение новых файлов в Xcode проверить по реальным target membership; сейчас часть core-файлов подключена явными ссылками, поэтому автоматическое обнаружение не предполагать.

## Этап 1. Зафиксировать каталог и формат рецепта

**Файлы:** новые `RecipeV2/CanvasRecipeV2.swift`, `CanvasRecipeCatalogV1.swift`, `CanvasRecipeSeed.swift`; `Steps4Tests/CanvasRecipeV2Tests.swift`; `Steps4Tests/Fixtures/CanvasRecipeV2/` (JSON контрольных рецептов, по сценарию).

**Consumes:** утверждённый commit сайта и spec. **Produces:** Codable-типы, стабильные ID, domain-separated seed, каталог и fixtures.

- [ ] Сохранить в fixture manifest commit сайта, все 37 строк, 12 колонок, палитры и диапазоны параметров. Пометить, какие образцы нативные, какие браузерные.
- [ ] Написать тесты числа/ID материалов, UInt64 hex roundtrip, независимости доменов, JSON roundtrip и отказа на неизвестной версии.
- [ ] Запустить `CanvasRecipeV2Tests`, затем реализовать типы и фиксированный hash с test vectors. Отказ на NaN/Infinity, отрицательном размере и повторяющихся slotID/eventID — явная ошибка загрузки, не генерация замены.
- [ ] Проверить тесты и fixtures, commit своих файлов.

```swift
func testSeedHexKeepsAllBits() throws {
    let seed = UInt64.max
    XCTAssertEqual(try CanvasRecipeSeed.decodeHex(CanvasRecipeSeed.hex(seed)), seed)
}
func testWholeRecipeRoundTrip() throws {
    let recipe = CanvasGrowthPlanner.make(daySeed: 42, scenario: .flow)
    let data = try JSONEncoder().encode(recipe)
    XCTAssertEqual(try JSONDecoder().decode(CanvasRecipeV2.self, from: data), recipe)
}
```

Roundtrip тест с planner включить на этапе 2; на этапе 1 выполнить тот же roundtrip на зафиксированной flow JSON fixture.

**Готово, когда:** рецепт можно сохранить и прочитать без потери значащих параметров, полный каталог имеет устойчивые имена.

## Этап 2. Сквозной локальный Поток

**Файлы:** новые `RecipeV2/CanvasGrowthPlanner.swift`, `CanvasRecipeRendererBridge.swift`, `CanvasRecipeLabView.swift`; modify `DayObjectScene.swift`, `DayObjectRenderFrame.swift`, `DayObjectsLabView.swift`; tests `Steps4Tests/CanvasGrowthPlannerTests.swift`, `CanvasRecipeRendererBridgeTests.swift`.

**Consumes:** типы этапа 1. **Produces:** recipe → Metal preview → offscreen для Потока с простыми solid/outline; без production-флага.

- [ ] Написать проверки чистоты planner, 10 слотов и одинаковых первых трёх объектов при показе 3/10, одинакового frame при том же state.
- [ ] Перенести формулу Потока из сайта: дуга/S, времена `[.38,.50,.63,.25,.76,.13,.87,.025,.975,.44]`, рост в обе стороны, scale taper и rotation по касательной. Держать параметры в рецепте, не вычислять их из текущего count.
- [ ] Добавить V2 bridge и раннюю ветку в scene/render-frame; V1 не пересчитывать и не менять его Metal dispatch. Сделать debug lab entry и ряд 1/3/5/10.
- [ ] Получить статичный снимок тем же renderer при t=4. Проверить на одном iPhone физический масштаб и натуральные пропорции.
- [ ] Прогнать planner/bridge тесты и существующие `DayObjectSceneTests`, commit.

```swift
func testFlowDoesNotDependOnPresentationCount() {
    let a = CanvasGrowthPlanner.make(daySeed: 42, scenario: .flow)
    let b = CanvasGrowthPlanner.make(daySeed: 42, scenario: .flow)
    XCTAssertEqual(Array(a.slots.prefix(3)), Array(b.slots.prefix(10).prefix(3)))
    XCTAssertEqual(a.slots.count, 10)
}
```

Дополнительно проверить неизменность actor spec через последовательные `candidate` + `CanvasRecipeMutation.apply` на этапе 3: один тест слотов сам по себе не доказывает устойчивость роста.

**Готово, когда:** Поток виден в приложении и экспорте; это первая пользовательская визуальная проверка, не готовность полного движка.

## Этап 3. Транзакции событий, пустой день и chooser

**Файлы:** новые `RecipeV2/CanvasRecipeMutation.swift`, `Steps4Tests/CanvasRecipeMutationTests.swift`; modify `Models/DayCanvas.swift`, `GalleryView.swift`, `Gallery/GalleryNotifications.swift`, `Models/HappeningShapeAssignment.swift`, `HappeningPaletteRenderFrame.swift`, `Services/CanvasStorageService.swift`; tests `CanvasPersistenceRegressionTests`, `HappeningAdditionsTests`, `HappeningPaletteRenderFrameTests`.

**Consumes:** стабильные слоты/типы. **Produces:** сохранённые actor specs и tombstones; одинаковый candidate в chooser и принятом событии.

- [ ] Написать проверки add→persist→reload; delete middle→unchanged survivors; delete last→persist empty recipe→reload; failed persist→unchanged canvas/model; re-add при свободном/занятом прежнем слоте; 10 active capacity.
- [ ] Перед показом preview создать и удерживать candidate eventID. `candidate(recipe:eventID:happeningID:variant:)` вычисляет форму/материал в рамках роли; на commit использовать тот же spec, не второй random.
- [ ] В `CanvasHappeningSpawnTransaction` и removal transaction обновлять recipe и elements в одной durable-записи до изменения domain entry. Номер операции увеличивать только в принятой транзакции. Вариант цвета/поворота хранить в actor overrides.
- [ ] Для V2 сохранять пустой DayCanvas. Путь V1 оставить совместимым. Не использовать `elements.count` как идентификатор следующего объекта и не удалять tombstones после перезапуска.
- [ ] Прогнать перечисленные persistence/chooser тесты; отдельно проверить скрытый chooser без glitch overlay, commit.

Порядок принятия:

```text
preflight current day + available happening + available slot
candidate (cached from preview) → apply add operation → encode full DayCanvas
durable save succeeds → model.addHappening(eventID) → schedule sync/snapshot
save fails → retain original document and preview; no consumed slot or happening
```

**Готово, когда:** можно добавлять/удалять и перезапускать приложение, сохраняя тот же локальный день.

## Этап 4. Остальные сценарии и расписание разнообразия

**Файлы:** новые `RecipeV2/CanvasRecipeScheduler.swift`, `CanvasRecipeIdentity.swift`, `Steps4Tests/CanvasRecipeSchedulerTests.swift`; modify `CanvasGrowthPlanner.swift`, `CanvasRecipeLabView.swift`, `CanvasGrowthPlannerTests.swift`.

**Consumes:** рецепт и операции. **Produces:** все пять сценариев, personal/day schedule и совместимые material policies.

- [ ] Написать проверки детерминированного выбора на 365 датах; все 5 сценариев и все 12 ведущих материалов достижимы; соседние блоки не повторяют крайний ID; открытие пропущенных дней не меняет расписание.
- [ ] Перенести четыре остальных сценария с сайта и задать каждому собственную роль/связь слотов. Не использовать роль «противовес» автоматически для третьего объекта Потока.
- [ ] Добавить `CanvasRecipeIdentity`: фиксированный hash канонического UUID аккаунта, полученного из существующего AuthenticationService; у гостя — hash один раз сохранённого локального UUID. Не использовать access token или display name. Выбранный рецепт сохранять до первой фигуры. Вход и изменение настроек применяются к будущим дням.
- [ ] Выбирать до трёх материалов и два семейства в соответствии с ролью. Размеры и позиции допускать в утверждённых диапазонах; до принятия проверять видимость и запланированные пересечения по реальному контуру, с максимумом 16 детерминированных попыток и последним проверенным шаблоном как fallback.
- [ ] Сравнить 30 seeds × 5 сценариев × 1/3/5/10 в lab. Для художественной оценки сохранять контактные листы; числа уникальности не заменяют просмотр.
- [ ] Прогнать scheduler/planner/mutation тесты, commit.

```swift
func testEveryMaterialHasAStableID() {
    let ids = CanvasMaterialIDV1.allCases.map(\.rawValue)
    XCTAssertEqual(ids.count, 12)
    XCTAssertEqual(Set(ids).count, 12)
}
```

**Готово, когда:** сценарии различаются конструкцией, а random не застревает на нескольких материалах.

## Этап 5. Вся библиотека в Metal

**Файлы:** новые `RecipeV2/CanvasMaterialPackerV2.swift`, `Metal/CanvasRecipeMaterialsV2.h`, `Steps4Tests/CanvasMaterialV2Tests.swift`, `CanvasMaterialV2ImageTests.swift`; modify `DayObjectsActorShader.metal`, `DayObjectRenderFrame.swift`, `DayObjectsRenderer.swift`, `CanvasRecipeLabView.swift`.

**Consumes:** shape/material descriptors, визуальный manifest. **Produces:** все 12 нативных материалов и 5 семейств с параметрами из рецепта.

- [ ] Написать ABI/packing тесты и изображения прозрачного фона: circle/superellipse/star/triangle/hexagon, minimum/maximum parameters. Не использовать enum rawValue каталога как старый GPU family ID без явного mapping.
- [ ] Ввести отдельный V2 shader dispatch с зафиксированной версией. Сначала перенести solid, side light, radialTwo/Three, outline; затем colorFlow/layers; затем proceduralLight/Flow/Gesture/glow; затем directionalBlur.
- [ ] Для размытия сохранить локальную ось, выбранную сторону/луч, premultiplied-alpha и достаточный quad/filter extent. Никаких полос из дискретных зон. Global sleep blur — отдельный этап.
- [ ] Собирать 444 native образца по fixture manifest. Сравнивать с эталоном на одинаковом цветовом фоне, отдельно RGBA/alpha, сглаживание контуров, отсутствие обрезанного свечения/blur.
- [ ] Прогнать V2 packing/image tests и прежние `DayObjectRenderFrameTests`, `DayObjectPaletteTests`; собрать на Metal-capable simulator и проверить на iPhone, commit.

Контракт формулы направленного размытия:

```text
q = inverse(actorTransform) * pixelPosition
d = dot(q, localBlurAxis)
u = clamp((focusedBoundary - d) / (focusedBoundary - farBoundary), 0, 1)
sigma = maxSigma * smoothGrowth(u)       // sharp focus, wide dissolved far side
sample premultiplied color and alpha together; rotate whole result with actor
```

**Готово, когда:** каждый материал действительно работает в Metal, а не подменён ближайшим старым эффектом.

## Этап 6. Перекрытия, фокус, анимация и стоимость кадра

**Файлы:** новые `RecipeV2/CanvasOverlapPolicyV2.swift`, `Metal/CanvasRecipeOverlapV2.metal`, `Steps4Tests/CanvasOverlapV2Tests.swift`; modify renderer/frame, `CanvasRecipeRendererBridge.swift`, `CanvasRecipeLabView.swift`; tests `CanvasRenderBudgetTests`, `HappeningPaletteRenderFrameTests`.

**Consumes:** настоящие покрытия/альфа материалов. **Produces:** пять эффектов пересечения, ограниченная анимация, читаемость на low focus.

- [ ] Написать pair-policy tests: blur+blur всегда normal для любого requested mode; outline interior не маскирует фон; triple overlap не применяет inversion дважды; порядок слоёв стабилен.
- [ ] Строить pair mask из покрытий нужных фигур. Зафиксировать порядок: базовые слои → pair effects с детерминированным приоритетом пары → общий фокус → существующий digital-impact путь с проверкой читаемости. При несовместимости действующего post-порядка выделить материал blur отдельно, не удваивать global blur.
- [ ] Ограничить амплитуду движения ролью и свободными областями. Экспорт t=4, Reduced Motion нейтрален. Chooser исключён из canvas glitch pass.
- [ ] Кэшировать статичные дорогие материал/blur маски по recipe fingerprint и масштабу; инвалидировать по реально изменённым параметрам. Не создавать Metal pipelines/textures и не запускать planner каждый кадр.
- [ ] На iPhone измерить CPU/GPU frame time, память и время offscreen на 10 крупных overlapping blur/glow actors, минимум 60 секунд после прогрева. Проверить фактический целевой FPS; budgets p95 ≤ 33.3 ms для 30 FPS canvas и ≤ 16.7 ms для 60 FPS chooser transition. Если не проходит, оптимизировать и повторить этот корпус.
- [ ] Прогнать overlap/render-budget/chooser проверки и сохранить профили/снимки, commit.

```swift
func testTwoBlursNeverUseIntersectionEffects() {
    for mode in CanvasOverlapIDV1.allCases {
        XCTAssertEqual(CanvasOverlapPolicyV2.resolve(
            .directionalBlur, .directionalBlur, requested: mode), .normal)
    }
}
```

**Готово, когда:** эффекты не уничтожают различимость объектов и укладываются в измеренный бюджет.

## Этап 7. Синхронизация и защита истории

**Файлы:** новые `RecipeV2/CanvasRecipeMerge.swift`, `Steps4Tests/CanvasRecipeMergeTests.swift`, `CanvasRecipeSyncTests.swift`; modify `GalleryView.swift`, `SupabaseSyncService+Canvas.swift`, `SupabaseSyncDTOs.swift`; миграция в `supabase/migrations/`, созданная CLI с именем `canvas_recipe_v2_revision_guard` (не выдумывать timestamp заранее).

**Consumes:** операции/ревизии этапа 3. **Produces:** согласованное слияние и защита V2 от stale/downgrade записей.

- [ ] Написать тесты `merge(a,b)==merge(b,a)`, `merge(a,a)==a`; tombstone против старого add; два офлайн add одного slot; разные catalog versions; сохранение всех событий при переполнении; unknown schema не перезаписывает raw JSON.
- [ ] Реализовать порядок конфликтов из spec и вынести V2 merge из View. Не менять пользовательский порядок V1 в рамках этой задачи.
- [ ] На dev проверить текущие deployed guards и JSON roundtrip. Перед implementation Supabase сверить актуальную документацию согласно skill. Простое добавление поля в JSON не требует новой таблицы, но защита конкурентной записи требует протокола ревизий.
- [ ] Реализовать атомарный compare-and-swap существующего day-canvas: клиент передаёт expected revision, сервер блокирует строку и возвращает accepted+newRevision либо conflict+current document. Клиент merge/retry сохраняет исходные operationID, не создаёт повторное событие. Сервер запрещает V1 replacement поверх V2 даже с более новым временем.
- [ ] Сохранить авторизацию через auth.uid()/существующие RLS; не расширять доступ. Создать миграцию через CLI по skill; проверить два конкурентных клиента и старый payload на dev. Продакшен-миграция — отдельный этап rollout после проверки, не действие этого планирования.
- [ ] Прогнать merge/sync/persistence tests. Пока серверный guard не подтверждён, production V2 выключен. Commit.

```text
read existing row under lock
if stored recipe V2 and incoming removes/downgrades recipe: reject
if stored revision != expected: return conflict + stored document
otherwise persist merged document with revision + 1; return accepted
```

**Готово, когда:** две стороны сходятся к одному документу, старый клиент не стирает рецепт и удаления.

## Этап 8. Единый экспорт и включение для новых дней

**Файлы:** новый `RecipeV2/CanvasRecipeFeaturePolicy.swift`, `Steps4Tests/CanvasRecipeRolloutTests.swift`, `CanvasRecipeExportTests.swift`; modify `EditorialCanvasInputFactory.swift`, `DayCanvasArtworkView.swift`, `CanvasStorageService.swift`, `DayObjectsImageRenderer.swift`, `ExportCanvasWallpaperIntent.swift`, `GalleryView.swift`, `Views/Settings/TodayCanvasBackground.swift`; tests `DayCanvasArtworkRoutingTests`, `TodayCanvasBackgroundTests`.

**Consumes:** полностью проверенный V2 renderer/storage/sync. **Produces:** V2 по умолчанию для новых дней с рабочим откатом создания новых рецептов.

- [ ] Написать маршрутизацию: исторический nil recipe→V1; известный V2→V2; неизвестный→read-only fallback; выключенный флаг не ломает существующий V2. Начатый V1-день остаётся V1.
- [ ] Пропустить сохранённый рецепт через все входы: основной экран, просмотр дня, фон настроек, thumbnail, widget, wallpaper. Cache key содержит versions, recipe content fingerprint, render metrics, viewport и canonical time.
- [ ] Сверить экран и offscreen при одинаковых state/time/viewport. При другом размере проверить fit/crop, естественные пропорции и наличие blur/glow за пределами body bounds.
- [ ] Прогнать финальный корпус: пять сценариев × counts 0/1/3/5/10; low/high focus; spent 0/малое/высокое; delete/re-add; relaunch; sync; background/foreground; Reduced Motion; chooser; export. Включить прежние regression suites и короткий smoke звука.
- [ ] Показать пользователю сборку на iPhone и контактный лист пяти сценариев. После визуальной приёмки и dev-sync проверки включить для новых дней. Явное преобразование старых дней не входит в rollout.
- [ ] Сохранить результаты и инструкцию отката, commit. Проверить, что toggle меняет только создание будущих дней.

**Готово, когда:** пользователь получает один и тот же день на всех поверхностях и после восстановления данных.

## Последовательность и контрольные точки

`1 → 2 → 3 → 4 → 5 → 6 → 7 → 8`.

- После 2–3: первый локальный сквозной Поток, оценка реальной трудоёмкости остальных этапов.
- После 4–6: пять сценариев и полная библиотека на iPhone, художественная приёмка и профиль производительности.
- После 7–8: синхронизация, история, экспорт и включение для новых дней.
- Одобрение этого плана не означает, что проверки выполнены. Не объявлять V2 готовым после первого красивого скриншота.

## Проверка полноты плана

| Требование | Этап |
|---|---|
| Пять сценариев, различимые на ранних событиях | 2, 4 |
| Полная текущая библиотека и прозрачность | 1, 5 |
| Постоянные слоты, удаление/повторное добавление, пустой день | 3 |
| Preview совпадает с добавлением | 3 |
| Пересечения и исключение blur+blur | 6 |
| Глитч при низком фокусе, отсутствие в chooser | 6 |
| Персональность и разнообразие между днями | 4 |
| История, версии и синхронизация | 1, 7, 8 |
| Wallpaper/миниатюры/виджет | 2, 8 |
| Производительность на iPhone | 6, 8 |

Следующий исполнимый шаг — этап 1, затем локальный Поток. В этом документе нет разрешения на самостоятельную публикацию production-сборки или миграцию пользовательской истории.
