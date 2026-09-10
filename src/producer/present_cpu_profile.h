#pragma once
#include <Windows.h>
#include <atomic>
#include <cstdint>
#include <cstdio>
#include <string>

namespace darktidevr::producer {
// Opt-in CPU observation only. Never waits for a GPU or changes presentation.
class PresentCpuProfile {
  struct Stamp { LONGLONG wall{}; std::uint64_t cpu{}; };
  struct Config {
    HANDLE log{INVALID_HANDLE_VALUE};
    LONGLONG frequency{};
    std::atomic<unsigned> admitted{};
    explicit Config(HMODULE module) {
      wchar_t path[32768]{};
      const auto size = GetModuleFileNameW(module, path, 32768);
      if (!size || size >= 32768) return;
      std::wstring flag(path, size);
      const auto separator = flag.find_last_of(L"\\/");
      if (separator == std::wstring::npos) return;
      flag.resize(separator + 1);
      flag += L"darktidevr_present_cpu_profile.flag";
      if (GetPrivateProfileIntW(L"probe", L"enabled", 0, flag.c_str()) != 1) return;
      LARGE_INTEGER qpc{};
      if (!QueryPerformanceFrequency(&qpc) || qpc.QuadPart <= 0) return;
      frequency = qpc.QuadPart;
      wchar_t temp[MAX_PATH]{};
      const auto length = GetTempPathW(MAX_PATH, temp);
      if (!length || length >= MAX_PATH) return;
      const auto file = std::wstring(temp) + L"darktidevr-present-cpu-" +
          std::to_wstring(GetCurrentProcessId()) + L".log";
      log = CreateFileW(file.c_str(), GENERIC_WRITE, FILE_SHARE_READ, nullptr,
                        CREATE_ALWAYS, FILE_ATTRIBUTE_NORMAL, nullptr);
      if (log != INVALID_HANDLE_VALUE) {
        char line[192]{};
        const auto n = std::snprintf(line, sizeof(line),
            "PRESENT_CPU_BEGIN pid=%lu warmup=600 limit=240 frequency=%lld cpu_units=100ns\n",
            GetCurrentProcessId(), frequency);
        DWORD written{};
        if (n > 0 && n < static_cast<int>(sizeof(line))) WriteFile(log, line, static_cast<DWORD>(n), &written, nullptr);
      }
    }
    ~Config() { if (log != INVALID_HANDLE_VALUE) CloseHandle(log); }
  };
  struct State {
    std::uint64_t generation{};
    unsigned warmup{};
    Stamp previous{};
    bool have_previous{};
  };
  static bool stamp(Stamp& output) {
    FILETIME created{}, exited{}, kernel{}, user{};
    LARGE_INTEGER qpc{};
    if (!GetThreadTimes(GetCurrentThread(), &created, &exited, &kernel, &user) ||
        !QueryPerformanceCounter(&qpc)) return false;
    output.wall = qpc.QuadPart;
    output.cpu = (std::uint64_t(kernel.dwHighDateTime) << 32 | kernel.dwLowDateTime) +
                 (std::uint64_t(user.dwHighDateTime) << 32 | user.dwLowDateTime);
    return true;
  }
  Config* config_{};
  Stamp begin_{}, previous_{};
  std::uint64_t generation_{};
  unsigned sample_{};
 public:
  PresentCpuProfile(HMODULE module, std::uint64_t generation) {
    const auto saved_error = GetLastError();
    initialize(module, generation);
    SetLastError(saved_error);
  }
  PresentCpuProfile(const PresentCpuProfile&) = delete;
  PresentCpuProfile& operator=(const PresentCpuProfile&) = delete;
  ~PresentCpuProfile() {
    if (!config_) return;
    const auto saved_error = GetLastError();
    Stamp end{};
    if (stamp(end)) {
      char line[384]{};
      const auto n = std::snprintf(line, sizeof(line),
          "PRESENT_CPU sample=%u thread=%lu generation=%llu begin_qpc=%lld frame_wall_ms=%.6f frame_cpu_ms=%.6f present_wall_ms=%.6f present_cpu_ms=%.6f\n",
          sample_, GetCurrentThreadId(), static_cast<unsigned long long>(generation_), begin_.wall,
          double(begin_.wall - previous_.wall) * 1000 / config_->frequency,
          double(begin_.cpu - previous_.cpu) / 10000,
          double(end.wall - begin_.wall) * 1000 / config_->frequency,
          double(end.cpu - begin_.cpu) / 10000);
      DWORD written{};
      if (n > 0 && n < static_cast<int>(sizeof(line))) WriteFile(config_->log, line, static_cast<DWORD>(n), &written, nullptr);
    }
    SetLastError(saved_error);
  }
 private:
  void initialize(HMODULE module, std::uint64_t generation) {
    static Config config(module);
    if (config.log == INVALID_HANDLE_VALUE || config.admitted.load(std::memory_order_relaxed) >= 240) return;
    static thread_local State state;
    if (state.generation != generation) state = State{generation};
    if (!generation || state.warmup++ < 600) return;
    Stamp current{};
    if (!stamp(current)) return;
    const auto previous = state.previous;
    const bool usable = state.have_previous && current.wall > previous.wall && current.cpu >= previous.cpu;
    state.previous = current;
    state.have_previous = true;
    if (!usable) return;
    auto count = config.admitted.load(std::memory_order_relaxed);
    while (count < 240) {
      if (config.admitted.compare_exchange_weak(count, count + 1, std::memory_order_relaxed)) {
        config_ = &config;
        begin_ = current;
        previous_ = previous;
        generation_ = generation;
        sample_ = count + 1;
        return;
      }
    }
  }
};
}
