# CircleShapeRenderer — полное описание генерации

## Концепция

Каждый circle-элемент — это **всегда** цветной диск с радиальным градиентом.  
Некоторые элементы дополнительно имеют **спирограф внутри** (гипотрохоида, clipped по кругу).

Наличие спирографа — **бинарная характеристика**, определяемая `shapeSeed` при spawn/reroll.  
Она не зависит от количества элементов на canvas. Если элемент "без узора" — он чистый навсегда (до reroll).

Видимость (intensity) спирографа на элементах "с узором" растёт с общим количеством circle-элементов на canvas (`circleCount`). При 1 элементе — даже "узорные" показывают только намёк. При 12 — полное кружево.

---

## Входные данные элемента

| Поле `CanvasElement` | Тип | Влияние |
|---------------------|-----|---------|
| `shapeSeed` | `UInt64` | Определяет ВСЁ: has pattern?, fill style, R/r/d спирографа, complexity |
| `basePosition` | `CGPoint` (0…1) | Нормализованная позиция на canvas |
| `size` / `userSize` | `CGFloat` | Базовый размер (radius = size × dim × 1.15) |
| `phaseOffset` | `Double` (0…2π) | Десинхронизация wobble/pulse, сдвиг rotation |
| `pulseFrequency` | `Double` | Частота пульсации радиуса |
| `userRotation` | `Double` | Пользовательский поворот |
| `hexColor` | `String` | Основной цвет → `decayedColor` |
| `hexColor2` | `String?` | Вторичный цвет → `decayedColor2` |

Внешний параметр (от `GenerativeCanvasView`):

| Параметр | Тип | Влияние |
|----------|-----|---------|
| `circleCount` | `Int` (1…12) | Количество circle-элементов на canvas. Управляет intensity и complexity спирографа |

---

## Определение: будет ли узор

```swift
private static func hasPattern(seed: UInt64) -> Bool {
    (seed &>> 5) % 100 < 55   // ~55% элементов получают узор
}
```

- Детерминистично из seed — один и тот же seed всегда даёт один и тот же ответ
- Reroll меняет seed → может переключить метку
- Элементы "без узора" (45%) — чистый круг навсегда

---

## Определение: fill style базового круга

```swift
private struct FillStyle {
    let isSolid: Bool        // ~50%: плотный однотонный диск vs двухцветный градиент
    let opacityMul: Double   // 0.85…1.0: jitter яркости

    init(seed: UInt64) {
        isSolid = (seed &>> 3) % 2 == 0
        let opacityBits = Double((seed &>> 7) % 16) / 15.0
        opacityMul = 0.85 + opacityBits * 0.15
    }
}
```

---

## Базовый круг (drawFill) — всегда рисуется

### Solid подвариант (~50%)

Один blended цвет (если есть color2 → `lerp(c1, c2, 0.35)`).

```
Gradient stops:
  0%   → blendColor × 0.92 × opacityMul
  75%  → blendColor × 0.88 × opacityMul
  100% → blendColor × 0.35 × opacityMul
```

Результат: плотный насыщенный диск с мягким затуханием на краю.

### Gradient подвариант (~50%)

Два цвета: `innerColor` в центре, `outerColor` на периферии.  
Если есть `color2` — центр градиента смещён от геометрического центра на 20% радиуса (по углу `phase × 2.3`).

```
Gradient stops:
  0%   → innerColor × 0.95 × opacityMul
  30%  → innerColor × 0.90 × opacityMul
  55%  → outerColor × 0.80 × opacityMul
  78%  → outerColor × 0.60 × opacityMul
  100% → outerColor × 0.30 × opacityMul
```

Результат: двухцветный круг с эксцентричным ядром.

---

## Спирограф overlay — только на элементах с `hasPattern == true`

### Параметры из seed и circleCount

```swift
// Intensity: насколько виден узор (0…1)
let intensity = min(1.0, Double(circleCount - 1) / 11.0)

// Complexity: плотность кривой (0…1)
let complexity = min(1.0, Double(circleCount - 1) / 11.0)

// Количество слоёв спирографа
let layerCount = min(3, 1 + (circleCount - 2) / 3)
```

| circleCount | intensity | complexity | layers |
|:-----------:|:---------:|:----------:|:------:|
| 1 | — | — | 0 (нет overlay) |
| 2 | 0.09 | 0.09 | 1 |
| 3 | 0.18 | 0.18 | 1 |
| 4 | 0.27 | 0.27 | 1 |
| 5 | 0.36 | 0.36 | 2 |
| 6 | 0.45 | 0.45 | 2 |
| 7 | 0.55 | 0.55 | 2 |
| 8 | 0.64 | 0.64 | 3 |
| 9 | 0.73 | 0.73 | 3 |
| 10 | 0.82 | 0.82 | 3 |
| 11 | 0.91 | 0.91 | 3 |
| 12 | 1.00 | 1.00 | 3 |

### Форма спирографа: гипотрохоида

```swift
R = radius × 0.6                              // внешний круг (60% от элемента)
r = R × (0.2 + (seed >> 10) % 60 / 100)       // внутренний (20–80% от R)
d = r × (0.5 + (seed >> 16) % 100 / 100)      // перо (50–150% от r)
```

| Биты seed | Параметр | Диапазон | Влияние |
|-----------|----------|----------|---------|
| bits 10–15 | `rRatio` (r/R) | 0.2…0.8 | Число лепестков |
| bits 16–22 | `dRatio` (d/r) | 0.5…1.5 | Глубина петель |

Характер фигуры:
- `d/r < 1` → мягкие округлые лепестки ("цветок")
- `d/r = 1` → острые вершины
- `d/r > 1` → петли с самопересечениями

### Анимация

```swift
rotSpeed = 0.02 + complexity × 0.03    // 0.02…0.05 рад/сек
```

Вся фигура вращается как жёсткое тело. Форма узора не меняется.

### Детализация кривой

```swift
steps = 300 + Int(complexity × 200)           // 300…500 сегментов
maxAngle = π × 2 × (3 + complexity × 5)      // 6π…16π (3–8 оборотов)
```

- complexity = 0 → 3 оборота, простой цветок
- complexity = 1 → 8 оборотов, плотная кружевная вязь

### Многослойность

Каждый из `layerCount` слоёв — отдельный спирограф:

```swift
layerSeed = seed &+ UInt64(layer × 7919)    // разные R/r/d → разный узор
layerT = t + Double(layer) × 2.3            // разная фаза вращения
layerRadius = r × (0.85 + layer × 0.08)     // слегка разный масштаб
```

### Rendering pipeline (per layer)

```
1. Clip to circle bounds (ellipse)
2. Rotate by element rotation
3. Generate spirograph Path (addLine, 300–500 steps)
4. Fill path with radial gradient:
     strokeColor × 0.8  (center)
     strokeColor × 0.3  (middle)
     strokeColor × 0.0  (edge)
5. Apply gaussian blur:
     blurRadius = blurSpread × (layer + 1) / layerCount
     blurSpread = 6.0 × intensity (max 6px)
6. Stroke path (AFTER blur → line stays sharp):
     color: strokeColor × 0.6
     lineWidth: 1.5
7. Blend mode: .plusLighter (intersections glow)
8. Layer opacity: baseOpacity × (1.0 - layer × 0.08)
     baseOpacity = 0.6 × intensity
     floor: max(0.05, ...)
```

---

## Позиционирование

```swift
// Нормализованная позиция → пиксели + wobble
cx = basePosition.x × width
cy = basePosition.y × height

wobbleX = sin(t × 0.012 + phase) × w × 0.004 × amp
        + sin(t × 0.006 + phase × 2.1) × w × 0.002 × amp
wobbleY = cos(t × 0.010 + phase × 1.4) × h × 0.004 × amp
        + cos(t × 0.007 + phase × 0.9) × h × 0.002 × amp
```

Два наложенных синусоидальных колебания с разной частотой → органичный drift, не петля.

---

## Sizing

```swift
radius = effectiveSize × min(w, h) × 1.15 × pulse
pulse = 1.0 + sin(t × (0.2 + pulseFreq × 0.2) + phase) × 0.015 × amp
```

- `effectiveSize` = `userSize ?? size` (0.14…0.30 при spawn)
- Pulse: ±1.5% радиуса, медленная синусоида

---

## Rotation

```swift
rotation = phaseOffset × 0.3 + userRotation
```

Каждый элемент повёрнут на небольшой случайный угол + пользовательский.

---

## Полный flow рендера одного элемента

```
1. Compute center (position + wobble)
2. Compute radius (size × dim × 1.15 × pulse)
3. Compute rotation (phase × 0.3 + userRotation)
4. Extract seed

5. ALWAYS: drawFill (base circle disc)
   ├─ Determine FillStyle from seed (solid vs gradient, opacityMul)
   ├─ Build ellipse path
   ├─ Apply rotation
   └─ Fill with radial gradient

6. IF hasPattern(seed) AND circleCount >= 2:
   drawSpirographOverlay
   ├─ Clip to circle bounds
   ├─ For each layer (1–3):
   │   ├─ Derive layerSeed, layerT, layerRadius
   │   ├─ Generate spirograph Path
   │   ├─ Fill with radial gradient (0.8 → 0.3 → 0)
   │   ├─ Blur fill
   │   ├─ Stroke (sharp, 1.5pt)
   │   └─ Blend: plusLighter
   └─ Opacity scales with intensity (from circleCount)
```

---

## Что меняет reroll

При dice tap (`reroll()`) генерируется новый `shapeSeed`:
- Может переключить `hasPattern` (был чистый → стал с узором, и наоборот)
- Новые R/r/d → новая форма спирографа (другое число лепестков, другая глубина)
- Новый FillStyle (solid ↔ gradient)
- Новый opacityMul

---

## Файлы

| Файл | Что делает |
|------|-----------|
| `Shapes/CircleShapeRenderer.swift` | Весь рендер: drawFill + drawSpirographOverlay + spirographPath |
| `Models/CanvasElement.swift` | Модель: shapeSeed, size, phaseOffset, spawn(), reroll() |
| `Models/ShapeStyles.swift` | `CanvasShapeType` enum, resolved(for:) |
| `Views/GenerativeCanvasView.swift` | Caller: вычисляет circleCount, вызывает draw() |
