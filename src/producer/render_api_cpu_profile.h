#pragma once
#include <Windows.h>
#include <array>
#include <cstdint>
#include <cstdio>
#include <memory>
#include <string>

namespace darktidevr::producer {
// Only the Present caller's work between Present calls is observed. Durations
// include the original D3D12 call/driver, and are not isolated mod overhead.
class RenderApiCpuProfile {
 public:
  enum Kind { draw, dispatch, barrier, pipeline, binding, execute, count };
 private:
  struct Totals { std::uint64_t calls{}; LONGLONG ticks{}; };
  struct Frame { std::array<Totals, count> totals{}; };
  struct State {
    std::uint64_t generation{};
    unsigned warmup{}, samples{}, depth{};
    bool active{}, pending{}, finished{};
    Frame current{};
    std::array<Frame, 240> frames{};
  };
  inline static thread_local State* current_{};
  struct Config {
    HANDLE log{INVALID_HANDLE_VALUE};
    LONGLONG frequency{};
    DWORD owner{};
    explicit Config(HMODULE module) {
      wchar_t path[32768]{};
      const auto length = GetModuleFileNameW(module, path, 32768);
      if (!length || length >= 32768) return;
      std::wstring flag(path, length);
      const auto split = flag.find_last_of(L"\\/");
      if (split == std::wstring::npos) return;
      flag.resize(split + 1);
      flag += L"darktidevr_present_cpu_profile.flag";
      if (GetPrivateProfileIntW(L"probe", L"enabled", 0, flag.c_str()) != 1) return;
      LARGE_INTEGER value{};
      if (!QueryPerformanceFrequency(&value) || value.QuadPart <= 0) return;
      frequency = value.QuadPart;
      wchar_t temp[MAX_PATH]{};
      const auto size = GetTempPathW(MAX_PATH, temp);
      if (!size || size >= MAX_PATH) return;
      const auto file = std::wstring(temp) + L"darktidevr-render-api-cpu-" +
          std::to_wstring(GetCurrentProcessId()) + L".log";
      log = CreateFileW(file.c_str(), GENERIC_WRITE, FILE_SHARE_READ | FILE_SHARE_DELETE, nullptr,
                        CREATE_ALWAYS, FILE_ATTRIBUTE_NORMAL, nullptr);
      owner = GetCurrentThreadId();
    }
    ~Config() { if (log != INVALID_HANDLE_VALUE) CloseHandle(log); }
  };
  State* state_{};
  static void emit(Config& config, const State& state) {
    constexpr const char* names[] = {"draw", "dispatch", "barrier", "pipeline", "binding", "execute"};
    std::string output;
    char line[256]{};
    auto n = std::snprintf(line, sizeof(line),
        "RENDER_API_CPU_BEGIN pid=%lu thread=%lu generation=%llu samples=%u warmup=600 scope=between_present original_api_included=1 outermost_only=1\n",
        GetCurrentProcessId(), config.owner, static_cast<unsigned long long>(state.generation), state.samples);
    if (n > 0 && n < static_cast<int>(sizeof(line))) output.append(line, n);
    for (unsigned sample = 0; sample < state.samples; ++sample) {
      for (unsigned kind = 0; kind < count; ++kind) {
        const auto& total = state.frames[sample].totals[kind];
        n = std::snprintf(line, sizeof(line), "RENDER_API_CPU sample=%u kind=%s calls=%llu wall_ms=%.6f\n",
            sample + 1, names[kind], static_cast<unsigned long long>(total.calls),
            double(total.ticks) * 1000 / config.frequency);
        if (n > 0 && n < static_cast<int>(sizeof(line))) output.append(line, n);
      }
    }
    DWORD written{};
    WriteFile(config.log, output.data(), static_cast<DWORD>(output.size()), &written, nullptr);
  }
 public:
  // Declare at Present entry. Destruction arms the following inter-Present interval.
  RenderApiCpuProfile(HMODULE module, std::uint64_t generation) {
    const auto error = GetLastError();
    static Config config(module);
    if (config.log != INVALID_HANDLE_VALUE && config.owner == GetCurrentThreadId()) {
      static thread_local std::unique_ptr<State> owned = std::make_unique<State>();
      current_ = owned.get();
      auto& state = *current_;
      state.active = false;
      if (state.generation != generation) state = State{generation};
      if (generation && !state.finished && state.warmup++ >= 600) {
        if (state.pending) state.frames[state.samples++] = state.current;
        state.current = {};
        state.pending = false;
        if (state.samples == state.frames.size()) {
          state.finished = true;
          emit(config, state);
        } else {
          state_ = &state;
        }
      }
    }
    SetLastError(error);
  }
  RenderApiCpuProfile(const RenderApiCpuProfile&) = delete;
  RenderApiCpuProfile& operator=(const RenderApiCpuProfile&) = delete;
  ~RenderApiCpuProfile() {
    if (state_) { state_->pending = true; state_->active = true; }
  }
  class Scope {
    State* state_{};
    Kind kind_{};
    LONGLONG begin_{};
    bool outer_{};
   public:
    explicit Scope(Kind kind) : kind_(kind) {
      if (current_ && current_->active) {
        const auto error = GetLastError();
        state_ = current_;
        outer_ = state_->depth++ == 0;
        if (outer_) {
          LARGE_INTEGER value{};
          QueryPerformanceCounter(&value);
          begin_ = value.QuadPart;
        }
        SetLastError(error);
      }
    }
    Scope(const Scope&) = delete;
    Scope& operator=(const Scope&) = delete;
    ~Scope() {
      if (!state_) return;
      const auto error = GetLastError();
      --state_->depth;
      if (outer_) {
        LARGE_INTEGER value{};
        QueryPerformanceCounter(&value);
        auto& total = state_->current.totals[kind_];
        ++total.calls;
        total.ticks += value.QuadPart - begin_;
      }
      SetLastError(error);
    }
  };
};
}
