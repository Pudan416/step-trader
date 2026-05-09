# Canvas colors and styles

Reference for palette and style enums used by the energy canvas, activity elements, and related UI. Source files are noted inline.

---

## 1. Activity color palette (`CanvasColorPalette`)

Sixteen fixed swatches (4×4 grid). Used for category/option colors and random picks.

**Source:** `StepsTrader/Models/CanvasElement.swift` — `CanvasColorPalette.paletteHex`

| # | Hex |
|---|-----|
| 1 | `#C3143B` |
| 2 | `#9BB6E0` |
| 3 | `#A7BF50` |
| 4 | `#C3D7A3` |
| 5 | `#01B6C4` |
| 6 | `#7652AF` |
| 7 | `#F68D0C` |
| 8 | `#2C2E4D` |
| 9 | `#796C3C` |
| 10 | `#FFD369` |
| 11 | `#49484D` |
| 12 | `#C7E0D8` |
| 13 | `#222831` |
| 14 | `#955530` |
| 15 | `#FEAAC2` |
| 16 | `#EBE4D7` |

---

## 2. Day canvas defaults (`DayCanvas`)

Default hex values stored on a new day record (sleep/steps channel tints).

**Source:** `StepsTrader/Models/CanvasElement.swift` — `DayCanvas.init`

| Field | Hex | Role |
|-------|-----|------|
| `sleepColorHex` | `#000000` | Sleep-driven default |
| `stepsColorHex` | `#FED415` | Steps-driven default |

---

## 3. Energy gradient palettes (`GradientPalette` → `EnergyGradientRenderer.Palette`)

Background / wallpaper energy layers. Each scheme defines five roles: **bright**, **warm**, **cool**, **dark**, **daylightBase**.

**Sources:**

- `StepsTrader/Models/Types.swift` — `GradientPalette` (cases + `displayName` + legacy `normalized` mapping)
- `StepsTrader/Views/Components/EnergyGradientBackground.swift` — `EnergyGradientRenderer.palette(for:)`

### Scheme cases

| Case | Display name |
|------|----------------|
| `warmSunset` | Sunset |
| `ocean` | Ocean |
| `aurora` | Aurora |
| `dusk` | Dusk |

### Legacy `UserDefaults` raw values (`GradientPalette.normalized`)

| Stored raw | Maps to |
|------------|---------|
| `roseGarden` | `.ocean` |
| `ember` | `.aurora` |
| (any other invalid string) | `.warmSunset` if `GradientPalette(rawValue:)` fails |

### Hex by scheme

| Scheme | bright | warm | cool | dark | daylightBase |
|--------|--------|------|------|------|--------------|
| Sunset (`warmSunset`) | `#FFBF65` | `#FD8973` | `#003A6C` | `#002646` | `#F2DCC8` |
| Ocean | `#7FDBDA` | `#3A9FBF` | `#1A4B6E` | `#0B1E33` | `#E0F0F5` |
| Aurora | `#C4B5FD` | `#7C6FBF` | `#1F6E5C` | `#0F1B2D` | `#EDE8F8` |
| Dusk | `#EEDDC9` | `#C0AC98` | `#5E7282` | `#384856` | `#F2EAE0` |

### Warm-sunset backward-compat aliases

**Source:** `StepsTrader/Views/Components/EnergyGradientBackground.swift` — static colors on `EnergyGradientRenderer`

| Name | Hex |
|------|-----|
| `gold` | `#FFBF65` |
| `coral` | `#FD8973` |
| `navy` | `#003A6C` |
| `night` | `#002646` |
| `daylightBase` | `#F2DCC8` |

> Note: The file comment still mentions an older “night” spec; the table above matches the current `palette(for: .warmSunset)` and static `night` value.

---

## 4. Gradient styles (`GradientStyle`)

How the energy gradient layer is composed (Appearance, `EnergyGradientBackground`, Shortcuts export).

**Source:** `StepsTrader/Models/Types.swift`

| Raw value | Display name |
|-----------|----------------|
| `radial` | Radial |
| `linear` | Linear |
| `radialReversed` | Radial Reversed |
| `linearReversed` | Linear Reversed |
| `organic` | Organic |

---

## 5. Procedural / preview pools (`RandomPalette`)

Not a user-pickable swatch grid. Nine warm and nine cool sRGB colors (0…1). `randomColors(seed:count:)` returns 2 or 3 `Color` values by shuffling pools and alternating warm/cool for outer vs center.

**Source:** `StepsTrader/Views/Components/CanvasShapePreview.swift`

### Warm pool (RGB 0…1)

| # | R | G | B |
|---|---|---|---|
| 1 | 0.92 | 0.78 | 0.42 |
| 2 | 0.90 | 0.58 | 0.35 |
| 3 | 0.88 | 0.48 | 0.55 |
| 4 | 0.82 | 0.42 | 0.62 |
| 5 | 0.75 | 0.35 | 0.48 |
| 6 | 0.90 | 0.70 | 0.48 |
| 7 | 0.80 | 0.52 | 0.60 |
| 8 | 0.88 | 0.55 | 0.65 |
| 9 | 0.78 | 0.85 | 0.55 |

### Cool pool (RGB 0…1)

| # | R | G | B |
|---|---|---|---|
| 1 | 0.62 | 0.42 | 0.82 |
| 2 | 0.50 | 0.42 | 0.85 |
| 3 | 0.40 | 0.55 | 0.85 |
| 4 | 0.38 | 0.65 | 0.82 |
| 5 | 0.38 | 0.75 | 0.65 |
| 6 | 0.42 | 0.78 | 0.55 |
| 7 | 0.48 | 0.72 | 0.75 |
| 8 | 0.55 | 0.75 | 0.48 |
| 9 | 0.40 | 0.60 | 0.50 |

### Heart gradients on the live canvas

Heart multi-stop gradients are **not** taken from `RandomPalette`. They are generated from the element’s `hexColor` with HSB jitter and opacity per stop.

**Source:** `StepsTrader/Models/ProceduralShapeGenerator.swift` — `heartGradientColors(seed:baseHex:)`  
(3 or 4 colors; hue ±0.12, saturation −0.15…+0.1, brightness −0.1…+0.15, clamped S/B, opacity 0.75 on first stop else 0.45…0.7.)

---

## 6. Shape and tint rendering styles

### `ElementKind`

**Source:** `StepsTrader/Models/CanvasElement.swift`

| Case | Typical use |
|------|-------------|
| `circle` | Body / Mind floating shapes |
| `ray` | Heart rays |

### `GradientMode` (preview / tinted assets)

**Source:** `StepsTrader/Views/Components/CanvasShapePreview.swift`

| Case | Meaning |
|------|---------|
| `linear(Angle)` | Linear gradient along angle |
| `radial(center: UnitPoint)` | Radial gradient from center |

### `GradientTintedAsset` pipeline

**Source:** `StepsTrader/Views/Components/CanvasShapePreview.swift`

1. Asset image: `saturation(0)`, `brightness(-0.15)`  
2. Overlay gradient with `blendMode(.color)`  
3. Second overlay same gradient with `blendMode(.overlay)`

---

## Energy gradient: coral, blobs, and proportions

All numbers come from `EnergyGradientRenderer.computeOpacities` and `draw` / `organicBlobs` in `StepsTrader/Views/Components/EnergyGradientBackground.swift`.

Assumptions below:

- **Night / dark canvas** (`isDaylight == false`). Daylight mode uses fixed opacities (gold 0.85, coral 0.9, navy 0.82, night 0.85) and the same **radius band math** via `goldLoc` / `coralLoc` / `navyLoc`.
- **Normalized points** use `Ss = smoothstep(stepsPoints / 20)`, `Ls = smoothstep(sleepPoints / 20)`. “Full” = 20/20 points → `Ss = 1`, `Ls = 1`.
- **No data** = `hasStepsData == false` **and** `hasSleepData == false` (no HealthKit for either), with `Ss = Ls = 0`.
- **Steps only** = `hasStepsData && !hasSleepData`, full steps → `Ss = 1`, `Ls = 0`.
- **Sleep only** = `hasSleepData && !hasStepsData`, full sleep → `Ls = 1`, `Ss = 0`.
- **Fully balanced** = both flags true, **full** steps and sleep → `Ss = Ls = 1`.

Color roles: **gold** = `pal.bright`, **coral** = `pal.warm`, **navy** = `pal.cool`, **night** = `pal.dark`.

### A) Radial gradient — share of radius per band

Locations are cumulative along **normalized radius** 0 (center) → 1 (edge). Band widths:

| Scenario | Gold band width<br>`goldLoc` | Coral band width<br>(fixed) | Navy band width<br>`navyLoc − coralLoc` | Night band width<br>`1 − navyLoc` |
|----------|------------------------------|-----------------------------|----------------------------------------|-----------------------------------|
| No data | `0` | **`0.30`** | `max(0, 0.20) = 0.08` (floor) | `0.62` |
| Steps only (full steps) | `0.42` | **`0.38`** | `0.16` | `0.04` |
| Sleep only (full sleep) | `0` | **`0.30`** | `0.20` | `0.50` |
| Both (full Ss & Ls) | `0.35` | **`0.30`** | `0.20` | `0.15` |

- Coral’s radial slice is **always 0.30** of radius except **steps-only**, where it is **0.38** (`coralShare`).
- Gold and navy widths follow the formulas:  
  `goldShare = stepsOnly ? Ss×0.42 : Ss×0.35`,  
  `navyShare = stepsOnly ? max(Ls×0.20, 0.16) : max(Ls×0.20, 0.08)`.

### B) Layer opacities (night mode) — raw strengths

These multiply each palette color in the main radial gradient stops (plus separate **glow** for the additive overlay when `gradientStyle != .organic`).

| Scenario | `gold` | `coral` | `navy` | `night` | `glow` |
|----------|--------|---------|--------|---------|--------|
| No data | `0` | `0.68` | `0.42` | `0.08` | `0.35` |
| Steps only (full) | `0.95` | `lerp(0.55,0.85,1)=0.85` | `lerp(0.08,0.14,1)=0.14` | `0.03` | `lerp(0.50,0.80,1)=0.80` |
| Sleep only (full) | `0` | `lerp(0.35,0.50,0)=0.35` | `lerp(0.42,0.55,1)=0.55` | `lerp(0.40,0.55,1)=0.55` | `0.25` |
| Balanced (full) | `0.95` | `0.85 × 0.92 = 0.782` | `lerp(0.28,0.48,1)=0.48` | `lerp(0.28,0.45,1)=0.45` | `0.60 × 0.85 = 0.51` |

If you want a **single proportion vector** over the four main layers, normalize `gold + coral + navy + night` to 1.0 (example **balanced full**): **≈ 0.35 : 0.29 : 0.18 : 0.17** (gold : coral : navy : night).

### C) Organic style — blobs (`gradientStyle == .organic`)

Eight blobs are drawn: **2 × night**, **2 × navy**, **2 × coral**, **2 × gold** — **equal count (25% per color role)**.

Per-blob opacity is `layerOpacity × random(0.5…0.9)` (dark/navy/gold) or `coralOpacity × random(0.4…0.8)` for **coral** blobs, so **within-role intensity** is not a fixed ratio.

---

## Quick map: what to edit

| What you want to change | Where |
|-------------------------|--------|
| 16 activity swatches | `CanvasColorPalette` in `CanvasElement.swift` |
| New-day sleep/steps defaults | `DayCanvas.init` in `CanvasElement.swift` |
| Named energy themes + hex | `EnergyGradientRenderer.palette(for:)` in `EnergyGradientBackground.swift` |
| Palette display names / cases | `GradientPalette` in `Types.swift` |
| Gradient layout modes | `GradientStyle` in `Types.swift` |
| Preview random tints | `RandomPalette` in `CanvasShapePreview.swift` |
| Live heart gradient math | `heartGradientColors` in `ProceduralShapeGenerator.swift` |
