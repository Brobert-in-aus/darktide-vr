#include "producer/ngx_feature_registry.h"
#include <array>
#include <iostream>
#include <stdexcept>
void expect(bool v) {if (!v) throw std::runtime_error("feature identity invariant failed");}
int main() {
  darktidevr::producer::NgxFeatureRegistry registry;
  std::array<int,130> handles{};
  expect(!registry.lookup(&handles[0]).lifetime);
  expect(!registry.created(&handles[0],11,0xbad00005).lifetime);
  expect(!registry.created(nullptr,11,1).lifetime);
  const auto first=registry.created(&handles[0],11,1);
  expect(first.kind==11 && first.lifetime);
  const auto upscaler=registry.created(&handles[1],1,1);
  expect(upscaler.kind==1 && upscaler.lifetime!=first.lifetime);
  registry.releasing(&handles[0]);
  expect(!registry.lookup(&handles[0]).lifetime);
  const auto reused=registry.created(&handles[0],1,1);
  expect(reused.kind==1 && reused.lifetime!=first.lifetime);
  expect(first.kind==11); // An already captured identity does not change.
  expect(!registry.created(&handles[0],11,1).lifetime);
  expect(!registry.lookup(&handles[0]).lifetime); // Ambiguous duplicate stays unknown.
  registry.releasing(&handles[0]);
  expect(registry.created(&handles[0],11,1).kind==11);
  for (std::size_t i=2;i<128;++i) expect(registry.created(&handles[i],11,1).lifetime!=0);
  expect(!registry.created(&handles[128],11,1).lifetime);
  expect(registry.lookup(&handles[1]).kind==1); // Saturation never evicts a live handle.
  registry.releasing(&handles[5]);
  expect(registry.created(&handles[128],11,1).kind==11);
  std::cout << "ngx_feature_registry=pass failures kinds release reuse duplicate saturation\n";
}
