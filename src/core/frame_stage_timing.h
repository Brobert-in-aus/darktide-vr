#pragma once

#include <algorithm>
#include <array>
#include <chrono>
#include <cmath>
#include <cstdint>
#include <ostream>

namespace darktidevr::core {

// CPU-observed wall time around calls, not GPU timestamps or display latency.
enum class FrameStage : std::size_t {
  ActiveLoop, PairWait, WaitFrame, BeginFrame, Tracking,
  SwapchainAcquireWait, GpuFence, EndFrame, Count
};

struct FrameStageSample {
  std::uint64_t count{};
  double total_ms{};
  double maximum_ms{};
  [[nodiscard]] double mean_ms() const noexcept {
    return count ? total_ms / static_cast<double>(count) : 0;
  }
};

class FrameStageTiming {
 public:
  using Clock = std::chrono::steady_clock;
  static constexpr std::size_t kCount = static_cast<std::size_t>(FrameStage::Count);

  void sample(FrameStage stage, double milliseconds) noexcept {
    const auto index = static_cast<std::size_t>(stage);
    if (index >= kCount || !std::isfinite(milliseconds) || milliseconds < 0) {
      ++invalid_samples_;
      return;
    }
    auto& row = samples_[index];
    if (!std::isfinite(row.total_ms + milliseconds)) {
      ++invalid_samples_;
      return;
    }
    ++row.count;
    row.total_ms += milliseconds;
    row.maximum_ms = (std::max)(row.maximum_ms, milliseconds);
  }

  void elapsed(FrameStage stage, Clock::time_point began) noexcept {
    sample(stage, std::chrono::duration<double, std::milli>(Clock::now()-began).count());
  }

  [[nodiscard]] const auto& samples() const noexcept { return samples_; }
  [[nodiscard]] std::uint64_t invalid_samples() const noexcept { return invalid_samples_; }

  void write(std::ostream& output, std::uint64_t completed_frames,
             std::int64_t last_display_period_ns) const {
    static constexpr std::array<const char*, kCount> names{
        "active_loop", "pair_wait", "wait_frame", "begin_frame", "tracking",
        "swapchain_acquire_wait", "gpu_fence", "end_frame"};
    output << "openxr.frame_stage_timing clock=steady units=ms scope=cpu_wall"
           << " window_end_frame=" << completed_frames
           << " last_display_period_ms=" << static_cast<double>(last_display_period_ns)/1.0e6
           << " invalid_samples=" << invalid_samples_;
    for (std::size_t i=0; i<kCount; ++i) {
      const auto& row=samples_[i];
      output << ' ' << names[i] << "_samples=" << row.count;
      // Omit durations when no call was observed; zero means a measured zero.
      if (row.count) output << ' ' << names[i] << "_mean=" << row.mean_ms()
                            << ' ' << names[i] << "_max=" << row.maximum_ms;
    }
    output << '\n';
  }

  void reset() noexcept { samples_={}; invalid_samples_=0; }

 private:
  std::array<FrameStageSample,kCount> samples_{};
  std::uint64_t invalid_samples_{};
};

}  // namespace darktidevr::core
