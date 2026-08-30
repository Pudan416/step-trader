#include <metal_stdlib>
#include <SwiftUI/SwiftUI.h>
using namespace metal;

// ════════════════════════════════════════════════════════════════════
// MARK: - Generative daily scene
//
// A density-field raymarch, not a surface SDF. The march integrates a
// thin shell of density around a deformed sphere, so translucency,
// internal glow and the bright grazing-angle rim come out of the
// integration itself instead of being approximated with alpha. That
// difference is what separates "a flat blob" from "a lit volume".
//
// Data mapping (see GenerativeSceneParams.swift for the Swift side):
//   energy  → size, spark density, emission, motion amplitude
//   sleep   → clarity: depth of the darks, thinness of the membrane,
//             calmness of the contour. Deliberately NOT brightness —
//             steps already own that channel.
//   events  → lobes fused into the body; near ones merge, far ones
//             stay separate bubbles
//   seed    → the day's variation: orientation, lobe placement, phase
// ════════════════════════════════════════════════════════════════════

// MARK: - Hash / noise

static inline float gsHash13(float3 p3) {
    p3 = fract(p3 * 0.1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

static inline float gsHash12(float2 p) {
    float3 p3 = fract(float3(p.x, p.y, p.x) * 0.1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

static inline float gsNoise(float3 x) {
    float3 i = floor(x);
    float3 f = fract(x);
    f = f * f * (3.0 - 2.0 * f);

    float a = gsHash13(i + float3(0.0, 0.0, 0.0));
    float b = gsHash13(i + float3(1.0, 0.0, 0.0));
    float c = gsHash13(i + float3(0.0, 1.0, 0.0));
    float d = gsHash13(i + float3(1.0, 1.0, 0.0));
    float e = gsHash13(i + float3(0.0, 0.0, 1.0));
    float g = gsHash13(i + float3(1.0, 0.0, 1.0));
    float h = gsHash13(i + float3(0.0, 1.0, 1.0));
    float k = gsHash13(i + float3(1.0, 1.0, 1.0));

    float z0 = mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
    float z1 = mix(mix(e, g, f.x), mix(h, k, f.x), f.y);
    return mix(z0, z1, f.z);
}

/// Octave count is a runtime bound so the lab can trade quality for frame
/// time on device; the loop bound stays constant so the compiler can unroll.
static inline float gsFbm(float3 p, int octaves) {
    float amp = 0.5;
    float sum = 0.0;
    for (int i = 0; i < 4; i++) {
        if (i >= octaves) break;
        sum += amp * gsNoise(p);
        p *= 2.03;          // not exactly 2 — avoids axis-aligned banding
        amp *= 0.5;
    }
    return sum;
}

/// Inigo Quilez's polynomial smooth minimum. This is the mechanism behind
/// "similar elements merge": large `k` fuses two masses into one body with a
/// neck, `k → 0` leaves them as separate objects.
static inline float gsSmin(float a, float b, float k) {
    float h = clamp(0.5 + 0.5 * (b - a) / max(k, 1e-4), 0.0, 1.0);
    return mix(b, a, h) - k * h * (1.0 - h);
}

// MARK: - Field

/// Signed distance to the day's body. Positive outside.
static inline float gsBody(float3 p,
                           float time,
                           float seed,
                           float energy,
                           float turbulence,
                           float events) {
    // The noise domain rotates slowly instead of the geometry: the scene
    // evolves continuously and never regenerates.
    float ang = time * 0.045 + seed * 6.2831;
    float ca = cos(ang);
    float sa = sin(ang);
    float3 q = float3(ca * p.x - sa * p.z, p.y, sa * p.x + ca * p.z);

    float radius = mix(0.50, 0.84, energy);
    float d = length(p) - radius;

    // Domain warping first, then fbm — this is what reads as smoke rather
    // than as a noisy sphere. https://iquilezles.org/articles/warp/
    float3 w = q * 1.5 + float3(0.0, time * 0.055, seed * 11.0);
    float warp = gsFbm(w, 2);
    float n = gsFbm(q * 1.85 + warp * 1.6 + seed * 4.0, 3) - 0.5;
    d += n * mix(0.07, 0.26, turbulence) * radius;

    // Event lobes. Distance from the body decides the blend: what sits close
    // fuses into one mass, what drifts away stays a separate bubble.
    int lobes = int(floor(events * 5.0 + 0.001));
    for (int i = 0; i < 5; i++) {
        if (i >= lobes) break;
        float fi = float(i) + 1.0;
        float h1 = fract(sin(seed * 91.7 + fi * 17.3) * 43758.5453);
        float h2 = fract(sin(seed * 47.1 + fi * 29.7) * 22578.1459);
        float h3 = fract(sin(seed * 13.9 + fi * 7.11) * 31415.9265);

        float theta = h1 * 6.2831 + time * 0.07 * (h2 - 0.5);
        float phi = 0.4 + h2 * 2.3;
        float spread = radius * mix(0.72, 1.65, h3);
        float3 centre = float3(sin(phi) * cos(theta),
                               cos(phi) * 0.8,
                               sin(phi) * sin(theta)) * spread;
        float lobe = length(p - centre) - radius * mix(0.15, 0.33, h1);

        float k = mix(0.40, 0.03, smoothstep(0.95, 1.5, spread / radius));
        d = gsSmin(d, lobe, k);
    }
    return d;
}

/// Density concentrated in a shell around the surface. A solid interior would
/// read as an opaque ball; the shell is what makes it a membrane you see into.
static inline float gsShell(float dist, float thickness) {
    float x = dist / thickness;
    return exp(-x * x);
}

// MARK: - Entry point

[[ stitchable ]] half4 generativeScene(
    float2 position,
    half4 color,
    float2 size,
    float time,
    float energy,
    float sleep,
    float events,
    float seed,
    float quality,
    half4 deepColor,
    half4 midColor,
    half4 glowColor
) {
    float2 uv = position / max(size, float2(1.0));
    float aspect = size.x / max(size.y, 1.0);
    float2 p = (uv - 0.5) * float2(aspect, 1.0);
    p.y = -p.y;

    float clarity = clamp(sleep, 0.0, 1.0);
    float turbulence = 1.0 - clarity;
    float e = clamp(energy, 0.0, 1.0);

    float3 deep = float3(deepColor.rgb);
    float3 mid = float3(midColor.rgb);
    float3 glow = float3(glowColor.rgb);

    float radial = length(p);

    // ── Background ────────────────────────────────────────────────────
    // Sleep does not darken the scene, it decides how clean the darkness is:
    // a rested day gets a deep, wide-range gradient, a poor one gets a haze
    // floor that compresses everything toward the middle.
    float3 bg = deep * mix(0.35, 0.95, 1.0 - uv.y);

    float2 bw = p * 1.35 + float2(seed * 7.0, time * 0.012);
    float bands = gsFbm(float3(bw, seed * 3.0), 3);
    bg += mid * pow(clamp(bands, 0.0, 1.0), 3.0) * mix(0.06, 0.20, clarity);

    // Halo behind the body — the only cheap stand-in for a real bloom pass.
    bg += mid * exp(-radial * radial * 3.4) * (0.03 + 0.15 * e);

    float haze = mix(0.075, 0.010, clarity);
    bg = bg * (1.0 - haze) + deep * 1.9 * haze;

    // Distant field of points. The falloff inside the cell is what makes these
    // points: a bare `step` on the cell hash lights the whole cell and the
    // background fills with squares.
    float2 fieldScaled = p * 90.0 + seed * 19.0;
    float2 fieldF = fract(fieldScaled) - 0.5;
    float fieldHash = gsHash12(floor(fieldScaled));
    float fieldMask = smoothstep(0.18, 0.55, uv.y) * smoothstep(0.72, 0.34, radial);
    bg += mid * step(0.9955, fieldHash) * exp(-dot(fieldF, fieldF) * 24.0) * fieldMask * 1.6;

    // ── Volumetric body ───────────────────────────────────────────────
    float3 ro = float3(0.0, 0.0, -2.6);
    // The 1.9 sets how much of the frame the body claims. Wider than the
    // physically obvious choice on purpose: the composition needs air around
    // the mass, and the date has to sit inside it without fighting the shell.
    float3 rd = normalize(float3(p * 1.9, 1.0));

    // Bounding sphere so the march spends its steps inside the field only.
    const float bound = 2.15;
    float bDot = dot(ro, rd);
    float cDot = dot(ro, ro) - bound * bound;
    float disc = bDot * bDot - cDot;

    float3 acc = float3(0.0);
    float trans = 1.0;

    if (disc > 0.0) {
        float root = sqrt(disc);
        float t0 = max(-bDot - root, 0.0);
        float t1 = -bDot + root;

        int steps = int(clamp(quality, 16.0, 72.0));
        float thickness = mix(0.070, 0.030, clarity);
        float absorption = mix(1.1, 1.7, clarity);

        // Two-speed march. A uniform step fine enough to resolve a 0.1-wide
        // shell would need ~200 steps to cross the bounding sphere; sphere
        // tracing through the empty middle spends them where the density is.
        // The field is fbm-displaced and so not strictly Lipschitz-1 — hence
        // the conservative 0.5 on the skip.
        float fine = thickness * 0.45;
        float t = t0 + fine * gsHash12(position * 0.7 + fract(time) * 53.0);

        for (int i = 0; i < 72; i++) {
            if (i >= steps || trans < 0.02 || t > t1) break;

            float3 pos = ro + rd * t;
            float d = gsBody(pos, time, seed, e, turbulence, events);

            // `abs`, not `d`: the body is hollow, so the deep interior is as
            // empty as the outside. Skipping only forward-facing distance
            // burned the whole step budget crossing the middle and the far
            // wall of the membrane never got rendered.
            if (abs(d) > thickness * 2.4) {
                t += max(abs(d) * 0.5, fine);
                continue;
            }

            float dens = gsShell(d, thickness);
            // Warm flecks live inside the membrane, they are not a tint over
            // the whole body — that is what keeps the gold precious.
            float hot = smoothstep(0.54, 0.74, gsFbm(pos * 3.4 + seed * 9.0, 2));
            float3 emit = mix(mid, glow, hot * hot * 1.15);
            // Lift where the shell faces the light, so the volume has a side.
            emit *= 0.55 + 0.85 * smoothstep(-0.7, 0.7, pos.y * 0.8 + pos.x * 0.6);

            acc += trans * dens * emit * fine * mix(9.0, 15.0, e);
            trans *= exp(-dens * fine * absorption);
            t += fine;
        }
    }

    float cover = 1.0 - trans;
    float3 col = bg * trans + acc;

    // ── Sparks ────────────────────────────────────────────────────────
    // Energy buys both the count and the brightness; they sit mostly inside
    // the body so they read as suspended in it, not sprinkled on top.
    float2 sc = p * mix(52.0, 86.0, e) + seed * 23.0;
    float2 cell = floor(sc);
    float2 f = fract(sc) - 0.5;
    float sh = gsHash12(cell);
    float threshold = mix(0.982, 0.946, e);
    float spark = step(threshold, sh)
        * exp(-dot(f, f) * 42.0)
        * (0.45 + 0.55 * sin(time * 1.7 + sh * 41.0));
    col += glow * spark * (0.7 + 1.5 * e) * (0.22 + 0.95 * cover);

    // ── Grade ─────────────────────────────────────────────────────────
    col = 1.0 - exp(-col * 1.55);                 // roll off highlights, keep darks
    col *= 1.0 - 0.34 * smoothstep(0.45, 1.15, radial);   // vignette

    float grain = gsHash12(position + fract(time) * 137.0) - 0.5;
    col += grain * mix(0.055, 0.018, clarity);

    return half4(half3(clamp(col, 0.0, 1.0)), color.a);
}
