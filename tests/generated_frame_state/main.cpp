#include "../isolated_transports.h"
#include "core/shared_generated_frame_state.h"
#include "core/generated_frame_cadence.h"
#include "core/present_focus_window.h"
#include "core/continuous_frame_trace.h"

#include <cstdint>
#include <iostream>
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
    darktidevr::tests::isolate_transports();
    using darktidevr::core::trace_continuous_frame;
    expect(!trace_continuous_frame(true, 0), "An unstarted frame is not a trace sample");
    unsigned sampled = 0;
    for (std::uint64_t frame = 1; frame <= 1200; ++frame) {
      expect(trace_continuous_frame(false, frame), "Bounded probes must retain every frame");
      if (trace_continuous_frame(true, frame)) ++sampled;
    }
    expect(sampled == 18 && trace_continuous_frame(true, 8) &&
           !trace_continuous_frame(true, 9) && !trace_continuous_frame(true, 119) &&
           trace_continuous_frame(true, 120) && !trace_continuous_frame(true, 121),
           "Persistent tracing must preserve startup and periodic frame evidence");
    darktidevr::core::PresentFocusWindow focus;
    focus.observe(true); focus.observe(true);
    expect(focus.changes == 0, "Initial foreground samples are not transitions");
    focus.observe(false); focus.observe(true);
    expect(focus.changes == 2 && focus.last_foreground,
           "Away-and-back within one health window must be observable");
    focus.clear_window(); focus.observe(true);
    expect(focus.changes == 0, "A settled following window must start clean");
    focus.clear_window(); focus.observe(false);
    expect(focus.changes == 1, "Window reset must retain the last observed focus");
    darktidevr::core::GeneratedFrameCadence cadence;
    cadence.observe_source(100'000'000);
    cadence.observe_source(132'000'000);
    cadence.generated(140'000'000,8'000'000);
    expect(!cadence.original_ready(148'000'000) && cadence.original_ready(156'000'000),
           "30-ish Hz source at 120-ish Hz display must space distinct images two slots apart");
    cadence = {};
    cadence.observe_source(100'000'000);
    cadence.observe_source(116'000'000);
    cadence.generated(124'000'000,8'000'000);
    expect(cadence.original_ready(132'000'000), "60-ish Hz source should use adjacent display slots");
    cadence.observe_source(1'000'000'000);
    cadence.generated(1'008'000'000,11'111'111);
    expect(cadence.source_period == 0 && cadence.original_ready(1'019'111'111),
           "A loading gap must reset cadence and use the current runtime period");
    using darktidevr::core::SharedGeneratedFrameState;
    using darktidevr::core::SharedGeneratedFrameStateReader;
    using darktidevr::core::SharedGeneratedFrameStateWriter;
    using darktidevr::core::generated_frame_slot;
    using darktidevr::core::valid_generated_frame_state;

    expect(generated_frame_slot(1) == 0 && generated_frame_slot(2) == 1 &&
               generated_frame_slot(3) == 2 && generated_frame_slot(4) == 0,
           "Generated frame sequences must cycle through three slots");

    SharedGeneratedFrameState invalid{};
    expect(!valid_generated_frame_state(invalid),
           "An empty generated frame state must be invalid");

    SharedGeneratedFrameStateWriter writer;
    SharedGeneratedFrameStateReader reader;
    expect(!writer.publish(0, 10, 20, 2496, 2688, 28),
           "Sequence zero must be rejected");
    expect(!writer.publish(1, 0, 20, 2496, 2688, 28),
           "Native call zero must be rejected");

    for (std::uint64_t sequence = 1; sequence <= 5; ++sequence) {
      const auto native_call = sequence + 4000;
      const auto frame_index = static_cast<std::uint32_t>(sequence + 9000);
      expect(writer.publish(sequence, native_call, frame_index, 2496, 2688,
                            28,sequence+100,sequence+101,4,sequence+200,sequence+300),
             "Valid generated frame publication failed");
      SharedGeneratedFrameState read{};
      expect(reader.read(read), "Generated frame reader failed");
      const auto& slot = read.slots[generated_frame_slot(sequence)];
      expect(read.transport_generation != 0 &&
                 read.latest_sequence == sequence && read.width == 2496 &&
                 read.height == 2688 && read.format == 28 &&
                 slot.sequence == sequence &&
                 slot.native_call == native_call &&
                 slot.frame_index == frame_index && slot.previous_pose == sequence+100 &&
                 slot.current_pose == sequence+101 && slot.gameplay_generation == 4 &&
                 slot.tick_ms == sequence+200 && slot.rendered_ready == sequence+300,
             "Generated frame metadata did not round-trip");
    }

    SharedGeneratedFrameStateWriter restarted_writer;
    SharedGeneratedFrameStateWriter original_writer{L"Local\\DarktideVR-test-original-frame-state"};
    SharedGeneratedFrameStateReader original_reader{L"Local\\DarktideVR-test-original-frame-state"};
    expect(original_writer.publish(1,99,0,2496,2688,28,0,111,4,222,1),"Original channel publish failed");
    SharedGeneratedFrameState original_channel{};
    expect(original_reader.read(original_channel) && original_channel.slots[0].native_call==99,
           "Original metadata must use its own mapping");
    expect(restarted_writer.publish(1, 1, 1, 2496, 2688, 28),
           "Restarted writer publication failed");
    SharedGeneratedFrameState restarted{};
    expect(reader.read(restarted) && restarted.latest_sequence == 1 &&
               restarted.transport_generation >= 2,
           "Writer restart must advance generation and reset sequence");

    std::cout << "generated_frame_state=pass\n";
    return 0;
  } catch (const std::exception& error) {
    std::cerr << error.what() << '\n';
    return 1;
  }
}
