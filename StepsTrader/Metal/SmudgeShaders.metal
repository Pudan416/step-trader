#include <metal_stdlib>
using namespace metal;

// ════════════════════════════════════════════════════════════════════
// MARK: - Shared Parameter Structs
// ════════════════════════════════════════════════════════════════════

struct SmudgeParams {
    float2 p0;           // previous touch point (pixels)
    float2 p1;           // current touch point  (pixels)
    float  radius;       // brush radius (pixels)
    float  strength;     // blend strength [0…1]
    float  dragFactor;   // sample offset multiplier
    float  _pad;         // alignment padding
    float2 direction;    // normalize(p1 - p0)
};

struct RelaxParams {
    float alphaDiff;     // diffusion blend factor
    float baseReturn;    // base relaxation rate (dt / targetSeconds)
    float dt;            // frame delta (seconds) — for age increment
    float ageAccel;      // how much age accelerates relaxation
};

struct RippleInfo {
    float2 center;       // tap position (pixels)
    float  elapsed;      // seconds since tap
    float  amplitude;    // max displacement (pixels)
    float  ringSpeed;    // ring expansion speed (pixels/sec)
    float  mainWidth;    // gaussian sigma for main ring (pixels)
    float  decay;        // spatial decay rate
    float  duration;     // total lifetime (seconds)
};

struct DisplayParams {
    uint  rippleCount;   // number of active ripples (0..5)
    float globalFade;    // smooth ramp 1→0 near timeout
};

// ════════════════════════════════════════════════════════════════════
// MARK: - Full-screen Display Pipeline
// ════════════════════════════════════════════════════════════════════

struct VertexOut {
    float4 position [[position]];
    float2 texCoord;
};

vertex VertexOut smudgeDisplayVertex(uint vid [[vertex_id]]) {
    const float2 positions[] = {
        float2(-1, -1), float2(1, -1), float2(-1, 1), float2(1, 1)
    };
    const float2 texCoords[] = {
        float2(0, 1), float2(1, 1), float2(0, 0), float2(1, 0)
    };

    VertexOut out;
    out.position = float4(positions[vid], 0, 1);
    out.texCoord = texCoords[vid];
    return out;
}

fragment float4 smudgeDisplayFragment(
    VertexOut in [[stage_in]],
    texture2d<float> interactiveTex [[texture(0)]],
    texture2d<float> baseTex        [[texture(1)]],
    texture2d<float> ageTex         [[texture(2)]],
    constant RippleInfo *ripples    [[buffer(0)]],
    constant DisplayParams &params  [[buffer(1)]]
) {
    constexpr sampler s(filter::linear, address::clamp_to_edge);
    constexpr sampler sn(filter::nearest, address::clamp_to_edge);

    float2 texSize  = float2(baseTex.get_width(), baseTex.get_height());
    float2 pixelPos = in.texCoord * texSize;

    float4 interactive = interactiveTex.sample(s, in.texCoord);
    float4 base        = baseTex.sample(s, in.texCoord);

    // ── 1. Smudge: AGE-BASED visibility (works on any theme) ────
    float age     = ageTex.sample(sn, in.texCoord).r;
    float ageFade = saturate(1.0 - age / 3.0);  // 1→0 over 3 seconds, never-smudged (99) = 0

    // Amplify the natural color displacement direction
    float3 colorShift = interactive.rgb - base.rgb;
    float3 smudgeColor = saturate(interactive.rgb + colorShift * 5.0 + float3(ageFade * 0.07));
    float  smudgeAlpha = ageFade * 0.55;

    // ── 2. Ripple: WAVE-SHAPE visibility (independent of colors) ─
    float2 rippleUV   = in.texCoord;
    float  rippleWave = 0.0;

    for (uint i = 0; i < params.rippleCount && i < 20; i++) {
        constant RippleInfo &r = ripples[i];
        if (r.amplitude <= 0.0 || r.elapsed >= r.duration) continue;

        float dist       = distance(pixelPos, r.center);
        float waveRadius = r.elapsed * r.ringSpeed;

        float timeFade = pow(max(0.0, 1.0 - r.elapsed / r.duration), 1.5);
        float spatial  = exp(-dist * r.decay);

        // Main ring
        float ms       = r.mainWidth;
        float mainDist = dist - waveRadius;
        float mainRing = exp(-mainDist * mainDist / (2.0 * ms * ms));

        // Echo 1
        float e1gap  = ms * 2.5;
        float e1s    = ms * 0.5;
        float e1dist = dist - (waveRadius - e1gap);
        float echo1  = 0.4 * exp(-e1dist * e1dist / (2.0 * e1s * e1s));

        // Echo 2
        float e2gap  = ms * 4.5;
        float e2s    = ms * 0.3;
        float e2dist = dist - (waveRadius - e2gap);
        float echo2  = 0.15 * exp(-e2dist * e2dist / (2.0 * e2s * e2s));

        float wave = (mainRing + echo1 + echo2) * timeFade * spatial;
        float disp = wave * r.amplitude;

        float2 dir = dist > 0.5 ? (pixelPos - r.center) / dist : float2(0);
        rippleUV += dir * disp / texSize;
        rippleWave = max(rippleWave, wave);
    }

    float rippleAlpha = 0.0;
    float3 rippleColor = float3(0);
    if (rippleWave > 0.001) {
        float4 rippledBase = baseTex.sample(s, rippleUV);
        float3 rShift = rippledBase.rgb - base.rgb;
        rippleColor = saturate(rippledBase.rgb + rShift * 5.0 + float3(rippleWave * 0.09));
        rippleAlpha = rippleWave * 0.6;
    }

    // ── 3. Combine: stronger effect wins, then apply global fade ─
    float  alpha;
    float3 color;
    if (smudgeAlpha >= rippleAlpha) {
        alpha = smudgeAlpha;
        color = smudgeColor;
    } else {
        alpha = rippleAlpha;
        color = rippleColor;
    }

    float fa = alpha * params.globalFade;
    return float4(color * fa, fa);
}

// ════════════════════════════════════════════════════════════════════
// MARK: - Smudge Compute Kernel
// ════════════════════════════════════════════════════════════════════

kernel void smudgeKernel(
    texture2d<float, access::read>  input   [[texture(0)]],
    texture2d<float, access::write> output  [[texture(1)]],
    texture2d<float, access::read>  ageIn   [[texture(2)]],
    texture2d<float, access::write> ageOut  [[texture(3)]],
    constant SmudgeParams &params           [[buffer(0)]],
    uint2 gid                               [[thread_position_in_grid]]
) {
    uint w = input.get_width();
    uint h = input.get_height();
    if (gid.x >= w || gid.y >= h) return;

    float2 uv = float2(gid);

    float2 seg       = params.p1 - params.p0;
    float  segLenSq  = dot(seg, seg);
    float  t         = segLenSq > 0.001
                        ? clamp(dot(uv - params.p0, seg) / segLenSq, 0.0, 1.0)
                        : 0.0;
    float2 closest   = params.p0 + t * seg;
    float  dist      = length(uv - closest);

    float4 current = input.read(gid);

    if (dist > params.radius) {
        output.write(current, gid);
        ageOut.write(ageIn.read(gid), gid);
        return;
    }

    float falloff = pow(1.0 - dist / params.radius, 2.0);

    float2 samplePos = uv - params.dragFactor * params.direction;
    samplePos = clamp(samplePos, float2(0), float2(float(w) - 1.0, float(h) - 1.0));

    float4 sampled = input.read(uint2(samplePos));
    float4 result  = mix(current, sampled, params.strength * falloff);
    output.write(result, gid);

    // Age proportional to falloff: center → 0, edge → existing age
    float existingAge = ageIn.read(gid).r;
    float smudgedAge  = existingAge * (1.0 - falloff);
    ageOut.write(float4(smudgedAge, 0, 0, 0), gid);
}

// ════════════════════════════════════════════════════════════════════
// MARK: - Combined Diffusion + Relaxation Kernel
// ════════════════════════════════════════════════════════════════════

kernel void relaxDiffuseKernel(
    texture2d<float, access::read>  interactive [[texture(0)]],
    texture2d<float, access::read>  base        [[texture(1)]],
    texture2d<float, access::write> output      [[texture(2)]],
    texture2d<float, access::read>  ageIn       [[texture(3)]],
    texture2d<float, access::write> ageOut      [[texture(4)]],
    constant RelaxParams &params                [[buffer(0)]],
    uint2 gid                                   [[thread_position_in_grid]]
) {
    int w = int(interactive.get_width());
    int h = int(interactive.get_height());
    if (int(gid.x) >= w || int(gid.y) >= h) return;

    float4 center = interactive.read(gid);

    float4 north = interactive.read(uint2(gid.x,                 uint(max(int(gid.y) - 1, 0))));
    float4 south = interactive.read(uint2(gid.x,                 uint(min(int(gid.y) + 1, h - 1))));
    float4 east  = interactive.read(uint2(uint(min(int(gid.x) + 1, w - 1)), gid.y));
    float4 west  = interactive.read(uint2(uint(max(int(gid.x) - 1, 0)),     gid.y));
    float4 blur  = (north + south + east + west) * 0.25;

    float4 diffused = mix(center, blur, params.alphaDiff);

    float age    = ageIn.read(gid).r;
    float newAge = age + params.dt;
    ageOut.write(float4(newAge, 0, 0, 0), gid);

    float relax  = saturate(params.baseReturn * (1.0 + newAge * params.ageAccel));
    float4 baseColor = base.read(gid);
    float4 result    = mix(diffused, baseColor, relax);

    output.write(result, gid);
}

// ════════════════════════════════════════════════════════════════════
// MARK: - Texture Copy Kernel
// ════════════════════════════════════════════════════════════════════

kernel void copyTextureKernel(
    texture2d<float, access::read>  source [[texture(0)]],
    texture2d<float, access::write> dest   [[texture(1)]],
    uint2 gid                              [[thread_position_in_grid]]
) {
    if (gid.x >= source.get_width() || gid.y >= source.get_height()) return;
    dest.write(source.read(gid), gid);
}
