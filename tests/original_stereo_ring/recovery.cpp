#include "../isolated_transports.h"
#include "producer/streamline_continuous_submission.h"
#include <iostream>
#include <stdexcept>
#include <cstring>

using Microsoft::WRL::ComPtr;
using darktidevr::producer::StreamlineContinuousSubmission;
void check(HRESULT result) { if(FAILED(result)) throw std::runtime_error("D3D12 failed"); }
void expect(bool value) { if(!value) throw std::runtime_error("Recovery invariant failed"); }
unsigned binding_rejections{};
void log_message(const char* format, ...) {
  if (std::strstr(format,"phase=binding_rejection")) ++binding_rejections;
}
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
    ComPtr<ID3D12Resource> ui_source;
    check(device->CreateCommittedResource(&heap,D3D12_HEAP_FLAG_NONE,&desc,
        D3D12_RESOURCE_STATE_COMMON,nullptr,IID_PPV_ARGS(&ui_source)));
    const std::array<D3D12_RESOURCE_DESC,2> ui_descriptions{desc,desc};
    const darktidevr::producer::StreamlineTagInput ui_input{
        ui_source.Get(),8,4,D3D12_RESOURCE_STATE_COMMON,DXGI_FORMAT_R8G8B8A8_UNORM};
    darktidevr::producer::streamline_2_7_30::Constants constants{};
    for (const unsigned mode : {0U,1U,2U}) {
    const bool with_ui=mode!=0,tag_ui=mode==1;
    StreamlineContinuousSubmission submission;
    expect(submission.initialize(device.Get(),2,{1,2},descriptions,log_message,true,true,
                                  with_ui ? &ui_descriptions : nullptr,tag_ui));
    expect(submission.ui_tagging_enabled()==tag_ui);
    for(std::uint64_t frame=1;frame<=12;++frame) {
      const bool left_ui=with_ui && (tag_ui || frame%3!=0);
      const bool right_ui=with_ui && (tag_ui || frame%3==1);
      submission.capture(0,frame,frame,constants,inputs,queue.Get(),execute,left_ui ? &ui_input : nullptr);
      expect(submission.pose()==frame && !submission.finished());
      expect(!submission.readback_ui()[0]);
      // Exercise discarded partial and complete captures, plus repeated pause.
      if(frame%2==0) submission.capture(1,frame,frame,constants,inputs,queue.Get(),execute,right_ui ? &ui_input : nullptr);
      const auto captured_ui=submission.readback_ui();
      expect((captured_ui[0]!=nullptr)==(frame%2==0 && left_ui && right_ui));
      if(captured_ui[0]) expect(captured_ui[1] && captured_ui[0]!=captured_ui[1] && captured_ui[0]!=ui_source.Get());
      expect(!submission.finished() && submission.ui_tagging_enabled()==tag_ui);
      submission.before_present(nullptr,queue.Get(),frame+1,{}, {},
          darktidevr::producer::StreamlineSubmission::Tagging::legacy,execute);
      submission.pause(queue.Get(),execute,"editor_open");
      submission.after_present(queue.Get(),nullptr,execute);
      expect(!submission.readback_ui()[0]);
      expect(!submission.finished() && !submission.staged() && submission.previous_pose()==0);
      const auto rejections=binding_rejections;
      for (unsigned repeat=0;repeat<3;++repeat)
        submission.before_present(nullptr,queue.Get(),frame+2+repeat,{}, {},
            darktidevr::producer::StreamlineSubmission::Tagging::legacy,execute);
      expect(binding_rejections==rejections); // Paused owners are not resubmitted.
      drain();
    }
    }
    for (const bool configured : {false,true}) {
      StreamlineContinuousSubmission invalid;
      expect(invalid.initialize(device.Get(),2,{1,2},descriptions,log_message,true,false,
                                 configured ? &ui_descriptions : nullptr));
      invalid.capture(0,1,1,constants,inputs,queue.Get(),execute,configured ? nullptr : &ui_input);
      expect(invalid.finished()); // Never silently omit an expected alpha plane.
    }
    // Bounded diagnostic probes intentionally retain their fail-closed policy.
    StreamlineContinuousSubmission bounded;
    expect(bounded.initialize(device.Get(),2,{1,2},descriptions,log_message,false));
    bounded.pause(queue.Get(),execute,"test"); expect(bounded.finished());
    drain(); CloseHandle(event);
    std::cout << "continuous_recovery=pass\n";
  } catch(const std::exception& error) { std::cerr << error.what() << '\n'; return 1; }
}
