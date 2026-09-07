#include <metal_stdlib>
using namespace metal;

struct DayObjectsPostUniforms {
    float2 resolution;
    float blurRadiusPixels;
    float contrast;
    float saturation;
    float grainIntensity;
    float grainPhase;
    uint grainSeed;
};

struct DayObjectsGlitchUniforms {
    float4 levels;
    float4 rendering;
    uint4 metadata;
};

struct DayObjectsGlitchBandUniform {
    float4 geometry;
    float4 motion;
};

static_assert(alignof(DayObjectsPostUniforms) == 8, "Post uniforms require 8-byte alignment");
static_assert(sizeof(DayObjectsPostUniforms) == 32, "Post uniforms must match Swift's 32-byte stride");
static_assert(alignof(DayObjectsGlitchUniforms) == 16, "Glitch uniforms require 16-byte alignment");
static_assert(sizeof(DayObjectsGlitchUniforms) == 48, "Glitch uniforms must match Swift's 48-byte stride");
static_assert(alignof(DayObjectsGlitchBandUniform) == 16, "Glitch bands require 16-byte alignment");
static_assert(sizeof(DayObjectsGlitchBandUniform) == 32, "Glitch bands must match Swift's 32-byte stride");

struct DayObjectsPostVertexOut {
    float4 position [[position]];
    float2 uv;
};

constant int dayObjectsMaximumBlurRadiusPixels = 32;
constant uint dayObjectsGlitchBandCapacity = 12;
constant float dayObjectsTwoPi = 6.28318530718;

static float4 dayObjectsGaussianBlur(
    texture2d<float> sourceTexture,
    sampler linearSampler,
    float2 uv,
    constant DayObjectsPostUniforms &uniforms,
    float2 direction
) {
    const float radius = clamp(
        uniforms.blurRadiusPixels,
        0.0,
        float(dayObjectsMaximumBlurRadiusPixels)
    );
    if (radius < 0.01) {
        return sourceTexture.sample(linearSampler, saturate(uv));
    }

    const float sigma = max(radius * 0.46, 0.65);
    const float inverseTwoSigmaSquared = 0.5 / (sigma * sigma);
    const float2 texel = direction / max(uniforms.resolution, float2(1.0));
    float4 accumulated = sourceTexture.sample(linearSampler, saturate(uv));
    float accumulatedWeight = 1.0;

    // Pair adjacent Gaussian taps and let the linear sampler interpolate
    // between them. The fixed 32-pixel cap bounds each full-resolution pass
    // at one center sample plus sixteen symmetric sample pairs.
    for (int firstTap = 1; firstTap <= dayObjectsMaximumBlurRadiusPixels; firstTap += 2) {
        const float firstOffset = float(firstTap);
        const float secondOffset = firstOffset + 1.0;
        const float firstSupport = clamp(radius - firstOffset + 1.0, 0.0, 1.0);
        const float secondSupport = clamp(radius - secondOffset + 1.0, 0.0, 1.0);
        const float firstWeight = exp(-firstOffset * firstOffset * inverseTwoSigmaSquared)
            * firstSupport;
        const float secondWeight = exp(-secondOffset * secondOffset * inverseTwoSigmaSquared)
            * secondSupport;
        const float pairedWeight = firstWeight + secondWeight;
        if (pairedWeight <= 1e-6) {
            continue;
        }

        const float pairedOffset = (
            firstOffset * firstWeight + secondOffset * secondWeight
        ) / pairedWeight;
        const float2 delta = texel * pairedOffset;
        accumulated += sourceTexture.sample(linearSampler, saturate(uv + delta)) * pairedWeight;
        accumulated += sourceTexture.sample(linearSampler, saturate(uv - delta)) * pairedWeight;
        accumulatedWeight += pairedWeight * 2.0;
    }

    return accumulated / max(accumulatedWeight, 1e-6);
}

fragment float4 dayObjectsBlurHorizontal(
    DayObjectsPostVertexOut in [[stage_in]],
    texture2d<float> sourceTexture [[texture(0)]],
    sampler linearSampler [[sampler(0)]],
    constant DayObjectsPostUniforms &uniforms [[buffer(0)]]
) {
    return dayObjectsGaussianBlur(
        sourceTexture,
        linearSampler,
        in.uv,
        uniforms,
        float2(1.0, 0.0)
    );
}

fragment float4 dayObjectsBlurVertical(
    DayObjectsPostVertexOut in [[stage_in]],
    texture2d<float> sourceTexture [[texture(0)]],
    sampler linearSampler [[sampler(0)]],
    constant DayObjectsPostUniforms &uniforms [[buffer(0)]]
) {
    return dayObjectsGaussianBlur(
        sourceTexture,
        linearSampler,
        in.uv,
        uniforms,
        float2(0.0, 1.0)
    );
}

static uint dayObjectsGrainHash(uint2 pixel, uint seed, uint phase) {
    uint value = pixel.x * 0x9E3779B9u;
    value ^= pixel.y * 0x85EBCA6Bu;
    value ^= seed + phase * 0xC2B2AE35u;
    value ^= value >> 16;
    value *= 0x7FEB352Du;
    value ^= value >> 15;
    value *= 0x846CA68Bu;
    value ^= value >> 16;
    return value;
}

static float dayObjectsGrainHash01(uint2 cell, uint seed) {
    return float(dayObjectsGrainHash(cell, seed, 0u)) / 4294967295.0;
}

static float dayObjectsSmoothGrainField(
    float2 pixel,
    float cellSize,
    uint seed
) {
    const float2 gridPoint = max(pixel, 0.0) / cellSize;
    const uint2 cell = uint2(floor(gridPoint));
    float2 fraction = fract(gridPoint);
    fraction = fraction * fraction * (3.0 - 2.0 * fraction);
    const float top = mix(
        dayObjectsGrainHash01(cell, seed),
        dayObjectsGrainHash01(cell + uint2(1, 0), seed),
        fraction.x
    );
    const float bottom = mix(
        dayObjectsGrainHash01(cell + uint2(0, 1), seed),
        dayObjectsGrainHash01(cell + uint2(1, 1), seed),
        fraction.x
    );
    return mix(top, bottom, fraction.y);
}

static float dayObjectsGrainNoise(
    float2 uv,
    constant DayObjectsPostUniforms &uniforms
) {
    float2 pixel = saturate(uv) * max(uniforms.resolution, float2(1.0));
    const float drift = max(uniforms.grainPhase, 0.0);
    pixel += float2(drift * 17.0, drift * 11.0);
    const float medium = dayObjectsSmoothGrainField(
        pixel,
        7.0,
        uniforms.grainSeed
    );
    const float large = dayObjectsSmoothGrainField(
        pixel + float2(19.0, 31.0),
        14.0,
        uniforms.grainSeed ^ 0xA511E9B3u
    );
    return medium * 0.72 + large * 0.28;
}

static float dayObjectsGlitchUnit(uint value) {
    value ^= value >> 16;
    value *= 0x7FEB352Du;
    value ^= value >> 15;
    value *= 0x846CA68Bu;
    value ^= value >> 16;
    return float(value >> 8) / 16777216.0;
}

// Soft double exposure and chromatic edges, plus a few day-seeded local tears.
// Uniform background stays clean outside the sparse strips; no scan-line grid.
static float4 dayObjectsApplyDigitalImpact(
    texture2d<float> sceneTexture,
    texture2d<float> actorEchoTexture,
    sampler linearSampler,
    float2 uv,
    float4 original,
    constant DayObjectsGlitchUniforms &glitch,
    constant DayObjectsGlitchBandUniform *bands,
    constant float2 &echoDirection
) {
    const float damage = saturate(glitch.levels.x);
    if (damage <= 0.0) { return original; }
    const float2 resolution = max(float2(sceneTexture.get_width(), sceneTexture.get_height()), 1.0);
    const float scale = min(resolution.x, resolution.y) / 390.0;
    const uint seed = glitch.metadata.x;
    const float time = max(glitch.rendering.x, 0.0);
    const float phase = dayObjectsGlitchUnit(seed) * dayObjectsTwoPi;
    // Keep low-spend details perceptible; their small masks and capped opacity protect the artwork.
    const float strength = pow(damage, 0.65);
    // Sparse, day-seeded events: ~11 seconds apart at low spend. Higher spend
    // gradually reveals the intervening events, without moving existing ones.
    const uint slot = uint(min(floor(time / 3.6), 4294967040.0));
    const uint eventSeed = seed ^ (slot * 0x9E3779B9u);
    const float age = fmod(time, 3.6) - (1.2 + 0.8 * dayObjectsGlitchUnit(eventSeed));
    const float eventGain = slot % 3u == 0u ? 1.0 : smoothstep(0.25, 0.85, damage);
    const float envelope = smoothstep(0.0, 0.055, age)
        * (1.0 - smoothstep(0.28, 0.46, age)) * eventGain;
    // A quick outward step, a smaller reverse step, then a soft return.
    const float kick = envelope * (1.0 - 1.35 * smoothstep(0.10, 0.15, age)
        + 0.35 * smoothstep(0.22, 0.30, age));
    const float2 direction = float2(cos(phase), sin(phase));
    const float restingOffset = 14.0 + 8.0 * dayObjectsGlitchUnit(seed ^ 0x68E31DA4u);
    const float2 echoOffset = direction * restingOffset * scale / resolution;
    const float3 ghost = sceneTexture.sample(linearSampler, saturate(uv - echoOffset)).rgb;
    float3 color = mix(original.rgb, ghost, 0.22);

    // A much tighter colour registration supplies a tinted edge to the full
    // secondary exposure. Constant fills remain unchanged by both samples.
    const float2 fringe = direction * 3.0 * scale / resolution;
    const float3 chromatic = float3(
        sceneTexture.sample(linearSampler, saturate(uv - fringe)).r,
        original.g,
        sceneTexture.sample(linearSampler, saturate(uv + fringe)).b
    );
    color = mix(color, chromatic, 0.12);

    float weight = 0.0;
    float stripOffset = 0.0;
    float stripTone = 0.0;
    float stripPulse = 0.0;
    const float2 edge = max(float2(0.8) / resolution, float2(0.0005));
    const uint availableBands = min(glitch.metadata.y, dayObjectsGlitchBandCapacity);
    const uint stripCount = min(availableBands, 6u);
    for (uint index = 0; index < stripCount; ++index) {
        // Bands are vertically sorted; sample the full height, not only its top half.
        const uint bandIndex = index * availableBands / stripCount;
        const DayObjectsGlitchBandUniform band = bands[bandIndex];
        const uint stripSeed = seed ^ ((index + 1u) * 0x9E3779B9u);
        const float position = dayObjectsGlitchUnit(stripSeed);
        const float variation = dayObjectsGlitchUnit(stripSeed ^ 0xB5297A4Du);
        // Only one local strip moves during each event.
        const bool selected = index == uint(dayObjectsGlitchUnit(eventSeed ^ 0x68E31DA4u) * float(stripCount));
        const float drift = selected ? kick * 3.0 : 0.0;
        const float2 center = float2(0.16 + 0.68 * position + drift * 0.018, band.geometry.x);
        const float2 halfSize = float2(0.065 + 0.09 * variation, (1.5 + 2.5 * variation) * scale / resolution.y);
        const float2 coverage = 1.0 - smoothstep(halfSize, halfSize + edge, abs(uv - center));
        const float candidate = coverage.x * coverage.y;
        if (candidate <= weight) { continue; }
        weight = candidate;
        stripOffset = (position < 0.5 ? -1.0 : 1.0) * (6.0 + 8.0 * variation + drift) * scale;
        stripTone = variation < 0.5 ? 0.015 : 0.96;
        stripPulse = selected ? envelope : 0.0;
    }
    if (weight > 0.0) {
        const float3 shifted = sceneTexture.sample(linearSampler,
            saturate(uv + float2(stripOffset / resolution.x, 0.0))).rgb;
        // A faint intrinsic tint keeps a short tear legible over a flat area.
        const float3 stripColor = mix(shifted, float3(stripTone), 0.10);
        color = mix(color, stripColor, weight * (0.40 + 0.12 * stripPulse));
    }
    // Capped opacity preserves the source artwork, including during a twitch.
    float3 result = mix(original.rgb, color, strength);
    { // The digital layer exists in still frames too; pulses only animate it.
        // This texture contains only the selected actor, BEFORE scene blur.
        // Its displaced silhouette supplies a distinct coloured crescent;
        // the original silhouette masks the copy away from the figure's body.
        const float2 shift = echoDirection * (restingOffset + (12.0 + 6.0 * damage) * kick) * scale / resolution;
        const float2 sampleUV = uv - shift;
        const bool inside = all(sampleUV >= 0.0) && all(sampleUV <= 1.0);
        const float4 echo = inside ? actorEchoTexture.sample(linearSampler, sampleUV) : float4(0.0);
        const float body = actorEchoTexture.sample(linearSampler, uv).a;
        // Compare matching contours: a broader body mask would swallow the
        // translated copy inside the actor's existing soft halo.
        const float crescent = max(smoothstep(0.20, 0.55, echo.a)
            - smoothstep(0.20, 0.55, body), 0.0);
        const float3 pigment = echo.rgb / max(echo.a, 0.0001);
        const float3 tint = mix(pigment, float3(0.48, 0.22, 0.64), 0.55);
        // Spend controls a persistent pigment layer, independently of sleep/focus.
        // Never multiply the whole echo by the transient animation envelope.
        const float restingOpacity = 0.28 * pow(damage, 0.25);
        const float peakOpacity = max(restingOpacity, min(0.50, pow(damage, 0.35) * 0.64));
        const float opacity = mix(restingOpacity, peakOpacity, envelope);
        result = mix(result, tint, crescent * opacity);
    }
    return float4(result, original.a);
}

fragment float4 dayObjectsDisplayFragment(
    DayObjectsPostVertexOut in [[stage_in]],
    texture2d<float> sceneTexture [[texture(0)]],
    texture2d<float> actorEchoTexture [[texture(1)]],
    sampler linearSampler [[sampler(0)]],
    constant DayObjectsPostUniforms &uniforms [[buffer(0)]],
    constant DayObjectsGlitchUniforms &glitch [[buffer(1)]],
    constant DayObjectsGlitchBandUniform *glitchBands [[buffer(2)]],
    constant float2 &echoDirection [[buffer(3)]]
) {
    const float4 original = sceneTexture.sample(linearSampler, saturate(in.uv));
    const float4 sampled = dayObjectsApplyDigitalImpact(
        sceneTexture,
        actorEchoTexture,
        linearSampler,
        saturate(in.uv),
        original,
        glitch,
        glitchBands,
        echoDirection
    );
    float3 color = max(sampled.rgb, 0.0);

    const float sourceLuminance = dot(color, float3(0.2126, 0.7152, 0.0722));
    color = mix(float3(sourceLuminance), color, max(uniforms.saturation, 0.0));
    color = (color - 0.5) * max(uniforms.contrast, 0.0) + 0.5;
    color = saturate(color);

    // Grain is evaluated from the final drawable pixel and applied only after
    // the scene texture has been blurred and display-adjusted. Modulating one
    // luminance value keeps the noise monochrome and avoids unrelated hue.
    const float grain = dayObjectsGrainNoise(in.uv, uniforms) * 2.0 - 1.0;
    const float luminance = dot(color, float3(0.2126, 0.7152, 0.0722));
    const float strength = clamp(uniforms.grainIntensity, 0.0, 0.075) * abs(grain);
    const float grainLuminance = grain < 0.0
        ? luminance - luminance * (1.0 - luminance) * strength
        : luminance + (sqrt(max(luminance, 0.0)) - luminance) * strength;
    color = saturate(color + (grainLuminance - luminance));

    return float4(color, sampled.a);
}
