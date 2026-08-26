struct PixelInput {
  float4 position : SV_Position;
  float3 texcoord15 : TEXCOORD15;
  float custom1 : CUSTOM1;
  float4 texcoord14 : TEXCOORD14;
  float4 custom0 : CUSTOM0;
  float2 custom2 : CUSTOM2;
  float3 custom3 : CUSTOM3;
  float3 custom4 : CUSTOM4;
  float3 custom5 : CUSTOM5;
};
float4 ps_main(PixelInput input) : SV_Target0 { return float4(0, 1, 1, 1); }
