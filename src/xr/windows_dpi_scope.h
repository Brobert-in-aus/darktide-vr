#pragma once
#include <Windows.h>

namespace darktidevr::harness {
// Capture, source extents and pointer mapping must all use physical pixels.
class ThreadDpiAwarenessScope {
 public:
  ThreadDpiAwarenessScope()
      : previous_(SetThreadDpiAwarenessContext(DPI_AWARENESS_CONTEXT_PER_MONITOR_AWARE_V2)) {}
  ~ThreadDpiAwarenessScope() {
    if (previous_) SetThreadDpiAwarenessContext(previous_);
  }
  ThreadDpiAwarenessScope(const ThreadDpiAwarenessScope&) = delete;
  ThreadDpiAwarenessScope& operator=(const ThreadDpiAwarenessScope&) = delete;
 private:
  DPI_AWARENESS_CONTEXT previous_{};
};
}
