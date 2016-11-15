# Copyright (c) 2015-2016, Ruslan Baratov
# All rights reserved.

include(hunter_apply_copy_rules)
include(hunter_apply_gate_settings)
include(hunter_calculate_self)
include(hunter_create_cache_file)
include(hunter_fatal_error)
include(hunter_internal_error)
include(hunter_sanity_checks)
include(hunter_status_debug)
include(hunter_status_print)
include(hunter_test_string_not_empty)

# Continue initialization of key variables (also see 'hunter_initialize')
#   * calculate toolchain-id
#   * calculate config-id
macro(hunter_finalize)
  # Check preconditions
  hunter_sanity_checks()

  list(APPEND HUNTER_CACHE_SERVERS "https://github.com/ingenue/hunter-cache")
  list(REMOVE_DUPLICATES HUNTER_CACHE_SERVERS)
  hunter_status_debug("List of cache servers:")
  foreach(_server ${HUNTER_CACHE_SERVERS})
    hunter_status_debug("  * ${_server}")
  endforeach()

  get_property(_enabled_languages GLOBAL PROPERTY ENABLED_LANGUAGES)

  list(FIND _enabled_languages "C" _c_enabled_result)
  if(_c_enabled_result EQUAL -1)
    set(_c_enabled FALSE)
  else()
    set(_c_enabled TRUE)
  endif()

  list(FIND _enabled_languages "CXX" _cxx_enabled_result)
  if(_cxx_enabled_result EQUAL -1)
    set(_cxx_enabled FALSE)
  else()
    set(_cxx_enabled TRUE)
  endif()

  if(_c_enabled AND NOT CMAKE_C_ABI_COMPILED)
    hunter_fatal_error(
        "ABI not detected for C compiler" WIKI "error.abi.detection.failure"
    )
  endif()

  if(_cxx_enabled AND NOT CMAKE_CXX_ABI_COMPILED)
    hunter_fatal_error(
        "ABI not detected for CXX compiler" WIKI "error.abi.detection.failure"
    )
  endif()

  string(COMPARE NOTEQUAL "$ENV{HUNTER_BINARY_DIR}" "" _env_not_empty)
  if(_env_not_empty)
    get_filename_component(HUNTER_BINARY_DIR "$ENV{HUNTER_BINARY_DIR}" ABSOLUTE)
    hunter_status_debug("HUNTER_BINARY_DIR: ${HUNTER_BINARY_DIR}")
  endif()

  # * Read HUNTER_GATE_* variables
  # * Check cache HUNTER_* variables is up-to-date
  # * Update cache if needed
  hunter_apply_gate_settings()

  string(SUBSTRING "${HUNTER_SHA1}" 0 7 HUNTER_ID)
  string(SUBSTRING "${HUNTER_CONFIG_SHA1}" 0 7 HUNTER_CONFIG_ID)
  string(SUBSTRING "${HUNTER_TOOLCHAIN_SHA1}" 0 7 HUNTER_TOOLCHAIN_ID)

  set(HUNTER_ID_PATH "${HUNTER_CACHED_ROOT}/_Base/${HUNTER_ID}")
  set(HUNTER_CONFIG_ID_PATH "${HUNTER_ID_PATH}/${HUNTER_CONFIG_ID}")
  set(
      HUNTER_TOOLCHAIN_ID_PATH
      "${HUNTER_CONFIG_ID_PATH}/${HUNTER_TOOLCHAIN_ID}"
  )

  set(HUNTER_INSTALL_PREFIX "${HUNTER_TOOLCHAIN_ID_PATH}/Install")
  list(APPEND CMAKE_PREFIX_PATH "${HUNTER_INSTALL_PREFIX}")
  if(ANDROID)
    # OpenCV support: https://github.com/ruslo/hunter/issues/153
    list(APPEND CMAKE_PREFIX_PATH "${HUNTER_INSTALL_PREFIX}/sdk/native/jni")
  endif()
  list(APPEND CMAKE_FIND_ROOT_PATH "${HUNTER_INSTALL_PREFIX}")

  hunter_status_print("HUNTER_ROOT: ${HUNTER_CACHED_ROOT}")
  hunter_status_debug("HUNTER_TOOLCHAIN_ID_PATH: ${HUNTER_TOOLCHAIN_ID_PATH}")
  hunter_status_debug(
      "HUNTER_CONFIGURATION_TYPES: ${HUNTER_CACHED_CONFIGURATION_TYPES}"
  )

  set(_id_info "[ Hunter-ID: ${HUNTER_ID} |")
  set(_id_info "${_id_info} Config-ID: ${HUNTER_CONFIG_ID} |")
  set(_id_info "${_id_info} Toolchain-ID: ${HUNTER_TOOLCHAIN_ID} ]")

  hunter_status_print("${_id_info}")

  set(HUNTER_CACHE_FILE "${HUNTER_TOOLCHAIN_ID_PATH}/cache.cmake")
  hunter_create_cache_file("${HUNTER_CACHE_FILE}")

  if(MSVC)
    include(hunter_setup_msvc)
    hunter_setup_msvc()
  endif()

  ### Disable package registry
  ### http://www.cmake.org/cmake/help/v3.1/manual/cmake-packages.7.html#disabling-the-package-registry
  set(CMAKE_EXPORT_NO_PACKAGE_REGISTRY ON)
  set(CMAKE_FIND_PACKAGE_NO_PACKAGE_REGISTRY ON)
  set(CMAKE_FIND_PACKAGE_NO_SYSTEM_PACKAGE_REGISTRY ON)
  ### -- end

  ### Disable environment variables
  ### http://www.cmake.org/cmake/help/v3.3/command/find_package.html
  set(ENV{CMAKE_PREFIX_PATH} "")
  set(ENV{CMAKE_FRAMEWORK_PATH} "")
  set(ENV{CMAKE_APPBUNDLE_PATH} "")
  ### -- end

  ### 1. Clear all '<NAME>_ROOT' variables (cache, environment, ...)
  ### 2. Set '<NAME>_ROOT' or 'HUNTER_<name>_VERSION' variables
  set(HUNTER_ALLOW_CONFIG_LOADING YES)
  include("${HUNTER_CONFIG_ID_PATH}/config.cmake")
  set(HUNTER_ALLOW_CONFIG_LOADING NO)

  hunter_test_string_not_empty("${HUNTER_INSTALL_PREFIX}")
  hunter_test_string_not_empty("${CMAKE_BINARY_DIR}")

  file(
      WRITE
      "${CMAKE_BINARY_DIR}/_3rdParty/Hunter/install-root-dir"
      "${HUNTER_INSTALL_PREFIX}"
  )

  hunter_apply_copy_rules()

  if(ANDROID AND CMAKE_VERSION VERSION_LESS "3.7")
    hunter_user_error(
        "CMake version 3.7+ required for Android platforms, see"
        " https://docs.hunter.sh/en/latest/quick-start/cmake.html"
    )
  endif()

  if(ANDROID)
    # Needed in 'hunter_autotool_project'
    get_filename_component(
        ANDROID_TOOLCHAIN_MACHINE_NAME
        "${CMAKE_CXX_ANDROID_TOOLCHAIN_PREFIX}"
        NAME
    )
    string(
        REGEX
        REPLACE
        "-$"
        ""
        ANDROID_TOOLCHAIN_MACHINE_NAME
        "${ANDROID_TOOLCHAIN_MACHINE_NAME}"
    )

    # GDBSERVER moved to https://github.com/hunter-packages/android-apk/commit/32531adeb287d3e3b20498ff1a0f76336cbe0551

    if(CMAKE_HOST_SYSTEM_NAME STREQUAL "Darwin")
      if(CMAKE_HOST_SYSTEM_PROCESSOR STREQUAL "x86_64")
        set(ANDROID_NDK_HOST_SYSTEM_NAME "darwin-x86_64")
      else()
        set(ANDROID_NDK_HOST_SYSTEM_NAME "darwin-x86")
      endif()
    elseif(CMAKE_HOST_SYSTEM_NAME STREQUAL "Linux")
      if(CMAKE_HOST_SYSTEM_PROCESSOR STREQUAL "x86_64")
        set(ANDROID_NDK_HOST_SYSTEM_NAME "linux-x86_64")
      else()
        set(ANDROID_NDK_HOST_SYSTEM_NAME "linux-x86")
      endif()
    elseif(CMAKE_HOST_SYSTEM_NAME STREQUAL "Windows")
      if(CMAKE_HOST_SYSTEM_PROCESSOR STREQUAL "AMD64")
        set(ANDROID_NDK_HOST_SYSTEM_NAME "windows-x86_64")
      else()
        set(ANDROID_NDK_HOST_SYSTEM_NAME "windows")
      endif()
    else()
      hunter_internal_error("Unknown host for Android")
    endif()

    set(ANDROID_COMPILER_VERSION "")
    string(
        REGEX
        REPLACE
        "^${CMAKE_ANDROID_NDK}/toolchains/${ANDROID_TOOLCHAIN_MACHINE_NAME}-(.*)/prebuilt/.*/bin/${ANDROID_TOOLCHAIN_MACHINE_NAME}-$"
        "\\1"
        ANDROID_COMPILER_VERSION
        "${CMAKE_CXX_ANDROID_TOOLCHAIN_PREFIX}"
    )
    string(COMPARE EQUAL "${ANDROID_COMPILER_VERSION}" "" is_empty)
    if(is_empty)
      hunter_internal_error("Parse failed")
    endif()
  endif()
endmacro()
