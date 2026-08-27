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
    float4 radial2;
    float4 field;
    float4 optical0;
    float4 optical1;
    float4 light;
    uint4 metadata;
};

static_assert(alignof(DayObjectGPUAppearance) == 16, "GPU appearances require 16-byte alignment");
static_assert(sizeof(DayObjectGPUAppearance) == 176, "GPU appearances must match Swift's 176-byte stride");

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

static float dayObjectsRadialLayerWeight(
    float2 point,
    float4 layer,
    float phase,
    float2 phaseDirection
) {
    const float2 animatedFocus = layer.xy
        + phaseDirection * (0.018 * sin(phase));
    const float distanceFromFocus = length(point - animatedFocus);
    const float softness = max(layer.w, 0.02);
    return 1.0 - smoothstep(
        max(layer.z - softness, 0.0),
        layer.z + softness,
        distanceFromFocus
    );
}

/// One daily optical DNA, expressed through two or three smoothly overlapping
/// radial fields. Color is Cartesian and continuous: phase can never flip the
/// palette direction or introduce a conic seam.
static float3 dayObjectsLayeredRadialColor(
    DayObjectsActorVertexOut in,
    DayObjectGPUAppearance appearance,
    float2 bodyPoint,
    float aspect
) {
    const float phase = in.materialPhase * 2.0 * M_PI_F;
    const float distortion = clamp(appearance.field.x, 0.0, 0.18);
    const float frequency = clamp(appearance.field.y, 0.8, 4.0);
    const float fieldPhase = appearance.field.z + phase;
    const float localSoftness = clamp(
        in.localDepthSoftness + appearance.optical1.w,
        0.0,
        1.0
    );
    const uint colorCount = clamp(appearance.metadata.y, 1u, 3u);
    const uint layerCount = clamp(appearance.metadata.z, 1u, 3u);

    float2 point = float2(bodyPoint.x, bodyPoint.y / max(aspect, 1e-4));
    const float deformationScale = distortion * mix(0.16, 0.035, localSoftness);
    point += float2(
        sin(point.y * frequency + fieldPhase),
        cos(point.x * frequency - fieldPhase)
    ) * deformationScale;
    const float2 phaseDirection = float2(cos(fieldPhase), sin(fieldPhase));
    const float w0 = dayObjectsRadialLayerWeight(
        point, appearance.radial0, phase, phaseDirection
    ) * clamp(appearance.light.y, 0.0, 1.0);
    const float w1 = layerCount >= 2u
        ? dayObjectsRadialLayerWeight(point, appearance.radial1, phase, -phaseDirection)
            * clamp(appearance.light.z, 0.0, 1.0)
        : 0.0;
    const float2 thirdDirection = float2(-phaseDirection.y, phaseDirection.x);
    const float w2 = layerCount >= 3u
        ? dayObjectsRadialLayerWeight(point, appearance.radial2, phase, thirdDirection)
            * clamp(appearance.light.w, 0.0, 1.0)
        : 0.0;

    const float3 color0 = max(appearance.color0.rgb, 0.0);
    const float3 color1 = max(appearance.color1.rgb, 0.0);
    const float3 color2 = max(appearance.color2.rgb, 0.0);
    if (colorCount <= 1) {
        const float luminanceShape = clamp(0.62 + 0.34 * w0 + 0.18 * w1, 0.0, 1.2);
        return color0 * luminanceShape;
    }
    const float baseWeight = 0.10 + 0.18 * (1.0 - max(w0, max(w1, w2)));
    float3 result;
    float3 paletteMean;
    if (colorCount == 2) {
        const float total = max(baseWeight + w0 + w1, 1e-5);
        result = (color0 * (baseWeight + w0) + color1 * w1) / total;
        paletteMean = (color0 + color1) * 0.5;
    } else {
        const float total = max(baseWeight + w0 + w1 + w2, 1e-5);
        result = (
            color0 * (baseWeight + w0) + color1 * w1 + color2 * w2
        ) / total;
        paletteMean = (color0 + color1 + color2) / 3.0;
    }
    return mix(result, paletteMean, localSoftness * 0.42);
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

    float3 bodyColor = dayObjectsLayeredRadialColor(in, appearance, bodyPoint, aspect);
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
    const uint material = min(appearance.metadata.x, 4u);
    float haloAlpha = 0.0;
    float3 haloColor = appearance.color1.rgb;

    switch (material) {
    case 1u: { // Living Glass
        const float refraction = clamp(appearance.optical1.y, 0.0, 0.08);
        const float angle = appearance.optical1.z;
        const float2 refractionDirection = normalize(
            sphereNormal + float2(cos(angle), sin(angle)) * 0.35 + float2(1e-5, 0.0)
        );
        const float3 refracted = backgroundTexture.sample(
            linearSampler,
            clamp(in.screenUV + refractionDirection * refraction, 0.0, 1.0)
        ).rgb;
        const float3 tint = mix(bodyColor, appearance.color1.rgb, 0.24);
        bodyColor = mix(refracted, tint, 0.22 + 0.20 * centerMask)
            + appearance.color2.rgb * rimMask * 0.18;
        bodyAlpha = bodyCoverage * actorOpacity
            * clamp(materialBodyOpacity + rimMask * appearance.optical1.x * 0.22, 0.0, 1.0);
        haloAlpha = haloCoverage * actorOpacity * appearance.optical0.y * 0.25;
        haloColor = appearance.color2.rgb;
        break;
    }
    case 2u: { // Inner Light
        const float glow = clamp(appearance.optical0.x, 0.0, 1.0);
        bodyColor *= 0.58 + glow * 0.82 * centerMask + 0.14 * softenedLight;
        bodyAlpha *= mix(0.78, 1.0, centerMask);
        haloAlpha = haloCoverage * actorOpacity * appearance.optical0.y * 0.38;
        break;
    }
    case 3u: { // Atmospheric Orb
        const float haze = clamp(combinedLocalSoftness + 0.18, 0.0, 1.0);
        bodyColor *= 0.64 + 0.22 * centerMask + 0.12 * softenedLight;
        bodyColor = mix(bodyColor, appearance.color1.rgb, haze * 0.12);
        haloAlpha = haloCoverage * actorOpacity
            * clamp(appearance.optical0.y + haze * 0.18, 0.0, 1.0) * 0.62;
        haloColor = mix(appearance.color1.rgb, appearance.color2.rgb, 0.5);
        break;
    }
    case 4u: { // Layered Membrane
        const uint layerCount = clamp(appearance.metadata.z, 2u, 3u);
        const float phase = in.materialPhase * 2.0 * M_PI_F;
        const float2 direction = float2(cos(phase), sin(phase));
        const float2 point = float2(bodyPoint.x, bodyPoint.y / max(aspect, 1e-4));
        const float a0 = dayObjectsRadialLayerWeight(
            point, appearance.radial0, phase, direction
        ) * bodyCoverage * actorOpacity * appearance.light.y * 0.58;
        const float a1 = dayObjectsRadialLayerWeight(
            point, appearance.radial1, phase, -direction
        ) * bodyCoverage * actorOpacity * appearance.light.z * 0.52;
        const float a2 = layerCount == 3u
            ? dayObjectsRadialLayerWeight(
                point, appearance.radial2, phase,
                float2(-direction.y, direction.x)
            ) * bodyCoverage * actorOpacity * appearance.light.w * 0.46
            : 0.0;
        const float composite = 1.0 - (1.0 - a0) * (1.0 - a1) * (1.0 - a2);
        bodyAlpha = max(bodyAlpha * 0.34, composite * materialBodyOpacity);
        haloAlpha = haloCoverage * actorOpacity * appearance.optical0.y * 0.30;
        break;
    }
    default: { // Soft Volume
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
