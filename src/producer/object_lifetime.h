#pragma once

#include <d3d12.h>
#include <atomic>
#include <functional>
#include <utility>

namespace darktidevr::producer {
// D3D12 releases private interfaces with their owner. The observer never holds
// an owner reference, so attaching one does not keep GPU allocations alive.
class LifetimeObserver final : public IUnknown {
 public:
  explicit LifetimeObserver(std::function<void()> expired)
      : expired_(std::move(expired)) {}
  HRESULT STDMETHODCALLTYPE QueryInterface(REFIID iid, void** output) override {
    if (!output) return E_POINTER;
    *output = nullptr;
    if (iid != __uuidof(IUnknown)) return E_NOINTERFACE;
    *output = static_cast<IUnknown*>(this);
    AddRef();
    return S_OK;
  }
  ULONG STDMETHODCALLTYPE AddRef() override { return ++references_; }
  ULONG STDMETHODCALLTYPE Release() override {
    const auto remaining = --references_;
    if (!remaining) delete this;
    return remaining;
  }
 private:
  ~LifetimeObserver() { expired_(); }
  std::atomic<ULONG> references_{1};
  std::function<void()> expired_;
};

inline bool observe_lifetime(ID3D12Object* object, REFGUID key,
                             std::function<void()> expired) {
  auto* observer = new LifetimeObserver(std::move(expired));
  const auto result = object->SetPrivateDataInterface(key, observer);
  observer->Release();
  return SUCCEEDED(result);
}
}  // namespace darktidevr::producer
