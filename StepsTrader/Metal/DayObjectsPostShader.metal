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

static float dayObjectsGrainNoise(
    float2 uv,
    constant DayObjectsPostUniforms &uniforms
) {
    const uint2 pixel = uint2(floor(saturate(uv) * max(uniforms.resolution, float2(1.0))));
    const uint phase = uint(floor(max(uniforms.grainPhase, 0.0) * 12.0 + 0.5));
    const uint bits = dayObjectsGrainHash(pixel, uniforms.grainSeed, phase);
    return float(bits) / 4294967295.0;
}

static float dayObjectsGlitchHash(uint value) {
    value ^= value >> 16;
    value *= 0x7FEB352Du;
    value ^= value >> 15;
    value *= 0x846CA68Bu;
    value ^= value >> 16;
    return float(value) / 4294967295.0;
}

// Adapted from SwiftUIShaders' bcs_glitch: stable horizontal block
// displacement, RGB channel separation, and scan-line corruption. Day Objects
// replaces the source's intermittent trigger and bright flash with cumulative,
// day-seeded scars driven by absolute spent colors.
static float4 dayObjectsApplyDigitalImpact(
    texture2d<float> sceneTexture,
    sampler linearSampler,
    float2 uv,
    float4 original,
    constant DayObjectsGlitchUniforms &glitch,
    constant DayObjectsGlitchBandUniform *bands
) {
    const float damage = saturate(glitch.levels.x);
    if (damage <= 0.0) {
        return original;
    }

    const float scarStrength = saturate(glitch.levels.y);
    const float signalCorruption = saturate(glitch.levels.z);
    const float ambientMotion = saturate(glitch.levels.w);
    const float2 resolution = max(float2(sceneTexture.get_width(), sceneTexture.get_height()), 1.0);
    const float time = max(glitch.rendering.x, 0.0);
    const float maximumDisplacementPixels = max(glitch.rendering.y, 0.0);
    const float maximumColorShiftPixels = max(glitch.rendering.z, 0.0);
    const float maximumScanLineStrength = saturate(glitch.rendering.w);
    const uint seed = glitch.metadata.x;
    const uint bandCount = min(glitch.metadata.y, dayObjectsGlitchBandCapacity);
    const bool reduceMotion = glitch.metadata.z != 0u;
    const float edgeWidth = max(1.5 / resolution.y, 0.001);

    float horizontalOffsetPixels = 0.0;
    float rgbDirection = 0.0;
    float coveredScar = 0.0;
    for (uint index = 0; index < dayObjectsGlitchBandCapacity; ++index) {
        if (index >= bandCount) {
            break;
        }
        const DayObjectsGlitchBandUniform band = bands[index];
        const float reveal = saturate(
            (damage - saturate(band.geometry.w) + 0.01) * float(dayObjectsGlitchBandCapacity)
        );
        const float halfHeight = max(band.geometry.y, 0.001);
        const float coverage = 1.0 - smoothstep(
            halfHeight,
            halfHeight + edgeWidth,
            abs(uv.y - band.geometry.x)
        );
        const float weight = coverage * reveal;
        if (weight <= 0.0) {
            continue;
        }

        const float frequency = 0.15 + 1.35 * ambientMotion;
        const float phase = band.motion.z + (reduceMotion ? 0.0 : time * frequency * dayObjectsTwoPi);
        const float twitch = reduceMotion ? 0.0 : sin(phase) * ambientMotion * 0.18;
        const float displacement = maximumDisplacementPixels
            * max(band.geometry.z, 0.0)
            * (0.12 + 0.88 * scarStrength)
            * (1.0 + twitch);
        horizontalOffsetPixels += band.motion.x * displacement * weight;
        rgbDirection += band.motion.y * weight;
        coveredScar = max(coveredScar, weight);
    }

    // Quantized macro-block displacement makes the whole signal progressively
    // unstable while the immutable bands remain recognizable daily scars.
    const float blockHeightPixels = mix(38.0, 11.0, signalCorruption);
    const uint blockY = uint(floor(uv.y * resolution.y / blockHeightPixels));
    const float blockNoise = dayObjectsGlitchHash(seed ^ (blockY * 0x9E3779B9u));
    const float blockDirection = blockNoise < 0.5 ? -1.0 : 1.0;
    const float blockMagnitude = smoothstep(0.28, 1.0, blockNoise)
        * maximumDisplacementPixels
        * signalCorruption
        * 0.72;
    horizontalOffsetPixels += blockDirection * blockMagnitude;

    const float2 displacedUV = saturate(
        uv + float2(horizontalOffsetPixels / resolution.x, 0.0)
    );
    const float direction = abs(rgbDirection) > 0.001
        ? sign(rgbDirection)
        : blockDirection;
    const float rgbPixels = maximumColorShiftPixels
        * (0.12 * coveredScar * scarStrength + 0.88 * signalCorruption);
    const float2 rgbOffset = float2(direction * rgbPixels / resolution.x, 0.0);

    const float4 center = sceneTexture.sample(linearSampler, displacedUV);
    const float4 red = sceneTexture.sample(linearSampler, saturate(displacedUV + rgbOffset));
    const float4 blue = sceneTexture.sample(linearSampler, saturate(displacedUV - rgbOffset));
    float3 corrupted = float3(red.r, center.g, blue.b);

    const float pixelY = uv.y * resolution.y;
    const float scanWave = pow(sin(pixelY * 3.14159265) * 0.5 + 0.5, 4.0);
    const float scanStrength = maximumScanLineStrength
        * (0.22 * scarStrength + 0.78 * signalCorruption);
    corrupted *= 1.0 - scanWave * scanStrength;

    // At maximum damage 28% of the untouched image remains, keeping the day's
    // composition readable beneath the digital erosion.
    const float corruptionMix = min(
        0.72,
        0.18 * scarStrength + 0.54 * signalCorruption
    );
    return float4(mix(original.rgb, corrupted, corruptionMix), original.a);
}

fragment float4 dayObjectsDisplayFragment(
    DayObjectsPostVertexOut in [[stage_in]],
    texture2d<float> sceneTexture [[texture(0)]],
    sampler linearSampler [[sampler(0)]],
    constant DayObjectsPostUniforms &uniforms [[buffer(0)]],
    constant DayObjectsGlitchUniforms &glitch [[buffer(1)]],
    constant DayObjectsGlitchBandUniform *glitchBands [[buffer(2)]]
) {
    const float4 original = sceneTexture.sample(linearSampler, saturate(in.uv));
    const float4 sampled = dayObjectsApplyDigitalImpact(
        sceneTexture,
        linearSampler,
        saturate(in.uv),
        original,
        glitch,
        glitchBands
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
