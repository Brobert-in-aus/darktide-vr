struct PixelInput {
  float4 position : SV_Position;
  float3 texcoord15 : TEXCOORD15;
  float custom1 : CUSTOM1;
  float4 texcoord16 : TEXCOORD16;
  float2 texcoord14 : TEXCOORD14;
  float2 custom2 : CUSTOM2;
  float4 custom0 : CUSTOM0;
};
float4 ps_main(PixelInput input) : SV_Target0 { return float4(0, 1, 0, 1); }
