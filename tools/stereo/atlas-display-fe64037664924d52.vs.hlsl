// Reconstructed display VS fe64037664924d52; offline candidate, not deployed.
// Atlas generation is unchanged. Camera basis is the only intended change;
// authored spin, dimensions, atlas UVs, fog and material outputs are preserved.
#include "billboard-cylindrical-basis.hlsli"

static const float _71[5] = { 8.0f, 16.0f, 32.0f, 64.0f, 128.0f };
static const float _78[5] = { 0.0f, 128.0f, 256.0f, 512.0f, 1536.0f };

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
static float TEXCOORD_5;
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
static float3 CUSTOM_3;
static float3 CUSTOM_4;
static float3 CUSTOM_5;

struct SPIRV_Cross_Input
{
    float4 COLOR : COLOR0;
    float TEXCOORD_8 : TEXCOORD8;
    float TEXCOORD_5 : TEXCOORD5;
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
    float3 CUSTOM_3 : CUSTOM3;
    float3 CUSTOM_4 : CUSTOM4;
    float3 CUSTOM_5 : CUSTOM5;
};

void vert_main()
{
    float3 dtvr_right, dtvr_up;
    dtvr_atlas_basis(_31_m0[0u].xyz, _31_m0[1u].xyz, _31_m0[2u].xyz,
                     dtvr_right, dtvr_up);
    float _130 = cos(TEXCOORD_1);
    float _131 = sin(TEXCOORD_1);
    float _138 = (_131 * dtvr_up.x) + (_130 * dtvr_right.x);
    float _139 = (_131 * dtvr_up.y) + (_130 * dtvr_right.y);
    float _140 = (_131 * dtvr_up.z) + (_130 * dtvr_right.z);
    float _147 = (dtvr_up.x * _130) - (_131 * dtvr_right.x);
    float _148 = (dtvr_up.y * _130) - (_131 * dtvr_right.y);
    float _149 = (dtvr_up.z * _130) - (_131 * dtvr_right.z);
    float _153 = (TEXCOORD_7.x * 0.5f) * POSITION_1.x;
    float _154 = (TEXCOORD_7.y * 0.5f) * POSITION_1.y;
    float _162 = ((_147 * _154) + POSITION.x) + (_138 * _153);
    float _164 = ((_148 * _154) + POSITION.y) + (_139 * _153);
    float _166 = ((_149 * _154) + POSITION.z) + (_140 * _153);
    float _176 = POSITION_1.x * 0.5f;
    float _216 = mad(_166, _31_m0[4u].z, mad(_164, _31_m0[4u].y, _162 * _31_m0[4u].x)) + _31_m0[4u].w;
    float _220 = mad(_166, _31_m0[5u].z, mad(_164, _31_m0[5u].y, _162 * _31_m0[5u].x)) + _31_m0[5u].w;
    float _228 = mad(_166, _31_m0[7u].z, mad(_164, _31_m0[7u].y, _162 * _31_m0[7u].x)) + _31_m0[7u].w;
    uint4 _230 = uint4(_15[uint(gl_InstanceIndex) - uint(gl_BaseInstanceARB)], 0, 0, 0);
    uint _231 = _230.x;
    uint _232 = _231 >> 24u;
    uint _234 = _231 & 65535u;
    float _238;
    float _240;
    if (_231 > 83886079u)
    {
        _238 = 0.0f;
        _240 = 0.0f;
    }
    else
    {
        uint _296 = uint(4096.0f / _71[_232]);
        float _301 = _71[_232] * 0.000244140625f;
        _238 = (float(_234 % _296) + ((POSITION_1.x + 1.0f) * 0.5f)) * _301;
        _240 = ((float(_234 / _296) + ((POSITION_1.y + 1.0f) * 0.5f)) * _301) + (_78[_232] * 0.000244140625f);
    }
    float _268 = _21_m0[10u].w - _162;
    float _269 = _21_m0[11u].w - _164;
    float _270 = _21_m0[12u].w - _166;
    float _277 = dot(float3((-0.0f) - _268, (-0.0f) - _269, (-0.0f) - _270), float3(_21_m0[10u].y, _21_m0[11u].y, _21_m0[12u].y));
    float _307;
    float _311;
    float _315;
    float _319;
    if (_26_m0[16u].x < 1.0f)
    {
        _307 = 0.0f;
        _311 = 0.0f;
        _315 = 0.0f;
        _319 = 0.0f;
    }
    else
    {
        float _354 = rsqrt(dot(float3(_268, _269, _270), float3(_268, _269, _270)));
        float _355 = _354 * _268;
        float _356 = _354 * _269;
        float _357 = _270 * _354;
        float _367 = _277 - _21_m0[106u].x;
        float frontier_phi_3_4_ladder;
        float frontier_phi_3_4_ladder_1;
        float frontier_phi_3_4_ladder_2;
        float frontier_phi_3_4_ladder_3;
        if (_26_m0[19u].z != 0.0f)
        {
            float4 _380 = _8.SampleLevel(_34, float3(((_216 / _228) * 0.5f) + 0.5f, ((((-0.0f) - _220) / _228) * 0.5f) + 0.5f, (log2(_367) * 0.693147182464599609375f) / (log2(_26_m0[20u].y) * 0.693147182464599609375f)), 0.0f);
            float _309 = _380.x;
            float _313 = _380.y;
            float _317 = _380.z;
            float _321 = _380.w;
            float frontier_phi_3_4_ladder_5_ladder;
            float frontier_phi_3_4_ladder_5_ladder_1;
            float frontier_phi_3_4_ladder_5_ladder_2;
            float frontier_phi_3_4_ladder_5_ladder_3;
            if (_277 > (_26_m0[20u].y + _21_m0[106u].x))
            {
                float _506 = 1.0f - _321;
                float _528 = ((max((_26_m0[17u].y - _166) / _26_m0[17u].z, 0.0f) * _26_m0[17u].x) + _26_m0[20u].w) + (max((_26_m0[18u].y - _166) / _26_m0[18u].z, 0.0f) * _26_m0[18u].x);
                float _547 = _26_m0[20u].z * _26_m0[20u].z;
                float _557 = ((1.0f - _547) / exp2(log2((_547 + 1.0f) - ((_26_m0[20u].z * 2.0f) * dot(float3(_26_m0[6u].yzw), float3(_355, _356, _357)))) * 1.5f)) * 0.079577468335628509521484375f;
                float _568 = (1.0f - _21_m0[99u].z) * _26_m0[2u].z;
                float _569 = (-0.0f) - _26_m0[20u].z;
                float4 _574 = _11.SampleLevel(_35, float3(_355 * _569, _356 * _569, _357 * _569), 0.0f);
                float _606 = ((((_574.x * _568) * _26_m0[3u].x) * _26_m0[21u].x) + (((_26_m0[7u].x * _26_m0[6u].x) * _557) * _26_m0[19u].w)) * _26_m0[16u].y;
                float _607 = ((((_574.y * _568) * _26_m0[3u].y) * _26_m0[21u].x) + (((_26_m0[7u].y * _26_m0[6u].x) * _557) * _26_m0[19u].w)) * _26_m0[16u].z;
                float _608 = ((((_574.z * _568) * _26_m0[3u].z) * _26_m0[21u].x) + (((_26_m0[7u].z * _26_m0[6u].x) * _557) * _26_m0[19u].w)) * _26_m0[16u].w;
                float _611 = exp2(((_367 - _26_m0[20u].y) * (-1.44269502162933349609375f)) * _528);
                bool _612 = _528 < 3.0000001061125658452510833740234e-07f;
                frontier_phi_3_4_ladder_5_ladder = ((_612 ? 0.0f : (_606 - (_606 * _611))) * _506) + _309;
                frontier_phi_3_4_ladder_5_ladder_1 = ((_612 ? 0.0f : (_607 - (_607 * _611))) * _506) + _313;
                frontier_phi_3_4_ladder_5_ladder_2 = ((_612 ? 0.0f : (_608 - (_608 * _611))) * _506) + _317;
                frontier_phi_3_4_ladder_5_ladder_3 = clamp(1.0f - ((1.0f - clamp(1.0f - _611, 0.0f, 1.0f)) * _506), 0.0f, 1.0f);
            }
            else
            {
                frontier_phi_3_4_ladder_5_ladder = _309;
                frontier_phi_3_4_ladder_5_ladder_1 = _313;
                frontier_phi_3_4_ladder_5_ladder_2 = _317;
                frontier_phi_3_4_ladder_5_ladder_3 = _321;
            }
            frontier_phi_3_4_ladder = frontier_phi_3_4_ladder_5_ladder;
            frontier_phi_3_4_ladder_1 = frontier_phi_3_4_ladder_5_ladder_1;
            frontier_phi_3_4_ladder_2 = frontier_phi_3_4_ladder_5_ladder_2;
            frontier_phi_3_4_ladder_3 = frontier_phi_3_4_ladder_5_ladder_3;
        }
        else
        {
            float _406 = ((max((_26_m0[17u].y - _166) / _26_m0[17u].z, 0.0f) * _26_m0[17u].x) + _26_m0[20u].w) + (max((_26_m0[18u].y - _166) / _26_m0[18u].z, 0.0f) * _26_m0[18u].x);
            float _425 = _26_m0[20u].z * _26_m0[20u].z;
            float _437 = ((1.0f - _425) / exp2(log2((_425 + 1.0f) - ((_26_m0[20u].z * 2.0f) * dot(float3(_26_m0[6u].yzw), float3(_355, _356, _357)))) * 1.5f)) * 0.079577468335628509521484375f;
            float _450 = (1.0f - _21_m0[99u].z) * _26_m0[2u].z;
            float _451 = (-0.0f) - _26_m0[20u].z;
            float4 _457 = _11.SampleLevel(_35, float3(_355 * _451, _356 * _451, _357 * _451), 0.0f);
            float _490 = ((((_457.x * _450) * _26_m0[3u].x) * _26_m0[21u].x) + (((_26_m0[7u].x * _26_m0[6u].x) * _437) * _26_m0[19u].w)) * _26_m0[16u].y;
            float _491 = ((((_457.y * _450) * _26_m0[3u].y) * _26_m0[21u].x) + (((_26_m0[7u].y * _26_m0[6u].x) * _437) * _26_m0[19u].w)) * _26_m0[16u].z;
            float _492 = ((((_457.z * _450) * _26_m0[3u].z) * _26_m0[21u].x) + (((_26_m0[7u].z * _26_m0[6u].x) * _437) * _26_m0[19u].w)) * _26_m0[16u].w;
            float _496 = exp2((_367 * (-1.44269502162933349609375f)) * _406);
            bool _497 = _406 < 3.0000001061125658452510833740234e-07f;
            frontier_phi_3_4_ladder = _497 ? 0.0f : (_490 - (_490 * _496));
            frontier_phi_3_4_ladder_1 = _497 ? 0.0f : (_491 - (_491 * _496));
            frontier_phi_3_4_ladder_2 = _497 ? 0.0f : (_492 - (_492 * _496));
            frontier_phi_3_4_ladder_3 = clamp(1.0f - _496, 0.0f, 1.0f);
        }
        _307 = frontier_phi_3_4_ladder;
        _311 = frontier_phi_3_4_ladder_1;
        _315 = frontier_phi_3_4_ladder_2;
        _319 = frontier_phi_3_4_ladder_3;
    }
    gl_Position.x = _216;
    gl_Position.y = _220;
    gl_Position.z = mad(_166, _31_m0[6u].z, mad(_164, _31_m0[6u].y, _162 * _31_m0[6u].x)) + _31_m0[6u].w;
    gl_Position.w = _228;
    TEXCOORD_15.x = _162;
    TEXCOORD_15.y = _164;
    TEXCOORD_15.z = _166;
    TEXCOORD_16.x = _307;
    TEXCOORD_16.y = _311;
    TEXCOORD_16.z = _315;
    TEXCOORD_16.w = _319;
    TEXCOORD_14.x = _238 - (POSITION_1.x * 0.0001220703125f);
    TEXCOORD_14.y = ((POSITION_1.y * 0.0001220703125f) + 1.0f) - _240;
    CUSTOM.x = COLOR.z;
    CUSTOM.y = COLOR.y;
    CUSTOM.z = COLOR.x;
    CUSTOM.w = COLOR.w;
    CUSTOM_1 = TEXCOORD_8;
    CUSTOM_2.x = ((TEXCOORD_5 < 50.0f) ? ((-0.0f) - _176) : _176) + 0.5f;
    CUSTOM_2.y = 0.5f - (POSITION_1.y * 0.5f);
    CUSTOM_3.x = _138;
    CUSTOM_3.y = _147;
    CUSTOM_3.z = (_139 * _149) - (_140 * _148);
    CUSTOM_4.x = _139;
    CUSTOM_4.y = _148;
    CUSTOM_4.z = (_140 * _147) - (_138 * _149);
    CUSTOM_5.x = _140;
    CUSTOM_5.y = _149;
    CUSTOM_5.z = (_138 * _148) - (_139 * _147);
}

SPIRV_Cross_Output main(SPIRV_Cross_Input stage_input)
{
    gl_InstanceIndex = int(stage_input.gl_InstanceIndex);
    gl_BaseInstanceARB = 0;
    COLOR = stage_input.COLOR;
    TEXCOORD_8 = stage_input.TEXCOORD_8;
    TEXCOORD_5 = stage_input.TEXCOORD_5;
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
    stage_output.CUSTOM_3 = CUSTOM_3;
    stage_output.CUSTOM_4 = CUSTOM_4;
    stage_output.CUSTOM_5 = CUSTOM_5;
    return stage_output;
}
