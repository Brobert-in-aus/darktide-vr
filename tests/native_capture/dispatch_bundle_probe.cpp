#include "../../tools/renderer_probe/dispatch-bundle-probe.h"
#include <vector>
#include <cstring>
#include <stdexcept>
#include <iostream>

void expect(bool value) { if (!value) throw std::runtime_error("bundle probe invariant failed"); }
int main() {
  using namespace darktidevr::diagnostics;
  std::vector<std::byte> memory(0x3000);
  const auto write = [&](std::size_t offset, auto value) { std::memcpy(memory.data()+offset, &value, sizeof(value)); };
  for (std::uint32_t i = 0; i < 16; ++i) {
    write(i*32+8, std::uint64_t(0x11000));
    write(i*32+16, i*16);
    write(i*32+20, std::uint32_t(16));
    write(i*32+24, std::uint32_t(0x20));
    write(0x2000+i*16, std::uint32_t(0x23));
    write(0x2000+i*16+4, std::uint32_t(16));
    write(0x2000+i*16+8, std::uint32_t(16));
  }
  write(0x1008, std::uint64_t(0x12000));
  write(0x1010, std::uint32_t(256));
  write(0x1014, std::uint32_t(256));
  unsigned reads{};
  const auto read = [&](std::uint64_t address, void* out, std::size_t size) {
    ++reads;
    if (address < 0x10000 || address-0x10000 > memory.size() || size > memory.size()-(address-0x10000)) return false;
    std::memcpy(out, memory.data()+(address-0x10000), size);
    return true;
  };
  const auto probe = probe_dispatch_bundles(0x10000, 16, read);
  expect(probe.attempted == 8 && reads == 24);
  for (unsigned i = 0; i < 8; ++i)
    expect(probe.samples[i].valid && probe.samples[i].index == i*15/7 &&
           probe.samples[i].flags == 0x20 && probe.samples[i].opcode == 0x23);
  reads = 0;
  expect(!probe_dispatch_bundles(0x10000, 0, read).attempted);
  expect(!probe_dispatch_bundles(0x10000, 10000001, read).attempted);
  expect(!probe_dispatch_bundles(0xfffffffffffffff0, 16, read).attempted && reads == 0);
  expect(probe_dispatch_bundles(0x10000, 1, read).samples[0].valid);
  write(0x2004, std::uint32_t(32)); // Final command may cross descriptor end.
  write(20, std::uint32_t(8));
  expect(probe_dispatch_bundles(0x10000, 1, read).samples[0].valid);
  write(20, std::uint32_t(16));
  write(0x2004, std::uint32_t(64));
  write(0x202c, std::uint32_t(3));
  const auto kernel = probe_dispatch_bundles(0x10000, 1, read);
  expect(kernel.samples[0].kernel_flags_valid && kernel.samples[0].kernel_flags == 3);
  expect(!kernel.samples[0].kernel_identity_valid);
  write(0x2004, std::uint32_t(144));
  write(0x2068, std::uint64_t(0x123456789abcdef0));
  write(0x2070, std::uint32_t(7));
  write(0x2074, std::uint32_t(8));
  write(0x2084, std::uint32_t(9));
  const auto identity = probe_dispatch_bundles(0x10000, 1, read);
  expect(identity.samples[0].kernel_identity_valid && identity.samples[0].resource_tag == 0x123456789abcdef0 &&
         identity.samples[0].object_tag == 7 && identity.samples[0].batch_tag == 8 && identity.samples[0].kernel_handle == 9);
  write(0x2004, std::uint32_t(16));
  write(16, std::uint32_t(250)); // Bundle extends beyond used bytes.
  expect(!probe_dispatch_bundles(0x10000, 16, read).samples[0].valid);
  write(16, std::uint32_t(0));
  write(0x2008, std::uint32_t(17)); // Payload outside first command.
  expect(!probe_dispatch_bundles(0x10000, 1, read).samples[0].valid);
  write(0x2008, std::uint32_t(16));
  write(8, std::uint64_t(0xfffffffffffffff0));
  expect(!probe_dispatch_bundles(0x10000, 1, read).samples[0].valid);
  std::cout << "dispatch_bundle_probe=pass bounds spacing unknown overflow read_budget\n";
}
