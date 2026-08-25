#pragma once

#include <cstdint>
#include <filesystem>
#include <optional>
#include <string>

namespace darktidevr {

struct BuildFingerprint {
  std::filesystem::path executable;
  std::uintmax_t executable_size{};
  std::string sha256;
  std::string file_version;
  std::string product_version;
  std::optional<std::string> game_version;
  std::optional<std::string> game_revision;
  std::optional<std::string> content_revision;
};

BuildFingerprint fingerprint_build(
    const std::filesystem::path& executable,
    const std::optional<std::filesystem::path>& game_root);

std::string fingerprint_json(const BuildFingerprint& fingerprint);

}  // namespace darktidevr
