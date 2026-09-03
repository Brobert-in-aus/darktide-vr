#pragma once

// Minimal read-only ABI mirror for NVIDIA Streamline v2.7.30. The upstream
// headers are MIT-licensed. Keep this deliberately limited to structures that
// Darktide itself passes through the observed slDLSSGGetState and
// slDLSSGSetOptions calls; the mod does not construct Streamline inputs or call
// the feature API independently.

#include <cstddef>
#include <cstdint>

namespace darktidevr::producer::streamline_2_7_30 {

struct StructType {
  std::uint32_t data1;
  std::uint16_t data2;
  std::uint16_t data3;
  std::uint8_t data4[8];
};

struct BaseStructure {
  BaseStructure* next;
  StructType struct_type;
  std::size_t struct_version;
};

struct ViewportHandle {
  BaseStructure base;
  std::uint32_t value;
};

struct Extent {
  std::uint32_t top{};
  std::uint32_t left{};
  std::uint32_t width{};
  std::uint32_t height{};
};

enum class ResourceType : char {
  texture_2d,
  buffer,
  command_queue,
  command_buffer,
  command_pool,
  fence,
  swapchain,
  host_fence,
  unknown,
};

struct Resource {
  BaseStructure base;
  ResourceType type{ResourceType::texture_2d};
  void* native{};
  void* memory{};
  void* view{};
  std::uint32_t state{UINT32_MAX};
  std::uint32_t width{};
  std::uint32_t height{};
  std::uint32_t native_format{};
  std::uint32_t mip_levels{};
  std::uint32_t array_layers{};
  std::uint64_t gpu_virtual_address{};
  std::uint32_t flags{};
  std::uint32_t usage{};
  std::uint32_t reserved{};
};

struct ResourceTag {
  BaseStructure base;
  Resource* resource{};
  std::uint32_t type{};
  std::uint32_t lifecycle{};
  Extent extent{};
};

struct DlssGOptions {
  BaseStructure base;
  std::uint32_t mode;
  std::uint32_t num_frames_to_generate;
  std::uint32_t flags;
  std::uint32_t dynamic_resolution_width;
  std::uint32_t dynamic_resolution_height;
  std::uint32_t num_back_buffers;
  std::uint32_t motion_depth_width;
  std::uint32_t motion_depth_height;
  std::uint32_t color_width;
  std::uint32_t color_height;
  std::uint32_t color_buffer_format;
  std::uint32_t motion_buffer_format;
  std::uint32_t depth_buffer_format;
  std::uint32_t hudless_buffer_format;
  std::uint32_t ui_buffer_format;
  void* api_error_callback;
  std::uint8_t reserved15;
  std::uint32_t queue_parallelism_mode;
};

struct DlssGState {
  BaseStructure base;
  std::uint64_t estimated_vram_usage_bytes;
  std::uint32_t status;
  std::uint32_t min_width_or_height;
  std::uint32_t num_frames_actually_presented;
  std::uint32_t num_frames_to_generate_max;
  std::uint8_t reserved4;
  std::uint8_t vsync_support_available;
  void* inputs_processing_completion_fence;
  std::uint64_t last_present_inputs_processing_completion_fence_value;
};

constexpr std::uint32_t kFeatureDlssG = 1000;

static_assert(sizeof(StructType) == 16);
static_assert(sizeof(BaseStructure) == 32);
static_assert(offsetof(ViewportHandle, value) == 32);
static_assert(sizeof(ViewportHandle) == 40);
static_assert(sizeof(Extent) == 16);
static_assert(offsetof(Resource, type) == 32);
static_assert(offsetof(Resource, native) == 40);
static_assert(offsetof(Resource, state) == 64);
static_assert(offsetof(Resource, gpu_virtual_address) == 88);
static_assert(sizeof(Resource) == 112);
static_assert(offsetof(ResourceTag, resource) == 32);
static_assert(offsetof(ResourceTag, type) == 40);
static_assert(offsetof(ResourceTag, extent) == 48);
static_assert(sizeof(ResourceTag) == 64);
static_assert(offsetof(DlssGOptions, mode) == 32);
static_assert(offsetof(DlssGOptions, num_frames_to_generate) == 36);
static_assert(offsetof(DlssGOptions, num_back_buffers) == 52);
static_assert(offsetof(DlssGOptions, color_width) == 64);
static_assert(offsetof(DlssGOptions, api_error_callback) == 96);
static_assert(offsetof(DlssGOptions, queue_parallelism_mode) == 108);
static_assert(sizeof(DlssGOptions) == 112);
static_assert(offsetof(DlssGState, estimated_vram_usage_bytes) == 32);
static_assert(offsetof(DlssGState, status) == 40);
static_assert(offsetof(DlssGState, num_frames_actually_presented) == 48);
static_assert(offsetof(DlssGState, num_frames_to_generate_max) == 52);
static_assert(offsetof(DlssGState, inputs_processing_completion_fence) == 64);
static_assert(offsetof(
                  DlssGState,
                  last_present_inputs_processing_completion_fence_value) ==
              72);
static_assert(sizeof(DlssGState) == 80);

}  // namespace darktidevr::producer::streamline_2_7_30
