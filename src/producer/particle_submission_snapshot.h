#pragma once
#include <array>
#include <cstdint>
#include <cstddef>

namespace darktidevr::producer {
struct ParticleSubmissionSnapshot {
  std::uint64_t object{}, resource{}, buffer_a{}, buffer_b{};
  std::uint32_t object_tag{}, batch_tag{}, update_serial{}, buffer_serial{};
  std::uint32_t handle_a{}, handle_b{};
  std::uint8_t update_needed{};
  std::array<std::uint8_t, 192> constants{};
  bool valid{};
};
// Exact-build helper arguments. All pointed-to locals are observed before the
// original call; failure discards the whole snapshot. No GPU memory is read.
template<class Read>
ParticleSubmissionSnapshot snapshot_particle_submission(
    std::uint64_t context, std::uint64_t batch, Read read) {
  ParticleSubmissionSnapshot result;
  std::array<std::uint64_t, 10> slots{};
  struct Tags { std::uint64_t resource; std::uint32_t object, batch; } tags{};
  std::uint64_t constants{};
  const auto at = [&](std::uint64_t base, std::uint64_t offset, void* destination, std::size_t bytes) {
    constexpr std::uint64_t user_address_limit = 0x0000800000000000;
    return base >= 0x10000 && base < user_address_limit && offset < user_address_limit - base &&
        bytes <= user_address_limit - base - offset && read(base + offset, destination, bytes);
  };
  if (!at(context, 0, slots.data(), sizeof(slots)) ||
      !at(batch, 0xd8, &tags, sizeof(tags))) return {};
  result.object = slots[5];
  result.resource = tags.resource;
  result.object_tag = tags.object;
  result.batch_tag = tags.batch;
  if (!at(slots[8], 0, &result.buffer_a, 8) ||
      !at(slots[9], 0, &result.buffer_b, 8) ||
      !at(result.buffer_a, 4, &result.handle_a, 4) ||
      !at(result.buffer_b, 4, &result.handle_b, 4) ||
      !at(result.object, 0x4e4, &result.buffer_serial, 4) ||
      !at(result.object, 0x510, &result.update_serial, 4) ||
      !at(result.object, 0x514, &result.update_needed, 1) ||
      !at(result.object, 0x138, &constants, 8) ||
      !at(constants, 0, result.constants.data(), result.constants.size())) return {};
  result.valid = true;
  return result;
}
}
