#include "core/fingerprint.h"

#include <Windows.h>

#include <filesystem>
#include <fstream>
#include <iostream>
#include <optional>
#include <stdexcept>
#include <string>

namespace {

void usage() {
  std::cout
      << "DarktideVR build fingerprint tool\\n\\n"
      << "Usage: darktidevr-fingerprint --exe <Darktide.exe> "
         "[--game-root <directory>] [--output <report.json>]\\n\\n"
      << "This tool only reads files. It does not start or modify the game.\\n";
}
std::string utf8_from_wide(const std::wstring& value) {
  if (value.empty()) {
    return {};
  }
  const auto size = WideCharToMultiByte(CP_UTF8, 0, value.data(),
                                        static_cast<int>(value.size()), nullptr,
                                        0, nullptr, nullptr);
  std::string result(static_cast<std::size_t>(size), '\0');
  WideCharToMultiByte(CP_UTF8, 0, value.data(), static_cast<int>(value.size()),
                      result.data(), size, nullptr, nullptr);
  return result;
}

}  // namespace


int wmain(int argc, wchar_t** argv) {
  try {
    std::optional<std::filesystem::path> executable;
    std::optional<std::filesystem::path> game_root;
    std::optional<std::filesystem::path> output;

    for (int index = 1; index < argc; ++index) {
      const std::wstring argument = argv[index];
      if (argument == L"--help" || argument == L"-h") {
        usage();
        return 0;
      }
      if (index + 1 >= argc) {
        throw std::invalid_argument("Missing value after " +
                                    utf8_from_wide(argument));
      }
      if (argument == L"--exe") {
        executable = argv[++index];
      } else if (argument == L"--game-root") {
        game_root = argv[++index];
      } else if (argument == L"--output") {
        output = argv[++index];
      } else {
        throw std::invalid_argument("Unknown argument: " +
                                    utf8_from_wide(argument));
      }
    }

    if (!executable) {
      usage();
      return 2;
    }

    const auto report = darktidevr::fingerprint_json(
        darktidevr::fingerprint_build(*executable, game_root));
    if (output) {
      std::ofstream stream(*output, std::ios::binary | std::ios::trunc);
      if (!stream) {
        throw std::runtime_error("Unable to open output file");
      }
      stream << report;
    } else {
      std::cout << report;
    }
    return 0;
  } catch (const std::exception& error) {
    std::cerr << "darktidevr-fingerprint: " << error.what() << '\n';
    return 1;
  }
}
