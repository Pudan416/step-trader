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
    uint silhouetteVariant;
    float paletteMorph;
    float presentationSaturation;
    float removalEmphasis;
    float presentationPadding;
};

static_assert(alignof(DayObjectGPUActor) == 16, "GPU actors require 16-byte alignment");
static_assert(sizeof(DayObjectGPUActor) == 80, "GPU actors must match Swift's 80-byte stride");

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
    float4 recipe0;
    float4 recipe1;
    uint4 metadata;
};

static_assert(alignof(DayObjectGPUAppearance) == 16, "GPU appearances require 16-byte alignment");
static_assert(sizeof(DayObjectGPUAppearance) == 208, "GPU appearances must match Swift's 208-byte stride");

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
    float paletteMorph;
    float presentationSaturation;
    float removalEmphasis;
    uint shape [[flat]];
    uint silhouetteVariant [[flat]];
    uint appearanceIndex [[flat]];
};

constant float dayObjectsSoftBlobRadialReach = 1.06;
constant float dayObjectsSoftStarRadialReach = 1.12;
constant float dayObjectsTrailSigmaFactor = 0.36;
constant float dayObjectsTrailSigmaSupport = 3.2;

vertex DayObjectsActorVertexOut dayObjectsActorVertex(
    const device float2 *quadPositions [[buffer(0)]],
    const device DayObjectGPUActor *actors [[buffer(1)]],
    const device DayObjectGPUAppearance *appearances [[buffer(2)]],
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
    const float radialReach = actor.silhouetteVariant > 0 ? 1.25 : actor.shape == 4
        ? dayObjectsSoftStarRadialReach
        : (actor.shape == 3 ? dayObjectsSoftBlobRadialReach : 1.0);
    const DayObjectGPUAppearance appearance = appearances[actor.appearanceIndex];
    const bool fragmentBlur = (appearance.metadata.x == 0u || appearance.metadata.x == 3u)
        && uint(round(appearance.recipe1.x)) == 4u;
    // Include all taps and their soft support, only for the blurred material.
    const float blurReach = fragmentBlur
        ? halfSize.x * 2.1 : 0.0;
    const float bodyMajorReach = halfSize.x * radialReach + mergeReach + blurReach;
    const float bodyMinorReach = (actor.paletteMorph < 1.0
        ? max(halfSize.y * radialReach, halfSize.x)
        : halfSize.y * radialReach) + mergeReach + blurReach;
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
    out.paletteMorph = clamp(actor.paletteMorph, 0.0, 1.0);
    out.presentationSaturation = clamp(actor.presentationSaturation, 0.0, 1.0);
    out.removalEmphasis = clamp(actor.removalEmphasis, 0.0, 1.0);
    out.shape = actor.shape;
    out.silhouetteVariant = actor.silhouetteVariant;
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

static float dayObjectsSoftColorFieldWeight(
    float2 point,
    float4 layer,
    float phase,
    float2 phaseDirection
) {
    const float2 animatedFocus = layer.xy
        + phaseDirection * (0.012 * sin(phase));
    const float normalizedDistance = length(point - animatedFocus)
        / max(layer.z, 1e-4);
    const float softness = clamp(layer.w, 0.02, 1.0);
    const float falloff = mix(3.2, 0.72, softness);
    return exp(-normalizedDistance * normalizedDistance * falloff);
}

/// Wide, overlapping radial fields. Every field is smooth over its full
/// support, so no ordered stop, angular split, or pasted-on colour patch can
/// appear inside the circular body.
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
    const float3 color0 = max(appearance.color0.rgb, 0.0);
    const float3 color1 = max(appearance.color1.rgb, 0.0);
    const float3 color2 = max(appearance.color2.rgb, 0.0);
    float3 result = color0;
    if (colorCount <= 1) {
        result = color0;
    } else {
        const float primaryField = dayObjectsSoftColorFieldWeight(
            point,
            appearance.radial0,
            phase,
            phaseDirection
        ) * clamp(appearance.light.y, 0.0, 1.0);
        const float broadPrimaryCoherence = smoothstep(
            0.76,
            0.82,
            appearance.radial0.w
        ) * smoothstep(0.95, 1.15, appearance.radial0.z);
        // Wide fields still need enough chromatic travel to read as a
        // gradient after depth blur and grain. A gentle power curve increases
        // separation without adding an edge or a local hotspot; every
        // transition remains continuous and the foci stay outside the carrier
        // core.
        const float broadPrimaryWeight = 0.012
            + 1.20 * pow(primaryField, 1.5);
        const float w0 = mix(
            0.72 + 0.38 * primaryField,
            broadPrimaryWeight,
            broadPrimaryCoherence
        );
        const float secondaryField = dayObjectsSoftColorFieldWeight(
            point,
            appearance.radial1,
            phase,
            -phaseDirection
        ) * clamp(appearance.light.z, 0.0, 1.0);
        const float broadSecondaryCoherence = smoothstep(
            0.76,
            0.82,
            appearance.radial1.w
        ) * smoothstep(0.95, 1.15, appearance.radial1.z);
        const float broadSecondaryWeight = 0.012
            + 1.20 * pow(secondaryField, 1.5);
        const float w1 = mix(
            0.10 + 0.58 * secondaryField,
            broadSecondaryWeight,
            broadSecondaryCoherence
        );
        float totalWeight = w0 + w1;
        result = color0 * w0 + color1 * w1;
        if (colorCount >= 3u) {
            const float2 thirdDirection = float2(-phaseDirection.y, phaseDirection.x);
            const float tertiaryField = dayObjectsSoftColorFieldWeight(
                point,
                appearance.radial2,
                phase,
                thirdDirection
            ) * clamp(appearance.light.w, 0.0, 1.0);
            const float broadTertiaryCoherence = smoothstep(
                0.76,
                0.82,
                appearance.radial2.w
            ) * smoothstep(0.95, 1.15, appearance.radial2.z);
            const float broadTertiaryWeight = 0.012
                + 1.20 * pow(tertiaryField, 1.5);
            const float w2 = mix(
                0.08 + 0.50 * tertiaryField,
                broadTertiaryWeight,
                broadTertiaryCoherence
            );
            result += color2 * w2;
            totalWeight += w2;
        }
        result /= max(totalWeight, 1e-4);
    }

    const float w1 = layerCount >= 2u
        ? dayObjectsRadialLayerWeight(point, appearance.radial1, phase, -phaseDirection)
            * clamp(appearance.light.z, 0.0, 1.0)
        : 0.0;
    const float2 thirdDirection = float2(-phaseDirection.y, phaseDirection.x);
    const float w2 = layerCount >= 3u
        ? dayObjectsRadialLayerWeight(point, appearance.radial2, phase, thirdDirection)
            * clamp(appearance.light.w, 0.0, 1.0)
        : 0.0;
    const float lightResponse = clamp(appearance.light.x, 0.0, 1.0);
    const float layeredLight = 0.94 + lightResponse * (0.035 * w1 + 0.025 * w2);
    return mix(result * layeredLight, result, localSoftness * 0.24);
}

// Broad, static patterns remain readable without animation or fine texture.
// Returns straight colour; alpha is used only by the translucent-sheet pattern.
static float4 dayObjectsArtisticFill(float2 point, DayObjectGPUAppearance appearance) {
    const uint pattern = uint(round(appearance.recipe1.x));
    const float angle = appearance.recipe1.y;
    const float2 q = float2(cos(angle) * point.x - sin(angle) * point.y,
        sin(angle) * point.x + cos(angle) * point.y);
    const float bend = appearance.recipe1.z;
    const float offset = (appearance.recipe1.w - 0.5) * 0.65;
    const float3 a = appearance.color0.rgb;
    const float3 b = appearance.color1.rgb;
    const float3 c = appearance.color2.rgb;
    if (pattern == 5u) {
        // Experimental radial volume: a movable light centre, with two or
        // three colour stops. The circular boundary stays dark when offset.
        const float2 centre = float2(cos(angle), -sin(angle))
            * clamp(appearance.recipe1.w, 0.0, 0.65);
        const float2 delta = point - centre;
        const float radius = length(delta);
        const float2 ray = delta / max(radius, 1e-5);
        const float projection = dot(centre, ray);
        const float boundary = -projection
            + sqrt(max(0.001, projection * projection + 1.0 - dot(centre, centre)));
        const float t = clamp(radius / max(boundary, 0.1), 0.0, 1.0);
        if (appearance.recipe1.z < 0.5)
            return float4(mix(a, c, smoothstep(0.08, 1.0, t)), 1.0);
        const float3 inner = mix(a, b, smoothstep(0.12, 0.68, t));
        return float4(mix(inner, c, smoothstep(0.52, 1.0, t)), 1.0);
    }
    if (pattern == 1u) {
        const float sweep = smoothstep(-0.75 + offset, 0.85 + offset, q.x);
        const float3 base = mix(a, b, sweep);
        return float4(mix(base, c, 0.13 * (1.0 - q.y * q.y)), 1.0);
    }
    if (pattern == 4u) {
        // A broad colour field keeps the defocused volume saturated.
        const float3 base = mix(a, b, smoothstep(-0.65 + offset, 0.15 + offset, q.x));
        return float4(mix(base, c, smoothstep(0.15 + offset, 0.95 + offset, q.x)), 1.0);
    }
    if (pattern == 2u) {
        const float center = offset + (0.22 + bend * 0.32) * sin(q.y * 2.25);
        const float ribbon = 1.0 - smoothstep(0.18 + bend * 0.08,
            0.48 + bend * 0.08, abs(q.x - center));
        const float3 base = mix(a, c, smoothstep(-1.0, 1.0, q.y) * 0.38);
        return float4(mix(base, b, ribbon * 0.94), 1.0);
    }
    const float boundary1 = q.y + 0.27 * sin(q.x * 1.9) - offset;
    const float boundary2 = q.x - 0.34 * sin(q.y * 1.7 + bend) + offset;
    const float layer1 = smoothstep(-0.25, -0.08, boundary1);
    const float layer2 = smoothstep(0.12, 0.29, boundary2);
    float3 color = mix(a, b, layer1 * 0.63);
    color = mix(color, c, layer2 * 0.57);
    const float seams = exp(-pow((boundary1 + 0.165) / 0.028, 2.0))
        + exp(-pow((boundary2 - 0.205) / 0.028, 2.0));
    color = mix(color, mix(b, c, 0.5), min(seams * 0.18, 0.30));
    return float4(color, 0.42 + 0.16 * layer1 + 0.18 * layer2);
}

/// Seven circle-derived bodies in local units. None of the variants can produce
/// the old triangles, slabs, petals, or thin Figma-like particles.
static float dayObjectsActorBody(
    uint shape,
    float2 point,
    float aspect,
    float radialVariation,
    uint silhouetteVariant
) {
    const float2 ellipsePoint = float2(point.x, point.y / max(aspect, 1e-4));
    const float radius = length(ellipsePoint);
    const float angle = atan2(ellipsePoint.y, ellipsePoint.x);
    // Variant zero keeps curated scenes pixel-compatible. A compact descriptor
    // controls broad geometry, independently of animated material phase.
    if (silhouetteVariant > 0) {
        const uint variant = min(silhouetteVariant, 64u) - 1u;
        const float lobes = 3.0 + float(variant % 4u);
        const float depth = float((variant / 4u) % 4u) / 3.0;
        if (shape == 4u) {
            const float amplitude = mix(0.12, 0.225, depth);
            return radius - (1.0 + amplitude * cos(lobes * angle));
        }
        if (shape == 5u) {
            const float sector = 2.0 * M_PI_F / lobes;
            const float folded = angle - sector * floor((angle + sector * 0.5) / sector);
            // Distance to the nearest side segment, rounded by an actual
            // circular offset. This avoids cusps from blending radial masks.
            const float rounding = mix(0.30, 0.12, depth);
            const float coreRadius = 1.0 - rounding;
            const float apothem = coreRadius * cos(M_PI_F / lobes);
            const float sideHalfLength = coreRadius * sin(M_PI_F / lobes);
            const float2 foldedPoint = radius * float2(cos(folded), sin(folded));
            const float2 nearest = float2(apothem,
                clamp(foldedPoint.y, -sideHalfLength, sideHalfLength));
            return length(foldedPoint - nearest) * sign(foldedPoint.x - apothem) - rounding;
        }
        if (shape == 6u) {
            const float exponent = 2.3 + 1.2 * float(variant / 16u);
            return pow(pow(abs(ellipsePoint.x), exponent)
                + pow(abs(ellipsePoint.y), exponent), 1.0 / exponent) - 1.0;
        }
    }
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
    case 4: { // continuous soft star
        const float starRadius = 1.0
            + 0.105 * cos(5.0 * angle + radialVariation * 0.8)
            + 0.018 * cos(10.0 * angle - radialVariation * 0.5);
        return radius - starRadius;
    }
    case 5: { // softly rounded polygon
        const float polygonRadius = 1.0
            + 0.052 * cos(6.0 * angle + radialVariation * 0.35);
        return radius - polygonRadius;
    }
    case 6: { // rounded square derived from a superellipse
        const float exponent = 4.2;
        const float superellipseRadius = pow(
            pow(abs(ellipsePoint.x), exponent)
                + pow(abs(ellipsePoint.y), exponent),
            1.0 / exponent
        );
        return superellipseRadius - 1.0;
    }
    default: // sphere
        return radius - 1.0;
    }
}

// Same IEC sRGB transfer as DayObjectRGB.linearComponent. Palette literals
// enter the material path in linear light, like the appearance buffer.
static float3 dayObjectsPresentationLinearRGB(float3 sRGB) {
    return select(pow((sRGB + 0.055) / 1.055, float3(2.4)), sRGB / 12.92, sRGB <= 0.04045);
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
    const float targetBodyDistancePixels = dayObjectsActorBody(
        in.shape,
        bodyPoint,
        aspect,
        in.materialPhase * 2.0 - 1.0,
        in.silhouetteVariant
    ) * majorHalfSize * in.shortSidePixels;
    const float paletteProgress = smoothstep(0.0, 1.0, in.paletteMorph);
    const float sphereRadius = length(bodyPoint);
    const float sphereDistancePixels = (sphereRadius - 1.0)
        * majorHalfSize * in.shortSidePixels;
    // Evaluate coverage on one analytical contour throughout the morph. The
    // production endpoint retains the original distance without interpolation.
    const float signedBodyDistancePixels = in.paletteMorph == 1.0
        ? targetBodyDistancePixels
        : mix(sphereDistancePixels, targetBodyDistancePixels, paletteProgress);

    // Derivatives are evaluated after conversion to screen pixels, so the
    // transition width remains a physical-pixel quantity on every canvas.
    const float recipeEdgePixels = clamp(appearance.recipe0.z, 0.0, 0.42)
        * majorHalfSize * in.shortSidePixels * 0.18;
    const float antialiasPixels = max(
        fwidth(signedBodyDistancePixels),
        0.70 + combinedLocalSoftness * 12.0 + recipeEdgePixels
    );
    float baseBodyCoverage = 1.0 - smoothstep(
        -antialiasPixels,
        antialiasPixels,
        signedBodyDistancePixels
    );
    const uint material = min(appearance.metadata.x, 8u);
    const float localAntialias = antialiasPixels
        / max(majorHalfSize * in.shortSidePixels, 1.0);
    // A directional footprint carries colour away from the focused edge.
    // Coverage and colour use the same samples to avoid a dark fringe.
    const bool fragmentBlur = (material == 0u || material == 3u)
        && uint(round(appearance.recipe1.x)) == 4u;
    float fragmentBlurMask = 0.0;
    float3 fragmentBlurColor = float3(0.0);
    DayObjectGPUAppearance artisticAppearance = appearance;
    if (fragmentBlur) {
        float angle = appearance.recipe1.y;
        // Focus a triangle vertex; other flat-sided shapes focus a face.
        // The focused direction is opposite the direction of defocus.
        // Resolve it in local shape coordinates so actor rotation is preserved.
        if (in.shape == 6u || (in.shape == 5u && in.silhouetteVariant > 0u)) {
            const float sides = in.shape == 6u ? 4.0
                : 3.0 + float((min(in.silhouetteVariant, 64u) - 1u) % 4u);
            const float sector = 2.0 * M_PI_F / sides;
            const float focusOffset = sides == 3.0 ? sector * 0.5 : 0.0;
            const float focusNormal = round((M_PI_F - angle - focusOffset) / sector)
                * sector + focusOffset;
            angle = M_PI_F - focusNormal;
        }
        artisticAppearance.recipe1.y = angle;
        const float2 axis = float2(cos(angle), -sin(angle));
        const float side = dot(bodyPoint, axis);
        const float offset = (appearance.recipe1.w - 0.5) * 0.20;
        const float2 across = float2(-axis.y, axis.x);
        // Anchor the narrow focused rim to this silhouette, not a circle-sized
        // box. Rounded triangles can meet this ray well before radius one.
        float insideRadius = 0.0;
        float outsideRadius = 1.3;
        for (int search = 0; search < 8; ++search) {
            const float radius = (insideRadius + outsideRadius) * 0.5;
            const float2 point = -axis * radius;
            const float target = dayObjectsActorBody(in.shape, point, aspect,
                in.materialPhase * 2.0 - 1.0, in.silhouetteVariant);
            const float distance = mix(radius - 1.0, target, paletteProgress);
            if (distance < 0.0) insideRadius = radius;
            else outsideRadius = radius;
        }
        const float focusedEdge = -(insideRadius + outsideRadius) * 0.5;
        const float fromEdge = side - focusedEdge;
        fragmentBlurMask = smoothstep(0.04, 0.18, fromEdge);
        const float progress = clamp((fromEdge - 0.08) / (1.8 + offset), 0.0, 1.0);
        const float spread = progress * progress;
        const float strength = 0.8 + 0.2 * clamp(appearance.recipe1.z, 0.0, 1.0);
        const float sigmaAlong = 0.035 + 0.62 * spread * strength;
        const float sigmaAcross = 0.025 + 0.40 * spread * strength;
        const float drift = 0.22 * spread;
        const float sampleSoftness = max(antialiasPixels,
            sigmaAlong * majorHalfSize * in.shortSidePixels * 0.60);
        // Normalized convolution preserves the opaque colour volume. Only the
        // real blurred coverage fades at the far edge; no extra opacity ramp.
        float blurredCoverage = 0.0;
        float3 coveredColor = float3(0.0);
        // Half-step Gaussian sampling avoids separate ghost contours from the
        // sparse five-tap grid, especially on the defocused triangle base.
        const float gaussianWeights[5] = { 1.0, 0.8824969, 0.6065307, 0.3246525, 0.1353353 };
        const float gaussianTotal = 4.8980308;
        for (int y = -4; y <= 4; ++y) {
            const float wy = gaussianWeights[abs(y)];
            for (int x = -4; x <= 4; ++x) {
                const float wx = gaussianWeights[abs(x)];
                const float weight = wx * wy / (gaussianTotal * gaussianTotal);
                const float2 samplePoint = bodyPoint - axis * drift
                    + axis * (float(x) * 0.5 * sigmaAlong)
                    + across * (float(y) * 0.5 * sigmaAcross);
                const float targetDistance = dayObjectsActorBody(in.shape, samplePoint,
                    aspect, in.materialPhase * 2.0 - 1.0, in.silhouetteVariant);
                const float distance = mix(length(samplePoint) - 1.0,
                    targetDistance, paletteProgress) * majorHalfSize * in.shortSidePixels;
                const float coverage = 1.0 - smoothstep(-sampleSoftness, sampleSoftness, distance);
                const float2 sampleEllipse = float2(samplePoint.x, samplePoint.y / max(aspect, 1e-4));
                coveredColor += dayObjectsArtisticFill(sampleEllipse, artisticAppearance).rgb * coverage * weight;
                blurredCoverage += coverage * weight;
            }
        }
        fragmentBlurColor = coveredColor / max(blurredCoverage, 1e-5);
        baseBodyCoverage = mix(baseBodyCoverage, blurredCoverage, fragmentBlurMask);
    }
    float bodyCoverage = baseBodyCoverage;
    float structuralCoverage = 0.0;
    float3 structuralColor = appearance.color2.rgb;

    if (material == 7u) { // Outline
        const int outlineCount = clamp(int(round(appearance.recipe1.x)), 1, 3);
        const float outlineWidth = clamp(appearance.recipe1.y, 0.002, 0.020);
        const float outlineAAPixels = max(fwidth(signedBodyDistancePixels), 0.70);
        const float outlineAA = outlineAAPixels / max(majorHalfSize * in.shortSidePixels, 1.0);
        const float outlineSpacing = clamp(appearance.recipe1.z, 0.02, 0.09);
        // Use the same field as the silhouette, including during palette morph.
        // Radial normalization at the centre of a lobed field is singular and
        // would create a false interior ring, so retain its signed local units.
        const float contourDistance = signedBodyDistancePixels
            / max(majorHalfSize * in.shortSidePixels, 1.0);
        float rings = 0.0;
        for (int index = 0; index < 3; ++index) {
            if (index < outlineCount) {
                const float inset = outlineWidth + float(index)
                    * (outlineSpacing + outlineWidth * 1.4);
                const float ringDistance = abs(contourDistance + inset);
                rings = max(
                    rings,
                    1.0 - smoothstep(
                        outlineWidth,
                        outlineWidth + outlineAA,
                        ringDistance
                    )
                );
            }
        }
        bodyCoverage = rings * (1.0 - smoothstep(-outlineAAPixels, outlineAAPixels, signedBodyDistancePixels));
    } else if (material == 8u) { // Counterform
        const float cutoutRadius = clamp(appearance.recipe1.x, 0.44, 0.62);
        const float cutoutSoftness = clamp(appearance.recipe1.y, 0.01, 0.08);
        const float coronaWidth = clamp(appearance.recipe1.z, 0.14, 0.34);
        const float coronaIntensity = clamp(appearance.recipe1.w, 0.58, 0.98);
        const float2 cutoutCenter = appearance.radial2.xy * 0.18;
        const float cutoutDistance = length(ellipticalPoint - cutoutCenter);
        const float cutoutMask = 1.0 - smoothstep(
            cutoutRadius - cutoutSoftness,
            cutoutRadius + cutoutSoftness,
            cutoutDistance
        );
        bodyCoverage = baseBodyCoverage * (1.0 - cutoutMask);
        structuralCoverage = (
            1.0 - smoothstep(
                coronaWidth,
                coronaWidth + cutoutSoftness + localAntialias,
                abs(cutoutDistance - cutoutRadius)
            )
        ) * coronaIntensity * baseBodyCoverage;
        structuralColor = mix(appearance.color1.rgb, appearance.color2.rgb, 0.5);
    }
    const float outsideDistancePixels = max(signedBodyDistancePixels, 0.0);
    const float haloReachPixels = max(majorHalfSize * 0.18 * in.shortSidePixels, 1.0);
    const float haloCoverage = (1.0 - baseBodyCoverage) * (
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
    const float trailCoverage = trailEnabled * behindBody * longitudinal * lateral
        * 0.72;

    const float actorOpacity = clamp(in.opacity, 0.0, 1.0);
    const float materialBodyOpacity = clamp(appearance.optical0.z, 0.0, 1.0);
    const float visibilityGate = smoothstep(0.0, 0.25, actorOpacity);
    const float minimumOpacity = clamp(appearance.recipe0.w, 0.58, 0.92)
        * visibilityGate;
    const float steadyOpacity = max(
        actorOpacity * materialBodyOpacity,
        minimumOpacity
    );
    float bodyAlpha = bodyCoverage * steadyOpacity;
    const float trailAlpha = trailCoverage * actorOpacity * materialBodyOpacity
        * in.trailEnergyNormalization * 0.32;
    const float visibleTrailAlpha = trailAlpha * (1.0 - bodyAlpha);
    const float mergeReachPixels = max(
        majorHalfSize * 0.18 * in.shortSidePixels,
        1.0
    );
    const float mergeCoverage = (1.0 - baseBodyCoverage) * (
        1.0 - smoothstep(0.0, mergeReachPixels, max(signedBodyDistancePixels, 0.0))
    );
    // Do not refill the dissolving side with the silhouette's merge rim.
    const float mergeAlpha = mergeCoverage * actorOpacity * materialBodyOpacity
        * 0.16 * (fragmentBlur ? 1.0 - fragmentBlurMask : 1.0)
        * (material == 7u ? 0.0 : 1.0);
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
    float haloAlpha = 0.0;
    float3 haloColor = appearance.color1.rgb;

    switch (material) {
    case 1u: { // Solid
        bodyColor = appearance.color0.rgb;
        break;
    }
    case 2u: { // Sphere
        bodyColor *= 0.66 + 0.36 * softenedLight + 0.18 * centerMask;
        bodyColor += appearance.color2.rgb * rimMask * appearance.optical1.x * 0.10;
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
        const float3 tint = mix(bodyColor, appearance.color1.rgb, 0.24);
        bodyColor = mix(refracted, tint, 0.62 + 0.18 * centerMask)
            + appearance.color2.rgb * rimMask * 0.14;
        bodyAlpha = bodyCoverage * max(
            actorOpacity * clamp(
                materialBodyOpacity + rimMask * appearance.optical1.x * 0.22,
                0.0,
                1.0
            ),
            minimumOpacity
        );
        haloAlpha = haloCoverage * actorOpacity * appearance.optical0.y * 0.25;
        haloColor = appearance.color2.rgb;
        break;
    }
    case 4u: { // Mist
        const float haze = clamp(combinedLocalSoftness + 0.18, 0.0, 1.0);
        bodyColor *= 0.82;
        bodyColor = mix(bodyColor, appearance.color1.rgb, haze * 0.10);
        haloAlpha = haloCoverage * actorOpacity
            * clamp(appearance.optical0.y + haze * 0.18, 0.0, 1.0) * 0.62;
        haloColor = mix(appearance.color1.rgb, appearance.color2.rgb, 0.5);
        break;
    }
    case 5u: { // Halo
        bodyColor *= 0.72 + 0.24 * centerMask + 0.12 * softenedLight;
        haloAlpha = haloCoverage * visibilityGate
            * clamp(appearance.optical0.y + 0.22, 0.0, 1.0) * 0.88;
        haloColor = mix(appearance.color0.rgb, appearance.color2.rgb, 0.45);
        break;
    }
    case 6u: { // Luminous
        const float glow = clamp(appearance.optical0.x, 0.0, 1.0);
        bodyColor *= 0.58 + glow * 0.82 * centerMask + 0.14 * softenedLight;
        haloAlpha = haloCoverage * actorOpacity * appearance.optical0.y * 0.38;
        break;
    }
    case 7u: { // Outline
        bodyColor *= 0.78 + 0.22 * softenedLight;
        haloAlpha = 0.0; // Plain outline has no outward glow.
        break;
    }
    case 8u: { // Counterform
        bodyColor *= 0.72 + 0.22 * softenedLight + 0.12 * rimMask;
        haloAlpha = haloCoverage * visibilityGate * appearance.optical0.y * 0.34;
        break;
    }
    default: { // Gradient
        // The overlapping colour fields already provide depth. A directional
        // normal-light pass introduces a straight sector through the centre,
        // which violates the radial-only material contract.
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
    bodyAlpha = max(bodyAlpha, bodyCoverage * minimumOpacity);

    // Only production gradient/glass descriptors opt in. Legacy materials and
    // curated previews keep their existing shading and GPU buffer layout.
    if ((material == 0u || material == 3u) && appearance.recipe1.x >= 1.0) {
        const float4 fill = dayObjectsArtisticFill(ellipticalPoint, artisticAppearance);
        bodyColor = fragmentBlur ? mix(fill.rgb, fragmentBlurColor, fragmentBlurMask) : fill.rgb;
        if (uint(round(appearance.recipe1.x)) == 3u) {
            bodyAlpha = bodyCoverage * actorOpacity * fill.a;
        }
    }

    const float structuralAlpha = structuralCoverage * max(
        actorOpacity,
        minimumOpacity
    );
    const float visibleStructuralAlpha = structuralAlpha * (1.0 - bodyAlpha);

    const float visibleHaloAlpha = haloAlpha * (1.0 - bodyAlpha)
        * (1.0 - visibleTrailAlpha) * (1.0 - visibleMergeAlpha)
        * (1.0 - visibleStructuralAlpha);
    const float alpha = clamp(
        bodyAlpha + visibleTrailAlpha + visibleMergeAlpha
            + visibleStructuralAlpha + visibleHaloAlpha,
        0.0,
        1.0
    );
    float3 premultiplied = bodyColor * bodyAlpha
        + trailColor * visibleTrailAlpha
        + bodyColor * visibleMergeAlpha
        + structuralColor * visibleStructuralAlpha
        + haloColor * visibleHaloAlpha;
    premultiplied = min(max(premultiplied, 0.0), alpha);
    if (in.paletteMorph == 1.0 && in.presentationSaturation == 1.0 && in.removalEmphasis == 0.0) {
        return float4(premultiplied, alpha);
    }

    // Match the native picker: a light translucent surface, independent of
    // the gradient and app theme, with enough luminance for black labels.
    const float shoulder = smoothstep(0.65, 1.0, sphereRadius);
    const float rim = smoothstep(0.965, 0.985, sphereRadius);
    const float neutralAlpha = (0.52 + shoulder * 0.06 + rim * 0.08)
        * baseBodyCoverage * actorOpacity;
    const float3 neutralColor = float3(0.96);
    const float presentedAlpha = mix(neutralAlpha, alpha, paletteProgress);
    float3 presentedRGB = mix(neutralColor * neutralAlpha, premultiplied, paletteProgress);
    float3 straightRGB = presentedAlpha > 1e-6 ? presentedRGB / presentedAlpha : float3(0.0);
    const float luminance = dot(straightRGB, float3(0.2126, 0.7152, 0.0722));
    straightRGB = mix(float3(luminance), straightRGB, in.presentationSaturation);

    // A narrow band wholly inside the current contour. Neither the core nor
    // the exterior halo/trail gains colour or coverage during removal.
    const float innerDistance = -signedBodyDistancePixels
        / max(majorHalfSize * in.shortSidePixels, 1.0);
    const float innerRim = smoothstep(0.0, 0.025, innerDistance)
        * (1.0 - smoothstep(0.08, 0.13, innerDistance));
    const float3 removalColor = dayObjectsPresentationLinearRGB(float3(255.0, 155.0, 122.0) / 255.0);
    straightRGB = mix(straightRGB, removalColor, innerRim * in.removalEmphasis);
    presentedRGB = clamp(straightRGB, 0.0, 1.0) * presentedAlpha;
    return float4(presentedRGB, presentedAlpha);
}
