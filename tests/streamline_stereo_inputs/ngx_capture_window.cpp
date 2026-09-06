#include "producer/ngx_capture_window.h"
#include <iostream>
#include <limits>
#include <stdexcept>

void expect(bool value) { if (!value) throw std::runtime_error("NGX window invariant failed"); }
int main() {
  using darktidevr::producer::NgxCaptureWindow;
  NgxCaptureWindow window;
  window.configure(true);
  for (auto call : {1ULL, 32768ULL, 1000000ULL})
    expect(!window.snapshot(call, 32768).eligible);
  expect(!window.open(0, 9, 1000000));
  expect(!window.open(1, 0, 1000000));
  expect(window.open(1, 12131, 1000000));
  expect(!window.snapshot(1000000, 32768).eligible);
  const auto first = window.snapshot(1000001, 32768);
  expect(first.eligible && first.batch == 1 && first.present == 12131 && first.first_call == 1000000);
  expect(window.snapshot(1032768, 32768).eligible);
  expect(!window.snapshot(1032769, 32768).eligible);
  expect(!window.open(2, 12134, 1032769));
  expect(!window.snapshot(1032770, 32768).eligible);
  expect(first.batch == 1 && first.present == 12131); // Captured context stays immutable.
  window.configure(false);
  expect(window.snapshot(1, 32768).eligible);
  expect(!window.open(1, 2, 4));
  expect(!window.snapshot(32769, 32768).eligible);
  window.configure(true);
  constexpr auto maximum = std::numeric_limits<std::uint64_t>::max();
  expect(window.open(1, 2, maximum-1));
  expect(window.snapshot(maximum, 32768).eligible);
  expect(!window.snapshot(0, 32768).eligible);
  std::cout << "ngx_capture_window=pass startup bounded no_rearm overflow\n";
}
