#include "../isolated_transports.h"
#include <Windows.h>
#include <d3d12.h>
#include <wrl/client.h>
#include <array>
#include <barrier>
#include <chrono>
#include <iostream>
#include <stdexcept>
#include <string_view>
#include <thread>
#include <vector>

using Microsoft::WRL::ComPtr;
void require(HRESULT hr) {
  if (FAILED(hr)) throw std::runtime_error("D3D12 operation failed");
}

int wmain(int argc, wchar_t** argv) {
  try {
    if (argc != 3) throw std::invalid_argument("Expected copied DLL and clean/diagnostic/control");
    const std::wstring_view mode(argv[2]);
    if (mode != L"clean" && mode != L"diagnostic" && mode != L"control")
      throw std::invalid_argument("Unknown mode");
    darktidevr::tests::isolate_transports();
    const auto module = LoadLibraryW(argv[1]);
    if (!module) throw std::runtime_error("DLL load failed");
    const auto install = reinterpret_cast<int(*)()>(GetProcAddress(module, "dtvr_install"));
    const auto diagnostics = reinterpret_cast<int(*)(int)>(
        GetProcAddress(module, "dtvr_set_diagnostic_render_hooks"));
    if (!install || !diagnostics) throw std::runtime_error("Missing exports");
    if (mode != L"control" && (diagnostics(mode == L"diagnostic") || install()))
      throw std::runtime_error("Hook installation failed");
    ComPtr<ID3D12Device> device;
    require(D3D12CreateDevice(nullptr, D3D_FEATURE_LEVEL_12_0, IID_PPV_ARGS(&device)));
    constexpr UINT descriptors = 16;
    const auto increment = device->GetDescriptorHandleIncrementSize(D3D12_DESCRIPTOR_HEAP_TYPE_CBV_SRV_UAV);
    for (const unsigned workers : {1U, 8U}) {
      struct Worker {
        ComPtr<ID3D12DescriptorHeap> source, destination;
        std::array<D3D12_CPU_DESCRIPTOR_HANDLE, descriptors> sources{};
        D3D12_CPU_DESCRIPTOR_HANDLE output{};
      };
      std::vector<Worker> state(workers);
      for (auto& worker : state) {
        D3D12_DESCRIPTOR_HEAP_DESC heap{};
        heap.Type = D3D12_DESCRIPTOR_HEAP_TYPE_CBV_SRV_UAV;
        heap.NumDescriptors = descriptors;
        require(device->CreateDescriptorHeap(&heap, IID_PPV_ARGS(&worker.source)));
        heap.Flags = D3D12_DESCRIPTOR_HEAP_FLAG_SHADER_VISIBLE;
        require(device->CreateDescriptorHeap(&heap, IID_PPV_ARGS(&worker.destination)));
        const auto start = worker.source->GetCPUDescriptorHandleForHeapStart();
        worker.output = worker.destination->GetCPUDescriptorHandleForHeapStart();
        D3D12_SHADER_RESOURCE_VIEW_DESC srv{};
        srv.Format = DXGI_FORMAT_R32_FLOAT;
        srv.ViewDimension = D3D12_SRV_DIMENSION_BUFFER;
        srv.Shader4ComponentMapping = D3D12_DEFAULT_SHADER_4_COMPONENT_MAPPING;
        srv.Buffer.NumElements = 16;
        for (UINT i = 0; i < descriptors; ++i) {
          worker.sources[i].ptr = start.ptr + SIZE_T(i) * increment;
          device->CreateShaderResourceView(nullptr, &srv, worker.sources[i]);
        }
      }
      for (const bool defaults : {false, true}) {
        const auto record = [&](Worker& worker, unsigned batches) {
          for (unsigned batch = 0; batch < batches; ++batch) {
            if (defaults) {
              for (UINT i = 0; i < descriptors; ++i) {
                const D3D12_CPU_DESCRIPTOR_HANDLE destination{worker.output.ptr + SIZE_T(i) * increment};
                device->CopyDescriptorsSimple(1, destination, worker.sources[0],
                                             D3D12_DESCRIPTOR_HEAP_TYPE_CBV_SRV_UAV);
              }
            }
            device->CopyDescriptors(1, &worker.output, &descriptors, descriptors,
                                    worker.sources.data(), nullptr,
                                    D3D12_DESCRIPTOR_HEAP_TYPE_CBV_SRV_UAV);
          }
        };
        for (auto& worker : state) record(worker, 1000);
        std::barrier ready(workers + 1);
        std::barrier start(workers + 1);
        std::barrier complete(workers + 1);
        std::vector<std::jthread> threads;
        for (unsigned index = 0; index < workers; ++index) {
          threads.emplace_back([&, index] {
            ready.arrive_and_wait();
            start.arrive_and_wait();
            record(state[index], 10000);
            complete.arrive_and_wait();
          });
        }
        ready.arrive_and_wait();
        const auto began = std::chrono::steady_clock::now();
        start.arrive_and_wait();
        complete.arrive_and_wait();
        const auto elapsed = std::chrono::duration<double, std::milli>(
            std::chrono::steady_clock::now() - began).count();
        std::cout << "workers=" << workers << " default_fills=" << defaults
                  << " batches=" << workers * 10000 << " elapsed_ms=" << elapsed << '\n';
      }
    }
    std::cout << "PASS descriptor_copies_only=1 gpu_submissions=0\n";
    // Keep hooks loaded until process exit.
    return 0;
  } catch (const std::exception& error) {
    std::cerr << error.what() << '\n';
    return 1;
  }
}
