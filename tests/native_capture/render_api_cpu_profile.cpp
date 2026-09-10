#include "producer/render_api_cpu_profile.h"
#include <filesystem>
#include <fstream>
#include <iterator>
#include <stdexcept>
#include <thread>

using Profile = darktidevr::producer::RenderApiCpuProfile;
void require(bool value) { if (!value) throw std::runtime_error("render API CPU profile check failed"); }
int main(int argc, char**) {
  const bool enabled = argc > 1;
  wchar_t module[MAX_PATH]{}, temp[MAX_PATH]{};
  require(GetModuleFileNameW(nullptr, module, MAX_PATH) > 0);
  require(GetTempPathW(MAX_PATH, temp) > 0);
  const auto flag = std::filesystem::path(module).parent_path() / "darktidevr_present_cpu_profile.flag";
  const auto log = std::filesystem::path(temp) /
      (L"darktidevr-render-api-cpu-" + std::to_wstring(GetCurrentProcessId()) + L".log");
  require(!std::filesystem::exists(flag));
  struct Cleanup {
    std::filesystem::path flag, log;
    ~Cleanup() { std::error_code error; std::filesystem::remove(flag, error); std::filesystem::remove(log, error); }
  } cleanup{flag, log};
  if (enabled) { std::ofstream output(flag); output << "[probe]\nenabled=1\n"; }
  for (unsigned i = 0; i < 1510; ++i) {
    SetLastError(1234);
    { Profile present(nullptr, i < 610 ? 1 : 2); }
    require(GetLastError() == 1234);
    if (i == 1220) {
      std::thread other([] { Profile::Scope draw(Profile::draw); });
      other.join();
    }
    {
      Profile::Scope draw(Profile::draw);
      Profile::Scope nested(Profile::dispatch);
      SetLastError(5678);
    }
    require(GetLastError() == 5678);
  }
  if (!enabled) { require(!std::filesystem::exists(log)); return 0; }
  std::ifstream input(log);
  const std::string contents{std::istreambuf_iterator<char>(input), {}};
  require(contents.find("generation=2 samples=240") != std::string::npos);
  require(contents.find("generation=1") == std::string::npos);
  unsigned draws{}, dispatches{}, rows{};
  std::size_t position{};
  while ((position = contents.find("RENDER_API_CPU sample=", position)) != std::string::npos) { ++rows; ++position; }
  position = 0;
  while ((position = contents.find("kind=draw calls=1", position)) != std::string::npos) { ++draws; ++position; }
  position = 0;
  while ((position = contents.find("kind=dispatch calls=0", position)) != std::string::npos) { ++dispatches; ++position; }
  require(rows == 1440 && draws == 240 && dispatches == 240);
  return 0;
}
