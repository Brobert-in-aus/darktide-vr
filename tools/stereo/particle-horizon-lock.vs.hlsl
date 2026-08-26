// Reconstructed from Darktide vertex shader 42e436fb1ef1b392. The original
// spherical billboard basis is replaced with a world-Z cylindrical basis.
// Compile with tools/stereo/build-particle-horizon-lock.ps1.

static uint _156;
static uint _157;
static uint _158;
static uint _418;

static const float _70[5] = { 8.0f, 16.0f, 32.0f, 64.0f, 128.0f };
static const float _77[5] = { 0.0f, 128.0f, 256.0f, 512.0f, 1536.0f };
static const float _82[12] = { -1.0f, 1.0f, -1.0f, -1.0f, 1.0f, 1.0f, 1.0f, 1.0f, -1.0f, -1.0f, 1.0f, -1.0f };

cbuffer global_viewportUBO : register(b0, space0)
{
    float4 global_viewport_m0[111] : packoffset(c0);
};

cbuffer global_environment_settingsUBO : register(b1, space0)
{
    float4 global_environment_settings_m0[25] : packoffset(c0);
};

cbuffer c_per_objectUBO : register(b2, space0)
{
    float4 c_per_object_m0[24] : packoffset(c0);
};

cbuffer c_particle_system_per_frameUBO : register(b3, space0)
{
    float4 c_particle_system_per_frame_m0[12] : packoffset(c0);
};

cbuffer c_material_exportsUBO : register(b4, space0)
{
    float4 c_material_exports_m0[7] : packoffset(c0);
};

ByteAddressBuffer r_particle_data_raw : register(t0, space0);
StructuredBuffer<uint> r_atlas_index_buffer : register(t1, space0);
ByteAddressBuffer r_external_emitter_transform_buffer : register(t2, space0);
Texture3D<float4> _tex_fog_volume : register(t3, space0);
TextureCube<float4> _tex_global_diffuse_map : register(t4, space0);
StructuredBuffer<uint> r_alivebuffer2 : register(t5, space0);
SamplerState _samp_fog_volume : register(s0, space0);
SamplerState _samp_global_diffuse_map : register(s1, space0);

static float4 gl_Position;
static int gl_VertexIndex;

static float4 TEXCOORD_16;
static float2 TEXCOORD_15;
static float CUSTOM;
static float CUSTOM_1;
static float2 CUSTOM_2;
static float CUSTOM_3;
static float CUSTOM_4;

struct SPIRV_Cross_Input
{
    uint gl_VertexIndex : SV_VertexID;
};

struct SPIRV_Cross_Output
{
    float4 gl_Position : SV_Position;
    float4 TEXCOORD_16 : TEXCOORD16;
    float2 TEXCOORD_15 : TEXCOORD15;
    float CUSTOM : CUSTOM0;
    float CUSTOM_1 : CUSTOM1;
    float2 CUSTOM_2 : CUSTOM2;
    float CUSTOM_3 : CUSTOM3;
    float CUSTOM_4 : CUSTOM4;
};

uint spvPackHalf2x16(float2 value)
{
    uint2 Packed = f32tof16(value);
    return Packed.x | (Packed.y << 16);
}

float2 spvUnpackHalf2x16(uint value)
{
    return f16tof32(uint2(value & 0xffff, value >> 16));
}

uint ByteAddressMask(uint index, uint stride)
{
    return index & (4294967295u / stride);
}

uint LoadParticleWord(uint index)
{
    return r_particle_data_raw.Load(index * 4u);
}

uint LoadExternalEmitterWord(uint index)
{
    return r_external_emitter_transform_buffer.Load(index * 4u);
}

void vert_main()
{
    uint _96 = uint(gl_VertexIndex);
    uint _99 = _96 % 6u;
    uint _102 = r_alivebuffer2[_96 / 6u];
    uint _105 = 0u + (_99 * 2u);
    uint _111 = 1u + (_99 * 2u);
    uint _115 = _102 * 56u;
    uint _128 = ByteAddressMask(_102 * 14u, 4u);
    uint4 _142 = uint4(LoadParticleWord(_128), LoadParticleWord(_128 + 1u), LoadParticleWord(_128 + 2u), LoadParticleWord(_128 + 3u));
    float _147 = asfloat(_142.x);
    float _148 = asfloat(_142.y);
    float _149 = asfloat(_142.z);
    uint4 _162 = uint4(_156, _157, _158, LoadParticleWord(ByteAddressMask((_102 * 14u) + 4u, 4u) + 3u));
    uint _163 = _162.w;
    float2 _168 = spvUnpackHalf2x16(_163);
    float _169 = _168.x;
    uint _175 = ByteAddressMask((_102 * 14u) + 8u, 4u);
    uint2 _182 = uint2(LoadParticleWord(_175), LoadParticleWord(_175 + 1u));
    float _185 = asfloat(_182.x);
    float _186 = asfloat(_182.y);
    float _196;
    float _198;
    float _200;
    if ((asuint(c_particle_system_per_frame_m0[9u]).x & 8u) == 0u)
    {
        _196 = _147;
        _198 = _148;
        _200 = _149;
    }
    else
    {
        uint2 _422 = uint2(_418, LoadParticleWord(ByteAddressMask((_102 * 14u) + 12u, 4u) + 1u));
        uint _423 = _422.y;
        uint _424 = _423 * 48u;
        uint _426 = ByteAddressMask(_423 * 12u, 4u);
        float4 _439 = asfloat(uint4(LoadExternalEmitterWord(_426), LoadExternalEmitterWord(_426 + 1u), LoadExternalEmitterWord(_426 + 2u), LoadExternalEmitterWord(_426 + 3u)));
        uint _447 = ByteAddressMask((_423 * 12u) + 4u, 4u);
        float4 _460 = asfloat(uint4(LoadExternalEmitterWord(_447), LoadExternalEmitterWord(_447 + 1u), LoadExternalEmitterWord(_447 + 2u), LoadExternalEmitterWord(_447 + 3u)));
        uint _468 = ByteAddressMask((_423 * 12u) + 8u, 4u);
        float4 _481 = asfloat(uint4(LoadExternalEmitterWord(_468), LoadExternalEmitterWord(_468 + 1u), LoadExternalEmitterWord(_468 + 2u), LoadExternalEmitterWord(_468 + 3u)));
        _196 = mad(_149, _481.x, mad(_148, _460.x, _439.x * _147)) + _439.w;
        _198 = mad(_149, _481.y, mad(_148, _460.y, _439.y * _147)) + _460.w;
        _200 = mad(_149, _481.z, mad(_148, _460.z, _439.z * _147)) + _481.w;
    }
    float _226 = dot(float3(_196 - global_viewport_m0[10u].w, _198 - global_viewport_m0[11u].w, _200 - global_viewport_m0[12u].w), float3(global_viewport_m0[10u].y, global_viewport_m0[11u].y, global_viewport_m0[12u].y));
    float _250 = float(_102);
    float _272 = _82[_105] * 0.5f;
    float _273 = _82[_111] * 0.5f;
    float _277 = floor(float(uint(fmod(_250, (1.0f - c_material_exports_m0[5u].z) + c_material_exports_m0[5u].w) + c_material_exports_m0[5u].z))) / c_material_exports_m0[3u].x;
    float _282 = frac(abs(_277));
    float _301 = mad(_200, c_per_object_m0[19u].z, mad(_198, c_per_object_m0[19u].y, c_per_object_m0[19u].x * _196)) + c_per_object_m0[19u].w;
    float _307 = max(global_viewport_m0[92u].z, global_viewport_m0[92u].w);
    float _315 = (c_material_exports_m0[2u].z / _307) * _301;
    float _319 = (c_material_exports_m0[4u].w / _307) * _301;
    float _320 = min(max(_185, _315), _319);
    float _321 = min(max(_186, _315), _319);
    float _336 = cos(_169);
    float _337 = sin(_169);
    float _356 = _272 * _320;
    float _357 = _273 * _321;
    float2 cylindrical_forward = c_per_object_m0[9u].xy;
    float cylindrical_length_squared = dot(cylindrical_forward, cylindrical_forward);
    float2 cylindrical_right;
    if (cylindrical_length_squared > 1.0e-8f)
    {
        cylindrical_forward *= rsqrt(cylindrical_length_squared);
        cylindrical_right = float2(cylindrical_forward.y, -cylindrical_forward.x);
    }
    else
    {
        float2 fallback_right = c_per_object_m0[8u].xy;
        float fallback_length_squared = dot(fallback_right, fallback_right);
        cylindrical_right = fallback_length_squared > 1.0e-8f ? fallback_right * rsqrt(fallback_length_squared) : float2(1.0f, 0.0f);
    }
    float3 locked_right = float3(cylindrical_right, 0.0f);
    float3 locked_up = float3(0.0f, 0.0f, 1.0f);
    float3 rotated_up = (locked_up * _336) - (_337 * locked_right);
    float3 rotated_right = (_337 * locked_up) + (_336 * locked_right);
    float _365 = (rotated_up.x * _357) + _196 + (rotated_right.x * _356);
    float _367 = (rotated_up.y * _357) + _198 + (rotated_right.y * _356);
    float _369 = (rotated_up.z * _357) + _200 + (rotated_right.z * _356);
    float _393 = mad(_369, c_per_object_m0[16u].z, mad(_367, c_per_object_m0[16u].y, _365 * c_per_object_m0[16u].x)) + c_per_object_m0[16u].w;
    float _397 = mad(_369, c_per_object_m0[17u].z, mad(_367, c_per_object_m0[17u].y, _365 * c_per_object_m0[17u].x)) + c_per_object_m0[17u].w;
    float _405 = mad(_369, c_per_object_m0[19u].z, mad(_367, c_per_object_m0[19u].y, _365 * c_per_object_m0[19u].x)) + c_per_object_m0[19u].w;
    uint _407 = r_atlas_index_buffer[_102];
    uint _408 = _407 >> 24u;
    uint _409 = _407 & 65535u;
    float _495;
    float _497;
    if (_407 > 83886079u)
    {
        _495 = 0.0f;
        _497 = 0.0f;
    }
    else
    {
        uint _547 = uint(4096.0f / _70[_408]);
        float _552 = _70[_408] * 0.000244140625f;
        _495 = (float(_409 % _547) + ((_82[_105] + 1.0f) * 0.5f)) * _552;
        _497 = ((float(_409 / _547) + ((_82[_111] + 1.0f) * 0.5f)) * _552) + (_77[_408] * 0.000244140625f);
    }
    float _521 = global_viewport_m0[10u].w - _365;
    float _522 = global_viewport_m0[11u].w - _367;
    float _523 = global_viewport_m0[12u].w - _369;
    float _530 = dot(float3((-0.0f) - _521, (-0.0f) - _522, (-0.0f) - _523), float3(global_viewport_m0[10u].y, global_viewport_m0[11u].y, global_viewport_m0[12u].y));
    float _558;
    float _562;
    float _566;
    float _570;
    if (global_environment_settings_m0[16u].x < 1.0f)
    {
        _558 = 0.0f;
        _562 = 0.0f;
        _566 = 0.0f;
        _570 = 0.0f;
    }
    else
    {
        float _589 = rsqrt(dot(float3(_521, _522, _523), float3(_521, _522, _523)));
        float _590 = _589 * _521;
        float _591 = _589 * _522;
        float _592 = _523 * _589;
        float _601 = _530 - global_viewport_m0[106u].x;
        float frontier_phi_5_6_ladder;
        float frontier_phi_5_6_ladder_1;
        float frontier_phi_5_6_ladder_2;
        float frontier_phi_5_6_ladder_3;
        if (global_environment_settings_m0[19u].z != 0.0f)
        {
            float4 _614 = _tex_fog_volume.SampleLevel(_samp_fog_volume, float3(((_393 / _405) * 0.5f) + 0.5f, ((((-0.0f) - _397) / _405) * 0.5f) + 0.5f, (log2(_601) * 0.693147182464599609375f) / (log2(global_environment_settings_m0[20u].y) * 0.693147182464599609375f)), 0.0f);
            float _560 = _614.x;
            float _564 = _614.y;
            float _568 = _614.z;
            float _572 = _614.w;
            float frontier_phi_5_6_ladder_7_ladder;
            float frontier_phi_5_6_ladder_7_ladder_1;
            float frontier_phi_5_6_ladder_7_ladder_2;
            float frontier_phi_5_6_ladder_7_ladder_3;
            if (_530 > (global_environment_settings_m0[20u].y + global_viewport_m0[106u].x))
            {
                float _737 = 1.0f - _572;
                float _759 = ((max((global_environment_settings_m0[17u].y - _369) / global_environment_settings_m0[17u].z, 0.0f) * global_environment_settings_m0[17u].x) + global_environment_settings_m0[20u].w) + (max((global_environment_settings_m0[18u].y - _369) / global_environment_settings_m0[18u].z, 0.0f) * global_environment_settings_m0[18u].x);
                float _778 = global_environment_settings_m0[20u].z * global_environment_settings_m0[20u].z;
                float _788 = ((1.0f - _778) / exp2(log2((_778 + 1.0f) - ((global_environment_settings_m0[20u].z * 2.0f) * dot(float3(global_environment_settings_m0[6u].yzw), float3(_590, _591, _592)))) * 1.5f)) * 0.079577468335628509521484375f;
                float _799 = (1.0f - global_viewport_m0[99u].z) * global_environment_settings_m0[2u].z;
                float _800 = (-0.0f) - global_environment_settings_m0[20u].z;
                float4 _805 = _tex_global_diffuse_map.SampleLevel(_samp_global_diffuse_map, float3(_590 * _800, _591 * _800, _592 * _800), 0.0f);
                float _837 = ((((_805.x * _799) * global_environment_settings_m0[3u].x) * global_environment_settings_m0[21u].x) + (((global_environment_settings_m0[7u].x * global_environment_settings_m0[6u].x) * _788) * global_environment_settings_m0[19u].w)) * global_environment_settings_m0[16u].y;
                float _838 = ((((_805.y * _799) * global_environment_settings_m0[3u].y) * global_environment_settings_m0[21u].x) + (((global_environment_settings_m0[7u].y * global_environment_settings_m0[6u].x) * _788) * global_environment_settings_m0[19u].w)) * global_environment_settings_m0[16u].z;
                float _839 = ((((_805.z * _799) * global_environment_settings_m0[3u].z) * global_environment_settings_m0[21u].x) + (((global_environment_settings_m0[7u].z * global_environment_settings_m0[6u].x) * _788) * global_environment_settings_m0[19u].w)) * global_environment_settings_m0[16u].w;
                float _842 = exp2(((_601 - global_environment_settings_m0[20u].y) * (-1.44269502162933349609375f)) * _759);
                bool _843 = _759 < 3.0000001061125658452510833740234e-07f;
                frontier_phi_5_6_ladder_7_ladder = ((_843 ? 0.0f : (_837 - (_837 * _842))) * _737) + _560;
                frontier_phi_5_6_ladder_7_ladder_1 = ((_843 ? 0.0f : (_838 - (_838 * _842))) * _737) + _564;
                frontier_phi_5_6_ladder_7_ladder_2 = ((_843 ? 0.0f : (_839 - (_839 * _842))) * _737) + _568;
                frontier_phi_5_6_ladder_7_ladder_3 = clamp(1.0f - ((1.0f - clamp(1.0f - _842, 0.0f, 1.0f)) * _737), 0.0f, 1.0f);
            }
            else
            {
                frontier_phi_5_6_ladder_7_ladder = _560;
                frontier_phi_5_6_ladder_7_ladder_1 = _564;
                frontier_phi_5_6_ladder_7_ladder_2 = _568;
                frontier_phi_5_6_ladder_7_ladder_3 = _572;
            }
            frontier_phi_5_6_ladder = frontier_phi_5_6_ladder_7_ladder;
            frontier_phi_5_6_ladder_1 = frontier_phi_5_6_ladder_7_ladder_1;
            frontier_phi_5_6_ladder_2 = frontier_phi_5_6_ladder_7_ladder_2;
            frontier_phi_5_6_ladder_3 = frontier_phi_5_6_ladder_7_ladder_3;
        }
        else
        {
            float _638 = ((max((global_environment_settings_m0[17u].y - _369) / global_environment_settings_m0[17u].z, 0.0f) * global_environment_settings_m0[17u].x) + global_environment_settings_m0[20u].w) + (max((global_environment_settings_m0[18u].y - _369) / global_environment_settings_m0[18u].z, 0.0f) * global_environment_settings_m0[18u].x);
            float _657 = global_environment_settings_m0[20u].z * global_environment_settings_m0[20u].z;
            float _668 = ((1.0f - _657) / exp2(log2((_657 + 1.0f) - ((global_environment_settings_m0[20u].z * 2.0f) * dot(float3(global_environment_settings_m0[6u].yzw), float3(_590, _591, _592)))) * 1.5f)) * 0.079577468335628509521484375f;
            float _681 = (1.0f - global_viewport_m0[99u].z) * global_environment_settings_m0[2u].z;
            float _682 = (-0.0f) - global_environment_settings_m0[20u].z;
            float4 _688 = _tex_global_diffuse_map.SampleLevel(_samp_global_diffuse_map, float3(_590 * _682, _591 * _682, _592 * _682), 0.0f);
            float _721 = ((((_688.x * _681) * global_environment_settings_m0[3u].x) * global_environment_settings_m0[21u].x) + (((global_environment_settings_m0[7u].x * global_environment_settings_m0[6u].x) * _668) * global_environment_settings_m0[19u].w)) * global_environment_settings_m0[16u].y;
            float _722 = ((((_688.y * _681) * global_environment_settings_m0[3u].y) * global_environment_settings_m0[21u].x) + (((global_environment_settings_m0[7u].y * global_environment_settings_m0[6u].x) * _668) * global_environment_settings_m0[19u].w)) * global_environment_settings_m0[16u].z;
            float _723 = ((((_688.z * _681) * global_environment_settings_m0[3u].z) * global_environment_settings_m0[21u].x) + (((global_environment_settings_m0[7u].z * global_environment_settings_m0[6u].x) * _668) * global_environment_settings_m0[19u].w)) * global_environment_settings_m0[16u].w;
            float _727 = exp2((_601 * (-1.44269502162933349609375f)) * _638);
            bool _728 = _638 < 3.0000001061125658452510833740234e-07f;
            frontier_phi_5_6_ladder = _728 ? 0.0f : (_721 - (_721 * _727));
            frontier_phi_5_6_ladder_1 = _728 ? 0.0f : (_722 - (_722 * _727));
            frontier_phi_5_6_ladder_2 = _728 ? 0.0f : (_723 - (_723 * _727));
            frontier_phi_5_6_ladder_3 = clamp(1.0f - _727, 0.0f, 1.0f);
        }
        _558 = frontier_phi_5_6_ladder;
        _562 = frontier_phi_5_6_ladder_1;
        _566 = frontier_phi_5_6_ladder_2;
        _570 = frontier_phi_5_6_ladder_3;
    }
    gl_Position.x = _393;
    gl_Position.y = _397;
    gl_Position.z = mad(_369, c_per_object_m0[18u].z, mad(_367, c_per_object_m0[18u].y, _365 * c_per_object_m0[18u].x)) + c_per_object_m0[18u].w;
    gl_Position.w = _405;
    TEXCOORD_16.x = _558;
    TEXCOORD_16.y = _562;
    TEXCOORD_16.z = _566;
    TEXCOORD_16.w = _570;
    TEXCOORD_15.x = _495 - (_82[_105] * 0.0001220703125f);
    TEXCOORD_15.y = ((_82[_111] * 0.0001220703125f) + 1.0f) - _497;
    CUSTOM = ((_226 < 2.0f) || (_226 > c_material_exports_m0[5u].x)) ? 0.0f : ((_226 < 4.0f) ? ((_226 + (-2.0f)) * 0.5f) : ((_226 > (c_material_exports_m0[5u].x - c_material_exports_m0[6u].x)) ? ((c_material_exports_m0[5u].x - _226) / c_material_exports_m0[6u].x) : 1.0f));
    CUSTOM_1 = (c_material_exports_m0[5u].y * 0.100000001490116119384765625f) * float(uint(fmod(_250, (1.0f - c_material_exports_m0[6u].y) + c_material_exports_m0[6u].z) + c_material_exports_m0[6u].y));
    CUSTOM_2.x = ((_272 + 0.5f) + (((_277 >= ((-0.0f) - _277)) ? _282 : ((-0.0f) - _282)) * c_material_exports_m0[3u].x)) / c_material_exports_m0[3u].x;
    CUSTOM_2.y = ((0.5f - _273) + floor(_277)) / c_material_exports_m0[3u].y;
    CUSTOM_3 = asfloat(_142.w) / spvUnpackHalf2x16(_163 >> 16u).x;
    CUSTOM_4 = clamp((_185 * _186) / (_321 * _320), 0.0f, 1.0f);
}

SPIRV_Cross_Output main(SPIRV_Cross_Input stage_input)
{
    gl_VertexIndex = int(stage_input.gl_VertexIndex);
    vert_main();
    SPIRV_Cross_Output stage_output;
    stage_output.gl_Position = gl_Position;
    stage_output.TEXCOORD_16 = TEXCOORD_16;
    stage_output.TEXCOORD_15 = TEXCOORD_15;
    stage_output.CUSTOM = CUSTOM;
    stage_output.CUSTOM_1 = CUSTOM_1;
    stage_output.CUSTOM_2 = CUSTOM_2;
    stage_output.CUSTOM_3 = CUSTOM_3;
    stage_output.CUSTOM_4 = CUSTOM_4;
    return stage_output;
}
