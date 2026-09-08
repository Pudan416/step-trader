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

fragment float4 metalShapeGenomeFragment(
    MetalShapeVertexOut in [[stage_in]],
    constant MetalShapeGenomeUniforms &g [[buffer(0)]],
    constant MetalShapeMaterialUniforms &m [[buffer(1)]]) {
    const float2 p = (in.uv - 0.5) * 2.72;
    const float distance = metalShapeDistance(p, g);
    const float antialias = max(fwidth(distance), 0.0025);
    const float body = smoothstep(antialias, -antialias, distance);
    const float2 direction = normalize(m.params1.xy);
    const float materialPhase = m.params0.x * 2.0 * M_PI_F;
    const uint material = min(m.metadata.x, 9u);
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
        const float axis = dot(p, direction);
        const float anchorMask = 1.0 - smoothstep(-0.24, 0.26, axis);
        const float anchorAlpha = body * anchorMask;
        float vapor = 0.0;
        float vaporWeight = 0.0;
        for (uint tap = 0u; tap <= 36u; ++tap) {
            const float t = float(tap) / 36.0;
            const float curve = m.metadata.y == 3u ? sin(t * M_PI_F) * 0.24 : 0.0;
            const float2 sourcePoint = p
                - direction * t * m.params1.z
                - float2(-direction.y, direction.x) * curve;
            const float sourceAxis = dot(sourcePoint, direction);
            const float sourceGate = smoothstep(-0.34, 0.30, sourceAxis);
            float weight = exp(-t * 2.05);
            if (m.metadata.y == 1u) weight *= 0.72 + 0.28 * sin(t * 38.0) * sin(t * 38.0);
            const float softness = mix(0.024, 0.30, t);
            vapor += metalShapeSoftCoverage(sourcePoint, g, softness) * sourceGate * weight;
            vaporWeight += weight;
        }
        const float vaporAlpha = vapor / max(vaporWeight, 1e-4);
        const float vaporFade = 1.0 - smoothstep(0.58, 1.52, axis);
        alpha = max(anchorAlpha, vaporAlpha * vaporFade * 0.56);

        const float brightTransition = smoothstep(-0.52, 0.14, axis);
        const float paleVapor = smoothstep(0.12, 1.08, axis);
        const float3 anchorColor = m.color2.rgb * 0.22;
        color = mix(anchorColor, m.color0.rgb, brightTransition);
        color = mix(color, m.color1.rgb, paleVapor);
        if (m.metadata.y == 2u) color = mix(color, color.brg, paleVapor * 0.34);
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

    return float4(color * alpha, alpha);
}
