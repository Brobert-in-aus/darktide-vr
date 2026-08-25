#include "adapters/darktide/present_candidates.h"

#include <algorithm>
#include <cmath>
#include <vector>

namespace darktidevr::darktide {

void PresentCandidateTracker::observe(const PresentObservation& observation) {
  if (observation.swapchain_id == 0) {
    return;
  }
  auto& statistics = candidates_[observation.swapchain_id];
  auto& candidate = statistics.candidate;
  candidate.swapchain_id = observation.swapchain_id;
  candidate.queue_id = observation.queue_id;
  candidate.window_id = observation.window_id;
  candidate.width = observation.width;
  candidate.height = observation.height;
  candidate.resize_count += observation.resized ? 1U : 0U;
  statistics.visible = observation.window_visible;
  statistics.foreground = observation.window_foreground;

  ++candidate.present_count;
  if (observation.interval_ms > 0.0 && std::isfinite(observation.interval_ms)) {
    ++statistics.interval_sample_count;
    const auto count = static_cast<double>(statistics.interval_sample_count);
    const auto delta = observation.interval_ms - candidate.mean_interval_ms;
    candidate.mean_interval_ms += delta / count;
    const auto delta_after = observation.interval_ms - candidate.mean_interval_ms;
    statistics.interval_m2 += delta * delta_after;
    if (statistics.interval_sample_count > 1) {
      candidate.interval_stddev_ms = std::sqrt(
          statistics.interval_m2 /
          static_cast<double>(statistics.interval_sample_count - 1));
    }
  }
}

CandidateSelection PresentCandidateTracker::select(
    std::uint64_t minimum_presents) const {
  struct Ranked {
    const Statistics* statistics{};
    double score{};
  };
  std::vector<Ranked> ranked;
  for (const auto& [id, statistics] : candidates_) {
    static_cast<void>(id);
    const auto& candidate = statistics.candidate;
    if (candidate.present_count < minimum_presents || candidate.queue_id == 0 ||
        candidate.window_id == 0 || candidate.width < 640 ||
        candidate.height < 480 || !statistics.visible) {
      continue;
    }
    const auto pixels = static_cast<double>(candidate.width) * candidate.height;
    const auto foreground_bonus = statistics.foreground ? 4.0 : 1.0;
    const auto stability = 1.0 / (1.0 + candidate.interval_stddev_ms);
    ranked.push_back({&statistics, pixels * foreground_bonus * stability});
  }
  if (ranked.empty()) {
    return {};
  }
  std::sort(ranked.begin(), ranked.end(),
            [](const Ranked& left, const Ranked& right) {
              return left.score > right.score;
            });
  if (ranked.size() > 1 && ranked[1].score >= ranked[0].score * 0.95) {
    return {CandidateState::ambiguous, std::nullopt};
  }
  return {CandidateState::selected, ranked[0].statistics->candidate};
}

}  // namespace darktidevr::darktide
