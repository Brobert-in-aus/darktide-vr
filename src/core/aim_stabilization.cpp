#include "core/aim_stabilization.h"

#include <algorithm>
#include <cmath>
#include <stdexcept>

namespace darktidevr::core {
namespace {
constexpr double kTau = 6.2831853071795864769;
float alpha(float cutoff, double dt) {
  return static_cast<float>(1.0 / (1.0 + 1.0 / (kTau * cutoff * dt)));
}
float dot(math::Quaternion a, math::Quaternion b) {
  return a.x*b.x + a.y*b.y + a.z*b.z + a.w*b.w;
}
bool valid(math::Quaternion q) {
  return std::isfinite(q.x) && std::isfinite(q.y) &&
      std::isfinite(q.z) && std::isfinite(q.w) &&
      std::isfinite(dot(q,q)) && dot(q,q)>1e-12F;
}
math::Quaternion interpolate(math::Quaternion a, math::Quaternion b, float t) {
  float cosine=dot(a,b);
  if (cosine<0) { b={-b.x,-b.y,-b.z,-b.w}; cosine=-cosine; }
  float wa=1-t, wb=t;
  if (cosine<0.9995F) {
    const auto angle=std::acos(std::clamp(cosine,0.0F,1.0F));
    const auto sine=std::sin(angle);
    wa=std::sin((1-t)*angle)/sine;
    wb=std::sin(t*angle)/sine;
  }
  return math::normalized({wa*a.x+wb*b.x,wa*a.y+wb*b.y,
                           wa*a.z+wb*b.z,wa*a.w+wb*b.w});
}
}

AimStabilization::AimStabilization(AimStabilizationConfig config):config_(config) {
  if (!std::isfinite(config.minimum_cutoff_hz) || config.minimum_cutoff_hz<=0 ||
      !std::isfinite(config.speed_coefficient) || config.speed_coefficient<0 ||
      !std::isfinite(config.derivative_cutoff_hz) || config.derivative_cutoff_hz<=0 ||
      !std::isfinite(config.maximum_gap_seconds) || config.maximum_gap_seconds<=0) {
    throw std::invalid_argument("Invalid aim stabilization configuration");
  }
}

void AimStabilization::reset() { filtered_.reset(); speed_=0; }

std::optional<math::Quaternion> AimStabilization::update(math::Quaternion raw,
    std::uint64_t sequence, std::int64_t pose_time_ns,
    std::uint64_t epoch, bool tracked) {
  if (!tracked || !valid(raw) || sequence==0 || pose_time_ns<=0) {
    reset(); return std::nullopt;
  }
  raw=math::normalized(raw);
  // A second consumer of one sample must not advance the filter again.
  if (filtered_ && epoch==epoch_ && sequence==sequence_) return filtered_;
  // Both accepted times are positive, so subtraction is safe and preserves
  // nanosecond differences even when absolute clock values are large.
  const double dt=static_cast<double>(pose_time_ns-pose_time_ns_)*1e-9;
  if (!filtered_ || epoch!=epoch_ || sequence<sequence_ || dt<=0 ||
      dt>config_.maximum_gap_seconds) {
    filtered_=raw; speed_=0;
  } else {
    const auto delta=math::multiply(math::conjugate(previous_raw_),raw);
    const float sine=std::sqrt(delta.x*delta.x+delta.y*delta.y+delta.z*delta.z);
    const float angle=2*std::atan2(sine,std::abs(delta.w));
    const float raw_speed=static_cast<float>(angle/dt);
    speed_+=alpha(config_.derivative_cutoff_hz,dt)*(raw_speed-speed_);
    const float cutoff=config_.minimum_cutoff_hz+config_.speed_coefficient*speed_;
    filtered_=interpolate(*filtered_,raw,alpha(cutoff,dt));
  }
  previous_raw_=raw; sequence_=sequence; epoch_=epoch; pose_time_ns_=pose_time_ns;
  return filtered_;
}
}  // namespace darktidevr::core
