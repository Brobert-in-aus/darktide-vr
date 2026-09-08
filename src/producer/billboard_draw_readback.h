#pragma once

#include <d3d12.h>
#include <array>
#include <cstdint>
#include <memory>
#include <vector>

namespace darktidevr::producer {

// Diagnostic copies require an exact single-subresource RTV in RENDER_TARGET
// state, outside a render pass, on a direct list. The caller owns that proof.
// The collector independently rejects unsupported resource shapes/formats.
class BillboardDrawReadback {
 public:
  using Id = std::uint64_t;
  struct Pixels {
    Id id{};
    std::uint64_t vertex_shader{}, pixel_shader{};
    std::uint64_t source_frame{};
    UINT width{}, height{}, row_pitch{};
    DXGI_FORMAT format{};
    std::vector<std::uint8_t> before, after;
  };
  struct Submission {
    std::array<Id, 3> ids{};
    std::size_t count{};
  };

  BillboardDrawReadback();
  // Destruction requires GPU idle and no command recordings referencing copies.
  // A production diagnostic owner must outlive all game command recordings.
  ~BillboardDrawReadback();
  BillboardDrawReadback(const BillboardDrawReadback&) = delete;
  BillboardDrawReadback& operator=(const BillboardDrawReadback&) = delete;

  Id begin(ID3D12GraphicsCommandList*, ID3D12Resource*,
           std::uint64_t vertex_shader, std::uint64_t pixel_shader,
           std::uint64_t source_frame = 0) noexcept;
  void end(Id, ID3D12GraphicsCommandList*) noexcept;
  // Call before ExecuteCommandLists, then after its return. Successful Reset
  // retires the old recording; failed Reset must leave it retained.
  Submission submitting(ID3D12CommandQueue*, UINT, ID3D12CommandList* const*) noexcept;
  void submitted(ID3D12CommandQueue*, const Submission&) noexcept;
  void retired(ID3D12GraphicsCommandList*) noexcept;
  // No waits. Return pixels only after retirement AND the last submission fence.
  // A retired unsubmitted recording, incomplete pair or multi-queue replay never
  // yields pixels. Copies remain retained until collector destruction.
  std::vector<Pixels> collect() noexcept;

 private:
  struct Impl;
  std::unique_ptr<Impl> impl_;
};
}  // namespace darktidevr::producer
