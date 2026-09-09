#include "producer/guarded_copy.h"
#include <array>
#include <iostream>
#include <stdexcept>

void check(bool value) { if (!value) throw std::runtime_error("guarded copy mismatch"); }
int main() {
  SYSTEM_INFO info{};
  GetSystemInfo(&info);
  struct Allocation {
    void* address{};
    ~Allocation() { if (address) VirtualFree(address, 0, MEM_RELEASE); }
  } allocation{VirtualAlloc(nullptr, info.dwPageSize * 2ULL,
                            MEM_COMMIT | MEM_RESERVE, PAGE_READWRITE)};
  check(allocation.address != nullptr);
  auto* source = static_cast<unsigned char*>(allocation.address);
  for (std::size_t i = 0; i < info.dwPageSize; ++i)
    source[i] = static_cast<unsigned char>(i * 37);
  DWORD previous{};
  check(VirtualProtect(source + info.dwPageSize, info.dwPageSize,
                       PAGE_NOACCESS, &previous) != 0);
  std::array<unsigned char, 512> sample{};
  for (const auto bytes : {std::size_t{0}, std::size_t{132}, std::size_t{512}}) {
    check(darktidevr::producer::safe_copy_bytes(sample.data(), source, bytes));
    check(std::memcmp(sample.data(), source, bytes) == 0);
  }
  check(darktidevr::producer::safe_copy_bytes(
      sample.data(), source + info.dwPageSize - 512, 512));
  check(!darktidevr::producer::safe_copy_bytes(
      sample.data(), source + info.dwPageSize, 132));
  check(!darktidevr::producer::safe_copy_bytes(
      sample.data(), source + info.dwPageSize - 64, 132));
  // Failed/partial samples are discarded; a later readable sample can recover.
  check(darktidevr::producer::safe_copy_bytes(sample.data(), source, sample.size()));
  check(std::memcmp(sample.data(), source, sample.size()) == 0);
  std::cout << "PASS exact bytes, inaccessible/cross-page rejection, recovery\n";
}
