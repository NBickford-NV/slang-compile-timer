cmake_minimum_required(VERSION 3.21...3.31)
project(slang-compile-timer LANGUAGES CXX)

if(MSVC)
  # Enable parallel builds by default on MSVC
  string(APPEND CMAKE_C_FLAGS " /MP")
  string(APPEND CMAKE_CXX_FLAGS " /MP")
endif()

# Slang compiler
add_subdirectory(slang)

# Test app
add_executable(${PROJECT_NAME}
               main.cpp
               compiler_dxc.h
               compiler_shaderc.h
               compiler_slang.h
               utilities.h)
set_target_properties(${PROJECT_NAME} PROPERTIES CXX_STANDARD 20)
target_link_libraries(${PROJECT_NAME} PUBLIC slang)

# Optional shader compilers from the Vulkan SDK.
find_package(Vulkan)
if(Vulkan_LIBRARY)
  get_filename_component(_Vulkan_LIB_DIR ${Vulkan_LIBRARY} DIRECTORY)
  # ShaderC
  find_file(Vulkan_shaderc_shared_LIBRARY
    NAMES shaderc_shared.lib
    HINTS ${_Vulkan_LIB_DIR})
  find_file(Vulkan_shaderc_shared_DLL
    NAMES shaderc_shared.dll
    HINTS ${_Vulkan_LIB_DIR}/../Bin)
  # DirectXShaderCompiler
  find_file(Vulkan_dxc_LIBRARY
    NAMES dxcompiler.lib
    HINTS ${_Vulkan_LIB_DIR})
  find_file(Vulkan_dxc_DLL
    NAMES dxcompiler.dll
    HINTS ${_Vulkan_LIB_DIR}/../Bin)
endif()
# ShaderC linking
if(Vulkan_shaderc_shared_LIBRARY AND Vulkan_shaderc_shared_DLL)
  target_link_libraries(${PROJECT_NAME} PUBLIC ${Vulkan_shaderc_shared_LIBRARY})
  target_include_directories(${PROJECT_NAME} PRIVATE ${Vulkan_INCLUDE_DIRS})
  target_compile_definitions(${PROJECT_NAME} PRIVATE HAS_SHADERC)
else()
  message(WARNING "Could not find shaderc_shared; compiling without it.")
endif()
# DXC linking
if(Vulkan_dxc_LIBRARY AND Vulkan_dxc_DLL)
  target_link_libraries(${PROJECT_NAME} PUBLIC ${Vulkan_dxc_LIBRARY})
  target_include_directories(${PROJECT_NAME} PRIVATE ${Vulkan_INCLUDE_DIRS})
  target_compile_definitions(${PROJECT_NAME} PRIVATE HAS_DXC)
else()
  message(WARNING "Could not find shaderc_shared; compiling without it.")
endif()

# Copy required DLLs to output
add_custom_command(TARGET ${PROJECT_NAME} POST_BUILD
                   COMMAND ${CMAKE_COMMAND} -E copy_if_different
                     $<TARGET_RUNTIME_DLLS:${PROJECT_NAME}>
                     ${Vulkan_shaderc_shared_DLL}
                     $<TARGET_FILE_DIR:${PROJECT_NAME}>
                   COMMAND_EXPAND_LISTS)