// Dispatch through an implementation of the official NGX interface, rather
// than through a second copy of the local ABI declaration.
#include <cstddef>
#include <cstdint>
#include <cstring>
#include <iostream>
#include <nvsdk_ngx_params.h>
#include "producer/ngx_parameter_reader.h"

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
  OTHER_GET(float, 11)
  OTHER_GET(double, 12)
  OTHER_GET(int, 14)
  OTHER_GET(ID3D11Resource*, 15)
  OTHER_GET(void*, 17)
#undef OTHER_GET
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
  static_assert(sizeof(void*) == 8);
  static_assert(ngx::kSuccess == NVSDK_NGX_Result_Success);
  static_assert(NVSDK_NGX_Feature_FrameGeneration == 11);
  Parameters parameters;
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
  output = nullptr;
  if (ngx::read_resource(&parameters, "test.resource", &output) !=
          NVSDK_NGX_Result_FAIL_InvalidParameter || output) return 3;
  value = 42;
  if (ngx::read_unsigned(&parameters, "test.uint", &value) !=
          NVSDK_NGX_Result_FAIL_InvalidParameter || value != 42) return 4;
  std::cout << "ngx_parameter_abi=pass resource_slot=9 unsigned_slot=12 failure_preserved=1\n";
}
