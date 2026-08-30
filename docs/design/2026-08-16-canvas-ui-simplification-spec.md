# Canvas UI Simplification — Handoff Spec

## 1. Overview

Упростить основной экран Canvas так, чтобы пользователь сразу видел:

1. сколько дневной энергии осталось из заработанного сегодня;
2. сам холст без перекрывающей его большой панели;
3. три понятных действия внизу: раскрыть холст, показать данные, добавить happening.

Полноэкранный просмотр и редактирование — два разных режима. Раскрытие холста не должно автоматически включать редактирование.

### Вне scope

- Изменение формулы начисления энергии.
- Изменение HealthKit, Supabase, App Group или day-boundary контрактов.
- Ручное добавление Steps или Sleep.
- Новый универсальный редактор с инструментами Select / Draw / Text / Elements.
- Изменение нижней навигации Canvas / Feeds / Me.
- Изменение data-driven фонового градиента при Remix.

## 2. Термины и источники данных

| Понятие | Источник | Правило |
|---|---|---|
| Остаток сегодня | `model.userEconomyStore.stepsBalance` | `clamp(stepsBalance, 0...earnedToday)` |
| Получено сегодня | `model.healthStore.baseEnergyToday` | `max(0, baseEnergyToday)` |
| Потрачено сегодня | `model.spentStepsToday` | Не показывается текстом; уже отражено в остатке |
| Бонусный баланс | `model.userEconomyStore.bonusSteps` | Не входит в верхний индикатор |
| Общий баланс | `totalStepsBalance` | Не использовать для этой карточки |

Верхний блок отвечает только на вопрос «сколько осталось из того, что получено сегодня». Пример: `58 / 72`.

```swift
let earnedToday = max(0, model.healthStore.baseEnergyToday)
let remainingToday = min(max(0, model.userEconomyStore.stepsBalance), earnedToday)
let remainingProgress = earnedToday > 0
    ? Double(remainingToday) / Double(earnedToday)
    : 0
```

`100`, `100 max`, `Energy`, `left` и `gained today` визуально не показываются.

## 3. State model

Экран имеет четыре взаимоисключающих presentation state:

```swift
enum CanvasPresentationState: Equatable {
    case canvas
    case data
    case fullScreen
    case editing
}
```

Допустимые переходы:

| From | Action | To |
|---|---|---|
| `canvas` | Tap Show data | `data` |
| `canvas` | Tap Full screen | `fullScreen` |
| `canvas` | Tap + | Canvas остаётся видимым; открывается существующая happening palette |
| `data` | Tap Hide data / swipe down | `canvas` |
| `fullScreen` | Tap Edit | `editing` |
| `fullScreen` | Tap Exit full screen | `canvas` |
| `editing` | Tap Done | `fullScreen` |

Запрещённые состояния:

- data sheet одновременно с full screen;
- edit mode без full screen;
- tab bar или верхний индикатор поверх full screen/editing;
- автоматический вход в editing при раскрытии холста.

Текущий `isWideCanvas` соответствует `fullScreen || editing`. Текущий `editState.isEditMode` соответствует только `editing`.

## 4. State A — Canvas

### 4.1 Layout

- Холст full-bleed и остаётся главным визуальным слоем.
- Верхний status pill закреплён по горизонтальному центру под Dynamic Island.
- Status pill не меняет положение при появлении или исчезновении других кнопок.
- Нижний action row расположен над floating tab bar с учётом `safeAreaBottom` и измеренного `tabBarHeight`.
- Порядок action row строго фиксирован:
  1. слева — Full screen;
  2. по центру — Show data;
  3. справа — Add.

### 4.2 Compact energy status

| Property | Spec |
|---|---|
| Content | `remainingToday / earnedToday`, пример `58 / 72` |
| Position | top center; `safeAreaTop + spacing-sm` |
| Width | 148 pt regular; content-driven up to 176 pt with Dynamic Type |
| Height | 58 pt regular |
| Corner radius | `radius-lg` = 16 pt continuous |
| Horizontal padding | `spacing-md` = 14 pt |
| Vertical padding | `spacing-sm` = 8 pt |
| Background | `glassCard(cornerRadius: 16, style: .lens)` |
| Remaining number | 20 pt, semibold, monospaced digit, `color-accent` |
| Separator | 17 pt, medium, primary text at 65% opacity |
| Earned number | 17 pt, semibold, monospaced digit, primary text |
| Progress height | 6 pt |
| Gap text → progress | 7 pt |

Progress bar:

- track spans the full inner width and represents `earnedToday`, not the product maximum 100;
- fill width = `remainingToday / earnedToday`;
- fill uses `AppColors.brandAccent` (`#FFD369`);
- track uses primary text at 20% opacity or existing glass-compatible stroke;
- animation only when either value changes: 300 ms ease-in-out;
- with Reduce Motion enabled, update without spring/overshoot.

Edge values:

| Data | Display | Progress |
|---|---|---|
| `earnedToday = 0` | `0 / 0` | 0% |
| `remainingToday = 0`, earned > 0 | `0 / earned` | 0% |
| remaining > earned because of stale state | clamp to earned | 100% max |
| bonus balance > 0 | ignored | unchanged |

### 4.3 Bottom action row

Common rules:

- horizontal guard rail: 24 pt;
- visual control height: 56 pt;
- minimum hit target: 72×72 pt for circles; at least 56 pt high for the center pill;
- all controls share one vertical center line;
- use `GlassEffectContainer` on iOS 26 to avoid merged interactive glass hit regions;
- order must not change in RTL; icons remain spatial utility controls, while text inside Show data localizes normally.

#### Full screen control — left

- Visual: transparent circular button with a thin outline, not a filled glass pill.
- Visual circle: 56×56 pt.
- Hit region: 72×72 pt.
- Border: primary text at 35% opacity, 1 pt.
- Icon: `arrow.up.left.and.arrow.down.right`, 20 pt regular.
- No visible text label.
- Accessibility label: localized `Expand canvas`.
- Tap: transition `canvas → fullScreen`; close the data sheet first if a stale state exists.

#### Show data control — center

- Visual: Liquid Glass capsule.
- Size: 128×56 pt regular; width may grow for localization.
- Use `liquidGlassControl(in: Capsule(style: .continuous), style: .lens)`.
- Content: localized `Show data` + `chevron.up`, 15 pt semibold.
- One-line only; minimum scale factor 0.85.
- Accessibility label: `Show canvas data`.
- Accessibility value: `Collapsed`.
- Tap: `canvas → data`.

#### Add control — right

- Visual circle: 56×56 pt; hit region 72×72 pt.
- Fill: `AppColors.brandAccent`.
- Foreground: `AppAccentInk.primary`.
- Icon: `plus`, 22 pt regular.
- Accessibility label: existing localized `Add happening`.
- Tap: existing `openHappeningPalette()` flow.
- Preserve current coach-mark anchor and `CanvasAddButtonCenterKey` reporting.

## 5. State B — Data

### 5.1 Behavior

- Верхний compact status pill остаётся на том же месте и не меняет размер.
- Data panel появляется снизу как bottom sheet поверх холста.
- Высота панели определяется её содержимым. Три строки по 52 pt плюс шапка дают
  минимум ~266 pt, и это больше 40% доступной высоты на любом текущем iPhone
  (535 pt доступно на Face ID-модели → 214 pt; 367 pt на SE → 147 pt), поэтому
  правило «не выше 40%» действует как потолок на случай роста числа строк, а не
  как обещание для трёх. Сжимать строки ниже 52 pt нельзя — это ниже минимума
  тапабельной цели.
- Холст остаётся видимым за sheet и над ним.
- Открытие data panel не изменяет canvas rendering state.

### 5.2 Sheet

| Property | Spec |
|---|---|
| Presentation | bottom overlay, не modal system sheet |
| Background | glass lens tinted/frosted according to legibility; reuse existing glass primitives |
| Top corners | 24 pt continuous |
| Drag handle | 36×4 pt, primary at 45% opacity |
| Header control | localized `Hide data` + `chevron.down` |
| Rows | Steps, Sleep, Happenings |
| Row minimum height | 52 pt |
| Horizontal padding | 16 pt |
| Row spacing | 8 pt |

Rows show the current metric contribution and remain tappable using existing handlers:

- Steps → `metricOverlay = .steps`;
- Sleep → `metricOverlay = .sleep`;
- Happenings → `metricOverlay = .happenings`.

Steps and Sleep are HealthKit-driven and must not expose manual-add actions. The small trailing `+` symbols present in exploratory mockups are not part of the functional spec. Adding a happening remains the single yellow `+` action on the Canvas state.

Closing:

- tap `Hide data`;
- downward drag exceeding 60 pt or 700 pt/s;
- switching away from Canvas tab;
- entering full screen;
- opening happening palette.

Motion: 300 ms interactive spring (`response: 0.32`, `dampingFraction: 0.86`); Reduce Motion uses a 150 ms opacity transition.

## 6. State C — Full screen viewing

Full screen is a viewing state, not editing.

On entry:

- set `isWideCanvas = true`;
- ensure `editState.isEditMode = false`;
- dismiss data panel and metric overlays;
- hide status pill, bottom action row, tab bar, activity suggestions and surrounding chrome;
- preserve canvas animation.

Bottom dock:

- pinned above safe-area bottom;
- translucent shared glass capsule;
- two actions: `Exit full screen` and `Edit`;
- minimum control height 56 pt;
- labels remain visible; do not rely on ambiguous icons alone.

Actions:

- `Exit full screen` → Canvas;
- `Edit` → Editing.

The existing iPad naturally-wide behavior may enter `fullScreen`, but must never auto-enter `editing`.

## 7. State D — Editing

### 7.1 Entry and chrome

- Editing can only be entered from Full screen.
- Canvas remains edge-to-edge.
- Hide status, tab bar, data controls, add button and full-screen dock.
- Top-left: glass `Done` control.
- Optional one-time coach text: localized `Drag elements to move`; auto-dismiss after 2.5 s or after the first successful drag.
- Bottom center: filled yellow `Remix` capsule.

### 7.2 Direct manipulation

- Drag is the only required element-editing gesture in this scope.
- Touching an element selects the nearest hit within its rendered bounds plus 12 pt tolerance.
- Selected element receives a subtle outline/glow only.
- No bounding box, resize handles, delete button, per-element dice button, Select/Draw/Text/Elements toolbar, pinch-resize or rotation gesture.
- Drag clamps normalized `basePosition` to `0.05...0.95` on each axis, matching current persistence constraints.
- Persist after drag end using the existing local mutation and save flow.

### 7.3 Remix

`Remix` changes the visual treatment of all decorative canvas elements at once.

For every existing `CanvasElement`, Remix may update:

- `shapeSeed`;
- `frozenShapeType`, constrained by `CanvasShapeType.allowedByUser`;
- `hexColor` and `hexColor2`, constrained by the current day composition palette;
- visual size and motion personality if required by the chosen shape;
- `lastEditedAt`.

Remix must preserve:

- `id`;
- `optionId`, label and semantic happening identity;
- `basePosition` — especially positions the user has manually arranged;
- day key and energy contributions;
- Steps/Sleep data;
- the data-driven background gradient;
- element count.

After Remix:

- update `dayCanvas.lastModified`;
- increment `localMutationCounter` once for the whole operation;
- persist the canvas once, after the batch completes;
- medium haptic feedback;
- animate the visual swap over 300 ms; Reduce Motion uses a crossfade.

`Done` saves any active drag, clears selection and returns to Full screen viewing. It does not collapse the canvas.

If the app resigns active while editing, commit an active drag, clear selection and return to Full screen viewing on resume.

## 8. Component changes

| Component / file | Required change |
|---|---|
| `Views/Components/StepBalanceCard.swift` | Replace the large/expandable card with a compact `CanvasEnergyStatusPill`; remove `100`, timer, help, internal expand state and metric chips from the top overlay. |
| `Views/MainTabView.swift` | Pass daily-only `stepsBalance` and `baseEnergyToday`; show the compact pill only in Canvas/Data; continue hiding it for wide/editing and Me. |
| `Views/GalleryView.swift` | Own or bind Canvas/Data/FullScreen/Editing presentation state; replace bottom row with outlined expand circle, center Show data glass pill and yellow Add circle; render data sheet and full-screen controls. |
| `Views/Gallery/CanvasStateManagers.swift` | Keep transient drag state; remove unneeded rotation/size state if no longer consumed. |
| `Views/GenerativeCanvasView.swift` | No rendering-contract change expected. |
| `Models/CanvasElement.swift` | Reuse/refactor reroll behavior for a batch Remix that preserves `basePosition` and identity. |
| `Localizable.xcstrings` | Add/update strings and accessibility labels listed below. |

Recommended extraction:

- `CanvasEnergyStatusPill`
- `CanvasBottomActionRow`
- `CanvasDataPanel`
- `CanvasFullScreenDock`

Each component should accept data/actions as props and contain no persistence logic.

## 9. Design tokens

| Token | Value / source | Usage |
|---|---|---|
| `color-accent` | `AppColors.brandAccent` / `#FFD369` | remaining number, progress fill, Add, Remix |
| `color-accent-ink` | `AppAccentInk.primary` | icon/text on yellow controls |
| `color-text-primary` | `AppColors.Night.textPrimary` | labels and icons on canvas |
| `glass-lens` | existing `LiquidGlassStyle.lens` | status, Show data, full-screen dock |
| `spacing-xs` | 4 pt | icon/text micro gaps |
| `spacing-sm` | 8 pt | internal vertical gaps |
| `spacing-md` | 14–16 pt | card/sheet padding |
| `spacing-lg` | 24 pt | bottom-row guard rail |
| `radius-lg` | 16 pt | status pill |
| `radius-sheet` | 24 pt | data panel top corners |
| `control-visual` | 56 pt | main controls |
| `control-hit-circle` | 72 pt | circular control hit area |
| `tap-min` | 44 pt | accessibility floor |

Do not introduce a second yellow or hardcoded glass implementation. Reuse `AppColors`, `AppAccentInk`, `glassCard`, `liquidGlassControl`, `GlassEffectContainer`, `minimumHitTarget` and Reduce Transparency fallbacks.

## 10. Motion and haptics

| Trigger | Motion | Duration | Haptic |
|---|---|---|---|
| Show/Hide data | move from bottom + opacity | 300 ms | light |
| Enter/Exit full screen | surrounding chrome fade/move; canvas remains stable | 350 ms | light |
| Enter/Exit editing | controls crossfade; freeze/unfreeze element motion using current edit behavior | 300 ms | light |
| Drag end | no extra bounce | immediate save | light |
| Remix | synchronized element crossfade/morph | 300 ms | medium |
| Energy value update | progress width ease-in-out | 300 ms | none |

No animation may shift the centered status pill horizontally.

## 11. Accessibility

- Status pill is one accessibility element:
  - label: localized `Daily energy`;
  - value: localized interpolation, e.g. `58 remaining out of 72 earned today`.
- Progress bar is hidden from VoiceOver to avoid duplicate information.
- Full-screen icon has accessibility label `Expand canvas` and hint `Opens the canvas without editing`.
- Show data exposes `Expanded` / `Collapsed` value.
- Add retains `Add happening`.
- Full-screen dock focus order: Exit full screen → Edit.
- Editing focus order: Done → Remix → selected canvas element.
- Selected element label includes its happening label and `Selected` state.
- All interactive targets meet at least 44×44 pt.
- Reduce Transparency uses existing opaque fallback.
- Increase Contrast raises outlined Full screen border opacity from 35% to 65%.
- Reduce Motion replaces moves/morphs with opacity transitions.

## 12. Localization strings

Visible strings:

- `Show data`
- `Hide data`
- `Exit full screen`
- `Edit`
- `Done`
- `Remix`
- `Drag elements to move`

Accessibility-only strings:

- `Daily energy`
- `%lld remaining out of %lld earned today`
- `Expand canvas`
- `Opens the canvas without editing`
- `Show canvas data`
- `Expanded`
- `Collapsed`
- `Edit canvas`
- `Done editing`

The visual `remaining / earned` line uses locale-aware integers with monospaced digits. Do not localize the slash as copy.

## 13. Edge cases

- Empty canvas: controls remain available; Add is still primary.
- No HealthKit data: status may show `0 / 0`; data rows show their existing unavailable/assumed states.
- Energy changes while data sheet is open: status and progress update in place without moving the sheet.
- Day boundary while any state is open: persist current drag, reset to Canvas, reload the new day and dismiss overlays.
- Switching tabs: dismiss Data; Full screen/editing must collapse before switching or prevent tab switching because the tab bar is hidden.
- Happening palette opened: dismiss Data first; status remains visible unless the palette's existing chrome policy hides it.
- Dynamic Type: bottom controls retain 44 pt targets; Show data may grow up to available center width; status numbers stay on one line with minimum scale 0.8.
- Small iPhone/SE: reduce horizontal gaps before reducing control visual size; never go below 44 pt visual circles.
- iPad natural-wide mode: treat as Full screen viewing, never as Editing.

## 14. Analytics

If analytics are already collected for Canvas actions, add:

- `canvas_data_opened`
- `canvas_data_closed`
- `canvas_fullscreen_entered`
- `canvas_fullscreen_exited`
- `canvas_edit_entered`
- `canvas_edit_exited`
- `canvas_remixed`

Do not include energy values, HealthKit values, happening labels or element IDs in analytics properties.

## 15. Acceptance criteria

1. Canvas opens with a compact centered `remaining / earnedToday` pill and no `100` or `Energy` label.
2. The pill uses the daily balance without bonuses and never shows remaining greater than earned.
3. The pill stays horizontally centered in Canvas and Data states.
4. Bottom actions are exactly: outlined full-screen circle left, Show data glass pill center, yellow Add circle right.
5. Show data opens a bottom panel; it does not expand the top card.
6. Full screen hides status, data controls, Add and tab bar.
7. Entering full screen does not activate editing.
8. Editing begins only after tapping Edit in Full screen.
9. Editing supports direct element dragging and no generic editing toolbar.
10. Remix changes all decorative element shapes/colors while preserving identities, positions and element count.
11. Done returns Editing → Full screen, not Canvas.
12. All mutations persist through the existing local save/sync path.
13. VoiceOver labels communicate the meaning of `58 / 72` without visible explanatory copy.
14. Reduce Motion and Reduce Transparency variants remain usable.

## 16. Verification plan

### Unit tests

- status value clamps and progress calculation;
- bonus balance excluded from the status;
- state-transition table, including invalid combinations;
- Remix preserves IDs, semantic fields, positions and count;
- Remix draws only from allowed shapes/colors;
- day-boundary reset returns to Canvas;
- Reduce Motion transition policy.

### SwiftUI / snapshot coverage

- Canvas, Data, Full screen and Editing states on a Face ID iPhone;
- compact-width iPhone/SE;
- Dynamic Type default and accessibility size;
- Reduce Transparency and Increase Contrast;
- empty energy `0 / 0`, full remaining, zero remaining;
- long localized Show/Hide/Exit labels.

### UI tests

- Canvas → Data → Canvas;
- Canvas → Full screen without edit affordances active;
- Full screen → Editing → Done → Full screen → Canvas;
- Add opens existing happening palette;
- drag persists after leaving and reopening Editing;
- Remix preserves element positions and persists after relaunch.

## 17. Reference implementation constraints

- Preserve unrelated uncommitted work in `MainTabView`, `GalleryView`, energy logic, rendering and tests.
- No schema or migration change is required.
- No new persisted presentation-state key is required; Canvas/Data/FullScreen/Editing are transient UI state.
- Existing canvas JSON remains compatible. Remix writes the existing mutable `CanvasElement` fields only.
- Existing coach marks must be updated so the expand anchor targets the new bottom-left circle and the Add anchor targets the yellow bottom-right button.
