#pragma once

#include <string>
#include <string_view>

namespace darktidevr::darktide {

struct BuildIdentity {
  std::string executable_sha256;
  std::string game_version;
  std::string file_version;
};

struct ObservationRequest {
  bool explicit_user_opt_in{};
  bool staged_research_environment{};
  bool eac_session_active{};
  bool process_mutation_requested{};
  bool concealment_or_bypass_requested{};
};

enum class ObservationDecision {
  allow_metadata_only,
  deny_unknown_build,
  deny_without_opt_in,
  deny_unstaged_environment,
  deny_active_eac_session,
  deny_process_mutation,
  deny_prohibited_behavior,
};

inline constexpr std::string_view kKnownExecutableSha256 =
    "e0f581d2c63b692c7d9f328e3edeb39c0f484956905569d38ba27bbb3fcc0aae";
inline constexpr std::string_view kKnownGameVersion = "1.12.0-b773907";
inline constexpr std::string_view kKnownFileVersion = "1.3.770.210";

ObservationDecision evaluate_observation(const BuildIdentity& identity,
                                         const ObservationRequest& request);
std::string_view decision_name(ObservationDecision decision);

}  // namespace darktidevr::darktide
