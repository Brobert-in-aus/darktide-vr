#include "../isolated_transports.h"
#include "core/shared_presentation_state.h"

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
    using namespace darktidevr::core;
    expect(immersive_projection_active(
               SharedPresentationMode::stereo_world) &&
               immersive_projection_active(SharedPresentationMode::flat_menu) &&
               immersive_projection_active(
                   SharedPresentationMode::world_anchored_menu),
           "Interactive menu overlays must retain immersive projection");
    expect(!immersive_projection_active(
               SharedPresentationMode::flat_loading_or_cinematic) &&
               !immersive_projection_active(
                   SharedPresentationMode::flat_interactive) &&
               !immersive_projection_active(
                   SharedPresentationMode::flat_interactive_native_aspect) &&
               !immersive_projection_active(SharedPresentationMode::disabled),
           "Only non-immersive modes may release projection ownership");
    expect(flat_interactive_active(SharedPresentationMode::flat_interactive) &&
               flat_interactive_active(
                   SharedPresentationMode::flat_interactive_native_aspect) &&
               !flat_interactive_active(SharedPresentationMode::flat_menu),
           "Both flat-interactive aspect policies must share input ownership");
    expect(flat_interactive_uses_eye_aspect(
               SharedPresentationMode::flat_interactive, true) &&
               !flat_interactive_uses_eye_aspect(
                   SharedPresentationMode::flat_interactive, false) &&
               !flat_interactive_uses_eye_aspect(
                   SharedPresentationMode::flat_interactive_native_aspect,
                   true),
           "Only an attached eye-encoded panel may use portrait eye aspect");
    SharedPresentationState loading_anchor{
        1, SharedPresentationMode::flat_loading_or_cinematic, 1920, 1080,
        0, 0, 1920, 1080, 2.0F, 2.0F};
    loading_anchor.transport_generation = 4;
    auto loading_heartbeat = loading_anchor;
    loading_heartbeat.sequence = 2;
    loading_heartbeat.published_at_ms = 1000;
    loading_heartbeat.source_width = 1280;
    loading_heartbeat.source_height = 720;
    loading_heartbeat.crop_width = 1280;
    loading_heartbeat.crop_height = 720;
    expect(same_flat_panel_anchor_identity(loading_anchor,
                                           loading_heartbeat),
           "Heartbeat and source-extent updates must not recenter a flat panel");
    loading_heartbeat.mode = SharedPresentationMode::flat_interactive;
    expect(!same_flat_panel_anchor_identity(loading_anchor,
                                            loading_heartbeat),
           "A semantic panel-mode transition must establish a new anchor");
    loading_heartbeat = loading_anchor;
    ++loading_heartbeat.transport_generation;
    expect(!same_flat_panel_anchor_identity(loading_anchor,
                                            loading_heartbeat),
           "A restarted presentation transport must establish a new anchor");
    SharedPresentationState body_anchor = loading_anchor;
    body_anchor.mode = SharedPresentationMode::world_anchored_menu;
    body_anchor.body_panel_pose_valid = true;
    body_anchor.body_panel_pose = {
        {0.0F, 0.0F, 0.0F, 1.0F}, {0.0F, 1.6F, -1.0F}};
    auto moved_body_anchor = body_anchor;
    moved_body_anchor.sequence = 3;
    moved_body_anchor.body_panel_pose.position.x = 0.25F;
    expect(!same_flat_panel_anchor_identity(body_anchor, moved_body_anchor),
           "A changed authored body anchor must update its world-space panel");
    SharedPresentationStateReader reader;
    std::uint64_t first_generation{};
    {
      SharedPresentationStateWriter writer;
      SharedPresentationState state{7,
                                    SharedPresentationMode::flat_menu,
                                    1920,
                                    1080,
                                    80,
                                    40,
                                    1760,
                                    1000,
                                    2.0F,
                                    2.0F};
      expect(writer.publish(state), "Valid menu state should publish");
      SharedPresentationState observed{};
      expect(reader.read(observed), "Published menu state should be readable");
      expect(observed.sequence == 7 &&
                 observed.transport_generation != 0 &&
                 observed.published_at_ms != 0 &&
                 observed.mode == SharedPresentationMode::flat_menu &&
                 observed.crop_x == 80 && observed.crop_width == 1760,
             "Reader should preserve the complete packet");
      expect(presentation_state_fresh(observed, observed.published_at_ms + 500,
                                      500) &&
                 !presentation_state_fresh(
                     observed, observed.published_at_ms + 501, 500),
             "Presentation heartbeat freshness must expire at its age bound");
      first_generation = observed.transport_generation;

      state.sequence = 8;
      state.crop_width = 1920;
      expect(!writer.publish(state), "Out-of-bounds crop must fail closed");
      state.crop_x = 0;
      state.crop_width = 1921;
      expect(!writer.publish(state),
             "Crop width larger than its source must not underflow validation");
      state.crop_width = 1760;
      state.crop_height = 1081;
      expect(!writer.publish(state),
             "Crop height larger than its source must not underflow validation");

      state = {9,
               SharedPresentationMode::world_anchored_menu,
               1920,
               1080,
               0,
               0,
               1920,
               1080,
               2.0F,
               2.0F,
               true,
               {{0.0F, 0.0F, 0.0F, 1.0F}, {1.0F, 2.0F, 1.5F}}};
      expect(writer.publish(state), "Valid world-anchored menu should publish");
      expect(reader.read(observed) && observed.body_panel_pose_valid &&
                 observed.body_panel_pose.position.y == 2.0F,
             "Reader should preserve the body-relative panel pose");
      state.body_panel_pose_valid = false;
      expect(!writer.publish(state),
             "World-anchored menu without a pose must fail closed");

      state = {10,
               SharedPresentationMode::flat_interactive,
               1920,
               1080,
               0,
               0,
               1920,
               1080,
               2.0F,
               2.0F};
      expect(writer.publish(state),
             "Valid flat interactive panel should publish");
      expect(reader.read(observed) &&
                 observed.mode == SharedPresentationMode::flat_interactive &&
                 !observed.body_panel_pose_valid,
             "Reader should preserve flat interactive mode");

      state.sequence = 11;
      state.mode = SharedPresentationMode::flat_interactive_native_aspect;
      expect(writer.publish(state),
             "Valid native-aspect interactive panel should publish");
      expect(reader.read(observed) &&
                 observed.mode ==
                     SharedPresentationMode::flat_interactive_native_aspect,
             "Reader should preserve native-aspect interactive mode");
    }

    SharedPresentationState restarted{};
    {
      SharedPresentationStateWriter writer;
      SharedPresentationState state{11,
                                    SharedPresentationMode::flat_menu,
                                    1280,
                                    720,
                                    0,
                                    0,
                                    1280,
                                    720,
                                    2.0F,
                                    2.0F};
      expect(writer.publish(state),
             "Restarted writer should publish a repeated sequence");
      expect(reader.read(restarted),
             "Reader should observe the restarted writer generation");
    }
    expect(restarted.sequence == 11 &&
               restarted.transport_generation == first_generation + 1 &&
               restarted.mode == SharedPresentationMode::flat_menu,
           "Writer generation must disambiguate a repeated restart sequence");

    std::cout << "presentation_state_transport.result=pass\n";
    return 0;
  } catch (const std::exception& error) {
    std::cerr << "presentation_state_transport: " << error.what() << '\n';
    return 1;
  }
}
