cmake_minimum_required(VERSION 3.16)
project(d_ufbx C)

set(CMAKE_C_STANDARD 99)
set(CMAKE_C_STANDARD_REQUIRED ON)
set(CMAKE_POSITION_INDEPENDENT_CODE ON)
set(BUILD_SHARED_LIBS OFF CACHE BOOL "" FORCE)

# ---- Vendored ufbx (extern/ufbx submodule) ------------------------------------
# ufbx is a single-file C library: just ufbx.c + ufbx.h.
# No CMake of its own; we compile the one translation unit directly.
add_library(ufbx STATIC extern/ufbx/ufbx.c)

target_include_directories(ufbx PUBLIC extern/ufbx)

target_compile_options(ufbx PRIVATE
    -Wall
    -Wno-unused-function
    # ufbx uses long long / bool / flexible arrays that may trigger pedantic warnings
    -Wno-pedantic
)
