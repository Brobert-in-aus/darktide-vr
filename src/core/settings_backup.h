#pragma once

#include <cstdint>
#include <filesystem>
#include <string>
#include <string_view>

namespace darktidevr::core {

// Keeps copies of the game's user_settings.config from launches where it was
// sound, so a crash that destroys the file mid-write (14 September 2026: the
// launcher then starts from defaults and the VR calibration is lost) can be
// undone. Backups are user_settings.<stamp>.config in their own directory,
// newest by name; the newest SettingsBackupKeep are kept.
inline constexpr std::size_t kSettingsBackupKeep = 5;
// A file this much smaller than the newest backup is taken as a reset to
// defaults (the reset file on 14 September was half the size), not saved.
inline constexpr double kSettingsBackupShrinkLimit = 0.7;
inline constexpr std::uintmax_t kSettingsBackupMinimumBytes = 2048;

enum class SettingsBackupResult {
  saved,          // a new backup was written
  unchanged,      // identical to the newest backup
  missing,        // no settings file
  invalid,        // too short, unbalanced, or not a game settings file
  shrunk,         // much smaller than the newest backup: likely a reset
  failed,         // an I/O error
};

const char* settings_backup_result_name(SettingsBackupResult result);

// Structure check of the game's SJSON-like settings text: at least the
// minimum size, braces and brackets balanced and never closing before they
// open (outside strings), and a mods_settings block.
bool settings_text_plausible(std::string_view text);

// stamp: a sortable local time such as "20260915-083000".
SettingsBackupResult backup_settings(const std::filesystem::path& settings,
                                     const std::filesystem::path& directory,
                                     const std::string& stamp);

// The newest backup, or an empty path.
std::filesystem::path newest_settings_backup(const std::filesystem::path& directory);

}  // namespace darktidevr::core
