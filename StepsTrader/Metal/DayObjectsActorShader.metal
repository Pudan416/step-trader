#include <metal_stdlib>
using namespace metal;

struct DayObjectGPUActor {
    float2 position;
    float2 direction;
    float2 halfSize;
    float2 positionPadding;
    float4 color;
    float opacity;
    float trailLength;
    uint shape;
    uint fill;
    float depth;
    float radialVariation;
    float tailPadding1;
    float tailPadding2;
};

static_assert(alignof(DayObjectGPUActor) == 16, "GPU actors require 16-byte alignment");
static_assert(sizeof(DayObjectGPUActor) == 80, "GPU actors must match Swift's 80-byte stride");

struct DayObjectsActorUniforms {
    float2 resolution;
    float energyNormalization;
    float shortSidePixels;
    float4 radialColor0;
    float4 radialColor1;
    float4 radialColor2;
    float4 radialParameters0;
    float4 radialParameters1;
    float4 radialParameters2;
};

static_assert(alignof(DayObjectsActorUniforms) == 16, "Actor uniforms require 16-byte alignment");
static_assert(sizeof(DayObjectsActorUniforms) == 112, "Actor uniforms must match Swift's 112-byte stride");

struct DayObjectsActorVertexOut {
    float4 position [[position]];
    float2 localPosition;
    float2 halfSize;
    float4 color;
    float opacity;
    float trailEnergyNormalization;
    float trailLength;
    float shortSidePixels;
    float radialVariation;
    uint shape [[flat]];
    uint fill [[flat]];
};

constant float dayObjectsScallopRadialReach = 1.13;
constant float dayObjectsTrailSigmaFactor = 0.70;
constant float dayObjectsTrailSigmaSupport = 3.5;

vertex DayObjectsActorVertexOut dayObjectsActorVertex(
    const device float2 *quadPositions [[buffer(0)]],
    const device DayObjectGPUActor *actors [[buffer(1)]],
    constant DayObjectsActorUniforms &uniforms [[buffer(2)]],
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
    // Scallop's modulated radius reaches 1.13 in some directions and its
    // major-axis support reaches 1.10598. The radial maximum is a conservative
    // body bound; every other SDF remains inside its nominal major half-size.
    const float bodyMajorReach = halfSize.x * (
        actor.shape == 5 ? dayObjectsScallopRadialReach : 1.0
    );
    const float bodyMinorReach = halfSize.y * (
        actor.shape == 5 ? dayObjectsScallopRadialReach : 1.0
    );
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
    out.color = actor.color;
    out.opacity = clamp(actor.opacity, 0.0, 1.0);
    out.trailEnergyNormalization = clamp(uniforms.energyNormalization, 0.0, 1.0);
    out.trailLength = max(actor.trailLength, 0.0);
    out.shortSidePixels = shortSidePixels;
    out.radialVariation = clamp(actor.radialVariation, -1.0, 1.0);
    out.shape = actor.shape;
    out.fill = actor.fill;
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

/// A soft, non-banded radial field. Every actor shares the daily palette and
/// topology; its stable variation only changes the local focal placement and
/// gradient direction so overlaps do not look like duplicated stickers.
static float3 dayObjectsStaticRadialColor(
    DayObjectsActorVertexOut in,
    constant DayObjectsActorUniforms &uniforms,
    float2 bodyPoint,
    float aspect
) {
    const float radius = max(uniforms.radialParameters0.x, 0.05);
    const float focalDistance = clamp(uniforms.radialParameters0.y, 0.0, 0.95);
    const float focalAngle = uniforms.radialParameters0.z + in.radialVariation * 0.45;
    const float falloff = clamp(uniforms.radialParameters0.w, -0.5, 0.8);
    const float mixing = clamp(uniforms.radialParameters1.x, 0.0, 1.0);
    const float distortion = clamp(uniforms.radialParameters1.y, 0.0, 0.7);
    const float distortionShift = clamp(uniforms.radialParameters1.z, -1.0, 1.0);
    const float distortionFrequency = clamp(uniforms.radialParameters1.w, 2.0, 12.0);
    const float rotation = uniforms.radialParameters2.x + in.radialVariation * 0.35;
    const float2 offset = uniforms.radialParameters2.yz
        + float2(in.radialVariation, -in.radialVariation) * 0.055;
    const uint requestedColorCount = uint(clamp(round(uniforms.radialParameters2.w), 1.0, 3.0));
    const uint colorCount = min(requestedColorCount, in.fill + 1);

    float2 point = float2(bodyPoint.x, bodyPoint.y / max(aspect, 1e-4));
    point = dayObjectsRotate(point, rotation) - offset;
    const float2 focal = float2(cos(focalAngle), sin(focalAngle)) * focalDistance;
    const float2 focalPoint = point - focal;
    const float polarAngle = atan2(focalPoint.y, focalPoint.x);
    const float deformation = sin(
        polarAngle * distortionFrequency
            + distortionShift * M_PI_F
            + in.radialVariation * 1.7
    ) * distortion * 0.16;
    const float normalizedRadius = length(focalPoint) / radius + deformation + falloff;
    const float softness = mix(0.10, 0.42, mixing);
    float radialT = smoothstep(-softness, 1.0 + softness, normalizedRadius);
    radialT = clamp(radialT + in.radialVariation * 0.08, 0.0, 1.0);

    const float3 color0 = max(uniforms.radialColor0.rgb, 0.0);
    const float3 color1 = max(uniforms.radialColor1.rgb, 0.0);
    const float3 color2 = max(uniforms.radialColor2.rgb, 0.0);
    if (colorCount <= 1) {
        return color0 * mix(1.08, 0.72, radialT);
    }

    const float directedT = in.radialVariation < 0.0 ? 1.0 - radialT : radialT;
    if (colorCount == 2) {
        return mix(color0, color1, directedT);
    }

    return directedT < 0.5
        ? mix(color0, color1, smoothstep(0.0, 0.5, directedT))
        : mix(color1, color2, smoothstep(0.5, 1.0, directedT));
}

/// The seven Day Object body families in local units where the major-axis
/// half-size is one and `aspect` is the minor/major ratio.
static float dayObjectsActorBody(uint shape, float2 point, float aspect) {
    switch (shape) {
    case 1: { // drop
        const float2 ellipsePoint = float2(point.x, point.y / max(aspect, 1e-4));
        return length(ellipsePoint) - 1.0;
    }
    case 2: { // slab
        const float2 delta = abs(point) - float2(1.0, aspect);
        return length(max(delta, 0.0)) + min(max(delta.x, delta.y), 0.0);
    }
    case 3: { // dart
        const float halfWidth = aspect * (1.0 - point.x) * 0.5;
        return max(abs(point.x) - 1.0, abs(point.y) - halfWidth);
    }
    case 4: { // wedge
        const float halfWidth = aspect * (1.0 + point.x) * 0.5;
        return max(abs(point.x) - 1.0, abs(point.y) - halfWidth);
    }
    case 5: { // scallop
        const float2 ellipsePoint = float2(point.x, point.y / max(aspect, 1e-4));
        const float radius = length(ellipsePoint);
        const float angle = atan2(ellipsePoint.y, ellipsePoint.x);
        return radius - (1.0 - 0.13 * sin(7.0 * angle));
    }
    case 6: { // burst
        const float2 ellipsePoint = float2(point.x, point.y / max(aspect, 1e-4));
        const float radius = length(ellipsePoint);
        const float angle = atan2(ellipsePoint.y, ellipsePoint.x);
        const float spikes = 0.42 + 0.58 * pow(abs(cos(6.0 * angle)), 0.45);
        return radius - spikes;
    }
    default: { // capsule
        const float radius = min(aspect * 0.95, 0.42);
        const float2 delta = abs(point) - float2(
            1.0 - radius,
            max(aspect - radius, 0.0)
        );
        return length(max(delta, 0.0)) + min(max(delta.x, delta.y), 0.0) - radius;
    }
    }
}

fragment float4 dayObjectsActorFragment(
    DayObjectsActorVertexOut in [[stage_in]],
    constant DayObjectsActorUniforms &uniforms [[buffer(2)]]
) {
    const float majorHalfSize = max(in.halfSize.x, 1e-5);
    const float aspect = in.halfSize.y / majorHalfSize;
    const float2 bodyPoint = in.localPosition / majorHalfSize;
    const float signedBodyDistancePixels = dayObjectsActorBody(
        in.shape,
        bodyPoint,
        aspect
    ) * majorHalfSize * in.shortSidePixels;

    // Derivatives are evaluated after conversion to screen pixels, so the
    // transition width remains a physical-pixel quantity on every canvas.
    const float antialiasPixels = max(fwidth(signedBodyDistancePixels), 0.70);
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

    const float actorOpacity = clamp(in.opacity * in.color.a, 0.0, 1.0);
    const float bodyAlpha = bodyCoverage * actorOpacity;
    const float trailAlpha = trailCoverage * actorOpacity * in.trailEnergyNormalization;
    const float visibleTrailAlpha = trailAlpha * (1.0 - bodyAlpha);
    const float alpha = clamp(bodyAlpha + visibleTrailAlpha, 0.0, 1.0);

    const float3 bodyColor = dayObjectsStaticRadialColor(in, uniforms, bodyPoint, aspect);
    const float3 trailColor = max(in.color.rgb * 0.88, 0.0);
    const float3 premultiplied = bodyColor * bodyAlpha
        + trailColor * visibleTrailAlpha;
    return float4(premultiplied, alpha);
}
