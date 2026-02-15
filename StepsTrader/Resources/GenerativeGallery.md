# Generative Gallery — Technical Specification

## Concept

The Gallery page becomes a **living, generative art canvas**. Every action the user takes during the day — choosing activities, walking, sleeping — paints a visual element onto the canvas. No silhouette. No triangle. Just an evolving abstract painting that is unique to each day.

The user holds `+`, slides toward a category, picks an activity, chooses a color, and a new visual element appears on the canvas. Steps and sleep form the background atmosphere. Everything drifts, pulses, and breathes. At end of day the painting is saved as a snapshot for the history gallery.

---

## 1. Interaction: Radial Hold Menu

### Trigger
- User **long-presses** the `+` button (300ms threshold).
- Three category nodes appear in an arc above the finger: **Body** (left), **Heart** (center), **Mind** (right).
- Haptic feedback on appear (`UIImpactFeedbackGenerator(.medium)`).

### Drag-to-select
- While holding, user slides finger toward a category.
- The nearest node highlights (scale up + glow).
- Distance threshold: 60pt from node center to activate.
- If finger lifts on a highlighted node → open that category's activity list.
- If finger lifts in dead zone → dismiss (no action).

### SwiftUI implementation
```swift
@GestureState private var dragOffset: CGSize = .zero
@State private var isMenuVisible = false
@State private var hoveredCategory: EnergyCategory? = nil

let holdAndDrag = LongPressGesture(minimumDuration: 0.3)
    .sequenced(before: DragGesture(minimumDistance: 0, coordinateSpace: .local))
    .updating($dragOffset) { value, state, _ in
        if case .second(true, let drag?) = value {
            state = drag.translation
        }
    }
    .onChanged { value in
        if case .second(true, _) = value {
            isMenuVisible = true
            // compute hoveredCategory from dragOffset
        }
    }
    .onEnded { value in
        if let category = hoveredCategory {
            openActivityPicker(for: category)
        }
        isMenuVisible = false
        hoveredCategory = nil
    }
```

### Node positions (relative to + button center)
| Category | Angle | Offset (dx, dy) |
|----------|-------|------------------|
| Body     | 210°  | (-80, -100)      |
| Heart    | 270°  | (0, -120)        |
| Mind     | 330°  | (80, -100)       |

---

## 2. Activity Selection + Color Picker

### Flow
1. Category node selected → present sheet with activity list (reuse existing `ActivityPickerSheet`).
2. Each activity row gains a **color dot** on the right side.
3. Tapping the dot opens a **color palette** (not full ColorPicker — curated grid of 16-20 colors).
4. Confirming the activity + color marks it as done and spawns a visual element.

### Color palette
A curated set that looks good on dark backgrounds with additive blending:
```swift
static let palette: [Color] = [
    // Warm
    Color(hue: 0.00, saturation: 0.75, brightness: 0.95),  // Red
    Color(hue: 0.05, saturation: 0.80, brightness: 0.95),  // Coral
    Color(hue: 0.08, saturation: 0.85, brightness: 0.95),  // Orange
    Color(hue: 0.12, saturation: 0.80, brightness: 0.95),  // Amber
    Color(hue: 0.16, saturation: 0.80, brightness: 0.95),  // Yellow
    // Nature
    Color(hue: 0.25, saturation: 0.70, brightness: 0.90),  // Lime
    Color(hue: 0.33, saturation: 0.65, brightness: 0.85),  // Green
    Color(hue: 0.42, saturation: 0.60, brightness: 0.85),  // Teal
    Color(hue: 0.50, saturation: 0.65, brightness: 0.90),  // Cyan
    // Cool
    Color(hue: 0.58, saturation: 0.70, brightness: 0.90),  // Sky
    Color(hue: 0.65, saturation: 0.75, brightness: 0.90),  // Blue
    Color(hue: 0.72, saturation: 0.65, brightness: 0.90),  // Indigo
    Color(hue: 0.78, saturation: 0.60, brightness: 0.90),  // Purple
    // Soft
    Color(hue: 0.85, saturation: 0.55, brightness: 0.92),  // Lavender
    Color(hue: 0.92, saturation: 0.60, brightness: 0.92),  // Pink
    Color(hue: 0.97, saturation: 0.50, brightness: 0.95),  // Rose
    // Neutral
    .white,
    Color(white: 0.7),
]
```

### Data model addition
```swift
struct ActivityColorSelection: Codable, Equatable {
    let optionId: String
    let category: EnergyCategory
    let hexColor: String           // "#FF5733"
    let elementKind: ElementKind   // .circle, .softLine, .ray
}
```

---

## 3. Visual Elements

### Element types

| Kind       | Shape                          | Animation                                   |
|------------|-------------------------------|---------------------------------------------|
| `.circle`  | RadialGradient, soft edges     | Pulse (scale oscillation) + slow drift       |
| `.softLine`| Bezier path, wide stroke, blur | Float across canvas, control points animate  |
| `.ray`     | Narrow LinearGradient at angle | Slow rotation + opacity breathing            |

The user does **not** pick the element type. It is assigned based on **category**:
- **Body** activities → `.circle` (grounded, centered energy)
- **Mind** activities → `.ray` (directional, focused)
- **Heart** activities → `.softLine` (fluid, emotional)

### Element data model
```swift
enum ElementKind: String, Codable, CaseIterable {
    case circle
    case softLine
    case ray
}

struct CanvasElement: Identifiable, Codable {
    let id: UUID
    let kind: ElementKind
    let category: EnergyCategory
    let optionId: String

    // Visual
    let hexColor: String
    let size: CGFloat              // normalized 0…1 relative to canvas
    let basePosition: CGPoint      // normalized (0…1, 0…1)

    // Animation parameters (randomized on creation)
    let phaseOffset: Double        // 0…2π — desynchronizes from other elements
    let driftSpeed: Double         // 0.1…0.5 — how fast it moves
    let driftAmplitude: CGFloat    // 0.01…0.06 — how far it drifts (normalized)
    let pulseFrequency: Double     // 0.3…1.2 Hz
    let pulseAmplitude: CGFloat    // 0.02…0.08 — scale oscillation range
    let rotationSpeed: Double      // degrees/sec (rays only)
    let opacity: Double            // 0.3…0.8

    // Timestamps
    let createdAt: Date
}
```

### Element factory
When an activity is confirmed:
```swift
static func spawn(
    optionId: String,
    category: EnergyCategory,
    color: String,
    existingElements: [CanvasElement]
) -> CanvasElement {
    let kind: ElementKind = switch category {
        case .activity:   .circle
        case .creativity: .ray
        case .joys:       .softLine
    }

    // Position: avoid overlap with existing elements
    let position = findOpenPosition(existing: existingElements)

    return CanvasElement(
        id: UUID(),
        kind: kind,
        category: category,
        optionId: optionId,
        hexColor: color,
        size: CGFloat.random(in: 0.15...0.35),
        basePosition: position,
        phaseOffset: Double.random(in: 0...(2 * .pi)),
        driftSpeed: Double.random(in: 0.15...0.4),
        driftAmplitude: CGFloat.random(in: 0.01...0.05),
        pulseFrequency: Double.random(in: 0.3...1.0),
        pulseAmplitude: CGFloat.random(in: 0.02...0.07),
        rotationSpeed: Double.random(in: 5...20),
        opacity: Double.random(in: 0.35...0.75),
        createdAt: Date()
    )
}
```

---

## 4. Background Atmosphere (Steps + Sleep)

Steps and sleep are **not** discrete elements. They form the **background atmosphere** behind all activity elements.

### Sleep gradient
- **Color**: Purple (default), user-customizable.
- **Shape**: Large vertical elliptical RadialGradient covering the upper portion of the canvas.
- **Size**: Scales with `sleepPoints` (0–20). At 0 → invisible. At 20 → covers ~60% of canvas.
- **Opacity**: `sleepPoints / 20.0 * 0.6` (max 0.6 so it doesn't overpower elements).
- **Animation**: Very slow pulse (0.15 Hz), slight vertical drift.

### Steps gradient
- **Color**: Yellow-gold (default), user-customizable.
- **Shape**: Large horizontal elliptical RadialGradient covering the lower portion.
- **Size**: Scales with `stepsPoints` (0–20). Same scaling as sleep.
- **Opacity**: Same formula as sleep.
- **Animation**: Slow horizontal drift (like walking motion), gentle pulse.

### Color customization for backgrounds
Stored in UserDefaults:
```swift
@AppStorage("gallery_sleep_color") var sleepColorHex: String = "#8B5CF6"  // purple
@AppStorage("gallery_steps_color") var stepsColorHex: String = "#EAB308"  // yellow
```

Accessible via a settings gear icon on the gallery page, or long-press on the background.

---

## 5. Rendering Engine

### Architecture
```
TimelineView (.animation, 30fps)
  └─ Canvas { context, size in ... }
       ├─ drawBackground(sleep, steps)
       ├─ for element in elements {
       │     drawElement(element, time: t)
       │  }
       └─ (blend mode: .plusLighter on dark bg)
```

### Canvas drawing (pseudocode)
```swift
struct GenerativeCanvasView: View {
    let elements: [CanvasElement]
    let sleepPoints: Int
    let stepsPoints: Int
    let sleepColor: Color
    let stepsColor: Color

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
            Canvas { context, size in
                let t = timeline.date.timeIntervalSinceReferenceDate

                // Background atmosphere
                drawSleepGradient(context: &context, size: size, t: t)
                drawStepsGradient(context: &context, size: size, t: t)

                // Activity elements
                for element in elements {
                    switch element.kind {
                    case .circle:   drawCircle(element, context: &context, size: size, t: t)
                    case .softLine: drawSoftLine(element, context: &context, size: size, t: t)
                    case .ray:      drawRay(element, context: &context, size: size, t: t)
                    }
                }
            }
        }
    }
}
```

### Drawing each element type

**Circle:**
```swift
func drawCircle(_ e: CanvasElement, context: inout GraphicsContext, size: CGSize, t: Double) {
    let phase = t * e.pulseFrequency + e.phaseOffset
    let scale = 1.0 + sin(phase) * Double(e.pulseAmplitude)
    let dx = sin(t * e.driftSpeed + e.phaseOffset) * Double(e.driftAmplitude) * Double(size.width)
    let dy = cos(t * e.driftSpeed * 0.7 + e.phaseOffset) * Double(e.driftAmplitude) * Double(size.height)

    let center = CGPoint(
        x: Double(e.basePosition.x) * Double(size.width) + dx,
        y: Double(e.basePosition.y) * Double(size.height) + dy
    )
    let radius = Double(e.size) * Double(min(size.width, size.height)) * scale

    let gradient = Gradient(colors: [
        Color(hex: e.hexColor).opacity(e.opacity),
        Color(hex: e.hexColor).opacity(e.opacity * 0.3),
        .clear
    ])

    context.drawLayer { ctx in
        ctx.opacity = e.opacity
        ctx.blendMode = .plusLighter
        let shading = GraphicsContext.Shading.radialGradient(
            gradient, center: center,
            startRadius: 0, endRadius: radius
        )
        ctx.fill(Circle().path(in: CGRect(
            x: center.x - radius, y: center.y - radius,
            width: radius * 2, height: radius * 2
        )), with: shading)
    }
}
```

**Soft Line:**
```swift
func drawSoftLine(_ e: CanvasElement, context: inout GraphicsContext, size: CGSize, t: Double) {
    let phase = t * e.driftSpeed + e.phaseOffset
    // Animated bezier control points
    let startX = Double(e.basePosition.x) * Double(size.width) + sin(phase) * 40
    let startY = Double(e.basePosition.y) * Double(size.height) + cos(phase * 0.8) * 30
    let endX = startX + Double(e.size) * Double(size.width) * cos(phase * 0.3)
    let endY = startY + Double(e.size) * Double(size.height) * sin(phase * 0.5)
    let ctrlX = (startX + endX) / 2 + sin(phase * 1.3) * 60
    let ctrlY = (startY + endY) / 2 + cos(phase * 0.9) * 60

    var path = Path()
    path.move(to: CGPoint(x: startX, y: startY))
    path.addQuadCurve(to: CGPoint(x: endX, y: endY),
                      control: CGPoint(x: ctrlX, y: ctrlY))

    context.drawLayer { ctx in
        ctx.opacity = e.opacity * (0.7 + sin(phase * e.pulseFrequency) * 0.3)
        ctx.blendMode = .plusLighter
        ctx.stroke(path,
                   with: .color(Color(hex: e.hexColor)),
                   style: StrokeStyle(lineWidth: 12, lineCap: .round))
    }
    // Add blur via a second wider, more transparent stroke
    context.drawLayer { ctx in
        ctx.opacity = e.opacity * 0.25
        ctx.blendMode = .plusLighter
        ctx.stroke(path,
                   with: .color(Color(hex: e.hexColor)),
                   style: StrokeStyle(lineWidth: 30, lineCap: .round))
    }
}
```

**Ray:**
```swift
func drawRay(_ e: CanvasElement, context: inout GraphicsContext, size: CGSize, t: Double) {
    let angle = Angle.degrees(t * e.rotationSpeed + e.phaseOffset * 57.3)
    let center = CGPoint(
        x: Double(e.basePosition.x) * Double(size.width),
        y: Double(e.basePosition.y) * Double(size.height)
    )
    let length = Double(e.size) * Double(max(size.width, size.height))
    let breathe = 0.6 + sin(t * e.pulseFrequency + e.phaseOffset) * 0.4

    context.drawLayer { ctx in
        ctx.opacity = e.opacity * breathe
        ctx.blendMode = .plusLighter
        ctx.translateBy(x: center.x, y: center.y)
        ctx.rotate(by: angle)

        let rect = CGRect(x: -4, y: -length / 2, width: 8, height: length)
        let gradient = Gradient(colors: [
            .clear,
            Color(hex: e.hexColor).opacity(0.8),
            Color(hex: e.hexColor),
            Color(hex: e.hexColor).opacity(0.8),
            .clear
        ])
        ctx.fill(
            Path(rect),
            with: .linearGradient(gradient,
                                  startPoint: CGPoint(x: 0, y: -length / 2),
                                  endPoint: CGPoint(x: 0, y: length / 2))
        )
    }
}
```

---

## 6. Canvas State & Persistence

### Today's canvas (live)
```swift
struct DayCanvas: Codable {
    let dayKey: String                          // "2026-02-12"
    var elements: [CanvasElement]               // spawned from activities
    var sleepPoints: Int
    var stepsPoints: Int
    var sleepColorHex: String
    var stepsColorHex: String
    var experienceEarned: Int
    var experienceSpent: Int
    let createdAt: Date
    var lastModified: Date
}
```

### Storage
- **Live canvas**: `UserDefaults` keyed by `"gallery_canvas_\(dayKey)"`. Updated on every activity confirmation and HealthKit refresh.
- **History**: Keep last 90 days. Older entries auto-pruned on app launch.
- **Snapshots**: On day-end (or when navigating away from today), render a static `UIImage` via `ImageRenderer` and save to `FileManager.default.urls(for: .documentDirectory)` as `"canvas_\(dayKey).png"`.

### Snapshot rendering
```swift
func saveCanvasSnapshot(canvas: DayCanvas) {
    let view = GenerativeCanvasView(
        elements: canvas.elements,
        sleepPoints: canvas.sleepPoints,
        stepsPoints: canvas.stepsPoints,
        sleepColor: Color(hex: canvas.sleepColorHex),
        stepsColor: Color(hex: canvas.stepsColorHex)
    )
    .frame(width: 390, height: 500)
    .background(Color.black)

    let renderer = ImageRenderer(content: view)
    renderer.scale = 3.0
    if let image = renderer.uiImage,
       let data = image.pngData() {
        let url = canvasSnapshotURL(for: canvas.dayKey)
        try? data.write(to: url)
    }
}
```

---

## 7. History Gallery

A horizontal scroll of past day canvases (replacing the current `MemoriesSection`).

### Layout
```
[ Today (live) ] [ Yesterday (static) ] [ 2 days ago ] [ ... ]
```

- **Today**: Full interactive `GenerativeCanvasView`, animated.
- **Past days**: Static PNG thumbnails loaded from disk. Tap to expand full-screen with stats overlay.

### Stats overlay (on tap)
Shows on top of the full-screen snapshot:
- Day date
- EXP earned / spent
- Steps count + sleep hours
- List of activities chosen (with their colors)

---

## 8. Decay: Spending EXP Degrades the Painting

When the user opens blocked apps and spends EXP, the canvas visually deteriorates. The more you spend, the more the painting falls apart. This creates a **visceral, non-verbal consequence** — you watch your art get destroyed in real-time.

### Decay metric

```swift
/// 0.0 = pristine (nothing spent), 1.0 = fully degraded (all EXP spent)
var decayNorm: Double {
    guard experienceEarned > 0 else { return 0 }
    return Double(experienceSpent) / Double(experienceEarned)
}
```

### Visual effects by decay level

| decayNorm | Name | Effects |
|-----------|------|---------|
| 0.0–0.15 | Pristine | No degradation. Clean painting. |
| 0.15–0.35 | Wear | Subtle grain overlay. Colors slightly desaturated. |
| 0.35–0.55 | Erosion | Visible noise. Elements jitter/twitch. Soft lines fragment. Gradients lose smoothness. |
| 0.55–0.75 | Damage | Heavy grain. Color channels shift (chromatic aberration). Elements glitch — random position jumps every few seconds. Rays flicker. |
| 0.75–1.0 | Ruin | Full distortion. Scanline artifacts. Elements tear and duplicate. Background gradients break into banded stripes. The painting is barely recognizable. |

### Implementation: decay effects in the Canvas draw pass

**1. Grain / noise overlay**
Draw random semi-transparent pixels over the entire canvas. Intensity scales with `decayNorm`.

```swift
func drawGrain(context: inout GraphicsContext, size: CGSize, decay: Double, t: Double) {
    guard decay > 0.15 else { return }
    let intensity = (decay - 0.15) / 0.85   // 0…1 within active range
    let grainOpacity = intensity * 0.35

    // Use a pre-rendered noise image (256x256 tiled) for performance
    // Offset it each frame for animated grain
    let offsetX = sin(t * 7.3) * 128
    let offsetY = cos(t * 5.9) * 128

    context.drawLayer { ctx in
        ctx.opacity = grainOpacity
        ctx.blendMode = .screen
        // Tile noise image across canvas
        if let noiseImage = noiseImage {
            for x in stride(from: -128 + offsetX, through: Double(size.width) + 128, by: 256) {
                for y in stride(from: -128 + offsetY, through: Double(size.height) + 128, by: 256) {
                    ctx.draw(noiseImage, in: CGRect(x: x, y: y, width: 256, height: 256))
                }
            }
        }
    }
}
```

**2. Color desaturation**
Apply per-element: mix the element's color toward gray as decay increases.

```swift
func decayedColor(_ hex: String, decay: Double) -> Color {
    let base = Color(hex: hex)
    let grayShift = max(0, (decay - 0.15) / 0.85)  // 0…1
    // Desaturate by shifting toward luminance-matched gray
    return base.saturation(1.0 - grayShift * 0.6)
}
```

**3. Element jitter / glitch**
Add random position jumps to elements. Frequency and magnitude scale with decay.

```swift
func glitchOffset(for element: CanvasElement, decay: Double, t: Double) -> CGPoint {
    guard decay > 0.35 else { return .zero }
    let intensity = (decay - 0.35) / 0.65

    // Glitch: random jump every N seconds, hold for a few frames
    let glitchCycle = 3.0 - intensity * 2.0  // faster glitches at higher decay
    let glitchPhase = floor(t / glitchCycle)
    // Deterministic "random" from element id + phase
    let seed = element.id.hashValue &+ Int(glitchPhase)
    let dx = Double((seed &* 2654435761) % 100 - 50) / 50.0 * intensity * 30
    let dy = Double((seed &* 2246822519) % 100 - 50) / 50.0 * intensity * 20

    // Only glitch for a fraction of the cycle (not constant)
    let withinCycle = t.truncatingRemainder(dividingBy: glitchCycle)
    let isGlitching = withinCycle < 0.15  // glitch for 150ms
    return isGlitching ? CGPoint(x: dx, y: dy) : .zero
}
```

**4. Chromatic aberration**
At decay > 0.55, draw the element three times with slight offsets — once red-shifted, once blue-shifted, once green-shifted.

```swift
func drawWithAberration(
    _ drawCall: (inout GraphicsContext, Color) -> Void,
    context: inout GraphicsContext,
    baseColor: Color,
    decay: Double
) {
    guard decay > 0.55 else {
        drawCall(&context, baseColor)
        return
    }
    let shift = (decay - 0.55) / 0.45 * 4  // 0…4 points of shift

    // Red channel — shift left
    context.drawLayer { ctx in
        ctx.opacity = 0.7
        ctx.blendMode = .plusLighter
        ctx.translateBy(x: -shift, y: 0)
        drawCall(&ctx, .red.opacity(0.5))
    }
    // Green channel — no shift
    context.drawLayer { ctx in
        ctx.opacity = 0.7
        ctx.blendMode = .plusLighter
        drawCall(&ctx, .green.opacity(0.5))
    }
    // Blue channel — shift right
    context.drawLayer { ctx in
        ctx.opacity = 0.7
        ctx.blendMode = .plusLighter
        ctx.translateBy(x: shift, y: 0)
        drawCall(&ctx, .blue.opacity(0.5))
    }
}
```

**5. Scanlines (heavy decay)**
At decay > 0.75, draw horizontal lines across the canvas like a broken display.

```swift
func drawScanlines(context: inout GraphicsContext, size: CGSize, decay: Double, t: Double) {
    guard decay > 0.75 else { return }
    let intensity = (decay - 0.75) / 0.25
    let lineSpacing = 4.0
    let scrollOffset = t * 40  // lines scroll slowly

    context.drawLayer { ctx in
        ctx.opacity = intensity * 0.3
        ctx.blendMode = .difference
        for y in stride(from: scrollOffset.truncatingRemainder(dividingBy: lineSpacing * 2),
                        through: Double(size.height),
                        by: lineSpacing * 2) {
            let rect = CGRect(x: 0, y: y, width: Double(size.width), height: 1)
            ctx.fill(Path(rect), with: .color(.white))
        }
    }
}
```

### Updated Canvas draw loop

```swift
Canvas { context, size in
    let t = timeline.date.timeIntervalSinceReferenceDate
    let decay = decayNorm

    // Background atmosphere
    drawSleepGradient(context: &context, size: size, t: t)
    drawStepsGradient(context: &context, size: size, t: t)

    // Activity elements (with decay effects)
    for element in elements {
        let color = decayedColor(element.hexColor, decay: decay)
        let glitch = glitchOffset(for: element, decay: decay, t: t)

        context.drawLayer { ctx in
            ctx.translateBy(x: glitch.x, y: glitch.y)
            if decay > 0.55 {
                drawWithAberration({ innerCtx, c in
                    drawElement(element, color: c, context: &innerCtx, size: size, t: t)
                }, context: &ctx, baseColor: color, decay: decay)
            } else {
                drawElement(element, color: color, context: &ctx, size: size, t: t)
            }
        }
    }

    // Post-processing overlays
    drawGrain(context: &context, size: size, decay: decay, t: t)
    drawScanlines(context: &context, size: size, decay: decay, t: t)
}
```

### DayCanvas model update

```swift
struct DayCanvas: Codable {
    // ... existing fields ...
    var experienceEarned: Int      // drives decayNorm denominator
    var experienceSpent: Int       // drives decayNorm numerator — updated on every app unlock spend
}
```

### Narrative impact

The painting is your **proof of a day lived**. Spending EXP on blocked apps literally **corrodes your art**. The history gallery becomes a visual record: clean days vs. damaged days. No numbers needed — you can *see* which days you were present and which you weren't.

---

## 9. View Hierarchy

```
MainTabView
  └─ GalleryView
       ├─ StepBalanceCard (top bar, unchanged)
       └─ ZStack
            ├─ GenerativeCanvasView (full screen, animated)
            │    ├─ Background: sleep gradient + steps gradient
            │    └─ Elements: circles, lines, rays
            ├─ Labels overlay (Mind/Heart/Body counts, semi-transparent)
            └─ RadialHoldMenu (+ button, bottom center)
                 ├─ Body node
                 ├─ Heart node
                 └─ Mind node
                      └─ onSelect → ActivityPickerSheet (with color picker)
```

---

## 10. Migration from Current Implementation

### What gets removed
- `EnergySilhouetteView` (Figma-based silhouette composition)
- `LivedEnergyTriangleView` (animated triangle/silhouette layers)
- `LivedEnergyTrianglePickerView` (triangle picker with spike labels)
- Silhouette/ellipse/mind/heart/body image assets (can keep for other screens)

### What gets reused
- `AppModel` properties: `sleepPointsToday`, `stepsPointsToday`, `activityPointsToday`, `creativityPointsToday`, `joysCategoryPointsToday`
- `EnergyCategory`, `EnergyOption`, `EnergyDefaults` — unchanged
- `ActivityPickerSheet` — extended with color picker column
- `PastDaySnapshot` — extended with `elements: [CanvasElement]` field
- `CategoryCardsRow`, `GalleryCard` — can be removed (replaced by radial menu flow)

### What gets added
| File | Contents |
|------|----------|
| `Models/CanvasElement.swift` | `CanvasElement`, `ElementKind`, `DayCanvas` models |
| `Views/GenerativeCanvasView.swift` | Canvas + TimelineView rendering engine |
| `Views/RadialHoldMenu.swift` | Long-press radial category selector |
| `Views/ColorPaletteView.swift` | Curated color grid picker |
| `Services/CanvasStorageService.swift` | Save/load/prune day canvases + snapshots |

---

## 11. Performance Considerations

- **Canvas vs SwiftUI views**: `Canvas` is significantly faster for many animated elements. It draws directly to a `CGContext` without SwiftUI's view diffing overhead. Handles 12+ elements at 30fps easily.
- **TimelineView at 30fps**: Matches current implementation. Can drop to 20fps if battery is a concern (check `ProcessInfo.processInfo.isLowPowerModeEnabled`).
- **Snapshot rendering**: Done on a background queue. `ImageRenderer` is synchronous but fast for a 390x500 canvas.
- **Memory**: Each `DayCanvas` JSON is ~2-5 KB. 90 days = ~450 KB. PNG snapshots at 3x are ~200-400 KB each. 90 days = ~30 MB. Acceptable.

---

## 12. Implementation Order

| Phase | Task | Estimate |
|-------|------|----------|
| 1 | `CanvasElement` + `DayCanvas` models | 0.5 day |
| 2 | `GenerativeCanvasView` — render circles, lines, rays | 3 days |
| 3 | Background atmosphere (sleep/steps gradients) | 1 day |
| 4 | `RadialHoldMenu` — long-press gesture + arc nodes | 2 days |
| 5 | `ColorPaletteView` — curated grid | 0.5 day |
| 6 | Wire up: activity confirm → spawn element on canvas | 1 day |
| 7 | `CanvasStorageService` — persist + snapshot | 1.5 days |
| 8 | History gallery — thumbnails + tap-to-expand | 1.5 days |
| 9 | Decay system: grain, jitter, aberration, scanlines | 2 days |
| 10 | Replace `GalleryView` internals, remove old views | 1 day |
| 11 | Polish: tuning animations, colors, positions | 2 days |
| **Total** | | **~16 days** |
