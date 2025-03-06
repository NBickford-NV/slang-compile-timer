#pragma once
#ifdef HAS_DXC

// DirectXShaderCompiler compilation helper.
// Based off the example in https://github.com/microsoft/DirectXShaderCompiler/wiki/Using-dxc.exe-and-dxcompiler.dll#using-the-compiler-interface

// Turns off as many validation settings as possible.
// #define DXC_HELPER_NO_VALIDATION

#include "utilities.h"

#include <Windows.h>
#include <atlbase.h>
#include <atomic>
#include <cassert>
#include <unordered_map>

#include "dxc/dxcapi.h"

bool check_hresult(HRESULT hresult, const char* expression)
{
  if(FAILED(hresult))
  {
    fprintf(stderr, "%s failed with HRESULT %lx\n", expression, hresult);
    return false;
  }
  return true;
}
#define CHECK_HRESULT(expr)                                                                                            \
  {                                                                                                                    \
    HRESULT hresult = (expr);                                                                                          \
    if(!check_hresult(hresult, #expr))                                                                                 \
    {                                                                                                                  \
      return false;                                                                                                    \
    }                                                                                                                  \
  }

// A simple blob that owns its raw data.
class MyDxcBlob : public IDxcBlob
{
private:
  std::vector<char>     m_data;
  std::atomic<uint32_t> m_ref_count = 0;

  MyDxcBlob() = default;

  // Copies the input.
  MyDxcBlob(const void* data, size_t size)
  {
    m_data.resize(size);
    memcpy(m_data.data(), data, size);
  }

  virtual ~MyDxcBlob() { assert(m_ref_count == 0); }

public:
  // IUnknown implementation
  HRESULT QueryInterface(REFIID riid, LPVOID* ppvObj) override
  {
    // Validate and clear out parameter
    if(!ppvObj)
    {
      return E_INVALIDARG;
    }
    *ppvObj = nullptr;

    if(IID_IUnknown == riid || __uuidof(IDxcBlob) == riid)
    {
      *ppvObj = this;
      AddRef();
      return NOERROR;
    }
    return E_NOINTERFACE;
  }

  ULONG AddRef() override { return ++m_ref_count; }

  ULONG Release() override
  {
    const ULONG ref_count = --m_ref_count;
    if(0 == ref_count)
    {
      delete this;
    }
    return ref_count;
  }

  // IDxcBlob implementation
  virtual LPVOID STDMETHODCALLTYPE GetBufferPointer(void) override { return m_data.data(); }

  virtual SIZE_T STDMETHODCALLTYPE GetBufferSize(void) override { return m_data.size(); }

  // Copies the given data into a new blob.
  static CComPtr<IDxcBlob> create(const void* inData, size_t size)
  {
    return CComPtr<IDxcBlob>(new MyDxcBlob(inData, size));
  }
};

// Include handler that caches files in memory.
struct MyDXIncluder : public IDxcIncludeHandler
{
private:
  std::atomic<ULONG> m_ref_count = 0;
  // Maps [wide string used by DXC, including search path] -> [file content].
  //  and [file that doesn't exist] -> [nullptr]
  std::unordered_map<std::wstring, CComPtr<IDxcBlob>> m_file_cache;

  fs::path m_include_path;

public:
  MyDXIncluder() = default;
  virtual ~MyDXIncluder() { assert(m_ref_count == 0); }

  // IUnknown implementation
  HRESULT QueryInterface(REFIID riid, LPVOID* ppvObj) override
  {
    // Validate and clear out parameter
    if(!ppvObj)
    {
      return E_INVALIDARG;
    }
    *ppvObj = nullptr;

    if(IID_IUnknown == riid || __uuidof(IDxcIncludeHandler) == riid)
    {
      // Increment the reference count and return the pointer.
      *ppvObj = this;
      AddRef();
      return NOERROR;
    }
    return E_NOINTERFACE;
  }

  ULONG AddRef() override { return ++m_ref_count; }

  ULONG Release() override
  {
    const ULONG ref_count = --m_ref_count;
    if(0 == ref_count)
    {
      delete this;
    }
    return ref_count;
  }

  // IDxcIncludeHandler implementation
  HRESULT STDMETHODCALLTYPE LoadSource(_In_z_ LPCWSTR pFilename, _COM_Outptr_result_maybenull_ IDxcBlob** ppIncludeSource) override
  {
    // Check for nullptr
    if(!ppIncludeSource)
    {
      return E_INVALIDARG;
    }
    *ppIncludeSource = nullptr;

    // Construct the search path
    const std::filesystem::path full_path = fs::absolute(m_include_path / fs::path(pFilename));
    const std::wstring          filename  = full_path.wstring();

    // Is this file already in the cache?
    const auto& it = m_file_cache.find(filename);
    if(it != m_file_cache.end())
    {
      IDxcBlob* blob = it->second;
      if(nullptr == blob)
      {
        // We tried to find this before but failed.
        return MAKE_HRESULT(SEVERITY_ERROR, FACILITY_WIN32, ERROR_FILE_NOT_FOUND);
      }
      // Add a reference to it since we're returning it.
      // It should have a reference count of at least 2: one in
      // m_file_cache, and the other in the pointer we're returning.
      blob->AddRef();
      assert(blob->AddRef() >= 3 && blob->Release());
      *ppIncludeSource = blob;
      return NOERROR;
    }

    // Otherwise, try to load it.
    std::optional<std::string> contents = load_file(filename.c_str());
    if(!contents.has_value())
    {
      // Cache that we couldn't find it.
      m_file_cache[filename] = nullptr;
      return MAKE_HRESULT(SEVERITY_ERROR, FACILITY_WIN32, ERROR_FILE_NOT_FOUND);
    }

    CComPtr<IDxcBlob> blob = MyDxcBlob::create(contents.value().data(), contents.value().size());
    // Cache it.
    m_file_cache[filename] = blob;
    // blob should have a reference count of 2;
    // one reference is in m_file_cache, and the other reference is the pointer
    // we're returning to the caller.
    assert((*blob).AddRef() == 3 && (*blob).Release());
    *ppIncludeSource = blob.Detach();
    return NOERROR;
  }

  // Other functions
  void set_include_path(const fs::path& include_path) { m_include_path = include_path; }
};

class DXCompilerHelper
{
private:
  // CComPtr<IDxcUtils> m_utils;
  CComPtr<IDxcCompiler3>    m_compiler;
  std::vector<std::wstring> m_arguments;
  CComPtr<IDxcBlob>         m_compiled_shader;
  CComPtr<MyDXIncluder>     m_includer;

public:
  bool init(bool /* enable_glsl */)
  {
    // CHECK_HRESULT(DxcCreateInstance(CLSID_DxcUtils, IID_PPV_ARGS(&m_utils)));
    CHECK_HRESULT(DxcCreateInstance(CLSID_DxcCompiler, IID_PPV_ARGS(&m_compiler)));

    m_includer = CComPtr<MyDXIncluder>(new MyDXIncluder());

    m_arguments = {
        L"-fspv-target-env=vulkan1.3",  // Vulkan target
        L"-T",
        L"cs_6_8",  // HLSL profile
        L"-spirv",  // Output SPIR-V
        L"-Od",     // No optimization
#ifdef DXC_HELPER_NO_VALIDATION
        L"-Vd",  // No validation
#endif
    };

    return true;
  }

  bool compile(const char* mainShaderPath, const char* source)
  {
    m_includer->set_include_path(std::filesystem::path(mainShaderPath).parent_path());

    DxcBuffer dxc_source{.Ptr = source, .Size = strlen(source), .Encoding = DXC_CP_UTF8};

    // Convert arguments in a vector of pointers.
    std::vector<const wchar_t*> m_argumentPointers(m_arguments.size());
    for(size_t i = 0; i < m_arguments.size(); i++)
    {
      m_argumentPointers[i] = m_arguments[i].c_str();
    }

    CComPtr<IDxcResult> results;
    check_hresult(m_compiler->Compile(&dxc_source,  // Source buffer
                                      m_argumentPointers.data(), static_cast<UINT32>(m_argumentPointers.size()),  // Arguments
                                      m_includer,  // Include handler
                                      IID_PPV_ARGS(&results)),
                  "m_compiler->Compile(...)");

    if(!results)
    {
      printf("m_compiler->Compile returned a null pointer!\n");
      return false;
    }

    // Print warnings and errors if present
    CComPtr<IDxcBlobUtf8> diagnostics;
    CHECK_HRESULT(results->GetOutput(DXC_OUT_ERRORS, IID_PPV_ARGS(&diagnostics), nullptr));
    if(diagnostics != nullptr && diagnostics->GetStringLength() != 0)
    {
      fprintf(stderr, "Shader compilation diagnostics: %s\n", diagnostics->GetStringPointer());
    }

    HRESULT compilation_hresult{};
    CHECK_HRESULT(results->GetStatus(&compilation_hresult));
    CHECK_HRESULT(compilation_hresult);

    // Get the shader binary.
    CComPtr<IDxcBlob> compiled_shader;
    CHECK_HRESULT(results->GetOutput(DXC_OUT_OBJECT, IID_PPV_ARGS(&compiled_shader), nullptr));
    m_compiled_shader = compiled_shader;
    return true;
  }

  const void* get_spirv_data() const { return m_compiled_shader->GetBufferPointer(); }
  size_t      get_spirv_size() const { return m_compiled_shader->GetBufferSize(); }

  static const char* name() { return "dxc"; }
};

#endif  // #ifdef HAS_DXC
