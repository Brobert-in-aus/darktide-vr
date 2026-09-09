// Isolated behavioral reconstruction for dispatch-layout comparisons.
// Not installed or substituted into any game pipeline.
#ifndef GROUP_Y
#define GROUP_Y 32
#endif
RWTexture2D<float4> input_texture0 : register(u0);
[numthreads(32, GROUP_Y, 1)]
void main(uint3 id : SV_DispatchThreadID) {
    float4 value = input_texture0[id.xy];
    if (any(isnan(value))) input_texture0[id.xy] = 0;
}
