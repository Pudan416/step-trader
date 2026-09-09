#include "Post/DayObjectsPostUniforms.metalh"
#include "Post/DayObjectsGrain.metalh"
#include "Post/DayObjectsDigitalImpact.metalh"

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

static float3 dayObjectsDisplayColor(float3 source, float2 uv, constant DayObjectsPostUniforms &uniforms, bool photographic = false) {
    float3 color = max(source, 0.0);

    const float sourceLuminance = dot(color, float3(0.2126, 0.7152, 0.0722));
    color = mix(float3(sourceLuminance), color, max(uniforms.saturation, 0.0));
    color = (color - 0.5) * max(uniforms.contrast, 0.0) + 0.5;
    color = saturate(color);

    // Grain is evaluated from the final drawable pixel and applied only after
    // the scene texture has been blurred and display-adjusted. Modulating one
    // luminance value keeps the noise monochrome and avoids unrelated hue.
    if (photographic) {
        // Static, monochrome silver-like grains at final drawable resolution.
        // No time/phase input: the texture never boils over still artwork.
        const float2 pixel = saturate(uv) * max(uniforms.resolution, float2(1.0));
        const float fine = dayObjectsGrainHash01(uint2(floor(pixel / 1.5)), uniforms.grainSeed);
        const float clusters = dayObjectsSmoothGrainField(pixel, 3.5, uniforms.grainSeed ^ 0xA511E9B3u);
        const float noise = (fine * 0.8 + clusters * 0.2) * 2.0 - 1.0;
        return saturate(color + noise * clamp(uniforms.grainIntensity, 0.0, 0.075) * 1.25);
    }
    const float grain = dayObjectsGrainNoise(uv, uniforms) * 2.0 - 1.0;
    const float luminance = dot(color, float3(0.2126, 0.7152, 0.0722));
    const float strength = clamp(uniforms.grainIntensity, 0.0, 0.075) * abs(grain);
    const float grainLuminance = grain < 0.0
        ? luminance - luminance * (1.0 - luminance) * strength
        : luminance + (sqrt(max(luminance, 0.0)) - luminance) * strength;
    color = saturate(color + (grainLuminance - luminance));

    return color;
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
        sceneTexture, actorEchoTexture, linearSampler, saturate(in.uv),
        original, glitch, glitchBands, echoDirection
    );
    return float4(dayObjectsDisplayColor(sampled.rgb, in.uv, uniforms), sampled.a);
}

// Native geometry has its own seeded trace pass, but shares the established
// final color adjustment, with a sharper static grain for the new artwork.
fragment float4 nativeAtlasFinishFragment(
    DayObjectsPostVertexOut in [[stage_in]],
    texture2d<float> sceneTexture [[texture(0)]],
    constant DayObjectsPostUniforms &uniforms [[buffer(0)]]
) {
    constexpr sampler linearSampler(coord::normalized, address::clamp_to_edge, filter::linear);
    return float4(dayObjectsDisplayColor(sceneTexture.sample(linearSampler, in.uv).rgb, in.uv, uniforms, true), 1.0);
}
