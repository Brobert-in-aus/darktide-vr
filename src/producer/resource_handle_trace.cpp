#include "producer/resource_handle_trace.h"
#include <MinHook.h>
#include <array>
#include <atomic>
#include <cstdint>
#include <cstdio>
#include <cstring>
#include <mutex>
#include <string>

namespace darktidevr::producer {
namespace {
using Allocate = std::uint32_t (*)(void*, std::uint32_t, bool);
using Release = void (*)(void*, std::uint32_t);
Allocate allocate_original{};
Release release_original{};
std::array<std::atomic<std::uint64_t>, 32> allocations{};
std::array<std::atomic<std::uint64_t>, 32> releases{};
HANDLE trace_file = INVALID_HANDLE_VALUE;
std::mutex trace_mutex;
ULONGLONG started{};
std::uintptr_t game_base{};
std::size_t game_size{};

void write_line(const char* text, DWORD length) {
  std::scoped_lock lock(trace_mutex);
  DWORD written{};
  WriteFile(trace_file, text, length, &written, nullptr);
}

std::uint32_t allocate_hook(void* allocator, std::uint32_t type, bool transient) {
  const auto handle = allocate_original(allocator, type, transient);
  const auto kind = (handle >> 26) & 31u;
  const auto count = allocations[kind].fetch_add(1, std::memory_order_relaxed) + 1;
  if (count <= 8 || count % 65536 == 0) {
    // Stack collection and file I/O only at sparse samples, never every draw.
    // Count deltas start at hook installation, not at process creation.
    std::array<void*, 8> stack{};
    const auto frames = CaptureStackBackTrace(1, static_cast<DWORD>(stack.size()),
                                             stack.data(), nullptr);
    std::array<char, 768> line{};
    auto length = std::snprintf(line.data(), line.size(),
        "ms=%llu type=%u allocator=%p handle=0x%08x index=%u generation=%u "
        "allocations=%llu releases=%llu callers=",
        GetTickCount64() - started, kind, allocator, handle, handle & 0x3fffffu,
        (handle >> 22) & 15u, static_cast<unsigned long long>(count),
        static_cast<unsigned long long>(releases[kind].load(std::memory_order_relaxed)));
    for (USHORT i = 0; i < frames && length > 0 &&
         static_cast<std::size_t>(length) + 32 < line.size(); ++i) {
      const auto address = reinterpret_cast<std::uintptr_t>(stack[i]);
      if (address >= game_base && address - game_base < game_size) {
        length += std::snprintf(line.data() + length, line.size() - length,
            "%s0x%llx", i == 0 ? "" : ",",
            static_cast<unsigned long long>(address - game_base));
      }
    }
    if (length > 0 && static_cast<std::size_t>(length) + 1 < line.size()) {
      line[static_cast<std::size_t>(length)] = '\n';
      ++length;
      write_line(line.data(), static_cast<DWORD>(length));
    }
  }
  return handle;
}

void release_hook(void* allocator, std::uint32_t handle) {
  release_original(allocator, handle);
  releases[(handle >> 26) & 31u].fetch_add(1, std::memory_order_relaxed);
}

template<std::size_t N>
void* verified_target(std::uintptr_t rva, const std::array<unsigned char, N>& signature) {
  if (rva >= game_size || N > game_size - rva) return nullptr;
  auto* target = reinterpret_cast<void*>(game_base + rva);
  MEMORY_BASIC_INFORMATION memory{};
  if (VirtualQuery(target, &memory, sizeof(memory)) != sizeof(memory) ||
      memory.State != MEM_COMMIT || (memory.Protect & (PAGE_GUARD | PAGE_NOACCESS)) ||
      std::memcmp(target, signature.data(), N) != 0) return nullptr;
  return target;
}
}

bool install_resource_handle_trace(HMODULE capture_module) {
  std::array<wchar_t, 32768> path{};
  const auto length = GetModuleFileNameW(capture_module, path.data(),
                                        static_cast<DWORD>(path.size()));
  if (length == 0 || length >= path.size()) return true;
  std::wstring directory(path.data(), length);
  const auto separator = directory.find_last_of(L"\\/");
  if (separator == std::wstring::npos) return true;
  directory.resize(separator + 1);
  const auto flag = directory + L"..\\darktidevr_resource_handle_trace.flag";
  if (GetFileAttributesW(flag.c_str()) == INVALID_FILE_ATTRIBUTES) return true;

  game_base = reinterpret_cast<std::uintptr_t>(GetModuleHandleW(nullptr));
  const auto* dos = reinterpret_cast<const IMAGE_DOS_HEADER*>(game_base);
  if (dos->e_magic != IMAGE_DOS_SIGNATURE || dos->e_lfanew <= 0) return false;
  const auto* nt = reinterpret_cast<const IMAGE_NT_HEADERS64*>(game_base + dos->e_lfanew);
  if (nt->Signature != IMAGE_NT_SIGNATURE ||
      nt->FileHeader.Machine != IMAGE_FILE_MACHINE_AMD64) return false;
  game_size = nt->OptionalHeader.SizeOfImage;
  // Exact prologues from the launcher's already hash-guarded executable.
  constexpr std::array<unsigned char, 20> allocate_signature{
      0x48,0x89,0x5c,0x24,0x08,0x48,0x89,0x6c,0x24,0x10,
      0x48,0x89,0x74,0x24,0x18,0x48,0x89,0x7c,0x24,0x20};
  constexpr std::array<unsigned char, 15> release_signature{
      0x48,0x89,0x5c,0x24,0x08,0x48,0x89,0x74,0x24,0x10,
      0x57,0x48,0x83,0xec,0x20};
  auto* allocate_target = verified_target(0x5b7870, allocate_signature);
  auto* release_target = verified_target(0x5b7950, release_signature);
  if (!allocate_target || !release_target) return false;

  std::array<wchar_t, MAX_PATH> temporary{};
  const auto temporary_length = GetTempPathW(static_cast<DWORD>(temporary.size()), temporary.data());
  if (temporary_length == 0 || temporary_length >= temporary.size()) return false;
  const auto output = std::wstring(temporary.data()) + L"darktidevr-resource-handles-" +
                      std::to_wstring(GetCurrentProcessId()) + L".log";
  trace_file = CreateFileW(output.c_str(), GENERIC_WRITE, FILE_SHARE_READ, nullptr,
                          CREATE_ALWAYS, FILE_ATTRIBUTE_NORMAL, nullptr);
  if (trace_file == INVALID_HANDLE_VALUE) return false;
  started = GetTickCount64();
  constexpr char header[] = "resource_handle_trace=armed schema=1 allocation_rva=0x5b7870 release_rva=0x5b7950\n";
  write_line(header, static_cast<DWORD>(sizeof(header) - 1));
  return MH_CreateHook(allocate_target, &allocate_hook,
      reinterpret_cast<void**>(&allocate_original)) == MH_OK &&
      MH_CreateHook(release_target, &release_hook,
      reinterpret_cast<void**>(&release_original)) == MH_OK;
}
}
