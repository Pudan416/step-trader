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

static_assert(alignof(DayObjectsPostUniforms) == 8, "Post uniforms require 8-byte alignment");
static_assert(sizeof(DayObjectsPostUniforms) == 32, "Post uniforms must match Swift's 32-byte stride");

struct DayObjectsPostVertexOut {
    float4 position [[position]];
    float2 uv;
};

constant int dayObjectsMaximumBlurRadiusPixels = 32;

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

fragment float4 dayObjectsDisplayFragment(
    DayObjectsPostVertexOut in [[stage_in]],
    texture2d<float> sceneTexture [[texture(0)]],
    sampler linearSampler [[sampler(0)]],
    constant DayObjectsPostUniforms &uniforms [[buffer(0)]]
) {
    const float4 sampled = sceneTexture.sample(linearSampler, saturate(in.uv));
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
