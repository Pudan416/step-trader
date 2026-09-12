# Current integration: план проверки и стабилизации

> **For agentic workers:** Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Проверить актуальный PR целиком и исправить подтверждённые ошибки, начиная с Canvas + звук + Smudge и карусели Me, сохранив визуальное и звуковое поведение.

**Architecture:** Выполнять работу небольшими проверяемыми исправлениями: воспроизведение → измерение → гипотеза → исправление → тот же сценарий после изменения. Разделять вычисления сцены, GPU-отрисовку, подготовку аудио, realtime audio и обновление SwiftUI. Не переписывать подсистемы без доказанной необходимости.

**Tech Stack:** Swift/SwiftUI, UIKit/MetalKit/Metal, AVAudioEngine и существующий audio runtime, HealthKit, Screen Time, Supabase, XCTest/XCUITest, Instruments.

**Spec:** Запрос пользователя от 2026-09-06: приоритет Canvas со звуком, Smudge, карусель страницы Me; затем полная проверка PR и устранение остальных багов. Предыдущее ревью: `/Users/kosta/.codex/reviews/pr21-2026-09-06/review.md`, только как список кандидатов для повторной проверки.

## Границы и актуальная версия

- На момент составления плана PR №21 и local current-integration имеют HEAD `868bf2b36ce8e24b08797466f68da642fe9bb48d`.
- Прежний отчёт и результат 1005 passed относятся к `8fc67d3`, не подтверждают качество нового HEAD. Day Objects теперь интегрирован в production Canvas; прежнее ограничение «только Lab» нельзя переносить автоматически.
- В current-integration есть незакоммиченные изменения renderer/palette/tests/localization и отдельная device performance scheme. Сначала сохранить и определить их состав; не отбрасывать, не включать автоматически в коммиты исправлений.
- Под каруселью принимается карусель постеров Me. Если воспроизведение указывает на другой экран, уточнить маршрут и расширить матрицу.
- Сохранить характер Smudge, качество изображения и музыкальное поведение. Снижение FPS, разрешения, числа голосов или отключение эффекта не считается исправлением без оценки видимой/слышимой потери качества.
- Не менять экономику энергии, семантику купленного времени или исторического рисунка под видом оптимизации.
- Не публиковать изменения в main и не применять production-миграции в рамках диагностики. Готовить проверяемые коммиты в integration; обновление PR — отдельный завершающий шаг после проверок.

## 0. Зафиксировать проверяемый исходный код

- [ ] Перечитать HEAD/base PR через GitHub и сравнить с локальной веткой; сформировать перечень файлов по подсистемам.
- [ ] Сохранить tracked diff и необходимые untracked-файлы в отдельный snapshot с manifest/hash. Не переключать грязный checkout и не выполнять reset/clean.
- [ ] Проверить изменения, появившиеся во время работы, перед каждым коммитом. Выделить собственные исправления из пользовательского WIP.
- [ ] Подготовить изолированную рабочую копию выбранного snapshot. Зафиксировать exact SHA + WIP manifest, Xcode, build configuration, модель/ОС устройства.
- [ ] Создать журнал `artifacts/current-integration-stabilization/findings.md`: ID, сценарий, версия, доказательство, причина, приоритет, fix commit, проверка после исправления, остаточные ограничения.

**Выход:** одна воспроизводимая версия и перечень изменений, которые реально попадут в PR. Повреждённую Git-ссылку из предыдущего ревью диагностировать отдельно, с сохранением содержимого; не смешивать ремонт repository metadata с продуктовыми коммитами.

## 1. Воспроизведение и исходные замеры трёх приоритетных проблем

**Точки входа:** `StepsTrader/Views/GalleryView.swift`, `Views/Components/DayCanvasArtworkView.swift`, `Utilities/RenderingActivity.swift`, `Views/MeView.swift`, `Views/MeViewSupport.swift`; существующая локальная `Steps4DevicePerformance.xcscheme` после проверки её содержимого.

- [ ] Собрать Debug для диагностики и оптимизированную сборку для устройства. В performance-сборке сохранить символы и выключить диагностические настройки, существенно искажающие скорость.
- [ ] Использовать фиксированный canvas/day seed с 0, 5 и 10 happenings. Для каждого записать размеры drawable и фактическую частоту renderer.
- [ ] Прогнать четыре комбинации: звук OFF / Smudge OFF; ON/OFF; OFF/ON; ON/ON. Отдельно холодный запуск, повторное включение, drag/multitouch, fullscreen, remix и смена вкладок.
- [ ] Для Me: первое открытие, 20 свайпов туда-обратно, быстрое направление назад, переход через календарь, возврат из background, share выбранного дня; повторить online/offline и с задержанными Health/remote-ответами.
- [ ] Записать Time Profiler + Hangs/Animation Hitches; GPU trace и Allocations отдельными прогонами, чтобы не суммировать overhead инструментов. Для audio — время start-to-first-audio, загрузку/декодирование банка, callback overruns и слышимые разрывы.
- [ ] Снять не менее трёх одинаковых прогонов каждой основной комбинации без параллельной компиляции. Сравнивать медиану и p95/p99, отдельно cold/warm.

**Артефакт:** `artifacts/current-integration-stabilization/baseline.md` и device traces: CPU/GPU frame time, hitch count/duration, peak/steady memory, число renderer/engine instances, latency звука и реакция на касание. Визуальные записи и аудиопрослушивание дополняют численные метрики.

**Если устройство недоступно:** продолжить код, симулятор и изолированные benchmark, но оставить real-device gate незавершённым. Не выдавать simulator/Mac timing за доказанную плавность iPhone.

## 2. Canvas и звук: запуск, взаимодействие, остановка

**Файлы:** `GalleryView.swift`; `Experiments/DayObjects/Sound/Lab/DayObjectsMusicLabController.swift`; `Sound/Playback/DayObjectsMusicPlaybackEngine.swift`, `DayObjectsTransport.swift`, `DayObjectsBusMeter.swift`; конкретные pool/bank/runtime implementations, найденные по trace.

**Тесты:** `Steps4Tests/DayObjectsMusicPlaybackEngineTests.swift`, `DayObjectsMusicLabControllerTests.swift`, `DayObjectsTransportTests.swift`, `RenderingActivityTests.swift`, `SmoothActivationTests.swift`.

- [ ] Проследить кнопку Sound → controller → prepare samples/runtime → AVAudioSession → engine start → первый audio callback → UI state. Разметить границы signpost; не логировать из realtime callback.
- [ ] Проверить синхронную подготовку на MainActor, повторную загрузку банков, перестройку audio graph и planner после каждого обновления view/жеста. `async`-сигнатура сама по себе не доказывает отсутствие блокировки UI.
- [ ] Проверить realtime path на locks, allocation, file I/O, logging и вызовы UI; отдельно выяснить частоту meter/pulse публикаций в SwiftUI и связанное пересоздание сцены.
- [ ] Зафиксировать regression для найденной причины: управляемая задержка preparation; ON→OFF до завершения start; несколько быстрых ON/OFF; уход с экрана во время start; interruption/route change. Проверять число start/stop, отсутствие «воскресшего» engine и released resources, а не только значение soundState.
- [ ] Исправить доказанную причину: вынести допустимую подготовку с MainActor, переиспользовать подготовленные ресурсы, ограничить UI-публикации или исправить cancellation/lifecycle — только те изменения, которые подтверждаются trace.
- [ ] Повторить четыре комбинации baseline; отдельно 10 минут совместной работы аудио и Canvas, затем 20 циклов ON/OFF и ухода/возврата.

**Готово:** нет зависания на включении, двойного engine/transport, висящих нот после остановки или воспроизводимых underruns; после нескольких циклов нет монотонного роста ресурсов. Сравнение latency/hitches приложено к коммиту.

## 3. Smudge: первый touch и совместная работа с музыкой

**Файлы:** `Views/Components/SmudgeCanvasView.swift`, `Metal/MetalSmudgeRenderer.swift`, `Metal/SmudgeShaders.metal`, `Views/Components/DayCanvasArtworkView.swift`, `Experiments/DayObjects/DayObjectsRenderer.swift`, `GalleryView.swift`.

**Тесты:** существующие `SmoothActivationTests.swift`, `RenderingActivityTests.swift`; создать `Steps4Tests/SmudgeLifecycleTests.swift` для найденных жизненных циклов и добавить в test target.

- [ ] Разделить стоимость touch handling, snapshotCanvas/ImageRenderer, загрузки исходной текстуры, compute/render pass и ожидания GPU.
- [ ] Проверить вызов `waitUntilCompleted()` в MetalSmudgeRenderer в контексте реального caller/thread. Это подозрительная точка, не установленная причина до trace.
- [ ] Проверить, создаются ли textures/pipelines/buffers при каждом touch или updateUIView; когда меняется snapshot identity; обновляется ли underlying Canvas одновременно со Smudge; корректна ли пауза скрытых MTKView.
- [ ] Воспроизвести первый touch, drag 30 секунд, multitouch, rotation/fullscreen resize, переключение стиля, прекращение касания, уход с экрана и звук ON/OFF во время drag.
- [ ] Для доказанного дефекта добавить тест владения/инвалидации ресурса или состояния touch/cancel. При оптимизации snapshot проверить, что новая фигура/цвет/размер действительно инвалидирует кэш, а только движение пальца — нет.
- [ ] Вносить по одному изменению и повторять тот же trace. Асинхронный upload должен сохранять ownership буфера/текстуры до завершения GPU; нельзя просто убрать ожидание и получить race.
- [ ] Сопоставить изображение до/после на фиксированном seed и одинаковой траектории; проверить след, мягкость, цвет, восстановление и корректность экспорта.

**Готово:** первый touch без заметного отдельного stall; в steady drag p95 CPU/GPU укладывается в согласованный бюджет текущего renderer (60 FPS = 16,7 мс, 30 FPS = 33,3 мс); нет серии длинных hitch, старого snapshot, гонок или утечек. Если бюджет не достигнут — явно записать ограничение и следующий подтверждённый bottleneck.

## 4. Карусель Me: корректность и плавность

**Файлы:** `Views/MeView.swift`, `Views/MeViewSupport.swift`, `Views/Me/MeCalendarStrip.swift`, `Services/HistoryThumbnailCache.swift`, `Views/Components/DayCanvasArtworkView.swift`.

**Тесты:** `Steps4Tests/MeWeekStatsTests.swift`; создать `Steps4Tests/MePosterLoadingTests.swift`, `Steps4UITests/MeCarouselUITests.swift`, зарегистрировать в проекте.

- [ ] Записать конкретные симптомы: рывок/пустой кадр, неверная выбранная дата, «прыгающая» высота, рассинхронизация календаря, неожиданный переход или неправильный share. Не считать карусель исправленной только после оптимизации загрузчика.
- [ ] Измерить число одновременно живых страниц, artwork renderers, загрузок и перерисовок при свайпе; проверить стоимость main-thread render/decode и публикаций общего AppModel.
- [ ] Проверить stable identity страницы и привязку ответа к dayKey: медленный ответ старой страницы не должен менять выбранную; отмена потребителя не должна ломать разделяемую загрузку.
- [ ] Повторно проверить negative cache ошибки сети, замену snapshot нулевым Health и устаревший fallback artwork из прошлого ревью на новом HEAD.
- [ ] Добавить детерминированные сценарии: loader nil/error→success; Health приходит после fallback; быстро A→B→A; share после выбора B; отмена при уходе; возврат на сегодня после новых happenings.
- [ ] Исправлять отдельно состояние/идентичность, асинхронную загрузку и визуальную стоимость. Prefetch ограничивать текущей страницей и соседями только если trace подтверждает необходимость; ограничить кэш по ресурсам, не скрывая сетевые ошибки.
- [ ] Прогнать 20 свайпов, календарные переходы, offline→online, большие размеры текста и VoiceOver. Сравнить память и hitches с baseline.

**Готово:** дата, календарь, изображение, подписи и экспорт относятся к одному дню; нет пустых вспышек при возврате к загруженной странице, ошибочной вечной заглушки и роста памяти от каждого свайпа.

## 5. Проверка пересечений трёх подсистем

- [ ] Звук + Smudge → Me → быстрые свайпы → Canvas: проверить живые engine/renderers и отсутствие скрытой нагрузки.
- [ ] Fullscreen → drag/звук → lock/background → foreground: определить ожидаемый resume policy из текущего продукта и проверить его без автоматического включения звука вопреки настройке.
- [ ] Remix и изменение happenings во время звука/Smudge: картинка, sample plan, touch target и сохраняемые данные остаются согласованными.
- [ ] Десятиминутный прогон на устройстве: thermal state, память, аудиоразрывы, накопление tasks; отдельно Low Power и Reduce Motion.

**Выход:** совместный before/after trace. Изолированный успех audio или Smudge не закрывает этот этап.

## 6. Остальной PR — систематический проход по всем изменённым областям

- [ ] Из актуального diff собрать coverage-таблицу: каждый изменённый production файл относится к проверенной области; тесты, документы и бинарные ресурсы учитывать отдельно.
- [ ] Canvas: persistence/remix/history/export, old-data decoding, баланс энергии, право редактирования, VoiceOver; перепроверить все пункты старого отчёта, помечая obsolete отдельно.
- [ ] Health/notifications: denied/partial/no-data, background refresh, day boundary/timezone, дубликаты suggestions и удаление уведомлений.
- [ ] Settings/account/sync: restore на новом устройстве, отменённый login, sign-out при pending sync, retries и account-scoped caches; две новые preference migrations и совместимость старого клиента.
- [ ] Feeds/Screen Time/widget: списание и refund, authorization revoked, late-evening fallback, expiry и extension deployment targets. Сопоставить открытые PR №22–25, не переносить автоматически изменение семантики usage budget в wall-clock.
- [ ] Звуковые assets/dependencies: наличие Release-ресурсов, отсутствие dev-only путей, manifest/duration/sample-rate consistency, лицензии, размер приложения, decoder failures и безопасный fallback.
- [ ] Эксперименты и инструменты: удалить только доказанно неиспользуемые остатки; проверить build membership, flags и тестовые fixtures в Release. Не выполнять широкую косметическую чистку вместе с функциональными исправлениями.
- [ ] Для каждой подтверждённой ошибки P0/P1/P2: записать воспроизведение, добавить дискриминирующий regression где оправдано, исправить и проверить. P3 выполнять при понятной пользе и малом риске; спорные изменения продукта вынести отдельно.

**Выход:** журнал без незакрытых P0/P1; каждый P2 исправлен либо явно обозначен как остаточный риск с причиной и влиянием. Не обещать буквальное отсутствие всех ошибок.

## 7. Финальная проверка и подготовка PR

- [ ] После локальных целевых проверок выполнить полный iOS unit suite один раз на итоговом коде, затем UI-сценарии Canvas/Smudge/звук/Me и smoke onboarding/settings/feeds.
- [ ] Собрать Debug и Release; проверить bundle ресурсов, минимальные iOS каждого extension и отсутствие тестовых обходов в пользовательских путях.
- [ ] Выполнить тесты затронутых Swift/Python-инструментов аудио/рендера; проверить admin-panel/tg-admin текущим CI. Не использовать старый зелёный CI как результат нового HEAD.
- [ ] Повторить baseline на том же устройстве, с теми же fixtures и без одновременно идущего build. Для каждого приоритетного дефекта показать before/after и visual/audio regression результат.
- [ ] Проверить финальный diff на случайные WIP, секреты, assets и диагностические логи. Каждый коммит — отдельное законченное исправление со своей проверкой, позволяющее откат без остальных подсистем.
- [ ] Обновить локально описание PR: итоговый состав, измеренные улучшения, тесты, обязательные migrations и остаточные ограничения. Проверить, что reviewed/tested SHA совпадает с публикуемым.
- [ ] При публикации обновления выполнить обычный push integration без force и дождаться CI нового HEAD; merge в main оставить отдельным явно запрошенным действием.

## Порядок и критерий завершения

Последовательность: версия → baseline → audio → Smudge → карусель → совместный прогон → остальные области → final verification. Если trace показывает общую причину нескольких симптомов, сначала исправить общую причину и повторить все затронутые сценарии.

План завершён не тогда, когда «все тесты зелёные», а когда три пользовательские проблемы воспроизводились до изменения и перестали воспроизводиться после него; измерения улучшились без потери эффекта/звука; остальные изменённые области покрыты ревью; финальные проверки относятся к одному точному набору файлов. Отсутствующий device trace, неоднозначная продуктовая семантика и внешняя недоступность должны остаться явно видимыми ограничениями.
