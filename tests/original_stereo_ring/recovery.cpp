#include "../isolated_transports.h"
#include "producer/streamline_continuous_submission.h"
#include <iostream>
#include <stdexcept>

using Microsoft::WRL::ComPtr;
using darktidevr::producer::StreamlineContinuousSubmission;
void check(HRESULT result) { if(FAILED(result)) throw std::runtime_error("D3D12 failed"); }
void expect(bool value) { if(!value) throw std::runtime_error("Recovery invariant failed"); }
void log_message(const char*, ...) {}
void STDMETHODCALLTYPE execute(ID3D12CommandQueue* queue, UINT count, ID3D12CommandList* const* lists) {
  queue->ExecuteCommandLists(count,lists);
}
int main() {
  try {
    darktidevr::tests::isolate_transports();
    ComPtr<IDXGIFactory4> factory; check(CreateDXGIFactory1(IID_PPV_ARGS(&factory)));
    ComPtr<IDXGIAdapter> warp; check(factory->EnumWarpAdapter(IID_PPV_ARGS(&warp)));
    ComPtr<ID3D12Device> device; check(D3D12CreateDevice(warp.Get(),D3D_FEATURE_LEVEL_11_0,IID_PPV_ARGS(&device)));
    D3D12_COMMAND_QUEUE_DESC queue_desc{};
    ComPtr<ID3D12CommandQueue> queue; check(device->CreateCommandQueue(&queue_desc,IID_PPV_ARGS(&queue)));
    D3D12_HEAP_PROPERTIES heap{}; heap.Type=D3D12_HEAP_TYPE_DEFAULT;
    D3D12_RESOURCE_DESC desc{}; desc.Dimension=D3D12_RESOURCE_DIMENSION_TEXTURE2D;
    desc.Width=8; desc.Height=4; desc.DepthOrArraySize=desc.MipLevels=1;
    desc.Format=DXGI_FORMAT_R8G8B8A8_UNORM; desc.SampleDesc.Count=1;
    ComPtr<ID3D12Resource> source;
    check(device->CreateCommittedResource(&heap,D3D12_HEAP_FLAG_NONE,&desc,D3D12_RESOURCE_STATE_COMMON,nullptr,IID_PPV_ARGS(&source)));
    std::array<std::array<D3D12_RESOURCE_DESC,3>,2> descriptions{};
    for(auto& eye:descriptions) for(auto& role:eye) role=desc;
    std::array<darktidevr::producer::StreamlineTagInput,4> inputs{};
    for(auto& input:inputs) input={source.Get(),8,4,D3D12_RESOURCE_STATE_COMMON,DXGI_FORMAT_R8G8B8A8_UNORM};
    ComPtr<ID3D12Fence> done; check(device->CreateFence(0,D3D12_FENCE_FLAG_NONE,IID_PPV_ARGS(&done)));
    const auto event=CreateEventW(nullptr,FALSE,FALSE,nullptr); expect(event!=nullptr);
    std::uint64_t value{};
    const auto drain=[&] {
      check(queue->Signal(done.Get(),++value)); check(done->SetEventOnCompletion(value,event));
      expect(WaitForSingleObject(event,10000)==WAIT_OBJECT_0);
    };
    StreamlineContinuousSubmission submission;
    expect(submission.initialize(device.Get(),2,{1,2},descriptions,log_message,true,true));
    darktidevr::producer::streamline_2_7_30::Constants constants{};
    for(std::uint64_t frame=1;frame<=12;++frame) {
      submission.capture(0,frame,frame,constants,inputs,queue.Get(),execute);
      expect(submission.pose()==frame && !submission.finished());
      // Exercise discarded partial and complete captures, plus repeated pause.
      if(frame%2==0) submission.capture(1,frame,frame,constants,inputs,queue.Get(),execute);
      submission.before_present(nullptr,queue.Get(),frame+1,{}, {},
          darktidevr::producer::StreamlineSubmission::Tagging::legacy,execute);
      submission.pause(queue.Get(),execute,"editor_open");
      submission.after_present(queue.Get(),nullptr,execute);
      expect(!submission.finished() && !submission.staged() && submission.previous_pose()==0);
      drain();
    }
    // Bounded diagnostic probes intentionally retain their fail-closed policy.
    StreamlineContinuousSubmission bounded;
    expect(bounded.initialize(device.Get(),2,{1,2},descriptions,log_message,false));
    bounded.pause(queue.Get(),execute,"test"); expect(bounded.finished());
    drain(); CloseHandle(event);
    std::cout << "continuous_recovery=pass\n";
  } catch(const std::exception& error) { std::cerr << error.what() << '\n'; return 1; }
}
