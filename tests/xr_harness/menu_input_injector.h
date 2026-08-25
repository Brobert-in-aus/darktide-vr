#pragma once

#include <Windows.h>

#include "core/menu_pointer_input.h"

#include <cstdint>
#include <optional>
#include <string>

namespace darktidevr::harness {

struct DesktopRect {
  int left{};
  int top{};
  int width{};
  int height{};
};

struct ClientRectOnDesktop {
  int left{};
  int top{};
  std::uint32_t width{};
  std::uint32_t height{};
};

struct AbsolutePointerPosition {
  LONG x{};
  LONG y{};
};

std::optional<AbsolutePointerPosition> map_source_to_absolute_pointer(
    std::uint32_t source_x, std::uint32_t source_y,
    std::uint32_t source_width, std::uint32_t source_height,
    const ClientRectOnDesktop& client, const DesktopRect& desktop);

// Dispatches only to one unambiguous, foreground Darktide window. The adapter
// is constructed only behind the explicit --enable-menu-input switch.
class MenuInputInjector {
 public:
  explicit MenuInputInjector(std::wstring title_substring);
  ~MenuInputInjector();

  MenuInputInjector(const MenuInputInjector&) = delete;
  MenuInputInjector& operator=(const MenuInputInjector&) = delete;

  bool dispatch(const core::MenuPointerEvent& event,
                std::uint32_t source_width,
                std::uint32_t source_height);
  void release();

 private:
  bool send_mouse_flags(DWORD flags, DWORD data = 0);

  std::wstring title_substring_;
  bool button_down_{};
};

}  // namespace darktidevr::harness
