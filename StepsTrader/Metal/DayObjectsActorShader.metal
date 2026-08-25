#include <metal_stdlib>
using namespace metal;

struct alignas(16) DayObjectGPUActor {
    float2 position;
    float2 direction;
    float2 halfSize;
    float2 quadPadding;
    float opacity;
    float trailLength;
    uint shape;
    uint appearanceIndex;
    float depth;
    float materialPhase;
    float localDepthSoftness;
    float tailPadding;
};

static_assert(alignof(DayObjectGPUActor) == 16, "GPU actors require 16-byte alignment");
static_assert(sizeof(DayObjectGPUActor) == 64, "GPU actors must match Swift's 64-byte stride");

struct DayObjectGPUAppearance {
    float4 color0;
    float4 color1;
    float4 color2;
    float4 radial0;
    float4 radial1;
    float4 optical0;
    float4 optical1;
    float4 membrane;
    float4 light;
    uint4 metadata;
};

static_assert(alignof(DayObjectGPUAppearance) == 16, "GPU appearances require 16-byte alignment");
static_assert(sizeof(DayObjectGPUAppearance) == 160, "GPU appearances must match Swift's 160-byte stride");

struct DayObjectsActorUniforms {
    float2 resolution;
    float energyNormalization;
    float shortSidePixels;
    float2 lightDirection;
    float lightSoftness;
    float globalTime;
};

static_assert(alignof(DayObjectsActorUniforms) == 8, "Actor uniforms require 8-byte alignment");
static_assert(sizeof(DayObjectsActorUniforms) == 32, "Actor uniforms must match Swift's 32-byte stride");

struct DayObjectsActorVertexOut {
    float4 position [[position]];
    float2 localPosition;
    float2 halfSize;
    float opacity;
    float trailEnergyNormalization;
    float trailLength;
    float shortSidePixels;
    float materialPhase;
    float localDepthSoftness;
    uint shape [[flat]];
    uint appearanceIndex [[flat]];
};

constant float dayObjectsSoftBlobRadialReach = 1.06;
constant float dayObjectsTrailSigmaFactor = 0.36;
constant float dayObjectsTrailSigmaSupport = 3.2;

vertex DayObjectsActorVertexOut dayObjectsActorVertex(
    const device float2 *quadPositions [[buffer(0)]],
    const device DayObjectGPUActor *actors [[buffer(1)]],
    constant DayObjectsActorUniforms &uniforms [[buffer(3)]],
    uint vertexID [[vertex_id]],
    uint instanceID [[instance_id]]
) {
    const DayObjectGPUActor actor = actors[instanceID];
    const float shortSidePixels = max(uniforms.shortSidePixels, 1.0);
    const float2 halfSize = max(actor.halfSize, float2(0.0));
    const float pixelMargin = 2.0 / shortSidePixels;
    const float trailSigma = max(
        halfSize.y * dayObjectsTrailSigmaFactor,
        1.25 / shortSidePixels
    );
    const float mergeReach = halfSize.x * 0.18;
    const float bodyMajorReach = halfSize.x * (
        actor.shape == 3 ? dayObjectsSoftBlobRadialReach : 1.0
    ) + mergeReach;
    const float bodyMinorReach = halfSize.y * (
        actor.shape == 3 ? dayObjectsSoftBlobRadialReach : 1.0
    ) + mergeReach;
    const float trailMinimumX = -halfSize.x - max(actor.trailLength, 0.0);

    // The local quad spans the body plus the complete exponential/Gaussian
    // trail support. It is asymmetric because negative local x is behind the
    // actual time-direction velocity supplied by the CPU.
    const float2 localMinimum = float2(
        min(-bodyMajorReach, trailMinimumX) - pixelMargin,
        -max(bodyMinorReach, trailSigma * dayObjectsTrailSigmaSupport) - pixelMargin
    );
    const float2 localMaximum = float2(
        bodyMajorReach + pixelMargin,
        max(bodyMinorReach, trailSigma * dayObjectsTrailSigmaSupport) + pixelMargin
    );
    const float2 corner = quadPositions[vertexID] * 0.5 + 0.5;
    const float2 local = mix(localMinimum, localMaximum, corner);

    float2 forward = actor.direction;
    const float directionLength = length(forward);
    forward = directionLength > 1e-6 ? forward / directionLength : float2(1.0, 0.0);
    const float2 lateral = float2(-forward.y, forward.x);
    const float2 shortSidePosition = actor.position + forward * local.x + lateral * local.y;
    const float2 canvasSpan = max(uniforms.resolution / shortSidePixels, float2(1.0));

    DayObjectsActorVertexOut out;
    out.position = float4(shortSidePosition * 2.0 / canvasSpan, 0.0, 1.0);
    out.localPosition = local;
    out.halfSize = halfSize;
    out.opacity = clamp(actor.opacity, 0.0, 1.0);
    out.trailEnergyNormalization = clamp(uniforms.energyNormalization, 0.0, 1.0);
    out.trailLength = max(actor.trailLength, 0.0);
    out.shortSidePixels = shortSidePixels;
    out.materialPhase = fract(max(actor.materialPhase, 0.0));
    out.localDepthSoftness = clamp(actor.localDepthSoftness, 0.0, 1.0);
    out.shape = actor.shape;
    out.appearanceIndex = actor.appearanceIndex;
    return out;
}

static float2 dayObjectsRotate(float2 point, float angle) {
    const float sine = sin(angle);
    const float cosine = cos(angle);
    return float2(
        cosine * point.x - sine * point.y,
        sine * point.x + cosine * point.y
    );
}

/// Every actor shares a daily static-radial preset. Actor variation only moves
/// its focal point and phase, so overlapping orbs feel related without looking
/// like duplicated stickers.
static float3 dayObjectsStaticRadialColor(
    DayObjectsActorVertexOut in,
    DayObjectGPUAppearance appearance,
    float2 bodyPoint,
    float aspect
) {
    const float variation = in.materialPhase * 2.0 - 1.0;
    const float focalDistance = clamp(appearance.radial0.x, 0.0, 0.95);
    const float focalAngle = appearance.radial0.y + variation * 0.20;
    const float radius = max(appearance.radial0.z, 0.05);
    const float falloff = clamp(appearance.radial0.w, -0.5, 0.8);
    const float mixing = clamp(appearance.radial1.x, 0.0, 1.0);
    const float distortion = clamp(appearance.radial1.y, 0.0, 0.7);
    const float distortionShift = clamp(appearance.radial1.z, -1.0, 1.0);
    const float distortionFrequency = clamp(appearance.radial1.w, 2.0, 12.0);
    const uint colorCount = clamp(appearance.metadata.y, 1u, 3u);

    float2 point = float2(bodyPoint.x, bodyPoint.y / max(aspect, 1e-4));
    point = dayObjectsRotate(point, variation * 0.12);
    const float2 focal = float2(cos(focalAngle), sin(focalAngle)) * focalDistance;
    const float2 focalPoint = point - focal;
    const float polarAngle = atan2(focalPoint.y, focalPoint.x);
    float deformation = sin(
        polarAngle * distortionFrequency
            + distortionShift * M_PI_F
            + variation * 1.7
    ) * distortion * 0.16;
    const float normalizedRadius = length(focalPoint) / radius + deformation + falloff;
    const float softness = mix(0.10, 0.42, mixing);
    float radialT = smoothstep(-softness, 1.0 + softness, normalizedRadius);
    radialT = clamp(radialT + variation * 0.05, 0.0, 1.0);

    const float3 color0 = max(appearance.color0.rgb, 0.0);
    const float3 color1 = max(appearance.color1.rgb, 0.0);
    const float3 color2 = max(appearance.color2.rgb, 0.0);
    if (colorCount <= 1) {
        return color0 * mix(1.08, 0.72, radialT);
    }

    const float directedT = variation < 0.0 ? 1.0 - radialT : radialT;
    if (colorCount == 2) {
        return mix(color0, color1, directedT);
    }

    return directedT < 0.5
        ? mix(color0, color1, smoothstep(0.0, 0.5, directedT))
        : mix(color1, color2, smoothstep(0.5, 1.0, directedT));
}

/// Four circle-derived bodies in local units. None of the variants can produce
/// the old triangles, slabs, petals, or thin Figma-like particles.
static float dayObjectsActorBody(
    uint shape,
    float2 point,
    float aspect,
    float radialVariation
) {
    const float2 ellipsePoint = float2(point.x, point.y / max(aspect, 1e-4));
    const float radius = length(ellipsePoint);
    const float angle = atan2(ellipsePoint.y, ellipsePoint.x);
    switch (shape) {
    case 1: // ellipse
        return radius - 1.0;
    case 2: { // softly pinched lens
        const float lensRadius = 1.0 - 0.055 * pow(abs(sin(angle)), 2.0);
        return radius - lensRadius;
    }
    case 3: { // low-amplitude organic orb
        const float blobRadius = 1.0 + 0.055 * sin(3.0 * angle + radialVariation * 1.8);
        return radius - blobRadius;
    }
    default: // sphere
        return radius - 1.0;
    }
}

fragment float4 dayObjectsActorFragment(
    DayObjectsActorVertexOut in [[stage_in]],
    const device DayObjectGPUAppearance *appearances [[buffer(2)]],
    constant DayObjectsActorUniforms &uniforms [[buffer(3)]]
) {
    const DayObjectGPUAppearance appearance = appearances[in.appearanceIndex];
    const float majorHalfSize = max(in.halfSize.x, 1e-5);
    const float aspect = in.halfSize.y / majorHalfSize;
    const float2 bodyPoint = in.localPosition / majorHalfSize;
    const float signedBodyDistancePixels = dayObjectsActorBody(
        in.shape,
        bodyPoint,
        aspect,
        in.materialPhase * 2.0 - 1.0
    ) * majorHalfSize * in.shortSidePixels;

    // Derivatives are evaluated after conversion to screen pixels, so the
    // transition width remains a physical-pixel quantity on every canvas.
    const float antialiasPixels = max(
        fwidth(signedBodyDistancePixels),
        0.70 + in.localDepthSoftness * 12.0
    );
    const float bodyCoverage = 1.0 - smoothstep(
        -antialiasPixels,
        antialiasPixels,
        signedBodyDistancePixels
    );

    const float trailSigma = max(
        in.halfSize.y * dayObjectsTrailSigmaFactor,
        1.25 / in.shortSidePixels
    );
    const float trailDistance = max(-in.localPosition.x - in.halfSize.x, 0.0);
    const float behindBody = 1.0 - step(-in.halfSize.x, in.localPosition.x);
    const float trailEnabled = step(1e-5, in.trailLength);
    const float trailFadeLength = max(in.trailLength * 0.38, 1.0 / in.shortSidePixels);
    const float longitudinal = exp(-trailDistance / trailFadeLength)
        * (1.0 - smoothstep(in.trailLength * 0.82, in.trailLength, trailDistance));
    const float lateralRatio = in.localPosition.y / trailSigma;
    const float lateralSupport = 1.0 - smoothstep(
        3.0,
        dayObjectsTrailSigmaSupport,
        abs(lateralRatio)
    );
    const float lateral = exp(-0.5 * lateralRatio * lateralRatio) * lateralSupport;
    const float trailCoverage = trailEnabled * behindBody * longitudinal * lateral * 0.72;

    const float actorOpacity = clamp(in.opacity * appearance.optical0.z, 0.0, 1.0);
    const float bodyAlpha = bodyCoverage * actorOpacity;
    const float trailAlpha = trailCoverage * actorOpacity * in.trailEnergyNormalization;
    const float visibleTrailAlpha = trailAlpha * (1.0 - bodyAlpha);
    const float mergeReachPixels = max(
        majorHalfSize * 0.18 * in.shortSidePixels,
        1.0
    );
    const float mergeCoverage = (1.0 - bodyCoverage) * (
        1.0 - smoothstep(0.0, mergeReachPixels, max(signedBodyDistancePixels, 0.0))
    );
    const float mergeAlpha = mergeCoverage * actorOpacity
        * 0.16;
    const float visibleMergeAlpha = mergeAlpha * (1.0 - bodyAlpha) * (1.0 - visibleTrailAlpha);
    const float alpha = clamp(bodyAlpha + visibleTrailAlpha + visibleMergeAlpha, 0.0, 1.0);

    const float3 bodyColor = dayObjectsStaticRadialColor(in, appearance, bodyPoint, aspect);
    const float3 trailColor = max(appearance.color0.rgb * 0.88, 0.0);
    const float3 premultiplied = bodyColor * bodyAlpha
        + trailColor * visibleTrailAlpha
        + bodyColor * visibleMergeAlpha;
    return float4(premultiplied, alpha);
}
