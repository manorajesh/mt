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
};

struct VertexOut {
    float4 position [[position]];
    float2 texCoord;
};

vertex VertexOut vertex_main(VertexIn in [[stage_in]]) {
    VertexOut out;
    out.position = float4(in.position, 0.0, 1.0);
    out.texCoord = in.texCoord;
    return out;
}

fragment float4 fragment_main(VertexOut in [[stage_in]],
                              texture2d<float> textTexture [[texture(0)]],
                              sampler samplerState [[sampler(0)]]) {
    float4 texColor = textTexture.sample(samplerState, in.texCoord);
    return texColor;  // Pass sampled texture color as output.
}
