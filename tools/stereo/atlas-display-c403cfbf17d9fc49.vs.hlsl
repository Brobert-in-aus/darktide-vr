// Reconstructed display VS c403cfbf17d9fc49; offline candidate, not deployed.
// Atlas generation is unchanged. Camera basis is the only intended change;
// authored spin, dimensions, atlas UVs, fog and material outputs are preserved.
#include "billboard-cylindrical-basis.hlsli"

static const float _67[5] = { 8.0f, 16.0f, 32.0f, 64.0f, 128.0f };
static const float _74[5] = { 0.0f, 128.0f, 256.0f, 512.0f, 1536.0f };

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

Texture3D<float4> _8 : register(t0, space0);
TextureCube<float4> _11 : register(t1, space0);
StructuredBuffer<uint> _15 : register(t2, space0);
SamplerState _34 : register(s0, space0);
SamplerState _35 : register(s1, space0);

static float4 gl_Position;
static int gl_InstanceIndex;
static int gl_BaseInstanceARB;
static float4 COLOR;
static float TEXCOORD_8;
static float2 POSITION_1;
static float TEXCOORD_1;
static float4 POSITION;
static float2 TEXCOORD_7;
static float3 TEXCOORD_15;
static float4 TEXCOORD_16;
static float2 TEXCOORD_14;
static float4 CUSTOM;
static float CUSTOM_1;
static float2 CUSTOM_2;

struct SPIRV_Cross_Input
{
    float4 COLOR : COLOR0;
    float TEXCOORD_8 : TEXCOORD8;
    float2 POSITION_1 : POSITION1;
    float TEXCOORD_1 : TEXCOORD1;
    float4 POSITION : POSITION0;
    float2 TEXCOORD_7 : TEXCOORD7;
    uint gl_InstanceIndex : SV_InstanceID;
};

struct SPIRV_Cross_Output
{
    float4 gl_Position : SV_Position;
    float3 TEXCOORD_15 : TEXCOORD15;
    float CUSTOM_1 : CUSTOM1;
    float4 TEXCOORD_16 : TEXCOORD16;
    float2 TEXCOORD_14 : TEXCOORD14;
    float2 CUSTOM_2 : CUSTOM2;
    float4 CUSTOM : CUSTOM0;
};

void vert_main()
{
    float3 dtvr_right, dtvr_up;
    dtvr_atlas_basis(_31_m0[0u].xyz, _31_m0[1u].xyz, _31_m0[2u].xyz,
                     dtvr_right, dtvr_up);
    float _125 = cos(TEXCOORD_1);
    float _126 = sin(TEXCOORD_1);
    float _148 = (TEXCOORD_7.x * 0.5f) * POSITION_1.x;
    float _149 = (TEXCOORD_7.y * 0.5f) * POSITION_1.y;
    float _157 = ((((dtvr_up.x * _125) - (_126 * dtvr_right.x)) * _149) + POSITION.x) + (((_126 * dtvr_up.x) + (_125 * dtvr_right.x)) * _148);
    float _159 = ((((dtvr_up.y * _125) - (_126 * dtvr_right.y)) * _149) + POSITION.y) + (((_126 * dtvr_up.y) + (_125 * dtvr_right.y)) * _148);
    float _161 = ((((dtvr_up.z * _125) - (_126 * dtvr_right.z)) * _149) + POSITION.z) + (((_126 * dtvr_up.z) + (_125 * dtvr_right.z)) * _148);
    float _196 = mad(_161, _31_m0[4u].z, mad(_159, _31_m0[4u].y, _157 * _31_m0[4u].x)) + _31_m0[4u].w;
    float _200 = mad(_161, _31_m0[5u].z, mad(_159, _31_m0[5u].y, _157 * _31_m0[5u].x)) + _31_m0[5u].w;
    float _208 = mad(_161, _31_m0[7u].z, mad(_159, _31_m0[7u].y, _157 * _31_m0[7u].x)) + _31_m0[7u].w;
    uint4 _210 = uint4(_15[uint(gl_InstanceIndex) - uint(gl_BaseInstanceARB)], 0, 0, 0);
    uint _211 = _210.x;
    uint _212 = _211 >> 24u;
    uint _214 = _211 & 65535u;
    float _219;
    float _221;
    if (_211 > 83886079u)
    {
        _219 = 0.0f;
        _221 = 0.0f;
    }
    else
    {
        uint _278 = uint(4096.0f / _67[_212]);
        float _283 = _67[_212] * 0.000244140625f;
        _219 = (float(_214 % _278) + ((POSITION_1.x + 1.0f) * 0.5f)) * _283;
        _221 = ((float(_214 / _278) + ((POSITION_1.y + 1.0f) * 0.5f)) * _283) + (_74[_212] * 0.000244140625f);
    }
    float _250 = _21_m0[10u].w - _157;
    float _251 = _21_m0[11u].w - _159;
    float _252 = _21_m0[12u].w - _161;
    float _259 = dot(float3((-0.0f) - _250, (-0.0f) - _251, (-0.0f) - _252), float3(_21_m0[10u].y, _21_m0[11u].y, _21_m0[12u].y));
    float _289;
    float _293;
    float _297;
    float _301;
    if (_26_m0[16u].x < 1.0f)
    {
        _289 = 0.0f;
        _293 = 0.0f;
        _297 = 0.0f;
        _301 = 0.0f;
    }
    else
    {
        float _327 = rsqrt(dot(float3(_250, _251, _252), float3(_250, _251, _252)));
        float _328 = _327 * _250;
        float _329 = _327 * _251;
        float _330 = _252 * _327;
        float _340 = _259 - _21_m0[106u].x;
        float frontier_phi_3_4_ladder;
        float frontier_phi_3_4_ladder_1;
        float frontier_phi_3_4_ladder_2;
        float frontier_phi_3_4_ladder_3;
        if (_26_m0[19u].z != 0.0f)
        {
            float4 _353 = _8.SampleLevel(_34, float3(((_196 / _208) * 0.5f) + 0.5f, ((((-0.0f) - _200) / _208) * 0.5f) + 0.5f, (log2(_340) * 0.693147182464599609375f) / (log2(_26_m0[20u].y) * 0.693147182464599609375f)), 0.0f);
            float _291 = _353.x;
            float _295 = _353.y;
            float _299 = _353.z;
            float _303 = _353.w;
            float frontier_phi_3_4_ladder_5_ladder;
            float frontier_phi_3_4_ladder_5_ladder_1;
            float frontier_phi_3_4_ladder_5_ladder_2;
            float frontier_phi_3_4_ladder_5_ladder_3;
            if (_259 > (_26_m0[20u].y + _21_m0[106u].x))
            {
                float _479 = 1.0f - _303;
                float _501 = ((max((_26_m0[17u].y - _161) / _26_m0[17u].z, 0.0f) * _26_m0[17u].x) + _26_m0[20u].w) + (max((_26_m0[18u].y - _161) / _26_m0[18u].z, 0.0f) * _26_m0[18u].x);
                float _520 = _26_m0[20u].z * _26_m0[20u].z;
                float _530 = ((1.0f - _520) / exp2(log2((_520 + 1.0f) - ((_26_m0[20u].z * 2.0f) * dot(float3(_26_m0[6u].yzw), float3(_328, _329, _330)))) * 1.5f)) * 0.079577468335628509521484375f;
                float _541 = (1.0f - _21_m0[99u].z) * _26_m0[2u].z;
                float _542 = (-0.0f) - _26_m0[20u].z;
                float4 _547 = _11.SampleLevel(_35, float3(_328 * _542, _329 * _542, _330 * _542), 0.0f);
                float _579 = ((((_547.x * _541) * _26_m0[3u].x) * _26_m0[21u].x) + (((_26_m0[7u].x * _26_m0[6u].x) * _530) * _26_m0[19u].w)) * _26_m0[16u].y;
                float _580 = ((((_547.y * _541) * _26_m0[3u].y) * _26_m0[21u].x) + (((_26_m0[7u].y * _26_m0[6u].x) * _530) * _26_m0[19u].w)) * _26_m0[16u].z;
                float _581 = ((((_547.z * _541) * _26_m0[3u].z) * _26_m0[21u].x) + (((_26_m0[7u].z * _26_m0[6u].x) * _530) * _26_m0[19u].w)) * _26_m0[16u].w;
                float _584 = exp2(((_340 - _26_m0[20u].y) * (-1.44269502162933349609375f)) * _501);
                bool _585 = _501 < 3.0000001061125658452510833740234e-07f;
                frontier_phi_3_4_ladder_5_ladder = ((_585 ? 0.0f : (_579 - (_579 * _584))) * _479) + _291;
                frontier_phi_3_4_ladder_5_ladder_1 = ((_585 ? 0.0f : (_580 - (_580 * _584))) * _479) + _295;
                frontier_phi_3_4_ladder_5_ladder_2 = ((_585 ? 0.0f : (_581 - (_581 * _584))) * _479) + _299;
                frontier_phi_3_4_ladder_5_ladder_3 = clamp(1.0f - ((1.0f - clamp(1.0f - _584, 0.0f, 1.0f)) * _479), 0.0f, 1.0f);
            }
            else
            {
                frontier_phi_3_4_ladder_5_ladder = _291;
                frontier_phi_3_4_ladder_5_ladder_1 = _295;
                frontier_phi_3_4_ladder_5_ladder_2 = _299;
                frontier_phi_3_4_ladder_5_ladder_3 = _303;
            }
            frontier_phi_3_4_ladder = frontier_phi_3_4_ladder_5_ladder;
            frontier_phi_3_4_ladder_1 = frontier_phi_3_4_ladder_5_ladder_1;
            frontier_phi_3_4_ladder_2 = frontier_phi_3_4_ladder_5_ladder_2;
            frontier_phi_3_4_ladder_3 = frontier_phi_3_4_ladder_5_ladder_3;
        }
        else
        {
            float _379 = ((max((_26_m0[17u].y - _161) / _26_m0[17u].z, 0.0f) * _26_m0[17u].x) + _26_m0[20u].w) + (max((_26_m0[18u].y - _161) / _26_m0[18u].z, 0.0f) * _26_m0[18u].x);
            float _398 = _26_m0[20u].z * _26_m0[20u].z;
            float _410 = ((1.0f - _398) / exp2(log2((_398 + 1.0f) - ((_26_m0[20u].z * 2.0f) * dot(float3(_26_m0[6u].yzw), float3(_328, _329, _330)))) * 1.5f)) * 0.079577468335628509521484375f;
            float _423 = (1.0f - _21_m0[99u].z) * _26_m0[2u].z;
            float _424 = (-0.0f) - _26_m0[20u].z;
            float4 _430 = _11.SampleLevel(_35, float3(_328 * _424, _329 * _424, _330 * _424), 0.0f);
            float _463 = ((((_430.x * _423) * _26_m0[3u].x) * _26_m0[21u].x) + (((_26_m0[7u].x * _26_m0[6u].x) * _410) * _26_m0[19u].w)) * _26_m0[16u].y;
            float _464 = ((((_430.y * _423) * _26_m0[3u].y) * _26_m0[21u].x) + (((_26_m0[7u].y * _26_m0[6u].x) * _410) * _26_m0[19u].w)) * _26_m0[16u].z;
            float _465 = ((((_430.z * _423) * _26_m0[3u].z) * _26_m0[21u].x) + (((_26_m0[7u].z * _26_m0[6u].x) * _410) * _26_m0[19u].w)) * _26_m0[16u].w;
            float _469 = exp2((_340 * (-1.44269502162933349609375f)) * _379);
            bool _470 = _379 < 3.0000001061125658452510833740234e-07f;
            frontier_phi_3_4_ladder = _470 ? 0.0f : (_463 - (_463 * _469));
            frontier_phi_3_4_ladder_1 = _470 ? 0.0f : (_464 - (_464 * _469));
            frontier_phi_3_4_ladder_2 = _470 ? 0.0f : (_465 - (_465 * _469));
            frontier_phi_3_4_ladder_3 = clamp(1.0f - _469, 0.0f, 1.0f);
        }
        _289 = frontier_phi_3_4_ladder;
        _293 = frontier_phi_3_4_ladder_1;
        _297 = frontier_phi_3_4_ladder_2;
        _301 = frontier_phi_3_4_ladder_3;
    }
    gl_Position.x = _196;
    gl_Position.y = _200;
    gl_Position.z = mad(_161, _31_m0[6u].z, mad(_159, _31_m0[6u].y, _157 * _31_m0[6u].x)) + _31_m0[6u].w;
    gl_Position.w = _208;
    TEXCOORD_15.x = _157;
    TEXCOORD_15.y = _159;
    TEXCOORD_15.z = _161;
    TEXCOORD_16.x = _289;
    TEXCOORD_16.y = _293;
    TEXCOORD_16.z = _297;
    TEXCOORD_16.w = _301;
    TEXCOORD_14.x = _219 - (POSITION_1.x * 0.0001220703125f);
    TEXCOORD_14.y = ((POSITION_1.y * 0.0001220703125f) + 1.0f) - _221;
    CUSTOM.x = COLOR.z;
    CUSTOM.y = COLOR.y;
    CUSTOM.z = COLOR.x;
    CUSTOM.w = COLOR.w;
    CUSTOM_1 = TEXCOORD_8;
    CUSTOM_2.x = (POSITION_1.x * 0.5f) + 0.5f;
    CUSTOM_2.y = 0.5f - (POSITION_1.y * 0.5f);
}

SPIRV_Cross_Output main(SPIRV_Cross_Input stage_input)
{
    gl_InstanceIndex = int(stage_input.gl_InstanceIndex);
    gl_BaseInstanceARB = 0;
    COLOR = stage_input.COLOR;
    TEXCOORD_8 = stage_input.TEXCOORD_8;
    POSITION_1 = stage_input.POSITION_1;
    TEXCOORD_1 = stage_input.TEXCOORD_1;
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
    return stage_output;
}
