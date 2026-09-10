#include "producer/present_cpu_profile.h"
#include <filesystem>
#include <fstream>
#include <iostream>
#include <set>
#include <thread>
#include <vector>

int main(int argc, char**) {
  const bool enabled = argc > 1;
  wchar_t executable[32768]{}, temp[MAX_PATH]{};
  if (!GetModuleFileNameW(nullptr, executable, 32768) || !GetTempPathW(MAX_PATH, temp)) return 1;
  const auto flag = std::filesystem::path(executable).parent_path() / L"darktidevr_present_cpu_profile.flag";
  const auto log = std::filesystem::path(temp) / (L"darktidevr-present-cpu-" + std::to_wstring(GetCurrentProcessId()) + L".log");
  if (std::filesystem::exists(flag) || std::filesystem::exists(log)) return 2;
  if (enabled) { std::ofstream output(flag); output << "[probe]\nenabled=1\n"; }
  bool error_preserved = true;
  for (unsigned i = 0; i < 700; ++i) {
    SetLastError(1234);
    {
      darktidevr::producer::PresentCpuProfile profile(nullptr, i % 2 + 1);
      error_preserved = error_preserved && GetLastError() == 1234;
      SetLastError(4321);
    }
    error_preserved = error_preserved && GetLastError() == 4321;
  }
  // Generation changes must restart warm-up; there must be no samples yet.
  std::string line;
  unsigned before{};
  { std::ifstream input(log); while (std::getline(input, line)) if (line.starts_with("PRESENT_CPU sample=")) ++before; }
  std::vector<std::thread> workers;
  for (unsigned n = 0; n < 4; ++n) workers.emplace_back([] {
    for (unsigned i = 0; i < 1000; ++i) {
      darktidevr::producer::PresentCpuProfile profile(nullptr, 9);
      SwitchToThread();
    }
  });
  for (auto& worker : workers) worker.join();
  unsigned records{};
  std::set<unsigned> samples;
  { std::ifstream input(log); while (std::getline(input, line)) {
      if (line.starts_with("PRESENT_CPU sample=")) {
        ++records;
        samples.insert(static_cast<unsigned>(std::stoul(line.substr(19))));
      }
    }
  }
  if (enabled) std::filesystem::remove(flag);
  // The profile owns the open log until process exit. It lives only in TEMP.
  if (!error_preserved || before || records != (enabled ? 240U : 0U) || samples.size() != records) return 3;
  if (!enabled && std::filesystem::exists(log)) return 4;
  std::cout << "present_cpu_profile=pass enabled=" << enabled << " records=" << records << '\n';
  return 0;
}
