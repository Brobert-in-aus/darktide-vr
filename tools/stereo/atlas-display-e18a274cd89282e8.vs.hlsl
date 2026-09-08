// Reconstructed display VS e18a274cd89282e8; offline candidate, not deployed.
// Atlas generation is unchanged. Camera basis is the only intended change;
// authored spin, dimensions, atlas UVs, fog and material outputs are preserved.
#include "billboard-cylindrical-basis.hlsli"

static const float _73[5] = { 8.0f, 16.0f, 32.0f, 64.0f, 128.0f };
static const float _80[5] = { 0.0f, 128.0f, 256.0f, 512.0f, 1536.0f };

cbuffer _19_21 : register(b0, space0)
{
    float4 _21_m0[111] : packoffset(c0);
};

cbuffer _24_26 : register(b1, space0)
{
    float4 _26_m0[25] : packoffset(c0);
};

cbuffer _29_31 : register(b2, space0)
{
    float4 _31_m0[8] : packoffset(c0);
};

cbuffer _34_36 : register(b3, space0)
{
    float4 _36_m0[6] : packoffset(c0);
};

Texture3D<float4> _8 : register(t0, space0);
TextureCube<float4> _11 : register(t1, space0);
StructuredBuffer<uint> _15 : register(t2, space0);
SamplerState _39 : register(s0, space0);
SamplerState _40 : register(s1, space0);

static float4 gl_Position;
static int gl_InstanceIndex;
static int gl_BaseInstanceARB;
static float4 COLOR;
static float TEXCOORD_5;
static float2 POSITION_1;
static float TEXCOORD_8;
static float4 POSITION;
static float2 TEXCOORD_7;
static float3 TEXCOORD_15;
static float4 TEXCOORD_16;
static float2 TEXCOORD_14;
static float4 CUSTOM;
static float2 CUSTOM_1;
static float CUSTOM_2;
static float2 CUSTOM_3;

struct SPIRV_Cross_Input
{
    float4 COLOR : COLOR0;
    float TEXCOORD_5 : TEXCOORD5;
    float2 POSITION_1 : POSITION1;
    float TEXCOORD_8 : TEXCOORD8;
    float4 POSITION : POSITION0;
    float2 TEXCOORD_7 : TEXCOORD7;
    uint gl_InstanceIndex : SV_InstanceID;
};

struct SPIRV_Cross_Output
{
    float4 gl_Position : SV_Position;
    float3 TEXCOORD_15 : TEXCOORD15;
    float CUSTOM_2 : CUSTOM2;
    float4 TEXCOORD_16 : TEXCOORD16;
    float2 TEXCOORD_14 : TEXCOORD14;
    float2 CUSTOM_1 : CUSTOM1;
    float4 CUSTOM : CUSTOM0;
    float2 CUSTOM_3 : CUSTOM3;
};

void vert_main()
{
    float3 dtvr_right, dtvr_up;
    dtvr_atlas_basis(_31_m0[0u].xyz, _31_m0[1u].xyz, _31_m0[2u].xyz,
                     dtvr_right, dtvr_up);
    float _133 = (TEXCOORD_7.x * 0.5f) * POSITION_1.x;
    float _134 = (TEXCOORD_7.y * 0.5f) * POSITION_1.y;
    float _142 = ((dtvr_right.x * _133) + POSITION.x) + (dtvr_up.x * _134);
    float _144 = ((dtvr_right.y * _133) + POSITION.y) + (dtvr_up.y * _134);
    float _146 = ((dtvr_right.z * _133) + POSITION.z) + (dtvr_up.z * _134);
    float _150 = POSITION_1.x * 0.5f;
    float _152 = _150 + 0.5f;
    float _153 = 0.5f - (POSITION_1.y * 0.5f);
    float _193 = mad(_146, _31_m0[4u].z, mad(_144, _31_m0[4u].y, _142 * _31_m0[4u].x)) + _31_m0[4u].w;
    float _197 = mad(_146, _31_m0[5u].z, mad(_144, _31_m0[5u].y, _142 * _31_m0[5u].x)) + _31_m0[5u].w;
    float _205 = mad(_146, _31_m0[7u].z, mad(_144, _31_m0[7u].y, _31_m0[7u].x * _142)) + _31_m0[7u].w;
    uint4 _207 = uint4(_15[uint(gl_InstanceIndex) - uint(gl_BaseInstanceARB)], 0, 0, 0);
    uint _208 = _207.x;
    uint _209 = _208 >> 24u;
    uint _211 = _208 & 65535u;
    float _215;
    float _217;
    if (_208 > 83886079u)
    {
        _215 = 0.0f;
        _217 = 0.0f;
    }
    else
    {
        uint _274 = uint(4096.0f / _73[_209]);
        float _279 = _73[_209] * 0.000244140625f;
        _215 = (float(_211 % _274) + ((POSITION_1.x + 1.0f) * 0.5f)) * _279;
        _217 = ((float(_211 / _274) + ((POSITION_1.y + 1.0f) * 0.5f)) * _279) + (_80[_209] * 0.000244140625f);
    }
    float _246 = _21_m0[10u].w - _142;
    float _247 = _21_m0[11u].w - _144;
    float _248 = _21_m0[12u].w - _146;
    float _255 = dot(float3((-0.0f) - _246, (-0.0f) - _247, (-0.0f) - _248), float3(_21_m0[10u].y, _21_m0[11u].y, _21_m0[12u].y));
    float _285;
    float _289;
    float _293;
    float _297;
    if (_26_m0[16u].x < 1.0f)
    {
        _285 = 0.0f;
        _289 = 0.0f;
        _293 = 0.0f;
        _297 = 0.0f;
    }
    else
    {
        float _325 = rsqrt(dot(float3(_246, _247, _248), float3(_246, _247, _248)));
        float _326 = _325 * _246;
        float _327 = _325 * _247;
        float _328 = _248 * _325;
        float _338 = _255 - _21_m0[106u].x;
        float frontier_phi_3_4_ladder;
        float frontier_phi_3_4_ladder_1;
        float frontier_phi_3_4_ladder_2;
        float frontier_phi_3_4_ladder_3;
        if (_26_m0[19u].z != 0.0f)
        {
            float4 _351 = _8.SampleLevel(_39, float3(((_193 / _205) * 0.5f) + 0.5f, ((((-0.0f) - _197) / _205) * 0.5f) + 0.5f, (log2(_338) * 0.693147182464599609375f) / (log2(_26_m0[20u].y) * 0.693147182464599609375f)), 0.0f);
            float _287 = _351.x;
            float _291 = _351.y;
            float _295 = _351.z;
            float _299 = _351.w;
            float frontier_phi_3_4_ladder_5_ladder;
            float frontier_phi_3_4_ladder_5_ladder_1;
            float frontier_phi_3_4_ladder_5_ladder_2;
            float frontier_phi_3_4_ladder_5_ladder_3;
            if (_255 > (_26_m0[20u].y + _21_m0[106u].x))
            {
                float _477 = 1.0f - _299;
                float _499 = ((max((_26_m0[17u].y - _146) / _26_m0[17u].z, 0.0f) * _26_m0[17u].x) + _26_m0[20u].w) + (max((_26_m0[18u].y - _146) / _26_m0[18u].z, 0.0f) * _26_m0[18u].x);
                float _518 = _26_m0[20u].z * _26_m0[20u].z;
                float _528 = ((1.0f - _518) / exp2(log2((_518 + 1.0f) - ((_26_m0[20u].z * 2.0f) * dot(float3(_26_m0[6u].yzw), float3(_326, _327, _328)))) * 1.5f)) * 0.079577468335628509521484375f;
                float _539 = (1.0f - _21_m0[99u].z) * _26_m0[2u].z;
                float _540 = (-0.0f) - _26_m0[20u].z;
                float4 _545 = _11.SampleLevel(_40, float3(_326 * _540, _327 * _540, _328 * _540), 0.0f);
                float _577 = ((((_545.x * _539) * _26_m0[3u].x) * _26_m0[21u].x) + (((_26_m0[7u].x * _26_m0[6u].x) * _528) * _26_m0[19u].w)) * _26_m0[16u].y;
                float _578 = ((((_545.y * _539) * _26_m0[3u].y) * _26_m0[21u].x) + (((_26_m0[7u].y * _26_m0[6u].x) * _528) * _26_m0[19u].w)) * _26_m0[16u].z;
                float _579 = ((((_545.z * _539) * _26_m0[3u].z) * _26_m0[21u].x) + (((_26_m0[7u].z * _26_m0[6u].x) * _528) * _26_m0[19u].w)) * _26_m0[16u].w;
                float _582 = exp2(((_338 - _26_m0[20u].y) * (-1.44269502162933349609375f)) * _499);
                bool _583 = _499 < 3.0000001061125658452510833740234e-07f;
                frontier_phi_3_4_ladder_5_ladder = ((_583 ? 0.0f : (_577 - (_577 * _582))) * _477) + _287;
                frontier_phi_3_4_ladder_5_ladder_1 = ((_583 ? 0.0f : (_578 - (_578 * _582))) * _477) + _291;
                frontier_phi_3_4_ladder_5_ladder_2 = ((_583 ? 0.0f : (_579 - (_579 * _582))) * _477) + _295;
                frontier_phi_3_4_ladder_5_ladder_3 = clamp(1.0f - ((1.0f - clamp(1.0f - _582, 0.0f, 1.0f)) * _477), 0.0f, 1.0f);
            }
            else
            {
                frontier_phi_3_4_ladder_5_ladder = _287;
                frontier_phi_3_4_ladder_5_ladder_1 = _291;
                frontier_phi_3_4_ladder_5_ladder_2 = _295;
                frontier_phi_3_4_ladder_5_ladder_3 = _299;
            }
            frontier_phi_3_4_ladder = frontier_phi_3_4_ladder_5_ladder;
            frontier_phi_3_4_ladder_1 = frontier_phi_3_4_ladder_5_ladder_1;
            frontier_phi_3_4_ladder_2 = frontier_phi_3_4_ladder_5_ladder_2;
            frontier_phi_3_4_ladder_3 = frontier_phi_3_4_ladder_5_ladder_3;
        }
        else
        {
            float _377 = ((max((_26_m0[17u].y - _146) / _26_m0[17u].z, 0.0f) * _26_m0[17u].x) + _26_m0[20u].w) + (max((_26_m0[18u].y - _146) / _26_m0[18u].z, 0.0f) * _26_m0[18u].x);
            float _396 = _26_m0[20u].z * _26_m0[20u].z;
            float _408 = ((1.0f - _396) / exp2(log2((_396 + 1.0f) - ((_26_m0[20u].z * 2.0f) * dot(float3(_26_m0[6u].yzw), float3(_326, _327, _328)))) * 1.5f)) * 0.079577468335628509521484375f;
            float _421 = (1.0f - _21_m0[99u].z) * _26_m0[2u].z;
            float _422 = (-0.0f) - _26_m0[20u].z;
            float4 _428 = _11.SampleLevel(_40, float3(_326 * _422, _327 * _422, _328 * _422), 0.0f);
            float _461 = ((((_428.x * _421) * _26_m0[3u].x) * _26_m0[21u].x) + (((_26_m0[7u].x * _26_m0[6u].x) * _408) * _26_m0[19u].w)) * _26_m0[16u].y;
            float _462 = ((((_428.y * _421) * _26_m0[3u].y) * _26_m0[21u].x) + (((_26_m0[7u].y * _26_m0[6u].x) * _408) * _26_m0[19u].w)) * _26_m0[16u].z;
            float _463 = ((((_428.z * _421) * _26_m0[3u].z) * _26_m0[21u].x) + (((_26_m0[7u].z * _26_m0[6u].x) * _408) * _26_m0[19u].w)) * _26_m0[16u].w;
            float _467 = exp2((_338 * (-1.44269502162933349609375f)) * _377);
            bool _468 = _377 < 3.0000001061125658452510833740234e-07f;
            frontier_phi_3_4_ladder = _468 ? 0.0f : (_461 - (_461 * _467));
            frontier_phi_3_4_ladder_1 = _468 ? 0.0f : (_462 - (_462 * _467));
            frontier_phi_3_4_ladder_2 = _468 ? 0.0f : (_463 - (_463 * _467));
            frontier_phi_3_4_ladder_3 = clamp(1.0f - _467, 0.0f, 1.0f);
        }
        _285 = frontier_phi_3_4_ladder;
        _289 = frontier_phi_3_4_ladder_1;
        _293 = frontier_phi_3_4_ladder_2;
        _297 = frontier_phi_3_4_ladder_3;
    }
    gl_Position.x = _193;
    gl_Position.y = _197;
    gl_Position.z = mad(_146, _31_m0[6u].z, mad(_144, _31_m0[6u].y, _31_m0[6u].x * _142)) + _31_m0[6u].w;
    gl_Position.w = _205;
    TEXCOORD_15.x = _142;
    TEXCOORD_15.y = _144;
    TEXCOORD_15.z = _146;
    TEXCOORD_16.x = _285;
    TEXCOORD_16.y = _289;
    TEXCOORD_16.z = _293;
    TEXCOORD_16.w = _297;
    TEXCOORD_14.x = _215 - (POSITION_1.x * 0.0001220703125f);
    TEXCOORD_14.y = ((POSITION_1.y * 0.0001220703125f) + 1.0f) - _217;
    CUSTOM.x = COLOR.z;
    CUSTOM.y = COLOR.y;
    CUSTOM.z = COLOR.x;
    CUSTOM.w = COLOR.w;
    CUSTOM_1.x = _36_m0[5u].x * (_152 + TEXCOORD_5);
    CUSTOM_1.y = _36_m0[5u].x * (_153 + TEXCOORD_5);
    CUSTOM_2 = TEXCOORD_8;
    CUSTOM_3.x = (TEXCOORD_5 < 50.0f) ? (0.5f - _150) : _152;
    CUSTOM_3.y = _153;
}

SPIRV_Cross_Output main(SPIRV_Cross_Input stage_input)
{
    gl_InstanceIndex = int(stage_input.gl_InstanceIndex);
    gl_BaseInstanceARB = 0;
    COLOR = stage_input.COLOR;
    TEXCOORD_5 = stage_input.TEXCOORD_5;
    POSITION_1 = stage_input.POSITION_1;
    TEXCOORD_8 = stage_input.TEXCOORD_8;
    POSITION = stage_input.POSITION;
    TEXCOORD_7 = stage_input.TEXCOORD_7;
    vert_main();
    SPIRV_Cross_Output stage_output;
    stage_output.gl_Position = gl_Position;
    stage_output.TEXCOORD_15 = TEXCOORD_15;
    stage_output.TEXCOORD_16 = TEXCOORD_16;
    stage_output.TEXCOORD_14 = TEXCOORD_14;
    stage_output.CUSTOM = CUSTOM;
    stage_output.CUSTOM_1 = CUSTOM_1;
    stage_output.CUSTOM_2 = CUSTOM_2;
    stage_output.CUSTOM_3 = CUSTOM_3;
    return stage_output;
}
