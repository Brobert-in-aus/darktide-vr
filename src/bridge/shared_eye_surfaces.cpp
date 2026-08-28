#include "bridge/shared_eye_surfaces.h"

#include <cstdint>
#include <stdexcept>
#include <string>

namespace darktidevr::bridge {
namespace {

void check(HRESULT result, const char* operation) {
  if (FAILED(result)) {
    throw std::runtime_error(std::string(operation) + " failed (HRESULT " +
                             std::to_string(static_cast<std::uint32_t>(result)) +
                             ")");
  }
}

void validate_name(const std::wstring& name, const char* label) {
  if (name.empty()) {
    throw std::invalid_argument(std::string(label) + " name must not be empty");
  }
}

HANDLE open_named_handle(ID3D12Device* device, const std::wstring& name,
                         const char* operation) {
  HANDLE handle{};
  check(device->OpenSharedHandleByName(name.c_str(), GENERIC_ALL, &handle),
        operation);
  return handle;
}

void validate_texture(const D3D12_RESOURCE_DESC& actual,
                      SharedEyeSurfaceDescription expected,
                      const std::string& label) {
  if (actual.Dimension != D3D12_RESOURCE_DIMENSION_TEXTURE2D ||
      actual.Width != expected.extent.width ||
      actual.Height != expected.extent.height || actual.DepthOrArraySize != 1 ||
      actual.MipLevels != 1 || actual.Format != expected.format ||
      actual.SampleDesc.Count != 1) {
    throw std::runtime_error(
        label +
        " does not match the negotiated description: actual=" +
        std::to_string(actual.Width) + "x" +
        std::to_string(actual.Height) + " format=" +
        std::to_string(static_cast<std::uint32_t>(actual.Format)) +
        " expected=" + std::to_string(expected.extent.width) + "x" +
        std::to_string(expected.extent.height) + " format=" +
        std::to_string(static_cast<std::uint32_t>(expected.format)));
  }
}

Microsoft::WRL::ComPtr<ID3D12Fence> open_fence(
    ID3D12Device* device, const std::wstring& name, const char* label) {
  const auto handle = open_named_handle(device, name, label);
  Microsoft::WRL::ComPtr<ID3D12Fence> fence;
  const auto result = device->OpenSharedHandle(handle, IID_PPV_ARGS(&fence));
  CloseHandle(handle);
  check(result, label);
  return fence;
}

}  // namespace

OpenedEyeSurfaces open_shared_eye_surfaces(
    ID3D12Device* device, const SharedEyeSurfaceNames& names,
    SharedEyeSurfaceDescription expected) {
  if (!device) {
    throw std::invalid_argument("D3D12 device must not be null");
  }
  if (expected.extent.width == 0 || expected.extent.height == 0 ||
      expected.format == DXGI_FORMAT_UNKNOWN) {
    throw std::invalid_argument("Expected eye description is incomplete");
  }
  validate_name(names.eyes[0], "Left eye");
  validate_name(names.eyes[1], "Right eye");
  validate_name(names.ready_fence, "Ready fence");
  validate_name(names.consumed_fence, "Consumed fence");

  OpenedEyeSurfaces opened;
  opened.description = expected;
  for (std::size_t eye = 0; eye < opened.eyes.size(); ++eye) {
    const auto handle = open_named_handle(
        device, names.eyes[eye], "ID3D12Device::OpenSharedHandleByName(eye)");
    const auto result =
        device->OpenSharedHandle(handle, IID_PPV_ARGS(&opened.eyes[eye]));
    CloseHandle(handle);
    check(result, "ID3D12Device::OpenSharedHandle(eye)");
    validate_texture(opened.eyes[eye]->GetDesc(), expected,
                     "Shared eye " + std::to_string(eye));
  }
  opened.ready_fence = open_fence(
      device, names.ready_fence,
      "ID3D12Device::OpenSharedHandle(ready fence)");
  opened.consumed_fence = open_fence(
      device, names.consumed_fence,
      "ID3D12Device::OpenSharedHandle(consumed fence)");
  return opened;
}

OpenedSharedTexture open_shared_texture(
    ID3D12Device* device, const SharedTextureNames& names,
    SharedEyeSurfaceDescription expected) {
  if (!device) {
    throw std::invalid_argument("D3D12 device must not be null");
  }
  if (expected.extent.width == 0 || expected.extent.height == 0 ||
      expected.format == DXGI_FORMAT_UNKNOWN) {
    throw std::invalid_argument("Expected texture description is incomplete");
  }
  validate_name(names.texture, "Texture");
  validate_name(names.ready_fence, "Ready fence");
  validate_name(names.consumed_fence, "Consumed fence");

  OpenedSharedTexture opened;
  opened.description = expected;
  const auto texture_handle = open_named_handle(
      device, names.texture,
      "ID3D12Device::OpenSharedHandleByName(texture)");
  const auto texture_result = device->OpenSharedHandle(
      texture_handle, IID_PPV_ARGS(&opened.texture));
  CloseHandle(texture_handle);
  check(texture_result, "ID3D12Device::OpenSharedHandle(texture)");
  validate_texture(opened.texture->GetDesc(), expected, "Shared texture");
  opened.ready_fence = open_fence(
      device, names.ready_fence,
      "ID3D12Device::OpenSharedHandle(texture ready fence)");
  opened.consumed_fence = open_fence(
      device, names.consumed_fence,
      "ID3D12Device::OpenSharedHandle(texture consumed fence)");
  return opened;
}

}  // namespace darktidevr::bridge
