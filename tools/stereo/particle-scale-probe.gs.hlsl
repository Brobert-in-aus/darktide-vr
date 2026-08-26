struct Vertex {
  float4 position : SV_Position;
  float4 texcoord16 : TEXCOORD16;
  float2 texcoord15 : TEXCOORD15;
  float custom0 : CUSTOM0;
  float custom1 : CUSTOM1;
  float2 custom2 : CUSTOM2;
  float custom3 : CUSTOM3;
  float custom4 : CUSTOM4;
};

[maxvertexcount(3)]
void gs_main(triangle Vertex input[3],
             inout TriangleStream<Vertex> output_stream) {
  float2 ndc[3];
  [unroll]
  for (uint index = 0; index < 3; ++index) {
    ndc[index] = input[index].position.xy / input[index].position.w;
  }
  const float2 center = (ndc[0] + ndc[1] + ndc[2]) / 3.0;
  [unroll]
  for (uint index = 0; index < 3; ++index) {
    Vertex output = input[index];
    const float2 expanded = center + (ndc[index] - center) * 10.0;
    output.position.xy = expanded * output.position.w;
    output_stream.Append(output);
  }
}
