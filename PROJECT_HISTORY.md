# Nowhere — История создания проекта

**Проект:** Steps4 / Nowhere  
**Автор:** Konstantin Pudan  
**Период документирован:** ~начало 2026 — апрель 2026  
**Составлен:** 3 апреля 2026 на основе чатов с AI

---

## Идея

Идея пришла из личного кризиса. Годы работы над creative-проектами для брендов — награды, признание — и ощущение, что живёшь внутри своей работы, прячешься в ней. "Я не знал себя. Я был нигде". Отсюда — имя: **Nowhere**. Читаешь снова — **Now Here**. Всё приложение построено вокруг этого парадокса.

Первоначальная идея: твои реальные действия (шаги, сон, ежедневные выборы) производят **цвета**. Цвета — это то, чем ты платишь за доступ к своим фидам (заблокированным приложениям). Не деньгами. Жизнью.

---

## Архитектура проекта

**Xcode проект:** `Steps4.xcodeproj`  
**Display name:** Nowhere  
**Внутренние имена:** StepsTrader, Steps4 (легаси от первых итераций, когда механика была про шаги→торговля)

### Таргеты (7 штук)

| Таргет | Назначение |
|--------|------------|
| Steps4 | Основное приложение |
| DeviceActivityMonitor | Extension: отслеживание событий использования приложений, перестройка шилдов |
| ShieldAction | Extension: обработка тапа на шилде → deep link → PayGate |
| ShieldConfiguration | Extension: кастомный UI шилда |
| UnlockWidgetExtension | WidgetKit: Energy Status + App Groups с App Intents |
| Steps4Tests | Unit-тесты |
| Steps4UITests | UI-тесты |

### Стек
- **SwiftUI** — основной фреймворк UI
- **HealthKit** — шаги и сон
- **FamilyControls + DeviceActivity + ManagedSettings** — блокировка приложений
- **Supabase** — бекенд, синхронизация, аналитика
- **Metal** — smudge-оверлей на canvas (живая "живопись")
- **WidgetKit + App Intents** — виджеты на домашнем экране
- **Sign in with Apple** — аутентификация

---

## Хронология разработки

### Этап 1 — Онбординг и концепция потока

Одна из первых больших задач: спроектировать онбординг, который одновременно объясняет механику и передаёт дух приложения. Проводился разбор с разных ролей — пользователь, PM, UX, редактор, инвестор.

**Результат — Onboarding v5 (13 слайдов):**
1. Холодный старт
2. Концепция canvas
3. **Paint demo** — интерактивная демонстрация рисования
4. **Color cap** — лимит 100 цветов
5. **Spend demo** — трата цветов
6. Резюме петли
7. Шаги / сон
8. HealthKit разрешение
9. Выбор фидов (можно пропустить)
10. "nowhere" / "now here" — раскрытие имени
11. Sign in with Apple
12–13. Приветствие

Онбординг — lowercase и литературный, не инструкция. Имя приложения намеренно раскрывается поздно.

Документ: [`ONBOARDING_FLOW.md`](./ONBOARDING_FLOW.md)

**Чаты:** [Онбординг — мультиролевой анализ](3029d124-b52f-4c86-8203-7fe80ce82f8f) · [Онбординг — улучшения](c591cc64-7192-44e8-a8ab-747602795bda)

---

### Этап 2 — Unlock flow: аудит и починка

Центральный технический вопрос: пользователь платит цветами → на N минут снимается блокировка. Механика проходила через виджет, PayGate и само приложение. Разбирался полный audit flow:

- Почему 10 минут работают, а 1 час — нет
- Почему новое приложение, открытое через виджет, не разблокируется
- `startOrUpdateLiveActivity` — scope error в extension
- Исправлена надёжность unlock через приложение (не только через виджет и PayGate)

**Чаты:** [Полный аудит unlock flow](9c5a8b57-bee2-4377-b9e0-cfcddcf3fb23) · [Unlock — надёжность](1a1f33ea-6c0b-4ce6-b583-0e03bf525c7d)

---

### Этап 3 — Me Page (теперь "Now" tab)

Вкладка профиля с 7-дневными кольцами, рефлексией недели, разбивкой по категориям и топ-потребителями. Итерации:

- Порядок копии в weekly block
- Паттерны предложений, читаемость, всё на одном экране
- Жёлтые кольца только на верхних кружках
- Приветственные строки и переносы "and"
- Исправлен compile error: `Int` vs `CGFloat` в `MeView.swift`
- Нарратив "I am NAME…" — bio UX, минималистичный стиль

**Чаты:** [Me tab — улучшения](6e464dad-c849-45d7-920a-88300103cd6c) · [Me page — bio UX](c8ab30d6-190a-4509-b52c-9b2ae1852b59)

---

### Этап 4 — Canvas и GalleryView

Главная вкладка. Canvas = генеративная анимированная картина дня. Технически: SwiftUI `Canvas` + `Timeline` + Metal smudge overlay.

**Ключевые задачи:**

- Широкий режим (wide) — элементы canvas не должны перемещаться при переходе в wide-вьюпорт; исправлено aspect-fill / canonical positioning
- `GalleryView`: широкий режим сохраняет ту же композицию что и нормальный; нижние контролы над tab bar в не-wide режиме
- Добавление на canvas: случайный цвет при добавлении элемента; редактирование цвета только в режиме редактирования
- Gradient assets / recolor / multi-color asset UX
- Широкий viewport не двигает элементы
- В широком режиме — только подписи (labels), без визуальных ассетов
- Список ассетов + скриншоты + отсутствующие mind/heart PNGs

**Чаты:** [Canvas — wide layout](ff2f626f-a72e-48b7-a0a8-cc05ca1dfd96) · [Canvas — цвета и редактирование](3045e37b-b89c-4c05-ba2a-af0a685b2b1a) · [Canvas — Maestro позиционирование](56e0636e-2440-4697-9164-7f5e249b8dc2) · [GalleryView — wide mode](aea72e02-6110-4b82-b25b-5018e6fe348a)

---

### Этап 5 — Виджеты

Два виджета через `UnlockWidgetExtension`:
- **Energy Status** (medium) — текущий баланс цветов
- **App Groups** (large) — настраиваемые группы через `AppIntentConfiguration` + `SelectGroupIntent`

Настройки: solid фон vs снимок обоев (через Settings → Widget).

**Ключевые задачи:**

- Механика обновления виджетов — объяснение, как часто данные обновляются
- Идеи для поддержания актуальности чисел
- Usage-based минуты vs wall-clock таймер
- Fix: шаги → reload виджета
- Большой виджет: обновляется самостоятельно + показывает минуты после выхода из приложения
- Dynamic Island таймер во время скролла
- `startOrUpdateLiveActivity` not in scope
- Bug fix: `usageBudgetInitial` перезаписывается при повторном тапе unlock (прогресс-бар показывает неверный знаменатель)
- Bug fix: цвета виджета не сбрасываются на кастомной границе дня
- Fix: обновление одного виджета должно обновлять оба (medium и large)
- Bug fix: при переходе виджет→приложение, время покупки сбрасывается в 0

**Чаты:** [Механика refresh виджетов](6581e3fb-6050-4ee7-97c8-34b09b339aa6) · [Большой виджет + Dynamic Island](be84dc4c-80ed-4938-82db-8fd6fa91f768) · [Widget colors boundary bug](c432be53-67f9-4ef4-93aa-2d86860e5a6b) · [Widget → app time reset](8841306b-2734-4dfe-9003-a36fe558114e)

---

### Этап 6 — Supabase + аналитика

Supabase как бекенд: профиль пользователя, дневные выборы, статистика, tickets, аналитика.

**Ключевые задачи:**

- Аудит синхронизации: какие таблицы нужны, какие лишние — дропнуть
- `SupabaseSyncService+Analytics` — publishing из background threads (threading bug → @MainActor fix)
- Аналитические события: `onboarding_completed`, `piece_selected`, `experience_spent`, `canvas_viewed`, `ticket_created`
- Паттерн синхронизации tickets: delete + reinsert через `syncTicketGroups`

**Чаты:** [Supabase sync audit](517bb508-d83d-4010-93bd-88c1a6f933f6) · [Supabase analytics threading](d1a33915-6075-458f-b517-d353e46dd3f4)

---

### Этап 7 — Health + Canvas интеграция

Добавление упражнений на canvas из HealthKit. Вопросы работы в симуляторе vs реальном устройстве. Local notification при обнаружении активности в Health.

**Также:** баннер под notch; Maestro/idb PATH setup; label-mode `timeScale` / hit-test fixes.

**Чат:** [Canvas + Health integration](d90291bc-63f2-4115-bfbf-2837052a2066)

---

### Этап 8 — Deprecated APIs и iOS 26

- `UnlockWidgetViews` — `Text` + deprecated modifier на iOS 26
- `.synchronize()` убран
- `UIApplication.shared.open` → async версия
- Остаточные `print()` → `AppLogger` (OSLog)

**Чат:** [iOS 26 deprecated APIs](d1a33915-6075-458f-b517-d353e46dd3f4)

---

### Этап 9 — Полный аудит кода (March 24, 2026)

Аудит всех 123 Swift файлов по 7 таргетам. Найдено:

**P0 (критические):**
- `loadDayPassGrants()` не вызывается в bootstrap → дневные пропуска теряются
- `loadAppUnlockSettings()` не вызывается → настройки разблокировки сбрасываются
- `loadCustomEnergyOptions()` не вызывается → кастомные активности пропадают
- `pay(cost:)` капает `spentStepsToday` вопреки задокументированному инварианту
- Отсутствует `NSHealthShareUsageDescription` в Info.plist

**P1 (высокий приоритет):**
- `payForEntry` с nil bundleId → цвета списываются без audit trail
- `startStepObservation()` не вызывается при bootstrap
- Тройной `recalculateDailyEnergy()` на каждый refresh
- Widget `usageBudgetInitial` перезаписывается при повторном unlock
- RNG bug в `OnboardingStoriesView.generateFloaters()`

Документ: [`AUDIT_REPORT.md`](./AUDIT_REPORT.md)

---

### Этап 10 — Notes Tab и тексты

Вкладка Notes — 11 редакционных карточек. Не инструкции. Эссе.

| Карточка | О чём |
|---------|-------|
| About the Canvas | День как отражение |
| About Body, Mind, and Heart | Тибетски вдохновлённое трёхчастное деление |
| About Shapes | Почему body = дышащие формы, mind = дрейфующие круги, heart = лучи |
| About Sleep | Сон на canvas (темнее = больше отдыха) |
| About Steps | Шаги как доказательство движения через мир |
| About Feeds | Минуты исчезают; трата цветов осушает canvas |
| About Limits | Личные пороги, не универсальные обязательства |
| About Wallpaper | Canvas как зеркало на lock screen |
| About Colors (×2) | Намерение палитры + "не продаётся" экономика |
| About Kosta | Письмо основателя — nowhere → now here, выгорание, контакт |

Тексты экспортированы в MD. Написаны комментарии и рефрейм на русском. Создан манифест About Kosta. Обсуждались supporting images к каждой карточке.

**Чат:** [Manuals texts export](1db023e2-ca1a-4f3b-bbbc-a1e8e576acea)

---

### Этап 11 — Welcome / Onboarding Screen

Отдельная задача: экран приветствия в соответствии с BRANDBOOK. Вместо логотипа — иконка приложения (App Icon). Итерации по соответствию brandbook-у.

**Чат:** [Onboarding welcome screen](5d54dee6-f8be-4127-a7c9-afa285d312a4)

---

### Этап 12 — App Store Connect + TestFlight

- Попытка загрузить `1.0.1` → ошибка: train `1.0.1` уже закрыт, `CFBundleShortVersionString` должен быть выше `1.0.1`
- Решение: поднять до `1.0.2` или `1.1.0`
- Commit и push с правильными сообщениями
- Инструкции для тестеров TestFlight: на что обращать внимание в текущем билде

**Чаты:** [App Store Connect validation](993f88e3-d9ae-4914-b48a-27a984021bd3) · [Commit + TestFlight guidance](d1480551-34eb-4d19-b9fd-c1a1cfe58f3c)

---

### Этап 13 — Стратегия и брендбук (обновление)

Пересмотр и синхронизация `PROJECT_STRATEGY.md` и `BRANDBOOK.md` с реальным состоянием кода — canvas, widgets, тон голоса, активный онбординг, shield copy.

**Чат:** [Refresh strategy + brandbook](b13fa073-4197-4b89-a133-b3c98fa740ba)

---

### Этап 14 — Маркетинг и позиционирование

#### Исследование конкурентов

Запущен маркетинговый research. Изучены конкуренты в категории:
- Традиционные blocker'ы (Screen Time, Freedom, One Sec, Opal)
- Unusual / aesthetic (Blank, Smile)
- Wellness/habit apps
- Anti-gamification подход

Использован Perplexity MCP для поиска данных. Найдены gap'ы рынка. Результат в `MARKETING_COMPETITOR_RESEARCH.md`.

**Чаты:** [Marketing research](b738fc66-9879-4bf3-928e-625c19ece73a) · [Competitor analysis](60e82f02-d7c7-449b-ae96-7cfe549181ab)

#### Позиционирование

Из конкурентного исследования добыты углы позиционирования. Создан `POSITIONING_ANGLES_SKILL.md` — живой документ с лучшими фреймами.

Выбран лучший угол: **"Not a blocker. A daily life canvas that happens to control your feeds."**

Один-лайн питч: _"Your life makes colors. Your feeds cost them."_

**Чаты:** [Mining research for angles](534c699e-ec9c-4416-8e17-1d93e349cf66) · [Picking the best angle](49bc09cf-7a22-4294-bcf6-5637faf72319)

#### Low-budget маркетинг

Идеи высокого левереджа с низким бюджетом, используя позиционирование AI/automation:
- Reddit (r/digitalminimalism, r/nosurf, r/QuantifiedSelf)
- Substack outreach
- Are.na community
- ProductHunt
- Creator partnerships

**Чат:** [Low-budget marketing ideas](322063b5-b220-482e-9c9f-edf59caa2e7d)

---

## Словарный договор

Один из ключевых дизайн-решений — жёсткий vocabulary contract. Закреплено в PROJECT_STRATEGY.md и соблюдается во всём UI:

| Концепция | ТОЛЬКО это | НЕ это |
|-----------|-----------|--------|
| Что производит жизнь | **colors** | balance, energy, EXP, experience, steps, points |
| Ежедневные действия | **pieces** | activities, selections, options |
| Три категории | **body, mind, heart** | Move/Reboot/Joy |
| Группы приложений | **tickets** (код) / **feeds** (вкладка) | shields, groups, bundles |
| Обмен | **spend** | pay, deduct, use, trade |
| Опция отмены | **keep it closed** | cancel, dismiss, close, lock |
| Записи Notes | **notes** | guides, manuals, help |

---

## Тон голоса

Документ: [`TONE_OF_VOICE.md`](./TONE_OF_VOICE.md)

Модель: один человек говорит с другим. Онбординг и Notes — lowercase и литературный. Шилды и уведомления — коротко и фактически.

- Без восклицательных знаков в рутинном UI
- Shield: "[App] is closed." / "Spend colors in Nowhere to unlock it."
- Notes: тон эссе, не help docs
- Observational, dry, economical, honest

---

## Текущее состояние (апрель 2026)

**Feature-complete для серьёзной беты.**

- Онбординг v5 — 13 интерактивных слайдов
- Canvas с Metal smudge overlay
- 5 вкладок: Canvas, Feeds, Now (неделя), Notes, Settings
- 11 редакционных карточек в Notes
- Виджеты: Energy Status + App Groups
- Shield extensions с Nowhere-брендингом
- Supabase: sync + аналитика
- 90-дневные snapshots истории
- 7-дневные кольца в Now tab
- Localizable.xcstrings (primary English)

**Остаётся перед публичным запуском:**
- Device QA на физическом устройстве
- TestFlight distribution
- Набор тестеров (30-50)
- App Store Connect assets (скриншоты, описание)
- Переименовать внутренние "steps" переменные в "colors" (механическая задача)

---

## Технический долг

| Пункт | Приоритет |
|-------|-----------|
| Дублирующийся `Note.id` для двух "About Colors" | Низкий |
| Внутренние имена `totalStepsBalance`, `StepBalanceCard` | Средний |
| AppModel forwarding layer | Средний |
| Остаточные `print()` в extensions | Низкий |

---

## Ключевые файлы проекта

| Файл | Назначение |
|------|-----------|
| `BRANDBOOK.md` | Полный брендбук v1.1 |
| `PROJECT_STRATEGY.md` | Стратегический блюпринт |
| `TONE_OF_VOICE.md` | Голос и тон |
| `ONBOARDING_FLOW.md` | Спецификация онбординга v5 |
| `AUDIT_REPORT.md` | Полный аудит 123 файлов (March 24, 2026) |
| `MARKETING_COMPETITOR_RESEARCH.md` | Конкурентный анализ |
| `POSITIONING_ANGLES_SKILL.md` | Углы позиционирования |
| `MANUALS_TEXTS.md` | Тексты Notes tab |

---

*Документ создан: 3 апреля 2026. Основан на ~28 чатах с AI (Cursor) за период разработки.*
