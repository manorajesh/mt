#include <metal_stdlib>
using namespace metal;

struct CellInstance {
  ushort col;
  ushort row;
  uchar  glyph;
  uchar  flags;
};

struct Uniforms {
  float2 viewportPx;
  float2 cellPx;
  float2 atlasPx;
  uint   atlasCols;
  uint   firstChar;
  float2 pad;
};

struct VSOut {
  float4 position [[position]];
  float2 uv;
};

vertex VSOut vertex_main(uint vid [[vertex_id]],
                         uint iid [[instance_id]],
                         const device CellInstance* inst [[buffer(0)]],
                         constant Uniforms& u [[buffer(1)]]) {
  // Local quad in [0,1] space (two triangles)
  const float2 q[6] = { float2(0,0), float2(1,0), float2(0,1), float2(1,0), float2(1,1), float2(0,1) };

  CellInstance ci = inst[iid];

  float2 px0 = float2(ci.col, ci.row) * u.cellPx;
  float2 px  = px0 + q[vid] * u.cellPx;

  // pixel -> NDC
  float2 ndc;
  ndc.x = (px.x / u.viewportPx.x) * 2.0 - 1.0;
  ndc.y = 1.0 - (px.y / u.viewportPx.y) * 2.0;

  // glyph -> atlas cell
  uint g = uint(ci.glyph);
  uint idx = (g >= u.firstChar) ? (g - u.firstChar) : 0;
  uint gx = idx % u.atlasCols;
  uint gy = idx / u.atlasCols;

  float2 cellUV = u.cellPx / u.atlasPx;
  float2 uv0 = float2(float(gx), float(gy)) * cellUV;
  float2 uv  = uv0 + q[vid] * cellUV;

  VSOut out;
  out.position = float4(ndc, 0.0, 1.0);
  out.uv = uv;
  return out;
}

fragment float4 fragment_main(VSOut in [[stage_in]], texture2d<float> atlas [[texture(0)]]) {
  constexpr sampler s(address::clamp_to_edge, filter::linear);
  float4 texel = atlas.sample(s, in.uv);
  float a = texel.a;
  float3 fg = float3(0.82, 0.98, 0.82);
  return float4(fg * a, a);
}
