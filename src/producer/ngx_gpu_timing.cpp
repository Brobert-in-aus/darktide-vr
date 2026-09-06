#include "producer/ngx_gpu_timing.h"
#include <wrl/client.h>
#include <array>
#include <atomic>
#include <mutex>
#include <cstdio>
#include <string>

namespace darktidevr::producer {
namespace {
using Microsoft::WRL::ComPtr;
std::atomic<bool> enabled{};
std::mutex mutex;
enum class Phase { free, recording, pending, submitted, abandoned };
struct Slot {
  ComPtr<ID3D12QueryHeap> queries;
  ComPtr<ID3D12Resource> readback;
  ComPtr<ID3D12Fence> fence;
  void* commands{};
  Phase phase{};
  UINT64 value{}, frequency{};
  unsigned eye{};
  bool valid{};
};
std::array<Slot,32> slots;
struct Aggregate { unsigned count{}; double evaluate{}, copy{}; };
std::array<Aggregate,2> aggregates;
HANDLE log_file{INVALID_HANDLE_VALUE};

bool allocate(Slot& slot, ID3D12GraphicsCommandList* commands) {
  if (slot.queries) return true;
  ComPtr<ID3D12Device> device;
  if (FAILED(commands->GetDevice(IID_PPV_ARGS(&device)))) return false;
  D3D12_QUERY_HEAP_DESC query{}; query.Type=D3D12_QUERY_HEAP_TYPE_TIMESTAMP; query.Count=3;
  D3D12_HEAP_PROPERTIES heap{}; heap.Type=D3D12_HEAP_TYPE_READBACK;
  D3D12_RESOURCE_DESC buffer{}; buffer.Dimension=D3D12_RESOURCE_DIMENSION_BUFFER;
  buffer.Width=3*sizeof(UINT64); buffer.Height=buffer.DepthOrArraySize=buffer.MipLevels=1;
  buffer.SampleDesc.Count=1; buffer.Layout=D3D12_TEXTURE_LAYOUT_ROW_MAJOR;
  if (FAILED(device->CreateQueryHeap(&query,IID_PPV_ARGS(&slot.queries))) ||
      FAILED(device->CreateCommittedResource(&heap,D3D12_HEAP_FLAG_NONE,&buffer,
          D3D12_RESOURCE_STATE_COPY_DEST,nullptr,IID_PPV_ARGS(&slot.readback))) ||
      FAILED(device->CreateFence(0,D3D12_FENCE_FLAG_NONE,IID_PPV_ARGS(&slot.fence)))) {
    slot.queries.Reset(); slot.readback.Reset(); slot.fence.Reset(); return false;
  }
  return true;
}
void harvest(Slot& slot) {
  if (slot.phase!=Phase::submitted) return;
  const auto complete=slot.fence->GetCompletedValue();
  if (complete==UINT64_MAX) { slot.phase=Phase::abandoned; return; }
  if (complete<slot.value) return;
  UINT64* ticks{}; D3D12_RANGE read{0,3*sizeof(UINT64)};
  if (slot.valid && slot.frequency && SUCCEEDED(slot.readback->Map(0,&read,reinterpret_cast<void**>(&ticks)))) {
    if (ticks[0]<=ticks[1] && ticks[1]<=ticks[2]) {
      auto& a=aggregates[slot.eye];
      a.evaluate+=double(ticks[1]-ticks[0])*1000.0/slot.frequency;
      a.copy+=double(ticks[2]-ticks[1])*1000.0/slot.frequency;
      if (++a.count==120) {
        char line[256];
        const auto length=std::snprintf(line,sizeof(line),
            "NGX_GPU_TIMING tick_ms=%llu eye=%u samples=%u evaluate_gpu_ms=%.4f post_evaluate_gpu_ms=%.4f\n",
            GetTickCount64(),slot.eye,a.count,a.evaluate/a.count,a.copy/a.count);
        DWORD written{};
        if (log_file!=INVALID_HANDLE_VALUE && length>0 && length<int(sizeof(line)))
          WriteFile(log_file,line,static_cast<DWORD>(length),&written,nullptr);
        a={};
      }
    }
    D3D12_RANGE written{0,0}; slot.readback->Unmap(0,&written);
  }
  slot.phase=Phase::free; slot.commands=nullptr;
}
}
void configure_ngx_gpu_timing(bool value) {
  if (!value) return;
  std::scoped_lock lock(mutex);
  if (enabled.load()) return;
  wchar_t temp[MAX_PATH]; const auto length=GetTempPathW(MAX_PATH,temp);
  if (!length || length>=MAX_PATH) return;
  const auto path=std::wstring(temp,length)+L"darktidevr-ngx-gpu-timing-"+std::to_wstring(GetCurrentProcessId())+L".log";
  log_file=CreateFileW(path.c_str(),GENERIC_WRITE,FILE_SHARE_READ,nullptr,CREATE_ALWAYS,FILE_ATTRIBUTE_NORMAL,nullptr);
  enabled.store(log_file!=INVALID_HANDLE_VALUE);
}
unsigned begin_ngx_gpu_timing(ID3D12GraphicsCommandList* commands, unsigned eye) {
  if (!enabled.load() || !commands || eye>1) return 0;
  const auto type=commands->GetType();
  if (type!=D3D12_COMMAND_LIST_TYPE_DIRECT && type!=D3D12_COMMAND_LIST_TYPE_COMPUTE) return 0;
  std::scoped_lock lock(mutex);
  for (auto& slot:slots) harvest(slot);
  for (unsigned i=0;i<slots.size();++i) {
    auto& slot=slots[i];
    if (slot.phase!=Phase::free || !allocate(slot,commands)) continue;
    slot.phase=Phase::recording; slot.commands=commands; slot.eye=eye; slot.valid=false;
    commands->EndQuery(slot.queries.Get(),D3D12_QUERY_TYPE_TIMESTAMP,0);
    return i+1;
  }
  return 0; // Never wait for profiling capacity.
}
void mark_ngx_gpu_timing(unsigned token, ID3D12GraphicsCommandList* commands) {
  if (!token || token>slots.size()) return;
  std::scoped_lock lock(mutex); auto& slot=slots[token-1];
  if (slot.phase==Phase::recording && slot.commands==commands)
    commands->EndQuery(slot.queries.Get(),D3D12_QUERY_TYPE_TIMESTAMP,1);
}
void end_ngx_gpu_timing(unsigned token, ID3D12GraphicsCommandList* commands, bool success) {
  if (!token || token>slots.size()) return;
  std::scoped_lock lock(mutex); auto& slot=slots[token-1];
  if (slot.phase!=Phase::recording || slot.commands!=commands) return;
  commands->EndQuery(slot.queries.Get(),D3D12_QUERY_TYPE_TIMESTAMP,2);
  commands->ResolveQueryData(slot.queries.Get(),D3D12_QUERY_TYPE_TIMESTAMP,0,3,slot.readback.Get(),0);
  slot.valid=success; slot.phase=Phase::pending;
}
void submit_ngx_gpu_timing(ID3D12CommandQueue* queue, unsigned count, ID3D12CommandList* const* lists) {
  if (!enabled.load()) return;
  std::scoped_lock lock(mutex);
  for (unsigned i=0;i<count;++i) for (auto& slot:slots) {
    if (slot.phase!=Phase::pending || slot.commands!=lists[i]) continue;
    slot.frequency=0;
    const auto frequency_result=queue->GetTimestampFrequency(&slot.frequency);
    const auto signal_result=queue->Signal(slot.fence.Get(),++slot.value);
    slot.valid=slot.valid && SUCCEEDED(frequency_result);
    slot.phase=SUCCEEDED(signal_result) ? Phase::submitted : Phase::abandoned;
  }
}
void reset_ngx_gpu_timing(void* commands) {
  if (!enabled.load()) return;
  std::scoped_lock lock(mutex);
  for (auto& slot:slots) if (slot.commands==commands &&
      (slot.phase==Phase::recording || slot.phase==Phase::pending)) {
    slot.phase=Phase::free; slot.commands=nullptr;
  }
}
}
