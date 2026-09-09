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
// Diagnostic replay stays requested until an eligible one-shot is consumed.
// Failed attempts stop replay too; missing/mismatched overlay pairs keep waiting.
bool stereo_ui_overlay_capture_requested();
// Optional one-shot capture, requested by a temp-directory diagnostic flag.
// Caller supplies exact owned COPY_DEST images and submits this list before
// finish_stereo_ui_readback. No file export or GPU wait occurs on Present.
void stage_stereo_ui_readback(ID3D12GraphicsCommandList* commands,
    ID3D12Resource* left_scene, ID3D12Resource* left_final,
    ID3D12Resource* right_scene, ID3D12Resource* right_final,
    std::uint64_t pose = 0, ID3D12Resource* left_ui = nullptr,
    ID3D12Resource* right_ui = nullptr);
void finish_stereo_ui_readback(ID3D12CommandQueue* queue);
}
