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
  void set_pointer_overlay(
      std::optional<std::pair<std::uint32_t, std::uint32_t>> source_position,
      std::uint32_t source_width, std::uint32_t source_height);

 private:
  HWND window_{};
  HDC memory_dc_{};
  HBITMAP bitmap_{};
  HGDIOBJ previous_bitmap_{};
  std::byte* pixels_{};
  std::uint32_t width_{};
  std::uint32_t height_{};
  std::atomic<std::uint64_t> pointer_normalized_{UINT64_MAX};
};

}  // namespace darktidevr::harness
