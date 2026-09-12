#pragma once

#include <Windows.h>

#include <atomic>
#include <cstddef>
#include <cstdint>
#include <optional>
#include <string>
#include <utility>

namespace darktidevr::harness {

struct CapturedWindowFrame {
  const std::byte* bgra_pixels{};
  std::uint32_t width{};
  std::uint32_t height{};
  std::uint32_t row_pitch{};
};

class WindowCapture {
 public:
  WindowCapture(std::wstring title_substring, std::uint32_t output_width,
                std::uint32_t output_height);
  ~WindowCapture();

  WindowCapture(const WindowCapture&) = delete;
  WindowCapture& operator=(const WindowCapture&) = delete;

  CapturedWindowFrame capture();
  [[nodiscard]] bool source_window_alive() const noexcept;
  [[nodiscard]] std::optional<std::pair<std::uint32_t, std::uint32_t>>
  source_extent() const noexcept;
  void set_source_crop(std::uint32_t source_width,
                       std::uint32_t source_height, std::uint32_t crop_x,
                       std::uint32_t crop_y, std::uint32_t crop_width,
                       std::uint32_t crop_height);
  void set_gameplay_reticle_atlas_enabled(bool enabled) noexcept;

 private:
  void ensure_source_surface(std::uint32_t width, std::uint32_t height);

  HWND window_{};
  HDC memory_dc_{};
  HBITMAP bitmap_{};
  HGDIOBJ previous_bitmap_{};
  std::byte* pixels_{};
  HDC source_dc_{};
  HBITMAP source_bitmap_{};
  HGDIOBJ previous_source_bitmap_{};
  std::uint32_t source_width_{};
  std::uint32_t source_height_{};
  std::uint32_t width_{};
  std::uint32_t height_{};
  // Four unsigned 16-bit normalized values: x, y, width, height.
  std::atomic<std::uint64_t> source_crop_normalized_{0xffffffff00000000ULL};
  std::atomic<bool> gameplay_reticle_atlas_enabled_{};
};

}  // namespace darktidevr::harness
