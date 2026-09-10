#include "producer/particle_submission_snapshot.h"
#include <cstring>
#include <iostream>
#include <stdexcept>
#include <vector>

void check(bool value) { if (!value) throw std::runtime_error("particle snapshot mismatch"); }
int main() {
  using namespace darktidevr::producer;
  constexpr std::uint64_t base = 0x10000, context = base, batch = base + 0x100;
  constexpr std::uint64_t object = base + 0x400, constants = base + 0xa00;
  std::vector<unsigned char> bytes(0x2000);
  auto put = [&](std::uint64_t address, const auto& value) {
    std::memcpy(bytes.data() + address - base, &value, sizeof(value));
  };
  put(context + 5 * 8, object);
  put(context + 8 * 8, base + 0x300);
  put(context + 9 * 8, base + 0x308);
  put(base + 0x300, base + 0xb00);
  put(base + 0x308, base + 0xc00);
  put(base + 0xb04, std::uint32_t{123});
  put(base + 0xc04, std::uint32_t{456});
  put(batch + 0xd8, std::uint64_t{0xabcdef});
  put(batch + 0xe0, std::uint32_t{789});
  put(batch + 0xe4, std::uint32_t{0x2765d852});
  put(object + 0x138, constants);
  put(object + 0x4e4, std::uint32_t{8});
  put(object + 0x510, std::uint32_t{9});
  put(object + 0x514, std::uint8_t{1});
  for (unsigned i = 0; i < 192; ++i) bytes[constants - base + i] = static_cast<unsigned char>(i);
  const auto original = bytes;
  unsigned reads{}, fail{};
  auto read = [&](std::uint64_t address, void* to, std::size_t size) {
    ++reads;
    if (reads == fail || address < base || address - base > bytes.size() ||
        size > bytes.size() - (address - base)) return false;
    std::memcpy(to, bytes.data() + address - base, size);
    return true;
  };
  const auto good = snapshot_particle_submission(context, batch, read);
  check(good.valid && good.object == object && good.resource == 0xabcdef &&
      good.object_tag == 789 && good.batch_tag == 0x2765d852 &&
      good.handle_a == 123 && good.handle_b == 456 && good.update_serial == 9 &&
      good.buffer_serial == 8 && good.update_needed == 1 && good.constants[191] == 191);
  const unsigned total = reads;
  for (fail = 1; fail <= total; ++fail) {
    reads = 0;
    const auto bad = snapshot_particle_submission(context, batch, read);
    check(!bad.valid && bad.object == 0 && bad.constants[191] == 0);
  }
  fail = 0;
  reads = 0;
  check(!snapshot_particle_submission(~std::uint64_t{}, batch, read).valid && reads == 0);
  put(context + 5 * 8, ~std::uint64_t{});
  check(!snapshot_particle_submission(context, batch, read).valid);
  bytes = original;
  check(snapshot_particle_submission(context, batch, read).valid && bytes == original);
  std::cout << "PASS identity, constants, every failed read, pointer bounds and recovery\n";
}
