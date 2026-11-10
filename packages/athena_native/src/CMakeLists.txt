# Android: kneejerk (libsystemone on llama.cpp, CPU) as libathena_engine.so, arm64-v8a.
# Gradle runs this (android/build.gradle.kts); KNEEJERK_DIR points at a kneejerk checkout.
cmake_minimum_required(VERSION 3.21)
project(athena_engine C CXX)

set(KNEEJERK_DIR "${CMAKE_CURRENT_LIST_DIR}/../../../third_party/kneejerk" CACHE PATH "kneejerk checkout")
if (NOT EXISTS "${KNEEJERK_DIR}/CMakeLists.txt")
    message(FATAL_ERROR "no kneejerk at ${KNEEJERK_DIR}: git submodule update --init --recursive")
endif()

set(BUILD_SHARED_LIBS   OFF CACHE BOOL "" FORCE)
set(SYSTEMONE_BUILD_CLI OFF CACHE BOOL "" FORCE)
set(GGML_NATIVE         OFF CACHE BOOL "" FORCE)
# dot product and fp16 arithmetic: Cortex-A55/A75 and newer (2018 on). The app checks
# /proc/cpuinfo for asimddp before loading, so an older phone gets a message, not a crash.
set(GGML_CPU_ARM_ARCH "armv8.2-a+dotprod+fp16" CACHE STRING "" FORCE)
set(GGML_OPENMP         OFF CACHE BOOL "" FORCE)
set(GGML_VULKAN         OFF CACHE BOOL "" FORCE)
set(LLAMA_OPENSSL       OFF CACHE BOOL "" FORCE)
add_subdirectory(${KNEEJERK_DIR} kneejerk EXCLUDE_FROM_ALL)

add_library(athena_engine SHARED athena_engine.c)
target_link_libraries(athena_engine PRIVATE systemone)
target_link_options(athena_engine PRIVATE
    "-Wl,--version-script=${CMAKE_CURRENT_LIST_DIR}/exports.map"
    -Wl,--gc-sections
    -Wl,-z,max-page-size=16384)   # 16 KB pages, Android 15+
