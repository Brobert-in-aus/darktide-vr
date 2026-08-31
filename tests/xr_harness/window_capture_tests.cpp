#include "window_capture.h"

#include <Windows.h>

#include <iostream>
#include <stdexcept>
#include <string_view>

namespace {

constexpr wchar_t kClassName[] = L"DarktideVRWindowCaptureTest";
constexpr wchar_t kTitle[] = L"DarktideVR capture recovery fixture";

LRESULT CALLBACK window_proc(HWND window, UINT message, WPARAM wparam,
                             LPARAM lparam) {
  if (message == WM_PAINT || message == WM_PRINTCLIENT) {
    PAINTSTRUCT paint{};
    const auto dc = message == WM_PAINT
                        ? BeginPaint(window, &paint)
                        : reinterpret_cast<HDC>(wparam);
    RECT client{};
    GetClientRect(window, &client);
    wchar_t title[128]{};
    GetWindowTextW(window, title, 128);
    const auto occluder = std::wstring_view(title).find(L"occluder") !=
                          std::wstring_view::npos;
    const auto brush = CreateSolidBrush(occluder ? RGB(220, 10, 10)
                                                 : RGB(18, 72, 126));
    FillRect(dc, message == WM_PAINT ? &paint.rcPaint : &client, brush);
    DeleteObject(brush);
    if (message == WM_PAINT) {
      EndPaint(window, &paint);
    }
    return 0;
  }
  return DefWindowProcW(window, message, wparam, lparam);
}

void expect(bool condition, const char* message) {
  if (!condition) {
    throw std::runtime_error(message);
  }
}

}  // namespace

int wmain() {
  HWND window{};
  try {
    WNDCLASSEXW window_class{sizeof(WNDCLASSEXW)};
    window_class.lpfnWndProc = window_proc;
    window_class.hInstance = GetModuleHandleW(nullptr);
    window_class.lpszClassName = kClassName;
    if (!RegisterClassExW(&window_class)) {
      throw std::runtime_error("RegisterClassExW failed");
    }
    window = CreateWindowExW(0, kClassName, kTitle, WS_OVERLAPPEDWINDOW,
                             20, 20, 320, 180, nullptr, nullptr,
                             window_class.hInstance, nullptr);
    if (!window) {
      throw std::runtime_error("CreateWindowExW failed");
    }
    ShowWindow(window, SW_SHOW);
    UpdateWindow(window);

    darktidevr::harness::WindowCapture capture(kTitle, 160, 90);
    expect(capture.source_window_alive(),
           "New capture must report its source window alive");
    const auto initial = capture.capture();
    expect(initial.bgra_pixels && initial.width == 160 && initial.height == 90,
           "Visible fixture should capture at requested dimensions");
    const auto idle_overlay_swatch = initial.bgra_pixels +
        (static_cast<std::size_t>(89) * 160 + 159) * 4;
    expect(idle_overlay_swatch[0] == std::byte{255} &&
               idle_overlay_swatch[1] == std::byte{255} &&
               idle_overlay_swatch[2] == std::byte{0} &&
               idle_overlay_swatch[3] == std::byte{255},
           "Capture did not publish its always-available XR overlay swatch");
    RECT expected_client{};
    expect(GetClientRect(window, &expected_client) != FALSE,
           "Fixture client extent must be readable");
    const auto source_extent = capture.source_extent();
    expect(source_extent &&
               source_extent->first == static_cast<std::uint32_t>(
                                           expected_client.right) &&
               source_extent->second == static_cast<std::uint32_t>(
                                            expected_client.bottom),
           "Capture must expose the physical client aspect to the XR panel");

    const auto occluder = CreateWindowExW(
        WS_EX_TOPMOST, kClassName, L"DarktideVR capture occluder",
        WS_POPUP | WS_VISIBLE, 20, 20, 320, 180, nullptr, nullptr,
        window_class.hInstance, nullptr);
    expect(occluder != nullptr, "Could not create capture occluder");
    InvalidateRect(occluder, nullptr, TRUE);
    UpdateWindow(occluder);
    const auto occluded = capture.capture();
    const auto fixture_centre = occluded.bgra_pixels +
                                (static_cast<std::size_t>(45) * 160 + 80) * 4;
    expect(fixture_centre[0] == std::byte{126} &&
               fixture_centre[1] == std::byte{72} &&
               fixture_centre[2] == std::byte{18},
           "Occluding window leaked into the captured client surface");
    DestroyWindow(occluder);
    capture.set_source_crop(320, 180, 0, 0, 160, 90);
    capture.set_pointer_overlay(std::pair{80U, 45U}, 320, 180);
    const auto with_pointer = capture.capture();
    const auto centre = with_pointer.bgra_pixels +
                        (static_cast<std::size_t>(45) * 160 + 80) * 4;
    expect(centre[0] == std::byte{255} && centre[1] == std::byte{255} &&
               centre[2] == std::byte{255},
           "Pointer overlay was not visible at the mapped source position");
    const auto cyan_ring = with_pointer.bgra_pixels +
                           (static_cast<std::size_t>(45) * 160 + 95) * 4;
    expect(cyan_ring[0] == std::byte{255} &&
               cyan_ring[1] == std::byte{220} &&
               cyan_ring[2] == std::byte{0},
           "Pointer overlay ring did not use its high-contrast colour");
    const auto laser_swatch = with_pointer.bgra_pixels +
                              (static_cast<std::size_t>(89) * 160 + 159) * 4;
    expect(laser_swatch[0] == std::byte{255} &&
               laser_swatch[1] == std::byte{255} &&
               laser_swatch[2] == std::byte{0} &&
               laser_swatch[3] == std::byte{255},
           "Pointer overlay did not preserve its OpenXR overlay swatch");
    capture.set_pointer_overlay(std::nullopt, 160, 90);

    ShowWindow(window, SW_MINIMIZE);
    bool minimized_rejected{};
    try {
      static_cast<void>(capture.capture());
    } catch (const std::runtime_error&) {
      minimized_rejected = true;
    }
    expect(minimized_rejected,
           "Minimized fixture must be reported as temporarily unavailable");

    ShowWindow(window, SW_RESTORE);
    UpdateWindow(window);
    const auto restored = capture.capture();
    expect(restored.bgra_pixels && restored.row_pitch == 160 * 4,
           "Restored fixture should resume capture without reconstruction");

    DestroyWindow(window);
    window = nullptr;
    expect(!capture.source_window_alive(),
           "Destroyed source window must be reported unavailable");
    UnregisterClassW(kClassName, window_class.hInstance);
    std::cout << "window_capture_recovery.result=pass\n";
    return 0;
  } catch (const std::exception& error) {
    if (window) {
      DestroyWindow(window);
    }
    std::cerr << "window_capture_recovery: " << error.what() << '\n';
    return 1;
  }
}
