#include "window_capture.h"

#include <Windows.h>

#include <iostream>
#include <stdexcept>

namespace {

constexpr wchar_t kClassName[] = L"DarktideVRWindowCaptureTest";
constexpr wchar_t kTitle[] = L"DarktideVR capture recovery fixture";

LRESULT CALLBACK window_proc(HWND window, UINT message, WPARAM wparam,
                             LPARAM lparam) {
  if (message == WM_PAINT) {
    PAINTSTRUCT paint{};
    const auto dc = BeginPaint(window, &paint);
    const auto brush = CreateSolidBrush(RGB(18, 72, 126));
    FillRect(dc, &paint.rcPaint, brush);
    DeleteObject(brush);
    EndPaint(window, &paint);
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
    const auto initial = capture.capture();
    expect(initial.bgra_pixels && initial.width == 160 && initial.height == 90,
           "Visible fixture should capture at requested dimensions");

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
