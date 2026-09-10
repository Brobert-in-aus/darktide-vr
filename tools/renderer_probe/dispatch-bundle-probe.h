#pragma once
#include <array>
#include <cstdint>
#include <cstddef>

namespace darktidevr::diagnostics {
struct DispatchBundleSample {
  std::uint32_t index{}, flags{}, opcode{};
  bool valid{};
  std::uint32_t kernel_flags{};
  bool kernel_flags_valid{};
  std::uint64_t resource_tag{};
  std::uint32_t object_tag{}, batch_tag{}, kernel_handle{};
  bool kernel_identity_valid{};
};
struct DispatchBundleProbe {
  std::uint32_t attempted{};
  std::array<DispatchBundleSample, 8> samples{};
};
// Exact-build read-only layout. Eight evenly spaced positions in the sorted
// array, not random samples, per-frame counts, or a timing distribution.
template<class Read>
DispatchBundleProbe probe_dispatch_bundles(std::uint64_t data, std::uint32_t count, Read read) {
  DispatchBundleProbe result;
  constexpr std::uint64_t user_limit = 0x0000800000000000;
  constexpr std::uint32_t byte_limit = 256 * 1024 * 1024;
  const auto address = [](std::uint64_t base, std::uint64_t bytes) {
    return base >= 0x10000 && base < user_limit && bytes <= user_limit - base;
  };
  if (!count || count > 10000000 || !address(data, std::uint64_t(count) * 32)) return result;
  result.attempted = count < result.samples.size() ? count : static_cast<std::uint32_t>(result.samples.size());
  struct Bundle { std::uint64_t key, owner; std::uint32_t offset, bytes, flags, padding; };
  struct Buffer { std::uint64_t data; std::uint32_t capacity, used; };
  struct Command { std::uint32_t opcode, bytes, payload; };
  static_assert(sizeof(Bundle) == 32 && sizeof(Buffer) == 16 && sizeof(Command) == 12);
  for (std::uint32_t i = 0; i < result.attempted; ++i) {
    auto& sample = result.samples[i];
    sample.index = result.attempted == 1 ? 0 : static_cast<std::uint32_t>(
        std::uint64_t(i) * (count - 1) / (result.attempted - 1));
    Bundle bundle{};
    Buffer buffer{};
    Command command{};
    if (!read(data + std::uint64_t(sample.index) * 32, &bundle, sizeof(bundle)) ||
        !address(bundle.owner, 24) || !read(bundle.owner + 8, &buffer, sizeof(buffer)) ||
        buffer.used > buffer.capacity || buffer.capacity > byte_limit ||
        bundle.offset > buffer.used || !bundle.bytes || bundle.bytes > buffer.used - bundle.offset ||
        buffer.used - bundle.offset < sizeof(Command) ||
        !address(buffer.data, buffer.used) ||
        !read(buffer.data + bundle.offset, &command, sizeof(command)) ||
        // The loop tests command start against the descriptor end. A final
        // command can cross that end (5c6bf0 stores payload size there), so
        // validate its full allocation against the owning buffer instead.
        command.bytes < 16 || command.bytes > buffer.used - bundle.offset ||
        command.payload < 16 || command.payload > command.bytes || command.opcode > 0xffff) continue;
    sample.flags = bundle.flags;
    sample.opcode = command.opcode;
    sample.valid = true;
    // Opcode 23 branches on one payload flag word at +1c before choosing
    // compute, ray dispatch, instancing or a direct draw. Do not copy payloads.
    if (command.opcode == 0x23 && command.bytes - command.payload >= 0x20)
      sample.kernel_flags_valid = read(buffer.data + bundle.offset + command.payload + 0x1c,
          &sample.kernel_flags, sizeof(sample.kernel_flags));
    if (!sample.kernel_flags_valid) sample.kernel_flags = 0;
    // Metadata consumed by the engine's resource/object/batch diagnostic tags
    // and its compute-kernel lookup. Never follow the resource handle here.
    struct KernelIdentity {
      std::uint64_t resource;
      std::uint32_t object, batch, ignored[3], handle;
    } identity{};
    static_assert(sizeof(KernelIdentity) == 32);
    if (command.opcode == 0x23 && command.bytes - command.payload >= 0x78 &&
        read(buffer.data + bundle.offset + command.payload + 0x58, &identity, sizeof(identity))) {
      sample.resource_tag = identity.resource;
      sample.object_tag = identity.object;
      sample.batch_tag = identity.batch;
      sample.kernel_handle = identity.handle;
      sample.kernel_identity_valid = true;
    }
  }
  return result;
}
}
