#include "producer/generated_stereo.h"
#include "core/shared_generated_frame_state.h"
#include "core/shared_object_name.h"
#include <Windows.h>
#include <d3d12.h>
#include <wrl/client.h>
#include <array>
#include <atomic>
#include <memory>
#include <mutex>
#include <string>
#include <cstdio>
#include <cstdarg>

namespace darktidevr::producer {
namespace {
using Microsoft::WRL::ComPtr;
std::atomic<bool> enabled{};
std::mutex mutex;
struct Slot {
  ComPtr<ID3D12Resource> texture, source;
  HANDLE handle{};
  void* commands{};
  core::SharedGeneratedFrameSlot metadata;
};
std::array<Slot,3> slots;
ComPtr<ID3D12Fence> ready, consumed;
HANDLE ready_handle{}, consumed_handle{};
std::unique_ptr<core::SharedGeneratedFrameStateWriter> writer;
struct InputContext { std::array<void*,6> inputs{}; core::SharedGeneratedFrameSlot frame; };
std::array<InputContext,8> contexts;
unsigned next_context{};
std::uint64_t sequence{};
std::atomic<std::uint64_t> evaluations{}, complete_evaluations{}, paired_evaluations{};
std::uint64_t context_misses{}, output_busy{}, input_contexts{}, unmapped_contexts{};
unsigned width{}, height{};
HANDLE status_log{INVALID_HANDLE_VALUE};
struct OriginalRing {
  std::array<ComPtr<ID3D12Resource>,3> textures;
  std::array<ComPtr<ID3D12Resource>,3> ui_textures;
  std::array<HANDLE,3> handles{};
  std::array<HANDLE,3> ui_handles{};
  ComPtr<ID3D12Fence> ready,consumed;
  HANDLE ready_handle{},consumed_handle{};
  std::unique_ptr<core::SharedGeneratedFrameStateWriter> writer;
  core::SharedGeneratedFrameSlot pending;
  std::uint64_t sequence{};
  unsigned width{},height{};
  bool failed{};
  bool separate_ui{};
} originals;
void status(const char* format, ...) {
  if(status_log==INVALID_HANDLE_VALUE) return;
  char line[1024]; va_list args; va_start(args,format);
  const auto length=vsnprintf(line,sizeof(line),format,args); va_end(args);
  DWORD written{};
  if(length>0 && length<sizeof(line)) WriteFile(status_log,line,length,&written,nullptr);
}

bool initialize(ID3D12Resource* output) {
  auto description = output->GetDesc();
  if (writer) return description.Width == width && description.Height == height;
  if (description.Dimension != D3D12_RESOURCE_DIMENSION_TEXTURE2D ||
      description.Format != DXGI_FORMAT_R8G8B8A8_UNORM || description.SampleDesc.Count != 1 ||
      description.MipLevels != 1 || description.DepthOrArraySize != 1 ||
      !description.Width || description.Width % 2 || !description.Height) return false;
  ComPtr<ID3D12Device> device;
  if (FAILED(output->GetDevice(IID_PPV_ARGS(&device)))) return false;
  D3D12_HEAP_PROPERTIES heap{}; heap.Type = D3D12_HEAP_TYPE_DEFAULT;
  description.Flags = D3D12_RESOURCE_FLAG_NONE;
  for (unsigned index = 0; index < slots.size(); ++index) {
    auto& slot = slots[index];
    const auto name = core::shared_object_name((L"Local\\DarktideVR-generated-stereo-" + std::to_wstring(index)).c_str());
    if (FAILED(device->CreateCommittedResource(&heap, D3D12_HEAP_FLAG_SHARED, &description,
            D3D12_RESOURCE_STATE_COMMON, nullptr, IID_PPV_ARGS(&slot.texture))) ||
        FAILED(device->CreateSharedHandle(slot.texture.Get(), nullptr, GENERIC_ALL, name.c_str(), &slot.handle))) return false;
  }
  if (FAILED(device->CreateFence(0,D3D12_FENCE_FLAG_SHARED,IID_PPV_ARGS(&ready))) ||
      FAILED(device->CreateFence(0,D3D12_FENCE_FLAG_SHARED,IID_PPV_ARGS(&consumed))) ||
      FAILED(device->CreateSharedHandle(ready.Get(),nullptr,GENERIC_ALL,
          core::shared_object_name(L"Local\\DarktideVR-generated-stereo-ready").c_str(),&ready_handle)) ||
      FAILED(device->CreateSharedHandle(consumed.Get(),nullptr,GENERIC_ALL,
          core::shared_object_name(L"Local\\DarktideVR-generated-stereo-consumed").c_str(),&consumed_handle))) return false;
  width = static_cast<unsigned>(description.Width); height = description.Height;
  try { writer = std::make_unique<core::SharedGeneratedFrameStateWriter>(); }
  catch(const std::exception& error) { status("failed metadata: %s\n",error.what()); return false; }
  return true;
}
}
void configure_generated_stereo(bool value) {
  enabled.store(value);
  if(value && status_log==INVALID_HANDLE_VALUE) {
    wchar_t temp[MAX_PATH]{}; GetTempPathW(MAX_PATH,temp);
    const auto path=std::wstring(temp)+L"darktidevr-generated-stereo-"+std::to_wstring(GetCurrentProcessId())+L".log";
    status_log=CreateFileW(path.c_str(),GENERIC_WRITE,FILE_SHARE_READ,nullptr,CREATE_ALWAYS,FILE_ATTRIBUTE_NORMAL,nullptr);
    status("enabled\n");
  }
}
bool generated_stereo_enabled() { return enabled.load(); }
std::uint64_t stage_original_stereo(ID3D12GraphicsCommandList* commands, ID3D12Resource* packed_final,
    std::uint64_t present, std::uint64_t pose, std::uint64_t generation,
    const std::array<ID3D12Resource*, 2>* separate_ui) {
  if(!enabled.load() || !commands || !packed_final || !pose || !generation || originals.failed) return 0;
  // Called only by the serialized input submission path, before its queue
  // execution. The packed final image has just been restored to PRESENT.
  auto description=packed_final->GetDesc();
  if (separate_ui) for (auto* ui : *separate_ui) {
    if (!ui) return 0;
    const auto d = ui->GetDesc();
    if (d.Dimension != D3D12_RESOURCE_DIMENSION_TEXTURE2D || d.Width * 2 != description.Width ||
        d.Height != description.Height || d.Format != DXGI_FORMAT_R8G8B8A8_UNORM ||
        d.DepthOrArraySize != 1 || d.MipLevels != 1 || d.SampleDesc.Count != 1) return 0;
  }
  if(!originals.writer) {
    ComPtr<ID3D12Device> device;
    if(FAILED(packed_final->GetDevice(IID_PPV_ARGS(&device)))) { originals.failed=true; return 0; }
    D3D12_HEAP_PROPERTIES heap{}; heap.Type=D3D12_HEAP_TYPE_DEFAULT;
    description.Flags=D3D12_RESOURCE_FLAG_NONE;
    for(unsigned i=0;i<3;++i) {
      const auto name=core::shared_object_name((L"Local\\DarktideVR-original-stereo-"+std::to_wstring(i)).c_str());
      if(FAILED(device->CreateCommittedResource(&heap,D3D12_HEAP_FLAG_SHARED,&description,
          D3D12_RESOURCE_STATE_COMMON,nullptr,IID_PPV_ARGS(&originals.textures[i]))) ||
          FAILED(device->CreateSharedHandle(originals.textures[i].Get(),nullptr,GENERIC_ALL,name.c_str(),&originals.handles[i]))) {
        originals.failed=true; return 0;
      }
      if (separate_ui) {
        const auto ui_name = core::shared_object_name((L"Local\\DarktideVR-original-ui-" + std::to_wstring(i)).c_str());
        if (FAILED(device->CreateCommittedResource(&heap, D3D12_HEAP_FLAG_SHARED, &description,
            D3D12_RESOURCE_STATE_COMMON, nullptr, IID_PPV_ARGS(&originals.ui_textures[i]))) ||
            FAILED(device->CreateSharedHandle(originals.ui_textures[i].Get(), nullptr, GENERIC_ALL,
                ui_name.c_str(), &originals.ui_handles[i]))) {
          originals.failed = true; return 0;
        }
      }
    }
    if(FAILED(device->CreateFence(0,D3D12_FENCE_FLAG_SHARED,IID_PPV_ARGS(&originals.ready))) ||
       FAILED(device->CreateFence(0,D3D12_FENCE_FLAG_SHARED,IID_PPV_ARGS(&originals.consumed))) ||
       FAILED(device->CreateSharedHandle(originals.ready.Get(),nullptr,GENERIC_ALL,
           core::shared_object_name(L"Local\\DarktideVR-original-stereo-ready").c_str(),&originals.ready_handle)) ||
       FAILED(device->CreateSharedHandle(originals.consumed.Get(),nullptr,GENERIC_ALL,
           core::shared_object_name(L"Local\\DarktideVR-original-stereo-consumed").c_str(),&originals.consumed_handle))) {
      originals.failed=true; return 0;
    }
    try { originals.writer=std::make_unique<core::SharedGeneratedFrameStateWriter>(L"Local\\DarktideVR-original-frame-state-v1"); }
    catch(...) { originals.failed=true; return 0; }
    originals.width=static_cast<unsigned>(description.Width); originals.height=description.Height;
    originals.separate_ui = separate_ui != nullptr;
  }
  if (originals.separate_ui != (separate_ui != nullptr)) return 0;
  if(description.Width!=originals.width || description.Height!=originals.height) return 0;
  const auto next=originals.sequence+1;
  const auto completed=originals.consumed->GetCompletedValue();
  if(completed==UINT64_MAX || (next>3 && completed<next-3)) return 0;
  auto* destination=originals.textures[core::generated_frame_slot(next)].Get();
  std::array<D3D12_RESOURCE_BARRIER,2> barriers{};
  for(auto& b:barriers) b.Type=D3D12_RESOURCE_BARRIER_TYPE_TRANSITION;
  barriers[0].Transition={packed_final,D3D12_RESOURCE_BARRIER_ALL_SUBRESOURCES,D3D12_RESOURCE_STATE_PRESENT,D3D12_RESOURCE_STATE_COPY_SOURCE};
  barriers[1].Transition={destination,D3D12_RESOURCE_BARRIER_ALL_SUBRESOURCES,D3D12_RESOURCE_STATE_COMMON,D3D12_RESOURCE_STATE_COPY_DEST};
  commands->ResourceBarrier(2,barriers.data());
  commands->CopyResource(destination,packed_final);
  for(auto& b:barriers) std::swap(b.Transition.StateBefore,b.Transition.StateAfter);
  commands->ResourceBarrier(2,barriers.data());
  if (separate_ui) {
    auto* packed_ui = originals.ui_textures[core::generated_frame_slot(next)].Get();
    D3D12_RESOURCE_BARRIER target{};
    target.Type = D3D12_RESOURCE_BARRIER_TYPE_TRANSITION;
    target.Transition = {packed_ui, D3D12_RESOURCE_BARRIER_ALL_SUBRESOURCES,
        D3D12_RESOURCE_STATE_COMMON, D3D12_RESOURCE_STATE_COPY_DEST};
    commands->ResourceBarrier(1, &target);
    for (unsigned eye = 0; eye < 2; ++eye) {
      D3D12_RESOURCE_BARRIER source{};
      source.Type = D3D12_RESOURCE_BARRIER_TYPE_TRANSITION;
      source.Transition = {(*separate_ui)[eye], D3D12_RESOURCE_BARRIER_ALL_SUBRESOURCES,
          D3D12_RESOURCE_STATE_COPY_DEST, D3D12_RESOURCE_STATE_COPY_SOURCE};
      commands->ResourceBarrier(1, &source);
      D3D12_TEXTURE_COPY_LOCATION from{}, to{};
      from.pResource = (*separate_ui)[eye]; from.Type = D3D12_TEXTURE_COPY_TYPE_SUBRESOURCE_INDEX;
      to.pResource = packed_ui; to.Type = D3D12_TEXTURE_COPY_TYPE_SUBRESOURCE_INDEX;
      commands->CopyTextureRegion(&to, eye * (originals.width / 2), 0, 0, &from, nullptr);
      std::swap(source.Transition.StateBefore, source.Transition.StateAfter);
      commands->ResourceBarrier(1, &source);
    }
    std::swap(target.Transition.StateBefore, target.Transition.StateAfter);
    commands->ResourceBarrier(1, &target);
  }
  originals.pending={};
  originals.pending.sequence=next; originals.pending.native_call=present;
  originals.pending.current_pose=pose; originals.pending.gameplay_generation=generation;
  originals.pending.frame_index = separate_ui ? core::kOriginalFrameSeparateUi : 0;
  originals.pending.tick_ms=GetTickCount64(); originals.sequence=next;
  return next;
}
bool submit_original_stereo(ID3D12CommandQueue* queue,std::uint64_t original_sequence) {
  if(!original_sequence || originals.pending.sequence!=original_sequence || !originals.writer) return false;
  const auto& p=originals.pending;
  return originals.writer->publish(original_sequence,p.native_call,p.frame_index,originals.width,originals.height,
      static_cast<unsigned>(originals.textures[0]->GetDesc().Format),0,p.current_pose,p.gameplay_generation,p.tick_ms,original_sequence) &&
      SUCCEEDED(queue->Signal(originals.ready.Get(),original_sequence));
}
void generated_stereo_evaluation(bool complete, bool paired) {
  if(!enabled.load()) return;
  ++evaluations;
  if(complete) ++complete_evaluations;
  if(paired) ++paired_evaluations;
}
void generated_stereo_health(std::uint64_t present, std::uint64_t original_ready,
    bool foreground, std::uint64_t present_ms) {
  if(!enabled.load()) return;
  std::scoped_lock lock(mutex);
  static std::uint64_t last_tick{}, last_present{}, last_ready{}, last_original{}, present_total_ms{}, present_samples{};
  present_total_ms+=present_ms; ++present_samples;
  const auto now=GetTickCount64();
  if(!last_tick) { last_tick=now; last_present=present; last_ready=original_ready; last_original=originals.sequence; return; }
  if(now-last_tick<1000) return;
  const double seconds=(now-last_tick)/1000.0;
  status("health engine_fps=%.2f legacy_publish_fps=%.2f original_ring_fps=%.2f present_mean_ms=%.2f foreground=%u evaluations=%llu complete=%llu paired=%llu published=%llu context_misses=%llu output_busy=%llu contexts=%llu unmapped=%llu original_failed=%u\n",
      (present-last_present)/seconds,(original_ready-last_ready)/seconds,(originals.sequence-last_original)/seconds,
      static_cast<double>(present_total_ms)/present_samples,foreground ? 1U : 0U,
      evaluations.load(),complete_evaluations.load(),paired_evaluations.load(),sequence,
      context_misses,output_busy,input_contexts,unmapped_contexts,originals.failed ? 1U : 0U);
  last_tick=now; last_present=present; last_ready=original_ready;
  last_original=originals.sequence;
  present_total_ms=present_samples=0;
}
void generated_stereo_context(std::uint64_t previous, std::uint64_t current,
    std::uint64_t generation, std::uint64_t rendered_ready, const std::array<void*,6>& inputs) {
  std::scoped_lock lock(mutex);
  static unsigned registrations{};
  ++input_contexts;
  if(!rendered_ready) ++unmapped_contexts;
  if(registrations++<12) status("context previous=%llu current=%llu generation=%llu ready=%llu inputs=%p,%p,%p,%p,%p,%p\n",
      previous,current,generation,rendered_ready,inputs[0],inputs[1],inputs[2],inputs[3],inputs[4],inputs[5]);
  auto* entry=&contexts[next_context++%contexts.size()];
  for (auto& prior:contexts) if(prior.inputs==inputs) { entry=&prior; break; }
  entry->inputs=inputs;
  auto& context=entry->frame;
  context = {}; context.previous_pose=previous; context.current_pose=current;
  context.gameplay_generation=generation; context.rendered_ready=rendered_ready;
}
void stage_generated_stereo(ID3D12GraphicsCommandList* commands, ID3D12Resource* output,
    std::uint64_t right_call, const std::array<void*,6>& inputs) {
  if (!enabled.load() || !commands || !output) return;
  std::scoped_lock lock(mutex);
  core::SharedGeneratedFrameSlot context{};
  for(const auto& entry:contexts) if(entry.inputs==inputs) { context=entry.frame; break; }
  if (!context.previous_pose || !context.current_pose || !context.gameplay_generation || !context.rendered_ready) {
    ++context_misses;
    static unsigned misses{};
    if(misses++<12) status("context_miss call=%llu previous=%llu current=%llu inputs=%p,%p,%p,%p,%p,%p\n",
        right_call,context.previous_pose,context.current_pose,inputs[0],inputs[1],inputs[2],inputs[3],inputs[4],inputs[5]);
    return;
  }
  if (!initialize(output)) { status("failed initialize\n"); enabled.store(false); return; }
  auto& slot = slots[core::generated_frame_slot(sequence+1)];
  const auto completed = consumed->GetCompletedValue();
  if (completed == UINT64_MAX || slot.commands || (slot.metadata.sequence && completed < slot.metadata.sequence)) {
    ++output_busy; return;
  }
  slot.source = output;
  slot.metadata = context; slot.metadata.sequence = ++sequence;
  slot.metadata.native_call=right_call; slot.metadata.tick_ms=GetTickCount64();
  std::array<D3D12_RESOURCE_BARRIER,2> barriers{};
  for (auto& barrier : barriers) barrier.Type=D3D12_RESOURCE_BARRIER_TYPE_TRANSITION;
  barriers[0].Transition={output,D3D12_RESOURCE_BARRIER_ALL_SUBRESOURCES,
      D3D12_RESOURCE_STATE_UNORDERED_ACCESS,D3D12_RESOURCE_STATE_COPY_SOURCE};
  barriers[1].Transition={slot.texture.Get(),D3D12_RESOURCE_BARRIER_ALL_SUBRESOURCES,
      D3D12_RESOURCE_STATE_COMMON,D3D12_RESOURCE_STATE_COPY_DEST};
  commands->ResourceBarrier(2,barriers.data());
  commands->CopyResource(slot.texture.Get(),output);
  for (auto& barrier : barriers) std::swap(barrier.Transition.StateBefore,barrier.Transition.StateAfter);
  commands->ResourceBarrier(2,barriers.data());
  slot.commands=commands;
}
void submit_generated_stereo(ID3D12CommandQueue* queue, unsigned count, ID3D12CommandList* const* lists) {
  if (!enabled.load()) return;
  std::scoped_lock lock(mutex);
  for (unsigned i=0;i<count;++i) for(auto& slot:slots) {
    if (slot.commands != lists[i]) continue;
    const auto& frame=slot.metadata;
    // Metadata precedes the GPU-ready signal; readers select only a ready slot.
    if (!writer->publish(frame.sequence,frame.native_call,0,width,height,DXGI_FORMAT_R8G8B8A8_UNORM,
        frame.previous_pose,frame.current_pose,frame.gameplay_generation,frame.tick_ms,frame.rendered_ready) ||
        FAILED(queue->Signal(ready.Get(),frame.sequence))) {
      status("failed publish sequence=%llu\n",frame.sequence);
      enabled.store(false);
    }
    slot.commands=nullptr;
    if(frame.sequence<=8 || frame.sequence%120==0) status("published sequence=%llu current=%llu ready=%llu\n",frame.sequence,frame.current_pose,frame.rendered_ready);
  }
}
void reset_generated_stereo(void* commands) {
  if (!enabled.load()) return;
  std::scoped_lock lock(mutex);
  for(const auto& slot:slots) if(slot.commands==commands) {
    status("failed reset_before_submit sequence=%llu\n",slot.metadata.sequence);
    enabled.store(false);
  }
}
}
