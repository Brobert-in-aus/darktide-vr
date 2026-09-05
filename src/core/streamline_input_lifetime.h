#pragma once

#include <array>
#include <cstdint>

namespace darktidevr::core {

// Bookkeeping only; the owner retains resources and COM fence references.
// Capture each eye's completion ticket on the Present thread using the existing
// coordinated GetState call. Never infer input retirement from output readiness
// or from Present returning. This conservative policy also covers other queues.
class StreamlineInputLifetime {
 public:
  bool begin(std::uint64_t submission) noexcept {
    if (active_ || submission == 0 || submission <= submission_) return false;
    active_ = true;
    submission_ = submission;
    return true;
  }

  bool mark_presented(std::uint64_t submission) noexcept {
    if (!matches(submission) || presented_) return false;
    presented_ = true;
    return true;
  }

  bool record_ticket(std::uint64_t submission, std::uint32_t eye,
                     std::uintptr_t fence, std::uint64_t value) noexcept {
    if (!matches(submission) || !presented_ || eye > 1 || fence == 0 ||
        value == ~std::uint64_t{}) return false;
    auto& ticket = tickets_[eye];
    // A repeated state observation must not replace the fence for this batch.
    if (ticket.fence != 0)
      return ticket.fence == fence && ticket.value == value;
    ticket = {fence, value, false};
    return true;
  }

  bool observe_completion(std::uint64_t submission, std::uint32_t eye,
                          std::uintptr_t fence,
                          std::uint64_t completed) noexcept {
    if (!matches(submission) || eye > 1 || completed == ~std::uint64_t{})
      return false; // D3D12 uses UINT64_MAX for device removal.
    auto& ticket = tickets_[eye];
    if (ticket.fence == 0 || ticket.fence != fence) return false;
    ticket.complete = ticket.complete || completed >= ticket.value;
    return ticket.complete;
  }

  bool mark_tags_cleared(std::uint64_t submission) noexcept {
    if (!matches(submission)) return false;
    tags_cleared_ = true;
    return true;
  }

  bool can_release() const noexcept {
    return active_ && tags_cleared_ &&
        (!presented_ || (tickets_[0].complete && tickets_[1].complete));
  }

  bool release(std::uint64_t submission) noexcept {
    if (!matches(submission) || !can_release()) return false;
    active_ = false;
    presented_ = false;
    tags_cleared_ = false;
    tickets_ = {};
    return true;
  }

 private:
  bool matches(std::uint64_t submission) const noexcept {
    return active_ && submission_ == submission;
  }
  struct Ticket {
    std::uintptr_t fence{};
    std::uint64_t value{};
    bool complete{};
  };
  bool active_{};
  bool presented_{};
  bool tags_cleared_{};
  std::uint64_t submission_{};
  std::array<Ticket, 2> tickets_{};
};
} // namespace darktidevr::core
