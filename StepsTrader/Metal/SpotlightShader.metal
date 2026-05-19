#include <metal_stdlib>
#include <SwiftUI/SwiftUI.h>
using namespace metal;

[[ stitchable ]] half4 spotlightEffect(
    float2 position,
    SwiftUI::Layer layer,
    float2 resolution,
    float time,
    half4 nearColor,
    half4 midColor,
    half4 farColor
) {
    float2 uv = position / resolution;
    float aspect = resolution.x / resolution.y;
    float2 p = (uv - 1.0) * float2(aspect, 1.0);

    float2 lightPos = float2(-0.5 * aspect, -0.5);

    // Sync numeric values with RayShapeRenderer (shaderAim, coneAngleMin/Max, coneBreathSpeed).
    float aim = 1.15;
    float2 dir = float2(sin(aim), cos(aim));

    float coneAngle = mix(78.0, 105.0, 0.5 + 0.5 * sin(time * 0.45));
    float halfAngleRad = coneAngle * 0.5 * M_PI_F / 180.0;

    float2 dlt = p - lightPos;
    float dist = length(dlt);
    float2 dirN = normalize(dir);
    constexpr float eps = 1e-4;
    float2 L = dist > eps ? dlt / dist : dirN;

    // Gaussian cone falloff — softer than smoothstep, no visible boundary
    float pixelAngle = acos(clamp(dot(L, dirN), -1.0, 1.0));
    float cone = exp(-pixelAngle * pixelAngle / (halfAngleRad * halfAngleRad * 0.6));

    float att = 1.0 / (1.35 + 5.5 * dist * dist + 1.2 * dist);
    float light = cone * att;

    // Angular color: pixel angle within cone drives a 3-stop gradient
    float angularT = clamp(pixelAngle / max(halfAngleRad, 0.01), 0.0, 1.0);
    float3 angularColor;
    if (angularT < 0.5) {
        angularColor = mix(float3(nearColor.rgb), float3(midColor.rgb), angularT * 2.0);
    } else {
        angularColor = mix(float3(midColor.rgb), float3(farColor.rgb), (angularT - 0.5) * 2.0);
    }

    // Radial color: classic distance-based 3-stop ramp
    float tRad = pow(smoothstep(0.04, 0.68, dist), 0.82);
    float3 radialColor = mix(float3(nearColor.rgb), float3(midColor.rgb),
                             clamp(tRad / 0.3, 0.0, 1.0));
    radialColor = mix(radialColor, float3(farColor.rgb),
                      clamp((tRad - 0.3) / 0.62, 0.0, 1.0));

    // Blend: core uses radial (bright center), edges use angular
    float radialMix = 1.0 - exp(-dist * 2.5);
    float3 lightColor = mix(radialColor, angularColor, radialMix);

    // Hotspot at light source — bright near-color accent
    float hotspot = exp(-dist * dist * 12.0);
    lightColor += float3(nearColor.rgb) * hotspot * 0.4;
    lightColor = min(lightColor, float3(1.0));

    float coreMul = mix(0.62, 1.0, smoothstep(0.0, 0.26, dist));
    float lightT = pow(clamp(light, 0.0, 1.0), 1.12);
    float w = lightT * coreMul * 1.35;

    float2 centered = uv - 0.5;
    float radialDist = length(centered) * 2.0;
    float edgeFade = 1.0 - smoothstep(0.6, 1.0, radialDist);
    w *= edgeFade;

    float a = clamp(w, 0.0, 1.0);
    half3 premul = half3(lightColor * w);

    return half4(premul, half(a));
}
