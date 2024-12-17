//
//  shader.metal
//  mt
//
//  Created by Mano Rajesh on 12/14/24.
//

#include <metal_stdlib>
using namespace metal;

struct VertexIn {
    float2 position [[attribute(0)]];
    float2 texCoord [[attribute(1)]];
    float4 fgColor  [[attribute(2)]];
    float4 bgColor  [[attribute(3)]];
};

struct VertexOut {
    float4 position [[position]];
    float2 texCoord;
    float4 fgColor;
    float4 bgColor;
};

vertex VertexOut vertex_main(VertexIn in [[stage_in]]) {
    VertexOut out;
    out.position = float4(in.position, 0.0, 1.0);
    out.texCoord = in.texCoord;
    out.fgColor  = in.fgColor;
    out.bgColor  = in.bgColor;
    return out;
}

fragment float4 fragment_main(VertexOut in [[stage_in]],
                              texture2d<float> textTexture [[texture(0)]],
                              sampler samplerState [[sampler(0)]]) {
    float4 glyphSample = textTexture.sample(samplerState, in.texCoord);
    // Blend: glyph alpha picks fgColor over bgColor
    return glyphSample * in.fgColor;
//    return float4(1.0, 0.0, 0.0, 1.0);
}
