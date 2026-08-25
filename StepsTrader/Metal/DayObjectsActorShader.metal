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
    float2 screenUV;
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
    // Clip-space +Y is presented toward the top of the Metal viewport, while
    // texture UV +Y points down. Preserve the same top-left screen position
    // when glass samples the already-rendered background.
    out.screenUV = float2(
        shortSidePosition.x / canvasSpan.x + 0.5,
        0.5 - shortSidePosition.y / canvasSpan.y
    );
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
    const float localSoftness = clamp(
        in.localDepthSoftness + appearance.optical1.w,
        0.0,
        1.0
    );
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
    ) * distortion * mix(0.16, 0.02, localSoftness);
    const float normalizedRadius = length(focalPoint) / radius + deformation + falloff;
    const float softness = mix(0.10, 0.42, mixing) + localSoftness * 0.24;
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
    constant DayObjectsActorUniforms &uniforms [[buffer(3)]],
    texture2d<float> backgroundTexture [[texture(0)]],
    sampler linearSampler [[sampler(0)]]
) {
    const DayObjectGPUAppearance appearance = appearances[in.appearanceIndex];
    const float majorHalfSize = max(in.halfSize.x, 1e-5);
    const float aspect = in.halfSize.y / majorHalfSize;
    const float2 bodyPoint = in.localPosition / majorHalfSize;
    const float2 ellipticalPoint = float2(bodyPoint.x, bodyPoint.y / max(aspect, 1e-4));
    const float radialDistance = length(ellipticalPoint);
    const float combinedLocalSoftness = clamp(
        in.localDepthSoftness + appearance.optical1.w,
        0.0,
        1.0
    );
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
        0.70 + combinedLocalSoftness * 12.0
    );
    const float bodyCoverage = 1.0 - smoothstep(
        -antialiasPixels,
        antialiasPixels,
        signedBodyDistancePixels
    );
    const float outsideDistancePixels = max(signedBodyDistancePixels, 0.0);
    const float haloReachPixels = max(majorHalfSize * 0.18 * in.shortSidePixels, 1.0);
    const float haloCoverage = (1.0 - bodyCoverage) * (
        1.0 - smoothstep(0.0, haloReachPixels, outsideDistancePixels)
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

    const float actorOpacity = clamp(in.opacity, 0.0, 1.0);
    const float materialBodyOpacity = clamp(appearance.optical0.z, 0.0, 1.0);
    float bodyAlpha = bodyCoverage * actorOpacity * materialBodyOpacity;
    const float trailAlpha = trailCoverage * actorOpacity * materialBodyOpacity
        * in.trailEnergyNormalization * 0.32;
    const float visibleTrailAlpha = trailAlpha * (1.0 - bodyAlpha);
    const float mergeReachPixels = max(
        majorHalfSize * 0.18 * in.shortSidePixels,
        1.0
    );
    const float mergeCoverage = (1.0 - bodyCoverage) * (
        1.0 - smoothstep(0.0, mergeReachPixels, max(signedBodyDistancePixels, 0.0))
    );
    const float mergeAlpha = mergeCoverage * actorOpacity * materialBodyOpacity
        * 0.16;
    const float visibleMergeAlpha = mergeAlpha * (1.0 - bodyAlpha)
        * (1.0 - visibleTrailAlpha);

    float3 bodyColor = dayObjectsStaticRadialColor(in, appearance, bodyPoint, aspect);
    const float3 trailColor = max(appearance.color0.rgb * 0.88, 0.0);
    const float centerMask = 1.0 - smoothstep(0.08, 0.78, radialDistance);
    const float rimMask = smoothstep(0.55, 1.0, radialDistance);
    const float2 sphereNormal = radialDistance > 1e-5
        ? ellipticalPoint / radialDistance
        : float2(0.0, 0.0);
    const float light = 0.5 + 0.5 * dot(
        sphereNormal,
        normalize(uniforms.lightDirection + float2(1e-5, 0.0))
    );
    const float lightHalfWidth = max(clamp(uniforms.lightSoftness, 0.0, 1.0) * 0.48, 0.04);
    const float softenedLight = smoothstep(
        0.5 - lightHalfWidth,
        0.5 + lightHalfWidth,
        light
    );
    const float lightResponse = clamp(appearance.light.x, 0.0, 1.0);
    const uint material = min(appearance.metadata.x, 5u);
    float haloAlpha = 0.0;
    float3 haloColor = appearance.color1.rgb;

    switch (material) {
    case 1u: { // Inner Glow
        const float glow = clamp(appearance.optical0.x, 0.0, 1.0);
        bodyColor *= 0.62 + glow * 0.75 * centerMask + 0.16 * softenedLight;
        bodyAlpha *= mix(0.78, 1.0, centerMask);
        break;
    }
    case 2u: { // Rim Glow
        const float rim = clamp(appearance.optical1.x, 0.0, 1.0);
        bodyColor *= 0.38 + rim * 1.15 * rimMask;
        haloAlpha = haloCoverage * actorOpacity
            * clamp(appearance.optical0.y, 0.0, 1.0) * 0.85;
        haloColor = mix(appearance.color1.rgb, appearance.color2.rgb, 0.5);
        break;
    }
    case 3u: { // Glass
        const float refraction = clamp(appearance.optical1.y, 0.0, 0.08);
        const float angle = appearance.optical1.z;
        const float2 refractionDirection = normalize(
            sphereNormal + float2(cos(angle), sin(angle)) * 0.35 + float2(1e-5, 0.0)
        );
        const float3 refracted = backgroundTexture.sample(
            linearSampler,
            clamp(in.screenUV + refractionDirection * refraction, 0.0, 1.0)
        ).rgb;
        const float3 tint = mix(appearance.color0.rgb, appearance.color1.rgb, 0.5);
        bodyColor = mix(refracted, tint, 0.18 + 0.18 * centerMask)
            + appearance.color2.rgb * rimMask * 0.22;
        bodyAlpha = bodyCoverage * actorOpacity
            * clamp(materialBodyOpacity + rimMask * appearance.optical1.x * 0.22, 0.0, 1.0);
        haloAlpha = haloCoverage * actorOpacity * appearance.optical0.y * 0.28;
        haloColor = appearance.color2.rgb;
        break;
    }
    case 4u: { // Membrane
        const uint layerCount = clamp(appearance.metadata.z, 2u, 3u);
        const float2 offset = appearance.membrane.xy;
        const float layer1 = 1.0 - smoothstep(
            -antialiasPixels,
            antialiasPixels,
            dayObjectsActorBody(in.shape, bodyPoint - offset, aspect, in.materialPhase * 2.0 - 1.0)
                * majorHalfSize * in.shortSidePixels
        );
        const float layer2 = 1.0 - smoothstep(
            -antialiasPixels,
            antialiasPixels,
            dayObjectsActorBody(in.shape, bodyPoint + offset, aspect, in.materialPhase * 2.0 - 1.0)
                * majorHalfSize * in.shortSidePixels
        );
        const float layer3 = layerCount == 3u ? bodyCoverage : 0.0;
        const float a0 = layer1 * actorOpacity * materialBodyOpacity * 0.48;
        const float a1 = layer2 * actorOpacity * materialBodyOpacity * 0.48;
        const float a2 = layer3 * actorOpacity * materialBodyOpacity * 0.36;
        const float composite = 1.0 - (1.0 - a0) * (1.0 - a1) * (1.0 - a2);
        bodyAlpha = composite;
        const float weight = max(a0 + a1 + a2, 1e-5);
        bodyColor = (
            appearance.color0.rgb * a0
                + appearance.color1.rgb * a1
                + appearance.color2.rgb * a2
        ) / weight;
        haloAlpha = haloCoverage * actorOpacity * appearance.optical0.y * 0.30;
        break;
    }
    case 5u: { // Spectral
        const float angle = atan2(ellipticalPoint.y, ellipticalPoint.x) / (2.0 * M_PI_F);
        const float migration = fract(angle + in.materialPhase + appearance.radial1.z * 0.1);
        bodyColor = migration < 0.5
            ? mix(appearance.color0.rgb, appearance.color1.rgb, smoothstep(0.0, 0.5, migration))
            : mix(appearance.color1.rgb, appearance.color2.rgb, smoothstep(0.5, 1.0, migration));
        bodyColor *= 0.72 + 0.28 * centerMask + appearance.optical0.x * 0.16;
        haloAlpha = haloCoverage * actorOpacity * appearance.optical0.y * 0.42;
        haloColor = appearance.color2.rgb;
        break;
    }
    default: { // Satin
        const float broadHighlight = softenedLight;
        bodyColor *= 0.68 + lightResponse * 0.42 * broadHighlight
            + appearance.optical0.x * 0.10 * centerMask;
        break;
    }
    }

    // Center opacity is independent from overall body opacity: daily presets
    // can produce hollow, translucent-core, and solid variants without
    // changing the silhouette or the actor's entrance/exit envelope.
    bodyAlpha *= mix(
        1.0,
        clamp(appearance.optical0.w, 0.0, 1.0),
        centerMask
    );

    const float visibleHaloAlpha = haloAlpha * (1.0 - bodyAlpha)
        * (1.0 - visibleTrailAlpha) * (1.0 - visibleMergeAlpha);
    const float alpha = clamp(
        bodyAlpha + visibleTrailAlpha + visibleMergeAlpha + visibleHaloAlpha,
        0.0,
        1.0
    );
    float3 premultiplied = bodyColor * bodyAlpha
        + trailColor * visibleTrailAlpha
        + bodyColor * visibleMergeAlpha
        + haloColor * visibleHaloAlpha;
    premultiplied = min(max(premultiplied, 0.0), alpha);
    return float4(premultiplied, alpha);
}
