// Interface-matched diagnostic replacement for Darktide pixel shader
// 6020f2548f29fd47. This shader is paired with the confirmed character-select
// mote vertex shader 42e436fb1ef1b392. It deliberately preserves the complete
// input signature while returning opaque magenta for easy worn inspection.
struct PixelInput {
  float4 position : SV_Position;
  float4 texcoord16 : TEXCOORD16;
  float2 texcoord15 : TEXCOORD15;
  float custom0 : CUSTOM0;
  float custom1 : CUSTOM1;
  float2 custom2 : CUSTOM2;
  float custom3 : CUSTOM3;
  float custom4 : CUSTOM4;
};

float4 ps_main(PixelInput input) : SV_Target0 {
  return float4(1.0, 0.0, 1.0, 1.0);
}
