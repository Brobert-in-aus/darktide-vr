#include <Windows.h>
#include <atomic>
#include <array>
#include <cstdint>
#include <cstdio>
#include <cwchar>
#include <stdexcept>
#include <thread>
#include <vector>

// Debugger-style instruction-pointer residency, not an ETW CPU-time profile.
// While suspended, read context and a bounded stack excerpt, then immediately
// ResumeThread. No target-process allocation, locking, file I/O or waits occur.
struct Handle {
  HANDLE value{};
  ~Handle() { if (value && value != INVALID_HANDLE_VALUE) CloseHandle(value); }
};
struct Sample {
  LONGLONG qpc{}, pause_ticks{};
  DWORD64 rip{}, rsp{};
  std::array<DWORD64, 64> stack{};
  bool stack_read{};
  bool layout_read{};
  DWORD workers{}, commands{}, weighted_commands{}, history_commands{};
  BYTE weighted_enabled{};
  double history_cost{};
  struct Category { double cost{}; DWORD records{}, padding{}; };
  static_assert(sizeof(Category) == 16);
  std::array<Category, 4> categories{};
  bool categories_read{};
  DWORD queue_a{}, queue_b{};
  bool queues_read{};
  DWORD chunk_count{}, boundary_count{};
  std::array<DWORD, 32> chunk_starts{};
  bool chunks_read{};
  DWORD64 peer_rip{}, peer_rsp{};
  std::array<DWORD64, 64> peer_stack{};
  bool peer_read{}, peer_stack_read{};
};
std::uint64_t filetime(FILETIME value) {
  return (std::uint64_t(value.dwHighDateTime) << 32) | value.dwLowDateTime;
}
void require(bool condition, const char* message) {
  if (!condition) throw std::runtime_error(message);
}
void capture(DWORD pid, DWORD tid, unsigned count, unsigned interval,
             const wchar_t* expected_path, std::uint64_t expected_created,
             std::uint64_t engine_base = 0, DWORD peer_tid = 0) {
  Handle process{OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION | PROCESS_VM_READ | SYNCHRONIZE, FALSE, pid)};
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
  Handle peer{};
  if (peer_tid) {
    require(peer_tid != tid && peer_tid != GetCurrentThreadId(), "Peer must be a separate target thread");
    peer.value = OpenThread(THREAD_GET_CONTEXT | THREAD_SUSPEND_RESUME | THREAD_QUERY_LIMITED_INFORMATION,
                           FALSE, peer_tid);
    require(peer.value && GetProcessIdOfThread(peer.value) == pid, "Peer thread ownership mismatch");
  }
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
    context.ContextFlags = CONTEXT_CONTROL | CONTEXT_INTEGER;
    Sample sample{};
    LARGE_INTEGER before{}, after{};
    QueryPerformanceCounter(&before);
    if (before.QuadPart - started.QuadPart > frequency.QuadPart * 30) { failure = ERROR_TIMEOUT; break; }
    const auto previous = SuspendThread(thread.value);
    if (previous == DWORD(-1)) { failure = GetLastError(); break; }
    const auto retrieved = GetThreadContext(thread.value, &context);
    const auto context_error = retrieved ? ERROR_SUCCESS : GetLastError();
    SIZE_T bytes{};
    if (retrieved) {
      sample.stack_read = ReadProcessMemory(process.value, reinterpret_cast<const void*>(context.Rsp),
          sample.stack.data(), sizeof(sample.stack), &bytes) != FALSE && bytes == sizeof(sample.stack);
    }
    // Optional, exact-build layout observation at the verified nested wait.
    // The wrapper gates this to the known executable hash. All reads are bounded.
    if (engine_base && sample.stack_read && context.Rip >= engine_base + 0x6f77c4 &&
        context.Rip < engine_base + 0x6f77df && sample.stack[5] == engine_base + 0x6f9542 &&
        sample.stack[23] == engine_base + 0x7ac4aa) {
      const auto read = [&](DWORD64 address, void* output, SIZE_T size) {
        SIZE_T got{};
        return ReadProcessMemory(process.value, reinterpret_cast<const void*>(address), output, size, &got) && got == size;
      };
      // R13 is preserved by both wait helpers. The leaf saves its caller's RBP
      // at RSP+0x38; the list helper's active branch leaves that register intact.
      const auto frame = sample.stack[7];
      sample.layout_read = read(context.Rsi + 0xd0, &sample.workers, sizeof(sample.workers)) &&
          read(frame - 0x80, &sample.commands, sizeof(sample.commands)) &&
          read(frame - 0x38, &sample.weighted_commands, sizeof(sample.weighted_commands)) &&
          read(context.R13 + 0xf8, &sample.history_cost, sizeof(sample.history_cost)) &&
          read(context.R13 + 0x100, &sample.history_commands, sizeof(sample.history_commands)) &&
          read(context.R13 + 0x104, &sample.weighted_enabled, sizeof(sample.weighted_enabled));
      // The merge routine at 7a5d20 accumulates four 16-byte category records
      // through dispatcher+b0's array at +8. Workers own separate records;
      // this aggregate is merged by the paused caller only after the wait.
      DWORD category_count{};
      DWORD64 category_data{};
      sample.categories_read = sample.layout_read &&
          read(context.R13 + 0xb0, &category_count, sizeof(category_count)) && category_count == 4 &&
          read(context.R13 + 0xb8, &category_data, sizeof(category_data)) && category_data &&
          read(category_data, sample.categories.data(), sizeof(sample.categories));
      // 6f7690 assists from pool+110 and pool+e8; 6f7820 reads each
      // queue's count at +1c. Other workers remain running, so these are
      // sequential observations, not a mutually consistent queue snapshot.
      sample.queues_read = sample.layout_read &&
          read(context.Rsi + 0x104, &sample.queue_a, sizeof(sample.queue_a)) &&
          read(context.Rsi + 0x12c, &sample.queue_b, sizeof(sample.queue_b));
      // 7aa1c0 sets RBP=RSP+100 after its prolog. The splitter keeps
      // job count at RSP+64 and its boundary array at RSP+68/+70 until
      // cleanup after this wait. Read only a bounded weighted array.
      DWORD64 boundaries{};
      sample.chunks_read = sample.layout_read && sample.weighted_enabled &&
          read(frame - 0x9c, &sample.chunk_count, sizeof(sample.chunk_count)) &&
          read(frame - 0x98, &sample.boundary_count, sizeof(sample.boundary_count)) &&
          sample.boundary_count > 0 && sample.boundary_count <= sample.chunk_starts.size() &&
          sample.chunk_count == sample.boundary_count &&
          read(frame - 0x90, &boundaries, sizeof(boundaries)) && boundaries &&
          read(boundaries, sample.chunk_starts.data(), sample.boundary_count * sizeof(DWORD));
    }
    // Bounded paired observation: primary stays paused while the peer is read.
    // This is a perturbed overlap, not an atomic snapshot of a running engine.
    DWORD peer_error{};
    if (peer.value && previous == 0 && retrieved) {
      const auto peer_previous = SuspendThread(peer.value);
      if (peer_previous == DWORD(-1)) { peer_error = GetLastError(); }
      else {
        CONTEXT peer_context{};
        peer_context.ContextFlags = CONTEXT_CONTROL;
        sample.peer_read = GetThreadContext(peer.value, &peer_context) != FALSE;
        if (!sample.peer_read) peer_error = GetLastError();
        if (sample.peer_read) {
          sample.peer_rip = peer_context.Rip;
          sample.peer_rsp = peer_context.Rsp;
          SIZE_T got{};
          sample.peer_stack_read = ReadProcessMemory(process.value,
              reinterpret_cast<const void*>(peer_context.Rsp), sample.peer_stack.data(),
              sizeof(sample.peer_stack), &got) && got == sizeof(sample.peer_stack);
        }
        const auto peer_resumed = ResumeThread(peer.value);
        if (peer_resumed == DWORD(-1)) peer_error = GetLastError();
        else if (peer_previous != 0 || peer_resumed != peer_previous + 1) peer_error = ERROR_BUSY;
      }
    }
    // Exactly undo our increment, including a pre-existing suspension. Do not
    // drain someone else's suspend count or perform logging before this call.
    const auto resumed = ResumeThread(thread.value);
    const auto resume_error = resumed == DWORD(-1) ? GetLastError() : ERROR_SUCCESS;
    QueryPerformanceCounter(&after);
    if (resume_error) { failure = resume_error; break; }
    if (previous != 0 || resumed != previous + 1) { failure = ERROR_BUSY; break; }
    if (context_error) { failure = context_error; break; }
    if (peer_error) { failure = peer_error; break; }
    sample.qpc = before.QuadPart;
    sample.pause_ticks = after.QuadPart - before.QuadPart;
    sample.rip = context.Rip;
    sample.rsp = context.Rsp;
    samples.push_back(sample);
    Sleep(interval);
  }
  std::printf("RESIDENCY_BEGIN pid=%lu thread=%lu created=%llu frequency=%lld requested=%u samples=%zu interval_ms=%u failure=%lu\n",
      pid, tid, static_cast<unsigned long long>(expected_created), frequency.QuadPart, count, samples.size(), interval, failure);
  std::printf("qpc,rip,pause_us,rsp,stack_read");
  for (unsigned i = 0; i < 64; ++i) std::printf(",s%u", i);
  std::printf(",layout_read,workers,commands,weighted_commands,history_commands,weighted_enabled,history_cost,categories_read");
  for (unsigned i = 0; i < 4; ++i) std::printf(",category%u_cost,category%u_records", i, i);
  std::printf(",queues_read,queue_a,queue_b");
  std::printf(",chunks_read,chunk_count,boundary_count");
  for (unsigned i = 0; i < 32; ++i) std::printf(",chunk_start%u", i);
  if (peer_tid) {
    std::printf(",peer_thread,peer_read,peer_rip,peer_rsp,peer_stack_read");
    for (unsigned i = 0; i < 64; ++i) std::printf(",peer_s%u", i);
  }
  std::puts("");
  for (const auto& sample : samples) {
    std::printf("%lld,0x%llx,%.3f,0x%llx,%u", sample.qpc, sample.rip,
                double(sample.pause_ticks) * 1000000 / frequency.QuadPart, sample.rsp, unsigned(sample.stack_read));
    for (const auto value : sample.stack) std::printf(",0x%llx", value);
    std::printf(",%u,%lu,%lu,%lu,%lu,%u,%.9g,%u", unsigned(sample.layout_read), sample.workers,
        sample.commands, sample.weighted_commands, sample.history_commands,
        unsigned(sample.weighted_enabled), sample.history_cost, unsigned(sample.categories_read));
    for (const auto& category : sample.categories) std::printf(",%.9g,%lu", category.cost, category.records);
    std::printf(",%u,%lu,%lu", unsigned(sample.queues_read), sample.queue_a, sample.queue_b);
    std::printf(",%u,%lu,%lu", unsigned(sample.chunks_read), sample.chunk_count, sample.boundary_count);
    for (const auto value : sample.chunk_starts) std::printf(",%lu", value);
    if (peer_tid) {
      std::printf(",%lu,%u,0x%llx,0x%llx,%u", peer_tid, unsigned(sample.peer_read),
          sample.peer_rip, sample.peer_rsp, unsigned(sample.peer_stack_read));
      for (const auto value : sample.peer_stack) std::printf(",0x%llx", value);
    }
    std::puts("");
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
      std::atomic<DWORD> peer_tid{};
      std::thread worker([&] { tid.store(GetCurrentThreadId()); while (!stop.load()) YieldProcessor(); });
      std::thread peer_worker([&] { peer_tid.store(GetCurrentThreadId()); while (!stop.load()) YieldProcessor(); });
      while (!tid.load() || !peer_tid.load()) Sleep(1);
      try {
        capture(GetCurrentProcessId(), tid.load(), 10, 5, path, filetime(created));
        capture(GetCurrentProcessId(), tid.load(), 10, 5, path, filetime(created), 0, peer_tid.load());
        const auto peer_handle = static_cast<HANDLE>(peer_worker.native_handle());
        require(SuspendThread(peer_handle) == 0, "Peer pre-suspension failed");
        bool peer_rejected{};
        try { capture(GetCurrentProcessId(), tid.load(), 10, 5, path, filetime(created), 0, peer_tid.load()); }
        catch (const std::exception&) { peer_rejected = true; }
        const auto peer_restored = ResumeThread(peer_handle);
        require(peer_rejected && peer_restored == 1, "Did not preserve peer suspension");
        const auto handle = static_cast<HANDLE>(worker.native_handle());
        require(SuspendThread(handle) == 0, "Self-test pre-suspension failed");
        bool rejected{};
        try { capture(GetCurrentProcessId(), tid.load(), 10, 5, path, filetime(created)); }
        catch (const std::exception&) { rejected = true; }
        const auto restored = ResumeThread(handle);
        require(rejected && restored == 1, "Did not preserve pre-existing suspension");
      }
      catch (...) { stop.store(true); worker.join(); peer_worker.join(); throw; }
      stop.store(true); worker.join(); peer_worker.join();
      return 0;
    }
    require(argc >= 7 && argc <= 9, "Expected PID TID sample-count interval-ms exact-exe-path creation-filetime [verified-engine-base [peer-thread]]");
    const auto pid = std::wcstoul(argv[1], nullptr, 10);
    const auto tid = std::wcstoul(argv[2], nullptr, 10);
    const auto count = std::wcstoul(argv[3], nullptr, 10);
    const auto interval = std::wcstoul(argv[4], nullptr, 10);
    const auto created = _wcstoui64(argv[6], nullptr, 10);
    require(pid && tid && count >= 10 && count <= 2000 && interval >= 5 && interval <= 50 && count * interval <= 30000,
            "Invalid or unbounded capture arguments");
    capture(pid, tid, count, interval, argv[5], created, argc >= 8 ? _wcstoui64(argv[7], nullptr, 0) : 0,
            argc == 9 ? std::wcstoul(argv[8], nullptr, 10) : 0);
    return 0;
  } catch (const std::exception& error) {
    std::fprintf(stderr, "%s (Windows error %lu)\n", error.what(), GetLastError());
    return 1;
  }
}
