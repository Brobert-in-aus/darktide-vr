#include <Windows.h>
#define _WINMM_
#include <mmsystem.h>

#include <array>
#include <string>

namespace {

using TimeBeginPeriodFn = MMRESULT(WINAPI*)(UINT);
using TimeEndPeriodFn = MMRESULT(WINAPI*)(UINT);
using TimeGetDevCapsFn = MMRESULT(WINAPI*)(LPTIMECAPS, UINT);
using TimeGetTimeFn = DWORD(WINAPI*)();
using SetDiagnosticHooksFn = int (*)(int);
using SetBillboardShaderSubstitutionFn = int (*)(int);
using SetBillboardBasisFn = int (*)(float, float, float, float, float, float,
                                    int);
using InstallHooksFn = int (*)();

HMODULE proxy_module{};
INIT_ONCE real_winmm_once = INIT_ONCE_STATIC_INIT;
INIT_ONCE native_bootstrap_once = INIT_ONCE_STATIC_INIT;
INIT_ONCE native_schedule_once = INIT_ONCE_STATIC_INIT;
HMODULE real_winmm{};
TimeBeginPeriodFn real_time_begin_period{};
TimeEndPeriodFn real_time_end_period{};
TimeGetDevCapsFn real_time_get_dev_caps{};
TimeGetTimeFn real_time_get_time{};
thread_local bool native_bootstrap_in_progress{};
constexpr bool kEnableNativeBootstrap = true;

BOOL CALLBACK initialize_real_winmm(PINIT_ONCE, PVOID, PVOID*) {
  std::array<wchar_t, MAX_PATH> system_directory{};
  const auto length = GetSystemDirectoryW(
      system_directory.data(), static_cast<UINT>(system_directory.size()));
  if (length == 0 || length >= system_directory.size()) {
    return FALSE;
  }
  std::wstring path(system_directory.data(), length);
  path += L"\\winmm.dll";
  real_winmm = LoadLibraryW(path.c_str());
  if (!real_winmm) {
    return FALSE;
  }
  real_time_begin_period = reinterpret_cast<TimeBeginPeriodFn>(
      GetProcAddress(real_winmm, "timeBeginPeriod"));
  real_time_end_period = reinterpret_cast<TimeEndPeriodFn>(
      GetProcAddress(real_winmm, "timeEndPeriod"));
  real_time_get_dev_caps = reinterpret_cast<TimeGetDevCapsFn>(
      GetProcAddress(real_winmm, "timeGetDevCaps"));
  real_time_get_time = reinterpret_cast<TimeGetTimeFn>(
      GetProcAddress(real_winmm, "timeGetTime"));
  return real_time_begin_period && real_time_end_period &&
                 real_time_get_dev_caps && real_time_get_time
             ? TRUE
             : FALSE;
}

bool ensure_real_winmm() {
  return InitOnceExecuteOnce(&real_winmm_once, initialize_real_winmm, nullptr,
                             nullptr) != FALSE;
}

BOOL CALLBACK initialize_native_capture(PINIT_ONCE, PVOID, PVOID*) {
  native_bootstrap_in_progress = true;
  std::array<wchar_t, 32768> module_path{};
  const auto length = GetModuleFileNameW(
      proxy_module, module_path.data(), static_cast<DWORD>(module_path.size()));
  if (length == 0 || length >= module_path.size()) {
    native_bootstrap_in_progress = false;
    return FALSE;
  }
  std::wstring path(module_path.data(), length);
  const auto separator = path.find_last_of(L"\\/");
  if (separator == std::wstring::npos) {
    native_bootstrap_in_progress = false;
    return FALSE;
  }
  path.resize(separator + 1);
  path += L"..\\mods\\darktidevr\\bin\\"
          L"darktidevr_native_capture.dll";
  const auto native = LoadLibraryW(path.c_str());
  if (!native) {
    native_bootstrap_in_progress = false;
    return FALSE;
  }
  const auto select_diagnostics = reinterpret_cast<SetDiagnosticHooksFn>(
      GetProcAddress(native, "dtvr_set_diagnostic_render_hooks"));
  const auto set_billboard_basis = reinterpret_cast<SetBillboardBasisFn>(
      GetProcAddress(native, "dtvr_set_billboard_view_basis"));
  const auto set_billboard_shader_substitution =
      reinterpret_cast<SetBillboardShaderSubstitutionFn>(GetProcAddress(
          native, "dtvr_set_billboard_shader_substitution"));
  const auto install = reinterpret_cast<InstallHooksFn>(
      GetProcAddress(native, "dtvr_install"));
  const bool initialized =
      select_diagnostics && set_billboard_shader_substitution &&
      set_billboard_basis && install && select_diagnostics(0) == 0 &&
      set_billboard_shader_substitution(1) == 0 &&
      set_billboard_basis(1.0F, 0.0F, 0.0F, 0.0F, 0.0F, 1.0F, 0) == 0 &&
      install() == 0;
  native_bootstrap_in_progress = false;
  return initialized ? TRUE : FALSE;
}

DWORD WINAPI native_capture_worker(LPVOID) {
  InitOnceExecuteOnce(&native_bootstrap_once, initialize_native_capture,
                      nullptr, nullptr);
  return 0;
}

BOOL CALLBACK schedule_native_capture(PINIT_ONCE, PVOID, PVOID*) {
  const auto thread =
      CreateThread(nullptr, 0, native_capture_worker, nullptr, 0, nullptr);
  if (!thread) {
    return FALSE;
  }
  CloseHandle(thread);
  return TRUE;
}

void ensure_native_capture() {
  if (kEnableNativeBootstrap && !native_bootstrap_in_progress) {
    InitOnceExecuteOnce(&native_schedule_once, schedule_native_capture, nullptr,
                        nullptr);
  }
}

template <typename Function>
Function resolve_real(const char* name) {
  if (!ensure_real_winmm()) {
    return nullptr;
  }
  return reinterpret_cast<Function>(GetProcAddress(real_winmm, name));
}

}  // namespace

extern "C" MMRESULT WINAPI timeBeginPeriod(UINT period) {
  if (!ensure_real_winmm()) {
    return TIMERR_NOCANDO;
  }
  ensure_native_capture();
  return real_time_begin_period(period);
}

extern "C" MMRESULT WINAPI timeEndPeriod(UINT period) {
  if (!ensure_real_winmm()) {
    return TIMERR_NOCANDO;
  }
  ensure_native_capture();
  return real_time_end_period(period);
}

extern "C" MMRESULT WINAPI timeGetDevCaps(LPTIMECAPS capabilities,
                                           UINT capabilities_size) {
  if (!ensure_real_winmm()) {
    return TIMERR_NOCANDO;
  }
  ensure_native_capture();
  return real_time_get_dev_caps(capabilities, capabilities_size);
}

extern "C" DWORD WINAPI timeGetTime() {
  if (!ensure_real_winmm()) {
    return 0;
  }
  ensure_native_capture();
  return real_time_get_time();
}

#define DTVR_FORWARD_MMRESULT(name, signature, arguments)                       \
  extern "C" MMRESULT WINAPI name signature {                                 \
    const auto function = resolve_real<decltype(&::name)>(#name);              \
    return function ? function arguments : MMSYSERR_ERROR;                     \
  }

DTVR_FORWARD_MMRESULT(waveOutOpen,
                      (LPHWAVEOUT output, UINT device_id,
                       LPCWAVEFORMATEX format, DWORD_PTR callback,
                       DWORD_PTR callback_instance, DWORD flags),
                      (output, device_id, format, callback, callback_instance,
                       flags))
DTVR_FORWARD_MMRESULT(waveOutPrepareHeader,
                      (HWAVEOUT output, LPWAVEHDR header, UINT header_size),
                      (output, header, header_size))
DTVR_FORWARD_MMRESULT(waveOutGetDevCapsA,
                      (UINT_PTR device_id, LPWAVEOUTCAPSA capabilities,
                       UINT capabilities_size),
                      (device_id, capabilities, capabilities_size))
DTVR_FORWARD_MMRESULT(waveOutMessage,
                      (HWAVEOUT output, UINT message, DWORD_PTR parameter1,
                       DWORD_PTR parameter2),
                      (output, message, parameter1, parameter2))
DTVR_FORWARD_MMRESULT(waveOutClose, (HWAVEOUT output), (output))
DTVR_FORWARD_MMRESULT(waveOutReset, (HWAVEOUT output), (output))
DTVR_FORWARD_MMRESULT(waveOutWrite,
                      (HWAVEOUT output, LPWAVEHDR header, UINT header_size),
                      (output, header, header_size))

extern "C" UINT WINAPI waveOutGetNumDevs() {
  const auto function =
      resolve_real<decltype(&::waveOutGetNumDevs)>("waveOutGetNumDevs");
  return function ? function() : 0;
}

DTVR_FORWARD_MMRESULT(waveInGetDevCapsA,
                      (UINT_PTR device_id, LPWAVEINCAPSA capabilities,
                       UINT capabilities_size),
                      (device_id, capabilities, capabilities_size))
DTVR_FORWARD_MMRESULT(waveInMessage,
                      (HWAVEIN input, UINT message, DWORD_PTR parameter1,
                       DWORD_PTR parameter2),
                      (input, message, parameter1, parameter2))
DTVR_FORWARD_MMRESULT(waveInClose, (HWAVEIN input), (input))
DTVR_FORWARD_MMRESULT(waveInReset, (HWAVEIN input), (input))
DTVR_FORWARD_MMRESULT(waveInStart, (HWAVEIN input), (input))
DTVR_FORWARD_MMRESULT(waveInAddBuffer,
                      (HWAVEIN input, LPWAVEHDR header, UINT header_size),
                      (input, header, header_size))
DTVR_FORWARD_MMRESULT(waveInPrepareHeader,
                      (HWAVEIN input, LPWAVEHDR header, UINT header_size),
                      (input, header, header_size))
DTVR_FORWARD_MMRESULT(waveInOpen,
                      (LPHWAVEIN input, UINT device_id,
                       LPCWAVEFORMATEX format, DWORD_PTR callback,
                       DWORD_PTR callback_instance, DWORD flags),
                      (input, device_id, format, callback, callback_instance,
                       flags))

extern "C" UINT WINAPI waveInGetNumDevs() {
  const auto function =
      resolve_real<decltype(&::waveInGetNumDevs)>("waveInGetNumDevs");
  return function ? function() : 0;
}

#undef DTVR_FORWARD_MMRESULT

BOOL WINAPI DllMain(HINSTANCE instance, DWORD reason, LPVOID) {
  if (reason == DLL_PROCESS_ATTACH) {
    proxy_module = instance;
    DisableThreadLibraryCalls(instance);
  }
  return TRUE;
}
