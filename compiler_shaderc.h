#pragma once
#ifdef HAS_SHADERC

// ShaderC compilation helper.

#include "utilities.h"

#include <shaderc/shaderc.hpp>

#include <optional>
#include <stddef.h>
#include <string>
#include <unordered_map>

// This implements the ShaderC includer interface.
// ShaderC can't cache compilation results. But we can at least store files in
// memory, so that we don't have to read them every time. This makes the
// benchmark less dependent on disk access speed.
class GlslIncluder : public shaderc::CompileOptions::IncluderInterface
{
private:
  std::unordered_map<std::string, std::string> m_fileCache;

public:
  GlslIncluder() {}

  // Subtype of shaderc_include_result that holds the include data we found.
  struct IncludeResult : public shaderc_include_result
  {
    IncludeResult(const std::string& content, const std::string& filenameFound)
        : m_filenameFound(filenameFound)
        , m_content(content)
    {
      this->source_name        = m_filenameFound.c_str();
      this->source_name_length = m_filenameFound.size();
      this->content            = m_content.c_str();
      this->content_length     = m_content.size();
      this->user_data          = nullptr;
    }

    const std::string m_filenameFound;
    const std::string m_content;
  };

  void ReleaseInclude(shaderc_include_result* data) override { delete static_cast<IncludeResult*>(data); };

  shaderc_include_result* GetInclude(const char* requested_source, shaderc_include_type type, const char* requesting_source, size_t include_depth) override
  {
    // For this simple benchmark, we only support relative includes -- i.e.
    // we don't look at `type`.
    const fs::path    search_path     = fs::absolute(fs::path(requesting_source).parent_path() / requested_source);
    const std::string search_path_str = search_path.string();

    const auto& find_result = m_fileCache.find(search_path_str);
    if(find_result != m_fileCache.end())
    {
      return new IncludeResult(find_result->second, search_path_str);
    }

    std::optional<std::string> src_code = load_file(search_path_str.c_str());
    if(!src_code.has_value())
    {
      printf("Could not find include for %s relative to %s!\n", requested_source, requesting_source);
      exit(EXIT_FAILURE);
    }

    m_fileCache[search_path_str] = src_code.value();
    return new IncludeResult(src_code.value(), search_path_str);
  }
};

class ShadercGlslCompilerHelper : public shaderc::Compiler
{
public:
  bool init(bool /* enable_glsl */)
  {
    m_compilerOptions.SetTargetSpirv(shaderc_spirv_version::shaderc_spirv_version_1_6);
    m_compilerOptions.SetTargetEnvironment(shaderc_target_env_vulkan, shaderc_env_version_vulkan_1_4);
    m_compilerOptions.SetOptimizationLevel(shaderc_optimization_level_zero);
    m_compilerOptions.SetIncluder(std::make_unique<GlslIncluder>());
    return true;
  }

  bool compile(const char* mainShaderPath, const char* source)
  {
    m_compileResult = CompileGlslToSpv(source, shaderc_shader_kind::shaderc_compute_shader, mainShaderPath, m_compilerOptions);
    if(shaderc_compilation_status_success != m_compileResult.GetCompilationStatus())
    {
      const std::string message = m_compileResult.GetErrorMessage();
      fprintf(stderr, "Shaderc compilation failed: %s\n", message.c_str());
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

#endif  // HAS_SHADERC