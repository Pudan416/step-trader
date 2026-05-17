# CanvasLab — Spec & Build Prompt

Промпт для создания отдельного iOS-приложения **CanvasLab** — изолированной тестовой площадки для канвас-механик из проекта `Steps4`. Никаких HealthKit / Supabase / Family Controls / подписок — только канвас, контролы и пресеты для быстрых экспериментов с формами, цветами, градиентами и Metal-оверлеями.

> Эталонные источники: `CanvasPalettes.md` (цвета), `CanvasBodyMindHeart.md` (геометрия и моушн), плюс реальные файлы `StepsTrader/Models/`, `StepsTrader/Views/`, `StepsTrader/Metal/`. Все формулы ниже сверены с актуальной кодовой базой Steps4.

---

## 0. Цель и не-цели

**Цель:** standalone SwiftUI-приложение под iOS 17+, в котором можно за 1 секунду переключить палитру / стиль градиента / оверлей / пресет сцены и сразу увидеть результат. Полигон для итерации над визуалом без всех остальных систем Steps4.

**Не-цели:**
- НЕТ: HealthKit, Family Controls, Supabase, StoreKit, App Groups, Widgets, Intents, Live Activities.
- НЕТ: Onboarding, login, settings persistence в облако.
- НЕТ: каталог PNG ассетов (mind/heart процедурные, body тоже).
- НЕТ: локализации, аналитики, логирования за пределы `print`.

---

## 1. Архитектура

- SwiftUI + лёгкий MVVM. Один `@MainActor LabAppModel: ObservableObject` хранит всё мутируемое состояние.
- Структура папок:
  ```
  CanvasLab/
    Models/          CanvasElement, ProceduralShapeGenerator, Types,
                     CanvasOverlayStyle
    Rendering/       EnergyGradientBackground, GenerativeCanvasView
    Metal/           ShaderParkShader.metal, SpotlightShader.metal,
                     SmudgeShaders.metal,
                     MetalShaderParkRenderer.swift, MetalSmudgeRenderer.swift
    Overlays/        CanvasAnimationOverlay, ShaderParkOverlayView,
                     SmudgeCanvasView
    UI/              ContentView, ControlsPanel
    Utilities/       SeededRNG, Color+Hex
    Resources/       Assets.xcassets (grain 1, AccentColor, AppIcon)
  ```
- Persistence: только `@AppStorage` standard (без App Group). Вообще можно не персистить — все настройки в `@Published` модели.

---

## 2. Цветовые палитры

### 2.1 Активити-палитра (16 свотчей, 4×4)

`enum CanvasColorPalette { static let paletteHex: [String] = [...] }`:

```
#C3143B  #9BB6E0  #A7BF50  #C3D7A3
#01B6C4  #7652AF  #F68D0C  #2C2E4D
#796C3C  #FFD369  #49484D  #C7E0D8
#222831  #955530  #FEAAC2  #EBE4D7
```

Кнопка "random color" в UI берёт случайный hex отсюда.

### 2.2 Дефолтные цвета "дня"

```swift
sleepColorHex = "#000000"
stepsColorHex = "#FED415"
```

### 2.3 7 палитр энергетического градиента (`GradientPalette`)

`enum GradientPalette: String, CaseIterable { warmSunset, ocean, aurora, dusk, dawn, ember, horizon }`.

Каждая палитра — `Palette(bright, warm, cool, dark, daylightBase)`:

| Scheme | bright | warm | cool | dark | daylightBase |
|---|---|---|---|---|---|
| `warmSunset` (Sunset) | `#FFBF65` | `#FD8973` | `#003A6C` | `#002646` | `#F2DCC8` |
| `ocean` | `#7FDBDA` | `#3A9FBF` | `#1A4B6E` | `#0B1E33` | `#E0F0F5` |
| `aurora` | `#C4B5FD` | `#7C6FBF` | `#1F6E5C` | `#0F1B2D` | `#EDE8F8` |
| `dusk` | `#EEDDC9` | `#C0AC98` | `#5E7282` | `#384856` | `#F2EAE0` |
| `dawn` | `#EBBFC8` | `#B87A92` | `#4A3568` | `#181430` | `#F5E2E8` |
| `ember` | `#F07838` | `#D04428` | `#2E1858` | `#0C0A22` | `#F5DDD0` |
| `horizon` | `#D0A440` | `#2898A8` | `#105868` | `#0A2832` | `#E4EDE0` |

Legacy raw `roseGarden` → `.ocean`, любой неизвестный → `.warmSunset`.

### 2.4 Random pool превью (`RandomPalette`)

Девять "тёплых" и девять "холодных" sRGB-цветов (R, G, B в 0…1) для процедурных превью форм (тинт PNG-ассета).

**Warm pool:**
```
(0.92, 0.78, 0.42)   (0.90, 0.58, 0.35)   (0.88, 0.48, 0.55)   (0.82, 0.42, 0.62)
(0.75, 0.35, 0.48)   (0.90, 0.70, 0.48)   (0.80, 0.52, 0.60)   (0.88, 0.55, 0.65)
(0.78, 0.85, 0.55)
```

**Cool pool:**
```
(0.62, 0.42, 0.82)   (0.50, 0.42, 0.85)   (0.40, 0.55, 0.85)   (0.38, 0.65, 0.82)
(0.38, 0.75, 0.65)   (0.42, 0.78, 0.55)   (0.48, 0.72, 0.75)   (0.55, 0.75, 0.48)
(0.40, 0.60, 0.50)
```

`randomColors(seed:count:)` шафлит пулы и чередует warm/cool для outer/center.

### 2.5 Heart gradient stops (HSB-jitter от базового hex)

`heartGradientColors(seed, baseHex)` → 3 или 4 цвета:
- hue ±0.12, saturation −0.15…+0.10, brightness −0.10…+0.15
- clamp `S` в `[0.15, 1]`, `B` в `[0.30, 1]`
- opacity первой остановки `0.75`, остальные `0.45…0.70`

### 2.6 Spotlight (Metal heart)

3 цвета из `CanvasColorPalette` минус `#222831` (исключаем самый тёмный, чтобы луч читался). Гарантированно различные индексы (см. `ProceduralShapeGenerator.spotlightColors`).

---

## 3. Стили градиента фона (`GradientStyle`)

`enum GradientStyle { radial, linear, radialReversed, linearReversed, organic }`. Все рендерятся внутри `EnergyGradientRenderer`.

### 3.1 Модель прозрачностей

**Вход:** `stepsPoints (0…20)`, `sleepPoints (0…20)`, `hasStepsData: Bool`, `hasSleepData: Bool`, `isDaylight: Bool`.

**Нормализация:** `Ss = smoothstep(stepsPoints/20)`, `Ls = smoothstep(sleepPoints/20)`, где `smoothstep(x) = x²(3 − 2x)` после clamp в `[0,1]`.

**Радиальные локации полос:**
```
stepsOnly  = hasStepsData && !hasSleepData
goldShare  = stepsOnly ? Ss * 0.42 : Ss * 0.35
coralShare = stepsOnly ? 0.38       : 0.30
navyShare  = stepsOnly ? max(Ls*0.20, 0.16) : max(Ls*0.20, 0.08)

goldLoc  = goldShare
coralLoc = goldLoc + coralShare
navyLoc  = coralLoc + navyShare
```

**Daylight ветка** (всё прижато к ~0.40):
```
gold  = hasStepsData ? 0.40 : 0
coral = 0.45
navy  = 0.40
night = 0.40
glow  = hasStepsData ? 0.30 : 0.20
```

**Night ветка** (полная формула):
```swift
goldOp = !hasStepsData ? 0 : lerp(0.55, 0.95, Ss)

coralOp =
  (!hasStepsData && !hasSleepData) ? 0.68 :
  (hasSleepData  && !hasStepsData) ? lerp(0.35, 0.50, 1 - Ls) :
  (hasStepsData  && !hasSleepData) ? lerp(0.55, 0.85, Ss) :
                                      lerp(0.55, 0.85, Ss) * lerp(1.00, 0.92, Ls)

navyOp =
  (!hasStepsData && !hasSleepData) ? 0.42 :
  (hasSleepData  && !hasStepsData) ? lerp(0.42, 0.55, Ls) :
  (hasStepsData  && !hasSleepData) ? lerp(0.08, 0.14, Ss) :
                                      lerp(0.28, 0.48, Ls)

nightOp = !hasSleepData ? (!hasStepsData ? 0.08 : 0.03) : lerp(0.28, 0.45, Ls)
if hasSleepData && !hasStepsData { nightOp = lerp(0.40, 0.55, Ls) }

glowOp =
  (!hasStepsData && !hasSleepData) ? 0.35 :
  (hasSleepData  && !hasStepsData) ? 0.25 :
  (hasStepsData  && !hasSleepData) ? lerp(0.50, 0.80, Ss) :
                                      lerp(0.30, 0.60, Ss) * lerp(1.00, 0.85, Ls)
```

### 3.2 Рендеринг

`EnergyGradientRenderer.draw(context, size, opacities, baseColor, gradientStyle, colorPalette)`:

1. Заливка `rect` цветом `baseColor` (`isDaylight ? pal.daylightBase : pal.dark`).
2. Основной gradient stops:
   ```
   (bright × gold,  loc = 0.00)
   (warm   × coral, loc = goldLoc)
   (cool   × navy,  loc = coralLoc)
   (dark   × night, loc = navyLoc)
   (dark   × night, loc = 1.00)
   ```
3. По стилю:
   - **radial** — `.radialGradient(stops, center, 0, maxReach * 0.85)`, плюс вторичный glow: `.radialGradient([bright × glow*0.6, warm × glow*0.25, .clear], center, 0, dim*0.5)`.
   - **radialReversed** — реверс stops, плюс ring glow `[clear, warm × glow*0.2, bright × glow*0.5]` радиусом `maxReach*0.85`.
   - **linear** — снизу вверх, stops инвертированы по location, glow в нижних 40% высоты.
   - **linearReversed** — сверху вниз, glow в верхних 40%.
   - **organic** — фон + 8 кругов с `blendMode = .plusLighter` (см. ниже).

### 3.3 Organic blobs (для `organic` стиля)

`organicBlobs(opacities, seed = daySeed, palette)` — 8 шт, по 2 на роль (`dark`, `cool`, `warm`, `bright`):

```
2× dark:   x,y ∈ 0…1,        radius ∈ 0.5…0.8 × maxReach, opacity = night × random(0.6…1.0)
2× cool:   x,y ∈ 0.05…0.95,  radius ∈ 0.35…0.6,           opacity = navy  × random(0.5…0.9)
2× warm:   x,y ∈ 0.10…0.90,  radius ∈ 0.25…0.5,           opacity = coral × random(0.4…0.8)
2× bright: x,y ∈ 0.15…0.85,  radius ∈ 0.20…0.4,           opacity = gold  × random(0.5…0.9)
```

Для каждого blob — `radialGradient([color×opacity, color×opacity*0.4, .clear])` в эллипсе `[cx-r, cy-r, 2r]` с `blendMode = .plusLighter`. `daySeed = ordinality(.day, in: .era)`. В Lab — кнопка "reroll seed".

### 3.4 Вспомогательное

- Поверх градиента — `Image("grain 1")` на 0.4 opacity с `.blendMode(.overlay)` (тумблер в UI).
- Анимация значений stepsPoints/sleepPoints — через `Animatable` модификатор, `.easeInOut(0.8)`. **Обязательно:** интерполировать `Ss/Ls` покадрово, не перерисовывать только по конечному значению.

---

## 4. Канвас-элементы (`CanvasElement`)

Категории: `body`, `mind`, `heart`. У каждой — `kind`: body/mind = `.circle`, heart = `.ray`.

### 4.1 Поля
```
id, kind, category, optionId, label, hexColor
size: CGFloat              // 0…1, нормировано к min(w, h)
basePosition: CGPoint      // (x, y) ∈ 0…1
phaseOffset: 0…2π
driftSpeed: 0.08…0.20
driftAmplitude: 0.01…0.03
pulseFrequency: body 0.08…0.20, mind/heart 0.30…0.80
pulseAmplitude: 0.01…0.03
rotationSpeed: 3…10        (только heart sweep)
opacity: body 0.20…0.45, mind/heart 0.35…0.75
shapeSeed: UInt64
userSize: CGFloat?         (overrides size после pinch)
userRotation: Double       (radians, после move)
activityCount: Int?        (driver сложности body)
```

### 4.2 Spawn-диапазоны размеров
```
body:  0.16…0.32
mind:  0.04…0.48   (XS…XL — самый широкий разброс)
heart: 0.20…0.28
```

### 4.3 Размещение

`findOpenPosition`: margin `0.12` от краёв, idealDistance `0.15` между элементами; если тесно — relax до `max(0.08, 0.15 − N×0.01)`; финальный fallback — кандидат, максимизирующий минимальное расстояние.

### 4.4 Reroll (кнопка "dice" в UI)

Перегенерировать `shapeSeed`, `size`, `phaseOffset`, `driftSpeed`. Очистить `userSize`. `lastEditedAt = Date()`. Цвет рероллится отдельно (вне модели — из `paletteHex`).

### 4.5 Spawn-анимация

Кубический ease-out за 0.8 сек: `1 − (1 − age/0.8)^3`. `scale = 0.3 + 0.7 * spawn`, `opacity = spawn`. Уже встроено в `drawElement`.

---

## 5. Процедурные формы (`ProceduralShapeGenerator`)

### 5.1 Body — organic blob

- 20 точек по углам, value-noise table 32 элемента (детерминированно от `seed`, кешировать `[seed: [[Double]]]`, лимит кеша 24 seed'а).
- 3 октавы, базовая частота `3.0`, амплитуда `0.12 + complexity * 0.18`.
- Time offset `time * 0.05` (медленное "дыхание" контура).
- Точки соединять `smoothClosedPath` (quadCurve через midpoints соседних вершин).

### 5.2 Mind — `RectMorphFrame` (D6 snowflake morph)

- Симметричная "снежинка": `folds ∈ 3…8` (фиксировано на seed через `seed ^ 0xF01D`).
- Каждые `morphDuration = 12s` морф к новой случайной фигуре, ease `(1 − cos(πt))/2`.
- 64 точки (`rectMorphN`). 1–2 гармоники (`mult ∈ 1…2`, `amp ∈ 0.1…0.4`).
- Цвет — `lerp` между двумя hex из `CanvasColorPalette` по `colorIdx`.
- **Trail:** 10 ghost-фреймов (`rectMorphTrailLen`), шаг `0.8s` (`rectMorphTrailSpacing`), peak alpha `0.35` (`rectMorphTrailPeakAlpha`).

### 5.3 Heart — два варианта

1. **Procedural rays (`heartRays`):**
   - 3–4 веера от origin к direction, длина `reach × 0.7…1.0`.
   - Базовая полуширина `length × 0.10…0.18`.
   - Средняя точка на `t = 0.45` с шириной `0.45 × baseHalfWidth`.
   - Wobble: `sin(time*0.4 + phase) * length * 0.015`.
   - Каждый луч — bezier-веер из 4 quadCurves (baseL → midL → tip → midR → baseR).

2. **Metal spotlight (`SpotlightShader.metal`):**
   - `.layerEffect(ShaderLibrary.spotlightEffect)` на белом прямоугольнике 256×256.
   - 3 цвета `(near, mid, far)` из `spotlightColors(seed:)`.
   - Шейдер ниже в секции 7.3.

### 5.4 Metaball merge (для близких body)

`metaballPath(blobs, in: rect, gridResolution: 50, threshold: 1.0)`:
- Скалярное поле `Σ rᵢ²/max(distSq, 1)`.
- Marching squares 16 конфигураций → segments → `connectSegmentsIntoPath` (epsilon `2.0`) → `smoothClosedPath`.

В реальном рендере используется `CGPath.union()` процедурных blobpath'ов (быстрее). `metaballPath` — backup / референс.

---

## 6. Геометрия и моушн (`GenerativeCanvasView`)

### 6.1 Render order

1. Background gradient (если `showsBackgroundGradient`).
2. **Pass 1:** все `mind` (рендерятся "под" грануляцией).
3. **Pass 2:** body clusters → solo body → heart.

Внутри каждого пасса circle-элементы сортируются по `size` desc.

### 6.2 Body — мягкий blob

- `circleCenter = basePosition * (w, h) + wobble`:
  ```
  wobbleX = sin(t*0.015 + φ)         * w*0.003*amp
          + sin(t*0.008 + φ*2.3)     * w*0.002*amp
  wobbleY = cos(t*0.013 + φ*1.3)     * h*0.003*amp
          + cos(t*0.009 + φ*0.7)     * h*0.002*amp
  ```
- `pulse = 1 + sin(t*(0.3 + pulseFreq*0.3) + φ) * 0.02 * ampScale`
- `radius = effectiveSize * min(w, h) * 1.05 * pulse`
- Поворот: `phaseOffset + userRotation`
- Заливка: `clip(to: bodyPath)` + `radialGradient(rimGrad)` где
  ```
  rimGrad stops:
    (color × 0.12, 0)
    (color × 0.10, edgeLoc)         // edgeLoc = (r-40)/r
    (color × 0.35, edgeLoc + (1-edgeLoc)*0.5)
    (color × 0.55, 1.0)
  ```
  + `stroke(bodyPath, color×0.65, lineWidth 1.5, round)`.
- Cluster merge: дистанция `< (r1 + r2) * 1.6`.

### 6.3 Mind — Lissajous-дрейф + snowflake morph

- `speed = 0.03 + driftSpeed * 0.06`
- `MindFrequencyProfile` (детерминируется `phaseOffset`):
  ```
  s = phase * 1000
  fx1 = 1.0  + sin(s*0.11)*0.15
  fx2 = 2.2  + sin(s*0.23)*0.30
  fx3 = 3.8  + sin(s*0.37)*0.50
  fy1 = 0.85 + cos(s*0.17)*0.15
  fy2 = 2.0  + cos(s*0.31)*0.30
  fy3 = 3.5  + cos(s*0.43)*0.50
  ```
- Envelope: `env = 0.7 + 0.3 * sin(t*speed*0.13 + φ*3.7) * sin(t*speed*0.07 + φ*1.3)`
- Home: `(basePos.x + sin(t*speed*0.05 + φ)*0.12, basePos.y + cos(t*speed*0.04 + φ*1.3)*0.12)`
- Полная позиция:
  ```
  nx = hx + sin(t*speed*fx1 + φ)        * 0.24*amp*env
          + sin(t*speed*fx2 + φ*2.3)    * 0.09*amp*env
          + sin(t*speed*fx3 + φ*4.1)    * 0.03*amp
  ny = hy + cos(t*speed*fy1 + φ*1.7)    * 0.22*amp*env
          + cos(t*speed*fy2 + φ*3.1)    * 0.08*amp*env
          + cos(t*speed*fy3 + φ*5.3)    * 0.03*amp
  ```
- Clamp с margin `0.06` (мягко, через `edgeWidth = 0.04`, чтобы скорость не схлопывалась в углах — нужно для непрерывности `atan2(vy, vx)`).
- `radius = effectiveSize * min(w, h) * 1.1 * pulse` (легче body breath).
- Render: каждый кадр — `rectMorphFrame(seed, time, in: rect)` + 10 ghost-trails.
- Stroke: `lineWidth 1.2`, round; opacity = `(0.92 + breathe*0.04) * (1 − decay*0.3)`.

### 6.4 Heart — луч на центр

- `heartCenter = basePosition * (w, h) + wobble` (~0.4% вместо 0.3% для body).
- `radius = effectiveSize * min(w, h) * 2.2` (намного крупнее).
- `breathe = 0.80 + sin(t*pulseFreq*0.5 + φ)*0.18 + sin(t*pulseFreq*0.17 + φ*1.7)*0.08`.
- `inwardAngle = atan2(canvasCenter.y − anchor.y, canvasCenter.x − anchor.x)`.
- `rotation = inwardAngle + 270° + userRotation + sweepAngle`, где
  ```
  sweepRange = (35 + rotationSpeed*0.6) * ampScale
  sweepSpeed = 0.025 + driftSpeed*0.015
  sweep = sin(t*sweepSpeed + φ*2.1)*sweepRange
        + sin(t*sweepSpeed*0.37 + φ*0.8)*sweepRange*0.3
  ```
- Render: либо `procedural heartRays` (заливка `heartGradientColors`), либо Metal `spotlightEffect` (см. 7.3) — переключатель в UI.
- Layer opacity: `(0.7 + breathe*0.3) * (1 − decay*0.4)`.

### 6.5 Decay (тумблер 0…1 в UI)

- `0…0.25` — полный цвет.
- `0.25…0.75` — `desaturated(by: t * 0.7)` где `t = (decay - 0.25) / 0.5`.
- `0.75…1.0` — `desaturated(by: 0.7 + t * 0.25)` где `t = (decay - 0.75) / 0.25`.

### 6.6 Лейблы

Текст 11pt, bold, rounded, uppercase. Если `showsOutlinedLabels` — 4 диагональных smaller copies на 0.4 opacity (halo).

### 6.7 Blend mode

По яркости фона: `dark (b < 0.5) → .plusLighter`, иначе `.normal`.

---

## 7. Metal-оверлеи (`CanvasOverlayStyle`)

Enum: `none`, `smudge`, `cosmic`. Persist через `@AppStorage("canvasOverlayStyle")`.

### 7.1 Cosmic — `ShaderParkShader.metal` (FBM domain warp + finger drag)

Полноэкранный transparent quad, `MTKView` paused в idle. Touch wakes.

**Params struct** (`ShaderParkParams`): `resolution`, `time`, `click`, `touch`, `velocity`, `hueOffset`, `ringFreq`.

**Что делает шейдер:**
1. UV aspect-corrected.
2. Touch warp: `falloff = exp(-dist²/sigma²)`, `sigma = 0.55`. `live = max(click, saturate(speed*5))`. `warp = falloff * live`.
3. Displacement:
   - радиальный `−toTouch/dist * warp * 0.30`,
   - тангенциальный (90°) `* 0.45`,
   - velocity drag `* 6.0`.
4. Sample warped field: `samplePos = float3((uv + disp) * 0.85, time*0.055 + hueOffset)`. 5-octave value noise, FBM, потом ещё один FBM поверх (Inigo Quilez warping).
5. Cosmic palette (cosine, IQ): `a + b*cos(2π*(c*t + d))` с
   ```
   a = (0.42, 0.38, 0.52)
   b = (0.32, 0.28, 0.42)
   c = (0.95, 1.00, 0.85)
   d = (0.05, 0.20, 0.45)
   ```
6. Mix to inky base `(0.06, 0.05, 0.09)` на 0.78.
7. Alpha: `0.55 * smoothstep(0, 1, live) + 0.18 * warp`. Idle = полностью прозрачно.

**Renderer:**
- `attack 0.14`, `decay 0.06`, velocity decay `0.92/frame`.
- Park view (`isPaused = true`) если `click < 0.005 && |v| < 0.0008 && clickTarget == 0`.
- `contentScaleFactor = min(UIScreen.main.scale, 1.25)` — экономия GPU.
- Premultiplied alpha blending: `srcOne / dstOneMinusSrcAlpha` для RGB и alpha.

### 7.2 Smudge — `SmudgeShaders.metal` (paint distortion + ripples)

Двойная ping-pong текстура:
- `interactiveA/B` — текущий smudged frame.
- `ageA/B` — single-channel age field (для возврата к base).
- `baseTexture` — снимок исходного канваса.

**Compute kernels:**
- `smudgeKernel`: для каждой точки в радиусе brush-сегмента — `falloff = (1 − dist/radius)²`, `sample = current − dragFactor * direction`, `result = mix(current, sampled, strength*falloff)`. Age сбрасывается пропорционально falloff.
- `relaxDiffuseKernel`: 4-tap blur (N+S+E+W)/4 + `mix(diffused, base, relax)` где `relax = saturate(baseReturn * (1 + age*ageAccel))`.
- `copyTextureKernel` для ping-pong.

**Display fragment:**
- Ageful smudge visibility: `ageFade = saturate(1 − age/3)`, `smudgeColor = saturate(interactive + (interactive − base)*5 + ageFade*0.07)`, `alpha = ageFade*0.55`.
- Ripples (до 5 active): main ring + 2 echo (gap `2.5×width`, `4.5×width`), Gaussian profile, `timeFade = (1 − elapsed/duration)^1.5`, `spatial = exp(−dist*decay)`. `wave = (mainRing + 0.4*echo1 + 0.15*echo2) * timeFade * spatial`, displacement по `dir`.
- Combine: `max(smudgeAlpha, rippleAlpha)` wins; финал `* globalFade`.

### 7.3 Spotlight (heart) — `SpotlightShader.metal` (`.layerEffect`)

Stitchable `half4` fragment. 1:1 порт с web-прототипа (`web/prototypes/body-blob-port.html`). Ключевые формулы:

```
lightPos  = (-0.5*aspect, -0.5)
aim       = 1.15 + 0.55*sin(time*0.55)
dir       = (sin(aim), cos(aim))
coneAngle = mix(30°, 110°, 0.5 + 0.5*sin(time*0.45))
softness  = 0.22 + 0.18 * ((coneAngle - 30) / 80)

att   = 1 / (1.35 + 5.5*dist² + 1.2*dist)
inner = cos(coneAngle * 0.5 * π / 180)
cone  = smoothstep(inner - softness, inner, dot(L, dirN))
light = cone * att

// 3-stop ramp по tRad = pow(smoothstep(0.04, 0.68, dist), 0.82)
// stops: 0.0 → near, 0.3 → mid, 0.92 → far
coreMul = mix(0.62, 1.0, smoothstep(0, 0.26, dist))
w       = pow(clamp(light), 1.12) * coreMul * 1.35

// edge fade — spherical, 0.6…1.0
radialDist = length(uv - 0.5) * 2.0
edgeFade   = 1 - smoothstep(0.6, 1.0, radialDist)
w *= edgeFade

return half4(color * w, w)   // premultiplied
```

**Критично:** `#include <SwiftUI/SwiftUI.h>` обязательно для `SwiftUI::Layer` параметра.

---

## 8. UI контролы (правая/нижняя панель)

Минимальный набор для тестирования:

1. **Пресеты сцены:** "Empty", "1×Body", "1×Mind", "1×Heart", "Mixed (3+3+3)", "Crowded (15)", "Body cluster (5 close)".
2. **Палитра градиента:** segmented по 7 кейсам `GradientPalette`.
3. **Стиль градиента:** segmented по 5 кейсам `GradientStyle`.
4. **Оверлей:** picker `none / smudge / cosmic`.
5. **Theme:** `daylight / night` (бьёт на `isDaylight` и blend mode).
6. **Слайдеры:** `stepsPoints 0…20`, `sleepPoints 0…20`, тумблеры `hasStepsData`, `hasSleepData`.
7. **Слайдер `decayNorm 0…1`** + **`timeScale 0…1.5`** (затухание/ускорение моушна).
8. **Тумблеры:** `showLabelsOnCanvas`, `showsOutlinedLabels`, `showsBackgroundGradient`, `grain overlay`.
9. **Heart renderer:** procedural / metal spotlight.
10. **Spawn buttons:** "+ Body", "+ Mind", "+ Heart" (random цвет из `paletteHex`).
11. **Per-element actions:** tap → highlight → "Reroll" / "Delete" / "Random color".
12. **Random palette seed reroll** (для organic).
13. **FPS counter** (overlay в корнере).

---

## 9. Технические детали

- **Canvas size:** `canonicalPortraitSize` — фикс через `UIScreen.main.bounds.size` (portrait), хранить в lock-guarded static. В Lab можно упростить.
- **Tick rate:** `TimelineView(.animation(minimumInterval: 1.0/20.0))` для основного канваса (20 FPS достаточно). Metal оверлеи — 60 FPS, но idle-park.
- **Caches** (в `RenderCache`):
  - sortedOrder, sortedIndexMap (signature по `(id, kind, size)`),
  - mind position cache (per-frame),
  - trail frames (per-tick, 0.8s),
  - cluster merged path (refresh когда центр уходит >2pt).
- **Color hex helpers:** `Color(hex:)` поддерживает 3/4/6/8 chars (ARGB shortcode). `toHex()` через `UIColor.getRed/...` с clamp `[0, 1]` (важно для P3).
- **Lerp colors:** в sRGB, не в HSB.
- **`desaturated(by:)`:** через `UIColor(hue:saturation:brightness:alpha:)`, остаться в UIColor чтоб не клиппить wide-gamut.

---

## 10. Файлы из Steps4 для копирования

(Они уже самодостаточны или близко к этому):

- `StepsTrader/Models/CanvasElement.swift` (`Codable` оставить — пригодится для пресетов).
- `StepsTrader/Models/ProceduralShapeGenerator.swift`
- `StepsTrader/Models/CanvasOverlayStyle.swift`
- `StepsTrader/Utilities/SeededRNG.swift`
- `StepsTrader/Views/Components/EnergyGradientBackground.swift` (убрать `AppLogger` / `SharedKeys`, заменить `@AppStorage(SharedKeys.x, store: UserDefaults.stepsTrader())` на `@AppStorage("x")`).
- `StepsTrader/Views/GenerativeCanvasView.swift` (убрать `AppColors` → заменить на свои константы).
- `StepsTrader/Metal/ShaderParkShader.metal`, `MetalShaderParkRenderer.swift`, `Views/Components/ShaderParkOverlayView.swift`.
- `StepsTrader/Metal/SpotlightShader.metal`.
- `StepsTrader/Metal/SmudgeShaders.metal`, `MetalSmudgeRenderer.swift`, `Views/Components/SmudgeCanvasView.swift`.
- `StepsTrader/Views/Components/CanvasAnimationOverlay.swift`.

Из `Types.swift` нужно вытащить только `GradientPalette`, `GradientStyle`, `EnergyCategory`, shape style enums (`BodyShapeStyle`, `MindShapeStyle`, `HeartShapeStyle` — для будущих новых форм). `AppTheme` упростить до `daylight | night`.

---

## 11. Стартовый скелет

### `LabAppModel.swift`

```swift
import SwiftUI

@MainActor
final class LabAppModel: ObservableObject {
    @Published var elements: [CanvasElement] = []
    @Published var stepsPoints: Int = 14
    @Published var sleepPoints: Int = 12
    @Published var hasStepsData: Bool = true
    @Published var hasSleepData: Bool = true

    @Published var gradientPalette: GradientPalette = .warmSunset
    @Published var gradientStyle: GradientStyle = .radial
    @Published var overlayStyle: CanvasOverlayStyle = .none
    @Published var isDaylight: Bool = false

    @Published var decayNorm: Double = 0
    @Published var timeScale: Double = 1.0
    @Published var showLabels: Bool = true
    @Published var showsOutlinedLabels: Bool = true
    @Published var showsBackgroundGradient: Bool = true
    @Published var showGrain: Bool = true
    @Published var heartUsesMetal: Bool = true

    func spawn(_ category: EnergyCategory) {
        let color = CanvasColorPalette.paletteHex.randomElement()!
        let label = category.rawValue.capitalized
        elements.append(.spawn(
            optionId: "lab_\(UUID().uuidString.prefix(6))",
            category: category,
            color: color,
            label: label,
            existingElements: elements
        ))
    }

    func reset() { elements.removeAll() }

    func loadPreset(_ preset: ScenePreset) {
        elements.removeAll()
        for (cat, n) in preset.spawn {
            for _ in 0..<n { spawn(cat) }
        }
    }
}

enum EnergyCategory: String, Codable, CaseIterable {
    case body, mind, heart
}

struct ScenePreset: Identifiable, Hashable {
    let id = UUID()
    let name: String
    let spawn: [(EnergyCategory, Int)]
    static let all: [ScenePreset] = [
        .init(name: "Empty",        spawn: []),
        .init(name: "1×Body",       spawn: [(.body, 1)]),
        .init(name: "1×Mind",       spawn: [(.mind, 1)]),
        .init(name: "1×Heart",      spawn: [(.heart, 1)]),
        .init(name: "Mixed 3+3+3",  spawn: [(.body, 3), (.mind, 3), (.heart, 3)]),
        .init(name: "Crowded 15",   spawn: [(.body, 5), (.mind, 5), (.heart, 5)]),
        .init(name: "Body Cluster", spawn: [(.body, 5)]),
    ]
    static func == (l: ScenePreset, r: ScenePreset) -> Bool { l.id == r.id }
    func hash(into h: inout Hasher) { h.combine(id) }
}
```

### `ContentView.swift`

```swift
import SwiftUI

struct ContentView: View {
    @StateObject private var model = LabAppModel()

    var body: some View {
        GeometryReader { geo in
            VStack(spacing: 0) {
                canvasArea
                    .frame(height: geo.size.height * 0.6)
                    .clipped()
                ControlsPanel(model: model)
                    .frame(height: geo.size.height * 0.4)
                    .background(.ultraThinMaterial)
            }
        }
        .preferredColorScheme(model.isDaylight ? .light : .dark)
    }

    private var canvasArea: some View {
        ZStack {
            EnergyGradientBackground(
                stepsPoints: model.stepsPoints,
                sleepPoints: model.sleepPoints,
                hasStepsData: model.hasStepsData,
                hasSleepData: model.hasSleepData,
                showGrain: model.showGrain,
                gradientStyleOverride: model.gradientStyle.rawValue,
                gradientPaletteOverride: model.gradientPalette.rawValue
            )

            GenerativeCanvasView(
                elements: model.elements,
                sleepPoints: model.sleepPoints,
                stepsPoints: model.stepsPoints,
                sleepColor: Color(hex: "#000000"),
                stepsColor: Color(hex: "#FED415"),
                decayNorm: model.decayNorm,
                backgroundColor: model.isDaylight ? .white : .black,
                showLabelsOnCanvas: model.showLabels,
                showsOutlinedLabels: model.showsOutlinedLabels,
                showsBackgroundGradient: false,
                hasStepsData: model.hasStepsData,
                hasSleepData: model.hasSleepData,
                timeScale: model.timeScale
            )

            CanvasAnimationOverlay(
                elements: model.elements,
                sleepPoints: model.sleepPoints,
                stepsPoints: model.stepsPoints,
                sleepColor: Color(hex: "#000000"),
                stepsColor: Color(hex: "#FED415"),
                decayNorm: model.decayNorm,
                backgroundColor: model.isDaylight ? .white : .black,
                hasStepsData: model.hasStepsData,
                hasSleepData: model.hasSleepData
            )
        }
    }
}
```

### `ControlsPanel.swift` (скелет)

```swift
import SwiftUI

struct ControlsPanel: View {
    @ObservedObject var model: LabAppModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                presetRow
                paletteRow
                stylePicker
                overlayPicker
                themeToggle
                slidersGroup
                togglesGroup
                spawnButtons
                elementList
            }
            .padding()
        }
    }

    private var presetRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack {
                ForEach(ScenePreset.all) { p in
                    Button(p.name) { model.loadPreset(p) }
                        .buttonStyle(.bordered)
                }
            }
        }
    }

    private var paletteRow: some View {
        Picker("Palette", selection: $model.gradientPalette) {
            ForEach(GradientPalette.allCases, id: \.self) { p in
                Text(p.displayName).tag(p)
            }
        }.pickerStyle(.segmented)
    }

    private var stylePicker: some View {
        Picker("Style", selection: $model.gradientStyle) {
            ForEach(GradientStyle.allCases, id: \.self) { s in
                Text(s.displayName).tag(s)
            }
        }.pickerStyle(.segmented)
    }

    private var overlayPicker: some View {
        Picker("Overlay", selection: $model.overlayStyle) {
            ForEach(CanvasOverlayStyle.allCases) { o in
                Text(o.displayName).tag(o)
            }
        }.pickerStyle(.segmented)
    }

    private var themeToggle: some View {
        Toggle("Daylight", isOn: $model.isDaylight)
    }

    private var slidersGroup: some View {
        VStack(alignment: .leading, spacing: 6) {
            slider("Steps", value: $model.stepsPoints, range: 0...20)
            slider("Sleep", value: $model.sleepPoints, range: 0...20)
            HStack {
                Text("Decay \(model.decayNorm, specifier: "%.2f")")
                Slider(value: $model.decayNorm, in: 0...1)
            }
            HStack {
                Text("Time ×\(model.timeScale, specifier: "%.2f")")
                Slider(value: $model.timeScale, in: 0...1.5)
            }
        }
    }

    private var togglesGroup: some View {
        VStack(alignment: .leading) {
            Toggle("hasStepsData", isOn: $model.hasStepsData)
            Toggle("hasSleepData", isOn: $model.hasSleepData)
            Toggle("Labels", isOn: $model.showLabels)
            Toggle("Outlined labels", isOn: $model.showsOutlinedLabels)
            Toggle("Grain", isOn: $model.showGrain)
            Toggle("Heart uses Metal", isOn: $model.heartUsesMetal)
        }
    }

    private var spawnButtons: some View {
        HStack {
            Button("+ Body") { model.spawn(.body) }
            Button("+ Mind") { model.spawn(.mind) }
            Button("+ Heart") { model.spawn(.heart) }
            Spacer()
            Button("Reset", role: .destructive) { model.reset() }
        }.buttonStyle(.borderedProminent)
    }

    private var elementList: some View {
        VStack(alignment: .leading) {
            ForEach(model.elements, id: \.id) { e in
                HStack {
                    Circle().fill(Color(hex: e.hexColor)).frame(width: 14, height: 14)
                    Text("\(e.category.rawValue) · size \(String(format: "%.2f", Double(e.size)))")
                        .font(.caption)
                    Spacer()
                    Button("dice") {
                        if let i = model.elements.firstIndex(where: { $0.id == e.id }) {
                            model.elements[i].reroll()
                            model.elements[i].hexColor = CanvasColorPalette.paletteHex.randomElement()!
                        }
                    }
                    Button("×", role: .destructive) {
                        model.elements.removeAll { $0.id == e.id }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func slider(_ title: String, value: Binding<Int>, range: ClosedRange<Int>) -> some View {
        HStack {
            Text("\(title) \(value.wrappedValue)").frame(width: 80, alignment: .leading)
            Slider(
                value: Binding(
                    get: { Double(value.wrappedValue) },
                    set: { value.wrappedValue = Int($0.rounded()) }
                ),
                in: Double(range.lowerBound)...Double(range.upperBound),
                step: 1
            )
        }
    }
}
```

---

## 12. Preview matrix

В каждый файл рендера добавить превьюшки, которые показывают одни и те же сцены — это даёт быстрое A/B при работе над новыми формами.

```swift
#Preview("Empty · Sunset · Radial · Night") { ... }
#Preview("Crowded · Aurora · Organic · Night") { ... }
#Preview("Body Cluster · Ember · Linear · Daylight") { ... }
#Preview("All categories · Ocean · RadialReversed · Cosmic overlay") { ... }
#Preview("Decay 0.0 / 0.5 / 1.0 ladder") { ... }
#Preview("hasStepsData OFF · hasSleepData ON · 20") { ... }
```

Минимум 6 превью на файл — даёт визуальный snapshot grid в Xcode.

---

## 13. Карта зависимостей файлов

```
SeededRNG.swift                  ← Foundation, CoreGraphics

CanvasElement.swift              ← SwiftUI
   ├─ EnergyCategory             ← (определи в Types.swift)
   ├─ ElementKind
   ├─ CanvasColorPalette
   └─ Color+Hex extension

ProceduralShapeGenerator.swift   ← SeededRNG, CanvasColorPalette

Types.swift (урезанный)          ← GradientPalette, GradientStyle,
                                    BodyShapeStyle, MindShapeStyle, HeartShapeStyle

EnergyGradientBackground.swift   ← GradientPalette, GradientStyle, SeededRNG, Color+Hex
   ├─ EnergyGradientRenderer
   └─ EnergyGradientBackground (View)

GenerativeCanvasView.swift       ← CanvasElement, ProceduralShapeGenerator,
                                    EnergyGradientRenderer, Color+Hex

Metal layer:
  ShaderParkShader.metal         ← stand-alone (Metal stdlib only)
  MetalShaderParkRenderer.swift  ← Metal, MetalKit, simd
  ShaderParkOverlayView.swift    ← UIKit, MetalShaderParkRenderer

  SmudgeShaders.metal            ← stand-alone
  MetalSmudgeRenderer.swift      ← Metal, MetalKit, simd
  SmudgeCanvasView.swift         ← UIKit, MetalSmudgeRenderer, CanvasElement

  SpotlightShader.metal          ← #include <SwiftUI/SwiftUI.h> (КРИТИЧНО)
                                    Используется через .layerEffect внутри
                                    GenerativeCanvasView (Canvas symbols)

CanvasOverlayStyle.swift         ← stand-alone enum

CanvasAnimationOverlay.swift     ← CanvasOverlayStyle, SmudgeOverlayView,
                                    ShaderParkOverlayView
```

**Порядок копирования** (без ошибок компиляции):
1. `SeededRNG.swift` + `Color+Hex` extension.
2. `Types.swift` (урезанный — enum'ы).
3. `CanvasElement.swift`.
4. `ProceduralShapeGenerator.swift`.
5. `EnergyGradientBackground.swift`.
6. Все `.metal` файлы + Metal renderers + UIViewRepresentables.
7. `CanvasOverlayStyle.swift` + `CanvasAnimationOverlay.swift`.
8. `GenerativeCanvasView.swift`.
9. `LabAppModel.swift` + `ContentView.swift` + `ControlsPanel.swift`.

---

## 14. Чеклист ассетов

`Assets.xcassets`:

| Asset | Назначение | Источник |
|-------|------------|----------|
| `grain 1` | overlay-зерно поверх градиента (0.4 opacity, `.overlay` blend) | скопировать из `Steps4/Assets.xcassets/grain 1.imageset` |
| `AccentColor` | стандартный | `#FFD369` из палитры подходит |
| `AppIcon` | стандартный | любой |

Если grain не нужен — выкини тумблер `showGrain` и `Image("grain 1")` блок из `EnergyGradientBackground`. Ничего не сломается.

**Никаких `mind_*` / `heart_*` PNG больше не требуется** — рендер целиком процедурный (snowflake morph + spotlight shader). Это упрощает порт по сравнению со старыми версиями Steps4.

---

## 15. Project setup (Xcode)

1. New Project → App → Interface: SwiftUI, Language: Swift, iOS 17+.
2. Bundle ID: `com.you.canvaslab`. Team — твой Apple ID, без капабилитиз.
3. Удали дефолтный `ContentView.swift` (заменишь своим).
4. Создай группы (Folders, не Groups) по структуре из секции 1.
5. Скопируй файлы по порядку из секции 13.
6. Перетащи `grain 1.imageset` в `Assets.xcassets`.
7. **Важно для `.metal` файлов:** убедись, что они находятся в Build Phase → Compile Sources (Xcode добавит автоматически при drag&drop, но если копируешь через `cp` — проверь руками).
8. **Для `SpotlightShader.metal`:** Build Settings → Metal Compiler → Other Metal Compiler Flags = `-fno-fast-math` (опционально, для bit-exactness с web прототипом). И убедись, что `MTL_LANGUAGE_REVISION = Metal3` (iOS 17 default).
9. Build & run.

---

## 16. Performance budget

Что считается приемлемым на iPhone 13+:

| Сцена | Целевые FPS | Реально в Steps4 |
|-------|-------------|-------------------|
| Empty canvas + radial gradient | 60 | 60 |
| 5 mind + 5 body + 5 heart | 20 (TimelineView cap) | 20 |
| 15 body в кластере (worst case `CGPath.union`) | 20 | 18-20 |
| Cosmic overlay над всем выше | 60 (Metal) + 20 (Canvas) | 55-60 |
| Smudge overlay активный (3 пальца) | 60 | 55-60 |
| Organic gradient style (8 plusLighter blobs) | 20 | 20 |

**Если новая форма роняет FPS ниже 18:**
- Профайл через Instruments → Metal System Trace + Time Profiler.
- Чек: точечная сложность шейпа (`bodyPath` 20 точек, `mindPath` 72-120, `rectMorph` 64). Не превышай 200 точек на форму без TimelineView throttle.
- Cluster `CGPath.union` — самое дорогое. Если новая форма часто кластеризуется, кешируй merged path (паттерн уже есть в `RenderCache.clusterCache`).
- Snowflake trail — 10 ghosts × N mind elements. Уже кешировано per-tick (0.8s), не трогай tickIndex логику без причины.

---

## 17. Pitfalls при портировании

1. **`@AppStorage(SharedKeys.xxx, store: UserDefaults.stepsTrader())`** — выкинуть `store:`, использовать стандартный `UserDefaults.standard`. App Groups в Lab не нужен.

2. **`AppLogger.ui.error(...)`** в Metal renderer'ах — заменить на `print(...)` или собственный:
   ```swift
   enum LabLog { static func e(_ s: String) { print("[LAB]", s) } }
   ```

3. **`AppColors.Night.background` / `AppColors.Daylight.background`** — определить локально:
   ```swift
   enum LabColors {
       static let nightBackground    = Color(hex: "#13181B")
       static let daylightBackground = Color(hex: "#F2DCC8")
   }
   ```

4. **`canonicalPortraitSize`** — в Lab можно убрать lock и просто `UIScreen.main.bounds.size` (нет background-actor доступа).

5. **`CanvasImageCatalog.mind/heart`** — больше не используется в актуальном рендере (mind = snowflake, heart = либо procedural rays, либо metal spotlight). Если найдёшь упоминания `assetVariant` в old paths — игнорируй.

6. **`heartDriftPosition` / `heartDriftVelocity`** — мёртвый код в `GenerativeCanvasView`, можно удалить (см. п. 5 в `CanvasBodyMindHeart.md`).

7. **Sample-rate**: основной `TimelineView` идёт на 20 FPS. Если хочешь 60 — поставь `1.0/60.0`, но cluster `CGPath.union` тяжёлая, заметишь jank на iPhone <13. Snowflake morph 64 vertices × N elements тоже не free.

8. **Metal pixel format**: оставь `.bgra8Unorm` — не `.rgba8Unorm`. Если поставишь rgba — overlay будет drawmode mismatch и пропустит alpha.

9. **`#include <SwiftUI/SwiftUI.h>`** в `SpotlightShader.metal` — критично для `SwiftUI::Layer`. Без этого include `.layerEffect` не скомпилит шейдер.

10. **`context.resolveSymbol(id:)`** в `drawRay` — heart-метал работает через `Canvas.symbols`, а не как fullscreen overlay. Не путать с `ShaderParkOverlayView` (который sibling-слой над канвасом).

---

## 18. Как добавить новую форму (главный use-case Lab)

### 18.1 Новая body-форма

1. В `BodyShapeStyle` добавь кейс, например `.smin` (smooth-min metaballs).
2. Добавь второй "путь" в `ProceduralShapeGenerator`:
   ```swift
   static func bodyPathSmin(seed: UInt64, complexity: Double, time: Double, in rect: CGRect) -> Path { ... }
   ```
3. В `LabAppModel` добавь `@Published var bodyShape: BodyShapeStyle = .standard`.
4. В `drawProceduralBody` диспатчи по `e.shapeStyle ?? .standard` (новое опциональное поле в `CanvasElement`, или просто read из model).
5. Picker в ControlsPanel.

### 18.2 Новый Metal-оверлей

1. Создай `MyEffectShader.metal` (vertex + fragment).
2. `MetalMyEffectRenderer: NSObject, MTKViewDelegate` (паттерн как в `MetalShaderParkRenderer`: pipeline, params struct, draw loop, idle parking).
3. `MyEffectOverlayView: UIViewRepresentable` (паттерн как в `ShaderParkOverlayView`).
4. Добавь кейс в `CanvasOverlayStyle` + ветку в `CanvasAnimationOverlay`.
5. Готово — выбирается через picker.

### 18.3 Новая палитра градиента

1. Добавь кейс в `GradientPalette` + локализованный `displayName`.
2. Добавь ветку в `EnergyGradientRenderer.palette(for:)` с пятёркой `(bright, warm, cool, dark, daylightBase)`.
3. Появится в picker автоматически (`ForEach(GradientPalette.allCases)`).

### 18.4 Новый стиль градиента

1. Добавь кейс в `GradientStyle` (например, `.mesh` для `MeshGradient` iOS 18+, или `.conic` для `AngularGradient`).
2. Добавь ветку в `EnergyGradientRenderer.draw(...)` switch (плюс возможный glow-блок ниже).
3. Появится в segmented picker автоматически.

---

## 19. TL;DR (для коротких LLM-контекстов)

> Создай iOS 17 SwiftUI app **CanvasLab** — изолированный полигон для канваса. Скопируй из `Steps4` файлы: `CanvasElement.swift`, `ProceduralShapeGenerator.swift`, `EnergyGradientBackground.swift`, `GenerativeCanvasView.swift`, `SeededRNG.swift`, все 3 Metal-шейдера (`ShaderParkShader.metal`, `SpotlightShader.metal`, `SmudgeShaders.metal`) + их Swift renderers и UIViewRepresentables, `CanvasOverlayStyle.swift`, `CanvasAnimationOverlay.swift`. Убери зависимости от App Group, Supabase, HealthKit, AppLogger, AppColors, SharedKeys, CanvasImageCatalog. Упрости `AppTheme` до `daylight | night`. Создай `LabAppModel` с публикуемыми параметрами (steps/sleep points, palette, style, overlay, элементы) и `ContentView` со split-layout: верх — канвас + gradient + overlay (`ZStack`), низ — `ControlsPanel` со всеми пресетами / пикерами / слайдерами / spawn-кнопками. Добавь preset-сцены (Empty, Mixed, Crowded, Cluster). Цель — быстро тестировать новые `BodyShapeStyle` / `MindShapeStyle` / `HeartShapeStyle`, новые палитры в `GradientPalette`, новые стили в `GradientStyle`, новые Metal-оверлеи в `CanvasOverlayStyle`. Полный спек цветов / формул / шейдеров — в этом MD.

---

## 20. Зависимости

- iOS 17+, SwiftUI, Metal, MetalKit, simd. Только Apple frameworks.
- Никаких HealthKit / Family Controls / Supabase / StoreKit / WidgetKit / ActivityKit.
- iPhone simulator или real device. На Mac (Catalyst) тоже должно работать с минимальными правками.
