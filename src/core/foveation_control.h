#pragma once
#include "core/foveation.h"

#include <cmath>
#include <cstdint>

// Deciding, per eye per frame, where the foveal centre goes and whether the
// shading rate image has to be repainted. Kept separate from the D3D12 work
// because both of the failures that live here are invisible in a headset:
//
//  * a stale or absent aim point makes the whole eye coarse, which reads as
//    "foveation looks terrible" rather than as "the aim point is missing";
//  * repainting the image every frame is an upload per eye per frame, which
//    reads as "foveation is not worth it" rather than as a bug.
namespace darktidevr::core {

enum class FoveationMode {
  off,
  // Centred where the caller says the eye's fixed centre is. On this renderer
  // that is the middle of the image: the game renders each eye with a
  // symmetric frustum rotated onto its optical axis, so the axis is at NDC 0
  // in both eyes. The caller supplies it anyway, because a renderer that did
  // otherwise would be a one-line change here rather than a rewrite.
  fixed,
  // Centred on the aim point, which in an aimed shooter is where the player is
  // usually looking -- most of the benefit of eye tracking without any. Falls
  // back to `fixed` whenever the aim point cannot be trusted.
  reticle,
};

struct FoveationRequest {
  FoveationMode mode{FoveationMode::off};
  std::uint32_t width{};
  std::uint32_t height{};
  std::uint32_t tile_size{};
  // Where this eye's pattern sits when the aim point is not being followed:
  // the `fixed` answer, and the fallback for `reticle`.
  float fallback_centre_ndc_x{};
  float fallback_centre_ndc_y{};
  // The aim point in this eye's NDC, and whether it can be trusted. `age` is
  // seconds since it was published.
  bool reticle_valid{};
  float reticle_ndc_x{};
  float reticle_ndc_y{};
  float reticle_age_seconds{};
};

struct FoveationDecision {
  bool enabled{};
  float centre_ndc_x{};
  float centre_ndc_y{};
  // Whether the image has to be repainted and re-uploaded this frame.
  bool repaint{};
  // Why the centre is where it is, for the log. A run that reports
  // `reticle_stale` for a whole session says the aim point never arrived,
  // which is a different problem from foveation not helping.
  enum class Reason {
    disabled,
    fixed_centre,
    reticle,
    reticle_invalid,
    reticle_stale,
    reticle_offscreen,
    unusable_extent,
  } reason{Reason::disabled};
};

inline const char* foveation_reason_name(FoveationDecision::Reason reason) {
  switch (reason) {
    case FoveationDecision::Reason::disabled: return "disabled";
    case FoveationDecision::Reason::fixed_centre: return "fixed_centre";
    case FoveationDecision::Reason::reticle: return "reticle";
    case FoveationDecision::Reason::reticle_invalid: return "reticle_invalid";
    case FoveationDecision::Reason::reticle_stale: return "reticle_stale";
    case FoveationDecision::Reason::reticle_offscreen: return "reticle_offscreen";
    case FoveationDecision::Reason::unusable_extent: return "unusable_extent";
  }
  return "unknown";
}

// One per eye. Remembers what was last painted so the image is re-uploaded
// only when it would actually differ.
class FoveationState {
 public:
  // An aim point older than this is not where the player is looking any more.
  // Two frames at 90 Hz: long enough to ride out a dropped publication, short
  // enough that a head turn does not drag the sharp region behind it.
  static constexpr float kStaleSeconds = 0.022F;
  // How far the centre must move before repainting is worth an upload. Half a
  // tile: below that the painted image is bit-identical, so the upload buys
  // nothing at all.
  static constexpr float kRepaintTilesNdc = 0.5F;
  // An aim point beyond this is off the eye's image. Slightly past the edge is
  // allowed so the sharp region can sit at the rim rather than snapping back
  // to the optics as the player aims to the side.
  static constexpr float kOffscreenNdc = 1.25F;

  FoveationDecision decide(const FoveationRequest& request) {
    FoveationDecision decision;
    if (request.mode == FoveationMode::off) {
      painted_ = false;
      decision.reason = FoveationDecision::Reason::disabled;
      return decision;
    }
    if (request.width == 0U || request.height == 0U || request.tile_size == 0U) {
      painted_ = false;
      decision.reason = FoveationDecision::Reason::unusable_extent;
      return decision;
    }
    decision.enabled = true;
    decision.centre_ndc_x = request.fallback_centre_ndc_x;
    decision.centre_ndc_y = request.fallback_centre_ndc_y;
    decision.reason = request.mode == FoveationMode::reticle
                          ? FoveationDecision::Reason::reticle_invalid
                          : FoveationDecision::Reason::fixed_centre;
    if (request.mode == FoveationMode::reticle) {
      const auto finite = [](float value) {
        return value == value && std::abs(value) < 1.0e6F;
      };
      if (!request.reticle_valid || !finite(request.reticle_ndc_x) ||
          !finite(request.reticle_ndc_y)) {
        decision.reason = FoveationDecision::Reason::reticle_invalid;
      } else if (!(request.reticle_age_seconds <= kStaleSeconds) ||
                 request.reticle_age_seconds < 0.0F) {
        // `!(age <= k)` rather than `age > k` so a NaN age is stale rather
        // than fresh. A clock that runs backwards is not fresh either.
        decision.reason = FoveationDecision::Reason::reticle_stale;
      } else if (std::abs(request.reticle_ndc_x) > kOffscreenNdc ||
                 std::abs(request.reticle_ndc_y) > kOffscreenNdc) {
        decision.reason = FoveationDecision::Reason::reticle_offscreen;
      } else {
        decision.centre_ndc_x = request.reticle_ndc_x;
        decision.centre_ndc_y = request.reticle_ndc_y;
        decision.reason = FoveationDecision::Reason::reticle;
      }
    }
    // A tile in NDC is two units across the whole extent.
    const auto tile_ndc_x =
        2.0F * static_cast<float>(request.tile_size) /
        static_cast<float>(request.width);
    const auto tile_ndc_y =
        2.0F * static_cast<float>(request.tile_size) /
        static_cast<float>(request.height);
    decision.repaint =
        !painted_ || painted_width_ != request.width ||
        painted_height_ != request.height ||
        painted_tile_ != request.tile_size ||
        std::abs(decision.centre_ndc_x - painted_centre_x_) >
            tile_ndc_x * kRepaintTilesNdc ||
        std::abs(decision.centre_ndc_y - painted_centre_y_) >
            tile_ndc_y * kRepaintTilesNdc;
    if (decision.repaint) {
      painted_ = true;
      painted_width_ = request.width;
      painted_height_ = request.height;
      painted_tile_ = request.tile_size;
      painted_centre_x_ = decision.centre_ndc_x;
      painted_centre_y_ = decision.centre_ndc_y;
    }
    return decision;
  }

  // The image is gone -- a device reset, an extent change, the feature turned
  // off and on. The next decision must repaint whatever it decides.
  void forget() { painted_ = false; }

  bool painted() const { return painted_; }

 private:
  bool painted_{};
  std::uint32_t painted_width_{};
  std::uint32_t painted_height_{};
  std::uint32_t painted_tile_{};
  float painted_centre_x_{};
  float painted_centre_y_{};
};

}  // namespace darktidevr::core
