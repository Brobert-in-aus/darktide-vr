#include "producer/buffer_registry.h"
#include <dxgi1_6.h>
#include <wrl/client.h>
#include <chrono>
#include <iostream>
#include <stdexcept>
using Microsoft::WRL::ComPtr;
using darktidevr::producer::BufferRegistry;
using darktidevr::producer::BufferResourceInfo;
void check(bool v) { if(!v) throw std::runtime_error("buffer lookup mismatch"); }
void ok(HRESULT hr) {check(SUCCEEDED(hr));}
int main() {
  ComPtr<IDXGIFactory4> factory; ok(CreateDXGIFactory1(IID_PPV_ARGS(&factory)));
  ComPtr<IDXGIAdapter> warp; ok(factory->EnumWarpAdapter(IID_PPV_ARGS(&warp)));
  ComPtr<ID3D12Device> device; ok(D3D12CreateDevice(warp.Get(),D3D_FEATURE_LEVEL_11_0,IID_PPV_ARGS(&device)));
  D3D12_HEAP_PROPERTIES heap{};heap.Type=D3D12_HEAP_TYPE_UPLOAD;
  D3D12_RESOURCE_DESC desc{};desc.Dimension=D3D12_RESOURCE_DIMENSION_BUFFER;
  desc.Width=256;desc.Height=1;desc.DepthOrArraySize=1;desc.MipLevels=1;
  desc.SampleDesc.Count=1;desc.Layout=D3D12_TEXTURE_LAYOUT_ROW_MAJOR;
  const auto create=[&] {
    ComPtr<ID3D12Resource> value;
    ok(device->CreateCommittedResource(&heap,D3D12_HEAP_FLAG_NONE,&desc,
      D3D12_RESOURCE_STATE_GENERIC_READ,nullptr,IID_PPV_ARGS(&value)));
    return value;
  };
  const auto registry=std::make_shared<BufferRegistry>();
  const auto resolve=[&](std::uint64_t address) {
    std::scoped_lock lock(registry->mutex);return registry->resolve_locked(address);
  };
  auto older=create(),newer=create();
  check(!resolve(1000)); // Cached miss must be invalidated by registration.
  registry->track(older.Get(),1000,100,D3D12_HEAP_TYPE_UPLOAD);
  check(resolve(1000)->resource==older.Get());check(!resolve(1100));
  registry->track(newer.Get(),1050,25,D3D12_HEAP_TYPE_UPLOAD);
  check(resolve(1060)->resource==newer.Get());check(resolve(1080)->resource==older.Get());
  newer.Reset();check(resolve(1060)->resource==older.Get());
  {
    std::scoped_lock lock(registry->mutex);
    registry->records_locked()[0].mapped=true;
    registry->records_locked()[0].mapped_base=reinterpret_cast<std::byte*>(0x1000);
  }
  check(resolve(1060)->mapped && resolve(1060)->mapped_base==reinterpret_cast<std::byte*>(0x1000));
  {
    std::scoped_lock lock(registry->mutex);
    registry->records_locked()[0].mapped=false;registry->records_locked()[0].mapped_base=nullptr;
  }
  check(!resolve(1060)->mapped && !resolve(1060)->mapped_base);
  registry->track(older.Get(),2000,100,D3D12_HEAP_TYPE_UPLOAD);
  check(!resolve(1060));check(resolve(2000)->resource==older.Get());
  older.Reset();check(!resolve(2000));
  std::vector<ComPtr<ID3D12Resource>> owners;
  for(unsigned i=0;i<1024;++i) {
    auto resource=create();
    registry->track(resource.Get(),0x100000ULL+i*0x10000ULL,256,D3D12_HEAP_TYPE_UPLOAD);
    owners.push_back(std::move(resource));
  }
  const auto baseline=[&](std::uint64_t address)->std::optional<BufferResourceInfo> {
    std::scoped_lock lock(registry->mutex);
    for(auto it=registry->records_locked().rbegin();it!=registry->records_locked().rend();++it)
      if(address>=it->gpu_start && address-it->gpu_start<it->size) return *it;
    return std::nullopt;
  };
  // Compare across cold lookups, hits, misses, colliding addresses and endpoints.
  for(unsigned repeat=0;repeat<2;++repeat) for(unsigned i=0;i<1024;++i)
    for(const unsigned offset:{0U,128U,255U,256U}) {
      const auto address=0x100000ULL+i*0x10000ULL+offset;
      const auto old=baseline(address),fresh=resolve(address);
      check(old.has_value()==fresh.has_value());
      if(old) check(old->resource==fresh->resource);
    }
  // Deleting an early entry moves later vector indices; cached values must expire.
  check(resolve(0x110000)->resource==owners[1].Get());
  owners[0].Reset();check(resolve(0x110000)->resource==owners[1].Get());
  for(unsigned trial=0;trial<5;++trial) {
    const auto measure=[&](bool old) {
      const auto begin=std::chrono::steady_clock::now();
      for(unsigned i=0;i<100000;++i) {
        const auto index=1+i%16;
        const auto address=0x100000ULL+index*0x10000ULL;
        const auto result=old?baseline(address):resolve(address);
        check(result && result->resource==owners[index].Get());
      }
      return std::chrono::duration<double,std::milli>(std::chrono::steady_clock::now()-begin).count();
    };
    double before{},after{};
    if(trial%2){after=measure(false);before=measure(true);}
    else{before=measure(true);after=measure(false);}
    std::cout << "trial=" << trial << " resources=1023 hot_addresses=16 queries=100000 old_ms=" << before << " new_ms=" << after << '\n';
  }
  owners.clear();check(registry->records_locked().empty());check(!resolve(0x110000));
  std::cout << "PASS overlap, lifecycle, refresh, index shifts, live metadata and reverse-scan equivalence\n";
}
