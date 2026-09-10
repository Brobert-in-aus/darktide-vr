#include <Windows.h>
#include <atomic>
#include <cstdint>
#include <cstdio>
#include <cwchar>
#include <stdexcept>
#include <thread>
#include <vector>

// Debugger-style instruction-pointer residency, not an ETW CPU-time profile.
// While suspended, perform only GetThreadContext followed immediately by one
// ResumeThread. No target-process allocation, locking, I/O or waits occur.
struct Handle {
  HANDLE value{};
  ~Handle() { if (value && value != INVALID_HANDLE_VALUE) CloseHandle(value); }
};
struct Sample { LONGLONG qpc{}, pause_ticks{}; DWORD64 rip{}; };
std::uint64_t filetime(FILETIME value) {
  return (std::uint64_t(value.dwHighDateTime) << 32) | value.dwLowDateTime;
}
void require(bool condition, const char* message) {
  if (!condition) throw std::runtime_error(message);
}
void capture(DWORD pid, DWORD tid, unsigned count, unsigned interval,
             const wchar_t* expected_path, std::uint64_t expected_created) {
  Handle process{OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION | SYNCHRONIZE, FALSE, pid)};
  require(process.value != nullptr, "OpenProcess failed");
  wchar_t path[32768]{};
  DWORD length = 32768;
  require(QueryFullProcessImageNameW(process.value, 0, path, &length) != FALSE, "Process path unavailable");
  require(_wcsicmp(path, expected_path) == 0, "Process path mismatch");
  FILETIME created{}, exited{}, kernel{}, user{};
  require(GetProcessTimes(process.value, &created, &exited, &kernel, &user) != FALSE, "Process lifetime unavailable");
  require(filetime(created) == expected_created, "Process lifetime mismatch");
  Handle thread{OpenThread(THREAD_GET_CONTEXT | THREAD_SUSPEND_RESUME | THREAD_QUERY_LIMITED_INFORMATION,
                           FALSE, tid)};
  require(thread.value != nullptr, "OpenThread failed");
  require(GetProcessIdOfThread(thread.value) == pid, "Thread belongs to another process");
  require(GetThreadId(thread.value) != GetCurrentThreadId(), "Cannot sample calling thread");
  LARGE_INTEGER frequency{};
  require(QueryPerformanceFrequency(&frequency) != FALSE, "QPC unavailable");
  std::vector<Sample> samples;
  samples.reserve(count);
  DWORD failure{};
  LARGE_INTEGER started{};
  QueryPerformanceCounter(&started);
  for (unsigned i = 0; i < count; ++i) {
    if (WaitForSingleObject(process.value, 0) != WAIT_TIMEOUT) { failure = ERROR_PROCESS_ABORTED; break; }
    CONTEXT context{};
    context.ContextFlags = CONTEXT_CONTROL;
    LARGE_INTEGER before{}, after{};
    QueryPerformanceCounter(&before);
    if (before.QuadPart - started.QuadPart > frequency.QuadPart * 30) { failure = ERROR_TIMEOUT; break; }
    const auto previous = SuspendThread(thread.value);
    if (previous == DWORD(-1)) { failure = GetLastError(); break; }
    const auto retrieved = GetThreadContext(thread.value, &context);
    const auto context_error = retrieved ? ERROR_SUCCESS : GetLastError();
    // Exactly undo our increment, including a pre-existing suspension. Do not
    // drain someone else's suspend count or perform logging before this call.
    const auto resumed = ResumeThread(thread.value);
    const auto resume_error = resumed == DWORD(-1) ? GetLastError() : ERROR_SUCCESS;
    QueryPerformanceCounter(&after);
    if (resume_error) { failure = resume_error; break; }
    if (previous != 0 || resumed != previous + 1) { failure = ERROR_BUSY; break; }
    if (context_error) { failure = context_error; break; }
    samples.push_back({before.QuadPart, after.QuadPart - before.QuadPart, context.Rip});
    Sleep(interval);
  }
  std::printf("RESIDENCY_BEGIN pid=%lu thread=%lu created=%llu frequency=%lld requested=%u samples=%zu interval_ms=%u failure=%lu\n",
      pid, tid, static_cast<unsigned long long>(expected_created), frequency.QuadPart, count, samples.size(), interval, failure);
  std::puts("qpc,rip,pause_us");
  for (const auto& sample : samples) {
    std::printf("%lld,0x%llx,%.3f\n", sample.qpc, sample.rip,
                double(sample.pause_ticks) * 1000000 / frequency.QuadPart);
  }
  require(failure == ERROR_SUCCESS && samples.size() == count, "Incomplete residency capture; inspect failure code");
}
int wmain(int argc, wchar_t** argv) {
  try {
    if (argc == 2 && std::wcscmp(argv[1], L"--self-test") == 0) {
      wchar_t path[32768]{};
      require(GetModuleFileNameW(nullptr, path, 32768) > 0, "Self path unavailable");
      FILETIME created{}, exited{}, kernel{}, user{};
      require(GetProcessTimes(GetCurrentProcess(), &created, &exited, &kernel, &user) != FALSE, "Self lifetime unavailable");
      std::atomic<bool> stop{};
      std::atomic<DWORD> tid{};
      std::thread worker([&] { tid.store(GetCurrentThreadId()); while (!stop.load()) YieldProcessor(); });
      while (!tid.load()) Sleep(1);
      try {
        capture(GetCurrentProcessId(), tid.load(), 10, 5, path, filetime(created));
        const auto handle = static_cast<HANDLE>(worker.native_handle());
        require(SuspendThread(handle) == 0, "Self-test pre-suspension failed");
        bool rejected{};
        try { capture(GetCurrentProcessId(), tid.load(), 10, 5, path, filetime(created)); }
        catch (const std::exception&) { rejected = true; }
        const auto restored = ResumeThread(handle);
        require(rejected && restored == 1, "Did not preserve pre-existing suspension");
      }
      catch (...) { stop.store(true); worker.join(); throw; }
      stop.store(true); worker.join();
      return 0;
    }
    require(argc == 7, "Expected PID TID sample-count interval-ms exact-exe-path creation-filetime");
    const auto pid = std::wcstoul(argv[1], nullptr, 10);
    const auto tid = std::wcstoul(argv[2], nullptr, 10);
    const auto count = std::wcstoul(argv[3], nullptr, 10);
    const auto interval = std::wcstoul(argv[4], nullptr, 10);
    const auto created = _wcstoui64(argv[6], nullptr, 10);
    require(pid && tid && count >= 10 && count <= 2000 && interval >= 5 && interval <= 50 && count * interval <= 30000,
            "Invalid or unbounded capture arguments");
    capture(pid, tid, count, interval, argv[5], created);
    return 0;
  } catch (const std::exception& error) {
    std::fprintf(stderr, "%s (Windows error %lu)\n", error.what(), GetLastError());
    return 1;
  }
}
