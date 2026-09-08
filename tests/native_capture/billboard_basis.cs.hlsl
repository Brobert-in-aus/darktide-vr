#include "../../tools/stereo/billboard-cylindrical-basis.hlsli"

StructuredBuffer<float4> input_basis : register(t0);
RWStructuredBuffer<float4> output_basis : register(u0);

[numthreads(1, 1, 1)]
void main(uint3 id : SV_DispatchThreadID)
{
    float3 right, up;
    dtvr_atlas_basis(input_basis[id.x * 3].xyz,
                     input_basis[id.x * 3 + 1].xyz,
                     input_basis[id.x * 3 + 2].xyz, right, up);
    output_basis[id.x * 2] = float4(right, 0);
    output_basis[id.x * 2 + 1] = float4(up, 0);
}
