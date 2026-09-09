// Dispatch through an implementation of the official NGX interface, rather
// than through a second copy of the local ABI declaration.
#include <cstddef>
#include <cstdint>
#include <cstring>
#include <iostream>
#include <string_view>
#include <nvsdk_ngx_params.h>
#include "producer/ngx_parameter_reader.h"
#include "producer/ngx_sr_observation.h"

namespace ngx = darktidevr::producer::ngx;
struct Parameters final : NVSDK_NGX_Parameter {
  mutable int selected{};
  ID3D12Resource* resource{};
  bool fail{};
#define SET(Type) void Set(const char*, Type) override { selected = -1; }
  SET(unsigned long long)
  SET(float)
  SET(double)
  SET(unsigned int)
  SET(int)
  SET(ID3D11Resource*)
  SET(ID3D12Resource*)
  SET(void*)
#undef SET
#define OTHER_GET(Type, Id) \
  NVSDK_NGX_Result Get(const char*, Type*) const override { \
    selected = Id; return NVSDK_NGX_Result_FAIL_InvalidParameter; }
  OTHER_GET(unsigned long long, 10)
  OTHER_GET(double, 12)
  OTHER_GET(ID3D11Resource*, 15)
  OTHER_GET(void*, 17)
#undef OTHER_GET
  NVSDK_NGX_Result Get(const char*, float* out) const override {
    selected = 11;
    if (fail) return NVSDK_NGX_Result_FAIL_InvalidParameter;
    *out = -0.375f;
    return NVSDK_NGX_Result_Success;
  }
  NVSDK_NGX_Result Get(const char*, int* out) const override {
    selected = 14;
    if (fail) return NVSDK_NGX_Result_FAIL_InvalidParameter;
    *out = -7;
    return NVSDK_NGX_Result_Success;
  }
  NVSDK_NGX_Result Get(const char* name, unsigned int* out) const override {
    selected = 13;
    if (fail || std::strcmp(name, "test.uint"))
      return NVSDK_NGX_Result_FAIL_InvalidParameter;
    *out = 173;
    return NVSDK_NGX_Result_Success;
  }
  NVSDK_NGX_Result Get(const char* name, ID3D12Resource** out) const override {
    selected = 16;
    if (fail || std::strcmp(name, "test.resource"))
      return NVSDK_NGX_Result_FAIL_InvalidParameter;
    *out = resource;
    return NVSDK_NGX_Result_Success;
  }
  void Reset() override { selected = -2; }
};

int main() {
  static_assert(std::string_view(NVSDK_NGX_Parameter_DLSS_Feature_Create_Flags) == "DLSS.Feature.Create.Flags");
  static_assert(NVSDK_NGX_DLSS_Feature_Flags_IsHDR == 1);
  static_assert(NVSDK_NGX_DLSS_Feature_Flags_MVLowRes == 2);
  static_assert(NVSDK_NGX_DLSS_Feature_Flags_MVJittered == 4);
  static_assert(NVSDK_NGX_DLSS_Feature_Flags_DepthInverted == 8);
  static_assert(NVSDK_NGX_DLSS_Feature_Flags_DoSharpening == 32);
  static_assert(NVSDK_NGX_DLSS_Feature_Flags_AutoExposure == 64);
  static_assert(NVSDK_NGX_DLSS_Feature_Flags_AlphaUpscaling == 128);
  static_assert(sizeof(void*) == 8);
  static_assert(ngx::kSuccess == NVSDK_NGX_Result_Success);
  static_assert(NVSDK_NGX_Feature_FrameGeneration == 11);
  static_assert(NVSDK_NGX_Feature_SuperSampling == 1);
  using namespace darktidevr::producer;
  static_assert(std::string_view(kNgxSrResourceNames[0]) == NVSDK_NGX_Parameter_Color);
  static_assert(std::string_view(kNgxSrResourceNames[1]) == NVSDK_NGX_Parameter_Output);
  static_assert(std::string_view(kNgxSrResourceNames[2]) == NVSDK_NGX_Parameter_Depth);
  static_assert(std::string_view(kNgxSrResourceNames[3]) == NVSDK_NGX_Parameter_MotionVectors);
  static_assert(std::string_view(kNgxSrResourceNames[4]) == NVSDK_NGX_Parameter_TransparencyMask);
  static_assert(std::string_view(kNgxSrResourceNames[5]) == NVSDK_NGX_Parameter_ExposureTexture);
  static_assert(std::string_view(kNgxSrResourceNames[6]) == NVSDK_NGX_Parameter_DLSS_Input_Bias_Current_Color_Mask);
  Parameters parameters;
  static_assert(std::string_view(kNgxSrFloatNames[0]) == NVSDK_NGX_Parameter_Jitter_Offset_X);
  static_assert(std::string_view(kNgxSrFloatNames[1]) == NVSDK_NGX_Parameter_Jitter_Offset_Y);
  static_assert(std::string_view(kNgxSrFloatNames[2]) == NVSDK_NGX_Parameter_MV_Scale_X);
  static_assert(std::string_view(kNgxSrFloatNames[3]) == NVSDK_NGX_Parameter_MV_Scale_Y);
  static_assert(std::string_view(kNgxSrFloatNames[4]) == NVSDK_NGX_Parameter_DLSS_Pre_Exposure);
  static_assert(std::string_view(kNgxSrUnsignedNames[0]) == NVSDK_NGX_Parameter_DLSS_Render_Subrect_Dimensions_Width);
  static_assert(std::string_view(kNgxSrUnsignedNames[1]) == NVSDK_NGX_Parameter_DLSS_Render_Subrect_Dimensions_Height);
  static_assert(std::string_view(kNgxSrResetName) == NVSDK_NGX_Parameter_Reset);
  float scalar{};
  int integer{};
  if (ngx::read_float(&parameters, "test.float", &scalar) != ngx::kSuccess ||
      scalar != -0.375f || parameters.selected != 11) return 5;
  if (ngx::read_integer(&parameters, "test.integer", &integer) != ngx::kSuccess ||
      integer != -7 || parameters.selected != 14) return 6;
  // Address identity only: no fabricated COM object is dereferenced.
  std::byte identity{};
  parameters.resource = reinterpret_cast<ID3D12Resource*>(&identity);
  ID3D12Resource* output{};
  if (ngx::read_resource(&parameters, "test.resource", &output) != ngx::kSuccess ||
      parameters.selected != 16 || output != parameters.resource) return 1;
  unsigned int value{};
  if (ngx::read_unsigned(&parameters, "test.uint", &value) != ngx::kSuccess ||
      parameters.selected != 13 || value != 173) return 2;
  parameters.fail = true;
  if (ngx::read_float(&parameters, "test.float", &scalar) != NVSDK_NGX_Result_FAIL_InvalidParameter || scalar != -0.375f) return 7;
  if (ngx::read_integer(&parameters, "test.integer", &integer) != NVSDK_NGX_Result_FAIL_InvalidParameter || integer != -7) return 8;
  output = nullptr;
  if (ngx::read_resource(&parameters, "test.resource", &output) !=
          NVSDK_NGX_Result_FAIL_InvalidParameter || output) return 3;
  value = 42;
  if (ngx::read_unsigned(&parameters, "test.uint", &value) !=
          NVSDK_NGX_Result_FAIL_InvalidParameter || value != 42) return 4;
  std::cout << "ngx_parameter_abi=pass resource_slot=9 unsigned_slot=12 integer_slot=11 float_slot=14 failure_preserved=1\n";
}
