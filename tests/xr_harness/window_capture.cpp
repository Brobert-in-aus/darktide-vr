#include "window_capture.h"

#include <algorithm>
#include <cwctype>
#include <stdexcept>
#include <string>
#include <vector>

namespace darktidevr::harness {
namespace {

std::wstring lowercase(std::wstring value) {
  std::transform(value.begin(), value.end(), value.begin(),
                 [](wchar_t character) {
                   return static_cast<wchar_t>(std::towlower(character));
                 });
  return value;
}

struct SearchContext {
  std::wstring needle;
  std::vector<HWND> matches;
};

class ThreadDpiAwarenessScope {
 public:
  ThreadDpiAwarenessScope()
      : previous_(SetThreadDpiAwarenessContext(
            DPI_AWARENESS_CONTEXT_PER_MONITOR_AWARE_V2)) {}

  ~ThreadDpiAwarenessScope() {
    if (previous_) {
      SetThreadDpiAwarenessContext(previous_);
    }
  }

  ThreadDpiAwarenessScope(const ThreadDpiAwarenessScope&) = delete;
  ThreadDpiAwarenessScope& operator=(const ThreadDpiAwarenessScope&) = delete;

 private:
  DPI_AWARENESS_CONTEXT previous_{};
};

BOOL CALLBACK find_window(HWND window, LPARAM parameter) {
  auto& context = *reinterpret_cast<SearchContext*>(parameter);
  if (!IsWindowVisible(window) || GetWindowTextLengthW(window) <= 0) {
    return TRUE;
  }
  std::wstring title(static_cast<std::size_t>(GetWindowTextLengthW(window)) + 1,
                     L'\0');
  const auto length = GetWindowTextW(window, title.data(),
                                     static_cast<int>(title.size()));
  title.resize(static_cast<std::size_t>(std::max(0, length)));
  if (lowercase(title).find(context.needle) != std::wstring::npos) {
    context.matches.push_back(window);
  }
  return TRUE;
}

}  // namespace

WindowCapture::WindowCapture(std::wstring title_substring,
                             std::uint32_t output_width,
                             std::uint32_t output_height)
    : width_(output_width), height_(output_height) {
  if (title_substring.empty() || width_ == 0 || height_ == 0) {
    throw std::invalid_argument("Window capture requires a title and dimensions");
  }
  SearchContext context{lowercase(std::move(title_substring)), {}};
  if (!EnumWindows(find_window, reinterpret_cast<LPARAM>(&context))) {
    throw std::runtime_error("EnumWindows failed during capture selection");
  }
  if (context.matches.size() != 1) {
    throw std::runtime_error("Window capture title must match exactly one visible window");
  }
  window_ = context.matches.front();

  memory_dc_ = CreateCompatibleDC(nullptr);
  if (!memory_dc_) {
    throw std::runtime_error("CreateCompatibleDC failed");
  }
  BITMAPINFO info{};
  info.bmiHeader.biSize = sizeof(BITMAPINFOHEADER);
  info.bmiHeader.biWidth = static_cast<LONG>(width_);
  info.bmiHeader.biHeight = -static_cast<LONG>(height_);
  info.bmiHeader.biPlanes = 1;
  info.bmiHeader.biBitCount = 32;
  info.bmiHeader.biCompression = BI_RGB;
  void* pixels{};
  bitmap_ = CreateDIBSection(memory_dc_, &info, DIB_RGB_COLORS, &pixels,
                             nullptr, 0);
  if (!bitmap_ || !pixels) {
    DeleteDC(memory_dc_);
    memory_dc_ = nullptr;
    throw std::runtime_error("CreateDIBSection failed");
  }
  pixels_ = static_cast<std::byte*>(pixels);
  previous_bitmap_ = SelectObject(memory_dc_, bitmap_);
  SetStretchBltMode(memory_dc_, COLORONCOLOR);
}

WindowCapture::~WindowCapture() {
  if (memory_dc_ && previous_bitmap_) {
    SelectObject(memory_dc_, previous_bitmap_);
  }
  if (bitmap_) {
    DeleteObject(bitmap_);
  }
  if (memory_dc_) {
    DeleteDC(memory_dc_);
  }
}

CapturedWindowFrame WindowCapture::capture() {
  // GDI screen coordinates and GetClientRect must use the same physical-pixel
  // coordinate system. Without an explicit thread context, a 125%-scaled 4K
  // display reports a 3072 px client width while the screen DC remains 3840
  // physical pixels, moving the apparent SBS boundary and mixing the two eyes
  // after resize.
  const ThreadDpiAwarenessScope dpi_awareness;

  if (!IsWindow(window_) || IsIconic(window_)) {
    throw std::runtime_error("Capture window is unavailable or minimized");
  }
  RECT client{};
  if (!GetClientRect(window_, &client)) {
    throw std::runtime_error("GetClientRect failed during capture");
  }
  POINT origin{client.left, client.top};
  if (!ClientToScreen(window_, &origin)) {
    throw std::runtime_error("ClientToScreen failed during capture");
  }
  const auto source_width = client.right - client.left;
  const auto source_height = client.bottom - client.top;
  if (source_width <= 0 || source_height <= 0) {
    throw std::runtime_error("Capture window has no drawable client area");
  }

  const auto screen_dc = GetDC(nullptr);
  if (!screen_dc) {
    throw std::runtime_error("GetDC failed during capture");
  }
  const auto copied = StretchBlt(
      memory_dc_, 0, 0, static_cast<int>(width_), static_cast<int>(height_),
      screen_dc, origin.x, origin.y, source_width, source_height, SRCCOPY);
  ReleaseDC(nullptr, screen_dc);
  if (!copied) {
    throw std::runtime_error("StretchBlt failed during capture");
  }
  GdiFlush();
  const auto pointer_normalized =
      pointer_normalized_.load(std::memory_order_acquire);
  if (pointer_normalized != UINT64_MAX) {
    const auto normalized_x =
        static_cast<std::uint32_t>(pointer_normalized & 0xffffffffULL);
    const auto normalized_y =
        static_cast<std::uint32_t>(pointer_normalized >> 32U);
    const auto centre_x = static_cast<int>(
        (static_cast<std::int64_t>(normalized_x) * (width_ - 1) + 32767) /
        65535);
    const auto centre_y = static_cast<int>(
        (static_cast<std::int64_t>(normalized_y) * (height_ - 1) + 32767) /
        65535);
    const auto set_pixel = [&](int x, int y, std::byte value) {
      if (x < 0 || y < 0 || x >= static_cast<int>(width_) ||
          y >= static_cast<int>(height_)) {
        return;
      }
      auto* pixel = pixels_ +
                    (static_cast<std::size_t>(y) * width_ +
                     static_cast<std::size_t>(x)) *
                        4;
      pixel[0] = value;
      pixel[1] = value;
      pixel[2] = value;
      pixel[3] = std::byte{255};
    };
    for (int offset = -8; offset <= 8; ++offset) {
      for (int thickness = -2; thickness <= 2; ++thickness) {
        set_pixel(centre_x + offset, centre_y + thickness, std::byte{255});
        set_pixel(centre_x + thickness, centre_y + offset, std::byte{255});
      }
    }
    for (int offset = -10; offset <= 10; ++offset) {
      set_pixel(centre_x + offset, centre_y - 3, std::byte{0});
      set_pixel(centre_x + offset, centre_y + 3, std::byte{0});
      set_pixel(centre_x - 3, centre_y + offset, std::byte{0});
      set_pixel(centre_x + 3, centre_y + offset, std::byte{0});
    }
    set_pixel(centre_x, centre_y, std::byte{255});
  }
  return {pixels_, width_, height_, width_ * 4};
}

void WindowCapture::set_pointer_overlay(
    std::optional<std::pair<std::uint32_t, std::uint32_t>> source_position,
    std::uint32_t source_width, std::uint32_t source_height) {
  if (!source_position || source_width <= 1 || source_height <= 1 ||
      source_position->first >= source_width ||
      source_position->second >= source_height) {
    pointer_normalized_.store(UINT64_MAX, std::memory_order_release);
    return;
  }
  const auto normalize = [](std::uint32_t value, std::uint32_t extent) {
    return static_cast<int>((static_cast<std::uint64_t>(value) * 65535 +
                             (extent - 1) / 2) /
                            (extent - 1));
  };
  const auto normalized_x = static_cast<std::uint32_t>(
      normalize(source_position->first, source_width));
  const auto normalized_y = static_cast<std::uint32_t>(
      normalize(source_position->second, source_height));
  pointer_normalized_.store(
      (static_cast<std::uint64_t>(normalized_y) << 32U) | normalized_x,
      std::memory_order_release);
}

}  // namespace darktidevr::harness
