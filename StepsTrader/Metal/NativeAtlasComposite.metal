#include "ShapeAtlas/Materials/MetalShapeMaterials.metalh"

struct NativeAtlasPlacement { float4 pose; float4 canvas; float4 effects; float4 presentation; };
static_assert(sizeof(NativeAtlasPlacement) == 64, "Native placement must match four Swift float4 values");

static float4 nativeAtlasPickerCircle(float2 point, float coverage) {
    const float radius = length(point);
    const float shoulder = smoothstep(0.65, 1.0, radius);
    const float rim = smoothstep(0.965, 0.985, radius);
    const float alpha = coverage * (0.52 + shoulder * 0.06 + rim * 0.08);
    // A light surface supports black ink even over a near-black gradient.
    const float3 color = float3(0.96);
    return float4(color * alpha, alpha);
}

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
    const float morph = saturate(placement.presentation.x);
    const float4 background = previous.sample(linearSampler, in.uv);
    if (morph == 0.0) {
        // Available targets do not inherit the future figure's material or
        // intersection mask. The figure is evaluated only after selection.
        const float2 point = local * 2.72;
        const float distance = length(point) - 1.0;
        const float aa = max(fwidth(distance), 0.0025);
        const float4 lens = nativeAtlasPickerCircle(point, smoothstep(aa, -aa, distance)) * placement.canvas.z;
        return float4(lens.rgb + background.rgb * (1.0 - lens.a), background.a);
    }
    MetalShapeVertexOut shapeIn = in; shapeIn.uv = local + 0.5;
    float4 shape = metalShapeGenomeShade(shapeIn, g, m);
    if (morph < 1.0) {
        // A quiet translucent circle until the first tap. Keep the Canvas
        // visible through its centre; a soft edge gives the touch target shape.
        const float2 point = local * 2.72;
        const float distance = mix(length(point) - 1.0, metalShapeDistance(point, g), morph);
        const float aa = max(fwidth(distance), 0.0025);
        const float filled = smoothstep(aa, -aa, distance);
        const float reveal = smoothstep(0.45, 1.0, morph);
        shape = mix(nativeAtlasPickerCircle(point, filled), shape, reveal);
    }
    float4 foreground = shape * placement.canvas.z;
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
        // Confirmation previews stay neutral even over saturated artwork. Keep
        // the outside background untouched and preserve the opacity transition.
        float neutral = (1.0 - placement.effects.z) * smoothstep(0.05, 0.9, a);
        combined = mix(combined, float3(dot(combined, float3(0.2126, 0.7152, 0.0722))), neutral);
    }
    return float4(combined, eligible ? a + background.a * (1.0 - a) : background.a * (1.0 - a));
}
