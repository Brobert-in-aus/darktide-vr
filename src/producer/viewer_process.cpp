#include "producer/viewer_process.h"

#include <Windows.h>

#include <array>
#include <mutex>
#include <string>

namespace darktidevr::producer::viewer {
namespace {

struct ViewerState {
  std::mutex mutex;
  HANDLE process{};
  HANDLE job{};
  HANDLE log{};
  std::wstring stop_file;
  int last_exit_code{-1};
  int starts{};
  DWORD last_error{};
};

ViewerState& viewer_state() {
  static ViewerState state;
  return state;
}

std::wstring module_directory() {
  HMODULE module{};
  if (!GetModuleHandleExW(GET_MODULE_HANDLE_EX_FLAG_FROM_ADDRESS |
                              GET_MODULE_HANDLE_EX_FLAG_UNCHANGED_REFCOUNT,
                          reinterpret_cast<LPCWSTR>(&module_directory),
                          &module)) {
    return {};
  }
  std::array<wchar_t, 32768> path{};
  const auto length =
      GetModuleFileNameW(module, path.data(), static_cast<DWORD>(path.size()));
  if (length == 0 || length >= path.size()) {
    return {};
  }
  std::wstring directory(path.data(), length);
  const auto separator = directory.find_last_of(L"\\/");
  if (separator == std::wstring::npos) {
    return {};
  }
  directory.resize(separator + 1);
  return directory;
}

std::wstring viewer_executable() {
  const auto directory = module_directory();
  return directory.empty() ? std::wstring{}
                           : directory + L"darktidevr-xr-harness.exe";
}

std::wstring output_directory() {
  std::array<wchar_t, 32768> value{};
  const auto length = GetEnvironmentVariableW(L"LOCALAPPDATA", value.data(),
                                              static_cast<DWORD>(value.size()));
  if (length == 0 || length >= value.size()) {
    return {};
  }
  std::wstring directory(value.data(), length);
  directory += L"\\DarktideVR\\";
  CreateDirectoryW(directory.c_str(), nullptr);
  return directory;
}

// Reaps a finished child so state() reports the exit instead of a stale run.
void reap_locked(ViewerState& state) {
  if (!state.process) {
    return;
  }
  if (WaitForSingleObject(state.process, 0) != WAIT_OBJECT_0) {
    return;
  }
  DWORD code{};
  state.last_exit_code =
      GetExitCodeProcess(state.process, &code) ? static_cast<int>(code) : -1;
  CloseHandle(state.process);
  state.process = nullptr;
  if (state.job) {
    CloseHandle(state.job);
    state.job = nullptr;
  }
  if (state.log) {
    CloseHandle(state.log);
    state.log = nullptr;
  }
  if (!state.stop_file.empty()) {
    DeleteFileW(state.stop_file.c_str());
  }
}

int start_locked(ViewerState& state) {
  reap_locked(state);
  if (state.process) {
    return 0;
  }
  const auto executable = viewer_executable();
  if (executable.empty() ||
      GetFileAttributesW(executable.c_str()) == INVALID_FILE_ATTRIBUTES) {
    state.last_error = ERROR_FILE_NOT_FOUND;
    return 2;
  }
  const auto directory = output_directory();
  if (directory.empty()) {
    state.last_error = ERROR_PATH_NOT_FOUND;
    return 3;
  }
  const auto pid = std::to_wstring(GetCurrentProcessId());
  state.stop_file = directory + L"viewer-stop-" + pid + L".flag";
  DeleteFileW(state.stop_file.c_str());

  SECURITY_ATTRIBUTES inheritable{};
  inheritable.nLength = sizeof(inheritable);
  inheritable.bInheritHandle = TRUE;
  const auto log_path = directory + L"viewer-" + pid + L".log";
  state.log = CreateFileW(log_path.c_str(), GENERIC_WRITE, FILE_SHARE_READ,
                          &inheritable, CREATE_ALWAYS, FILE_ATTRIBUTE_NORMAL,
                          nullptr);
  if (state.log == INVALID_HANDLE_VALUE) {
    state.log = nullptr;
    state.last_error = GetLastError();
    return 4;
  }

  // The accepted play configuration: shared-eye projection, menu pointer
  // input, the gameplay reticle and a whole-session duration. The stop file
  // gives the viewer an orderly exit; the job object ends it with the game.
  std::wstring command = L"\"" + executable + L"\"";
  command += L" --shared-eyes --require-rendering --frames 30";
  command += L" --xr-seconds 86400";
  command += L" --capture-window-title \"Warhammer 40,000: Darktide\"";
  command += L" --enable-menu-input --enable-gameplay-reticle";
  command += L" --projection-translation-scale 1.0";
  command += L" --stop-file \"" + state.stop_file + L"\"";

  STARTUPINFOW startup{};
  startup.cb = sizeof(startup);
  startup.dwFlags = STARTF_USESTDHANDLES;
  startup.hStdOutput = state.log;
  startup.hStdError = state.log;
  startup.hStdInput = nullptr;
  PROCESS_INFORMATION information{};
  const auto created = CreateProcessW(
      executable.c_str(), command.data(), nullptr, nullptr, TRUE,
      CREATE_NO_WINDOW | CREATE_SUSPENDED, nullptr,
      module_directory().c_str(), &startup, &information);
  if (!created) {
    state.last_error = GetLastError();
    CloseHandle(state.log);
    state.log = nullptr;
    return 5;
  }
  state.job = CreateJobObjectW(nullptr, nullptr);
  if (state.job) {
    JOBOBJECT_EXTENDED_LIMIT_INFORMATION limits{};
    limits.BasicLimitInformation.LimitFlags =
        JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE;
    if (!SetInformationJobObject(state.job, JobObjectExtendedLimitInformation,
                                 &limits, sizeof(limits)) ||
        !AssignProcessToJobObject(state.job, information.hProcess)) {
      // A host job without nesting rights leaves the viewer unbound; it still
      // stops through the stop file and the process handle.
      state.last_error = GetLastError();
      CloseHandle(state.job);
      state.job = nullptr;
    }
  }
  ResumeThread(information.hThread);
  CloseHandle(information.hThread);
  state.process = information.hProcess;
  state.last_exit_code = -1;
  ++state.starts;
  return 0;
}

int stop_locked(ViewerState& state) {
  reap_locked(state);
  if (!state.process) {
    return 0;
  }
  if (!state.stop_file.empty()) {
    const auto stop = CreateFileW(state.stop_file.c_str(), GENERIC_WRITE, 0,
                                  nullptr, CREATE_ALWAYS,
                                  FILE_ATTRIBUTE_NORMAL, nullptr);
    if (stop != INVALID_HANDLE_VALUE) {
      CloseHandle(stop);
    }
  }
  if (WaitForSingleObject(state.process, 5000) != WAIT_OBJECT_0) {
    TerminateProcess(state.process, 0xdead);
    WaitForSingleObject(state.process, 2000);
  }
  reap_locked(state);
  if (state.process) {
    state.last_error = GetLastError();
    return 6;
  }
  return 0;
}

}  // namespace

int control(bool enabled) {
  auto& state = viewer_state();
  std::scoped_lock lock(state.mutex);
  return enabled ? start_locked(state) : stop_locked(state);
}

int state(int* values, unsigned int count) {
  if (!values || count < 5) {
    return 1;
  }
  auto& viewer = viewer_state();
  std::scoped_lock lock(viewer.mutex);
  reap_locked(viewer);
  values[0] = viewer.process ? 1 : 0;
  values[1] = viewer.last_exit_code;
  values[2] = viewer.starts;
  values[3] = static_cast<int>(viewer.last_error);
  const auto executable = viewer_executable();
  values[4] = !executable.empty() &&
                      GetFileAttributesW(executable.c_str()) !=
                          INVALID_FILE_ATTRIBUTES
                  ? 1
                  : 0;
  return 0;
}

}  // namespace darktidevr::producer::viewer
