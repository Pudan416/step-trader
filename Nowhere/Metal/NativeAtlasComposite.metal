#include "HappeningPickerStyle.metalh"
#include "ShapeAtlas/Materials/MetalShapeMaterials.metalh"

struct NativeAtlasPlacement { float4 pose; float4 canvas; float4 effects; float4 presentation; float4 trace; };
static_assert(sizeof(NativeAtlasPlacement) == 80, "Native placement must match five Swift float4 values");

fragment float4 nativeAtlasComposite(MetalShapeVertexOut in [[stage_in]],
    constant MetalShapeGenomeUniforms &g [[buffer(0)]],
    constant MetalShapeMaterialUniforms &m [[buffer(1)]],
    constant NativeAtlasPlacement &placement [[buffer(2)]],
    constant float4 &pickerAccent [[buffer(3)]],
    texture2d<float> previous [[texture(0)]],
    texture2d<float> canvasBackground [[texture(1)]]) {
    constexpr sampler linearSampler(coord::normalized, address::clamp_to_edge, filter::linear);
    const float2 resolution = placement.canvas.xy;
    float2 local = (in.uv - placement.pose.xy) * resolution / min(resolution.x, resolution.y) / max(placement.pose.z, 0.001);
    const float2 pickerPoint = local * 2.72;
    const float c = cos(placement.pose.w), s = sin(placement.pose.w);
    local = float2(local.x * c + local.y * s, -local.x * s + local.y * c);
    const float morph = saturate(placement.presentation.x);
    const float4 background = previous.sample(linearSampler, in.uv);
    const float4 cleanCanvas = canvasBackground.sample(linearSampler, in.uv);
    if (morph == 0.0) {
        // Available targets do not inherit the future figure's material or
        // intersection mask. The figure is evaluated only after selection.
        const float2 point = pickerPoint;
        const float distance = happeningPickerRadius(point) - 1.0;
        const float aa = max(fwidth(distance), 0.0025);
        const float4 lens = happeningPickerFill(happeningPickerRadius(point), smoothstep(aa, -aa, distance), pickerAccent.rgb) * placement.canvas.z;
        return float4(lens.rgb + background.rgb * (1.0 - lens.a), lens.a + background.a * (1.0 - lens.a));
    }
    MetalShapeVertexOut shapeIn = in; shapeIn.uv = local + 0.5;
    float4 shape = metalShapeGenomeShade(shapeIn, g, m);
    if (morph < 1.0) {
        // A quiet translucent rounded target until the first tap. Keep the Canvas
        // visible through its centre; a soft edge gives the touch target shape.
        const float2 point = local * 2.72;
        const float distance = mix(happeningPickerRadius(pickerPoint) - 1.0, metalShapeDistance(point, g), morph);
        const float aa = max(fwidth(distance), 0.0025);
        const float filled = smoothstep(aa, -aa, distance);
        const float reveal = smoothstep(0.45, 1.0, morph);
        shape = mix(happeningPickerFill(happeningPickerRadius(pickerPoint), filled, pickerAccent.rgb), shape, reveal);
    }
    float4 foreground = shape * placement.canvas.z;
    float a = clamp(foreground.a, 0.0, 1.0);
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
    // Spend traces are rendered against each figure's local geometry. The
    // ambient gradient remains the material revealed by fades and erosion.
    const uint traceType = uint(placement.trace.x);
    const float traceStrength = saturate(placement.trace.y);
    if (eligible && traceStrength > 0.0 && traceType >= 5u && traceType <= 8u) {
        const float seeded = placement.trace.z * 127.0 + placement.trace.w * 311.0;
        if (traceType == 5u && a > 0.001) { // Signal: color registration at edges and tiny tears.
            const float edge = smoothstep(0.025, 0.18, coverageDerivative);
            const float band = fract((local.y * 21.0 + seeded) * 0.5);
            const float tear = (1.0 - smoothstep(0.08, 0.19, abs(band - 0.5)))
                * step(0.72, fract(sin(floor(local.y * 21.0 + seeded) * 91.7) * 43758.5));
            const float3 split = float3(color.r * 0.62 + 0.38, color.g * 0.78 + 0.12, color.b * 0.66 + 0.34);
            color = mix(color, split, traceStrength * (edge * 0.7 + tear * 0.38));
        } else if (traceType == 6u && a > 0.001) { // Fade: pigment recedes into the canvas.
            color = mix(color, background.rgb, traceStrength * 0.88);
            a *= 1.0 - traceStrength * 0.36;
        } else if (traceType == 7u) { // Drift: a soft, seeded pigment echo trails an edge.
            const float angle = placement.trace.z * 6.2831853;
            const float2 direction = float2(cos(angle), sin(angle));
            MetalShapeVertexOut echoIn = in;
            echoIn.uv = local + 0.5 - direction * (0.06 + traceStrength * 0.28);
            if (all(echoIn.uv >= 0.0) && all(echoIn.uv <= 1.0)) {
                const float4 echo = metalShapeGenomeShade(echoIn, g, m);
                const float trail = clamp(echo.a * traceStrength * 0.42 * (1.0 - a), 0.0, 0.28);
                const float3 pigment = mix(echo.rgb / max(echo.a, 0.0001), float3(0.30, 0.78, 0.72), 0.22);
                color = (color * a + pigment * trail) / max(a + trail, 0.0001);
                a += trail;
            }
        } else if (traceType == 8u && a > 0.001) { // Erosion: pinholes reveal the gradient below.
            const float cellScale = mix(16.0, 43.0, traceStrength);
            const float2 cell = floor((local + 0.5) * cellScale + float2(seeded, seeded * 0.71));
            const float noise = fract(sin(dot(cell, float2(127.1, 311.7))) * 43758.5453);
            const float erosion = step(0.63, noise) * smoothstep(0.14, 0.92, traceStrength);
            a *= 1.0 - erosion * 0.78;
        }
    }
    float3 combined = color * a + background.rgb * (1.0 - a);
    const float2 shapePoint = local * 2.72;
    const float shapeDistance = metalShapeDistance(shapePoint, g);
    const float matteAA = max(fwidth(shapeDistance), 0.0025);
    const float glowCutout = m.metadata.x == 9u && placement.presentation.y < 0.5
        ? (1.0 - smoothstep(-matteAA, matteAA, shapeDistance)) * placement.canvas.z
        : 0.0;
    combined = mix(combined, cleanCanvas.rgb, glowCutout);
    if (placement.presentation.y > 0.5) {
        // Confirmation previews stay neutral even over saturated artwork. Keep
        // the outside background untouched and preserve the opacity transition.
        float neutral = (1.0 - placement.effects.z) * smoothstep(0.05, 0.9, a);
        combined = mix(combined, float3(dot(combined, float3(0.2126, 0.7152, 0.0722))), neutral);
    }
    const float sceneAlpha = eligible ? a + background.a * (1.0 - a) : background.a * (1.0 - a);
    return float4(combined, mix(sceneAlpha, 1.0, glowCutout));
}
