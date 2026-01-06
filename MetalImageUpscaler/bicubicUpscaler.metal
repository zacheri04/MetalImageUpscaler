//
//  bicubicUpscaler.metal
//  MetalImageUpscaler
//
//  Created by Zack on 1/5/26.
//

#include <metal_stdlib>
using namespace metal;

// Helper function for the cubic weighting
float weight(float x) {
    float a = -0.5;
    x = abs(x);
    if (x <= 1.0) return (a + 2.0) * pow(x, 3.0) - (a + 3.0) * pow(x, 2.0) + 1.0;
    if (x < 2.0) return a * pow(x, 3.0) - 5.0 * a * pow(x, 2.0) + 8.0 * a * x - 4.0 * a;
    return 0.0;
}

kernel void bicubic_kernel(texture2d<float, access::sample> source [[texture(0)]],
                                   texture2d<float, access::write> target [[texture(1)]],
                                   sampler s [[sampler(0)]],
                                   uint2 gid [[thread_position_in_grid]])
{
    if (gid.x >= target.get_width() || gid.y >= target.get_height()) return;

    float2 targetSize = float2(target.get_width(), target.get_height());
    float2 sourceSize = float2(source.get_width(), source.get_height());
    
    // Normalized coordinate of the center of the target pixel
    float2 uv = (float2(gid) + 0.5) / targetSize;
    
    // Convert UV to "pixel coordinates" in the source image
    float2 pixelPos = uv * sourceSize - 0.5;
    float2 index = floor(pixelPos);
    float2 fraction = pixelPos - index;

    float4 color = float4(0.0);
    float totalWeight = 0.0;

    // Loop through a 4x4 neighborhood
    for (int j = -1; j <= 2; j++) {
        for (int i = -1; i <= 2; i++) {
            float2 offset = float2(float(i), float(j));
            float w = weight(offset.x - fraction.x) * weight(offset.y - fraction.y);
            
            // Sample and accumulate
            float2 sampleUV = (index + offset + 0.5) / sourceSize;
            color += source.sample(s, sampleUV) * w;
            totalWeight += w;
        }
    }

    target.write(color / totalWeight, gid);
    /*
    // Another way to do it using dedicated hardware, but I found the output worse
    if (gid.x >= target.get_width() || gid.y >= target.get_height()) return;

        float2 targetSize = float2(target.get_width(), target.get_height());
        float2 sourceSize = float2(source.get_width(), source.get_height());
        float2 invSourceSize = 1.0 / sourceSize;

        float2 uv = (float2(gid) + 0.5) / targetSize;
        float2 pixelPos = uv * sourceSize - 0.5;
        float2 f = fract(pixelPos);

        // 1. Calculate the 4 weights for each axis
        float4 wx = float4(weight(f.x + 1.0), weight(f.x), weight(1.0 - f.x), weight(2.0 - f.x));
        float4 wy = float4(weight(f.y + 1.0), weight(f.y), weight(1.0 - f.y), weight(2.0 - f.y));

        // 2. Combine weights into 2 "bilinear" weights
        float2 w0 = float2(wx.x + wx.y, wy.x + wy.y);
        float2 w1 = float2(wx.z + wx.w, wy.z + wy.w);

        // 3. Calculate the optimized offsets
        // This tells the hardware exactly where to sample to get the cubic result
    
        float offset0x  = (wx.y / w0.x) - 1.0;
        float offset1x  = (wx.w / w1.x) + 1.0;
        float offset0y  = (wy.y / w0.y) - 1.0;
        float offset1y  = (wy.w / w1.y) + 1.0;

        // 4. Sample only 4 times instead of 16
        float2 basePos = floor(pixelPos) + 0.5;
        
        float4 color =
            (w0.x * w0.y) * source.sample(s, (basePos + float2(offset0x, offset0y)) * invSourceSize) +
            (w1.x * w0.y) * source.sample(s, (basePos + float2(offset1x, offset0y)) * invSourceSize) +
            (w0.x * w1.y) * source.sample(s, (basePos + float2(offset0x, offset1y)) * invSourceSize) +
            (w1.x * w1.y) * source.sample(s, (basePos + float2(offset1x, offset1y)) * invSourceSize);

        target.write(color, gid);
     */
}
