#include "adapters/darktide/observation_gate.h"
#include "adapters/darktide/present_candidates.h"

#include <iostream>
#include <limits>
#include <stdexcept>

namespace {

void expect(bool condition, const char* message) {
  if (!condition) {
    throw std::runtime_error(message);
  }
}

}  // namespace

int main() {
  try {
    using namespace darktidevr::darktide;
    const BuildIdentity known{std::string(kKnownExecutableSha256),
                              std::string(kKnownGameVersion),
                              std::string(kKnownFileVersion)};
    const ObservationRequest allowed{true, true, false, false, false};
    expect(evaluate_observation(known, allowed) ==
               ObservationDecision::allow_metadata_only,
           "Known staged build should allow metadata-only observation");

    auto request = allowed;
    request.eac_session_active = true;
    expect(evaluate_observation(known, request) ==
               ObservationDecision::deny_active_eac_session,
           "Active EAC session must fail closed");
    request = allowed;
    request.process_mutation_requested = true;
    expect(evaluate_observation(known, request) ==
               ObservationDecision::deny_process_mutation,
           "Phase 0 metadata gate must reject mutation");
    request = allowed;
    request.concealment_or_bypass_requested = true;
    expect(evaluate_observation(known, request) ==
               ObservationDecision::deny_prohibited_behavior,
           "Bypass behavior must always be rejected");
    auto unknown = known;
    unknown.executable_sha256[0] = unknown.executable_sha256[0] == '0' ? '1' : '0';
    expect(evaluate_observation(unknown, allowed) ==
               ObservationDecision::deny_unknown_build,
           "Unknown build must fail closed");

    PresentCandidateTracker tracker;
    for (std::uint64_t frame = 0; frame < 240; ++frame) {
      tracker.observe({1, 10, 100, 1920, 1080, 8.33 + (frame % 2) * 0.02,
                       true, true, frame == 120});
      tracker.observe({2, 11, 101, 512, 512, 8.5, true, false, false});
    }
    const auto selection = tracker.select();
    expect(selection.state == CandidateState::selected && selection.candidate,
           "Expected one selected final swapchain");
    expect(selection.candidate->swapchain_id == 1,
           "Foreground full-size swapchain should win");
    expect(selection.candidate->resize_count == 1,
           "Resize telemetry should be retained");

    PresentCandidateTracker noisy_timing;
    noisy_timing.observe({5, 14, 104, 1920, 1080, 0.0, true, true, false});
    noisy_timing.observe(
        {5, 14, 104, 1920, 1080,
         std::numeric_limits<double>::quiet_NaN(), true, true, false});
    noisy_timing.observe({5, 14, 104, 1920, 1080, 10.0, true, true, false});
    noisy_timing.observe({5, 14, 104, 1920, 1080, 20.0, true, true, false});
    const auto noisy_selection = noisy_timing.select(4);
    expect(noisy_selection.state == CandidateState::selected &&
               noisy_selection.candidate,
           "Invalid timing samples must not invalidate a candidate");
    expect(noisy_selection.candidate->mean_interval_ms == 15.0,
           "Invalid timing samples must not skew the timing mean");

    PresentCandidateTracker ambiguous;
    for (int frame = 0; frame < 140; ++frame) {
      ambiguous.observe({3, 12, 102, 1920, 1080, 8.33, true, true, false});
      ambiguous.observe({4, 13, 103, 1920, 1080, 8.33, true, true, false});
    }
    expect(ambiguous.select().state == CandidateState::ambiguous,
           "Eye/auxiliary parity must not be guessed through ambiguity");

    std::cout << "observation_gate.result=pass\n";
    return 0;
  } catch (const std::exception& error) {
    std::cerr << "observation_gate: " << error.what() << '\n';
    return 1;
  }
}
