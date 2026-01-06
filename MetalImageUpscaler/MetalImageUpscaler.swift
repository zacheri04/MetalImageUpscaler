//
//  main.swift
//  MetalImageUpscaler
//
//  Created by Zack on 1/5/26.
//

import ArgumentParser
import Foundation
import ImageIO
import MetalKit
import MetalPerformanceShaders
import UniformTypeIdentifiers

@main
struct MetalImageUpscaler: ParsableCommand {
    @Option(
        name: [.short, .customLong("input-file")],
        help: "Input file"
    )
    var inputFile: String

    @Option(name: [.short, .customLong("scale")], help: "Desired scale")
    var scale: Int

    @Option(
        name: [.short, .customLong("method")],
        help: "Valid options are 'bilinear', 'bicubic', 'nearest', and 'lanczos'. Defaults to 'bicubic'"
    )
    var desiredMethod: String?

    mutating func run() throws {
        switch desiredMethod {
        case "bilinear":
            scaleImage(method: .bilinear, scale: scale)
        case "bicubic":
            scaleImage(method: .bicubic, scale: scale)
        case "nearest":
            scaleImage(method: .nearest, scale: scale)
        case "lanczos":
            scaleImage(method: .lanczos, scale: scale)
        default:
            scaleImage(method: .bicubic, scale: scale)
        }

        // Take a CGImage and output it to the disk
        func writeImage(image: CGImage, path: URL, asType type: UTType) {
            guard
                let destination = CGImageDestinationCreateWithURL(
                    path as CFURL,
                    type.identifier as CFString,
                    1,
                    nil
                )
            else {
                fatalError("Error saving image")
            }

            CGImageDestinationAddImage(destination, image, nil)

            CGImageDestinationFinalize(destination)
        }

        // Read image from arguments[0] and create a CGImage and find the filetype
        func readImage(path: String) -> (CGImage, UTType)? {
            let standardizedPath = NSString(string: path).expandingTildeInPath
            let fileURL = URL(fileURLWithPath: standardizedPath).absoluteURL

            guard
                let imageSource = CGImageSourceCreateWithURL(
                    fileURL as CFURL,
                    nil
                )
            else {
                return nil
            }
            guard
                let image = CGImageSourceCreateImageAtIndex(imageSource, 0, nil)
            else {
                return nil
            }
            return (
                image,
                UTType(
                    filenameExtension: URL(fileURLWithPath: path).pathExtension
                )!
            )
        }

        // Upscaling types
        enum method: String {
            case bilinear, bicubic, nearest, lanczos
        }

        /*
         General flow is:
         1. Read image data
         2. Scale image based by desired method
         3. Write the output image
         */
        func scaleImage(method: method, scale: Int) {
            // Read image data and get file type
            guard let imageData = readImage(path: inputFile) else {
                fatalError("Error reading file")
            }
            var output: CGImage

            // Set up GPU work
            guard let device = MTLCreateSystemDefaultDevice() else {
                fatalError("Error: Metal is not supported on this device")
            }

            let inputTexture = loadTexture(from: imageData.0, device: device)

            let desc = MTLTextureDescriptor.texture2DDescriptor(
                pixelFormat: .rgba8Unorm,
                width: inputTexture.width * scale,
                height: inputTexture.height * scale,
                mipmapped: false
            )
            desc.usage = [.shaderWrite, .shaderRead]

            let outputTexture = device.makeTexture(
                descriptor: desc
            )!

            guard let defaultLibrary = device.makeDefaultLibrary(),
                let bilinearUpscaleFunction = defaultLibrary.makeFunction(
                    name: "bilinear_kernel"
                ),
                let bicubicUpscaleFunction = defaultLibrary.makeFunction(
                    name: "bicubic_kernel"
                ),
                let nearestUpscaleFunction = defaultLibrary.makeFunction(
                    name: "nearest_kernel"
                )
            else {
                fatalError("Error: Could not load default Metal library.")
            }

            var pipelineState: MTLComputePipelineState!
            let samplerDescriptor = MTLSamplerDescriptor()

            switch method {
            case .bilinear:
                pipelineState = try! device.makeComputePipelineState(
                    function: bilinearUpscaleFunction
                )
                samplerDescriptor.magFilter = .linear
                samplerDescriptor.minFilter = .linear
                samplerDescriptor.sAddressMode = .clampToEdge
                samplerDescriptor.tAddressMode = .clampToEdge
            case .bicubic:
                pipelineState = try! device.makeComputePipelineState(
                    function: bicubicUpscaleFunction
                )
                // Trick that uses linear but combines to ultimately do bicubic
                samplerDescriptor.magFilter = .linear
                samplerDescriptor.minFilter = .linear
                samplerDescriptor.sAddressMode = .clampToEdge
                samplerDescriptor.tAddressMode = .clampToEdge
            case .nearest:
                pipelineState = try! device.makeComputePipelineState(
                    function: nearestUpscaleFunction
                )
                samplerDescriptor.magFilter = .nearest
                samplerDescriptor.minFilter = .nearest
                samplerDescriptor.sAddressMode = .clampToEdge
                samplerDescriptor.tAddressMode = .clampToEdge
            case .lanczos:
                // This is lazily done because I did not implement the Lanczos upscaler,
                // instead this is designed to test my kernels with Apple's premade
                // Lanczos upscaler which should outperform any of my upscalers.
                let lanczosScale = MPSImageLanczosScale(device: device)
                let lanczosCommandQueue = device.makeCommandQueue()!
                let lanczosCommandBuffer =
                    lanczosCommandQueue.makeCommandBuffer()!
                lanczosScale.encode(
                    commandBuffer: lanczosCommandBuffer,
                    sourceTexture: inputTexture,
                    destinationTexture: outputTexture
                )
                lanczosCommandBuffer.commit()
                lanczosCommandBuffer.waitUntilCompleted()
                
                // Get the work done by the GPU as a CGImage
                output = cgImage(from: outputTexture)!

                // Export the CGImage back to whatever file format was originally used
                writeImage(
                    image: output,
                    path: URL(
                        fileURLWithPath:
                            "\(desiredMethod ?? "bicubic")_scaled_\(scale)x_\(inputFile)"
                    ),
                    asType: imageData.1
                )
                
                return
            }

            let sampler = device.makeSamplerState(descriptor: samplerDescriptor)

            let commandQueue = device.makeCommandQueue()!
            let commandBuffer = commandQueue.makeCommandBuffer()!
            let commandEncoder = commandBuffer.makeComputeCommandEncoder()!

            commandEncoder.setComputePipelineState(pipelineState)
            commandEncoder.setTexture(inputTexture, index: 0)
            commandEncoder.setTexture(outputTexture, index: 1)
            commandEncoder.setSamplerState(sampler, index: 0)

            // Perform GPU work
            let threadsPerGroup = MTLSize(width: 16, height: 16, depth: 1)
            let threadsPerGrid = MTLSize(
                width: outputTexture.width,
                height: outputTexture.height,
                depth: 1
            )
            commandEncoder.dispatchThreadgroups(
                threadsPerGrid,
                threadsPerThreadgroup: threadsPerGroup
            )

            commandEncoder.endEncoding()
            commandBuffer.commit()
            commandBuffer.waitUntilCompleted()

            // Get the work done by the GPU as a CGImage
            output = cgImage(from: outputTexture)!

            // Export the CGImage back to whatever file format was originally used
            writeImage(
                image: output,
                path: URL(
                    fileURLWithPath:
                        "\(desiredMethod ?? "bicubic")_scaled_\(scale)x_\(inputFile)"
                ),
                asType: imageData.1
            )

        }

        // Helper function to convert MTLTexture in GPU back to a CGImage
        func cgImage(from texture: MTLTexture) -> CGImage? {
            let width = texture.width
            let height = texture.height
            let bytesPerRow = width * 4
            let byteCount = bytesPerRow * height

            var data = [UInt8](repeating: 0, count: byteCount)
            let region = MTLRegionMake2D(0, 0, width, height)

            // Copy pixels from GPU memory to CPU array
            texture.getBytes(
                &data,
                bytesPerRow: bytesPerRow,
                from: region,
                mipmapLevel: 0
            )

            let colorSpace = CGColorSpaceCreateDeviceRGB()
            let bitmapInfo = CGBitmapInfo(
                rawValue: CGImageAlphaInfo.premultipliedLast.rawValue
            )

            guard
                let provider = CGDataProvider(
                    data: NSData(bytes: &data, length: byteCount)
                )
            else { return nil }

            return CGImage(
                width: width,
                height: height,
                bitsPerComponent: 8,
                bitsPerPixel: 32,
                bytesPerRow: bytesPerRow,
                space: colorSpace,
                bitmapInfo: bitmapInfo,
                provider: provider,
                decode: nil,
                shouldInterpolate: false,
                intent: .defaultIntent
            )
        }

        // Load a CGImage into an MTLTexture
        func loadTexture(from cgImage: CGImage, device: MTLDevice) -> MTLTexture
        {
            let loader = MTKTextureLoader(device: device)

            let options: [MTKTextureLoader.Option: Any] = [
                .origin: MTKTextureLoader.Origin.topLeft,
                .SRGB: false,  // TODO: Support SRGB
            ]

            do {
                return try loader.newTexture(cgImage: cgImage, options: options)
            } catch {
                fatalError("Failed to create texture \(error)")
            }
        }
    }
}
