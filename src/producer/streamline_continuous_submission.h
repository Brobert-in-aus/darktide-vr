#pragma once

#include "producer/streamline_submission.h"
#include "core/streamline_present_binding.h"
#include <d3d12.h>
#include <dxgi1_4.h>
#include <wrl/client.h>
#include <array>

namespace darktidevr::producer {

// Consecutive-frame input ownership for bounded probes and persistent delivery.
// Owners are recycled only after exact input completion tickets have retired;
// process-lifetime retention on failure avoids freeing in-flight resources.
// Caller serializes capture and Present calls under its snapshot mutex and
// holds the existing tag API lock across Present.
class StreamlineContinuousSubmission {
 public:
  using Execute = void (STDMETHODCALLTYPE*)(ID3D12CommandQueue*, UINT,
                                            ID3D12CommandList* const*);
  using GetState = int (*)(const void*, void*, const void*);
  using Log = void (*)(const char*, ...);
  bool initialize(ID3D12Device* device, unsigned frames,
                  const std::array<std::uint32_t, 2>& viewports,
                  const std::array<std::array<D3D12_RESOURCE_DESC, 3>, 2>& descriptions,
                  Log log, bool persistent = false, bool profile = false,
                  const std::array<D3D12_RESOURCE_DESC, 2>* ui = nullptr);
  void capture(unsigned eye, std::uint64_t present, std::uint64_t pose,
               const streamline_2_7_30::Constants& constants,
               const std::array<StreamlineTagInput, 4>& inputs,
               ID3D12CommandQueue* queue, Execute execute,
               const StreamlineTagInput* ui = nullptr);
  void before_present(IDXGISwapChain3* swapchain, ID3D12CommandQueue* queue,
                      std::uint64_t present,
                      const std::array<core::StreamlinePresentEyeBinding, 2>& bindings,
                      StreamlineSubmissionApi api, StreamlineSubmission::Tagging tagging,
                      Execute execute, std::uint64_t generation = 0);
  void after_present(ID3D12CommandQueue* queue, GetState get_state, Execute execute);
  void pause(ID3D12CommandQueue* queue, Execute execute, const char* reason);
  bool initialized() const noexcept { return initialized_; }
  bool finished() const noexcept { return stopped_; }
  bool staged() const noexcept { return staged_; }
  std::uint64_t original_ready() const noexcept { return original_ready_; }
  std::uint64_t pose() const noexcept { return frames_[current_ % count_].pose; }
  std::uint64_t previous_pose() const noexcept { return previous_pose_; }
  std::array<void*,6> inputs() const noexcept {
    std::array<void*,6> result{};
    for(unsigned eye=0;eye<2;++eye) for(unsigned role=0;role<3;++role)
      result[eye*3+role]=frames_[current_%count_].textures[eye][role].Get();
    return result;
  }
  void cancel(const char* reason) { fail(reason); }

 private:
  template<class T> using ComPtr = Microsoft::WRL::ComPtr<T>;
  struct Frame {
    StreamlineSubmission submission;
    // Depth, motion, HUDless scene, final color and optional premultiplied UI.
    std::array<std::array<ComPtr<ID3D12Resource>, 5>, 2> textures, sources;
    std::array<ComPtr<ID3D12CommandAllocator>, 2> capture_allocators;
    std::array<ComPtr<ID3D12GraphicsCommandList>, 2> capture_commands;
    std::array<ComPtr<ID3D12Fence>, 2> capture_fences, input_fences;
    ComPtr<ID3D12CommandAllocator> stage_allocator, cleanup_allocator;
    ComPtr<ID3D12GraphicsCommandList> stage_commands, cleanup_commands;
    ComPtr<ID3D12Fence> stage_done;
    ComPtr<ID3D12QueryHeap> timing_queries;
    ComPtr<ID3D12Resource> timing_readback;
    std::array<std::uint64_t, 3> timing_frequencies{};
    std::array<streamline_2_7_30::Constants, 2> constants;
    std::uint64_t source_present{}, pose{}, present{};
    std::uint64_t submission_id{}, reuse_value{1};
    unsigned captured{};
    bool presented{};
  };
  void fail(const char* reason);
  void clear_bindings(ID3D12CommandQueue* queue, Execute execute);
  bool recycle(Frame& frame);
  void harvest_timing(Frame& frame);
  bool resume_capture();
  bool make_commands(ID3D12Device* device, ComPtr<ID3D12CommandAllocator>& allocator,
                     ComPtr<ID3D12GraphicsCommandList>& commands);
  std::array<Frame, 8> frames_;
  std::array<std::uint32_t, 2> viewports_{};
  unsigned count_{}, current_{};
  std::uint32_t width_{}, height_{};
  bool initialized_{}, stopped_{}, staged_{}, cleanup_submitted_{};
  bool persistent_{};
  bool ui_enabled_{};
  std::array<double, 3> timing_totals_{};
  unsigned timing_samples_{};
  bool paused_{}, previous_tags_active_{};
  ComPtr<ID3D12CommandAllocator> pause_allocator_;
  ComPtr<ID3D12GraphicsCommandList> pause_commands_;
  ComPtr<ID3D12Fence> pause_fence_;
  std::uint64_t pause_value_{}, previous_present_{};
  std::uint64_t previous_pose_{};
  std::uint64_t original_ready_{};
  Log log_{};
};
} // namespace darktidevr::producer
