# A simple Slang shader compilation profiler

slang-compile-timer looks for a file and measures how long it takes to compile
it using Slang or shaderc.
This is intended to test hot-reload performance.
If built in RelWithDbgInfo mode, it can be profiled to find compilation hotspots.

Built to reproduce an issue; not a full project. Currently only tested on Windows.

To build:

```
git clone --recursive https://github.com/NBickford-NV/slang-compile-timer.git
cd slang-compile-timer
mkdir cmake_build
cd cmake_build
cmake ..
cmake --build . --parallel
```

Then to measure how long Slang takes to compile shader.slang, run:

```
slang-compile-timer examples/simple/shader.slang
```

To measure how long shaderc takes to compile shader.comp.glsl (if CMake
found shaderc_shared), run:

```
slang-compile-timer --shaderc examples/simple/shader.comp.glsl
```

And finally, for DirectXShaderCompiler (if CMake found dxc), run:

```
slang-compile-timer --dxc examples/simple/shader.hlsl
```

For the path tracing benchmark (simulating a compute shader of the size we would
typically see in a professional app), run

```
slang-compile-timer examples/pathtrace-slang/gltf_pathtrace.slang
slang-compile-timer --shaderc examples/pathtrace-glsl/gltf_pathtrace.comp.glsl
slang-compile-timer --dxc examples/pathtrace-hlsl/gltf_pathtrace.hlsl
```

These were modified from https://github.com/nvpro-samples/vk_mini_samples/tree/main/samples/gltf_raytrace.

By default, the Slang compiler helper will cache modules and avoid validation
for optimal performance. These settings can be changed using the preprocessor
macros in `compiler_slang.h`.
