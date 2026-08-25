#include "core/output_layout.h"

#include <stdexcept>

namespace darktidevr::core {
namespace {

void require_valid(PixelExtent extent, const char* label) {
  if (extent.width == 0 || extent.height == 0) {
    throw std::invalid_argument(std::string(label) +
                                " dimensions must be non-zero");
  }
}

}  // namespace

OutputLayout choose_output_layout(const OutputLayoutRequest& request) {
  require_valid(request.runtime_recommended_eye, "runtime eye");
  const auto eye_extent =
      request.eye_override.value_or(request.runtime_recommended_eye);
  require_valid(eye_extent, "eye override");

  PixelExtent mirror_extent{};
  if (request.mirror_mode != MirrorMode::disabled) {
    require_valid(request.mirror_extent, "mirror");
    mirror_extent = request.mirror_extent;
  }

  return {
      eye_extent,
      request.mirror_mode,
      mirror_extent,
      2,
  };
}

}  // namespace darktidevr::core
