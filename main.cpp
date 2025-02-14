#include <slang-com-ptr.h>
#include <slang.h>

#ifdef HAS_SHADERC
#include <shaderc/shaderc.hpp>
#endif

#include <chrono>
#include <fstream>
#include <iostream>
#include <optional>
#include <stdio.h>
#include <stdlib.h>

class SlangCompilerHelper
{
public:
  bool init(bool enable_glsl)
  {
    SlangGlobalSessionDesc global_session_desc{.enableGLSL = enable_glsl};
    SlangResult            result = slang::createGlobalSession(&global_session_desc, m_globalSession.writeRef());
    if(SLANG_FAILED(result))
    {
      fprintf(stderr, "Slang compiler initialization failed with code %d, facility %d.\n",
              SLANG_GET_RESULT_CODE(result), SLANG_GET_RESULT_FACILITY(result));
      return false;
    }

    // Set up default options and target
    m_options = {{slang::CompilerOptionName::EmitSpirvDirectly, {slang::CompilerOptionValueKind::Int, 1}},        //
                 {slang::CompilerOptionName::VulkanUseEntryPointName, {slang::CompilerOptionValueKind::Int, 1}},  //
                 {slang::CompilerOptionName::Optimization, {slang::CompilerOptionValueKind::Int, 0}}};
    m_targets = {slang::TargetDesc{.format = SLANG_SPIRV, .profile = m_globalSession->findProfile("spirv_1_6")}};
    return true;
  }

  bool compile(const char* moduleName, const char* source)
  {
    // Create a session
    {
      slang::SessionDesc desc{.targets{m_targets.data()},
                              .targetCount{SlangInt(m_targets.size())},
                              .searchPaths     = m_slangSearchPaths.data(),
                              .searchPathCount = SlangInt(m_slangSearchPaths.size()),
                              .compilerOptionEntries{m_options.data()},
                              .compilerOptionEntryCount{uint32_t(m_options.size())}};
      m_globalSession->createSession(desc, m_session.writeRef());
    }

    m_spirv = nullptr;
    Slang::ComPtr<slang::IBlob> diagnostics;
    m_shaderModule = m_session->loadModuleFromSourceString(moduleName, nullptr, source, diagnostics.writeRef());
    if(diagnostics)
    {
      fprintf(stderr, "Diagnostics:\n%s\n", reinterpret_cast<const char*>(diagnostics->getBufferPointer()));
      return false;
    }

    SlangResult result = m_shaderModule->getTargetCode(0, m_spirv.writeRef());
    if(SLANG_FAILED(result))
    {
      fprintf(stderr, "Slang compilation failed with code %d, facility %d.\n", SLANG_GET_RESULT_CODE(result),
              SLANG_GET_RESULT_FACILITY(result));
      return false;
    }

    return true;
  }

  const void* get_spirv_data() const { return m_spirv->getBufferPointer(); }
  size_t      get_spirv_size() const { return m_spirv->getBufferSize(); }

  static const char* name() { return "slang"; }

private:
  Slang::ComPtr<slang::IGlobalSession>    m_globalSession;
  std::vector<slang::TargetDesc>          m_targets;
  std::vector<slang::CompilerOptionEntry> m_options;
  std::vector<const char*>                m_slangSearchPaths;
  std::vector<std::string>                m_searchPaths;
  Slang::ComPtr<slang::ISession>          m_session;
  Slang::ComPtr<slang::IModule>           m_shaderModule;
  Slang::ComPtr<ISlangBlob>               m_spirv;
};

#ifdef HAS_SHADERC
class ShadercGlslCompilerHelper : public shaderc::Compiler
{
public:
  bool init(bool /* enable_glsl */)
  {
    m_compilerOptions.SetTargetSpirv(shaderc_spirv_version::shaderc_spirv_version_1_6);
    m_compilerOptions.SetTargetEnvironment(shaderc_target_env_vulkan, shaderc_env_version_vulkan_1_4);
    m_compilerOptions.SetOptimizationLevel(shaderc_optimization_level_zero);
    return true;
  }

  bool compile(const char* moduleName, const char* source)
  {
    m_compileResult = CompileGlslToSpv(source, shaderc_shader_kind::shaderc_compute_shader, moduleName, m_compilerOptions);
    if(shaderc_compilation_status_success != m_compileResult.GetCompilationStatus())
    {
      fprintf(stderr, "Shaderc compilation failed: %s\n", m_compileResult.GetErrorMessage().c_str());
      return false;
    }

    return true;
  }

  const void* get_spirv_data() const { return m_compileResult.begin(); }
  size_t      get_spirv_size() const { return (m_compileResult.end() - m_compileResult.begin()) * sizeof(uint32_t); }

  static const char* name() { return "shaderc"; }

private:
  shaderc::CompileOptions       m_compilerOptions;
  shaderc::SpvCompilationResult m_compileResult;
};
#endif

// Prints how long it takes the compiler to compile a given file.
// Returns true if an operation failed.
template <class Compiler>
bool benchmark(const char* shader_source, const size_t num_repetitions, const bool enable_glsl)
{
  using timer = std::chrono::high_resolution_clock;

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

  // Benchmark
  {
    fprintf(stderr, "Compiling %zu times...\n", num_repetitions);
    const timer::time_point start = timer::now();
    for(size_t repetition = 1; repetition <= num_repetitions; repetition++)
    {
      // Power of 2 iteration printer
      if((repetition & (repetition - 1)) == 0)
      {
        fprintf(stderr, "Repetition %zu\n", repetition);
      }

      if(!compiler->compile("shader", shader_source))
      {
        return false;
      }
    }
    const timer::time_point                         end      = timer::now();
    const std::chrono::duration<double, std::milli> duration = (end - start);
    printf("Average compilation time: %f ms\n", duration.count() / static_cast<double>(num_repetitions));

    const void*  spirv_data = compiler->get_spirv_data();
    const size_t spirv_size = compiler->get_spirv_size();
    fprintf(stderr, "SPIR-V output is %zu bytes long.\n", spirv_size);
    std::ofstream(std::string(Compiler::name()) + ".spv", std::ios::binary).write(reinterpret_cast<const char*>(spirv_data), spirv_size);
  }

  return true;
}

// Loads a file from a path; returns empty on failure.
std::optional<std::string> load_file(const char* filename)
{
  try
  {
    std::ifstream file(filename, std::ios::ate);
    file.exceptions(std::ios::badbit);
    const std::streampos size_signed = file.tellg();
    if(size_signed < 0)
    {
      fprintf(stderr, "Could not load %s: size was negative.\n", filename);
      return {};
    }

    const size_t size = static_cast<size_t>(size_signed);
    std::string  result(size, '\0');
    file.seekg(0, std::ios::beg);
    file.read(result.data(), size_signed);
    fprintf(stderr, "Loaded %s; %zu bytes.\n", filename, size);
    return {result};  // Success!
  }
  catch(const std::exception& e)
  {
    fprintf(stderr, "Caught exception while trying to read %s: %s\n", filename, e.what());
  }
  return {};  // Only reached on exception
}

// Finds and loads a file, searching up at most 3 directories; returns empty
// on failure.
std::optional<std::string> find_file(const char* filename)
{
  std::optional<std::string> result;
  std::string                search_path = filename;
  for(size_t parents = 0; parents <= 3; parents++)
  {
    result = load_file(search_path.c_str());
    if(result.has_value())
    {
      return result;
    }
    search_path = "../" + search_path;
  }
  return result;
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
    else
    {
      filename = arg;
    }
  }

  // Find shader.slang; search up at most 3 directories.
  std::optional<std::string> shader_code = find_file(filename);
  if(!shader_code.has_value())
  {
    fprintf(stderr, "Could not load %s.\n", filename);
    return EXIT_FAILURE;
  }

  if(!test_shaderc)
  {
    if(!benchmark<SlangCompilerHelper>(shader_code.value().c_str(), num_repetitions, enable_glsl))
    {
      return EXIT_FAILURE;
    }
  }

#ifdef HAS_SHADERC
  if(test_shaderc)
  {
    if(!benchmark<ShadercGlslCompilerHelper>(shader_code.value().c_str(), num_repetitions, enable_glsl))
    {
      return EXIT_FAILURE;
    }
  }
#endif

  return EXIT_SUCCESS;
}
