#include "ShapeAtlas/Materials/MetalShapeMaterials.metalh"

struct NativeAtlasPlacement { float4 pose; float4 canvas; float4 effects; float4 presentation; };
static_assert(sizeof(NativeAtlasPlacement) == 64, "Native placement must match four Swift float4 values");

fragment float4 nativeAtlasComposite(MetalShapeVertexOut in [[stage_in]],
    constant MetalShapeGenomeUniforms &g [[buffer(0)]],
    constant MetalShapeMaterialUniforms &m [[buffer(1)]],
    constant NativeAtlasPlacement &placement [[buffer(2)]],
    texture2d<float> previous [[texture(0)]]) {
    constexpr sampler linearSampler(coord::normalized, address::clamp_to_edge, filter::linear);
    const float2 resolution = placement.canvas.xy;
    float2 local = (in.uv - placement.pose.xy) * resolution / min(resolution.x, resolution.y) / max(placement.pose.z, 0.001);
    const float c = cos(placement.pose.w), s = sin(placement.pose.w);
    local = float2(local.x * c + local.y * s, -local.x * s + local.y * c);
    MetalShapeVertexOut shapeIn = in; shapeIn.uv = local + 0.5;
    float4 shape = metalShapeGenomeShade(shapeIn, g, m);
    const float morph = saturate(placement.presentation.x);
    if (morph < 1.0) {
        // The first stage is always a solid circle. On the first tap the
        // existing picker timeline reveals its actual silhouette and fill.
        const float2 point = local * 2.72;
        const float distance = mix(length(point) - 1.0, metalShapeDistance(point, g), morph);
        const float aa = max(fwidth(distance), 0.0025);
        const float filled = smoothstep(aa, -aa, distance);
        const float reveal = smoothstep(0.45, 1.0, morph);
        const float alpha = mix(filled, shape.a, reveal);
        const float3 targetColor = shape.a > 0.00001 ? shape.rgb / shape.a : m.color0.rgb;
        shape = float4(mix(float3(0.14), targetColor, reveal) * alpha, alpha);
    }
    float4 foreground = shape * placement.canvas.z;
    const float4 background = previous.sample(linearSampler, in.uv);
    const float a = clamp(foreground.a, 0.0, 1.0);
    const float coverageDerivative = fwidth(a);
    float3 color = foreground.rgb / max(a, 0.00001);
    color = mix(float3(dot(color, float3(0.2126, 0.7152, 0.0722))), color, placement.effects.z);
    color *= 1.0 - placement.effects.w * 0.15;
    const bool eligible = placement.canvas.w > 0.5;
    const float strength = clamp(placement.effects.y, 0.0, 1.0);
    if (eligible && background.a > 0.5 && a > 0.001) {
        const uint mode = uint(placement.effects.x);
        if (mode == 0u) color = mix(color, background.rgb, strength * 0.65);
        if (mode == 2u) {
            const float3 overlay = select(2.0 * background.rgb * color, 1.0 - 2.0 * (1.0 - background.rgb) * (1.0 - color), background.rgb > 0.5);
            color = mix(color, overlay, strength);
        }
        if (mode == 1u && a > 0.5) {
            const float2 delta = 2.0 / resolution;
            const float neighbor = min(min(previous.sample(linearSampler, in.uv + float2(delta.x, 0)).a, previous.sample(linearSampler, in.uv - float2(delta.x, 0)).a), min(previous.sample(linearSampler, in.uv + float2(0, delta.y)).a, previous.sample(linearSampler, in.uv - float2(0, delta.y)).a));
            const float edge = max(smoothstep(0.015, 0.15, coverageDerivative), 1.0 - smoothstep(0.1, 0.6, neighbor));
            color = mix(color, float3(1.0), edge * strength * 0.9);
        }
    }
    float3 combined = color * a + background.rgb * (1.0 - a);
    if (placement.presentation.y > 0.5) {
        // Added picker items stay neutral even over saturated artwork. Keep
        // the outside background untouched and preserve the opacity transition.
        float neutral = (1.0 - placement.effects.z) * smoothstep(0.05, 0.9, a);
        combined = mix(combined, float3(dot(combined, float3(0.2126, 0.7152, 0.0722))), neutral);
    }
    return float4(combined, eligible ? a + background.a * (1.0 - a) : background.a * (1.0 - a));
}
