#pragma once

#include <cstdint>

namespace darktidevr::core {

inline constexpr wchar_t kSharedGameplayAimStateName[] =
    L"Local\\DarktideVR-gameplay-aim-state-v1";

struct SharedGameplayAimState {
  std::uint64_t sequence{};
  float distance_metres{};
  bool active{};
  bool hit{};
};

class SharedGameplayAimStateWriter {
 public:
  SharedGameplayAimStateWriter();
  ~SharedGameplayAimStateWriter();

  SharedGameplayAimStateWriter(const SharedGameplayAimStateWriter&) = delete;
  SharedGameplayAimStateWriter& operator=(
      const SharedGameplayAimStateWriter&) = delete;

  bool publish(const SharedGameplayAimState& state);

 private:
  void* mapping_{};
  void* view_{};
};

class SharedGameplayAimStateReader {
 public:
  SharedGameplayAimStateReader() = default;
  ~SharedGameplayAimStateReader();

  SharedGameplayAimStateReader(const SharedGameplayAimStateReader&) = delete;
  SharedGameplayAimStateReader& operator=(
      const SharedGameplayAimStateReader&) = delete;

  bool read(SharedGameplayAimState& state);

 private:
  bool ensure_open();

  void* mapping_{};
  void* view_{};
};

bool valid_gameplay_aim_state(const SharedGameplayAimState& state);

}  // namespace darktidevr::core
