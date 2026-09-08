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
    return length(p) - metalShapeGenomeRadius(theta, g);
}

static float metalShapeCoverage(float2 p, constant MetalShapeGenomeUniforms &g) {
    const float distance = metalShapeDistance(p, g);
    const float antialias = max(fwidth(distance), 0.0025);
    return smoothstep(antialias, -antialias, distance);
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
        float weighted = body;
        float weightSum = 1.0;
        for (uint tap = 1u; tap <= 18u; ++tap) {
            const float t = float(tap) / 18.0;
            const float curve = m.metadata.y == 3u ? sin(t * M_PI_F) * 0.22 : 0.0;
            const float2 bent = direction * t * m.params1.z + float2(-direction.y, direction.x) * curve;
            float weight = exp(-t * 2.1);
            if (m.metadata.y == 1u) weight *= 0.56 + 0.44 * sin(t * 35.0) * sin(t * 35.0);
            weighted += metalShapeCoverage(p + bent, g) * weight;
            weightSum += weight;
        }
        alpha = clamp(weighted / weightSum, 0.0, 1.0);
        const float progression = smoothstep(-0.9, 0.9, dot(p, direction));
        color = metalShapePalette(progression, m);
        if (m.metadata.y == 2u) color = mix(color, color.brg, smoothstep(0.2, 0.9, 1.0 - body) * 0.42);
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
