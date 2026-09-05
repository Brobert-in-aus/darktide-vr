#include "producer/streamline_submission.h"
#include "core/streamline_present_binding.h"
#include <iostream>
#include <stdexcept>
#include <vector>

using namespace darktidevr::producer;
namespace sl = streamline_2_7_30;
namespace {
std::vector<int> calls;
int fail_at{}, attempt{}, clear_fail_eye{};
void* expected_frame;
void check(bool value) { if (!value) throw std::runtime_error("submission contract"); }
int constants(const void* values, const void* frame, const void* viewport) {
  check(values && frame == expected_frame);
  const auto id = static_cast<const sl::ViewportHandle*>(viewport)->value;
  calls.push_back(static_cast<int>(id * 10));
  return ++attempt == fail_at ? 7 : 0;
}
int tags(const void* frame, const void* viewport, const void* data,
         std::uint32_t count, void* commands) {
  check(frame == expected_frame && count == 4 && commands);
  const auto id = static_cast<const sl::ViewportHandle*>(viewport)->value;
  const auto* tag = static_cast<const sl::ResourceTag*>(data);
  const bool clearing = !tag[0].resource;
  calls.push_back(static_cast<int>(id * 10 + (clearing ? 2 : 1)));
  if (clearing) {
    for (std::uint32_t i = 0; i < count; ++i)
      check(!tag[i].resource && tag[i].extent.width == 0);
    return static_cast<int>(id) == clear_fail_eye ? 9 : 0;
  }
  return ++attempt == fail_at ? 7 : 0;
}
int legacy_tags(const void* viewport, const void* data,
                std::uint32_t count, void* commands) {
  return tags(expected_frame, viewport, data, count, commands);
}
}
int main() {
  using namespace darktidevr::core;
  const std::array<StreamlinePresentEyeBinding, 2> valid_binding{{
      {true, 100, 51, 49, 49, 200, 1, true, 1, 49},
      {true, 100, 51, 49, 49, 200, 2, true, 1, 49}}};
  check(streamline_present_binding_matches(50, {1, 2}, valid_binding));
  check(!streamline_present_binding_matches(51, {1, 2}, valid_binding));
  check(!streamline_present_binding_matches(0, {1, 2}, valid_binding));
  check(!streamline_present_binding_matches(50, {2, 1}, valid_binding));
  for (int mutation = 0; mutation < 9; ++mutation) {
    auto invalid = valid_binding;
    auto& eye = invalid[1];
    switch (mutation) {
      case 0: eye.token_call++; break; // Same pointer, recycled token.
      case 1: eye.frame_index++; break;
      case 2: eye.pose++; break;
      case 3: eye.token++; break;
      case 4: eye.mode = 0; break;
      case 5: eye.options_present--; break;
      case 6: eye.options_valid = false; break;
      case 7: eye.constants_valid = false; break;
      case 8: eye.constants_present--; break;
    }
    check(!streamline_present_binding_matches(50, {1, 2}, invalid));
  }
  int resources[6]{}, frame{}, commands{};
  expected_frame = &frame;
  StreamlineStereoTags::Inputs inputs{};
  for (std::uint32_t eye = 0; eye < 2; ++eye)
    for (std::uint32_t i = 0; i < 3; ++i)
      inputs[eye][i] = {&resources[eye * 3 + i], 200, 200, 64, 28};
  std::array<sl::Constants, 2> values{};
  for (auto& value : values)
    value.base = {nullptr, {0xdcd35ad7, 0x4e4a, 0x4bad,
        {0xa9, 0x0c, 0xe0, 0xc4, 0x9e, 0xb2, 0x3a, 0xfe}}, 2};
  const StreamlineSubmissionApi api{constants, tags};
  // Inject a failure at every SL submission call, including partially applied
  // tag calls; successful cleanup must permit retirement without Present.
  for (int failure = 1; failure <= 4; ++failure) {
    StreamlineSubmission batch;
    calls.clear(); attempt = 0; fail_at = failure;
    check(batch.prepare(1, 200, 200, {1, 2}, values, inputs));
    check(!batch.stage(api, &frame, &commands));
    check(batch.last_result() == 7 && !batch.begin_present());
    check(!batch.retire());
    check(batch.clear_tags(&commands));
    check(batch.retire());
    check(calls.back() == (failure == 1 ? 10 : failure == 4 ? 22 : 12));
  }
  StreamlineSubmission batch;
  calls.clear(); attempt = 0; fail_at = 0;
  check(batch.prepare(1, 200, 200, {1, 2}, values, inputs));
  check(!batch.stage({}, &frame, &commands));
  check(!batch.stage(api, &frame, nullptr));
  check(!batch.stage(api, nullptr, &commands));
  check(calls.empty());
  check(batch.stage(api, &frame, &commands));
  check(calls == std::vector<int>({10, 11, 20, 21}));
  check(!batch.stage(api, &frame, &commands));
  check(batch.begin_present());
  check(!batch.retire());
  clear_fail_eye = 2;
  check(!batch.clear_tags(&commands));
  check(batch.record_ticket(1, 0, 100, 4));
  check(batch.record_ticket(1, 1, 100, 5));
  check(batch.observe_completion(1, 0, 100, 5));
  check(batch.observe_completion(1, 1, 100, 5));
  check(!batch.retire());
  calls.clear(); clear_fail_eye = 0;
  check(batch.clear_tags(&commands));
  check(calls == std::vector<int>({22}));
  check(batch.retire());
  check(batch.prepare(2, 200, 200, {1, 2}, values, inputs));
  check(batch.clear_tags(&commands));
  check(!batch.stage(api, &frame, &commands) && !batch.begin_present());
  check(batch.retire());
  check(batch.prepare(3, 200, 200, {1, 2}, values, inputs));
  // A later batch must use the token supplied at staging, including cleanup.
  int next_frame{};
  expected_frame = &next_frame;
  const StreamlineSubmissionApi legacy_api{constants, nullptr, legacy_tags};
  check(!batch.stage(legacy_api, &frame, &commands)); // No silent API-mode fallback.
  calls.clear();
  check(batch.stage(legacy_api, &next_frame, &commands, StreamlineSubmission::Tagging::legacy));
  check(calls == std::vector<int>({10, 11, 20, 21}));
  check(batch.clear_tags(&commands));
  check(batch.retire());
  check(batch.prepare(4, 200, 200, {1, 2}, values, inputs));
  calls.clear();
  check(batch.stage({nullptr, tags}, &next_frame, &commands,
      StreamlineSubmission::Tagging::frame_based,
      StreamlineSubmission::ConstantsMode::already_supplied));
  check(calls == std::vector<int>({11, 21}));
  check(batch.clear_tags(&commands));
  check(batch.retire());
  for (int failure = 1; failure <= 2; ++failure) {
    StreamlineSubmission failed_tags;
    calls.clear(); attempt = 0; fail_at = failure;
    check(failed_tags.prepare(1, 200, 200, {1, 2}, values, inputs));
    check(!failed_tags.stage({nullptr, tags}, &next_frame, &commands,
        StreamlineSubmission::Tagging::frame_based,
        StreamlineSubmission::ConstantsMode::already_supplied));
    check(!failed_tags.begin_present() && !failed_tags.retire());
    check(failed_tags.clear_tags(&commands));
    check(failed_tags.retire());
    check(calls == (failure == 1 ? std::vector<int>{11, 12}
                                : std::vector<int>{11, 21, 12, 22}));
  }
  std::cout << "streamline_submission=pass\n";
}
