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

cbuffer c_per_object : register(b2) {
  column_major float4x4 world;
  column_major float4x4 inv_world;
  column_major float4x4 view;
  column_major float4x4 projection;
  column_major float4x4 view_projection;
  column_major float4x4 inv_view_projection;
};

float squared_distance(float2 lhs, float2 rhs) {
  const float2 delta = lhs - rhs;
  return dot(delta, delta);
}

[maxvertexcount(3)]
void gs_main(triangle Vertex input[3],
             inout TriangleStream<Vertex> output_stream) {
  float2 ndc[3];
  [unroll]
  for (uint index = 0; index < 3; ++index) {
    ndc[index] = input[index].position.xy / input[index].position.w;
  }

  // The source VS emits two triangles per particle using the fixed corners
  // (-1,+1), (-1,-1), (+1,+1), (+1,+1), (-1,-1), (+1,-1).  Each triangle
  // therefore contains both ends of the quad diagonal.  Its longest edge gives
  // the same particle center for both primitives, avoiding a visible seam.
  const float distance01 = squared_distance(ndc[0], ndc[1]);
  const float distance12 = squared_distance(ndc[1], ndc[2]);
  const float distance20 = squared_distance(ndc[2], ndc[0]);
  uint diagonal_a = 0;
  uint diagonal_b = 1;
  if (distance12 > distance01 && distance12 >= distance20) {
    diagonal_a = 1;
    diagonal_b = 2;
  } else if (distance20 > distance01 && distance20 > distance12) {
    diagonal_a = 2;
    diagonal_b = 0;
  }

  const float4 center_clip =
      (input[diagonal_a].position + input[diagonal_b].position) * 0.5;
  const float2 center_ndc = center_clip.xy / center_clip.w;

  // Project Darktide's world-Z axis through the same per-object transform as
  // the source VS.  Re-expressing the original screen-space offsets in this
  // right/up basis removes headset pitch/roll from the billboard plane while
  // preserving its size, texture coordinates, particle rotation and shading.
  const float4 world_up_clip =
      mul(float4(0.0, 0.0, 1.0, 0.0), view_projection);
  const float4 projected_up_clip = center_clip + world_up_clip;
  float2 up = projected_up_clip.xy / projected_up_clip.w - center_ndc;
  const float up_length_squared = dot(up, up);
  if (up_length_squared > 1.0e-10) {
    up *= rsqrt(up_length_squared);
  } else {
    up = float2(0.0, 1.0);
  }
  const float2 right = float2(up.y, -up.x);

  [unroll]
  for (uint index = 0; index < 3; ++index) {
    Vertex output = input[index];
    const float2 offset = ndc[index] - center_ndc;
    // Keep this diagnostic pass visibly enlarged.  Production will use 1.0
    // after the horizon basis has been validated in-headset.
    const float2 locked_offset = (right * offset.x + up * offset.y) * 3.0;
    output.position.xy = (center_ndc + locked_offset) * output.position.w;
    output_stream.Append(output);
  }
}
