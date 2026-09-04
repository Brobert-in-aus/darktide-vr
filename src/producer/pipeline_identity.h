#pragma once

#include <d3d12.h>

namespace darktidevr::producer {
// Identity belongs to the COM object, not its recyclable address. Library
// metadata refreshes preserve it; destruction removes it automatically.
inline constexpr GUID kBillboardIdentity =
    {0x7845a25b, 0x02c2, 0x458b, {0xa6, 0x31, 0xf4, 0x65, 0x77, 0x21, 0xd9, 0x33}};

inline bool mark_billboard_pipeline(ID3D12Object* object) {
  const UINT marker = 1;
  return SUCCEEDED(object->SetPrivateData(kBillboardIdentity, sizeof(marker), &marker));
}

inline bool is_billboard_pipeline(ID3D12Object* object) {
  UINT marker = 0;
  UINT size = sizeof(marker);
  return object && SUCCEEDED(object->GetPrivateData(kBillboardIdentity, &size, &marker)) &&
         size == sizeof(marker) && marker == 1;
}
}  // namespace darktidevr::producer
