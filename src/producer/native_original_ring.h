#pragma once
#include <Windows.h>
#include <d3d12.h>
#include <cstdint>
#include <memory>

namespace darktidevr::producer {

// Optional native-only publisher using the existing original-frame protocol.
// Its owner must drain the submitted queue before destroying the publisher.
class NativeOriginalRing {
 public:
  using Execute = void(STDMETHODCALLTYPE*)(ID3D12CommandQueue*, UINT,
                                          ID3D12CommandList* const*);
  struct Tag {
    std::uint64_t present{}, pose{}, generation{};
  };
  enum class Result { staged, published, busy, invalid, failed };
  NativeOriginalRing();
  ~NativeOriginalRing();
  NativeOriginalRing(const NativeOriginalRing&) = delete;
  NativeOriginalRing& operator=(const NativeOriginalRing&) = delete;
  Result capture(ID3D12CommandQueue* queue, Execute execute,
                 ID3D12Resource* source, D3D12_RESOURCE_STATES state,
                 unsigned eye, Tag tag);

 private:
  struct Impl;
  std::unique_ptr<Impl> impl_;
};

}  // namespace darktidevr::producer
