#include "ShapeAtlas/MetalShapeUniforms.metalh"

// Seeded digital trace pass; source sampling and strength curve are unchanged.
fragment float4 nativeAtlasDisplay(MetalShapeVertexOut in [[stage_in]], texture2d<float> scene [[texture(0)]], constant float4 &effect [[buffer(0)]], constant float4 &finish [[buffer(1)]]) {
    constexpr sampler linearSampler(coord::normalized, address::clamp_to_edge, filter::linear);
    const float2 uv = in.uv;
    const float strength = clamp(effect.x, 0.0, 1.0), amount = strength * strength * 0.085;
    const float phase = effect.z * 6.2831853, angle = effect.w * 6.2831853;
    const float2 direction = float2(cos(angle), sin(angle));
    float2 shifted = uv;
    const uint type = uint(effect.y);
    if (type == 0u) {
        const float band = floor(uv.y / (0.018 + effect.z * 0.045));
        const float random = fract(sin(band * 127.1 + phase) * 43758.5453);
        if (random < 0.06 + strength * 0.88) shifted.x += (random * 2.0 - 1.0) * amount * 2.0;
    } else if (type == 2u && strength > 0.0) {
        const float cell = 0.008 + strength * 0.065;
        const float2 grid = floor(uv / cell);
        if (fract(sin(dot(grid, float2(127.1, 311.7)) + phase) * 43758.5453) < 0.06 + strength * 0.88) shifted = (grid + 0.5) * cell;
    } else if (type == 3u) {
        const float coordinate = dot(uv, direction);
        shifted += float2(-direction.y, direction.x) * sin(coordinate * (12.0 + effect.z * 28.0) + phase) * amount * (0.25 + 0.75 * pow(0.5 + 0.5 * sin(coordinate * 5.0 + phase), 2.0));
    }
    float3 color = scene.sample(linearSampler, shifted).rgb;
    if (type == 1u) {
        const float2 offset = direction * amount * (0.25 + 0.75 * (0.5 + 0.5 * sin(uv.y * 8.0 + uv.x * 3.0 + phase)));
        color.r = scene.sample(linearSampler, uv + offset).r;
        color.b = scene.sample(linearSampler, uv - offset).b;
    } else if (type == 4u && strength > 0.0) {
        const float2 texel = 1.0 / float2(scene.get_width(), scene.get_height());
        for (uint index = 1u; index <= 3u; index++) {
            const float2 point = uv - direction * amount * float(index);
            const float3 echo = scene.sample(linearSampler, point).rgb;
            const float edge = length(scene.sample(linearSampler, point + texel * 2.0).rgb - scene.sample(linearSampler, point - texel * 2.0).rgb);
            color = mix(color, echo, min(0.8, edge * strength * 2.0) / float(index));
        }
    }
    // Health-driven softness and color clarity remain independent of digital damage.
    if (finish.x > 0.0001) {
        float3 soft = color * 0.4;
        for (uint i = 0; i < 6; i++) {
            const float a = float(i) * 1.04719755;
            soft += scene.sample(linearSampler, shifted + float2(cos(a), sin(a)) * finish.x).rgb * 0.1;
        }
        color = soft;
    }
    return float4(clamp(color, 0.0, 1.0), 1.0);
}
