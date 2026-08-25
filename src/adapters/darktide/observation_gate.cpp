#include "adapters/darktide/observation_gate.h"

namespace darktidevr::darktide {

ObservationDecision evaluate_observation(const BuildIdentity& identity,
                                         const ObservationRequest& request) {
  if (request.concealment_or_bypass_requested) {
    return ObservationDecision::deny_prohibited_behavior;
  }
  if (request.process_mutation_requested) {
    return ObservationDecision::deny_process_mutation;
  }
  if (request.eac_session_active) {
    return ObservationDecision::deny_active_eac_session;
  }
  if (!request.explicit_user_opt_in) {
    return ObservationDecision::deny_without_opt_in;
  }
  if (!request.staged_research_environment) {
    return ObservationDecision::deny_unstaged_environment;
  }
  if (identity.executable_sha256 != kKnownExecutableSha256 ||
      identity.game_version != kKnownGameVersion ||
      identity.file_version != kKnownFileVersion) {
    return ObservationDecision::deny_unknown_build;
  }
  return ObservationDecision::allow_metadata_only;
}

std::string_view decision_name(ObservationDecision decision) {
  switch (decision) {
    case ObservationDecision::allow_metadata_only:
      return "allow_metadata_only";
    case ObservationDecision::deny_unknown_build:
      return "deny_unknown_build";
    case ObservationDecision::deny_without_opt_in:
      return "deny_without_opt_in";
    case ObservationDecision::deny_unstaged_environment:
      return "deny_unstaged_environment";
    case ObservationDecision::deny_active_eac_session:
      return "deny_active_eac_session";
    case ObservationDecision::deny_process_mutation:
      return "deny_process_mutation";
    case ObservationDecision::deny_prohibited_behavior:
      return "deny_prohibited_behavior";
  }
  return "invalid";
}

}  // namespace darktidevr::darktide
