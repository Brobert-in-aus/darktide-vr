#pragma once
struct ID3D12GraphicsCommandList;
struct ID3D12Resource;
struct ID3D12CommandQueue;
namespace darktidevr::producer {
// Optional one-shot capture, requested by a temp-directory diagnostic flag.
// Caller supplies exact owned COPY_DEST images and submits this list before
// finish_stereo_ui_readback. No file export or GPU wait occurs on Present.
void stage_stereo_ui_readback(ID3D12GraphicsCommandList* commands,
    ID3D12Resource* left_scene, ID3D12Resource* left_final,
    ID3D12Resource* right_scene, ID3D12Resource* right_final);
void finish_stereo_ui_readback(ID3D12CommandQueue* queue);
}
