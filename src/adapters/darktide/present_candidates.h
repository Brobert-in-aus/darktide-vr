#pragma once

#include <cstdint>
#include <optional>
#include <unordered_map>

namespace darktidevr::darktide {

struct PresentObservation {
  std::uintptr_t swapchain_id{};
  std::uintptr_t queue_id{};
  std::uintptr_t window_id{};
  std::uint32_t width{};
  std::uint32_t height{};
  double interval_ms{};
  bool window_visible{};
  bool window_foreground{};
  bool resized{};
};

struct PresentCandidate {
  std::uintptr_t swapchain_id{};
  std::uintptr_t queue_id{};
  std::uintptr_t window_id{};
  std::uint32_t width{};
  std::uint32_t height{};
  std::uint64_t present_count{};
  std::uint64_t resize_count{};
  double mean_interval_ms{};
  double interval_stddev_ms{};
};

enum class CandidateState { no_candidate, ambiguous, selected };

struct CandidateSelection {
  CandidateState state{CandidateState::no_candidate};
  std::optional<PresentCandidate> candidate;
};

class PresentCandidateTracker {
 public:
  void observe(const PresentObservation& observation);
  CandidateSelection select(std::uint64_t minimum_presents = 120) const;
  std::size_t candidate_count() const { return candidates_.size(); }

 private:
  struct Statistics {
    PresentCandidate candidate;
    std::uint64_t interval_sample_count{};
    double interval_m2{};
    bool visible{};
    bool foreground{};
  };

  std::unordered_map<std::uintptr_t, Statistics> candidates_;
};

}  // namespace darktidevr::darktide
