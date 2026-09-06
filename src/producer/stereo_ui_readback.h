#pragma once
#include <cstdint>
struct ID3D12GraphicsCommandList;
struct ID3D12Resource;
struct ID3D12CommandQueue;
namespace darktidevr::producer {
// Diagnostic-only transparent replay, completed on the eye's graphics queue.
// Does not install a Streamline tag or establish complete UI coverage.
void observe_stereo_ui_readback_overlay(unsigned eye, std::uint64_t pose,
    ID3D12Resource* resource);
bool stereo_ui_overlay_readback_staged() noexcept;
// Optional one-shot capture, requested by a temp-directory diagnostic flag.
// Caller supplies exact owned COPY_DEST images and submits this list before
// finish_stereo_ui_readback. No file export or GPU wait occurs on Present.
void stage_stereo_ui_readback(ID3D12GraphicsCommandList* commands,
    ID3D12Resource* left_scene, ID3D12Resource* left_final,
    ID3D12Resource* right_scene, ID3D12Resource* right_final,
    std::uint64_t pose = 0);
void finish_stereo_ui_readback(ID3D12CommandQueue* queue);
}
