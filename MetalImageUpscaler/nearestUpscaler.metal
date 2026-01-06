//
//  nearestUpscaler.metal
//  MetalImageUpscaler
//
//  Created by Zack on 1/5/26.
//

#include <metal_stdlib>
using namespace metal;

kernel void nearest_kernel(texture2d<float, access::sample>  source  [[texture(0)]],
                           texture2d<float, access::write> target  [[texture(1)]],
                           sampler                         s       [[sampler(0)]],
                           uint2                           gid     [[thread_position_in_grid]])
{
    if (gid.x >= target.get_width() || gid.y >= target.get_height()) return;

    // Normalize the coordinates (0.0 to 1.0) based on the target size
    float2 uv = float2(gid) / float2(target.get_width(), target.get_height());

    // Hardware bilinear sampling happens here
    float4 color = source.sample(s, uv);

    // Write the interpolated color to the destination
    target.write(color, gid);
}
