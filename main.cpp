#ifdef HAS_DXC
#include "compiler_dxc.h"
#endif
#ifdef HAS_SHADERC
#include "compiler_shaderc.h"
#endif
#include "compiler_slang.h"
#include "utilities.h"

#include <fstream>
#include <memory>
#include <optional>
#include <stddef.h>
#include <string.h>

//-----------------------------------------------------------------------------
// Benchmark

// Prints how long it takes the compiler to compile a given file.
// Returns true if an operation failed.
template <class Compiler>
bool benchmark(const char* shader_path, const char* shader_source, const size_t num_repetitions, const bool enable_glsl)
{
  std::unique_ptr<Compiler> compiler;

  // Initialization
  {
    const timer::time_point start = timer::now();
    compiler                      = std::make_unique<Compiler>();
    if(!compiler->init(enable_glsl))
    {
      return false;
    }
    const timer::time_point                         end      = timer::now();
    const std::chrono::duration<double, std::milli> duration = (end - start);
    printf("Compiler initialization time: %f ms\n", duration.count());
  }

  // First compilation to warm up caches
  {
    const timer::time_point start = timer::now();
    if(!compiler->compile(shader_path, shader_source))
    {
      return false;
    }
    const timer::time_point                         end      = timer::now();
    const std::chrono::duration<double, std::milli> duration = (end - start);
    printf("First compilation (building caches): %f ms\n", duration.count());

    const void*  spirv_data = compiler->get_spirv_data();
    const size_t spirv_size = compiler->get_spirv_size();
    fprintf(stderr, "SPIR-V output is %zu bytes long.\n", spirv_size);
    std::ofstream(std::string(Compiler::name()) + ".spv", std::ios::binary).write(reinterpret_cast<const char*>(spirv_data), spirv_size);
  }

  // Benchmark
  {
    fprintf(stderr, "Compiling %zu times...\n", num_repetitions);
    const timer::time_point start = timer::now();
    for(size_t repetition = 1; repetition <= num_repetitions; repetition++)
    {
#ifdef VERBOSE
      // Power of 2 iteration printer
      if((repetition & (repetition - 1)) == 0)
      {
        fprintf(stderr, "Repetition %zu\n", repetition);
      }
#endif

      if(!compiler->compile(shader_path, shader_source))
      {
        return false;
      }
    }
    const timer::time_point                         end      = timer::now();
    const std::chrono::duration<double, std::milli> duration = (end - start);
    printf("Average compilation time: %f ms\n", duration.count() / static_cast<double>(num_repetitions));
  }

  return true;
}

void print_help()
{
  printf(
      "slang-compile-timer: Benchmarks how long Slang takes to compile a shader.\n"
      "Usage: slang-compile-timer [options] filename\n"
      "Options\n"
      "  -h: Print this text and exit.\n"
      "  -r: Number of repetitions (default: 128)\n"
      "  --enable-glsl: Sets SlangGlobalSessionDesc::enableGLSL to true.\n"
#ifdef HAS_SHADERC
      "  --shaderc: Benchmark shaderc instead of Slang.\n"
#endif
  );
}

int main(int argc, char* argv[])
{
  // Parse arguments
  size_t      num_repetitions = 128;
  bool        enable_glsl     = false;
  bool        test_shaderc    = false;
  bool test_dxc = false;
  const char* filename        = "shader.slang";
  for(int argi = 1; argi < argc; argi++)
  {
    const char* arg = argv[argi];
    if(strcmp("-h", arg) == 0)
    {
      print_help();
      return EXIT_SUCCESS;
    }
    else if(strcmp("-r", arg) == 0)
    {
      argi++;
      if(argi == argc)
      {
        fprintf(stderr, "-r must be followed by the number of repetitions.\n");
        return EXIT_FAILURE;
      }
      num_repetitions = strtoull(argv[argi], nullptr, 0);
    }
    else if(strcmp("--enable-glsl", arg) == 0)
    {
      enable_glsl = true;
    }
#ifdef HAS_SHADERC
    else if(strcmp("--shaderc", arg) == 0)
    {
      test_shaderc = true;
    }
#endif
#ifdef HAS_DXC
    else if (strcmp("--dxc", arg) == 0)
    {
        test_dxc = true;
    }
#endif
    else
    {
      filename = arg;
    }
  }

  // Find the shader; search up at most 3 directories.
  std::string                shader_path;
  std::optional<std::string> shader_code = find_file(filename, &shader_path);
  if(!shader_code.has_value())
  {
    fprintf(stderr, "Could not load %s.\n", filename);
    return EXIT_FAILURE;
  }

  if(!test_shaderc && !test_dxc)
  {
    if(!benchmark<SlangCompilerHelper>(shader_path.c_str(), shader_code.value().c_str(), num_repetitions, enable_glsl))
    {
      return EXIT_FAILURE;
    }
  }

#ifdef HAS_SHADERC
  if(test_shaderc)
  {
    if(!benchmark<ShadercGlslCompilerHelper>(shader_path.c_str(), shader_code.value().c_str(), num_repetitions, enable_glsl))
    {
      return EXIT_FAILURE;
    }
  }
#endif

#ifdef HAS_DXC
  if (test_dxc)
  {
      if (!benchmark<DXCompilerHelper>(shader_path.c_str(), shader_code.value().c_str(), num_repetitions, enable_glsl))
      {
          return EXIT_FAILURE;
      }
  }
#endif

  return EXIT_SUCCESS;
}
