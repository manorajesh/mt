#include <metal_stdlib>
using namespace metal;

struct CellInstance {
    ushort col;
    ushort row;
    uint glyph;
    uint attr;
};

struct Uniforms {
    float2 viewportPx;
    float2 cellPx;
    float2 atlasPx;
    float2 atlasCellPx;
    uint atlasCols;
    uint firstChar;
};

struct VSOut {
    float4 pos [[position]];
    float2 uv;
};

vertex VSOut terminal_vertex(
                             uint vid [[vertex_id]],
                             uint iid [[instance_id]],
                             constant CellInstance* inst [[buffer(0)]],
                             constant Uniforms& u [[buffer(1)]]
                             ) {
    const float2 quad[6] = {
        {0,0},{1,0},{0,1},{1,0},{1,1},{0,1}
    };
    
    CellInstance c = inst[iid];
    float2 p = quad[vid];
    
    float2 px = float2(c.col, c.row) * u.cellPx + p * u.cellPx;
    float2 ndc = (px / u.viewportPx) * 2.0 - 1.0;
    ndc.y = -ndc.y;
    
    uint g = c.glyph - u.firstChar;
    uint gx = g % u.atlasCols;
    uint gy = g / u.atlasCols;
    
    float2 glyphPx =
    float2(gx, gy) * u.atlasCellPx + p * u.atlasCellPx;
    
    float2 uv = glyphPx / u.atlasPx;
    
    VSOut o;
    o.pos = float4(ndc, 0, 1);
    o.uv = uv;
    return o;
}

fragment float4 terminal_fragment(VSOut in [[stage_in]],
                                  texture2d<float> atlas [[texture(0)]]) {
    constexpr sampler s(filter::linear);
    float4 c = atlas.sample(s, in.uv);
    return c;
}
