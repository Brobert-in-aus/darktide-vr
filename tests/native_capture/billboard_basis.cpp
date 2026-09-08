#include <d3d11.h>
#include <d3dcompiler.h>
#include <wrl/client.h>

#include <array>
#include <cmath>
#include <iostream>
#include <stdexcept>
#include <vector>

using Microsoft::WRL::ComPtr;
using Vector = std::array<float, 4>;

void check(HRESULT result, const char* operation) {
  if (FAILED(result)) throw std::runtime_error(operation);
}

void check_axes(const Vector& actual, const Vector& expected) {
  for (std::size_t i = 0; i < 4; ++i) {
    if (!std::isfinite(actual[i]) || std::abs(actual[i] - expected[i]) > 2e-5f)
      throw std::runtime_error("Compiled billboard basis differs from expected axes");
  }
}

Vector combine(const Vector& a, float scale_a, const Vector& b, float scale_b) {
  Vector value{};
  for (std::size_t i = 0; i < 3; ++i) value[i] = a[i] * scale_a + b[i] * scale_b;
  return value;
}

int wmain(int argc, wchar_t** argv) {
  try {
    if (argc != 2) throw std::runtime_error("Expected compute shader source path");
    std::vector<Vector> inputs, expected;
    const Vector world_up{0, 0, 1, 0};
    constexpr float radians = 3.14159265358979323846f / 180.0f;
    // Fixed yaw must produce identical cylindrical axes across pitch/roll.
    for (float yaw : {-170.f, -90.f, -25.f, 0.f, 35.f, 90.f, 170.f}) {
      const Vector yaw_right{std::cos(yaw * radians), std::sin(yaw * radians), 0, 0};
      const Vector yaw_forward{-yaw_right[1], yaw_right[0], 0, 0};
      for (float pitch : {-89.f, -60.f, -15.f, 0.f, 15.f, 60.f, 89.f}) {
        const auto forward = combine(yaw_forward, std::cos(pitch * radians),
                                     world_up, std::sin(pitch * radians));
        const auto pitched_up = combine(world_up, std::cos(pitch * radians),
                                        yaw_forward, -std::sin(pitch * radians));
        for (float roll : {-150.f, -90.f, -30.f, 0.f, 30.f, 90.f, 150.f}) {
          inputs.push_back(combine(yaw_right, std::cos(roll * radians),
                                   pitched_up, std::sin(roll * radians)));
          inputs.push_back(forward);
          inputs.push_back(combine(pitched_up, std::cos(roll * radians),
                                   yaw_right, -std::sin(roll * radians)));
          expected.push_back(yaw_right);
          expected.push_back(world_up);
        }
      }
    }
    // Exact pole, nearly vertical forward, and degenerate fallback.
    for (const auto& forward : {Vector{0, 0, 1, 0}, Vector{1e-6f, 0, -1, 0}}) {
      inputs.insert(inputs.end(), {Vector{0, 2, 0, 0}, forward, Vector{1, 0, 0, 0}});
      expected.insert(expected.end(), {Vector{0, 1, 0, 0}, world_up});
    }
    inputs.insert(inputs.end(), {Vector{}, Vector{}, Vector{}});
    expected.insert(expected.end(), {Vector{1, 0, 0, 0}, world_up});
    const auto count = static_cast<UINT>(inputs.size() / 3);

    // WARP executes the real compiled HLSL without using the live game's GPU.
    ComPtr<ID3D11Device> device;
    ComPtr<ID3D11DeviceContext> context;
    const D3D_FEATURE_LEVEL requested = D3D_FEATURE_LEVEL_11_0;
    check(D3D11CreateDevice(nullptr, D3D_DRIVER_TYPE_WARP, nullptr, 0,
        &requested, 1, D3D11_SDK_VERSION, &device, nullptr, &context), "Create WARP device");
    D3D11_BUFFER_DESC input_desc{};
    input_desc.ByteWidth = static_cast<UINT>(inputs.size() * sizeof(Vector));
    input_desc.Usage = D3D11_USAGE_IMMUTABLE;
    input_desc.BindFlags = D3D11_BIND_SHADER_RESOURCE;
    input_desc.MiscFlags = D3D11_RESOURCE_MISC_BUFFER_STRUCTURED;
    input_desc.StructureByteStride = sizeof(Vector);
    const D3D11_SUBRESOURCE_DATA input_data{inputs.data(), 0, 0};
    ComPtr<ID3D11Buffer> input;
    check(device->CreateBuffer(&input_desc, &input_data, &input), "Create input buffer");
    ComPtr<ID3D11ShaderResourceView> srv;
    check(device->CreateShaderResourceView(input.Get(), nullptr, &srv), "Create input view");
    D3D11_BUFFER_DESC output_desc{};
    output_desc.ByteWidth = static_cast<UINT>(expected.size() * sizeof(Vector));
    output_desc.Usage = D3D11_USAGE_DEFAULT;
    output_desc.BindFlags = D3D11_BIND_UNORDERED_ACCESS;
    output_desc.MiscFlags = D3D11_RESOURCE_MISC_BUFFER_STRUCTURED;
    output_desc.StructureByteStride = sizeof(Vector);
    ComPtr<ID3D11Buffer> output;
    check(device->CreateBuffer(&output_desc, nullptr, &output), "Create output buffer");
    ComPtr<ID3D11UnorderedAccessView> uav;
    check(device->CreateUnorderedAccessView(output.Get(), nullptr, &uav), "Create output view");
    auto staging_desc = output_desc;
    staging_desc.Usage = D3D11_USAGE_STAGING;
    staging_desc.BindFlags = staging_desc.MiscFlags = staging_desc.StructureByteStride = 0;
    staging_desc.CPUAccessFlags = D3D11_CPU_ACCESS_READ;
    ComPtr<ID3D11Buffer> staging;
    check(device->CreateBuffer(&staging_desc, nullptr, &staging), "Create readback buffer");
    for (int cylindrical : {0, 1}) {
      const D3D_SHADER_MACRO macros[] = {
          {"DTVR_ATLAS_CYLINDRICAL", cylindrical ? "1" : "0"}, {nullptr, nullptr}};
      ComPtr<ID3DBlob> bytecode, errors;
      const auto compile = D3DCompileFromFile(argv[1], macros, D3D_COMPILE_STANDARD_FILE_INCLUDE,
          "main", "cs_5_0", D3DCOMPILE_ENABLE_STRICTNESS | D3DCOMPILE_WARNINGS_ARE_ERRORS,
          0, &bytecode, &errors);
      if (FAILED(compile) && errors)
        std::cerr.write(static_cast<const char*>(errors->GetBufferPointer()), errors->GetBufferSize());
      check(compile, "Compile basis fixture");
      ComPtr<ID3D11ComputeShader> shader;
      check(device->CreateComputeShader(bytecode->GetBufferPointer(), bytecode->GetBufferSize(),
          nullptr, &shader), "Create compute shader");
      context->CSSetShader(shader.Get(), nullptr, 0);
      ID3D11ShaderResourceView* input_view = srv.Get();
      ID3D11UnorderedAccessView* output_view = uav.Get();
      context->CSSetShaderResources(0, 1, &input_view);
      context->CSSetUnorderedAccessViews(0, 1, &output_view, nullptr);
      context->Dispatch(count, 1, 1);
      ID3D11UnorderedAccessView* unbound = nullptr;
      context->CSSetUnorderedAccessViews(0, 1, &unbound, nullptr);
      context->CopyResource(staging.Get(), output.Get());
      D3D11_MAPPED_SUBRESOURCE mapped{};
      check(context->Map(staging.Get(), 0, D3D11_MAP_READ, 0, &mapped), "Read compiled basis");
      const auto* values = static_cast<const Vector*>(mapped.pData);
      for (UINT i = 0; i < count; ++i) {
        check_axes(values[i * 2], cylindrical ? expected[i * 2] : inputs[i * 3]);
        check_axes(values[i * 2 + 1], cylindrical ? expected[i * 2 + 1] : inputs[i * 3 + 2]);
      }
      context->Unmap(staging.Get(), 0);
    }
    std::cout << "Compiled stock/cylindrical basis passed " << count << " cases each\n";
    return 0;
  } catch (const std::exception& error) {
    std::cerr << error.what() << '\n';
    return 1;
  }
}
