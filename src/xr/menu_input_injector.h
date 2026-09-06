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

struct DesktopPointerSample {
  std::uint32_t source_x{};
  std::uint32_t source_y{};
  bool primary_down{};
  bool auxiliary_down{};
};

std::optional<AbsolutePointerPosition> map_source_to_absolute_pointer(
    std::uint32_t source_x, std::uint32_t source_y,
    std::uint32_t source_width, std::uint32_t source_height,
    const ClientRectOnDesktop& client, const DesktopRect& desktop);

std::optional<std::pair<std::uint32_t, std::uint32_t>>
map_client_to_source_pointer(int client_x, int client_y,
                             std::uint32_t client_width,
                             std::uint32_t client_height,
                             std::uint32_t source_width,
                             std::uint32_t source_height);

// Reads or dispatches only against one unambiguous, foreground Darktide window.
// Windows input dispatch remains behind the explicit --enable-menu-input switch.
class MenuInputInjector {
 public:
  explicit MenuInputInjector(std::wstring title_substring);
  ~MenuInputInjector();

  MenuInputInjector(const MenuInputInjector&) = delete;
  MenuInputInjector& operator=(const MenuInputInjector&) = delete;

  bool dispatch(const core::MenuPointerEvent& event,
                std::uint32_t source_width,
                std::uint32_t source_height);
  std::optional<DesktopPointerSample> read_desktop_pointer(
      std::uint32_t source_width, std::uint32_t source_height) const;
  void release();

 private:
  bool send_mouse_flags(DWORD flags, DWORD data = 0);

  std::wstring title_substring_;
  bool button_down_{};
};

}  // namespace darktidevr::harness
