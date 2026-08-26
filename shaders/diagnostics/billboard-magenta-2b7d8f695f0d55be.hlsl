struct PixelInput {
  float4 position : SV_Position;
  float3 texcoord15 : TEXCOORD15;
  float custom2 : CUSTOM2;
  float4 texcoord14 : TEXCOORD14;
  float3 texcoord13 : TEXCOORD13;
  float4 custom0 : CUSTOM0;
  float2 custom1 : CUSTOM1;
  float2 custom3 : CUSTOM3;
};
float4 ps_main(PixelInput input) : SV_Target0 { return float4(0, 0, 1, 1); }
