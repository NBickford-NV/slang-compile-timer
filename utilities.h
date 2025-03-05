#pragma once

// Utility functions.

// If defined, prints more messages.
#define VERBOSE

#include <chrono>
#include <filesystem>
#include <fstream>
#include <optional>
#include <stddef.h>
#include <stdio.h>
#include <string>

namespace fs = std::filesystem;
using timer  = std::chrono::high_resolution_clock;

// Loads a file from a path; returns empty on failure.
std::optional<std::string> load_file(const char* filename)
{
  try
  {
    std::ifstream file(filename, std::ios::ate | std::ios::binary);
    file.exceptions(std::ios::badbit);
    const std::streampos size_signed = file.tellg();
    if(size_signed < 0)
    {
#ifdef VERBOSE
      fprintf(stderr, "Could not load %s: size was negative.\n", filename);
#endif
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
#ifdef VERBOSE
    fprintf(stderr, "Caught exception while trying to read %s: %s\n", filename, e.what());
#endif
  }
  return {};  // Only reached on exception
}

// Finds and loads a file, searching up at most 3 directories; returns empty
// on failure.
std::optional<std::string> find_file(const char* filename, std::string* found_path)
{
  std::optional<std::string> result;
  std::string                search_path = filename;
  for(size_t parents = 0; parents <= 3; parents++)
  {
    result = load_file(search_path.c_str());
    if(result.has_value())
    {
      if(found_path)
      {
        *found_path = search_path;
      }
      return result;
    }
    search_path = "../" + search_path;
  }
  return result;
}
