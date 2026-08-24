#include <metal_stdlib>
#include <SwiftUI/SwiftUI.h>
using namespace metal;

// ════════════════════════════════════════════════════════════════════
// MARK: - Day rays
//
// Every blade of the day's fan in ONE pass. Drawing them as separate
// SwiftUI layers would composite them over each other; the whole point
// is that they sum, so two crossing blades make a third colour that
// neither of them has. That only happens inside a single shader.
//
// A blade is a capsule of varying radius swept along its own axis, not
// an angular wedge. The wedge version made every long blade a thin
// splinter converging on the centre, which is why fifteen different
// days all read as the same starburst. As a capsule the blade keeps its
// body out to the tip, can sit detached from the centre, and can lean
// off-radial — and the silhouette (spike, petal, trapezoid, slab,
// lozenge, comet) becomes a real difference rather than a label.
//
// Blades arrive packed as floats, 12 per blade:
//   0 angle          4 halfWidthOuter   8  r
//   1 innerRadius    5 tilt             9  g
//   2 length         6 isDark           10 b
//   3 halfWidthInner 7 phase            11 softness
// ════════════════════════════════════════════════════════════════════

constant int kRayStride = 12;

// Non-default silhouettes, matching `RayBladeShape`'s case order.
// Spike is raw value 0 and intentionally uses the base profile below.
constant int kShapePetal     = 1;
constant int kShapeTrapezoid = 2;
constant int kShapeSlab      = 3;

/// Brightness along the blade. `t` runs 0 at the inner end to 1 at the tip.
static inline float drProfile(float t, int kind) {
    switch (kind) {
        case 1:  return pow(max(1.0 - t, 0.0), 1.5);            // bright inner end
        case 2:  return pow(abs(2.0 * t - 1.0), 1.2);           // both ends
        case 3: {                                                // head + tail
            float head = (t - 0.85) / 0.12;
            return exp(-head * head) + 0.35 * (1.0 - t);
        }
        default: return 0.35 + 0.65 * t;                         // burnout
    }
}

[[ stitchable ]] half4 dayRays(
    float2 position,
    half4 color,
    float2 size,
    float time,
    float2 origin,        // convergence point, in uv (may sit outside 0…1)
    float motionKind,     // 0 rotate · 1 breathe · 2 wave · 3 swirl · 4 flicker · 5 drift · 6 still
    float motionSpeed,
    float profileKind,
    float shapeKind,
    float maxLength,
    half4 bgTop,
    half4 bgBottom,
    device const float *blades,
    int bladeFloats
) {
    float2 uv = position / max(size, float2(1.0));
    float aspect = size.x / max(size.y, 1.0);

    // Short side is the unit, so blade lengths are frame-independent.
    float2 p = float2((uv.x - origin.x) * aspect, uv.y - origin.y);

    // ── Background ────────────────────────────────────────────────────
    float3 bg = mix(float3(bgBottom.rgb), float3(bgTop.rgb), 1.0 - uv.y);
    float2 c = uv - 0.5;
    bg *= 1.0 - 0.28 * smoothstep(0.30, 0.78, length(c));

    // ── Blades ────────────────────────────────────────────────────────
    int count = bladeFloats / kRayStride;
    int mode = int(motionKind);
    int prof = int(profileKind);
    int shape = int(shapeKind);

    float3 light = float3(0.0);
    float darkMask = 0.0;

    for (int i = 0; i < count && i < 48; i++) {
        int b = i * kRayStride;

        float angle  = blades[b + 0];
        float inner  = blades[b + 1];
        float len    = blades[b + 2];
        float wIn    = blades[b + 3];
        float wOut   = blades[b + 4];
        float tilt   = blades[b + 5];
        bool  isDark = blades[b + 6] > 0.5;
        float phase  = blades[b + 7];
        float3 tint  = float3(blades[b + 8], blades[b + 9], blades[b + 10]);
        float soft   = clamp(blades[b + 11], 0.05, 0.95);

        float intensity = 1.0;

        // One law of motion per day; the blade only carries its own phase.
        if (mode == 0) {
            angle += time * motionSpeed;
        } else if (mode == 1) {
            len *= 1.0 + 0.14 * sin(time * motionSpeed);
        } else if (mode == 2) {
            len *= 1.0 + 0.16 * sin(time * motionSpeed + angle * 2.0);
            inner *= 1.0 + 0.10 * sin(time * motionSpeed + angle * 2.0);
        } else if (mode == 3) {
            angle += time * motionSpeed * (len / max(maxLength, 1e-4));
        } else if (mode == 4) {
            intensity = 0.25 + 0.75 * pow(max(sin(time * motionSpeed + phase * 6.2831), 0.0), 6.0);
        } else if (mode == 6) {
            len *= 1.0 + 0.03 * sin(time * 0.12 + phase);
        }
        // mode 5 (drift) moves `origin` and is applied on the Swift side.

        // Blade frame: the axis may lean away from the radius it sits on.
        float2 radial = float2(cos(angle), sin(angle));
        float2 dir = float2(cos(angle + tilt), sin(angle + tilt));
        float2 base = radial * inner;

        float2 rel = p - base;
        float along = dot(rel, dir);
        float tRaw = along / max(len, 1e-4);
        if (tRaw < -0.25 || tRaw > 1.25) continue;

        float t = clamp(tRaw, 0.0, 1.0);
        float halfWidth = mix(wIn, wOut, t);
        if (shape == kShapePetal) {
            // Narrow at both ends, widest in the middle.
            halfWidth *= pow(sin(t * M_PI_F), 0.55) * 2.2;
        }
        halfWidth = max(halfWidth, 1e-4);

        // Distance to the blade's spine gives rounded caps for free; the
        // square-ended silhouettes cut theirs back below.
        float2 spine = base + dir * (t * len);
        float dist = length(p - spine);

        float alpha = 1.0 - smoothstep(halfWidth * (1.0 - soft),
                                       halfWidth * (1.0 + soft * 0.4),
                                       dist);
        if (shape == kShapeSlab || shape == kShapeTrapezoid) {
            alpha *= smoothstep(-0.02, 0.015, tRaw) * (1.0 - smoothstep(0.985, 1.02, tRaw));
        }

        alpha *= drProfile(t, prof) * intensity;
        if (alpha <= 0.002) continue;

        if (isDark) {
            darkMask = max(darkMask, alpha);
        } else {
            // Burnout: the inner end washes out to white, the tip keeps the hue.
            float3 shade = prof == 0 ? mix(float3(1.0), tint, clamp(t * 1.25, 0.0, 1.0)) : tint;
            light += shade * alpha;
        }
    }

    float3 col = bg * (1.0 - darkMask * 0.92);
    // Roll off only the added light, so a pale ground does not blow out.
    col += 1.0 - exp(-light * 1.15);

    return half4(half3(clamp(col, 0.0, 1.0)), color.a);
}
