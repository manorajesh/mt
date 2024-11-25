//
//  shader.metal
//  mt
//
//  Created by Mano Rajesh on 11/16/24.
//

#include <metal_stdlib>
using namespace metal;

// Vertex data structure
struct VertexIn {
    float2 position [[attribute(0)]];
    float2 texCoord [[attribute(1)]];
};

// Vertex output structure
struct VertexOut {
    float4 position [[position]];
    float2 texCoord;
};

// Uniforms structure
struct Uniforms {
    float4x4 projectionMatrix;
};

// Vertex Shader
vertex VertexOut vertexShader(uint vertexID [[vertex_id]],
                              const device VertexIn *vertices [[buffer(0)]],
                              constant Uniforms &uniforms [[buffer(1)]]) {
    VertexOut out;
    VertexIn in = vertices[vertexID];
    out.position = uniforms.projectionMatrix * float4(in.position, 0.0, 1.0);
    out.texCoord = in.texCoord;
    return out;
}

// Fragment Shader
fragment float4 fragmentShader(VertexOut in [[stage_in]],
                               texture2d<float> sdfTexture [[texture(0)]],
                               sampler sdfSampler [[sampler(0)]]) {
    // Sample the SDF texture
//    float sdf = sdfTexture.sample(sdfSampler, in.texCoord).r;
//
//    // Define edge threshold and smoothing
//    float edge = 0.5;
//    float smoothing = 0.1;
//
//    // Compute alpha using smoothstep for antialiasing
//    float alpha = smoothstep(edge - smoothing, edge + smoothing, sdf);
//
//    // Define text color (white)
//    float3 color = float3(1.0, 1.0, 1.0);
//
//    return float4(color * alpha, alpha);
    
    return float4(1.0, 0.0, 0.0, 1.0);
}
