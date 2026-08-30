#include "menu_input_injector.h"

#include <algorithm>
#include <cwctype>
#include <limits>
#include <stdexcept>
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

BOOL CALLBACK find_window(HWND window, LPARAM parameter) {
  auto& context = *reinterpret_cast<SearchContext*>(parameter);
  if (!IsWindowVisible(window) || GetWindowTextLengthW(window) <= 0) {
    return TRUE;
  }
  std::wstring title(static_cast<std::size_t>(GetWindowTextLengthW(window)) + 1,
                     L'\0');
  const auto length =
      GetWindowTextW(window, title.data(), static_cast<int>(title.size()));
  title.resize(static_cast<std::size_t>(std::max(0, length)));
  if (lowercase(title).find(context.needle) != std::wstring::npos) {
    context.matches.push_back(window);
  }
  return TRUE;
}

std::optional<HWND> unique_window(const std::wstring& title_substring) {
  SearchContext context{lowercase(title_substring), {}};
  if (!EnumWindows(find_window, reinterpret_cast<LPARAM>(&context)) ||
      context.matches.size() != 1) {
    return std::nullopt;
  }
  return context.matches.front();
}

DesktopRect virtual_desktop() {
  return {GetSystemMetrics(SM_XVIRTUALSCREEN),
          GetSystemMetrics(SM_YVIRTUALSCREEN),
          GetSystemMetrics(SM_CXVIRTUALSCREEN),
          GetSystemMetrics(SM_CYVIRTUALSCREEN)};
}

std::optional<ClientRectOnDesktop> client_rect(HWND window) {
  RECT rect{};
  if (!GetClientRect(window, &rect)) {
    return std::nullopt;
  }
  POINT origin{rect.left, rect.top};
  if (!ClientToScreen(window, &origin)) {
    return std::nullopt;
  }
  const auto width = rect.right - rect.left;
  const auto height = rect.bottom - rect.top;
  if (width <= 0 || height <= 0) {
    return std::nullopt;
  }
  return ClientRectOnDesktop{origin.x, origin.y,
                             static_cast<std::uint32_t>(width),
                             static_cast<std::uint32_t>(height)};
}

}  // namespace

std::optional<AbsolutePointerPosition> map_source_to_absolute_pointer(
    std::uint32_t source_x, std::uint32_t source_y,
    std::uint32_t source_width, std::uint32_t source_height,
    const ClientRectOnDesktop& client, const DesktopRect& desktop) {
  if (source_width == 0 || source_height == 0 || client.width == 0 ||
      client.height == 0 || desktop.width <= 1 || desktop.height <= 1 ||
      source_x >= source_width || source_y >= source_height) {
    return std::nullopt;
  }
  const auto scale_coordinate = [](std::uint32_t value,
                                   std::uint32_t source_extent,
                                   std::uint32_t target_extent) {
    if (source_extent <= 1 || target_extent <= 1) {
      return std::uint64_t{0};
    }
    return (static_cast<std::uint64_t>(value) * (target_extent - 1) +
            (source_extent - 1) / 2) /
           (source_extent - 1);
  };
  const auto screen_x = static_cast<std::int64_t>(client.left) +
                        static_cast<std::int64_t>(scale_coordinate(
                            source_x, source_width, client.width));
  const auto screen_y = static_cast<std::int64_t>(client.top) +
                        static_cast<std::int64_t>(scale_coordinate(
                            source_y, source_height, client.height));
  const auto relative_x = screen_x - desktop.left;
  const auto relative_y = screen_y - desktop.top;
  if (relative_x < 0 || relative_y < 0 || relative_x >= desktop.width ||
      relative_y >= desktop.height) {
    return std::nullopt;
  }
  return AbsolutePointerPosition{
      static_cast<LONG>((relative_x * 65535 + (desktop.width - 1) / 2) /
                        (desktop.width - 1)),
      static_cast<LONG>((relative_y * 65535 + (desktop.height - 1) / 2) /
                        (desktop.height - 1))};
}

std::optional<std::pair<std::uint32_t, std::uint32_t>>
map_client_to_source_pointer(int client_x, int client_y,
                             std::uint32_t client_width,
                             std::uint32_t client_height,
                             std::uint32_t source_width,
                             std::uint32_t source_height) {
  if (client_width == 0 || client_height == 0 || source_width == 0 ||
      source_height == 0 || client_x < 0 || client_y < 0 ||
      static_cast<std::uint32_t>(client_x) >= client_width ||
      static_cast<std::uint32_t>(client_y) >= client_height) {
    return std::nullopt;
  }
  const auto scale_coordinate = [](std::uint32_t value,
                                   std::uint32_t source_extent,
                                   std::uint32_t target_extent) {
    if (source_extent <= 1 || target_extent <= 1) {
      return std::uint32_t{0};
    }
    return static_cast<std::uint32_t>(
        (static_cast<std::uint64_t>(value) * (target_extent - 1) +
         (source_extent - 1) / 2) /
        (source_extent - 1));
  };
  return std::pair{
      scale_coordinate(static_cast<std::uint32_t>(client_x), client_width,
                       source_width),
      scale_coordinate(static_cast<std::uint32_t>(client_y), client_height,
                       source_height)};
}

MenuInputInjector::MenuInputInjector(std::wstring title_substring)
    : title_substring_(std::move(title_substring)) {
  if (title_substring_.empty()) {
    throw std::invalid_argument("Menu input target title cannot be empty");
  }
}

MenuInputInjector::~MenuInputInjector() { release(); }

std::optional<DesktopPointerSample> MenuInputInjector::read_desktop_pointer(
    std::uint32_t source_width, std::uint32_t source_height) const {
  const auto target = unique_window(title_substring_);
  if (!target || GetForegroundWindow() != *target) {
    return std::nullopt;
  }
  RECT rect{};
  POINT pointer{};
  if (!GetClientRect(*target, &rect) || !GetCursorPos(&pointer) ||
      !ScreenToClient(*target, &pointer)) {
    return std::nullopt;
  }
  const auto width = rect.right - rect.left;
  const auto height = rect.bottom - rect.top;
  if (width <= 0 || height <= 0) {
    return std::nullopt;
  }
  const auto source = map_client_to_source_pointer(
      pointer.x, pointer.y, static_cast<std::uint32_t>(width),
      static_cast<std::uint32_t>(height), source_width, source_height);
  if (!source) {
    return std::nullopt;
  }
  return DesktopPointerSample{
      source->first, source->second,
      (GetAsyncKeyState(VK_LBUTTON) & 0x8000) != 0};
}

bool MenuInputInjector::send_mouse_flags(DWORD flags, DWORD data) {
  INPUT input{};
  input.type = INPUT_MOUSE;
  input.mi.dwFlags = flags;
  input.mi.mouseData = data;
  return SendInput(1, &input, sizeof(input)) == 1;
}

bool MenuInputInjector::dispatch(const core::MenuPointerEvent& event,
                                 std::uint32_t source_width,
                                 std::uint32_t source_height) {
  const auto target = unique_window(title_substring_);
  if (!target) {
    if (button_down_) {
      release();
    }
    return false;
  }
  if (GetForegroundWindow() != *target &&
      (event.type == core::MenuPointerEventType::button_down ||
       event.type == core::MenuPointerEventType::scroll ||
       event.type == core::MenuPointerEventType::back)) {
    // A VR user can open a menu while the desktop mirror is behind another
    // application. Native Darktide UI input is foreground-only, so make the
    // already verified unique game window authoritative when the user first
    // performs an action, rather than silently dropping that action.
    ShowWindow(*target, SW_RESTORE);
    SetForegroundWindow(*target);
  }
  if (GetForegroundWindow() != *target) {
    // Mouse-up is global state. If focus changes while our synthetic button is
    // held, release it immediately rather than leaving Windows stuck down.
    if (button_down_) {
      release();
    }
    return false;
  }

  if (event.type == core::MenuPointerEventType::move ||
      event.type == core::MenuPointerEventType::button_down) {
    const auto client = client_rect(*target);
    const auto position =
        client ? map_source_to_absolute_pointer(
                     event.source_x, event.source_y, source_width,
                     source_height, *client, virtual_desktop())
               : std::nullopt;
    if (!position) {
      return false;
    }
    INPUT move{};
    move.type = INPUT_MOUSE;
    move.mi.dx = position->x;
    move.mi.dy = position->y;
    move.mi.dwFlags = MOUSEEVENTF_MOVE | MOUSEEVENTF_ABSOLUTE |
                      MOUSEEVENTF_VIRTUALDESK;
    if (SendInput(1, &move, sizeof(move)) != 1) {
      return false;
    }
    if (event.type == core::MenuPointerEventType::move) {
      return true;
    }
    if (!button_down_ && send_mouse_flags(MOUSEEVENTF_LEFTDOWN)) {
      button_down_ = true;
      return true;
    }
    return button_down_;
  }

  if (event.type == core::MenuPointerEventType::button_up) {
    if (!button_down_) {
      return true;
    }
    if (send_mouse_flags(MOUSEEVENTF_LEFTUP)) {
      button_down_ = false;
      return true;
    }
    return false;
  }
  if (event.type == core::MenuPointerEventType::scroll) {
    const auto delta = static_cast<DWORD>(event.scroll_steps * WHEEL_DELTA);
    return send_mouse_flags(MOUSEEVENTF_WHEEL, delta);
  }
  if (event.type == core::MenuPointerEventType::back) {
    INPUT inputs[2]{};
    inputs[0].type = INPUT_KEYBOARD;
    inputs[0].ki.wVk = VK_ESCAPE;
    inputs[1] = inputs[0];
    inputs[1].ki.dwFlags = KEYEVENTF_KEYUP;
    return SendInput(2, inputs, sizeof(INPUT)) == 2;
  }
  return false;
}

void MenuInputInjector::release() {
  if (button_down_ && send_mouse_flags(MOUSEEVENTF_LEFTUP)) {
    button_down_ = false;
  }
}

}  // namespace darktidevr::harness
