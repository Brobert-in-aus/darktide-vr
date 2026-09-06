#pragma once

namespace darktidevr::core {
// Observe every measured Present, not just the end of the health interval.
// An away-and-back transition otherwise looks like uninterrupted foreground.
struct PresentFocusWindow {
  bool initialized{}, last_foreground{};
  unsigned changes{};

  void observe(bool foreground) {
    if (initialized && foreground != last_foreground) ++changes;
    initialized = true;
    last_foreground = foreground;
  }
  void clear_window() { changes = 0; }
};
}
