#include "producer/buffer_registry.h"
#include <dxgi1_6.h>
#include <wrl/client.h>
#include <chrono>
#include <iostream>
#include <limits>
#include <stdexcept>
using Microsoft::WRL::ComPtr;
using darktidevr::producer::BufferRegistry;
using darktidevr::producer::BufferResourceInfo;
void check(bool v) { if(!v) throw std::runtime_error("buffer lookup mismatch"); }
void ok(HRESULT hr) {check(SUCCEEDED(hr));}
// Keep both lookup/locking boundaries out of line so the benchmark compares
// full metadata returns rather than differently optimised pointer-only checks.
__declspec(noinline) std::optional<BufferResourceInfo> linear_lookup(BufferRegistry& registry,std::uint64_t address) {
  std::scoped_lock lock(registry.mutex);
  for(auto it=registry.records_locked().rbegin();it!=registry.records_locked().rend();++it)
    if(address>=it->gpu_start && address-it->gpu_start<it->size) return *it;
  return std::nullopt;
}
__declspec(noinline) std::optional<BufferResourceInfo> cached_lookup(BufferRegistry& registry,std::uint64_t address) {
  std::scoped_lock lock(registry.mutex);return registry.resolve_locked(address);
}
__declspec(noinline) std::optional<BufferResourceInfo> linear_range(
    BufferRegistry& registry,std::uint64_t address,std::uint64_t bytes) {
  std::scoped_lock lock(registry.mutex);
  for(auto it=registry.records_locked().rbegin();it!=registry.records_locked().rend();++it)
    if(address>=it->gpu_start && address-it->gpu_start+bytes<=it->size) return *it;
  return std::nullopt;
}
__declspec(noinline) std::optional<BufferResourceInfo> cached_range(
    BufferRegistry& registry,std::uint64_t address,std::uint64_t bytes) {
  std::scoped_lock lock(registry.mutex);return registry.resolve_range_locked(address,bytes);
}
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
    return cached_lookup(*registry,address);
  };
  auto older=create(),newer=create();
  check(!resolve(1000)); // Cached miss must be invalidated by registration.
  registry->track(older.Get(),1000,100,D3D12_HEAP_TYPE_UPLOAD);
  check(cached_range(*registry,1060,20)->resource==older.Get());
  check(cached_range(*registry,1100,0)->resource==older.Get());
  check(!cached_range(*registry,1100,1));
  check(!cached_range(*registry,1060,(std::numeric_limits<std::uint64_t>::max)()));
  check(resolve(1000)->resource==older.Get());check(!resolve(1100));
  check(resolve(1060)->resource==older.Get()); // Prime overlapping winner.
  registry->track(newer.Get(),1050,25,D3D12_HEAP_TYPE_UPLOAD);
  check(cached_range(*registry,1060,10)->resource==newer.Get());
  check(cached_range(*registry,1060,20)->resource==older.Get());
  check(cached_range(*registry,1060,10)->resource==newer.Get());
  check(cached_range(*registry,1060,40)->resource==older.Get());
  check(!cached_range(*registry,1060,41));
  // This range selects the older entry, exercising cached metadata rather
  // than the newest-allocation fast path during Map/Unmap-style changes.
  {
    std::scoped_lock lock(registry->mutex);
    registry->records_locked()[0].mapped=true;
    registry->records_locked()[0].mapped_base=reinterpret_cast<std::byte*>(0x2000);
    registry->records_locked()[0].staging_base=reinterpret_cast<std::byte*>(0x3000);
    registry->records_locked()[0].staging_size=100;
  }
  check(cached_range(*registry,1060,20)->mapped_base==reinterpret_cast<std::byte*>(0x2000));
  check(cached_range(*registry,1060,20)->staging_base==reinterpret_cast<std::byte*>(0x3000));
  {
    std::scoped_lock lock(registry->mutex);
    registry->records_locked()[0].mapped=false;
    registry->records_locked()[0].mapped_base=nullptr;
    registry->records_locked()[0].staging_base=nullptr;
    registry->records_locked()[0].staging_size=0;
  }
  check(!cached_range(*registry,1060,20)->mapped&&!cached_range(*registry,1060,20)->staging_base);
  check(resolve(1060)->resource==newer.Get());check(resolve(1080)->resource==older.Get());
  newer.Reset();check(resolve(1060)->resource==older.Get());
  check(cached_range(*registry,1060,10)->resource==older.Get());
  {
    std::scoped_lock lock(registry->mutex);
    registry->records_locked()[0].mapped=true;
    registry->records_locked()[0].mapped_base=reinterpret_cast<std::byte*>(0x1000);
  }
  check(resolve(1060)->mapped && resolve(1060)->mapped_base==reinterpret_cast<std::byte*>(0x1000));
  check(cached_range(*registry,1060,10)->mapped_base==reinterpret_cast<std::byte*>(0x1000));
  {
    std::scoped_lock lock(registry->mutex);
    registry->records_locked()[0].mapped=false;registry->records_locked()[0].mapped_base=nullptr;
  }
  check(!resolve(1060)->mapped && !resolve(1060)->mapped_base);
  check(!cached_range(*registry,1060,10)->mapped);
  registry->track(older.Get(),2000,100,D3D12_HEAP_TYPE_UPLOAD);
  check(!resolve(1060));check(resolve(2000)->resource==older.Get());
  check(!cached_range(*registry,1060,10));
  check(cached_range(*registry,2000,100)->resource==older.Get());
  older.Reset();check(!resolve(2000));
  {
    auto extreme=create();
    const auto maximum=(std::numeric_limits<std::uint64_t>::max)();
    registry->track(extreme.Get(),maximum-16,32,D3D12_HEAP_TYPE_UPLOAD);
    auto recent=create();
    registry->track(recent.Get(),1000,25,D3D12_HEAP_TYPE_UPLOAD);
    check(cached_range(*registry,maximum,1)->resource==extreme.Get());
    check(!cached_range(*registry,0,1));
  }
  std::vector<ComPtr<ID3D12Resource>> owners;
  for(unsigned i=0;i<1024;++i) {
    auto resource=create();
    registry->track(resource.Get(),0x100000ULL+i*0x10000ULL,256,D3D12_HEAP_TYPE_UPLOAD);
    owners.push_back(std::move(resource));
  }
  const auto baseline=[&](std::uint64_t address) {return linear_lookup(*registry,address);};
  // Compare across cold lookups, hits, misses, colliding addresses and endpoints.
  for(unsigned repeat=0;repeat<2;++repeat) for(unsigned i=0;i<1024;++i)
    for(const unsigned offset:{0U,128U,255U,256U}) {
      const auto address=0x100000ULL+i*0x10000ULL+offset;
      const auto old=baseline(address),fresh=resolve(address);
      check(old.has_value()==fresh.has_value());
      if(old) check(old->resource==fresh->resource);
    }
  for(unsigned i=0;i<1024;++i) for(const unsigned offset:{0U,128U,255U,256U})
    for(const unsigned bytes:{0U,1U,128U,256U,257U}) {
      const auto address=0x100000ULL+i*0x10000ULL+offset;
      const auto old=linear_range(*registry,address,bytes),fresh=cached_range(*registry,address,bytes);
      check(old.has_value()==fresh.has_value());
      if(old)check(old->resource==fresh->resource);
    }
  // Deleting an early entry moves later vector indices; cached values must expire.
  check(resolve(0x110000)->resource==owners[1].Get());
  check(cached_range(*registry,0x110000,128)->resource==owners[1].Get());
  owners[0].Reset();check(resolve(0x110000)->resource==owners[1].Get());
  check(cached_range(*registry,0x110000,128)->resource==owners[1].Get());
  check(!cached_range(*registry,0x100000,128));
  for(const unsigned workload:{0U,1U,2U,3U}) {
    for(unsigned trial=0;trial<5;++trial) {
      const auto measure=[&](bool old) {
        const auto begin=std::chrono::steady_clock::now();
        for(unsigned i=0;i<100000;++i) {
          const auto index=workload==0 ? 1+i%16 : workload==1 ? 1023 : 1+i%1023;
          const auto address=workload==3 ? 0x100000000ULL+i*256ULL : 0x100000ULL+index*0x10000ULL;
          const auto result=old?baseline(address):resolve(address);
          if(workload==3) check(!result);
          else check(result && result->resource==owners[index].Get());
        }
        return std::chrono::duration<double,std::milli>(std::chrono::steady_clock::now()-begin).count();
      };
      double before{},after{};
      if(trial%2){after=measure(false);before=measure(true);}
      else{before=measure(true);after=measure(false);}
      std::cout << "workload=" << workload << " trial=" << trial << " resources=1023 queries=100000 old_ms=" << before << " new_ms=" << after << '\n';
    }
  }
  for(const unsigned workload:{0U,1U,2U,3U,4U}) for(unsigned trial=0;trial<5;++trial) {
    const auto measure=[&](bool old) {
      const auto begin=std::chrono::steady_clock::now();
      for(unsigned i=0;i<100000;++i) {
        const auto index=workload==0?1+i%16:workload==1?1023:1+i%1023;
        const auto address=workload==3?0x100000000ULL+i*256ULL:
            workload==4?0x100000ULL+(1+i%1022)*0x10000ULL+512+(i/1022)*256ULL:
            0x100000ULL+index*0x10000ULL;
        const auto result=old?linear_range(*registry,address,128):cached_range(*registry,address,128);
        if(workload>=3)check(!result);else check(result&&result->resource==owners[index].Get());
      }
      return std::chrono::duration<double,std::milli>(std::chrono::steady_clock::now()-begin).count();
    };
    double before{},after{};
    if(trial%2){after=measure(false);before=measure(true);}else{before=measure(true);after=measure(false);}
    std::cout<<"range_workload="<<workload<<" trial="<<trial<<" queries=100000 old_ms="<<before<<" new_ms="<<after<<'\n';
  }
  owners.clear();check(registry->records_locked().empty());check(!resolve(0x110000));
  check(!cached_range(*registry,0x110000,128));
  std::cout << "PASS overlap, lifecycle, refresh, index shifts, live metadata and reverse-scan equivalence\n";
}
