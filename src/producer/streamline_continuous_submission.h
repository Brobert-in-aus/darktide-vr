#pragma once

#include "producer/streamline_submission.h"
#include "core/streamline_present_binding.h"
#include <d3d12.h>
#include <dxgi1_4.h>
#include <wrl/client.h>
#include <array>

namespace darktidevr::producer {

// Bounded consecutive-frame experiment. All GPU owners remain alive until
// process shutdown, including on failure. No generated image is published.
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
                  Log log);
  void capture(unsigned eye, std::uint64_t present, std::uint64_t pose,
               const streamline_2_7_30::Constants& constants,
               const std::array<StreamlineTagInput, 3>& inputs,
               ID3D12CommandQueue* queue, Execute execute);
  void before_present(IDXGISwapChain3* swapchain, ID3D12CommandQueue* queue,
                      std::uint64_t present,
                      const std::array<core::StreamlinePresentEyeBinding, 2>& bindings,
                      StreamlineSubmissionApi api, StreamlineSubmission::Tagging tagging,
                      Execute execute);
  void after_present(ID3D12CommandQueue* queue, GetState get_state, Execute execute);
  bool initialized() const noexcept { return initialized_; }
  bool finished() const noexcept { return stopped_; }
  bool staged() const noexcept { return staged_; }
  void cancel(const char* reason) { fail(reason); }

 private:
  template<class T> using ComPtr = Microsoft::WRL::ComPtr<T>;
  struct Frame {
    StreamlineSubmission submission;
    std::array<std::array<ComPtr<ID3D12Resource>, 3>, 2> textures, sources;
    std::array<ComPtr<ID3D12CommandAllocator>, 2> capture_allocators;
    std::array<ComPtr<ID3D12GraphicsCommandList>, 2> capture_commands;
    std::array<ComPtr<ID3D12Fence>, 2> capture_fences, input_fences;
    ComPtr<ID3D12CommandAllocator> stage_allocator, cleanup_allocator;
    ComPtr<ID3D12GraphicsCommandList> stage_commands, cleanup_commands;
    std::array<streamline_2_7_30::Constants, 2> constants;
    std::uint64_t source_present{}, pose{}, present{};
    unsigned captured{};
    bool presented{};
  };
  void fail(const char* reason);
  void clear_bindings(ID3D12CommandQueue* queue, Execute execute);
  bool make_commands(ID3D12Device* device, ComPtr<ID3D12CommandAllocator>& allocator,
                     ComPtr<ID3D12GraphicsCommandList>& commands);
  std::array<Frame, 8> frames_;
  std::array<std::uint32_t, 2> viewports_{};
  unsigned count_{}, current_{};
  std::uint32_t width_{}, height_{};
  bool initialized_{}, stopped_{}, staged_{}, cleanup_submitted_{};
  Log log_{};
};
} // namespace darktidevr::producer
