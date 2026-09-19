#include <metal_stdlib>
using namespace metal;

// ════════════════════════════════════════════════════════════════════
// MARK: - Cosmic field
// Multi-octave FBM passed through one round of domain-warping (Inigo
// Quilez trick), coloured with a soft cosine palette, modulated by a
// finger-driven warp (radial pinch + tangential swirl + velocity drag).
// Idle = fully transparent; touch ramps in immersively.
// ════════════════════════════════════════════════════════════════════

struct ShaderParkParams {
    float2 resolution;   // pixels
    float  time;         // seconds since renderer start
    float  click;        // 0…1 attack/decay
    float2 touch;        // current touch in aspect-corrected uv space
    float2 velocity;     // per-frame finger delta in uv space
    float  hueOffset;    // palette phase nudge (cycles)
    float  ringFreq;     // unused — kept for ABI parity with renderer
};

struct VertexOut {
    float4 position [[position]];
    float2 uv;
};

vertex VertexOut shaderParkVertex(uint vid [[vertex_id]]) {
    constexpr float2 positions[] = {
        float2(-1, -1), float2(1, -1), float2(-1, 1), float2(1, 1)
    };
    constexpr float2 uvs[] = {
        float2(-1, -1), float2(1, -1), float2(-1, 1), float2(1, 1)
    };
    VertexOut out;
    out.position = float4(positions[vid], 0, 1);
    out.uv       = uvs[vid];
    return out;
}

// ──────────────────────────────────────────────────────────────────
// Value noise + 5-octave FBM
// ──────────────────────────────────────────────────────────────────

static inline float spHash(float3 p) {
    p = fract(p * 0.3183099 + 0.1);
    p *= 17.0;
    return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

static inline float spValueNoise(float3 x) {
    float3 i = floor(x);
    float3 f = fract(x);
    f = f * f * (3.0 - 2.0 * f);
    float n000 = spHash(i + float3(0,0,0));
    float n100 = spHash(i + float3(1,0,0));
    float n010 = spHash(i + float3(0,1,0));
    float n110 = spHash(i + float3(1,1,0));
    float n001 = spHash(i + float3(0,0,1));
    float n101 = spHash(i + float3(1,0,1));
    float n011 = spHash(i + float3(0,1,1));
    float n111 = spHash(i + float3(1,1,1));
    return mix(mix(mix(n000, n100, f.x),
                   mix(n010, n110, f.x), f.y),
               mix(mix(n001, n101, f.x),
                   mix(n011, n111, f.x), f.y), f.z);
}

// 5-octave FBM. Persistence 0.5 → classic 1/f spectrum, soft + smoky.
static inline float spFbm5(float3 p) {
    float v = 0.0;
    float a = 0.55;
    for (int i = 0; i < 5; i++) {
        v += a * spValueNoise(p);
        p = p * 2.02 + float3(0.13, 0.41, 0.27);
        a *= 0.52;
    }
    return v;
}

// One round of domain-warping. The output of fbm offsets the next fbm
// lookup, which produces the swirling "galactic gas" look without any
// extra geometry.
static inline float3 spWarpedField(float3 p) {
    float3 q = float3(
        spFbm5(p),
        spFbm5(p + float3(5.2, 1.3, 2.4)),
        spFbm5(p + float3(1.7, 8.3, 4.6))
    );
    float3 r = float3(
        spFbm5(p + 2.2 * q + float3(1.7, 9.2, 0.4)),
        spFbm5(p + 2.2 * q + float3(8.3, 2.8, 5.1)),
        spFbm5(p + 2.2 * q + float3(3.5, 6.7, 1.8))
    );
    return r;
}

// ──────────────────────────────────────────────────────────────────
// Cosmic cosine palette (Inigo Quilez form)
// Tuned toward indigo / violet / dusty-rose — no harsh primaries.
// ──────────────────────────────────────────────────────────────────

static inline float3 cosmicPalette(float t) {
    constexpr float3 a = float3(0.42, 0.38, 0.52);
    constexpr float3 b = float3(0.32, 0.28, 0.42);
    constexpr float3 c = float3(0.95, 1.00, 0.85);
    constexpr float3 d = float3(0.05, 0.20, 0.45);
    return a + b * cos(6.28318530718 * (c * t + d));
}

// ──────────────────────────────────────────────────────────────────
// Fragment
// ──────────────────────────────────────────────────────────────────

fragment float4 shaderParkFragment(
    VertexOut in                       [[stage_in]],
    constant ShaderParkParams &params  [[buffer(0)]]
) {
    float aspect = params.resolution.x / max(params.resolution.y, 1.0);
    float2 uv = in.uv;
    uv.x *= aspect;                           // aspect-corrected ndc

    // ── Finger warp field ────────────────────────────────────────
    float2 toTouch = uv - params.touch;
    float  dist    = length(toTouch);
    float  sigma   = 0.55;
    float  falloff = exp(-dist * dist / (sigma * sigma));
    float  speed   = length(params.velocity);
    float  live    = max(params.click, saturate(speed * 5.0));
    float  warp    = falloff * live;

    // Radial pinch + 90° tangential swirl + drag along velocity. The
    // tangential component is what makes the field feel like a slow
    // galactic vortex around the finger instead of a flat dent.
    float2 disp = float2(0);
    if (dist > 1e-3) {
        float2 inv    = 1.0 / max(dist, 1e-3);
        float2 radial = -toTouch * inv;
        float2 perp   = float2(-toTouch.y, toTouch.x) * inv;
        disp += radial * warp * 0.30;
        disp += perp   * warp * 0.45;
    }
    disp += params.velocity * warp * 6.0;

    // ── Sample the warped field ─────────────────────────────────
    // Big, slow structure: scale 0.85 (broad blobs), time 0.055 (drifting
    // not racing). Hue phase nudged by `hueOffset` so each session looks
    // slightly different without repeating.
    float scale       = 0.85;
    float3 samplePos  = float3((uv + disp) * scale,
                               params.time * 0.055 + params.hueOffset);
    float3 q          = spWarpedField(samplePos);
    float  t          = saturate(0.5 + 0.55 * (q.x - q.z));

    float3 col = cosmicPalette(t);

    // Subtle inner glow at the touch — pulls the eye in without flashing.
    col += float3(0.05, 0.03, 0.12) * warp;

    // Slight desaturation toward an inky base so the canvas stays present
    // through the overlay rather than getting bleached out.
    constexpr float3 inkyBase = float3(0.06, 0.05, 0.09);
    col = mix(inkyBase, col, 0.78);

    // ── Alpha ─────────────────────────────────────────────────────
    // Idle = transparent. Touch peaks at ~0.55, never opaque, so the
    // overlay always feels like fog rather than a solid sheet.
    float alpha = 0.55 * smoothstep(0.0, 1.0, live);

    // Slight extra opacity in the warped core so the finger has a clear
    // halo without letting the rest of the screen go bright.
    alpha = saturate(alpha + 0.18 * warp);

    return float4(col * alpha, alpha);
}
