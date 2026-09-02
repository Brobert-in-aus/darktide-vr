#include "core/shared_head_pose.h"

#include <Windows.h>

#include <chrono>
#include <cstdint>
#include <iostream>
#include <memory>
#include <stdexcept>
#include <string>
#include <thread>

namespace {

struct HandleCloser {
  void operator()(void* handle) const noexcept {
    if (handle) {
      CloseHandle(handle);
    }
  }
};

using UniqueHandle = std::unique_ptr<void, HandleCloser>;

void print_usage() {
  std::wcout << L"Usage: darktidevr-synthetic-head-publisher "
                L"[--seconds N]\n";
}

}  // namespace

int wmain(int argc, wchar_t** argv) {
  try {
    unsigned seconds = 60;
    for (int index = 1; index < argc; ++index) {
      const std::wstring argument = argv[index];
      if (argument == L"--help") {
        print_usage();
        return 0;
      }
      if (argument == L"--seconds" && index + 1 < argc) {
        seconds = static_cast<unsigned>(std::stoul(argv[++index]));
        if (seconds == 0 || seconds > 46'000) {
          throw std::invalid_argument("--seconds must be between 1 and 46000");
        }
        continue;
      }
      print_usage();
      return 2;
    }

    UniqueHandle mutex(CreateMutexW(
        nullptr, FALSE, L"Local\\DarktideVR-synthetic-head-publisher-v1"));
    if (!mutex || WaitForSingleObject(mutex.get(), 0) != WAIT_OBJECT_0) {
      std::cerr << "synthetic_head.publisher=busy\n";
      return 3;
    }

    darktidevr::core::SharedHeadPoseWriter writer;
    darktidevr::core::SharedHeadPoseSample sample{};
    sample.recenter_generation = 1;
    sample.pose.orientation.w = 1.0F;
    sample.render_vertical_fov_radians = 1.727876F;
    sample.render_aspect_ratio = 2112.0F / 2304.0F;
    sample.render_width = 2112;
    sample.render_height = 2304;
    // Exact VirtualDesktopXR Medium frusta retained by the accepted runtime
    // baseline. They exercise Darktide's recentered symmetric optical-camera
    // rotations while leaving the synthetic head itself motionless.
    sample.render_frusta[0] =
        {-0.942478F, 0.698132F, -0.959931F, 0.767945F};
    sample.render_frusta[1] =
        {-0.698132F, 0.942478F, -0.959931F, 0.767945F};
    sample.ipd_metres = 0.064F;

    std::cout << "synthetic_head.publisher=active profile=vdxr_medium"
                 " width=2112 height=2304 seconds="
              << seconds << '\n';
    const auto deadline =
        std::chrono::steady_clock::now() + std::chrono::seconds(seconds);
    auto next_publish = std::chrono::steady_clock::now();
    constexpr auto cadence = std::chrono::microseconds(8'333);
    while (std::chrono::steady_clock::now() < deadline) {
      sample.sequence += 1;
      if (!writer.publish(sample)) {
        throw std::runtime_error("Shared head-pose publication failed");
      }
      next_publish += cadence;
      std::this_thread::sleep_until(next_publish);
    }
    std::cout << "synthetic_head.publisher=complete samples="
              << sample.sequence << '\n';
    ReleaseMutex(mutex.get());
    return 0;
  } catch (const std::exception& error) {
    std::cerr << "synthetic_head.publisher=error message=" << error.what()
              << '\n';
    return 1;
  }
}
