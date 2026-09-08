float4 vs_main(uint vertex : SV_VertexID) : SV_Position {
    return float4(vertex == 1 ? 1 : -1, vertex == 2 ? 1 : -1, 0, 1);
}

float4 ps_stock() : SV_Target0 { return float4(0, 1, 0, 1); }
float4 ps_probe() : SV_Target0 { return float4(1, 0, 1, 1); }

// Same pixel linkage, but an incompatible resource requirement. This should
// pass signature selection and fail D3D12 creation, exercising stock fallback.
cbuffer MissingRootBinding : register(b0) { float4 missing_color; }
float4 ps_invalid() : SV_Target0 { return missing_color; }
