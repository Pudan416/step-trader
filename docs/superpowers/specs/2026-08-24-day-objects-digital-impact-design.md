# Day Objects Digital Impact Design

**Date:** 2026-08-24

## Goal

Add cumulative digital interference to the Day Objects experiment so every
color spent during the current day leaves a visible mark on the canvas. The
effect expresses a product idea: the beauty produced by a real, color-filled
day remains present, but time spent entering digital space corrupts how that
day is seen.

At zero spent colors the canvas is completely natural. At the product ceiling
of 100 spent colors the canvas is seriously glitched while retaining roughly
25–30% visual readability, so the user can still recognize what was affected.

## Product meaning

The glitch is an absolute record of colors spent, not a percentage of colors
earned.

```text
spentColors = clamp(spentColorsToday, 0, 100)
damage      = spentColors / 100
```

Consequences:

- Spending 10 colors produces the same damage whether the user earned 10, 40,
  or 100 colors.
- Spending `10 + 10 + 10` produces the same final canvas as spending 30 once.
- Earning more colors later does not heal or dilute existing damage.
- The canvas does not need transaction timestamps, transaction sizes, or a
  purchase event stream. Only the current day's cumulative spent value matters.
- A refund reduces cumulative damage. The custom-day boundary resets it to zero.

The first implementation stays inside the Day Objects lab. Production canvas,
PayGate, historical-canvas, persistence, and export wiring are follow-up work,
but the experiment exposes an input that can later accept
`AppModel.spentStepsToday` or a persisted `DayCanvas.inkSpent` directly.

## Confirmed experience

The selected visual direction combines two forms of corruption:

1. **Persistent digital scars.** Small spends introduce a few stable damaged
   horizontal regions. Increasing the cumulative spend reveals more regions and
   strengthens existing ones.
2. **Global signal decay.** RGB separation, scanlines, and small block
   displacements become increasingly visible as the total approaches 100.

The persistent scars remain visible whenever the canvas is open. While the
canvas is actively rendering, they occasionally twitch and separate into RGB
channels. These ambient motions are derived from cumulative damage and the
daily seed; they are not tied to the moment a purchase occurs.

There is deliberately no purchase burst. Users spend colors outside the canvas,
so a short transaction animation would usually finish unseen and would add an
unnecessary event-delivery subsystem.

## Scope

Included:

- an absolute `0...100` spent-color input for Day Objects;
- deterministic daily glitch geometry;
- persistent scars, global signal decay, and ambient live motion;
- integration into the existing final Metal display pass;
- Reduce Motion behavior;
- interactive lab controls and fixed presets;
- deterministic, GPU-render, UI, accessibility, and performance checks;
- attribution for the adapted SwiftUIShaders glitch implementation.

Not included:

- connecting the experiment to `AppModel`, PayGate, or Supabase;
- observing or replaying individual payment events;
- altering the Day Objects palette, actors, score, or scene identity after a
  spend;
- replacing the production canvas;
- applying the effect to historical canvases, widgets, wallpapers, or exports;
- adding the complete SwiftUIShaders package as a dependency;
- literal one-band-per-color rendering.

## Damage model

`DayObjectDigitalImpact` is a pure value that owns the cumulative input and its
art-directed mappings:

```swift
struct DayObjectDigitalImpact: Equatable {
    static let maximumSpentColors = 100

    let spentColors: Int

    var damage: Double
    var scarStrength: Double
    var signalCorruption: Double
    var ambientMotion: Double
}
```

Construction clamps non-negative integer input to `0...100`. The derived values
remain finite and inside `0...1`:

```text
damage            = spentColors / 100
scarStrength      = damage
signalCorruption  = pow(damage, 1.6)
ambientMotion     = pow(damage, 1.35)
```

This produces a restrained low end and a severe high end:

| Spent | Damage | Signal corruption | Intended reading |
| ---: | ---: | ---: | --- |
| 0 | 0.00 | 0.00 | Untouched |
| 10 | 0.10 | ~0.03 | A few quiet scars |
| 25 | 0.25 | ~0.11 | Clearly affected on inspection |
| 50 | 0.50 | ~0.33 | Digital influence is immediately legible |
| 75 | 0.75 | ~0.63 | Most of the image participates in the damage |
| 100 | 1.00 | 1.00 | Severe corruption with 25–30% readability |

Every additional color changes the continuous strength values even when it does
not reveal a new scar. The design therefore reflects every unit without drawing
100 independent bands or allowing visual complexity to grow without bound.

## Deterministic scar layout

Each daily scene derives a fixed `DayObjectGlitchLayout` from the existing
`scene.rootSeed`. The layout contains 12 bands. Each band has:

- normalized vertical center and half-height;
- horizontal displacement direction and maximum reach;
- RGB split direction;
- activation threshold;
- ambient phase offset.

Band geometry never depends on cumulative spend. Spend only reveals and
strengthens the pre-existing daily layout, so moving from 40 to 41 colors cannot
move a scar that was already visible.

The first band begins revealing at one spent color. Remaining activation
thresholds cover the range through 100. A band's opacity, displacement, and
channel separation interpolate continuously after its threshold. The global
signal component also changes continuously at every value.

The layout uses a separate seed domain from palette, background, choreography,
and actors. Adding glitch support must not alter any existing scene output at
the same day, identity, happenings, motion, and focus inputs.

## Ambient motion

The rendered damage is persistent rather than transaction-triggered. When the
canvas is active:

- stable scars remain visible between impulses;
- day-seeded phase offsets periodically shift affected bands by a few pixels;
- RGB separation briefly widens during an impulse;
- impulse frequency and displacement scale with `ambientMotion`;
- the maximum state produces no more than 1.5 impulses per second;
- no impulse introduces a full-screen luminance flash.

The renderer's existing animation clock drives the phase and pauses with the
scene. Reopening the canvas with the same day and spent value restores the same
damage layout; it does not replay missed motion or simulate past purchases.

With Reduce Motion enabled, temporal phase is frozen, band positions remain
static, and cumulative opacity/RGB damage remains visible. Static renders use a
fixed phase and never depend on wall-clock time.

## Render pipeline

The existing pipeline remains structurally unchanged:

```text
daily palette
    ├── animated mesh-gradient background
    └── instanced actor/trail pass
                 ↓
        composite scene texture
                 ↓
          sleep focus blur
                 ↓
    digital scars and signal corruption
                 ↓
          sharp physical grain
                 ↓
               display
```

The digital effect belongs after sleep-controlled blur because it corrupts the
already composed view of the day. Existing grain remains above it so the grain
continues to read as the sharp physical texture established by the choreography
design.

The effect is implemented inside `dayObjectsDisplayFragment` in
`StepsTrader/Metal/DayObjectsPostShader.metal`. It adapts the block displacement,
RGB channel separation, scanline, and hash techniques from
SwiftUIShaders' `bcs_glitch` shader to the Day Objects texture-based MetalKit
pipeline.

No additional render target or render pass is introduced. At zero damage the
fragment shader takes an explicit natural-state path and performs the same
source sampling and display adjustments as the current renderer. At non-zero
damage it samples displaced red, green, and blue coordinates and combines them
before grain.

The implementation must cap sampling displacement so edge coordinates stay
inside the source texture and the 25–30% readability floor is preserved at 100.

## Architecture boundaries

### `DayObjectDigitalImpact`

Owns input clamping and the monotonic damage curves. It has no knowledge of
earned colors, transactions, AppModel, dates, Metal, or SwiftUI.

### `DayObjectGlitchLayout`

Derives the 12 immutable band descriptors from the scene root seed using a new
domain. Layout generation is independent of spend and render time.

### `DayObjectsView`

Accepts digital impact independently from `DayObjectSceneInput`:

```swift
DayObjectsView(
    sceneInput: input,
    digitalImpact: DayObjectDigitalImpact(spentColors: spent),
    isAnimating: true
)
```

The default impact is zero for existing callers. `DayObjectScene.make(input:)`
does not receive spend and therefore cannot reseed or rebuild actors because of
damage.

### `DayObjectsMetalView`

Passes the current impact to `DayObjectsRenderer` through the existing
`UIViewRepresentable` update path. It does not observe transactions or retain a
timeline.

### `DayObjectsRenderer`

Retains the immutable glitch layout for the active scene, converts the current
impact and animation phase into GPU-safe uniforms, and binds them only for the
display pass. Changing spend does not rebuild render targets, pipelines, actor
buffers, or choreography state.

Glitch uniforms and the fixed band array use explicit Swift/Metal alignment and
stride assertions. They remain separate from `DayObjectsPostUniforms`, whose
current focus/grain ABI stays focused and easier to validate.

### `DayObjectsPostShader.metal`

Evaluates band coverage, block displacement, RGB sampling, scanlines, and
ambient impulses. It applies no digital modification when damage is zero and no
time-based movement when Reduce Motion freezes the phase.

### `DayObjectsLabView`

Owns temporary, non-persisted lab state. It exposes:

- a `Spent colors` slider over `0...100` with step 1;
- `+1`, `+5`, and `+10` controls;
- a `Refund −10` control;
- presets for `0`, `10`, `25`, `50`, `75`, and `100`.

All controls update the same cumulative value. None creates a purchase event or
starts a transient animation. The existing grid renders its selected fixed
spent value consistently across all displayed days.

## Invalid, empty, and lifecycle states

- Negative spend clamps to zero; values above 100 clamp to 100.
- Empty scenes may still show damage over the daily background because colors
  can come from daily energy sources other than visible happening actors.
- Non-finite derived shader inputs fall back to zero before upload.
- Metal setup or allocation failure keeps the existing static-gradient fallback.
- Pausing or backgrounding freezes ambient motion without removing persistent
  damage.
- A refund updates directly to the lower cumulative state; there is no healing
  animation.
- Day rollover is represented by the caller providing zero spend for the new
  day; the experimental renderer owns no persistence or rollover logic.

## Accessibility and safety

- Reduce Motion freezes all displacement changes while retaining static damage.
- The effect does not use full-screen brightness flashes.
- Ambient impulses are capped at 1.5 Hz at maximum damage.
- RGB separation and scanlines are capped below values that erase the underlying
  composition.
- Lab controls expose stable accessibility identifiers and numeric values.
- The canvas retains its existing single accessibility label; the decorative
  glitch does not create additional VoiceOver elements.

## Attribution and dependency policy

The project does not add SwiftUIShaders as an SPM dependency. It adapts only the
relevant glitch algorithm from repository revision
`6b644a8bd4f3131401bd6765990e476352d3cdef`:

- source: <https://github.com/krispuckett/SwiftUIShaders>;
- original function: `bcs_glitch`;
- copyright: Copyright (c) 2026 Kris Puckett;
- license: MIT.

`THIRD_PARTY_NOTICES.md` must include the upstream copyright and complete MIT
license text before the adapted shader ships.

## Testing strategy

### Pure model tests

- input clamps at 0 and 100;
- the six lab presets produce the expected damage curves;
- damage, scar strength, signal corruption, and ambient motion are monotonic for
  every integer from 0 through 100;
- zero spend produces exact zero for every digital parameter;
- earned colors and transaction data are absent from the model;
- the same root seed reproduces every band descriptor;
- changing spend preserves band geometry byte-for-byte;
- the glitch seed domain does not change palette, score, or actors.

### Uniform and pipeline tests

- Swift and Metal glitch uniform alignment, offsets, size, and stride match;
- exactly 12 bounded band descriptors are uploaded;
- the display pipeline still resolves `dayObjectsDisplayFragment`;
- all uploaded values are finite and sampling reach stays within its cap;
- Reduce Motion produces a fixed phase independent of elapsed time.

### GPU render tests

- the zero-spend render matches the existing natural-canvas perceptual baseline;
- fixed-seed renders at `10`, `25`, `50`, `75`, and `100` differ monotonically
  according to corruption signatures;
- 100 retains the agreed 25–30% readability of the source composition;
- identical day, spend, and fixed phase reproduce identical pixels;
- different days produce different scar layouts without changing spend curves;
- empty-scene, dark-palette, light-palette, portrait, and landscape cases remain
  finite and nonblank.

### UI tests

- slider and buttons clamp correctly at both endpoints;
- each preset updates the numeric readout and canvas;
- refund lowers the same cumulative value without a separate animation control;
- toggling the existing grid keeps the selected spend value;
- Reduce Motion leaves a stable, visibly damaged frame at non-zero spend.

### Performance validation

Measure on a physical supported iPhone at 30 FPS with 40 actors and spent values
of 0, 50, and 100. The maximum-damage case must remain below the existing p95
GPU frame-time target of 25 ms during a five-minute run without sustained
thermal escalation. Simulator timing is not performance evidence.

The zero-damage path must not perform displaced RGB samples. The implementation
adds no render pass and no per-frame heap allocation.

## Acceptance criteria

1. Zero spent colors renders the natural Day Objects canvas with no digital
   residue.
2. Cumulative damage is based only on absolute spent colors clamped to 0...100.
3. Every additional spent color monotonically increases at least one visible
   damage parameter.
4. Earning additional colors does not reduce existing damage.
5. Small spends create quiet stable scars; 50 is immediately legible; 100 is
   severe while preserving 25–30% source readability.
6. Existing scars never move or reseed when spend changes.
7. Ambient motion occurs only while the canvas is active and is never tied to a
   purchase event.
8. Reduce Motion preserves static cumulative damage without temporal twitching.
9. Palette, actors, score, focus, and grain keep their existing deterministic
   behavior.
10. The implementation adds no Swift package dependency or additional render
    pass and meets the physical-device performance target.
11. Lab controls cover the complete 0...100 range without persistence or
    production-model coupling.
12. The adapted shader is accompanied by complete MIT attribution.
