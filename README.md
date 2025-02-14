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
slang-compile-timer shader.slang
```

And to measure how long shaderc takes to compile shader.comp.glsl (if CMake
found shaderc_shared), run:

```
slang-compile-timer --shaderc shader.comp.glsl
```
