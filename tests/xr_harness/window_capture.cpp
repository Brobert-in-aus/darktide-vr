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
  source_dc_ = CreateCompatibleDC(nullptr);
  if (!memory_dc_ || !source_dc_) {
    if (source_dc_) {
      DeleteDC(source_dc_);
    }
    if (memory_dc_) {
      DeleteDC(memory_dc_);
    }
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
    DeleteDC(source_dc_);
    source_dc_ = nullptr;
    DeleteDC(memory_dc_);
    memory_dc_ = nullptr;
    throw std::runtime_error("CreateDIBSection failed");
  }
  pixels_ = static_cast<std::byte*>(pixels);
  previous_bitmap_ = SelectObject(memory_dc_, bitmap_);
  SetStretchBltMode(memory_dc_, COLORONCOLOR);
}

WindowCapture::~WindowCapture() {
  if (source_dc_ && previous_source_bitmap_) {
    SelectObject(source_dc_, previous_source_bitmap_);
  }
  if (source_bitmap_) {
    DeleteObject(source_bitmap_);
  }
  if (source_dc_) {
    DeleteDC(source_dc_);
  }
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

void WindowCapture::ensure_source_surface(std::uint32_t width,
                                          std::uint32_t height) {
  if (source_bitmap_ && source_width_ == width && source_height_ == height) {
    return;
  }
  if (source_bitmap_) {
    SelectObject(source_dc_, previous_source_bitmap_);
    DeleteObject(source_bitmap_);
    source_bitmap_ = nullptr;
    previous_source_bitmap_ = nullptr;
  }
  BITMAPINFO info{};
  info.bmiHeader.biSize = sizeof(BITMAPINFOHEADER);
  info.bmiHeader.biWidth = static_cast<LONG>(width);
  info.bmiHeader.biHeight = -static_cast<LONG>(height);
  info.bmiHeader.biPlanes = 1;
  info.bmiHeader.biBitCount = 32;
  info.bmiHeader.biCompression = BI_RGB;
  void* source_pixels{};
  source_bitmap_ = CreateDIBSection(source_dc_, &info, DIB_RGB_COLORS,
                                    &source_pixels, nullptr, 0);
  if (!source_bitmap_ || !source_pixels) {
    throw std::runtime_error("CreateDIBSection failed for source window");
  }
  previous_source_bitmap_ = SelectObject(source_dc_, source_bitmap_);
  source_width_ = width;
  source_height_ = height;
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
  const int source_width = static_cast<int>(client.right - client.left);
  const int source_height = static_cast<int>(client.bottom - client.top);
  if (source_width <= 0 || source_height <= 0) {
    throw std::runtime_error("Capture window has no drawable client area");
  }

  ensure_source_surface(static_cast<std::uint32_t>(source_width),
                        static_cast<std::uint32_t>(source_height));
  // PrintWindow asks DWM/the application for this HWND's client surface. The
  // former screen-DC StretchBlt copied whatever happened to cover Darktide on
  // the desktop, which could expose another application inside the headset.
  // PW_RENDERFULLCONTENT keeps the capture independent of z-order and partial
  // occlusion on supported composited windows.
  constexpr UINT render_full_content = 0x00000002;
  const auto printed = PrintWindow(
      window_, source_dc_, PW_CLIENTONLY | render_full_content);
  if (!printed) {
    throw std::runtime_error("PrintWindow failed during capture");
  }
  const auto packed_crop =
      source_crop_normalized_.load(std::memory_order_acquire);
  const auto normalized_crop_x =
      static_cast<std::uint32_t>(packed_crop & 0xffffULL);
  const auto normalized_crop_y =
      static_cast<std::uint32_t>((packed_crop >> 16U) & 0xffffULL);
  const auto normalized_crop_width =
      static_cast<std::uint32_t>((packed_crop >> 32U) & 0xffffULL);
  const auto normalized_crop_height =
      static_cast<std::uint32_t>((packed_crop >> 48U) & 0xffffULL);
  const auto scale_crop = [](std::uint32_t normalized, int extent) {
    return static_cast<int>((static_cast<std::uint64_t>(normalized) * extent +
                             32767ULL) /
                            65535ULL);
  };
  const auto crop_x = scale_crop(normalized_crop_x, source_width);
  const auto crop_y = scale_crop(normalized_crop_y, source_height);
  const auto crop_width = std::clamp(
      scale_crop(normalized_crop_width, source_width), 1,
      source_width - std::min(crop_x, source_width - 1));
  const auto crop_height = std::clamp(
      scale_crop(normalized_crop_height, source_height), 1,
      source_height - std::min(crop_y, source_height - 1));
  const auto copied = StretchBlt(
      memory_dc_, 0, 0, static_cast<int>(width_), static_cast<int>(height_),
      source_dc_, crop_x, crop_y, crop_width, crop_height, SRCCOPY);
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
    const auto set_pixel = [&](int x, int y, std::byte blue,
                               std::byte green, std::byte red) {
      if (x < 0 || y < 0 || x >= static_cast<int>(width_) ||
          y >= static_cast<int>(height_)) {
        return;
      }
      auto* pixel = pixels_ +
                    (static_cast<std::size_t>(y) * width_ +
                     static_cast<std::size_t>(x)) *
                        4;
      pixel[0] = blue;
      pixel[1] = green;
      pixel[2] = red;
      pixel[3] = std::byte{255};
    };
    // Draw a high-contrast reticle directly into the captured menu
    // image. It therefore follows the exact source-space coordinate consumed
    // by Darktide's hotspots and remains visible in both the headset panel and
    // diagnostic capture, independently of the OS cursor.
    for (int y = -20; y <= 20; ++y) {
      for (int x = -20; x <= 20; ++x) {
        const auto distance_squared = x * x + y * y;
        if (distance_squared <= 400 && distance_squared >= 324) {
          set_pixel(centre_x + x, centre_y + y, std::byte{0},
                    std::byte{0}, std::byte{0});
        } else if (distance_squared < 324 && distance_squared >= 196) {
          set_pixel(centre_x + x, centre_y + y, std::byte{255},
                    std::byte{220}, std::byte{0});
        } else if (distance_squared < 36 ||
                   (std::abs(x) <= 2 && std::abs(y) <= 12) ||
                   (std::abs(y) <= 2 && std::abs(x) <= 12)) {
          set_pixel(centre_x + x, centre_y + y, std::byte{255},
                    std::byte{255}, std::byte{255});
        }
      }
    }
    // Reserve the final capture pixel as an opaque cyan swatch. The OpenXR
    // menu pointer layers sample this one pixel to render a spatial laser and
    // impact marker without allocating or synchronizing another swapchain.
    set_pixel(static_cast<int>(width_ - 1), static_cast<int>(height_ - 1),
              std::byte{255}, std::byte{255}, std::byte{0});
  }
  return {pixels_, width_, height_, width_ * 4};
}

void WindowCapture::set_source_crop(std::uint32_t source_width,
                                    std::uint32_t source_height,
                                    std::uint32_t crop_x,
                                    std::uint32_t crop_y,
                                    std::uint32_t crop_width,
                                    std::uint32_t crop_height) {
  if (source_width == 0 || source_height == 0 || crop_width == 0 ||
      crop_height == 0 || crop_x >= source_width || crop_y >= source_height ||
      crop_width > source_width - crop_x ||
      crop_height > source_height - crop_y) {
    source_crop_normalized_.store(0xffffffff00000000ULL,
                                  std::memory_order_release);
    return;
  }
  const auto normalize = [](std::uint32_t value, std::uint32_t extent) {
    return static_cast<std::uint32_t>(
        (static_cast<std::uint64_t>(value) * 65535ULL + extent / 2) / extent);
  };
  const auto packed =
      static_cast<std::uint64_t>(normalize(crop_x, source_width)) |
      (static_cast<std::uint64_t>(normalize(crop_y, source_height)) << 16U) |
      (static_cast<std::uint64_t>(normalize(crop_width, source_width)) << 32U) |
      (static_cast<std::uint64_t>(normalize(crop_height, source_height))
       << 48U);
  source_crop_normalized_.store(packed, std::memory_order_release);
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
  const auto packed_crop =
      source_crop_normalized_.load(std::memory_order_acquire);
  const auto normalized_crop_x =
      static_cast<std::uint32_t>(packed_crop & 0xffffULL);
  const auto normalized_crop_y =
      static_cast<std::uint32_t>((packed_crop >> 16U) & 0xffffULL);
  const auto normalized_crop_width =
      static_cast<std::uint32_t>((packed_crop >> 32U) & 0xffffULL);
  const auto normalized_crop_height =
      static_cast<std::uint32_t>((packed_crop >> 48U) & 0xffffULL);
  const auto normalize = [](std::uint32_t value, std::uint32_t extent) {
    return static_cast<int>((static_cast<std::uint64_t>(value) * 65535 +
                             (extent - 1) / 2) /
                            (extent - 1));
  };
  const auto crop_x = static_cast<std::uint32_t>(
      (static_cast<std::uint64_t>(normalized_crop_x) * source_width + 32767) /
      65535);
  const auto crop_y = static_cast<std::uint32_t>(
      (static_cast<std::uint64_t>(normalized_crop_y) * source_height + 32767) /
      65535);
  const auto crop_width = std::max<std::uint32_t>(
      1, (static_cast<std::uint64_t>(normalized_crop_width) * source_width +
          32767) /
             65535);
  const auto crop_height = std::max<std::uint32_t>(
      1, (static_cast<std::uint64_t>(normalized_crop_height) * source_height +
          32767) /
             65535);
  if (source_position->first < crop_x || source_position->second < crop_y ||
      source_position->first >= crop_x + crop_width ||
      source_position->second >= crop_y + crop_height) {
    pointer_normalized_.store(UINT64_MAX, std::memory_order_release);
    return;
  }
  const auto normalized_x = static_cast<std::uint32_t>(normalize(
      source_position->first - crop_x, crop_width));
  const auto normalized_y = static_cast<std::uint32_t>(normalize(
      source_position->second - crop_y, crop_height));
  pointer_normalized_.store(
      (static_cast<std::uint64_t>(normalized_y) << 32U) | normalized_x,
      std::memory_order_release);
}

}  // namespace darktidevr::harness
