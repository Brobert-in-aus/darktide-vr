// Optional offline comparison against the official Streamline v2.7.30 headers.
// The reference SDK is supplied externally, never loaded into the game.
#include <cstddef>
#include <cstring>
#include <iostream>
#include <sl_dlss_g.h>
#include "producer/streamline_abi_2_7_30.h"

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
  // The SDK keeps the viewport value private. Compare a real constructed
  // object's bytes instead of bypassing C++ access controls.
  const sl::ViewportHandle viewport(0x12345678U);
  mirror::ViewportHandle copied{};
  std::memcpy(&copied, &viewport, sizeof(copied));
  if (copied.value != 0x12345678U) return 1;
  std::cout << "streamline_abi_reference=pass\n";
}
