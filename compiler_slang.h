#pragma once

// Compiler helper for Slang. Compiles a shader in memory to SPIR-V; optionally,
// tries to cache modules as much as it can.

// The following options can be used to configure the helper:

// If defined, makes the Slang compiler helper use a module cache.
//
// Specifically, the first time the Slang compiler tries to load a Slang module,
// the compiler helper will load the corresponding .slang file, start another
// session to compile it, and then serialize the result so that it doesn't have
// to recompile the module the next time it's loaded.
//
// The approach I'm using for this is slightly hacky, and I'm not sure if this
// is how it's supposed to be done. Since we don't know what modules a .slang
// file uses until it's loaded (we could use a regex or have a human look at
// the file, of course), we implement Slang's IFileSystem to intercept
// calls by Slang to load .slang-module files.
#define USE_MODULE_CACHE

// If defined, makes the Slang compiler helper implement IFilesystemEXT instead
// of only IFilesystem. This makes it so that Slang doesn't try to wrap it in
// its own file cache, but also means that the implementation's more complex.
// This might not be statistically significant; p = 0.14 across 4 runs
// with and without it.
// #define IMPLEMENT_FILESYSTEMEXT

// Turns off as many validation settings as possible.
#define SLANG_HELPER_NO_VALIDATION

#include "utilities.h"

#include <slang-com-helper.h>
#include <slang-com-ptr.h>
#include <slang.h>

#include <cassert>
#include <filesystem>
#include <stddef.h>
#include <stdint.h>
#include <stdio.h>
#include <unordered_map>
#include <vector>

#ifdef USE_MODULE_CACHE
// A simple blob that owns its raw data.
// Based on slang-blob.h.
class MyRawBlob : public ISlangBlob
{
private:
  std::vector<char> m_data;
  uint32_t          m_refCount = 0;

  MyRawBlob() = default;

  // Copies the input.
  MyRawBlob(const void* data, size_t size)
  {
    m_data.resize(size);
    memcpy(m_data.data(), data, size);
  }

  virtual ~MyRawBlob()
  {
    // printf("deleting a raw blob at %p\n", this);
    assert(m_refCount == 0);
  }

public:
  SLANG_REF_OBJECT_IUNKNOWN_ALL

  uint32_t addReference() { return ++m_refCount; }
  uint32_t releaseReference()
  {
    assert(m_refCount != 0);
    if(--m_refCount == 0)
    {
      delete this;
      return 0;
    }
    return m_refCount;
  }

  ISlangUnknown* getInterface(const Slang::Guid& guid)
  {
    if(guid == ISlangUnknown::getTypeGuid() || guid == ISlangBlob::getTypeGuid())
    {
      return static_cast<ISlangBlob*>(this);
    }
    return nullptr;
  }

  virtual SLANG_NO_THROW void const* SLANG_MCALL getBufferPointer() override { return m_data.data(); };
  virtual SLANG_NO_THROW size_t SLANG_MCALL      getBufferSize() override { return m_data.size(); }

  // Copies the given data into a new blob.
  static Slang::ComPtr<ISlangBlob> create(const void* inData, size_t size)
  {
    return Slang::ComPtr<ISlangBlob>(new MyRawBlob(inData, size));
  }
};
#endif

class SlangCompilerHelper
#ifdef USE_MODULE_CACHE
#ifdef IMPLEMENT_FILESYSTEMEXT
    : public ISlangFileSystemExt
#else
    : public ISlangFileSystem
#endif
#endif
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
    m_options = {
        {slang::CompilerOptionName::EmitSpirvDirectly, {slang::CompilerOptionValueKind::Int, 1}},         //
        {slang::CompilerOptionName::VulkanUseEntryPointName, {slang::CompilerOptionValueKind::Int, 1}},   //
        {slang::CompilerOptionName::Optimization, {slang::CompilerOptionValueKind::Int, 0}},              //
        {slang::CompilerOptionName::MinimumSlangOptimization, {slang::CompilerOptionValueKind::Int, 1}},  //
        {slang::CompilerOptionName::Capability,
         {slang::CompilerOptionValueKind::Int, m_globalSession->findCapability("spvRayQueryKHR")}},
#ifdef SLANG_HELPER_NO_VALIDATION
        {slang::CompilerOptionName::SkipSPIRVValidation, {slang::CompilerOptionValueKind::Int, 1}},             //
        {slang::CompilerOptionName::DisableNonEssentialValidations, {slang::CompilerOptionValueKind::Int, 1}},  //
        {slang::CompilerOptionName::ValidateIr, {slang::CompilerOptionValueKind::Int, 0}},         // (default value)
        {slang::CompilerOptionName::ValidateUniformity, {slang::CompilerOptionValueKind::Int, 0}}  // (default value)
#endif
    };
    m_targets = {slang::TargetDesc{.format = SLANG_SPIRV, .profile = m_globalSession->findProfile("spirv_1_6")}};

    return true;
  }

private:
  // Creates a session.
  Slang::ComPtr<slang::ISession> makeSession()
  {
    slang::SessionDesc desc{.targets{m_targets.data()},
                            .targetCount{SlangInt(m_targets.size())},
                            .compilerOptionEntries{m_options.data()},
                            .compilerOptionEntryCount{uint32_t(m_options.size())}};
#ifdef USE_MODULE_CACHE
    desc.fileSystem = this;
#endif
    desc.searchPaths     = &m_currentSearchPathCString;
    desc.searchPathCount = 1;

    Slang::ComPtr<slang::ISession> session;
    m_globalSession->createSession(desc, session.writeRef());
    return session;
  }

  // Compiles a string to a module.
  Slang::ComPtr<slang::IModule> compileModule(slang::ISession* session, const char* shaderPath, const char* source)
  {
    Slang::ComPtr<slang::IBlob>   diagnostics;
    Slang::ComPtr<slang::IModule> shader_module;
    shader_module = session->loadModuleFromSourceString(shaderPath, nullptr, source, diagnostics.writeRef());
    if(diagnostics)
    {
      fprintf(stderr, "Diagnostics:\n%s\n", reinterpret_cast<const char*>(diagnostics->getBufferPointer()));
      return nullptr;
    }

    return shader_module;
  }

public:
  bool compile(const char* mainShaderPath, const char* source)
  {
    m_currentSearchPath        = fs::path(mainShaderPath).parent_path().string();
    m_currentSearchPathCString = m_currentSearchPath.c_str();

    Slang::ComPtr<slang::ISession> session       = makeSession();
    Slang::ComPtr<slang::IModule>  shader_module = compileModule(session, mainShaderPath, source);
    if(!shader_module)
    {
      return false;
    }

    m_spirv            = nullptr;
    SlangResult result = shader_module->getTargetCode(0, m_spirv.writeRef());
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

#ifdef USE_MODULE_CACHE
  // Module cache implementation
  // We use this to intercept Slang `import` calls and return pre-compiled
  // modules.
  SLANG_REF_OBJECT_IUNKNOWN_ALL

  uint32_t addReference() { return ++m_fakeReferenceCount; }
  uint32_t releaseReference() { return --m_fakeReferenceCount; }

  ISlangUnknown* getInterface(const Slang::Guid& guid)
  {
#ifdef IMPLEMENT_FILESYSTEMEXT
    if(ISlangFileSystemExt::getTypeGuid() == guid)
    {
      return static_cast<ISlangFileSystemExt*>(this);
    }
#endif
    if(ISlangUnknown::getTypeGuid() == guid || ISlangFileSystem::getTypeGuid() == guid)
    {
      return static_cast<ISlangFileSystem*>(this);
    }
    return nullptr;
  }

  void* castAs(const Slang::Guid& guid)
  {
    if(auto ptr = getInterface(guid))
    {
      return ptr;
    }
    return nullptr;
  }

#ifdef IMPLEMENT_FILESYSTEMEXT
  virtual SLANG_NO_THROW SlangResult SLANG_MCALL getFileUniqueIdentity(const char* path, ISlangBlob** outUniqueIdentity) override
  {
    // Since we assume files are constant over the lifetime of this application,
    // we can just return the path.
    // It seems like we don't need to call std::filesystem::absolute() here.
    // Also, a full implementation would catch exceptions for all of these
    // functions.
    *outUniqueIdentity = MyRawBlob::create(path, strlen(path)).detach();
    return SLANG_OK;
  }

  virtual SLANG_NO_THROW SlangResult SLANG_MCALL calcCombinedPath(SlangPathType fromPathType,
                                                                  const char*   fromPath,
                                                                  const char*   path,
                                                                  ISlangBlob**  pathOut) override
  {
    // NOTE: A full implementation would need to specify UTF-8 here
    fs::path parent = fs::path(fromPath);
    if(fromPathType == SLANG_PATH_TYPE_FILE)
    {
      parent = parent.parent_path();
    }
    const std::string path_string = (parent / fs::path(path)).string();
    // And this would ideally be a move
    *pathOut = MyRawBlob::create(path_string.c_str(), path_string.size()).detach();
    return SLANG_OK;
  }

  virtual SLANG_NO_THROW SlangResult SLANG_MCALL getPathType(const char* path, SlangPathType* pathTypeOut) override
  {
    // For the current hack version, reply "yep, that's a file" when querying
    // all paths. Ideally, we'd need to do the same .slang-module -> .slang
    // remapping here.
    *pathTypeOut = SLANG_PATH_TYPE_FILE;
    return SLANG_OK;
    /*
    const fs::file_status status = fs::status(fs::path(path));
    switch(status.type())
    {
        case fs::file_type::regular:
        *pathTypeOut = SLANG_PATH_TYPE_FILE;
        return SLANG_OK;
        case fs::file_type::directory:
        *pathTypeOut = SLANG_PATH_TYPE_DIRECTORY;
        return SLANG_OK;
        default:
        return SLANG_E_NOT_FOUND;
    }
    */
  }

  virtual SLANG_NO_THROW SlangResult SLANG_MCALL getPath(PathKind kind, const char* path, ISlangBlob** outPath) override
  {
    assert(!"getPath() is not implemented");
    return SLANG_E_NOT_IMPLEMENTED;
  }

  virtual SLANG_NO_THROW void SLANG_MCALL clearCache() override { assert(!"clearCache() is not implemented"); }

  virtual SLANG_NO_THROW SlangResult SLANG_MCALL enumeratePathContents(const char*                path,
                                                                       FileSystemContentsCallBack callback,
                                                                       void*                      userData) override
  {
    assert(!"enumeratePathContents() is not implemented");
    return SLANG_E_NOT_IMPLEMENTED;
  }

  virtual SLANG_NO_THROW OSPathKind SLANG_MCALL getOSPathKind()
  {
    return OSPathKind::Direct;  // I think
  }
#endif

  virtual SLANG_NO_THROW SlangResult SLANG_MCALL loadFile(char const* path, ISlangBlob** outBlob) override
  {
    // Is this file already in our cache?
    const std::string path_string = (fs::path(m_currentSearchPath) / fs::path(path)).string();
    const auto&       it          = m_moduleCache.find(path_string);
    if(it != m_moduleCache.end())
    {
      ISlangBlob* blob = it->second.get();
      // If `blob` is nullptr, then we've tried to load this file before and
      // failed.
      if(nullptr == blob)
      {
        return SLANG_E_NOT_FOUND;
      }
      // This is a file we've successfully loaded before.
      *outBlob = blob;
      // The blob should have a reference count of at least 2; one in
      // m_moduleCache, and the other in the pointer we're returning.
      // It can have a larger number if we're not implementing IFilesystemEXT
      // and Slang has its own file cache.
      blob->addRef();
      assert(blob->addRef() >= 3 && blob->release());
      return SLANG_OK;
    }

    // Otherwise, is it a .slang-module file?
    if(path_string.ends_with("-module"))
    {
      const std::string          original_path = path_string.substr(0, path_string.size() - 7);
      std::optional<std::string> contents      = load_file(original_path.c_str());
      if(!contents.has_value())
      {
        // This file doesn't exist.
        // Cache that information:
        m_moduleCache[path_string] = nullptr;
        return SLANG_E_NOT_FOUND;
      }

      // Compile it to a module:
      Slang::ComPtr<slang::ISession> session;
      Slang::ComPtr<slang::IModule>  shader_module;
      {
        const timer::time_point start = timer::now();

        session       = makeSession();
        shader_module = compileModule(session, original_path.c_str(), contents.value().c_str());
        if(!shader_module)
        {
          return SLANG_FAIL;
        }

        const timer::time_point                         end      = timer::now();
        const std::chrono::duration<double, std::milli> duration = (end - start);
        printf("Module compilation time: %f ms\n", duration.count());
      }

      // Serialize it to something we can provide to another session:
      ISlangBlob* serialized_module = nullptr;
      {
        const timer::time_point start = timer::now();

        SlangResult result = shader_module->serialize(&serialized_module);
        if(SLANG_FAILED(result))
        {
          fprintf(stderr, "Slang module serialization failed with code %d, facility %d.\n",
                  SLANG_GET_RESULT_CODE(result), SLANG_GET_RESULT_FACILITY(result));
          return SLANG_FAIL;
        }

        const timer::time_point                         end      = timer::now();
        const std::chrono::duration<double, std::milli> duration = (end - start);
        printf("Module serialization time: %f ms\n", duration.count());
        printf("Serialized module size: %zu bytes\n", serialized_module->getBufferSize());
      }

      // Cache it.
      m_moduleCache[path_string] = Slang::ComPtr<ISlangBlob>(serialized_module);
      // serialized_module should have a reference count of 2;
      // one reference is in m_moduleCache, and the other reference is the
      // pointer we're returning to the caller.
      assert(serialized_module->addRef() == 3 && serialized_module->release());
      *outBlob = serialized_module;
      return SLANG_OK;
    }

    // Otherwise, it's a regular file. Load it and add it to our cache.
    // Note: This path doesn't occur during this benchmark.
    {
      std::optional<std::string> contents = load_file(path);
      if(!contents.has_value())
      {
        // This file doesn't exist.
        // Cache that information:
        m_moduleCache[path_string] = nullptr;
        return SLANG_E_NOT_FOUND;
      }

      const auto& blob = m_moduleCache[path_string] = MyRawBlob::create(contents.value().data(), contents.value().size());
      // The blob should have a reference count of 2; one in m_moduleCache,
      // and the other in the pointer we're returning.
      blob->addRef();
      assert(blob->addRef() == 3 && blob->release());
      *outBlob = blob.get();
      return SLANG_OK;
    }
  }
#endif

private:
  Slang::ComPtr<slang::IGlobalSession>    m_globalSession;
  std::vector<slang::TargetDesc>          m_targets;
  std::vector<slang::CompilerOptionEntry> m_options;
  std::string                             m_currentSearchPath;
  const char*                             m_currentSearchPathCString;
  Slang::ComPtr<ISlangBlob>               m_spirv;

#ifdef USE_MODULE_CACHE
  // Fake reference count used so that we can implement IUnknown.
  uint32_t m_fakeReferenceCount = 1;
  // Map of the following:
  // [include path with .slang-module extension] -> [.slang precompiled to a .slang-module blob]
  // [other file type] -> [file contents]
  // [file that doesn't exist] -> nullptr
  std::unordered_map<std::string, Slang::ComPtr<ISlangBlob>> m_moduleCache;
#endif
};
