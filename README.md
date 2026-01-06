# Metal Image Upscaler

A macOS command line utility for upscaling images with various algorithms. Written in Swift and Metal Shading Language (MSL).

<div align="center">
<img src="https://raw.githubusercontent.com/zacheri04/MetalImageUpscaler/refs/heads/main/demo.png" alt="Logo" width="512">
</div>

### Upscaling Interpolation Algorithms Included:

- Nearest Neighbor
- Bilinear
- Bicubic
- Lanczos

---

## Installation Guide

Release can be found [here](https://github.com/zacheri04/MetalImageUpscaler/releases).

Drag the `MetalImageUpscaler` binary and the `.metallib` file into `/usr/local/bin`.

---

## Usage

Once the binary is in your `/usr/local/bin` folder, you can run it from your Terminal of choice.

```bash
$ MetalImageUpscaler
```

| Parameter                     | Description                                                                          |
| ----------------------------- | ------------------------------------------------------------------------------------ |
| -i, --input-file <input-file> | Input file name.                                                                     |
| -s, --scale <scale>           | Desired output scale. Must be an integer                                             |
| -d, --method                  | Algorithm to use. Valid options are 'nearest', 'bilinear', 'bicubic', and 'lanczos'. |
| -h, --help                    | Show help information.                                                               |

### Example Usage

This example scales `flowers.jpeg` by a 3x using the bilinear upscaling algorithm.

```bash
$ MetalImageUpscaler -i flowers.jpeg -s 3 -d bilinear
```

The program defaults to bicubic upscaling if none is specified, as follows:

```bash
$ MetalImageUpscaler -i flowers.jpeg -s 3
```

---

## Dislaimer & License

The Lanczos scaler was not written by me, instead it is [Apple's MPSImageLanczosScale](https://developer.apple.com/documentation/metalperformanceshaders/mpsimagelanczosscale) class included in their [Metal Performance Shaders framework](https://developer.apple.com/documentation/metalperformanceshaders). It is included to evaluate performance between the various algorithms.

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.
