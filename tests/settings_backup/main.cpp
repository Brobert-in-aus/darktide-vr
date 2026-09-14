#include "core/settings_backup.h"

#include <filesystem>
#include <fstream>
#include <iostream>
#include <stdexcept>
#include <string>

namespace {

void expect(bool condition, const char* message) {
  if (!condition) {
    throw std::runtime_error(message);
  }
}

std::string settings_text(std::size_t padding) {
  std::string text = "fullscreen = false\nmods_settings = {\n\tdarktidevr = {\n"
                     "\t\tvr_calibration_v1 = {\n\t\t\theight = 1.8\n\t\t}\n"
                     "\t\tname = \"a } brace in a string [\"\n\t}\n}\n"
                     "screen_resolution = [\n\t1280\n\t720\n]\n";
  text += "padding = \"" + std::string(padding, 'x') + "\"\n";
  return text;
}

void write(const std::filesystem::path& path, const std::string& text) {
  std::ofstream output(path, std::ios::binary | std::ios::trunc);
  output << text;
}

}  // namespace

int main() {
  using namespace darktidevr::core;
  try {
    const auto root = std::filesystem::temp_directory_path() /
                      ("darktidevr-settings-backup-test-" +
                       std::to_string(std::filesystem::file_time_type::clock::now()
                                          .time_since_epoch()
                                          .count()));
    std::filesystem::create_directories(root);
    const auto settings = root / "user_settings.config";
    const auto directory = root / "backups";

    expect(settings_text_plausible(settings_text(4000)), "sound settings rejected");
    expect(!settings_text_plausible("mods_settings = {}"), "a tiny file accepted");
    expect(!settings_text_plausible(settings_text(4000) + "{"), "unbalanced braces accepted");
    expect(!settings_text_plausible("]" + settings_text(4000) + "["), "a close before an open accepted");
    std::string zeroed = settings_text(4000);
    zeroed[100] = '\0';
    expect(!settings_text_plausible(zeroed), "a zero-filled file accepted");
    expect(!settings_text_plausible(std::string(5000, 'a')), "a file without mods_settings accepted");

    expect(backup_settings(settings, directory, "20260915-080000") == SettingsBackupResult::missing,
           "missing file");
    write(settings, "garbage");
    expect(backup_settings(settings, directory, "20260915-080000") == SettingsBackupResult::invalid,
           "invalid file saved");
    expect(!std::filesystem::exists(directory) || newest_settings_backup(directory).empty(),
           "an invalid file left a backup");

    write(settings, settings_text(8000));
    expect(backup_settings(settings, directory, "20260915-080000") == SettingsBackupResult::saved,
           "first backup");
    expect(newest_settings_backup(directory).filename() == "user_settings.20260915-080000.config",
           "backup name");
    expect(backup_settings(settings, directory, "20260915-080100") == SettingsBackupResult::unchanged,
           "an identical file saved twice");

    write(settings, settings_text(2500));  // a reset to defaults: far smaller
    expect(backup_settings(settings, directory, "20260915-080200") == SettingsBackupResult::shrunk,
           "a shrunken file replaced the good backup");
    expect(newest_settings_backup(directory).filename() == "user_settings.20260915-080000.config",
           "the shrunken file became newest");

    for (int i = 0; i < 7; ++i) {
      write(settings, settings_text(8000 + static_cast<std::size_t>(i) + 1));
      const auto stamp = "20260915-09000" + std::to_string(i);
      expect(backup_settings(settings, directory, stamp) == SettingsBackupResult::saved, "rotation save");
    }
    std::size_t count = 0;
    for (const auto& entry : std::filesystem::directory_iterator(directory)) {
      (void)entry;
      ++count;
    }
    expect(count == kSettingsBackupKeep, "rotation did not keep exactly the newest backups");
    expect(newest_settings_backup(directory).filename() == "user_settings.20260915-090006.config",
           "newest after rotation");
    expect(!std::filesystem::exists(directory / "user_settings.20260915-080000.config"),
           "the oldest backup survived rotation");

    std::filesystem::remove_all(root);
  } catch (const std::exception& error) {
    std::cerr << "settings_backup failed: " << error.what() << '\n';
    return 1;
  }
  std::cout << "settings_backup=pass plausible reject_zeroed unchanged shrunk rotation\n";
  return 0;
}
