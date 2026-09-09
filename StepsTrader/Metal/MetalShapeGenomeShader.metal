#include <metal_stdlib>
using namespace metal;

struct MetalShapeGenomeUniforms {
    float4 superformula;
    float4 harmonic0;
    float4 harmonic1;
    float4 harmonic2;
    float4 anisotropyOffset;
    float4 transform;
    uint4 metadata;
    float4 reserved;
};

struct MetalShapeMaterialUniforms {
    float4 color0;
    float4 color1;
    float4 color2;
    float4 params0;
    float4 params1;
    float4 params2;
    float4 params3;
    uint4 metadata;
};

struct MetalShapeVertexOut {
    float4 position [[position]];
    float2 uv;
};

vertex MetalShapeVertexOut metalShapeGenomeVertex(uint vertexID [[vertex_id]]) {
    const float2 positions[3] = { float2(-1, -1), float2(3, -1), float2(-1, 3) };
    MetalShapeVertexOut out;
    const float2 position = positions[vertexID];
    out.position = float4(position, 0, 1);
    out.uv = float2((position.x + 1) * 0.5, 1 - (position.y + 1) * 0.5);
    return out;
}

static float metalShapeHarmonic(float theta, float4 harmonic) {
    if (harmonic.w < 0.5) return 0;
    return harmonic.y * cos(harmonic.x * theta + harmonic.z);
}

static float metalShapeGenomeRadius(float theta, constant MetalShapeGenomeUniforms &g) {
    const float m = clamp(g.superformula.x, 2.0, 12.0);
    const float n1 = clamp(g.superformula.y, 0.2, 8.0);
    const float n2 = clamp(g.superformula.z, 0.2, 8.0);
    const float n3 = clamp(g.superformula.w, 0.2, 8.0);
    const float a = pow(max(abs(cos(m * theta * 0.25)), 1e-5), n2);
    const float b = pow(max(abs(sin(m * theta * 0.25)), 1e-5), n3);
    const float base = pow(max(a + b, 1e-5), -1.0 / n1);
    const float modulation = 1.0
        + metalShapeHarmonic(theta, g.harmonic0)
        + metalShapeHarmonic(theta, g.harmonic1)
        + metalShapeHarmonic(theta, g.harmonic2);
    return clamp(base * modulation * g.transform.y, 0.72, 1.0);
}

static float metalShapeHash(uint seed, uint petal, uint channel) {
    uint value = seed ^ (petal * 0x9E3779B9u) ^ (channel * 0x85EBCA6Bu);
    value ^= value >> 16;
    value *= 0x7FEB352Du;
    value ^= value >> 15;
    value *= 0x846CA68Bu;
    value ^= value >> 16;
    return float(value & 0x00FFFFFFu) / float(0x01000000u);
}

static float metalShapeSnowflakeRadius(float theta, constant MetalShapeGenomeUniforms &g) {
    const float halfSector = M_PI_F / float(clamp(g.metadata.z, 3u, 12u));
    float local = fmod(theta, 2.0 * halfSector);
    if (local < 0.0) local += 2.0 * halfSector;
    const float folded = local > halfSector ? 2.0 * halfSector - local : local;
    const float unit = folded / halfSector;
    const float u = unit * M_PI_F;
    const uint count = min(g.metadata.w, 5u);
    float radius = 1.0;
    if (count > 0u) radius += g.harmonic0.y * cos(u * g.harmonic0.x);
    if (count > 1u) radius += g.harmonic0.w * cos(u * g.harmonic0.z);
    if (count > 2u) radius += g.harmonic1.y * cos(u * g.harmonic1.x);
    if (count > 3u) radius += g.harmonic1.w * cos(u * g.harmonic1.z);
    if (count > 4u) radius += g.harmonic2.y * cos(u * g.harmonic2.x);
    if (g.harmonic2.z > 0.0) {
        const float spike = max(0.0, 1.0 - abs(unit) / max(g.harmonic2.w, 1e-4));
        radius += g.harmonic2.z * spike * spike;
    }
    if (g.transform.z > 0.0) {
        const float distance = (unit - g.transform.w) / 0.12;
        radius -= g.transform.z * exp(-(distance * distance));
    }
    return max(radius, 0.12) * g.transform.y;
}

static float metalShapeWindflowerRadius(float theta, constant MetalShapeGenomeUniforms &g) {
    const uint petals = clamp(g.metadata.z, 3u, 7u);
    const float sector = 2.0 * M_PI_F / float(petals);
    const float shifted = (theta + sector * 0.5) / sector;
    const int rawCell = int(floor(shifted));
    const uint petal = uint((rawCell % int(petals) + int(petals)) % int(petals));
    const float local = fract(shifted) * sector - sector * 0.5;
    const float irregularity = g.superformula.z;
    const float skew = (metalShapeHash(g.metadata.y, petal, 0u) - 0.5) * sector * irregularity * 0.55;
    const float span = local < skew ? skew + sector * 0.5 : sector * 0.5 - skew;
    const float distance = min(abs(local - skew) / max(span, 1e-5), 1.0);
    const float exponent = g.superformula.w * (0.88 + 0.24 * metalShapeHash(g.metadata.y, petal, 1u));
    const float tip = 1.0 - irregularity * (0.05 + 0.42 * metalShapeHash(g.metadata.y, petal, 2u));
    const float valley = g.superformula.y * (0.94 + 0.12 * metalShapeHash(g.metadata.y, petal, 3u));
    return valley + (tip - valley) * (1.0 - pow(distance, exponent));
}

static float metalShapeConcaveSquareRadius(float theta, constant MetalShapeGenomeUniforms &g) {
    const float valley = clamp(g.transform.z, 0.62, 0.72);
    const float exponent = clamp(g.transform.w, 2.4, 4.0);
    const float corner = abs(cos(2.0 * (theta - M_PI_F * 0.25)));
    return valley + (1.0 - valley) * pow(corner, exponent);
}

static float metalShapeSoftCloverRadius(float theta, constant MetalShapeGenomeUniforms &g) {
    const float valley = clamp(g.transform.z, 0.46, 0.58);
    const float exponent = clamp(g.transform.w, 0.54, 0.74);
    const float lobe = abs(cos(2.0 * (theta - M_PI_F * 0.25)));
    return valley + (1.0 - valley) * pow(lobe, exponent);
}

static float metalShapeRegularPolygonDistance(float2 p, float sides) {
    const float sector = 2.0 * M_PI_F / sides;
    const float angle = atan2(p.y, p.x);
    const float folded = angle - sector * floor((angle + sector * 0.5) / sector);
    const float boundary = cos(M_PI_F / sides) / max(cos(folded), 1e-4);
    return length(p) - boundary;
}

static float metalShapeLegacyDistance(float2 p, uint shape, uint variant) {
    if (shape == 6u) {
        const float exponent = 2.3 + 1.2 * floor(float(max(variant, 1u) - 1u) / 16.0);
        return pow(pow(abs(p.x), exponent) + pow(abs(p.y), exponent), 1.0 / exponent) - 1.0;
    }
    if (shape == 5u) {
        const float sides = 3.0 + float((max(variant, 1u) - 1u) % 4u);
        const float polygon = metalShapeRegularPolygonDistance(p, sides);
        return mix(polygon, length(p) - 0.94, 0.12);
    }
    if (shape == 4u) {
        const uint value = max(variant, 1u) - 1u;
        const float rays = 3.0 + float(value % 4u);
        const float depth = float((value / 4u) % 4u) / 3.0;
        const float boundary = (1.0 + (0.12 + 0.105 * depth) * cos(rays * atan2(p.y, p.x)))
            / (1.0 + 0.12 + 0.105 * depth);
        return length(p) - boundary;
    }
    return length(p) - 1.0;
}

static float metalShapeDistance(float2 point, constant MetalShapeGenomeUniforms &g) {
    float2 p = point - g.anisotropyOffset.zw;
    const float angle = -g.transform.x;
    const float c = cos(angle), s = sin(angle);
    p = float2(p.x * c - p.y * s, p.x * s + p.y * c);
    p /= clamp(g.anisotropyOffset.xy, float2(0.82), float2(1.18));
    if (g.metadata.x == 1u) return metalShapeLegacyDistance(p, g.metadata.y, g.metadata.z);
    const float theta = atan2(p.y, p.x);
    if (g.metadata.x == 2u) return length(p) - metalShapeSnowflakeRadius(theta, g);
    if (g.metadata.x == 3u) return length(p) - metalShapeWindflowerRadius(theta, g);
    if (g.metadata.x == 4u) return length(p) - metalShapeConcaveSquareRadius(theta, g);
    if (g.metadata.x == 5u) return length(p) - metalShapeSoftCloverRadius(theta, g);
    return length(p) - metalShapeGenomeRadius(theta, g);
}

static float metalShapeSoftCoverage(
    float2 p,
    constant MetalShapeGenomeUniforms &g,
    float softness
) {
    const float distance = metalShapeDistance(p, g);
    const float edge = max(max(fwidth(distance), 0.0025), softness);
    return smoothstep(edge, -edge, distance);
}

static float3 metalShapePalette(float t, constant MetalShapeMaterialUniforms &m) {
    const float first = smoothstep(0.05, 0.52, t);
    const float second = smoothstep(0.46, 0.96, t);
    return mix(mix(m.color0.rgb, m.color1.rgb, first), m.color2.rgb, second);
}

static float4 metalShapeGenomeShade(
    MetalShapeVertexOut in,
    constant MetalShapeGenomeUniforms &g,
    constant MetalShapeMaterialUniforms &m) {
    const float2 p = (in.uv - 0.5) * 2.72;
    const float distance = metalShapeDistance(p, g);
    const float antialias = max(fwidth(distance), 0.0025);
    const float body = smoothstep(antialias, -antialias, distance);
    const float2 direction = normalize(m.params1.xy);
    const float materialPhase = m.params0.x * 2.0 * M_PI_F;
    const uint material = min(m.metadata.x, 10u);
    float3 color = m.color0.rgb;
    float alpha = body;

    if (material == 1u) {
        const float light = smoothstep(-1.05, 0.88, dot(p, direction) + 0.22 * sin(p.y * 1.8 + materialPhase));
        color = mix(m.color0.rgb, m.color1.rgb, light);
    } else if (material == 2u) {
        const float line = 1.0 - smoothstep(0.018, 0.045, abs(distance));
        alpha = line;
        color = mix(m.color0.rgb, m.color1.rgb, 0.58);
    } else if (material == 3u) {
        const float2 blurPoint = p * 1.42;
        const float axis = dot(blurPoint, direction);
        // A continuous increase in edge softness, with no seam between body and blur.
        const float progression = smoothstep(-0.65, 0.95, axis);
        const float extent = m.metadata.y == 1u ? 0.42 : (m.metadata.y == 3u ? 0.70 : 0.56);
        const float spread = mix(0.0025, extent, progression * progression);
        const float shiftedDistance = metalShapeDistance(blurPoint - direction * progression * 0.10, g);
        const float sigma = max(antialias, spread);
        alpha = 1.0 / (1.0 + exp(clamp(1.7 * shiftedDistance / sigma, -30.0, 30.0)));
        alpha *= 1.0 - smoothstep(1.38, 1.90, length(blurPoint));
        if (g.metadata.x == 1u && g.metadata.y == 6u && g.metadata.z == 17u) {
            // Only a narrow leading rim stays crisp; softness grows immediately behind it.
            const float early = smoothstep(-0.98, 0.10, axis);
            const float edgeSoftness = 0.0025 + 0.82 * pow(early, 1.1);
            const float edgeDistance = metalShapeDistance(blurPoint - direction * early * 0.15, g);
            alpha = 1.0 / (1.0 + exp(clamp(1.7 * edgeDistance / max(antialias, edgeSoftness), -30.0, 30.0)));
            alpha *= 1.0 - smoothstep(-0.88, 1.30, axis);
            alpha *= 1.0 - smoothstep(1.40, 1.91, length(blurPoint));
        }
        if (g.metadata.x == 1u && g.metadata.y == 5u && g.metadata.z == 5u) {
            // Keep only the leading tip: the rest opens into a diffuse light beam.
            const float travel = axis + 0.86;
            const float crossAxis = dot(blurPoint, float2(-direction.y, direction.x));
            const float diffusion = smoothstep(0.0, 1.75, travel);
            const float beamSigma = 0.004 + 0.60 * pow(diffusion, 1.15);
            const float sideDistance = abs(crossAxis) - max(travel, 0.0) * 0.44;
            const float sides = 1.0 / (1.0 + exp(clamp(1.7 * sideDistance / beamSigma, -30.0, 30.0)));
            alpha = sides * smoothstep(-0.015, 0.035, travel)
                * (1.0 - smoothstep(0.16, 2.58, travel))
                * (1.0 - smoothstep(1.45, 1.91, length(blurPoint)));
        }
        color = m.metadata.y == 2u ? mix(m.color0.rgb, m.color1.rgb, progression) : m.color0.rgb;
    } else if (material == 4u || material == 5u) {
        const float2 focus = (m.params2.xy - 0.5) * 0.68;
        const float radial = clamp(length(p - focus) / 1.28, 0.0, 1.0);
        color = material == 4u
            ? mix(m.color1.rgb, m.color0.rgb, smoothstep(0.08, 0.96, radial))
            : metalShapePalette(radial, m);
    } else if (material == 6u) {
        const float2 first = (m.params2.xy - 0.5) * 0.9;
        const float2 second = (m.params2.zw - 0.5) * 0.9;
        const float glow = exp(-dot(p - first, p - first) * 2.4)
            + 0.72 * exp(-dot(p - second, p - second) * 3.2);
        color = metalShapePalette(clamp(glow, 0.0, 1.0), m);
    } else if (material == 7u) {
        const float warped = dot(p, direction) * 5.4
            + sin(dot(p, float2(-direction.y, direction.x)) * 3.1 + materialPhase) * 1.25;
        alpha = body;
        color = metalShapePalette(0.5 + 0.5 * sin(warped * 0.54 + 1.1), m);
    } else if (material == 8u) {
        const float bands = abs(sin(distance * (48.0 + m.params2.x * 28.0) + materialPhase));
        const float boundaryLine = 1.0 - smoothstep(0.016, 0.042, abs(distance));
        const float interiorLines = body * (1.0 - smoothstep(0.07, 0.21, bands));
        alpha = max(boundaryLine, interiorLines * 0.74);
        color = mix(m.color0.rgb, m.color1.rgb, interiorLines);
    } else if (material == 9u) {
        const float outside = max(distance, 0.0);
        const float edge = exp(-distance * distance * 2100.0);
        const float halo = exp(-outside * outside * 58.0) * smoothstep(0.30, 0.0, outside);
        alpha = max(edge, halo * 0.72) * smoothstep(-0.10, -0.015, distance);
        color = mix(m.color1.rgb, m.color0.rgb, smoothstep(0.0, 0.28, outside));
    }

    if (material == 10u) {
        const float2 sun = p * 1.48;
        const float edgeDistance = length(sun) - 0.88;
        const float lower = smoothstep(-0.20, 0.90, sun.y);
        const float softness = mix(0.018, 0.19, lower);
        const float disk = 1.0 / (1.0 + exp(clamp(edgeDistance / softness, -30.0, 30.0)));
        const float fade = 1.0 - smoothstep(0.0, 1.0, sun.y);
        const float halo = exp(-max(edgeDistance, 0.0) * 7.0)
            * (1.0 - smoothstep(-0.35, 0.55, sun.y)) * 0.30;
        alpha = max(disk * fade, halo) * (1.0 - smoothstep(1.35, 1.90, length(sun)));
        const float warmth = smoothstep(-0.88, 0.25, sun.y + (m.params0.x - 0.5) * 0.12);
        color = mix(float3(1.0, 0.64, 0.008), float3(1.0, 0.025, 0.035), warmth);
    }
    return float4(color * alpha, alpha);
}

fragment float4 metalShapeGenomeFragment(MetalShapeVertexOut in [[stage_in]], constant MetalShapeGenomeUniforms &g [[buffer(0)]], constant MetalShapeMaterialUniforms &m [[buffer(1)]]) {
    return metalShapeGenomeShade(in, g, m);
}

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
