#include "producer/diagnostic_append_log.h"

#include <array>
#include <atomic>
#include <filesystem>
#include <fstream>
#include <iostream>
#include <set>
#include <string>
#include <thread>
#include <vector>

int main() {
  std::array<wchar_t, MAX_PATH> temporary_path{};
  std::array<wchar_t, MAX_PATH> file_path{};
  if (!GetTempPathW(MAX_PATH, temporary_path.data()) ||
      !GetTempFileNameW(temporary_path.data(), L"dvp", 0, file_path.data())) {
    return 1;
  }
  const auto path = std::filesystem::path(file_path.data());
  const auto observer = CreateFileW(path.c_str(), GENERIC_READ,
      FILE_SHARE_READ | FILE_SHARE_WRITE, nullptr, OPEN_EXISTING,
      FILE_ATTRIBUTE_NORMAL, nullptr);
  if (observer == INVALID_HANDLE_VALUE) {
    DeleteFileW(path.c_str());
    return 1;
  }
  std::atomic<bool> ready{};
  std::atomic<unsigned> failures{};
  std::vector<std::thread> writers;
  constexpr unsigned thread_count = 8;
  constexpr unsigned records_per_thread = 128;
  for (unsigned thread = 0; thread < thread_count; ++thread) {
    writers.emplace_back([&, thread] {
      while (!ready.load(std::memory_order_acquire)) {
        std::this_thread::yield();
      }
      for (unsigned record = 0; record < records_per_thread; ++record) {
        const auto line = "thread=" + std::to_string(thread) +
            "\trecord=" + std::to_string(record) + "\r\n";
        if (!darktidevr::producer::append_diagnostic_record(
                path.c_str(), line)) {
          ++failures;
        }
      }
    });
  }
  ready.store(true, std::memory_order_release);
  for (auto& writer : writers) writer.join();
  CloseHandle(observer);

  std::set<std::string> actual;
  std::ifstream input(path, std::ios::binary);
  unsigned count{};
  for (std::string line; std::getline(input, line); ++count) {
    actual.insert(line);
  }
  input.close();
  std::set<std::string> expected;
  for (unsigned thread = 0; thread < thread_count; ++thread) {
    for (unsigned record = 0; record < records_per_thread; ++record) {
      expected.insert("thread=" + std::to_string(thread) +
          "\trecord=" + std::to_string(record) + "\r");
    }
  }

  // A reader must permit an append writer; incompatible external access
  // should report failure rather than claiming a complete capture.
  const auto blocker = CreateFileW(path.c_str(), GENERIC_READ,
      FILE_SHARE_READ, nullptr, OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, nullptr);
  const bool lock_valid = blocker != INVALID_HANDLE_VALUE;
  const bool denied = lock_valid &&
      !darktidevr::producer::append_diagnostic_record(path.c_str(), "blocked\r\n");
  if (lock_valid) CloseHandle(blocker);
  const bool empty_rejected =
      !darktidevr::producer::append_diagnostic_record(path.c_str(), "");
  const bool resumed =
      darktidevr::producer::append_diagnostic_record(path.c_str(), "resumed\r\n");
  const bool removed = DeleteFileW(path.c_str()) != 0;
  if (failures || count != expected.size() || actual != expected ||
      !denied || !empty_rejected || !resumed || !removed) {
    std::cerr << "diagnostic append failed: errors=" << failures.load()
              << " records=" << count << '\n';
    return 1;
  }
  std::cout << "Concurrent diagnostic records preserved: " << count << '\n';
}
