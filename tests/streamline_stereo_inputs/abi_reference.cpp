// Optional offline comparison against the official Streamline v2.7.30 headers.
// The reference SDK is supplied externally, never loaded into the game.
#include <cstddef>
#include <cstring>
#include <iostream>
#include <sl_dlss_g.h>
#include "producer/streamline_abi_2_7_30.h"
#include "producer/streamline_eye_tags.h"
#include "producer/streamline_stereo_tags.h"
#include "producer/streamline_submission.h"

namespace mirror = darktidevr::producer::streamline_2_7_30;
static_assert(SL_VERSION_MAJOR == 2 && SL_VERSION_MINOR == 7 && SL_VERSION_PATCH == 30,
              "This comparison requires the official v2.7.30 headers");
#define SIZE(local, upstream) static_assert(sizeof(mirror::local) == sizeof(sl::upstream))
#define FIELD(local, field, upstream, member) \
  static_assert(offsetof(mirror::local, field) == offsetof(sl::upstream, member))

SIZE(BaseStructure, BaseStructure);
FIELD(BaseStructure, struct_type, BaseStructure, structType);
FIELD(BaseStructure, struct_version, BaseStructure, structVersion);
SIZE(ViewportHandle, ViewportHandle);
SIZE(Extent, Extent);
SIZE(Constants, Constants);
FIELD(Constants, camera_view_to_clip, Constants, cameraViewToClip);
FIELD(Constants, clip_to_camera_view, Constants, clipToCameraView);
FIELD(Constants, clip_to_lens_clip, Constants, clipToLensClip);
FIELD(Constants, clip_to_prev_clip, Constants, clipToPrevClip);
FIELD(Constants, prev_clip_to_clip, Constants, prevClipToClip);
FIELD(Constants, jitter_offset, Constants, jitterOffset);
FIELD(Constants, motion_vector_scale, Constants, mvecScale);
FIELD(Constants, camera_position, Constants, cameraPos);
FIELD(Constants, camera_near, Constants, cameraNear);
FIELD(Constants, depth_inverted, Constants, depthInverted);
FIELD(Constants, min_relative_linear_depth_object_separation, Constants,
      minRelativeLinearDepthObjectSeparation);
SIZE(Resource, Resource);
FIELD(Resource, type, Resource, type);
FIELD(Resource, native, Resource, native);
FIELD(Resource, state, Resource, state);
FIELD(Resource, width, Resource, width);
FIELD(Resource, array_layers, Resource, arrayLayers);
FIELD(Resource, gpu_virtual_address, Resource, gpuVirtualAddress);
FIELD(Resource, reserved, Resource, reserved);
SIZE(ResourceTag, ResourceTag);
FIELD(ResourceTag, resource, ResourceTag, resource);
FIELD(ResourceTag, type, ResourceTag, type);
FIELD(ResourceTag, lifecycle, ResourceTag, lifecycle);
FIELD(ResourceTag, extent, ResourceTag, extent);
SIZE(DlssGOptions, DLSSGOptions);
FIELD(DlssGOptions, mode, DLSSGOptions, mode);
FIELD(DlssGOptions, num_frames_to_generate, DLSSGOptions, numFramesToGenerate);
FIELD(DlssGOptions, num_back_buffers, DLSSGOptions, numBackBuffers);
FIELD(DlssGOptions, color_width, DLSSGOptions, colorWidth);
FIELD(DlssGOptions, api_error_callback, DLSSGOptions, onErrorCallback);
FIELD(DlssGOptions, queue_parallelism_mode, DLSSGOptions, queueParallelismMode);
SIZE(DlssGState, DLSSGState);
FIELD(DlssGState, estimated_vram_usage_bytes, DLSSGState, estimatedVRAMUsageInBytes);
FIELD(DlssGState, status, DLSSGState, status);
FIELD(DlssGState, num_frames_actually_presented, DLSSGState, numFramesActuallyPresented);
FIELD(DlssGState, num_frames_to_generate_max, DLSSGState, numFramesToGenerateMax);
FIELD(DlssGState, inputs_processing_completion_fence, DLSSGState,
      inputsProcessingCompletionFence);
FIELD(DlssGState, last_present_inputs_processing_completion_fence_value, DLSSGState,
      lastPresentInputsProcessingCompletionFenceValue);
static_assert(mirror::kFeatureDlssG == sl::kFeatureDLSS_G);

int main() {
  const auto request = mirror::make_dlssg_state();
  const sl::DLSSGState expected_request{};
  if (request.base.next || request.base.struct_version != expected_request.structVersion ||
      std::memcmp(&request.base.struct_type, &sl::DLSSGState::s_structType,
                  sizeof(sl::StructType)) != 0 || request.inputs_processing_completion_fence)
    return 1;
  const auto prepared_viewport = mirror::make_viewport(42);
  const sl::ViewportHandle expected_viewport(42);
  mirror::ViewportHandle compared_viewport{};
  std::memcpy(&compared_viewport, &expected_viewport, sizeof(expected_viewport));
  if (prepared_viewport.value != compared_viewport.value ||
      std::memcmp(&prepared_viewport.base.struct_type, &compared_viewport.base.struct_type,
                  sizeof(sl::StructType)) != 0) return 1;
  // The SDK keeps the viewport value private. Compare a real constructed
  // object's bytes instead of bypassing C++ access controls.
  const sl::ViewportHandle viewport(0x12345678U);
  mirror::ViewportHandle copied{};
  std::memcpy(&copied, &viewport, sizeof(copied));
  if (copied.value != 0x12345678U) return 1;
  int depth{}, motion{}, color{};
  const std::array<darktidevr::producer::StreamlineTagInput, 3> inputs{{
      {&depth, 100, 100, 64, 41}, {&motion, 100, 100, 64, 34},
      {&color, 200, 200, 64, 28}}};
  darktidevr::producer::StreamlineEyeTags prepared;
  if (!prepared.prepare(1, 200, 200, inputs)) return 1;
  for (std::uint32_t i = 0; i < prepared.count(); ++i) {
    const auto& tag = prepared.data()[i];
    if (std::memcmp(&tag.base.struct_type, &sl::ResourceTag::s_structType,
                    sizeof(sl::StructType)) != 0 ||
        tag.base.struct_version != sl::kStructVersion1) return 1;
    if (tag.resource &&
        (std::memcmp(&tag.resource->base.struct_type, &sl::Resource::s_structType,
                     sizeof(sl::StructType)) != 0 ||
         tag.resource->base.struct_version != sl::kStructVersion1 ||
         tag.lifecycle != sl::ResourceLifecycle::eValidUntilPresent)) return 1;
  }
  if (prepared.data()[0].type != sl::kBufferTypeDepth ||
      prepared.data()[1].type != sl::kBufferTypeMotionVectors ||
      prepared.data()[2].type != sl::kBufferTypeHUDLessColor ||
      prepared.data()[3].type != sl::kBufferTypeBackbuffer) return 1;
  sl::Constants sdk_constants;
  sdk_constants.jitterOffset = {0.25f, -0.125f};
  std::array<mirror::Constants, 2> constants{};
  std::memcpy(&constants[0], &sdk_constants, sizeof(sdk_constants));
  constants[1] = constants[0];
  constants[1].jitter_offset.x = -0.25f;
  int right_depth{}, right_motion{}, right_color{};
  darktidevr::producer::StreamlineStereoTags::Inputs pair_inputs{{inputs, {{
      {&right_depth, 100, 100, 64, 41}, {&right_motion, 100, 100, 64, 34},
      {&right_color, 200, 200, 64, 28}}}}};
  darktidevr::producer::StreamlineStereoTags pair;
  if (!pair.prepare(200, 200, {1, 2}, constants, pair_inputs) ||
      pair.viewport(1) != 2 || pair.eye(2) || pair.constants(2) ||
      pair.eye(1)->data()[3].extent.left != 200 ||
      pair.constants(0)->jitter_offset.x != 0.25f ||
      pair.constants(1)->jitter_offset.x != -0.25f) return 1;
  constants[0].jitter_offset.x = 0.5f;
  if (pair.constants(0)->jitter_offset.x != 0.25f) return 1;
  // Failed preparation must not expose a previously valid pair.
  if (pair.prepare(200, 200, {1, 1}, constants, pair_inputs) || pair.eye(0)) return 1;
  auto aliased = pair_inputs;
  aliased[1][1].native = aliased[0][0].native;
  if (pair.prepare(200, 200, {1, 2}, constants, aliased)) return 1;
  auto wide_inputs = pair_inputs;
  for (auto& eye_inputs : wide_inputs) eye_inputs[2].width = 400;
  if (pair.prepare(200, 200, {1, 2}, constants, wide_inputs) || pair.eye(0)) return 1;
  constants[0].base.next = &constants[1].base;
  if (pair.prepare(200, 200, {1, 2}, constants, pair_inputs)) return 1;
  constants[0].base.next = nullptr;
  constants[0].base.struct_version = 1;
  if (pair.prepare(200, 200, {1, 2}, constants, pair_inputs)) return 1;
  constants[0].base.struct_version = 2;
  constants[0].base.struct_type.data1 = 0;
  if (pair.prepare(200, 200, {1, 2}, constants, pair_inputs)) return 1;
  std::memcpy(&constants[0], &sdk_constants, sizeof(sdk_constants));
  darktidevr::producer::StreamlineSubmission submission;
  int frame{}, commands{};
  if (!submission.prepare(1, 200, 200, {1, 2}, constants, pair_inputs)) return 1;
  const auto check_viewport = +[](const void*, const void*, const void* handle) -> int {
    const auto* value = static_cast<const mirror::ViewportHandle*>(handle);
    const sl::ViewportHandle expected(value->value);
    mirror::ViewportHandle copied_viewport{};
    std::memcpy(&copied_viewport, &expected, sizeof(expected));
    return value->base.next == nullptr && value->base.struct_version == 1 &&
        std::memcmp(&value->base.struct_type, &copied_viewport.base.struct_type,
                    sizeof(sl::StructType)) == 0 ? 0 : 1;
  };
  const auto accept_tags = +[](const void*, const void*, const void*,
                              std::uint32_t, void*) -> int { return 0; };
  if (!submission.stage({check_viewport, accept_tags}, &frame, &commands) ||
      !submission.clear_tags(&commands) || !submission.retire()) return 1;
  std::cout << "streamline_abi_reference=pass\n";
}
