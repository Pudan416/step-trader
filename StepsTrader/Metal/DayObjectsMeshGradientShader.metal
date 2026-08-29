#include <metal_stdlib>
using namespace metal;

// Moving broad color fields with organic distortion and vortex flow.

struct DayObjectsMeshGradientUniforms {
    float4 colors[5];
    float2 resolution;
    float2 offset;
    float time;
    float distortion;
    float swirl;
    float scale;
    float phase;
    uint colorCount;
    uint archetype;
    float motionDirection;
};

static_assert(alignof(DayObjectsMeshGradientUniforms) == 16, "Mesh uniforms require 16-byte alignment");
static_assert(sizeof(DayObjectsMeshGradientUniforms) == 128, "Mesh uniforms must match Swift's 128-byte stride");

struct DayObjectsFullscreenVertexOut {
    float4 position [[position]];
    float2 uv;
};

vertex DayObjectsFullscreenVertexOut dayObjectsFullscreenVertex(
    uint vertexID [[vertex_id]]
) {
    const float2 positions[3] = {
        float2(-1.0, -1.0),
        float2(3.0, -1.0),
        float2(-1.0, 3.0),
    };
    DayObjectsFullscreenVertexOut out;
    float2 position = positions[vertexID];
    out.position = float4(position, 0.0, 1.0);
    // Metal viewport coordinates have a top-left origin. Flip texture Y once
    // here so every fullscreen pass preserves the composition planner's
    // top-left normalized UI/exclusion coordinate system.
    out.uv = float2(position.x * 0.5 + 0.5, 0.5 - position.y * 0.5);
    return out;
}

static float2 dayObjectsBackgroundRotate(float2 point, float angle) {
    float sine = sin(angle);
    float cosine = cos(angle);
    return float2(
        cosine * point.x - sine * point.y,
        sine * point.x + cosine * point.y
    );
}

static float2 dayObjectsMeshPosition(
    uint index,
    float time,
    float phase,
    uint archetype
) {
    float i = float(index);
    float angle = i * 0.37 + phase;
    switch (archetype) {
    case 0: { // drift — broad fields crossing the canvas in one flow
        float2 flow = float2(cos(phase), sin(phase));
        float2 lateral = float2(-flow.y, flow.x);
        float lane = (i - 1.5) * 0.18;
        float travel = sin(time * (0.48 + 0.07 * i) + angle);
        return 0.5 + flow * travel * 0.42 + lateral * lane;
    }
    case 2: { // tide — vertically separated nodes following an S current
        float lane = (i - 1.5) * 0.22;
        return 0.5 + float2(
            0.40 * sin(time * 0.52 + lane * 4.2 + phase),
            lane + 0.10 * sin(time * 0.31 + i * 1.7)
        );
    }
    case 3: { // islands — independent Lissajous fields
        return 0.5 + float2(
            0.38 * sin(time * (0.41 + i * 0.09) + angle * 2.1),
            0.38 * cos(time * (0.57 + i * 0.07) + angle * 1.3)
        );
    }
    case 4: { // bloom — breathing radial constellation
        float bloomRadius = 0.12 + 0.25 * (0.5 + 0.5 * sin(time * 0.46 + i * 1.9));
        float bloomAngle = phase + i * 2.399963 + time * (0.16 + i * 0.025);
        return 0.5 + bloomRadius * float2(cos(bloomAngle), sin(bloomAngle));
    }
    default: { // orbit — offset rotating constellation
        float orbitRadius = 0.24 + 0.08 * sin(i * 1.7 + phase);
        float orbitAngle = phase + i * 1.570796 + time * (0.32 + i * 0.035);
        return 0.5 + orbitRadius * float2(cos(orbitAngle), sin(orbitAngle));
    }
    }
}

static float dayObjectsBroadFieldWeight(float distance, float radius) {
    float normalized = distance / max(radius, 0.001);
    float gaussian = exp(-1.65 * normalized * normalized);
    return 0.035 + gaussian;
}

fragment float4 dayObjectsMeshGradientFragment(
    DayObjectsFullscreenVertexOut in [[stage_in]],
    constant DayObjectsMeshGradientUniforms &uniforms [[buffer(0)]]
) {
    float2 safeResolution = max(uniforms.resolution, float2(1.0));
    float2 aspect = safeResolution / min(safeResolution.x, safeResolution.y);
    float2 uv = (in.uv - 0.5) * aspect / max(uniforms.scale, 0.01) + 0.5 + uniforms.offset;
    float direction = uniforms.motionDirection < 0.0 ? -1.0 : 1.0;
    float time = 0.5 * (uniforms.time * direction + 41.5 + uniforms.phase);

    float radius = smoothstep(0.0, 1.0, length(uv - 0.5));
    float centerWeight = 1.0 - radius;
    switch (uniforms.archetype) {
    case 0: { // drift
        float2 flow = float2(cos(uniforms.phase), sin(uniforms.phase));
        float wave = sin(dot(uv - 0.5, float2(-flow.y, flow.x)) * 3.2 + time * 0.38);
        uv += flow * wave * uniforms.distortion * 0.16;
        break;
    }
    case 2: { // tide
        uv.x += uniforms.distortion * 0.24 * sin((uv.y - 0.5) * 2.4 + time * 0.62);
        uv.y += uniforms.distortion * 0.07 * sin((uv.x - 0.5) * 2.1 - time * 0.34);
        break;
    }
    case 3: { // islands
        uv += uniforms.distortion * 0.09 * float2(
            sin(uv.y * 3.0 + time * 0.43) + cos(uv.x * 2.3 - time * 0.27),
            cos(uv.x * 3.0 - time * 0.39) - sin(uv.y * 2.5 + time * 0.31)
        );
        break;
    }
    case 4: { // bloom
        float breathing = 1.0 + uniforms.distortion * 0.18 * sin(time * 0.52 + radius * 3.0);
        uv = (uv - 0.5) / breathing + 0.5;
        uv = dayObjectsBackgroundRotate(
            uv - 0.5,
            uniforms.swirl * 0.7 * sin(time * 0.24) * centerWeight
        ) + 0.5;
        break;
    }
    default: { // orbit
        float layer = 1.0;
        uv.x += uniforms.distortion * centerWeight / layer
            * sin(time + layer * 0.4 * smoothstep(0.0, 1.0, uv.y))
            * cos(0.2 * time + layer * 1.6 * smoothstep(0.0, 1.0, uv.y));
        uv.y += uniforms.distortion * centerWeight / layer
            * cos(time + layer * 1.6 * smoothstep(0.0, 1.0, uv.x));
        break;
    }
    }

    if (uniforms.archetype != 4) {
        uv = dayObjectsBackgroundRotate(
            uv - 0.5,
            -1.35 * uniforms.swirl * radius
        ) + 0.5;
    }

    uint colorCount = clamp(uniforms.colorCount, 3u, 5u);
    float fieldRadius;
    switch (uniforms.archetype) {
    case 0: // drift
        fieldRadius = 0.72;
        break;
    case 2: // tide
        fieldRadius = 0.74;
        break;
    case 3: // islands
        fieldRadius = 0.62;
        break;
    case 4: // bloom
        fieldRadius = 0.70;
        break;
    default: // orbit
        fieldRadius = 0.68;
        break;
    }
    float3 color = float3(0.0);
    float totalWeight = 0.0;
    for (uint index = 0; index < 5; ++index) {
        if (index >= colorCount) {
            break;
        }
        float2 position = dayObjectsMeshPosition(
            index,
            time,
            uniforms.phase,
            uniforms.archetype
        );
        float2 fieldPosition = 0.5 + (position - 0.5) * 1.85;
        float distance = length(uv - fieldPosition);
        float nodeFactor = 0.94 + 0.06 * sin(float(index) * 2.17 + uniforms.phase);
        float weight = dayObjectsBroadFieldWeight(distance, fieldRadius) * nodeFactor;
        color += uniforms.colors[index].rgb * weight;
        totalWeight += weight;
    }
    return float4(color / max(totalWeight, 0.0001), 1.0);
}

fragment float4 dayObjectsBackgroundPresentFragment(
    DayObjectsFullscreenVertexOut in [[stage_in]],
    texture2d<float> backgroundTexture [[texture(0)]],
    sampler linearSampler [[sampler(0)]]
) {
    return backgroundTexture.sample(linearSampler, saturate(in.uv));
}
