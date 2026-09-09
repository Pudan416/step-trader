#include "ShapeAtlas/Materials/MetalShapeMaterials.metalh"

vertex MetalShapeVertexOut metalShapeGenomeVertex(uint vertexID [[vertex_id]]) {
    const float2 positions[3] = { float2(-1, -1), float2(3, -1), float2(-1, 3) };
    MetalShapeVertexOut out;
    const float2 position = positions[vertexID];
    out.position = float4(position, 0, 1);
    out.uv = float2((position.x + 1) * 0.5, 1 - (position.y + 1) * 0.5);
    return out;
}

fragment float4 metalShapeGenomeFragment(MetalShapeVertexOut in [[stage_in]], constant MetalShapeGenomeUniforms &g [[buffer(0)]], constant MetalShapeMaterialUniforms &m [[buffer(1)]]) {
    return metalShapeGenomeShade(in, g, m);
}
