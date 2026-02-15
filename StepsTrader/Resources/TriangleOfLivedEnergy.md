# The Triangle of Lived Energy (TLE)

## What this is
**TLE is a per-day visual memory**: a triangle that encodes (1) where the day went (**Body/Mind/Heart**), (2) what held it up (**Steps/Sleep**), and (3) what remains (**available EXP vs spent**).

This is explicitly **not** productivity or “performance”. It’s *direction + foundation + remaining resource*.

In Steps4 terms, it maps cleanly onto the existing 5-metric EXP model:
- **Body** = `activityPointsToday` (0–20)
- **Mind** = `creativityPointsToday` (0–20)
- **Heart** = `joysCategoryPointsToday` (0–20)
- **Steps** = `stepsPointsToday` (0–20)
- **Sleep** = `sleepPointsToday` (0–20)
- **Total earned (foundation+direction)** = `baseEnergyToday` (0–100)
- **Current remaining (selected for TLE size)** = `totalStepsBalance` (**remaining balance**, base+bonus)
- **Potential energy for the day (outline)** = `baseEnergyToday + bonusSteps` (capped by your existing invariant to \(\le 100\))
- **Spent (derived)** = `potential - currentRemaining`

Relevant code reality today:
- “Earned EXP” is computed in `AppModel+DailyEnergy.recalculateDailyEnergy()` as the sum of the five metrics (capped to 100).
- Remaining balance (base+bonus) is available via `UserEconomyStore.totalStepsBalance` and is what will drive TLE “current size”.
- Past days already have `PastDaySnapshot(experienceEarned, experienceSpent, steps, sleepHours, activityIds, creativityIds, joysIds)`.

## Locked concept v2 (authoritative)
This section is the source of truth and overrides any conflicting earlier notes.

### First state (before actions)
- Show a **small triangle in the center**.
- Show a **`+` sign inside** the triangle.
- **Inner yellow gradient** = how much EXP was earned from **Steps** today, out of 20.
- **Outer purple gradient/glow** = how much EXP was earned from **Sleep** today, out of 20.

### Add activity flow
- User taps `+`.
- A picker opens (sheet/popover), grouped by **Body / Mind / Heart** activities.
- Each confirmed activity increments one related spike by **+1 level**.
- Each spike has **max 4 levels**.
- Triangle grows/deforms per spike independently.
- Triangle does **not spin**.

### Outer motion behavior
- No static outer border.
- Instead: a **running ray of light** on the outside path, moving **counter-clockwise**.
- This ray indicates max envelope for today.

### Spend behavior
- When EXP is spent (app entry), the filled triangle gets slightly smaller.
- The running outer ray keeps moving on the **maximum size reached for today**.
- This creates visible contrast between:
  - total earned today (max envelope/ray path),
  - what remains now (current filled triangle).

## The visual language

### 1) Triangle = direction (Body / Mind / Heart)
Each angle (Body / Mind / Heart) grows **independently** and has **4 discrete lengths**:
- Level 0: no growth
- Level 1: small growth
- Level 2: medium growth
- Level 3: full growth
- Level 4: max growth

Mapping rule (locked):
- each category has 0..20 points
- convert to level with `level = min(4, points / 5)` (integer buckets)
- each angle uses its own level; one angle can be level 4 while others stay level 0/1

Interpretation:
- A sharp “top” (Heart) = emotionally/relationally rich day.
- A broad “base” (Body) = embodied/movement day.
- A skew (Mind) = cognitive/creative day.

**Key: this deformation answers “where life was expressed”, not “how much was done.”**

### 2) Interior gradient = foundation (Steps / Sleep)
Steps and Sleep do not move vertices. They modulate the *inner field*:
- **Sleep → center glow** (restoration / softness)
- **Steps → color depth / density** (embodied vitality)

The gradient *enriches*; it doesn’t distort the silhouette.

Color decision (locked):
- **Sleep = purple**
- **Steps = yellow**

Meaning decision (locked):
- **Purple (outer glow/gradient ring)** encodes **sleep EXP progress** in range 0..20.
- **Yellow (inner fill/gradient)** encodes **steps EXP progress** in range 0..20.

Practical palette (iOS-friendly defaults):
- Sleep purple: `Color.purple` (or a custom like `#AF52DE`)
- Steps yellow: `Color.yellow` (or a custom like `#FFD60A`)

### 3) Size = available energy (potential vs current)
Two layered triangles:
- **Potential outline**: how large the triangle can be given the day’s **potential balance** (earned + bonus).
- **Current filled**: how much remains right now (**remaining balance**).

When the user spends EXP:
- the **filled** triangle shrinks
- the **outline** remains (the day’s structure is still visible)

**The shape does not collapse; only its magnitude changes.**

## Proposed mathematical model (production-friendly)

### Inputs (normalized)
Let:
- \(b, m, h \in [0, 1]\) = Body/Mind/Heart normalized by 20
- \(st, sl \in [0, 1]\) = stepsPoints/sleepPoints normalized by 20
- \(E \in [0, 100]\) = earned (base) EXP for day
- \(B \in [0, 100]\) = bonus EXP for day (`bonusSteps`)
- \(P = clamp(E + B, 0, 100)\) = potential balance (outline)
- \(R = clamp(remainingBalance, 0, P)\) = remaining balance (filled)
- \(p = P / 100\), \(r = R / 100\)

### Shape deformation
Base triangle is equilateral, centered, pointing upward.

Each angle gets its own independent growth offset:
- \(L_b, L_m, L_h \in \{0,1,2,3,4\}\)
- \(d_b = \alpha \cdot (L_b / 4)\)
- \(d_m = \alpha \cdot (L_m / 4)\)
- \(d_h = \alpha \cdot (L_h / 4)\)

Where **\(\alpha\)** is the maximum deformation ratio (suggest starting at **0.18**; tweak visually).

Implementation note: deformation should be applied in the triangle’s local coordinates *before* global scaling, so the silhouette is stable and the energy scaling feels like “zooming the same day”.

### Potential vs current scaling
We want “size represents energy”. Two viable mappings:
- **Linear radius**: `scale = p` and `scale = r`
- **Linear area** (more perceptual honesty): `scale = sqrt(p)` and `scale = sqrt(r)`

Decision: ship **area-linear** (sqrt). It keeps low-energy days from looking “too dead” while preserving proportional area.

### Foundation gradient
A simple, controllable mapping:
- **sleep glow**: radial gradient center alpha \(= lerp(0.04, 0.22, sl)\)
- **steps depth**: saturation/contrast \(= lerp(0.35, 1.0, st)\)

Gradient can be implemented as:
- fill = base tint color × steps depth
- overlay = radial “glow” × sleep intensity

## UI placement (locked)
Decision: **replace the Gallery option card rows with a single interactive triangle picker**, where the selectable cards remain **inside each corresponding angle**:
- Body options live in the Body wedge
- Mind options live in the Mind wedge
- Heart options live in the Heart wedge

The triangle is simultaneously:
- a day-level visualization (direction/foundation/remaining)
- the interaction surface for selecting the day’s cards (up to 4 per category)

Interaction update (locked):
- The activity lists are **not visible by default** on screen.
- Each angle has a corner `+` button.
- Tapping `+` opens that category picker sheet/popover with the list of activities.

## Production task: implement TLE in Steps4 (v1)

### Goal
Introduce an **interactive triangle picker** in `GalleryView` that:
- **replaces** `CategoryCardsRow` horizontally scrolling rows
- keeps the same selection rules (max 4 per category, confirmation, etc.)
- visualizes direction/foundation/current-vs-potential at a glance
- animates independently for (a) vertex deformation, (b) gradient, (c) spending shrink

### Non-goals (v1)
- New data collection (no new “activity point entry” UI)
- Redesigning the selection rules (still 4 max per category)

### Deliverables

#### 1) Triangle rendering component (non-interactive core)
Add a reusable SwiftUI component:
- **`LivedEnergyTriangleView`** (name suggestion)
  - inputs:
    - `potentialXP: Int` (0–100) (outline scale)
    - `remainingXP: Int` (0–100) (filled scale)
    - `body: Int`, `mind: Int`, `heart: Int` (0–20)
    - `steps: Int`, `sleep: Int` (0–20)
    - `style: Style` (colors, line widths, corner rounding, etc.)
    - `animationKey: AnyHashable` (optional, to isolate animations)
  - outputs:
    - composited view with:
      - outline triangle (potential)
      - filled triangle (current)
      - clipped interior gradient
      - stable direction silhouette

Implementation approach (pragmatic):
- `LivedEnergyTriangleShape: Shape` builds the deformed triangle path.
- Use `Canvas` (or `Shape.fill().overlay().mask()`) to:
  - stroke outline at potential scale
  - fill current at current scale with gradient masked to the shape

Performance targets:
- fast enough to show **~60 day tiles** in a horizontal list without hitching
- no heavy per-frame randomness; any noise must be deterministic by `dayKey`

Accessibility:
- `.accessibilityLabel` summarizing earned/current and the 5 metrics

#### 2) Model adapter for “today” vs “past day” (with stored targets per day)
Create a small adapter layer (even if just functions) to generate triangle inputs from:
- Today (from `AppModel`)
- Past day (from `PastDaySnapshot`)

For past days:
- direction points can be derived from ids count:
  - body = `min(activityIds.count, 4) * 5` (0–20)
  - mind = `min(creativityIds.count, 4) * 5` (0–20)
  - heart = `min(joysIds.count, 4) * 5` (0–20)
- foundation points must use **the targets that were active that day** (stored per day):
  - stepsPoints = `20 × min(steps, stepsTarget) / stepsTarget`
  - sleepPoints = `20 × min(hours, sleepTargetHours) / sleepTargetHours`

Schema change:
- extend `PastDaySnapshot` to include `stepsTarget: Int` (or `Double`) and `sleepTargetHours: Double`
- write them when saving snapshot at day rollover
- decode them with backward compatibility (missing → default to current or `EnergyDefaults`)

#### 3) Gallery integration (interactive triangle picker)
In `GalleryView`:
- Replace the `VStack` of `CategoryCardsRow(...)` with **one** `LivedEnergyTrianglePickerView` that:
  - renders `LivedEnergyTriangleView` as the background (potential vs remaining)
  - shows only lightweight in-angle status/chips (selected summary), not the full option list
  - exposes a `+` trigger per angle to open category options

Picker rules (must match today’s behavior):
- **max 4 selections per category**
- selection requires **confirm** (“cannot be undone today”)
- already-selected items show the existing “cross/mark” affordance (or the new in-triangle equivalent)

Layout constraints (core requirement from you):
- The selectable cards must remain **inside each corresponding angle**.
- No cross-wedge overlap; a card is unambiguously Body vs Mind vs Heart by location alone.

Implementation approach (v1-friendly):
- Build three invisible wedge hit-test regions (Body/Mind/Heart) based on the triangle geometry.
- In each wedge, place:
  - current level indicator (0..4)
  - selected count (`x/4`)
  - corner `+` button for opening picker
- Category picker UI is a sheet/popover (`CategoryEditSheet` / category selector) shown only after `+` tap.

Memories/history:
- Keep `MemoriesSection` (horizontal strip), but replace `MemoryDayCard` with a small triangle tile (non-interactive picker; tap opens existing day sheet).
- For past days, triangle inputs come from snapshot + stored targets.

#### 4) Animation rules (hard requirement)
Honor the “never all three at once” principle:
- **Vertex deformation** animates only when Body/Mind/Heart changes (card selection toggles)
- **Gradient** animates only when Steps/Sleep changes (HealthKit update / sleep sync)
- **Scale** animates only when **remaining balance** changes (`totalStepsBalance`)

Additionally (new): **Idle “living” motion** (optional but desired)
- The triangle should *breathe* and move subtly like a living organism.
- The triangle should **not spin constantly**.
- Motion should keep the triangle in the **same visual position** (tiny local motion only).
- This motion must be **purely cosmetic** and should not mask the semantic animations above.
- Keep it subtle: users should perceive it as “alive”, not “attention-seeking”.

Production constraints for idle motion:
- Use **low amplitude** transforms (tiny scale pulse + micro offset).
- Use **long durations** (6–14s), smooth/easing or sinusoidal motion.
- Respect **Reduce Motion** (disable or reduce amplitudes when `UIAccessibility.isReduceMotionEnabled`).
- For lists (memories strip), consider disabling idle motion to avoid perf + visual noise; enable only on the focused “Today” triangle.

Implementation sketch (SwiftUI)
- Breathing via slow pulse:
  - `scaleEffect(1 + sin(phase) * 0.01 ... 0.02)`
  - optional `offset(y: sin(phase * 0.8) * 1 ... 2)`
- Liquid feel without whole-triangle spin:
  - animate gradient phase/center/noise, but keep shape orientation stable
  - avoid continuous `rotationEffect` on the triangle container

Concrete parameters (starting point):
- breathing amplitude: 1-2%
- breathing period: 8-14s
- micro drift: 1-2pt max
- gradient phase cycle: 12-24s (no rigid full-spin requirement)

Gradient composition suggestion (reads “sleep vs steps” while moving):
- Base: `AngularGradient(colors: [stepsYellow, sleepPurple, stepsYellow], center: .center)`
- Overlay: a soft radial glow whose alpha is driven by sleep score (purple-ish center bloom)

Implementation detail:
- Use separate `.animation(..., value:)` modifiers per parameter group.
- Avoid a single `withAnimation` around broad state updates in the parent view.

#### 5) Analytics
Add events (if you want them):
- `triangle_day_tapped` with `{ day_key, earned, spent, remaining }`
- optionally `triangle_rendered` (dedupe by day key to keep noise down)

### Acceptance criteria
- **Correctness**
  - Potential outline scale matches **potential balance** \(P = earned + bonus\) (capped to 100).
  - Filled scale matches **remaining balance** \(R\) (clamped; never exceeds outline).
  - Body/Mind/Heart deformation is stable and deterministic per metric values.
  - Steps/Sleep only affects interior (no vertex movement).
- **UX**
  - At a glance you can distinguish:
    - a body-heavy day vs mind-heavy day vs heart-heavy day
    - high-sleep soft glow vs low-sleep flat interior
    - a “spent down” day vs “still full” day
  - Spending visibly shrinks filled triangle while keeping outline.
- **Performance**
  - No scrolling hitches in a 60-day horizontal list on mid-tier devices.
- **Accessibility**
  - VoiceOver reads a useful summary (earned/remaining + direction + foundation).

### Edge cases to handle
- Earned = 0 (still render a minimal faint outline; filled = 0)
- Remaining > Potential (clamp filled to outline)
- Old snapshots missing `steps`/`sleepHours` (already default to 0)
- Migration: old snapshots missing `stepsTarget`/`sleepTargetHours` use sensible defaults

## Locked decisions (from you)
- **Size driver**: filled triangle size = **remaining balance** (`totalStepsBalance`).
- **Gallery UI**: replace rows of cards with a **single triangle picker**; cards remain **inside their angle**.
- **History accuracy**: **store steps/sleep targets per day** in `PastDaySnapshot` and use them for reconstruction.
- **Energy-size mapping**: use **area-linear** scaling (sqrt).
- **Angle growth model**: each angle grows independently with **4 lengths** (plus zero baseline).
- **Idle motion**: breathing/living motion only, **no constant triangle spin**, stable on-screen position.
- **Activity list visibility**: hidden by default; open via corner `+` button.

## Activity taxonomy (locked)

### BODY
Ways your body was truly present today.
1. Walking - Moving forward with your body in the world.  
   Examples: city walk, nature walk, walking without a goal
2. Physical Effort - Using strength and resistance.  
   Examples: gym, home workout, carrying, manual work
3. Stretching - Opening and releasing tension.  
   Examples: stretching, yoga, mobility, slow warm-up
4. Resting - Allowing the body to recover.  
   Examples: good sleep, lying down, intentional break
5. Breathing - Returning to your physical rhythm.  
   Examples: breathing pause, calming breath, mindful inhale
6. Touch - Feeling the world through contact.  
   Examples: water, grass, sunlight, physical grounding
7. Balance - Holding yourself steady and aware.  
   Examples: slow movement, posture work, standing still
8. Repetition - Doing simple physical actions with presence.  
   Examples: cleaning, tidying, daily routines
9. Warming - Feeling heat and comfort in the body.  
   Examples: hot shower, sun exposure, warm drink
10. Stillness - Being completely motionless for a moment.  
    Examples: sitting quietly, body scan, silent pause

### MIND
Ways your attention shaped the day.
1. Focusing - Holding attention on one thing.  
   Examples: reading, deep work, careful listening
2. Learning - Taking something new into the mind.  
   Examples: studying, educational content, skill practice
3. Thinking - Actively processing ideas or situations.  
   Examples: reflecting, problem-solving, mental exploration
4. Planning - Organising what comes next.  
   Examples: structuring tasks, setting priorities
5. Writing - Turning thoughts into form.  
   Examples: journaling, notes, drafting ideas
6. Observing - Noticing without interfering.  
   Examples: watching people, noticing patterns, awareness
7. Questioning - Challenging assumptions.  
   Examples: asking why, rethinking, curiosity moments
8. Ordering - Creating clarity and structure.  
   Examples: organising files, simplifying, arranging ideas
9. Remembering - Returning to past experience consciously.  
   Examples: reviewing the day, recalling a memory
10. Letting Go - Releasing mental tension.  
    Examples: closing tasks, stopping overthinking, pause

### HEART
Ways you felt and connected today.
1. Joy - Feeling lightness and warmth.  
   Examples: laughter, playful moments, spontaneous happiness
2. Calm - Feeling settled and safe inside.  
   Examples: quiet time, relaxation, emotional ease
3. Gratitude - Recognising something as valuable.  
   Examples: appreciating a moment, feeling thankful
4. Connection - Feeling close to someone.  
   Examples: meaningful talk, shared silence
5. Care - Giving attention and warmth.  
   Examples: helping, supporting, caring for yourself
6. Wonder - Feeling awe or curiosity.  
   Examples: noticing beauty, surprise, inspiration
7. Trust - Allowing openness without tension.  
   Examples: relying on someone, emotional safety
8. Vulnerability - Allowing yourself to feel honestly.  
   Examples: emotional openness, sincere sharing
9. Belonging - Feeling part of something.  
   Examples: community, shared identity, feeling at home
10. Peace - Deep inner quiet.  
    Examples: acceptance, emotional stillness

## Optional extensions (nice later)
- Bonus energy visualization (halo ring around the outline, or a second faint outer field)
- Tiny “spend ticks” animation (subtle shrink pulses when spending happens)
- Weekly strip: 7 triangles in a row as a week memory
- Screenshot-ready export of a day triangle as an image (shareable memory)

