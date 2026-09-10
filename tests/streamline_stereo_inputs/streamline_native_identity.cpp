#include "producer/streamline_native_identity.h"
#include <iostream>
#include <stdexcept>

using namespace darktidevr::producer;
void expect(bool value) { if (!value) throw std::runtime_error("native identity invariant failed"); }

struct FakeInterface : IUnknown {
  ULONG references{1};
  unsigned queries{};
  HRESULT answer{E_NOINTERFACE};
  IUnknown* underlying{};
  HRESULT STDMETHODCALLTYPE QueryInterface(REFIID iid, void** output) override {
    ++queries;
    expect(InlineIsEqualGUID(iid, kStreamlineNativeInterface));
    *output = underlying;
    if (underlying) underlying->AddRef();
    return answer;
  }
  ULONG STDMETHODCALLTYPE AddRef() override { return ++references; }
  ULONG STDMETHODCALLTYPE Release() override { return --references; }
};

int main() {
  expect(!observe_streamline_native_identity(nullptr).queried);
  FakeInterface proxy, native;
  auto identity = observe_streamline_native_identity(&proxy);
  expect(identity.queried && identity.result == static_cast<unsigned>(E_NOINTERFACE) && !identity.native);
  proxy.answer = S_OK;
  identity = observe_streamline_native_identity(&proxy);
  expect(identity.queried && !identity.native); // Malformed success remains unknown.
  proxy.underlying = &native;
  identity = observe_streamline_native_identity(&proxy);
  expect(identity.native == reinterpret_cast<std::uintptr_t>(&native));
  expect(native.references == 1 && proxy.references == 1);
  proxy.answer = E_FAIL; // Even a malformed failure must not leak its reference.
  identity = observe_streamline_native_identity(&proxy);
  expect(!identity.native && native.references == 1 && proxy.queries == 4);
  std::cout << "streamline_native_identity=pass null unsupported success malformed reference_balance\n";
}
