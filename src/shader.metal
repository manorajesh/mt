#include <metal_stdlib>
using namespace metal;

struct Vertex {
    float2 position [[attribute(0)]];
    float2 tex_coords [[attribute(1)]];
};

struct VertexOut {
    float4 position [[position]];
    float2 tex_coords;
};

vertex VertexOut vertex_main(Vertex in [[stage_in]]) {
    VertexOut out;
    out.position = float4(in.position, 0.0, 1.0);
    out.tex_coords = in.tex_coords;
    return out;
}

fragment float4 fragment_main(VertexOut in [[stage_in]],
                              texture2d<float, access::sample> atlas [[ texture(0) ]],
                              sampler sampler0 [[ sampler(0) ]]) {
    float4 glyphSample = atlas.sample(sampler0, in.tex_coords);
    return glyphSample;
}
