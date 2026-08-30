#include <metal_stdlib>
#include <SwiftUI/SwiftUI.h>
using namespace metal;

// ════════════════════════════════════════════════════════════════════
// MARK: - Canvas dust
//
// One plane of suspended motes. The view stacks three of these at
// different scales and blurs — fine and dense far away, a handful of
// large soft discs up close. That contrast is what reads as air.
//
// Output is premultiplied with a real alpha so the layer can be
// composited additively over the canvas without a second pass.
// ════════════════════════════════════════════════════════════════════

static inline float dustHash12(float2 p) {
    float3 p3 = fract(float3(p.x, p.y, p.x) * 0.1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

static inline float2 dustHash22(float2 p) {
    float3 p3 = fract(float3(p.x, p.y, p.x) * float3(0.1031, 0.1030, 0.0973));
    p3 += dot(p3, p3.yxz + 33.33);
    return fract((p3.xx + p3.yz) * p3.zy);
}

[[ stitchable ]] half4 canvasDust(
    float2 position,
    half4 color,
    float2 size,
    float time,
    float scale,      // motes per unit — the plane's grain
    float density,    // 0…1, from steps
    float drift,      // parallax speed multiplier
    half4 tint
) {
    float2 uv = position / max(size, float2(1.0));
    float aspect = size.x / max(size.y, 1.0);

    // Drift is slow and diagonal. Motes hanging in the air do not travel,
    // they wander — anything faster reads as snowfall.
    float2 p = uv * float2(aspect, 1.0) * scale;
    p += float2(time * 0.0045, -time * 0.0075) * drift * scale;

    float2 cell = floor(p);
    float2 f = fract(p) - 0.5;

    float h = dustHash12(cell);
    // More steps, more in the air. The window is narrow on purpose: even a
    // still day should have some, or the frame goes airless.
    float threshold = mix(0.955, 0.72, clamp(density, 0.0, 1.0));
    if (h < threshold) {
        return half4(0.0h);
    }

    // Jitter inside the cell, or the field reads as a grid.
    float2 offset = (dustHash22(cell + 7.31) - 0.5) * 0.7;
    float d = length(f - offset);

    // Size varies per mote so a plane is not a field of identical dots.
    float radius = mix(0.10, 0.30, dustHash12(cell + 19.7));
    float body = exp(-(d * d) / (radius * radius));

    // Slow individual twinkle, out of phase per mote.
    float twinkle = 0.55 + 0.45 * sin(time * 0.7 + h * 41.0);

    float a = body * twinkle * clamp(float(tint.a), 0.0, 1.0);
    if (a < 0.002) {
        return half4(0.0h);
    }

    return half4(half3(tint.rgb) * half(a), half(a));
}
