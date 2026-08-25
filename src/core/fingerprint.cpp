#include "core/fingerprint.h"

#include <Windows.h>
#include <bcrypt.h>

#include <array>
#include <cctype>
#include <fstream>
#include <iomanip>
#include <regex>
#include <sstream>
#include <stdexcept>
#include <vector>

namespace darktidevr {
namespace {

class AlgorithmProvider {
 public:
  AlgorithmProvider() {
    const auto status = BCryptOpenAlgorithmProvider(
        &handle_, BCRYPT_SHA256_ALGORITHM, nullptr, 0);
    if (status < 0) {
      throw std::runtime_error("BCryptOpenAlgorithmProvider(SHA-256) failed");
    }
  }

  ~AlgorithmProvider() {
    if (handle_ != nullptr) {
      BCryptCloseAlgorithmProvider(handle_, 0);
    }
  }

  AlgorithmProvider(const AlgorithmProvider&) = delete;
  AlgorithmProvider& operator=(const AlgorithmProvider&) = delete;

  BCRYPT_ALG_HANDLE get() const { return handle_; }

 private:
  BCRYPT_ALG_HANDLE handle_{};
};

class HashHandle {
 public:
  explicit HashHandle(BCRYPT_ALG_HANDLE algorithm) {
    const auto status = BCryptCreateHash(
        algorithm, &handle_, nullptr, 0, nullptr, 0, 0);
    if (status < 0) {
      throw std::runtime_error("BCryptCreateHash failed");
    }
  }

  ~HashHandle() {
    if (handle_ != nullptr) {
      BCryptDestroyHash(handle_);
    }
  }

  HashHandle(const HashHandle&) = delete;
  HashHandle& operator=(const HashHandle&) = delete;

  BCRYPT_HASH_HANDLE get() const { return handle_; }

 private:
  BCRYPT_HASH_HANDLE handle_{};
};

std::string sha256_file(const std::filesystem::path& path) {
  std::ifstream stream(path, std::ios::binary);
  if (!stream) {
    throw std::runtime_error("Unable to open executable for hashing");
  }

  AlgorithmProvider algorithm;
  HashHandle hash(algorithm.get());
  std::vector<char> buffer(1024 * 1024);
  while (stream) {
    stream.read(buffer.data(), static_cast<std::streamsize>(buffer.size()));
    const auto count = stream.gcount();
    if (count > 0) {
      const auto status = BCryptHashData(
          hash.get(), reinterpret_cast<PUCHAR>(buffer.data()),
          static_cast<ULONG>(count), 0);
      if (status < 0) {
        throw std::runtime_error("BCryptHashData failed");
      }
    }
  }

  if (!stream.eof()) {
    throw std::runtime_error("Failed while reading executable");
  }

  std::array<UCHAR, 32> digest{};
  if (BCryptFinishHash(hash.get(), digest.data(),
                       static_cast<ULONG>(digest.size()), 0) < 0) {
    throw std::runtime_error("BCryptFinishHash failed");
  }

  std::ostringstream text;
  text << std::hex << std::setfill('0');
  for (const auto byte : digest) {
    text << std::setw(2) << static_cast<unsigned int>(byte);
  }
  return text.str();
}

std::pair<std::string, std::string> file_versions(
    const std::filesystem::path& path) {
  DWORD ignored{};
  const auto size = GetFileVersionInfoSizeW(path.c_str(), &ignored);
  if (size == 0) {
    return {};
  }

  std::vector<std::byte> data(size);
  if (!GetFileVersionInfoW(path.c_str(), 0, size, data.data())) {
    throw std::runtime_error("GetFileVersionInfoW failed");
  }

  VS_FIXEDFILEINFO* info{};
  UINT info_size{};
  if (!VerQueryValueW(data.data(), L"\\", reinterpret_cast<void**>(&info),
                      &info_size) || info_size < sizeof(VS_FIXEDFILEINFO)) {
    return {};
  }

  const auto format = [](DWORD high, DWORD low) {
    std::ostringstream value;
    value << HIWORD(high) << '.' << LOWORD(high) << '.' << HIWORD(low) << '.'
          << LOWORD(low);
    return value.str();
  };
  return {format(info->dwFileVersionMS, info->dwFileVersionLS),
          format(info->dwProductVersionMS, info->dwProductVersionLS)};
}

std::optional<std::string> ini_value(const std::filesystem::path& path,
                                     const std::string& key) {
  std::ifstream input(path);
  if (!input) {
    return std::nullopt;
  }

  const std::regex pattern("^\\s*" + key +
                           "\\s*=\\s*\\\"?([^\\\"\\r\\n]+)\\\"?\\s*$");
  std::string line;
  std::smatch match;
  while (std::getline(input, line)) {
    if (std::regex_match(line, match, pattern)) {
      auto value = match[1].str();
      while (!value.empty() && std::isspace(static_cast<unsigned char>(value.back()))) {
        value.pop_back();
      }
      return value;
    }
  }
  return std::nullopt;
}

std::string json_escape(const std::string& value) {
  std::ostringstream escaped;
  for (const unsigned char character : value) {
    switch (character) {
      case '\\': escaped << "\\\\"; break;
      case '"': escaped << "\\\""; break;
      case '\b': escaped << "\\b"; break;
      case '\f': escaped << "\\f"; break;
      case '\n': escaped << "\\n"; break;
      case '\r': escaped << "\\r"; break;
      case '\t': escaped << "\\t"; break;
      default:
        if (character < 0x20) {
          escaped << "\\u" << std::hex << std::setw(4) << std::setfill('0')
                  << static_cast<int>(character);
        } else {
          escaped << character;
        }
    }
  }
  return escaped.str();
}

void append_optional(std::ostringstream& json, const char* name,
                     const std::optional<std::string>& value) {
  json << "  \"" << name << "\": ";
  if (value) {
    json << "\"" << json_escape(*value) << "\"";
  } else {
    json << "null";
  }
  json << ",\n";
}

std::string path_utf8(const std::filesystem::path& path) {
  const auto& wide = path.native();
  if (wide.empty()) {
    return {};
  }
  const auto size = WideCharToMultiByte(CP_UTF8, 0, wide.data(),
                                        static_cast<int>(wide.size()), nullptr,
                                        0, nullptr, nullptr);
  if (size <= 0) {
    throw std::runtime_error("WideCharToMultiByte failed for executable path");
  }
  std::string result(static_cast<std::size_t>(size), '\0');
  WideCharToMultiByte(CP_UTF8, 0, wide.data(), static_cast<int>(wide.size()),
                      result.data(), size, nullptr, nullptr);
  return result;
}

}  // namespace

BuildFingerprint fingerprint_build(
    const std::filesystem::path& executable,
    const std::optional<std::filesystem::path>& game_root) {
  if (!std::filesystem::is_regular_file(executable)) {
    throw std::invalid_argument("Executable does not exist or is not a file");
  }

  BuildFingerprint result;
  result.executable = std::filesystem::absolute(executable).lexically_normal();
  result.executable_size = std::filesystem::file_size(executable);
  result.sha256 = sha256_file(executable);
  const auto [file_version, product_version] = file_versions(executable);
  result.file_version = file_version;
  result.product_version = product_version;

  if (game_root) {
    const auto settings = *game_root / "bundle" / "application_settings" /
                          "settings_common.ini";
    result.game_version = ini_value(settings, "game_version");
    result.game_revision = ini_value(settings, "game_revision");
    result.content_revision = ini_value(settings, "content_revision");
  }
  return result;
}

std::string fingerprint_json(const BuildFingerprint& fingerprint) {
  std::ostringstream json;
  json << "{\n"
       << "  \"schema_version\": 1,\n"
       << "  \"executable\": \""
       << json_escape(path_utf8(fingerprint.executable)) << "\",\n"
       << "  \"executable_size\": " << fingerprint.executable_size << ",\n"
       << "  \"sha256\": \"" << fingerprint.sha256 << "\",\n"
       << "  \"file_version\": \"" << json_escape(fingerprint.file_version)
       << "\",\n"
       << "  \"product_version\": \""
       << json_escape(fingerprint.product_version) << "\",\n";
  append_optional(json, "game_version", fingerprint.game_version);
  append_optional(json, "game_revision", fingerprint.game_revision);
  append_optional(json, "content_revision", fingerprint.content_revision);
  json << "  \"safe_mode_required\": true\n}\n";
  return json.str();
}

}  // namespace darktidevr
