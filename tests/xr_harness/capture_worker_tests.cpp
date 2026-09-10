#include "capture_worker.h"

#include <chrono>
#include <condition_variable>
#include <iostream>
#include <mutex>
#include <stdexcept>

using namespace std::chrono_literals;

int main() {
  std::mutex mutex;
  std::condition_variable changed;
  unsigned attempts{};
  bool release{};
  bool callback_finished{};
  auto wait_for = [&](auto predicate, auto timeout) {
    std::unique_lock lock(mutex);
    return changed.wait_for(lock, timeout, predicate);
  };
  auto require = [](bool value, const char* message) {
    if (!value) throw std::runtime_error(message);
  };
  try {
    {
      darktidevr::harness::CaptureWorker worker([&] {
        std::unique_lock lock(mutex);
        ++attempts;
        callback_finished = false;
        changed.notify_all();
        changed.wait(lock, [&] { return release; });
        callback_finished = true;
        changed.notify_all();
      }, 20ms);
      // On failure always release a held callback before joining the worker.
      try {
        require(!wait_for([&] { return attempts != 0; }, 60ms), "Idle worker captured");
        worker.set_enabled(true);
        require(wait_for([&] { return attempts == 1; }, 1s), "Enable did not wake capture");
        worker.set_enabled(false);
        {
          std::scoped_lock lock(mutex);
          release = true;
        }
        changed.notify_all();
        require(wait_for([&] { return callback_finished; }, 1s), "In-flight capture did not finish");
        require(!wait_for([&] { return attempts != 1; }, 80ms), "Paused worker kept capturing");
        {
          std::scoped_lock lock(mutex);
          release = false;
        }
        worker.set_enabled(true);
        require(wait_for([&] { return attempts == 2; }, 1s), "Resume did not capture again");
        worker.set_enabled(false);
        {
          std::scoped_lock lock(mutex);
          release = true;
        }
        changed.notify_all();
        require(wait_for([&] { return callback_finished; }, 1s), "Resumed callback did not finish");
      } catch (...) {
        worker.set_enabled(false);
        {
          std::scoped_lock lock(mutex);
          release = true;
        }
        changed.notify_all();
        throw;
      }
    }
    const auto begin = std::chrono::steady_clock::now();
    { darktidevr::harness::CaptureWorker idle([] {}, 5s); }
    require(std::chrono::steady_clock::now() - begin < 1s, "Idle shutdown waited for capture interval");
    bool rejected = false;
    try { darktidevr::harness::CaptureWorker invalid([] {}, 0ms); }
    catch (const std::invalid_argument&) { rejected = true; }
    require(rejected, "Invalid cadence accepted");
    std::cout << "capture_worker: idle, in-flight pause, resume, shutdown passed\n";
    return 0;
  } catch (const std::exception& error) {
    std::cerr << error.what() << '\n';
    return 1;
  }
}
