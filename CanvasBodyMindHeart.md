# Canvas: Body, Mind, and Heart — layout, motion, and rendering

This document describes how **activity choices** (energy categories **Body**, **Mind**, and **Heart**) become **canvas elements**: where they sit, how big they are, how they rotate, and how they animate. It matches the implementation in `CanvasElement.swift` (spawn + stored fields) and `GenerativeCanvasView.swift` (live draw).

---

## 1. Shared data model (`CanvasElement`)

Every spawned element is a `CanvasElement` with normalized geometry and animation parameters. On disk / in JSON-style terms:

| Field | Meaning |
|--------|---------|
| `category` | `body`, `mind`, or `heart` — which kind of daily choice produced the element |
| `kind` | `circle` for body and mind, `ray` for heart (derived from category at spawn) |
| `basePosition` | `CGPoint` with **x and y in 0…1** relative to the canvas width and height |
| `size` | **0…1**, interpreted against **`min(width, height)`** in pixels when drawing |
| `userSize` | Optional override from pinch; if set, replaces `size` for radius calculations |
| `userRotation` | User-applied rotation in **radians** (move mode); added on top of procedural rotation |
| `phaseOffset` | **0…2π** — desynchronizes motion from other elements |
| `driftSpeed` | **0.08…0.2** at spawn — scales how fast optional drifts run |
| `driftAmplitude` | **0.01…0.03** normalized — used where drift parameters apply |
| `pulseFrequency`, `pulseAmplitude` | Drive breathing / pulse (usage differs by category) |
| `rotationSpeed` | **3…10** — used for heart ray sweep, not a constant spin for all types |
| `opacity` | Spawn opacity range depends on category (see below) |
| `assetVariant` | Index into image catalog for mind/heart; body forces `0` |
| `shapeSeed` | `UInt64` — deterministic input for procedural **body** blob shape |
| `activityCount` | Feeds **body** shape complexity (more history → richer blob, capped) |

**Spawn placement:** `findOpenPosition` picks `basePosition` with margin **~0.12** from edges, trying to keep **~0.15** normalized distance from existing elements (relaxed if the canvas is crowded). So elements are spread but not tied to a fixed grid.

**Canonical canvas size:** `GenerativeCanvasView.canonicalPortraitSize` is used elsewhere so exports and gallery see a stable aspect; drawing still uses the actual `Canvas` size passed at render time.

---

## 2. Render order and layering

Understanding **when** each category is drawn explains overlaps and labels:

1. **Mind** — all mind elements first (they sit “under” the heavier body/heart treatment where compositing matters).
2. **Body clusters** — nearby body blobs are merged into metaball-style unions; labels for clustered bodies use each blob’s **animated center**.
3. **Solo body + heart** — any body not in a cluster, then hearts; mind is skipped in this pass (already drawn).

Within the element list, **circles** (body + mind) are sorted **largest `size` first**, then non-circles, so big blobs tend to paint before smaller ones when both use the circle pipeline.

---

## 3. Body (`EnergyCategory.body`)

### Role on the canvas

Body choices become **soft procedural blobs** — organic shapes from `ProceduralShapeGenerator.bodyPath`, not catalog PNGs. They read as **grounded, slow, breathy** masses; several close activities can **merge visually** into one silhouette.

### Position

- **Anchor:** `basePosition` mapped to pixel center: `(base.x * width, base.y * height)`.
- **Motion:** a **small wobble** only — two layers of sine/cosine on `t` with tiny amplitude (**~0.2–0.3%** of width/height per component), scaled by `ampScale` (from `timeScale`, e.g. quieter in edit mode). The blob stays near its spawn point.

### Size

- **At spawn:** normalized `size` is random in **0.16…0.32** (medium–large relative to mind).
- **On screen:**  
  `radius = effectiveSize * min(width, height) * 1.05 * pulse`  
  where `pulse = 1 + sin(…) * 0.02 * ampScale` — a **slow breath**, tied to `pulseFrequency` in a narrow band for body.

### Orientation

- The filled path is rotated by **`phaseOffset + userRotation`** (slow phase from identity + user tweak).
- In **clusters**, each blob’s path is additionally transformed around **its own** animated center with the same angle convention.

### Opacity and look

- Spawn `opacity` is **0.20…0.45** — intentionally **ghostly**; the rim stroke carries readable edge.
- Colors still go through **decay** (`decayNorm`) for desaturation as ink is spent.

### Clustering (metaballs)

- For each body element, the renderer computes **animated center** and **radius** (same pulse as solo draw).
- Two blobs are in the same cluster if  
  `distance(centers) < (r1 + r2) * 1.6`  
  (merge threshold **1.6**). Transitive closure groups chains of nearby blobs.
- **Cluster draw:** paths are unioned; a shared clip + multi-blob gradient fill produces a merged “goo” while preserving per-blob seeds/complexity in the union.

### Complexity

- `complexity` is derived from `activityCount` (capped vs 30) plus optional **interaction noise boost** when elements influence each other — busier canvas → slightly wilder silhouette.

---

## 4. Mind (`EnergyCategory.mind`)

### Role on the canvas

Mind choices become **image assets** from `CanvasImageCatalog.mind`, drawn inside a **rounded-rectangle-ish** layout (aspect from the asset). They behave like **slow drifting “thought” particles** with a **motion-aligned** rotation and optional **comet trail**.

### Position

- **Not** fixed at `basePosition` in screen space.
- **`mindDriftPosition`** builds a path in **normalized coordinates** then multiplies by width/height:
  - A **wandering home** near the spawn: `base ± 0.12` in x/y with slow sin/cos.
  - On top of that, **three frequency pairs** (Lissajous-style) with amplitudes **~0.24, 0.09, 0.03** on x and **~0.22, 0.08, 0.03** on y, modulated by an **envelope** `0.7 + 0.3 * sin(…) * sin(…)` so the drift **breathes** between wide sweeps and tight orbits.
  - **Frequencies** (`MindFrequencyProfile`) are **derived from `phaseOffset`** so each card’s motion looks different.
  - **Speed:** `0.03 + driftSpeed * 0.06`.
  - Result is **clamped** with margin **0.06** so minds stay inside the frame.
- **Interaction queries** use this **animated** normalized position (not `basePosition` alone).

### Size

- **At spawn:** normalized `size` **0.10…0.18** (smallest category on average).
- **On screen:** scale factor **1.1** on the radius (slightly larger than body’s 1.05), same `effectiveSize` and `min(width,height)` rule; a lighter **breathe** pulse than body.

### Orientation

- **`mindDriftVelocity`** is the time derivative of position (analytical).
- **Rotation:** `atan2(vy, vx) + userRotation + 270°` — the asset’s “forward” is aligned to **direction of travel** (plus user offset). Ghost trail copies use the same rule at **past times**.

### Trail

- **4** ghost images behind the main sprite, spaced **0.8** seconds apart in the time parameter, with **fading opacity** so fast arcs read as streaks.

### Opacity

- Main draw uses **`~0.76 ± breathe`** on the layer, separate from the stored spawn opacity band **0.35…0.75** (spawn still sets a general “character” for the element; the live mind path applies its own breathing opacity).

---

## 5. Heart (`EnergyCategory.heart`)

### Role on the canvas

Heart choices become **ray-shaped image assets** from `CanvasImageCatalog.heart`. They are anchored near the choice’s `basePosition` but **rotate so the ray points toward the center of the screen**, with a gentle **side-to-side sweep** — “pulling” energy inward emotionally.

### Position

- **Anchor (`heartCenter`):** same pattern as body — `basePosition` in pixels plus **small wobble** (coefficients slightly larger than body’s, ~0.4% level).
- **Important implementation note:** `heartDriftPosition` / `heartDriftVelocity` are defined in the same file but **are not used** by `drawRay` or `elementCenter`. Hearts do **not** drift around the global canvas center `(0.5, 0.5)` in the current ship build; they stay near their spawn with wobble only. If you change behavior, either wire those helpers in or delete them to avoid confusion.

### Size

- **At spawn:** normalized `size` **0.20…0.28**.
- **On screen:**  
  `radius = effectiveSize * min(width, height) * 2.2`  
  — the **2.2** multiplier makes heart assets **much larger** in pixel extent than a “circle” of the same normalized `size` would suggest; rays read as bold strokes.

### Orientation

- Let `anchor` be the (possibly interaction-offset) center.
- **Inward angle:** `atan2(canvasCenter.y - anchor.y, canvasCenter.x - anchor.x)` so the tip points **toward the middle of the view**.
- **Full rotation:** `inwardAngle + 90° + userRotation + raySweepAngle`.
  - **`raySweepAngle`:** sine wave in time with amplitude roughly **`(10 + rotationSpeed * 0.2) * ampScale`** degrees and a slow frequency tied to `driftSpeed` — a **gentle oscillating sway** around the inward aim.
- **Interaction:** optional `attractionOffset` shifts the anchor before computing inward angle (subtle “pulled by neighbors” feel when interactions are active).

### Opacity

- Layer opacity **`breathe = 0.92 + sin(t * pulseFrequency * 0.5 + phaseOffset) * 0.06`** — a calm shimmer, not the full spawn opacity range used directly as the only gate.

---

## 6. Machine-readable summary (JSON)

Use this as a compact spec for tools, tests, or design docs:

```json
{
  "coordinateSystem": {
    "basePosition": "0…1 in x and y; spawn uses margin ~0.12 and spacing heuristics",
    "size": "0…1 times min(canvas.width, canvas.height) for radii; userSize overrides size"
  },
  "body": {
    "kind": "circle",
    "shape": "procedural bodyPath + soft fill + rim",
    "position": "basePosition * size + small multi-sine wobble",
    "radiusFormula": "effectiveSize * min(w,h) * 1.05 * slowPulse",
    "rotation": "phaseOffset + userRotation (per blob in clusters)",
    "clusterMerge": "distance < (r1+r2) * 1.6",
    "spawnSizeRange": [0.16, 0.32],
    "spawnOpacityRange": [0.2, 0.45]
  },
  "mind": {
    "kind": "circle",
    "shape": "mind PNG asset + optional trail",
    "position": "Lissajous-like drift around wandering home; clamp margin 0.06",
    "radiusFormula": "effectiveSize * min(w,h) * 1.1 * lightPulse",
    "rotation": "atan2(velocity) + userRotation + 270deg",
    "trail": { "ghosts": 4, "dt": 0.8 },
    "spawnSizeRange": [0.1, 0.18],
    "spawnOpacityRange": [0.35, 0.75]
  },
  "heart": {
    "kind": "ray",
    "shape": "heart PNG asset or tapered gradient fallback",
    "position": "heartCenter = basePosition * size + wobble (heartDrift* unused in drawRay)",
    "radiusFormula": "effectiveSize * min(w,h) * 2.2",
    "rotation": "toward canvas center + 90deg + userRotation + sweep",
    "spawnSizeRange": [0.2, 0.28],
    "spawnOpacityRange": [0.35, 0.75]
  }
}
```

---

## 7. Source map

| Topic | File / symbol |
|--------|----------------|
| Spawn ranges, `kind`, placement | `CanvasElement.spawn`, `findOpenPosition` |
| Element fields | `CanvasElement` struct |
| Mind drift, velocity, trail | `GenerativeCanvasView` — `mindDriftPosition`, `mindDriftVelocity`, `drawMindAssetTrail` |
| Body wobble, circle radius, procedural body | `circleCenter`, `drawCircle`, `drawProceduralBody`, `drawBodyFill` |
| Heart ray, center, sweep | `heartCenter`, `drawRay`, `raySweepAngle` |
| Unused heart drift | `heartDriftPosition`, `heartDriftVelocity` (not called by current draw path) |
| Clusters | `collectBodyClusters`, `drawBodyCluster` |
| Frozen centers (e.g. export) | `GenerativeCanvasView.frozenElementCenter` |
| Heart gradient stops (tint) | `ProceduralShapeGenerator.heartGradientColors` (not layout; color only) |

---

## 8. Relation to `CanvasPalettes.md`

`CanvasPalettes.md` documents **colors and gradients** (swatches, day defaults, energy themes). This file documents **geometry and motion** for the three choice-driven element categories. Together they describe most of the “what does the canvas look like” surface area.
