#include "core/shared_controller_state.h"
#include "core/shared_gameplay_aim_state.h"
#include "core/shared_head_pose.h"
#include "synthetic_controller_path.h"

#include <Windows.h>

#include <chrono>
#include <cstdint>
#include <iostream>
#include <stdexcept>
#include <string>
#include <thread>

namespace {

std::uint32_t parse_seconds(const wchar_t* text) {
  std::size_t consumed{};
  const auto value = std::stoul(text, &consumed);
  if (consumed != std::wstring(text).size() || value == 0 || value > 43200) {
    throw std::invalid_argument("--seconds must be in the range 1..43200");
  }
  return static_cast<std::uint32_t>(value);
}

std::uint64_t timestamp_ns() {
  return static_cast<std::uint64_t>(
      std::chrono::duration_cast<std::chrono::nanoseconds>(
          std::chrono::steady_clock::now().time_since_epoch())
          .count());
}

void print_usage() {
  std::wcout << L"Usage: darktidevr-synthetic-controller-publisher "
                L"[--seconds N] [--weapon-aim-matrix] "
                L"[--neutral-body-pose]\n";
}

}  // namespace

int wmain(int argc, wchar_t** argv) {
  try {
    std::uint32_t seconds = 300;
    bool weapon_aim_matrix = false;
    bool neutral_body_pose = false;
    for (int index = 1; index < argc; ++index) {
      const std::wstring argument(argv[index]);
      if (argument == L"--help") {
        print_usage();
        return 0;
      }
      if (argument == L"--seconds" && index + 1 < argc) {
        seconds = parse_seconds(argv[++index]);
      } else if (argument == L"--weapon-aim-matrix") {
        weapon_aim_matrix = true;
      } else if (argument == L"--neutral-body-pose") {
        neutral_body_pose = true;
      } else {
        print_usage();
        return 2;
      }
    }

    const HANDLE mutex = CreateMutexW(
        nullptr, FALSE, L"Local\\DarktideVR_XR_Harness_SingleWriter");
    if (!mutex) {
      throw std::runtime_error("CreateMutexW(single writer) failed");
    }
    if (WaitForSingleObject(mutex, 0) != WAIT_OBJECT_0) {
      CloseHandle(mutex);
      throw std::runtime_error(
          "Another Darktide VR controller/shared-eye writer is active");
    }

    try {
      darktidevr::core::SharedControllerStateWriter writer;
      darktidevr::core::SharedHeadPoseWriter head_writer;
      darktidevr::core::SharedGameplayAimStateReader aim_reader;
      darktidevr::math::Pose panel_pose{};
      panel_pose.orientation.w = 1.0F;
      std::uint64_t frame{};
      std::uint64_t sequence{};
      std::uint64_t matrix_frame{};
      std::uint64_t gameplay_active_frames{};
      const auto started = std::chrono::steady_clock::now();
      const auto deadline = started + std::chrono::seconds(seconds);
      constexpr auto frame_period = std::chrono::nanoseconds(16666667);

      while (std::chrono::steady_clock::now() < deadline) {
        darktidevr::core::SharedHeadPoseSample head{};
        head.sequence = frame + 1;
        head.recenter_generation = 1;
        head.pose.orientation.w = 1.0F;
        head.render_vertical_fov_radians = 1.6416F;
        head.render_aspect_ratio = 2112.0F / 2304.0F;
        head.render_width = 2112;
        head.render_height = 2304;
        for (auto& frustum : head.render_frusta) {
          frustum.left = -0.777324F;
          frustum.right = 0.777324F;
          frustum.down = -0.8208F;
          frustum.up = 0.8208F;
        }
        head.ipd_metres = 0.064F;
        head.floor_eye_height_metres = 1.70F;
        if (!head_writer.publish(head)) {
          throw std::runtime_error("Shared head pose rejected stationary sample");
        }
        darktidevr::core::SharedGameplayAimState aim{};
        constexpr std::uint64_t maximum_gameplay_aim_age_ns = 100'000'000ULL;
        const bool gameplay_active = aim_reader.read(aim) &&
                                     darktidevr::core::gameplay_aim_state_is_fresh(
                                         aim, timestamp_ns(),
                                         maximum_gameplay_aim_age_ns) &&
                                     aim.active;
        auto sample = darktidevr::harness::synthetic_controller_path_sample(
            frame, ++sequence, timestamp_ns(), panel_pose, 2.0F, 2.0F, false);
        // Supply the same recenter-relative Darktide-basis poses that the XR
        // harness normally derives from its HMD anchor. Visual weapon-matrix
        // captures can hold a plausible reachable pose so the intentionally
        // impossible reach phase does not elongate authored glove cuffs.
        darktidevr::harness::apply_synthetic_body_reach_path(sample.state,
                                                             neutral_body_pose
                                                                 ? 5
                                                                 : frame);
        if (weapon_aim_matrix) {
          if (gameplay_active) {
            darktidevr::harness::apply_synthetic_weapon_aim_matrix(
                sample.state, matrix_frame++);
            ++gameplay_active_frames;
          } else {
            darktidevr::harness::apply_synthetic_weapon_aim_matrix(
                sample.state, 0);
          }
        }
        if (!writer.publish(sample.state)) {
          throw std::runtime_error("Shared controller state rejected sample");
        }
        ++frame;
        std::this_thread::sleep_until(started + frame_period * frame);
      }

      // Publish one fresh neutral/invalid sample so a stopped diagnostic can
      // never leave a held gameplay action or apparently tracked hand behind.
      darktidevr::core::SharedControllerState neutral{};
      neutral.sequence = ++sequence;
      neutral.timestamp_ns = timestamp_ns();
      for (auto& hand : neutral.hands) {
        hand.aim_pose.orientation.w = 1.0F;
        hand.grip_pose.orientation.w = 1.0F;
        hand.body_aim_pose.orientation.w = 1.0F;
        hand.body_grip_pose.orientation.w = 1.0F;
      }
      if (!writer.publish(neutral)) {
        throw std::runtime_error("Shared controller state rejected neutral sample");
      }
      std::cout << "synthetic_controller_publisher.result=pass frames=" << frame
                << " gameplay_active_frames=" << gameplay_active_frames
                << " matrix_frames=" << matrix_frame
                << " eye_surface_generation="
                << head_writer.read_eye_surface_generation()
                << " menu_surface_generation="
                << head_writer.read_menu_surface_generation()
                << " body_path="
                << (neutral_body_pose ? "neutral" : "stress") << '\n';
    } catch (...) {
      ReleaseMutex(mutex);
      CloseHandle(mutex);
      throw;
    }
    ReleaseMutex(mutex);
    CloseHandle(mutex);
    return 0;
  } catch (const std::exception& error) {
    std::cerr << "synthetic_controller_publisher: " << error.what() << '\n';
    return 1;
  }
}
