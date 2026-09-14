#include "core/settings_backup.h"

#include <algorithm>
#include <fstream>
#include <iterator>
#include <system_error>
#include <vector>

namespace darktidevr::core {
namespace {

bool is_backup_name(const std::filesystem::path& path) {
  const auto name = path.filename().string();
  constexpr std::string_view prefix = "user_settings.2";
  constexpr std::string_view suffix = ".config";
  return name.size() > prefix.size() + suffix.size() &&
         name.compare(0, prefix.size(), prefix) == 0 &&
         name.compare(name.size() - suffix.size(), suffix.size(), suffix) == 0;
}

std::vector<std::filesystem::path> backups_newest_first(
    const std::filesystem::path& directory) {
  std::vector<std::filesystem::path> found;
  std::error_code error;
  for (std::filesystem::directory_iterator it(directory, error), end;
       !error && it != end; it.increment(error)) {
    if (it->is_regular_file(error) && is_backup_name(it->path())) {
      found.push_back(it->path());
    }
  }
  std::sort(found.begin(), found.end(),
            [](const auto& a, const auto& b) { return a.filename() > b.filename(); });
  return found;
}

bool read_all(const std::filesystem::path& path, std::string& text) {
  std::ifstream input(path, std::ios::binary);
  if (!input) {
    return false;
  }
  text.assign(std::istreambuf_iterator<char>(input), {});
  return !input.bad();
}

}  // namespace

const char* settings_backup_result_name(SettingsBackupResult result) {
  switch (result) {
    case SettingsBackupResult::saved: return "saved";
    case SettingsBackupResult::unchanged: return "unchanged";
    case SettingsBackupResult::missing: return "missing";
    case SettingsBackupResult::invalid: return "invalid";
    case SettingsBackupResult::shrunk: return "shrunk";
    case SettingsBackupResult::failed: return "failed";
  }
  return "unknown";
}

bool settings_text_plausible(std::string_view text) {
  if (text.size() < kSettingsBackupMinimumBytes ||
      text.find("mods_settings") == std::string_view::npos) {
    return false;
  }
  int braces = 0;
  int brackets = 0;
  bool in_string = false;
  for (std::size_t i = 0; i < text.size(); ++i) {
    const char c = text[i];
    if (c == '\0') {
      return false;  // a crash-truncated file is often zero-filled
    }
    if (in_string) {
      if (c == '\\') {
        ++i;
      } else if (c == '"') {
        in_string = false;
      }
      continue;
    }
    switch (c) {
      case '"': in_string = true; break;
      case '{': ++braces; break;
      case '}': if (--braces < 0) return false; break;
      case '[': ++brackets; break;
      case ']': if (--brackets < 0) return false; break;
      default: break;
    }
  }
  return !in_string && braces == 0 && brackets == 0;
}

std::filesystem::path newest_settings_backup(const std::filesystem::path& directory) {
  const auto backups = backups_newest_first(directory);
  return backups.empty() ? std::filesystem::path{} : backups.front();
}

SettingsBackupResult backup_settings(const std::filesystem::path& settings,
                                     const std::filesystem::path& directory,
                                     const std::string& stamp) {
  std::error_code error;
  if (!std::filesystem::is_regular_file(settings, error)) {
    return SettingsBackupResult::missing;
  }
  std::string text;
  if (!read_all(settings, text)) {
    return SettingsBackupResult::failed;
  }
  if (!settings_text_plausible(text)) {
    return SettingsBackupResult::invalid;
  }
  auto backups = backups_newest_first(directory);
  if (!backups.empty()) {
    std::string newest;
    if (read_all(backups.front(), newest)) {
      if (newest == text) {
        return SettingsBackupResult::unchanged;
      }
      if (static_cast<double>(text.size()) <
          static_cast<double>(newest.size()) * kSettingsBackupShrinkLimit) {
        return SettingsBackupResult::shrunk;
      }
    }
  }
  std::filesystem::create_directories(directory, error);
  if (error) {
    return SettingsBackupResult::failed;
  }
  const auto destination = directory / ("user_settings." + stamp + ".config");
  const auto temporary = destination.string() + ".partial";
  {
    std::ofstream output(temporary, std::ios::binary | std::ios::trunc);
    output.write(text.data(), static_cast<std::streamsize>(text.size()));
    if (!output) {
      std::filesystem::remove(temporary, error);
      return SettingsBackupResult::failed;
    }
  }
  std::filesystem::rename(temporary, destination, error);
  if (error) {
    std::filesystem::remove(temporary, error);
    return SettingsBackupResult::failed;
  }
  backups = backups_newest_first(directory);
  for (std::size_t i = kSettingsBackupKeep; i < backups.size(); ++i) {
    std::filesystem::remove(backups[i], error);
  }
  return SettingsBackupResult::saved;
}

}  // namespace darktidevr::core
