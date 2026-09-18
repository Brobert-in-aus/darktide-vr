// The render-target census that decides where the shading rate belongs.
//
// Foveation reduces shading work, so the rate has to go on the passes that
// shade. Two plausible guesses are both wrong here: the eye final is the
// resolved output and the work is already done by the time it is bound, and
// the main passes run at the DLSS internal resolution rather than the eye
// extent, so matching the eye's size would miss them. This counts instead, and
// the counting has to be right or the first thing it decides is wrong.

#include "producer/foveation_census.h"

#include <cstring>
#include <iostream>
#include <stdexcept>
#include <string>
#include <vector>

namespace {

using darktidevr::producer::FoveationCensus;

void require(bool condition, const std::string& message) {
  if (!condition) {
    throw std::runtime_error(message);
  }
}

std::string written(const FoveationCensus& census) {
  std::vector<char> buffer(16384, '\0');
  const auto count = census.write(buffer.data(),
                                  static_cast<int>(buffer.size()) - 1);
  return std::string(buffer.data(), static_cast<std::size_t>(count));
}

const int kListA = 0;
const int kListB = 0;

// The target and the viewport arrive from two different hooks, so a fixture
// that sets both is what a real pass looks like.
void bind_at(FoveationCensus& census, const void* list, std::uint32_t width,
             std::uint32_t height, std::uint32_t format,
             std::uint32_t viewport_width, std::uint32_t viewport_height,
             const char* marker) {
  census.bind(list, width, height, format, marker);
  census.viewport(list, viewport_width, viewport_height);
}

void draws_are_charged_to_the_target_that_was_bound() {
  FoveationCensus census;
  const void* list = &kListA;
  bind_at(census, list, 1280, 1440, 10, 1280, 1440, "gbuffer");
  census.draw(list, 300, 1);
  census.draw(list, 150, 2);
  bind_at(census, list, 1920, 2160, 28, 1920, 2160, "eye_final");
  census.draw(list, 6, 1);

  require(census.size() == 2, "two distinct shapes were bound");
  const auto text = written(census);
  require(text.find("shape=1280x1440 viewport=1280x1440 format=10 binds=1 draws=2 vertices=600")
              != std::string::npos,
          "the gbuffer's draws and primitives: " + text);
  require(text.find("shape=1920x2160 viewport=1920x2160 format=28 binds=1 draws=1 vertices=6")
              != std::string::npos,
          "the eye final's single blit: " + text);
  require(census.unattributed_draws() == 0, "every draw found a target");
}

void the_busiest_shape_is_reported_first() {
  // The point of the census is to answer "where does the shading go", so the
  // answer must be the first line rather than somewhere in a list of
  // twenty-four.
  FoveationCensus census;
  const void* list = &kListA;
  bind_at(census, list, 1920, 2160, 28, 1920, 2160, "eye_final");
  census.draw(list, 6, 1);
  bind_at(census, list, 1280, 1440, 10, 1280, 1440, "gbuffer");
  for (int i = 0; i < 500; ++i) {
    census.draw(list, 900, 1);
  }
  const auto text = written(census);
  const auto gbuffer = text.find("shape=1280x1440");
  const auto final_target = text.find("shape=1920x2160");
  require(gbuffer != std::string::npos && final_target != std::string::npos,
          "both shapes reported");
  require(gbuffer < final_target,
          "the shape carrying the draws must be reported first, not the one "
          "that happens to match the eye extent");
}

void several_command_lists_record_at_once() {
  // The engine records on several threads. Attributing every draw to whatever
  // was bound last ANYWHERE would put the whole frame on one pass.
  FoveationCensus census;
  const void* first = &kListA;
  const void* second = &kListB;
  bind_at(census, first, 1280, 1440, 10, 1280, 1440, "gbuffer");
  bind_at(census, second, 512, 512, 55, 512, 512, "shadow");
  census.draw(first, 100, 1);
  census.draw(second, 7, 1);
  census.draw(first, 100, 1);
  const auto text = written(census);
  require(text.find("shape=1280x1440 viewport=1280x1440 format=10 binds=1 draws=2 vertices=200")
              != std::string::npos,
          "the first list kept its own target: " + text);
  require(text.find("shape=512x512 viewport=512x512 format=55 binds=1 draws=1 vertices=7")
              != std::string::npos,
          "the second list kept its own target: " + text);
}

void unbinding_stops_attribution_rather_than_guessing() {
  FoveationCensus census;
  const void* list = &kListA;
  bind_at(census, list, 1280, 1440, 10, 1280, 1440, "gbuffer");
  census.draw(list, 100, 1);
  // A depth-only pass binds no colour target. Charging its draws to the
  // previous colour target would inflate exactly the number this exists to
  // measure.
  bind_at(census, list, 0, 0, 0, 0, 0, nullptr);
  census.draw(list, 100, 1);
  require(census.unattributed_draws() == 1,
          "a draw with no colour target must be counted as unattributed");
  const auto text = written(census);
  require(text.find("draws=1 vertices=100") != std::string::npos,
          "the gbuffer kept only its own draw: " + text);

  // And a released list must not keep charging a stale target.
  bind_at(census, list, 1280, 1440, 10, 1280, 1440, "gbuffer");
  census.release(list);
  census.draw(list, 100, 1);
  require(census.unattributed_draws() == 2,
          "a released list must not attribute draws to its old target");
}

void instances_multiply_and_zero_instances_still_counts_once() {
  FoveationCensus census;
  const void* list = &kListA;
  bind_at(census, list, 64, 64, 2, 64, 64, "instanced");
  census.draw(list, 10, 50);
  // A zero instance count draws nothing, but counting it as zero primitives
  // would let a pass that issues thousands of them read as free.
  census.draw(list, 10, 0);
  const auto text = written(census);
  require(text.find("draws=2 vertices=510") != std::string::npos,
          "instances multiply and a zero count still counts once: " + text);
}

void the_marker_is_kept_and_cannot_break_the_log() {
  FoveationCensus census;
  const void* list = &kListA;
  bind_at(census, list, 64, 64, 2, 64, 64, "lighting\tpass\r\nwith breaks");
  census.draw(list, 1, 1);
  const auto text_after_draw = written(census);
  require(text_after_draw.find("marker=lighting pass  with breaks") != std::string::npos,
          "tabs and newlines in a marker must not break the line: " +
              text_after_draw);
  // One line per shape plus the summary.
  std::size_t lines = 0;
  for (std::size_t i = 0; i + 1 < text_after_draw.size(); ++i) {
    if (text_after_draw[i] == '\r' && text_after_draw[i + 1] == '\n') ++lines;
  }
  require(lines == 2, "one line for the shape and one summary, got " +
                          std::to_string(lines));

  // An over-long marker must be truncated, not overrun.
  FoveationCensus long_marker;
  const std::string huge(400, 'x');
  bind_at(long_marker, list, 32, 32, 1, 32, 32, huge.c_str());
  long_marker.draw(list, 1, 1);
  const auto long_text = written(long_marker);
  require(long_text.find("marker=xxxx") != std::string::npos,
          "the marker survived truncation");
  require(long_text.size() < 400,
          "an over-long marker was not truncated: " + std::to_string(long_text.size()));

  // A null marker is a pass the engine did not label, not a crash.
  FoveationCensus unlabelled;
  bind_at(unlabelled, list, 16, 16, 1, 16, 16, nullptr);
  unlabelled.draw(list, 1, 1);
  require(written(unlabelled).find("shape=16x16") != std::string::npos,
          "an unlabelled pass is still counted");
}

void running_out_of_shapes_is_reported_not_hidden() {
  FoveationCensus census;
  const void* list = &kListA;
  for (std::uint32_t i = 0; i < FoveationCensus::kCapacity + 5; ++i) {
    bind_at(census, list, 100 + i, 100, 1, 100 + i, 100, "pass");
    census.draw(list, 1, 1);
  }
  require(census.size() == FoveationCensus::kCapacity, "capacity is the cap");
  require(census.overflowed_shapes() == 5,
          "the shapes that did not fit must be counted, got " +
              std::to_string(census.overflowed_shapes()));
  const auto text = written(census);
  require(text.find("overflowed_shapes=5") != std::string::npos,
          "and said in the log: " + text);
  // Draws to a shape that did not fit are unattributed, not charged to
  // whatever happened to be in the last slot.
  require(census.unattributed_draws() == 5,
          "draws to an overflowed shape must be unattributed, got " +
              std::to_string(census.unattributed_draws()));
}

void clear_starts_again() {
  FoveationCensus census;
  const void* list = &kListA;
  bind_at(census, list, 64, 64, 1, 64, 64, "pass");
  census.draw(list, 5, 1);
  census.clear();
  require(census.size() == 0 && census.unattributed_draws() == 0,
          "clear must forget the shapes");
  // And must forget which target each list had bound, or the first draw of
  // the next window lands on a shape that no longer exists.
  census.draw(list, 5, 1);
  require(census.unattributed_draws() == 1,
          "clear must forget the per-list bindings too");
}

void a_small_buffer_is_not_overrun() {
  FoveationCensus census;
  const void* list = &kListA;
  bind_at(census, list, 1280, 1440, 10, 1280, 1440, "gbuffer");
  census.draw(list, 5, 1);
  std::vector<char> buffer(40, '\xEE');
  const auto count = census.write(buffer.data(), 16);
  require(count <= 16, "write must respect the capacity it was given");
  require(buffer[20] == '\xEE', "write ran past the capacity it was given");
  require(census.write(nullptr, 100) == 0, "a null buffer writes nothing");
  require(census.write(buffer.data(), 0) == 0, "a zero capacity writes nothing");
}

void the_viewport_distinguishes_passes_that_share_a_target() {
  // The usual way an engine implements an upscaled or dynamic internal
  // resolution is a SMALLER VIEWPORT into a full-size target. Keying on the
  // resource extent alone would then report one shape for every pass and
  // answer nothing -- which is the entire question this census exists to ask.
  FoveationCensus census;
  const void* list = &kListA;
  bind_at(census, list, 1920, 2160, 10, 1280, 1440, "main_at_internal_res");
  census.draw(list, 500, 1);
  bind_at(census, list, 1920, 2160, 10, 1920, 2160, "post_at_full_res");
  census.draw(list, 3, 1);
  require(census.size() == 2,
          "one target at two viewports must be two shapes, got " +
              std::to_string(census.size()));
  const auto text = written(census);
  require(text.find("shape=1920x2160 viewport=1280x1440") != std::string::npos,
          "the internal-resolution pass: " + text);
  require(text.find("shape=1920x2160 viewport=1920x2160") != std::string::npos,
          "the full-resolution pass: " + text);
}

void a_thread_tracking_too_many_lists_says_so() {
  // Each recording thread caches a few lists. A thread cycling through more
  // than that evicts live bindings, and their draws are charged to whatever
  // replaces them. That is a wrong number, and it must not be a silent one.
  FoveationCensus census;
  std::vector<int> lists(FoveationCensus::kLocalLists + 4);
  for (std::size_t i = 0; i < lists.size(); ++i) {
    bind_at(census, &lists[i], 64, 64, 1, 64, 64, "pass");
    census.draw(&lists[i], 1, 1);
  }
  require(census.evicted_bindings() == 4,
          "evicted bindings must be counted, got " +
              std::to_string(census.evicted_bindings()));
  const auto text = written(census);
  require(text.find("evicted_bindings=4") != std::string::npos,
          "and said in the log: " + text);

  // Releasing a list must RECLAIM its slot, or a thread that opens and closes
  // lists in a loop fills its cache and evicts for ever.
  FoveationCensus reclaiming;
  for (std::size_t i = 0; i < lists.size() * 4; ++i) {
    const auto* list = &lists[i % lists.size()];
    bind_at(reclaiming, list, 64, 64, 1, 64, 64, "pass");
    reclaiming.draw(list, 1, 1);
    reclaiming.release(list);
  }
  require(reclaiming.evicted_bindings() == 0,
          "a released list must free its slot; evicted " +
              std::to_string(reclaiming.evicted_bindings()));
  require(reclaiming.unattributed_draws() == 0,
          "and every draw still found its target");
}

void the_report_says_its_numbers_are_not_pixels() {
  // Foveation saves pixel shading, and neither draws nor vertices are pixels:
  // a depth prepass can carry an enormous vertex count and shade nothing. A
  // reader ranking passes off this log has to be told that.
  FoveationCensus census;
  const void* list = &kListA;
  bind_at(census, list, 64, 64, 1, 64, 64, "pass");
  census.draw(list, 5, 1);
  require(written(census).find("note=draws_and_vertices_are_not_pixels") !=
              std::string::npos,
          "the log must say what it is not measuring");
}

}  // namespace

int main() {
  try {
    draws_are_charged_to_the_target_that_was_bound();
    the_busiest_shape_is_reported_first();
    several_command_lists_record_at_once();
    unbinding_stops_attribution_rather_than_guessing();
    instances_multiply_and_zero_instances_still_counts_once();
    the_marker_is_kept_and_cannot_break_the_log();
    running_out_of_shapes_is_reported_not_hidden();
    clear_starts_again();
    a_small_buffer_is_not_overrun();
    the_viewport_distinguishes_passes_that_share_a_target();
    a_thread_tracking_too_many_lists_says_so();
    the_report_says_its_numbers_are_not_pixels();
    std::cout << "foveation_census.result=pass\n";
    return 0;
  } catch (const std::exception& error) {
    std::cerr << "foveation_census: " << error.what() << '\n';
    return 1;
  }
}
