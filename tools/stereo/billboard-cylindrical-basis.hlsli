// Darktide uses world Z as up. Preserve the stock basis in the control build.
// Authored spin is applied by each shader after this camera-basis correction.
#ifndef DTVR_ATLAS_CYLINDRICAL
#define DTVR_ATLAS_CYLINDRICAL 0
#endif

void dtvr_atlas_basis(float3 stock_right, float3 stock_forward, float3 stock_up,
                     out float3 right, out float3 up)
{
#if DTVR_ATLAS_CYLINDRICAL
    float2 forward = stock_forward.xy;
    float length_squared = dot(forward, forward);
    float2 horizontal_right;
    if (length_squared > 1.0e-8f)
    {
        forward *= rsqrt(length_squared);
        horizontal_right = float2(forward.y, -forward.x);
    }
    else
    {
        // At a vertical view direction, yaw is undefined; retain a finite
        // horizontal fallback. This does not promise continuity at the pole.
        float2 fallback = stock_right.xy;
        float fallback_squared = dot(fallback, fallback);
        horizontal_right = fallback_squared > 1.0e-8f
            ? fallback * rsqrt(fallback_squared) : float2(1.0f, 0.0f);
    }
    right = float3(horizontal_right, 0.0f);
    up = float3(0.0f, 0.0f, 1.0f);
#else
    right = stock_right;
    up = stock_up;
#endif
}
