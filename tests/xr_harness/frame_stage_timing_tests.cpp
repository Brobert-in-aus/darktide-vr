#include "core/frame_stage_timing.h"

#include <cstdlib>
#include <iostream>
#include <limits>
#include <sstream>

namespace {
void require(bool condition, const char* message) {
  if (!condition) { std::cerr << message << '\n'; std::exit(1); }
}
}

int main() {
  using darktidevr::core::FrameStage;
  darktidevr::core::FrameStageTiming timing;
  // Waits can occur twice per frame, and early runtime frames may not render.
  // Counts must describe observed calls rather than treating absent calls as 0.
  timing.sample(FrameStage::ActiveLoop, 10);
  timing.sample(FrameStage::ActiveLoop, 20);
  timing.sample(FrameStage::WaitFrame, 1.25);
  timing.sample(FrameStage::WaitFrame, 2.75);
  timing.sample(FrameStage::SwapchainAcquireWait, 0);
  timing.sample(FrameStage::SwapchainAcquireWait, 0.125);
  timing.sample(FrameStage::SwapchainAcquireWait, 0.375);
  for (int i=0; i<3; ++i) timing.sample(FrameStage::PairPollSleep, 0.75);
  auto rows=timing.samples();
  require(rows[0].count==2 && rows[0].mean_ms()==15 && rows[0].maximum_ms==20,
          "active-loop window aggregate is wrong");
  const auto swap=static_cast<std::size_t>(FrameStage::SwapchainAcquireWait);
  require(rows[swap].count==3 && rows[swap].total_ms==0.5,
          "multiple waits and measured zero must retain their own count");
  timing.sample(FrameStage::WaitFrame, -1);
  timing.sample(FrameStage::WaitFrame, std::numeric_limits<double>::quiet_NaN());
  timing.sample(FrameStage::WaitFrame, std::numeric_limits<double>::infinity());
  timing.sample(FrameStage::Count, 1);
  require(timing.invalid_samples()==4, "invalid durations/index must be explicit");
  require(timing.samples()[static_cast<std::size_t>(FrameStage::WaitFrame)].count==2,
          "invalid durations must not contaminate the valid mean");
  std::ostringstream output;
  timing.write(output, 120, 10000000, "standard");
  const auto text=output.str();
  require(text.find("scope=cpu_wall")!=std::string::npos, "timing scope missing");
  require(text.find("window_end_frame=120 last_display_period_ms=10")!=std::string::npos,
          "window identity and latest runtime period must be explicit");
  require(text.find("gpu_fence_samples=0")!=std::string::npos &&
          text.find("gpu_fence_mean=")==std::string::npos,
          "unobserved GPU wait must not become a measured zero");
  require(text.find("wait_frame_mean=2")!=std::string::npos, "fractional mean lost");
  require(text.find("pair_wait_mode=standard")!=std::string::npos &&
          text.find("pair_poll_sleep_samples=3 pair_poll_sleep_mean=0.75")!=std::string::npos,
          "poll count and selected wait mode must be retained");
  timing.reset();
  require(timing.invalid_samples()==0, "reset must start a new independent window");
  for(const auto& row:timing.samples()) require(row.count==0 && row.total_ms==0 &&
      row.maximum_ms==0, "prior window leaked");
  timing.sample(FrameStage::WaitFrame, std::numeric_limits<double>::max());
  timing.sample(FrameStage::WaitFrame, std::numeric_limits<double>::max());
  require(timing.invalid_samples()==1, "aggregate overflow must be rejected");
  std::cout << "frame_stage_timing=pass\n";
}
