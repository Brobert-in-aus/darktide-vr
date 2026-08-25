#include <Windows.h>
#include <TlHelp32.h>

#include <chrono>
#include <cstdint>
#include <cstdio>
#include <string>

namespace {

constexpr DWORD64 kBreakpointControlMask = 0xFULL << 16;
constexpr DWORD64 kBreakpointEnableMask = 0x3ULL;

bool set_write_breakpoint(DWORD thread_id, std::uintptr_t address,
                          bool enabled) {
  const auto thread = OpenThread(THREAD_GET_CONTEXT | THREAD_SET_CONTEXT,
                                 FALSE, thread_id);
  if (!thread) {
    return false;
  }
  CONTEXT context{};
  context.ContextFlags = CONTEXT_DEBUG_REGISTERS;
  const auto read = GetThreadContext(thread, &context) != FALSE;
  if (read) {
    context.Dr0 = enabled ? address : 0;
    context.Dr6 = 0;
    context.Dr7 &= ~(kBreakpointControlMask | kBreakpointEnableMask);
    if (enabled) {
      // Local slot 0, write access, four-byte length.
      context.Dr7 |= 1ULL | (1ULL << 16) | (3ULL << 18);
    }
  }
  const auto written = read && SetThreadContext(thread, &context) != FALSE;
  CloseHandle(thread);
  return written;
}

void set_all_thread_breakpoints(DWORD process_id, std::uintptr_t address,
                                bool enabled) {
  const auto snapshot = CreateToolhelp32Snapshot(TH32CS_SNAPTHREAD, 0);
  if (snapshot == INVALID_HANDLE_VALUE) {
    return;
  }
  THREADENTRY32 entry{};
  entry.dwSize = sizeof(entry);
  if (Thread32First(snapshot, &entry)) {
    do {
      if (entry.th32OwnerProcessID == process_id) {
        set_write_breakpoint(entry.th32ThreadID, address, enabled);
      }
    } while (Thread32Next(snapshot, &entry));
  }
  CloseHandle(snapshot);
}

std::string module_location(DWORD process_id, std::uintptr_t address) {
  const auto snapshot = CreateToolhelp32Snapshot(
      TH32CS_SNAPMODULE | TH32CS_SNAPMODULE32, process_id);
  if (snapshot == INVALID_HANDLE_VALUE) {
    return "unknown";
  }
  MODULEENTRY32W entry{};
  entry.dwSize = sizeof(entry);
  std::string result = "unknown";
  if (Module32FirstW(snapshot, &entry)) {
    do {
      const auto base = reinterpret_cast<std::uintptr_t>(entry.modBaseAddr);
      if (address >= base && address - base < entry.modBaseSize) {
        char name[MAX_PATH]{};
        WideCharToMultiByte(CP_UTF8, 0, entry.szModule, -1, name,
                            static_cast<int>(sizeof(name)), nullptr, nullptr);
        char label[MAX_PATH + 40]{};
        std::snprintf(label, sizeof(label), "%s+0x%llx", name,
                      static_cast<unsigned long long>(address - base));
        result = label;
        break;
      }
    } while (Module32NextW(snapshot, &entry));
  }
  CloseHandle(snapshot);
  return result;
}

}  // namespace

int wmain(int argc, wchar_t** argv) {
  if (argc != 5) {
    std::fwprintf(stderr,
                  L"usage: darktidevr_watch_write <pid> <hex-address> "
                  L"<duration-ms> <output.tsv>\n");
    return 2;
  }
  const auto process_id = static_cast<DWORD>(std::wcstoul(argv[1], nullptr, 0));
  const auto address = static_cast<std::uintptr_t>(
      std::wcstoull(argv[2], nullptr, 0));
  const auto duration = std::chrono::milliseconds(
      static_cast<long long>(std::wcstoull(argv[3], nullptr, 0)));
  if (!process_id || !address || duration.count() <= 0) {
    return 3;
  }
  FILE* output{};
  if (_wfopen_s(&output, argv[4], L"wb") != 0 || !output) {
    return 4;
  }
  std::fprintf(output, "event\tthread\trip\tlocation\tdr6\n");
  std::fflush(output);

  DebugSetProcessKillOnExit(FALSE);
  if (!DebugActiveProcess(process_id)) {
    std::fprintf(output, "attach_failed\t0\t0\terror=%lu\t0\n",
                 GetLastError());
    std::fclose(output);
    return 5;
  }

  const auto deadline = std::chrono::steady_clock::now() + duration;
  unsigned hit_count{};
  bool initialized{};
  while (std::chrono::steady_clock::now() < deadline && hit_count < 32) {
    DEBUG_EVENT event{};
    if (!WaitForDebugEvent(&event, 100)) {
      continue;
    }
    DWORD continue_status = DBG_CONTINUE;
    if (!initialized) {
      set_all_thread_breakpoints(process_id, address, true);
      initialized = true;
    }
    if (event.dwDebugEventCode == CREATE_THREAD_DEBUG_EVENT) {
      set_write_breakpoint(event.dwThreadId, address, true);
      CloseHandle(event.u.CreateThread.hThread);
    } else if (event.dwDebugEventCode == CREATE_PROCESS_DEBUG_EVENT) {
      set_write_breakpoint(event.dwThreadId, address, true);
      CloseHandle(event.u.CreateProcessInfo.hFile);
      CloseHandle(event.u.CreateProcessInfo.hThread);
      CloseHandle(event.u.CreateProcessInfo.hProcess);
    } else if (event.dwDebugEventCode == LOAD_DLL_DEBUG_EVENT) {
      CloseHandle(event.u.LoadDll.hFile);
    } else if (event.dwDebugEventCode == EXCEPTION_DEBUG_EVENT) {
      const auto code = event.u.Exception.ExceptionRecord.ExceptionCode;
      if (code == EXCEPTION_SINGLE_STEP) {
        const auto thread = OpenThread(THREAD_GET_CONTEXT, FALSE,
                                       event.dwThreadId);
        CONTEXT context{};
        context.ContextFlags = CONTEXT_CONTROL | CONTEXT_DEBUG_REGISTERS;
        if (thread && GetThreadContext(thread, &context) &&
            (context.Dr6 & 1ULL) != 0) {
          const auto location = module_location(
              process_id, static_cast<std::uintptr_t>(context.Rip));
          std::fprintf(output, "write\t%lu\t0x%llx\t%s\t0x%llx\n",
                       event.dwThreadId,
                       static_cast<unsigned long long>(context.Rip),
                       location.c_str(),
                       static_cast<unsigned long long>(context.Dr6));
          std::fflush(output);
          ++hit_count;
        }
        if (thread) {
          CloseHandle(thread);
        }
      } else if (code != EXCEPTION_BREAKPOINT) {
        continue_status = DBG_EXCEPTION_NOT_HANDLED;
      }
    }
    ContinueDebugEvent(event.dwProcessId, event.dwThreadId, continue_status);
  }

  set_all_thread_breakpoints(process_id, address, false);
  DebugActiveProcessStop(process_id);
  std::fprintf(output, "complete\t0\t0\thits=%u\t0\n", hit_count);
  std::fclose(output);
  return 0;
}
