include(CMakeParseArguments)

# --- Global macros ---

# setx()
# Description:
#   Sets a variable, similar to `set()`, but also prints the value.
# Arguments:
#   variable string - The variable to set
#   value    string - The value to set the variable to
macro(setx)
  set(${ARGV})
  message(STATUS "Set ${ARGV0}: ${${ARGV0}}")
endmacro()

# optionx()
# Description:
#   Defines an option, similar to `option()`, but allows for bool, string, and regex types.
# Arguments:
#   variable    string - The variable to set
#   type        string - The type of the variable
#   description string - The description of the variable
#   DEFAULT     string - The default value of the variable
#   PREVIEW     string - The preview value of the variable
#   REGEX       string - The regex to match the value
#   REQUIRED    bool   - Whether the variable is required
macro(optionx variable type description)
  set(options REQUIRED)
  set(oneValueArgs DEFAULT PREVIEW REGEX)
  set(multiValueArgs)
  cmake_parse_arguments(${variable} "${options}" "${oneValueArgs}" "${multiValueArgs}" ${ARGN})

  if(NOT ${type} MATCHES "^(BOOL|STRING|FILEPATH|PATH|INTERNAL)$")
    set(${variable}_REGEX ${type})
    set(${variable}_TYPE STRING)
  else()
    set(${variable}_TYPE ${type})
  endif()

  set(${variable} ${${variable}_DEFAULT} CACHE ${${variable}_TYPE} ${description})
  set(${variable}_SOURCE "argument")
  set(${variable}_PREVIEW -D${variable})

  if(DEFINED ENV{${variable}})
    set(${variable} $ENV{${variable}} CACHE ${${variable}_TYPE} ${description} FORCE)
    set(${variable}_SOURCE "environment variable")
    set(${variable}_PREVIEW ${variable})
  endif()

  if(NOT ${variable} AND ${${variable}_REQUIRED})
    message(FATAL_ERROR "Required ${${variable}_SOURCE} is missing: please set, ${${variable}_PREVIEW}=<${${variable}_REGEX}>")
  endif()

  if(${type} STREQUAL "BOOL")
    if("${${variable}}" MATCHES "^(TRUE|true|ON|on|YES|yes|1)$")
      set(${variable} ON)
    elseif("${${variable}}" MATCHES "^(FALSE|false|OFF|off|NO|no|0)$")
      set(${variable} OFF)
    else()
      message(FATAL_ERROR "Invalid ${${variable}_SOURCE}: ${${variable}_PREVIEW}=\"${${variable}}\", please use ${${variable}_PREVIEW}=<ON|OFF>")
    endif()
  endif()

  if(DEFINED ${variable}_REGEX AND NOT "^(${${variable}_REGEX})$" MATCHES "${${variable}}")
    message(FATAL_ERROR "Invalid ${${variable}_SOURCE}: ${${variable}_PREVIEW}=\"${${variable}}\", please use ${${variable}_PREVIEW}=<${${variable}_REGEX}>")
  endif()

  message(STATUS "Set ${variable}: ${${variable}}")
endmacro()

# unsupported()
# Description:
#   Prints a message that the feature is not supported.
# Arguments:
#   variable string - The variable that is not supported
macro(unsupported variable)
  message(FATAL_ERROR "Unsupported ${variable}: \"${${variable}}\"")
endmacro()

# --- CMake variables ---

setx(CMAKE_VERSION ${CMAKE_VERSION})
setx(CMAKE_COMMAND ${CMAKE_COMMAND})
setx(CMAKE_HOST_SYSTEM_NAME ${CMAKE_HOST_SYSTEM_NAME})

# In script mode, using -P, this variable is not set
if(NOT DEFINED CMAKE_HOST_SYSTEM_PROCESSOR)
  cmake_host_system_information(RESULT CMAKE_HOST_SYSTEM_PROCESSOR QUERY OS_PLATFORM)
endif()
setx(CMAKE_HOST_SYSTEM_PROCESSOR ${CMAKE_HOST_SYSTEM_PROCESSOR})

if(CMAKE_HOST_APPLE)
  set(HOST_OS "darwin")
elseif(CMAKE_HOST_WIN32)
  set(HOST_OS "windows")
elseif(CMAKE_HOST_LINUX)
  set(HOST_OS "linux")
else()
  unsupported(CMAKE_HOST_SYSTEM_NAME)
endif()

if(CMAKE_HOST_SYSTEM_PROCESSOR MATCHES "arm64|ARM64|aarch64|AARCH64")
  set(HOST_OS "aarch64")
elseif(CMAKE_HOST_SYSTEM_PROCESSOR MATCHES "x86_64|X86_64|x64|X64|amd64|AMD64")
  set(HOST_OS "x64")
else()
  unsupported(CMAKE_HOST_SYSTEM_PROCESSOR)
endif()

setx(CMAKE_EXPORT_COMPILE_COMMANDS ON)
setx(CMAKE_COLOR_DIAGNOSTICS ON)

cmake_host_system_information(RESULT CORE_COUNT QUERY NUMBER_OF_LOGICAL_CORES)
optionx(CMAKE_BUILD_PARALLEL_LEVEL STRING "The number of parallel build jobs" DEFAULT ${CORE_COUNT})

# --- Global variables ---

setx(CWD ${CMAKE_SOURCE_DIR})
setx(BUILD_PATH ${CMAKE_BINARY_DIR})

optionx(CACHE_PATH FILEPATH "The path to the cache directory" DEFAULT ${BUILD_PATH}/cache)
optionx(CACHE_STRATEGY "read-write|read-only|write-only|none" "The strategy to use for caching" DEFAULT "read-write")

optionx(CI BOOL "If CI is enabled" DEFAULT OFF)

if(CI)
  set(WARNING FATAL_ERROR)
else()
  set(WARNING WARNING)
endif()

# TODO: This causes flaky zig builds in CI, so temporarily disable it.
# if(CI)
#   set(DEFAULT_VENDOR_PATH ${CACHE_PATH}/vendor)
# else()
#   set(DEFAULT_VENDOR_PATH ${CWD}/vendor)
# endif()

optionx(VENDOR_PATH FILEPATH "The path to the vendor directory" DEFAULT ${CWD}/vendor)
optionx(TMP_PATH FILEPATH "The path to the temporary directory" DEFAULT ${BUILD_PATH}/tmp)

optionx(FRESH BOOL "Set when --fresh is used" DEFAULT OFF)
optionx(CLEAN BOOL "Set when --clean is used" DEFAULT OFF)

# --- Helper functions ---

# setenv()
# Description:
#   Sets an environment variable during the build step, and writes it to a .env file.
# Arguments:
#   variable string - The variable to set
#   value    string - The value to set the variable to
function(setenv variable value)
  set(ENV_PATH ${BUILD_PATH}/.env)
  if(value MATCHES "/|\\\\")
    file(TO_NATIVE_PATH ${value} value)
  endif()
  set(ENV_LINE "${variable}=${value}")

  if(EXISTS ${ENV_PATH})
    file(STRINGS ${ENV_PATH} ENV_FILE ENCODING UTF-8)

    foreach(line ${ENV_FILE})
      if(line MATCHES "^${variable}=")
        list(REMOVE_ITEM ENV_FILE ${line})
        set(ENV_MODIFIED ON)
      endif()
    endforeach()

    if(ENV_MODIFIED)
      list(APPEND ENV_FILE "${variable}=${value}")
      list(JOIN ENV_FILE "\n" ENV_FILE)
      file(WRITE ${ENV_PATH} ${ENV_FILE})
    else()
      file(APPEND ${ENV_PATH} "\n${variable}=${value}")
    endif()
  else()
    file(WRITE ${ENV_PATH} ${ENV_LINE})
  endif()

  message(STATUS "Set ENV ${variable}: ${value}")
endfunction()

# check_command()
# Description:
#   Checks if a command is available, used by `find_command()` as a validator.
# Arguments:
#   FOUND bool   - The variable to set to true if the version is found
#   CMD   string - The executable to check the version of
function(check_command FOUND CMD)
  set(${FOUND} OFF PARENT_SCOPE)

  if(${CMD} MATCHES "zig")
    set(CHECK_COMMAND ${CMD} version)
  else()
    set(CHECK_COMMAND ${CMD} --version)
  endif()

  execute_process(
    COMMAND ${CHECK_COMMAND}
    RESULT_VARIABLE RESULT
    OUTPUT_VARIABLE OUTPUT
    OUTPUT_STRIP_TRAILING_WHITESPACE
  )

  if(NOT RESULT EQUAL 0 OR NOT OUTPUT)
    message(DEBUG "${CHECK_COMMAND}, exited with code ${RESULT}")
    return()
  endif()

  parse_semver(${OUTPUT} CMD)
  parse_semver(${CHECK_COMMAND_VERSION} CHECK)

  if(CHECK_COMMAND_VERSION MATCHES ">=")
    if(NOT CMD_VERSION VERSION_GREATER_EQUAL ${CHECK_VERSION})
      message(DEBUG "${CHECK_COMMAND}, actual: ${CMD_VERSION}, expected: ${CHECK_COMMAND_VERSION}")
      return()
    endif()
  elseif(CHECK_COMMAND_VERSION MATCHES ">")
    if(NOT CMD_VERSION VERSION_GREATER ${CHECK_VERSION})
      message(DEBUG "${CHECK_COMMAND}, actual: ${CMD_VERSION}, expected: ${CHECK_COMMAND_VERSION}")
      return()
    endif()
  else()
    if(NOT CMD_VERSION VERSION_EQUAL ${CHECK_VERSION})
      message(DEBUG "${CHECK_COMMAND}, actual: ${CMD_VERSION}, expected: =${CHECK_COMMAND_VERSION}")
      return()
    endif()
  endif()

  set(${FOUND} TRUE PARENT_SCOPE)
endfunction()

# find_command()
# Description:
#   Finds a command, similar to `find_program()`, but allows for version checking.
# Arguments:
#   VARIABLE  string   - The variable to set
#   COMMAND   string[] - The names of the command to find
#   PATHS     string[] - The paths to search for the command
#   REQUIRED  bool     - If false, the command is optional
#   VERSION   string   - The version of the command to find (e.g. "1.2.3" or ">1.2.3")
function(find_command)
  set(options)
  set(args VARIABLE VERSION MIN_VERSION REQUIRED)
  set(multiArgs COMMAND PATHS)
  cmake_parse_arguments(CMD "${options}" "${args}" "${multiArgs}" ${ARGN})

  if(NOT CMD_VARIABLE)
    message(FATAL_ERROR "find_command: VARIABLE is required")
  endif()

  if(NOT CMD_COMMAND)
    message(FATAL_ERROR "find_command: COMMAND is required")
  endif()

  if(CMD_VERSION)
    set(CHECK_COMMAND_VERSION ${CMD_VERSION}) # special global variable
    set(CMD_VALIDATOR VALIDATOR check_command)
  endif()

  find_program(
    ${CMD_VARIABLE}
    NAMES ${CMD_COMMAND}
    PATHS ${CMD_PATHS}
    ${CMD_VALIDATOR}
  )

  if(NOT CMD_REQUIRED STREQUAL "OFF" AND ${CMD_VARIABLE} MATCHES "NOTFOUND")
    if(CMD_VERSION)
      message(FATAL_ERROR "Command not found: \"${CMD_COMMAND}\" that matches version \"${CHECK_COMMAND_VERSION}\"")
    endif()
    message(FATAL_ERROR "Command not found: \"${CMD_COMMAND}\"")
  endif()

  if(${CMD_VARIABLE} MATCHES "NOTFOUND")
    unset(${CMD_VARIABLE} PARENT_SCOPE)
  else()
    setx(${CMD_VARIABLE} ${${CMD_VARIABLE}} PARENT_SCOPE)
  endif()
endfunction()

# register_command()
# Description:
#   Registers a command, similar to `add_custom_command()`, but has more validation and features.
# Arguments:
#   COMMAND      string[] - The command to run
#   COMMENT      string   - The comment to display in the log
#   CWD          string   - The working directory to run the command in
#   ENVIRONMENT  string[] - The environment variables to set (e.g. "DEBUG=1")
#   TARGETS      string[] - The targets that this command depends on
#   SOURCES      string[] - The files that this command depends on
#   OUTPUTS      string[] - The files that this command produces
#   ARTIFACTS    string[] - The files that this command produces, and uploads as an artifact in CI
#   ALWAYS_RUN   bool     - If true, the command will always run
#   TARGET       string   - The target to register the command with
#   TARGET_PHASE string   - The target phase to register the command with (e.g. PRE_BUILD, PRE_LINK, POST_BUILD)
#   GROUP        string   - The group to register the command with (e.g. similar to JOB_POOL)
function(register_command)
  set(options ALWAYS_RUN)
  set(args COMMENT CWD TARGET TARGET_PHASE GROUP)
  set(multiArgs COMMAND ENVIRONMENT TARGETS SOURCES OUTPUTS ARTIFACTS)
  cmake_parse_arguments(CMD "${options}" "${args}" "${multiArgs}" ${ARGN})

  if(NOT CMD_COMMAND)
    message(FATAL_ERROR "register_command: COMMAND is required")
  endif()

  if(NOT CMD_CWD)
    set(CMD_CWD ${CWD})
  endif()

  if(CMD_ENVIRONMENT)
    set(CMD_COMMAND ${CMAKE_COMMAND} -E env ${CMD_ENVIRONMENT} ${CMD_COMMAND})
  endif()
  
  if(NOT CMD_COMMENT)
    string(JOIN " " CMD_COMMENT ${CMD_COMMAND})
  endif()

  set(CMD_COMMANDS COMMAND ${CMD_COMMAND})
  set(CMD_EFFECTIVE_DEPENDS)

  list(GET CMD_COMMAND 0 CMD_EXECUTABLE)
  if(CMD_EXECUTABLE MATCHES "/|\\\\")
    list(APPEND CMD_EFFECTIVE_DEPENDS ${CMD_EXECUTABLE})
  endif()

  foreach(target ${CMD_TARGETS})
    if(target MATCHES "/|\\\\")
      message(FATAL_ERROR "register_command: TARGETS contains \"${target}\", if it's a path add it to SOURCES instead")
    endif()
    if(NOT TARGET ${target})
      message(FATAL_ERROR "register_command: TARGETS contains \"${target}\", but it's not a target")
    endif()
    list(APPEND CMD_EFFECTIVE_DEPENDS ${target})
  endforeach()

  foreach(source ${CMD_SOURCES})
    if(NOT source MATCHES "^(${CWD}|${BUILD_PATH}|${CACHE_PATH}|${VENDOR_PATH})")
      message(FATAL_ERROR "register_command: SOURCES contains \"${source}\", if it's a path, make it absolute, otherwise add it to TARGETS instead")
    endif()
    list(APPEND CMD_EFFECTIVE_DEPENDS ${source})
  endforeach()

  if(NOT CMD_EFFECTIVE_DEPENDS AND NOT CMD_ALWAYS_RUN)
    message(FATAL_ERROR "register_command: TARGETS or SOURCES is required")
  endif()

  set(CMD_EFFECTIVE_OUTPUTS)

  foreach(output ${CMD_OUTPUTS})
    if(NOT output MATCHES "^(${CWD}|${BUILD_PATH}|${CACHE_PATH}|${VENDOR_PATH})")
      message(FATAL_ERROR "register_command: OUTPUTS contains \"${output}\", if it's a path, make it absolute")
    endif()
    list(APPEND CMD_EFFECTIVE_OUTPUTS ${output})
  endforeach()

  foreach(artifact ${CMD_ARTIFACTS})
    if(NOT artifact MATCHES "^(${CWD}|${BUILD_PATH}|${CACHE_PATH}|${VENDOR_PATH})")
      message(FATAL_ERROR "register_command: ARTIFACTS contains \"${artifact}\", if it's a path, make it absolute")
    endif()
    list(APPEND CMD_EFFECTIVE_OUTPUTS ${artifact})
    if(BUILDKITE)
      file(RELATIVE_PATH filename ${BUILD_PATH} ${artifact})
      list(APPEND CMD_COMMANDS COMMAND ${CMAKE_COMMAND} -E chdir ${BUILD_PATH} buildkite-agent artifact upload ${filename})
    endif()
  endforeach()

  foreach(output ${CMD_EFFECTIVE_OUTPUTS})
    get_source_file_property(generated ${output} GENERATED)
    if(generated)
      list(REMOVE_ITEM CMD_EFFECTIVE_OUTPUTS ${output})
      list(APPEND CMD_EFFECTIVE_OUTPUTS ${output}.always_run_${CMD_TARGET})
    endif()
  endforeach()

  if(CMD_ALWAYS_RUN)
    list(APPEND CMD_EFFECTIVE_OUTPUTS ${CMD_CWD}/.always_run_${CMD_TARGET})
  endif()

  if(CMD_TARGET_PHASE)
    if(NOT CMD_TARGET)
      message(FATAL_ERROR "register_command: TARGET is required when TARGET_PHASE is set")
    endif()
    if(NOT TARGET ${CMD_TARGET})
      message(FATAL_ERROR "register_command: TARGET is not a valid target: ${CMD_TARGET}")
    endif()
    add_custom_command(
      TARGET ${CMD_TARGET} ${CMD_TARGET_PHASE}
      COMMENT ${CMD_COMMENT}
      WORKING_DIRECTORY ${CMD_CWD}
      VERBATIM ${CMD_COMMANDS}
    )
    set_property(TARGET ${CMD_TARGET} PROPERTY OUTPUT ${CMD_EFFECTIVE_OUTPUTS} APPEND)
    set_property(TARGET ${CMD_TARGET} PROPERTY DEPENDS ${CMD_EFFECTIVE_DEPENDS} APPEND)
    return()
  endif()

  if(NOT CMD_EFFECTIVE_OUTPUTS)
    message(FATAL_ERROR "register_command: OUTPUTS or ARTIFACTS is required, or set ALWAYS_RUN")
  endif()

  if(CMD_TARGET)
    if(TARGET ${CMD_TARGET})
      message(FATAL_ERROR "register_command: TARGET is already registered: ${CMD_TARGET}")
    endif()
    add_custom_target(${CMD_TARGET}
      COMMENT ${CMD_COMMENT}
      DEPENDS ${CMD_EFFECTIVE_OUTPUTS}
      JOB_POOL ${CMD_GROUP}
    )
    if(TARGET clone-${CMD_TARGET})
      add_dependencies(${CMD_TARGET} clone-${CMD_TARGET})
    endif()
  endif()

  add_custom_command(
    VERBATIM ${CMD_COMMANDS}
    WORKING_DIRECTORY ${CMD_CWD}
    COMMENT ${CMD_COMMENT}
    DEPENDS ${CMD_EFFECTIVE_DEPENDS}
    OUTPUT ${CMD_EFFECTIVE_OUTPUTS}
    JOB_POOL ${CMD_GROUP}
  )
endfunction()

# parse_package_json()
# Description:
#   Parses a package.json file.
# Arguments:
#   CWD                   string - The directory to look for the package.json file
#   VERSION_VARIABLE      string - The variable to set to the package version
#   NODE_MODULES_VARIABLE string - The variable to set to list of node_modules sources
function(parse_package_json)
  set(args CWD VERSION_VARIABLE NODE_MODULES_VARIABLE)
  cmake_parse_arguments(NPM "" "${args}" "" ${ARGN})

  if(NOT NPM_CWD)
    set(NPM_CWD ${CWD})
  endif()

  set(NPM_PACKAGE_JSON_PATH ${NPM_CWD}/package.json)

  if(NOT EXISTS ${NPM_PACKAGE_JSON_PATH})
    message(FATAL_ERROR "parse_package_json: package.json not found: ${NPM_PACKAGE_JSON_PATH}")
  endif()

  file(READ ${NPM_PACKAGE_JSON_PATH} NPM_PACKAGE_JSON)
  if(NOT NPM_PACKAGE_JSON)
    message(FATAL_ERROR "parse_package_json: failed to read package.json: ${NPM_PACKAGE_JSON_PATH}")
  endif()

  if(NPM_VERSION_VARIABLE)
    string(JSON NPM_VERSION ERROR_VARIABLE error GET "${NPM_PACKAGE_JSON}" version)
    if(error)
      message(FATAL_ERROR "parse_package_json: failed to read 'version': ${error}")
    endif()
    set(${NPM_VERSION_VARIABLE} ${NPM_VERSION} PARENT_SCOPE)
  endif()

  if(NPM_NODE_MODULES_VARIABLE)
    set(NPM_NODE_MODULES)
    set(NPM_NODE_MODULES_PATH ${NPM_CWD}/node_modules)
    set(NPM_NODE_MODULES_PROPERTIES "devDependencies" "dependencies")
    
    foreach(property ${NPM_NODE_MODULES_PROPERTIES})
      string(JSON NPM_${property} ERROR_VARIABLE error GET "${NPM_PACKAGE_JSON}" "${property}")
      if(error MATCHES "not found")
        continue()
      endif()
      if(error)
        message(FATAL_ERROR "parse_package_json: failed to read '${property}': ${error}")
      endif()

      string(JSON NPM_${property}_LENGTH ERROR_VARIABLE error LENGTH "${NPM_${property}}")
      if(error)
        message(FATAL_ERROR "parse_package_json: failed to read '${property}' length: ${error}")
      endif()

      math(EXPR NPM_${property}_MAX_INDEX "${NPM_${property}_LENGTH} - 1")
      foreach(i RANGE 0 ${NPM_${property}_MAX_INDEX})
        string(JSON NPM_${property}_${i} ERROR_VARIABLE error MEMBER "${NPM_${property}}" ${i})
        if(error)
          message(FATAL_ERROR "parse_package_json: failed to index '${property}' at ${i}: ${error}")
        endif()
        list(APPEND NPM_NODE_MODULES ${NPM_NODE_MODULES_PATH}/${NPM_${property}_${i}}/package.json)
      endforeach()
    endforeach()

    set(${NPM_NODE_MODULES_VARIABLE} ${NPM_NODE_MODULES} PARENT_SCOPE)
  endif()
endfunction()

# register_bun_install()
# Description:
#   Registers a command to run `bun install` in a directory.
# Arguments:
#   CWD                   string - The directory to run `bun install`
#   NODE_MODULES_VARIABLE string - The variable to set to list of node_modules sources
function(register_bun_install)
  set(args CWD NODE_MODULES_VARIABLE)
  cmake_parse_arguments(NPM "" "${args}" "" ${ARGN})

  if(NOT NPM_CWD)
    set(NPM_CWD ${CWD})
  endif()

  if(NPM_CWD STREQUAL ${CWD})
    set(NPM_COMMENT "bun install")
  else()
    set(NPM_COMMENT "bun install --cwd ${NPM_CWD}")
  endif()

  parse_package_json(
    CWD
      ${NPM_CWD}
    NODE_MODULES_VARIABLE
      NPM_NODE_MODULES
  )

  if(NOT NPM_NODE_MODULES)
    message(FATAL_ERROR "register_bun_install: ${NPM_CWD}/package.json does not have dependencies?")
  endif()

  register_command(
    COMMENT
      ${NPM_COMMENT}
    CWD
      ${NPM_CWD}
    COMMAND
      ${BUN_EXECUTABLE}
        install
        --frozen-lockfile
    SOURCES
      ${NPM_CWD}/package.json
    OUTPUTS
      ${NPM_NODE_MODULES}
  )

  set(${NPM_NODE_MODULES_VARIABLE} ${NPM_NODE_MODULES} PARENT_SCOPE)
endfunction()

# register_repository()
# Description:
#   Registers a git repository.
# Arguments:
#   NAME       string - The name of the repository
#   REPOSITORY string - The repository to clone
#   BRANCH     string - The branch to clone
#   TAG        string - The tag to clone
#   COMMIT     string - The commit to clone
#   PATH       string - The path to clone the repository to
#   OUTPUTS    string - The outputs of the repository
function(register_repository)
  set(args NAME REPOSITORY BRANCH TAG COMMIT PATH)
  set(multiArgs OUTPUTS)
  cmake_parse_arguments(GIT "" "${args}" "${multiArgs}" ${ARGN})

  if(NOT GIT_REPOSITORY)
    message(FATAL_ERROR "git_clone: REPOSITORY is required")
  endif()

  if(NOT GIT_BRANCH AND NOT GIT_TAG AND NOT GIT_COMMIT)
    message(FATAL_ERROR "git_clone: COMMIT, TAG, or BRANCH is required")
  endif()

  if(NOT GIT_PATH)
    set(GIT_PATH ${VENDOR_PATH}/${GIT_NAME})
  endif()

  set(GIT_EFFECTIVE_OUTPUTS)
  foreach(output ${GIT_OUTPUTS})
    list(APPEND GIT_EFFECTIVE_OUTPUTS ${GIT_PATH}/${output})
  endforeach()

  register_command(
    TARGET
      clone-${GIT_NAME}
    COMMENT
      "Cloning ${GIT_NAME}"
    COMMAND
      ${CMAKE_COMMAND}
        -DGIT_PATH=${GIT_PATH}
        -DGIT_REPOSITORY=${GIT_REPOSITORY}
        -DGIT_NAME=${GIT_NAME}
        -DGIT_COMMIT=${GIT_COMMIT}
        -DGIT_TAG=${GIT_TAG}
        -DGIT_BRANCH=${GIT_BRANCH}
        -P ${CWD}/cmake/scripts/GitClone.cmake
    OUTPUTS
      ${GIT_PATH}
      ${GIT_EFFECTIVE_OUTPUTS}
  )
endfunction()

# register_cmake_command()
# Description:
#   Registers a command that builds an external CMake project.
# Arguments:
#   TARGET                    string   - The target to register the command with
#   ARGS                      string[] - The arguments to pass to CMake (e.g. -DKEY=VALUE)
#   CWD                       string   - The directory where the CMake files are located
#   BUILD_PATH                string   - The path to build the project to
#   LIB_PATH                  string   - The path to the libraries
#   TARGETS                   string[] - The targets to build from CMake
#   LIBRARIES                 string[] - The libraries that are built
#   INCLUDES                  string[] - The include paths
function(register_cmake_command)
  set(args TARGET CWD BUILD_PATH LIB_PATH)
  set(multiArgs ARGS TARGETS LIBRARIES INCLUDES)
  # Use "MAKE" instead of "CMAKE" to prevent conflicts with CMake's own CMAKE_* variables
  cmake_parse_arguments(MAKE "" "${args}" "${multiArgs}" ${ARGN})

  if(NOT MAKE_TARGET)
    message(FATAL_ERROR "register_cmake_command: TARGET is required")
  endif()

  if(TARGET ${MAKE_TARGET})
    message(FATAL_ERROR "register_cmake_command: TARGET is already a target: ${MAKE_TARGET}")
  endif()

  if(NOT MAKE_CWD)
    set(MAKE_CWD ${VENDOR_PATH}/${MAKE_TARGET})
  endif()

  if(NOT MAKE_BUILD_PATH)
    set(MAKE_BUILD_PATH ${BUILD_PATH}/${MAKE_TARGET})
  endif()

  if(MAKE_LIB_PATH)
    set(MAKE_LIB_PATH ${MAKE_BUILD_PATH}/${MAKE_LIB_PATH})
  else()
    set(MAKE_LIB_PATH ${MAKE_BUILD_PATH})
  endif()

  set(MAKE_EFFECTIVE_ARGS -B${MAKE_BUILD_PATH} ${CMAKE_ARGS})

  set(setFlags GENERATOR BUILD_TYPE)
  set(appendFlags C_FLAGS CXX_FLAGS LINKER_FLAGS)
  set(specialFlags POSITION_INDEPENDENT_CODE)
  set(flags ${setFlags} ${appendFlags} ${specialFlags})

  foreach(arg ${MAKE_ARGS})
    foreach(flag ${flags})
      if(arg MATCHES "-DCMAKE_${flag}=(.*)")
        if(DEFINED MAKE_${flag})
          message(FATAL_ERROR "register_cmake_command: CMAKE_${flag} was already set: \"${MAKE_${flag}}\"")
        endif()
        set(MAKE_${flag} ${CMAKE_MATCH_1})
        set(${arg}_USED ON)
      endif()
    endforeach()
    if(NOT ${arg}_USED)
      list(APPEND MAKE_EFFECTIVE_ARGS ${arg})
    endif()
  endforeach()

  foreach(flag ${setFlags})
    if(NOT DEFINED MAKE_${flag} AND DEFINED CMAKE_${flag})
      set(MAKE_${flag} ${CMAKE_${flag}})
    endif()
  endforeach()

  foreach(flag ${appendFlags})
    if(MAKE_${flag})
      set(MAKE_${flag} "${CMAKE_${flag}} ${MAKE_${flag}}")
    else()
      set(MAKE_${flag} ${CMAKE_${flag}})
    endif()
  endforeach()

  if(MAKE_POSITION_INDEPENDENT_CODE AND NOT WIN32)
    set(MAKE_C_FLAGS "${MAKE_C_FLAGS} -fPIC")
    set(MAKE_CXX_FLAGS "${MAKE_CXX_FLAGS} -fPIC")
  elseif(APPLE)
    set(MAKE_C_FLAGS "${MAKE_C_FLAGS} -fno-pic -fno-pie")
    set(MAKE_CXX_FLAGS "${MAKE_CXX_FLAGS} -fno-pic -fno-pie")
  endif()

  set(effectiveFlags ${setFlags} ${appendFlags})
  foreach(flag ${effectiveFlags})
    list(APPEND MAKE_EFFECTIVE_ARGS "-DCMAKE_${flag}=${MAKE_${flag}}")
  endforeach()

  if(DEFINED FRESH)
    list(APPEND MAKE_EFFECTIVE_ARGS --fresh)
  endif()

  register_command(
    COMMENT "Configuring ${MAKE_TARGET}"
    TARGET configure-${MAKE_TARGET}
    COMMAND ${CMAKE_COMMAND} ${MAKE_EFFECTIVE_ARGS}
    CWD ${MAKE_CWD}
    OUTPUTS ${MAKE_BUILD_PATH}/CMakeCache.txt
  )

  if(TARGET clone-${MAKE_TARGET})
    add_dependencies(configure-${MAKE_TARGET} clone-${MAKE_TARGET})
  endif()

  set(MAKE_BUILD_ARGS --build ${MAKE_BUILD_PATH} --config ${MAKE_BUILD_TYPE})

  set(MAKE_EFFECTIVE_LIBRARIES)
  set(MAKE_ARTIFACTS)
  foreach(lib ${MAKE_LIBRARIES})
    if(lib MATCHES "^(WIN32|UNIX|APPLE)$")
      if(${lib})
        continue()
      else()
        list(POP_BACK MAKE_ARTIFACTS)
      endif()
    else()
      list(APPEND MAKE_EFFECTIVE_LIBRARIES ${lib})
      if(lib MATCHES "\\.")
        list(APPEND MAKE_ARTIFACTS ${MAKE_LIB_PATH}/${lib})
      else()
        list(APPEND MAKE_ARTIFACTS ${MAKE_LIB_PATH}/${CMAKE_STATIC_LIBRARY_PREFIX}${lib}${CMAKE_STATIC_LIBRARY_SUFFIX})
      endif()
    endif()
  endforeach()

  if(NOT MAKE_TARGETS)
    set(MAKE_TARGETS ${MAKE_EFFECTIVE_LIBRARIES})
  endif()

  foreach(target ${MAKE_TARGETS})
    list(APPEND MAKE_BUILD_ARGS --target ${target})
  endforeach()

  set(MAKE_EFFECTIVE_INCLUDES)
  foreach(include ${MAKE_INCLUDES})
    if(include STREQUAL ".")
      list(APPEND MAKE_EFFECTIVE_INCLUDES ${MAKE_CWD})
    else()
      list(APPEND MAKE_EFFECTIVE_INCLUDES ${MAKE_CWD}/${include})
    endif()
  endforeach()

  register_command(
    COMMENT "Building ${MAKE_TARGET}"
    TARGET ${MAKE_TARGET}
    TARGETS configure-${MAKE_TARGET}
    COMMAND ${CMAKE_COMMAND} ${MAKE_BUILD_ARGS}
    CWD ${MAKE_CWD}
    ARTIFACTS ${MAKE_ARTIFACTS}
  )

  if(MAKE_EFFECTIVE_INCLUDES)
    target_include_directories(${bun} PRIVATE ${MAKE_EFFECTIVE_INCLUDES})
    if(TARGET clone-${MAKE_TARGET} AND NOT BUN_LINK_ONLY)
      add_dependencies(${bun} clone-${MAKE_TARGET})
    endif()
  endif()

  # HACK: Workaround for duplicate symbols when linking mimalloc.o
  # >| duplicate symbol '_mi_page_queue_append(mi_heap_s*, mi_page_queue_s*, mi_page_queue_s*)' in:
  # >| mimalloc/CMakeFiles/mimalloc-obj.dir/src/static.c.o
  # >| ld: 287 duplicate symbols for architecture arm64
  if(NOT BUN_LINK_ONLY OR NOT MAKE_ARTIFACTS MATCHES "static.c.o")
    target_link_libraries(${bun} PRIVATE ${MAKE_ARTIFACTS})
  endif()

  if(BUN_LINK_ONLY)
    target_sources(${bun} PRIVATE ${MAKE_ARTIFACTS})
  endif()
endfunction()

# register_compiler_flag()
# Description:
#   Registers a compiler flag, similar to `add_compile_options()`, but has more validation and features.
# Arguments:
#   flags string[]     - The flags to register
#   DESCRIPTION string - The description of the flag
#   LANGUAGES string[] - The languages to register the flag (default: C, CXX)
#   TARGETS string[]   - The targets to register the flag (default: all)
function(register_compiler_flags)
  set(args DESCRIPTION)
  set(multiArgs LANGUAGES TARGETS)
  cmake_parse_arguments(COMPILER "" "${args}" "${multiArgs}" ${ARGN})

  if(NOT COMPILER_LANGUAGES)
    set(COMPILER_LANGUAGES C CXX)
  endif()

  set(COMPILER_FLAGS)
  foreach(flag ${COMPILER_UNPARSED_ARGUMENTS})
    if(flag STREQUAL "ON")
      continue()
    elseif(flag STREQUAL "OFF")
      list(POP_BACK COMPILER_FLAGS)
    elseif(flag MATCHES "^(-|/)")
      list(APPEND COMPILER_FLAGS ${flag})
    else()
      message(FATAL_ERROR "register_compiler_flags: Invalid flag: \"${flag}\"")
    endif()
  endforeach()

  foreach(target ${COMPILER_TARGETS})
    if(NOT TARGET ${target})
      message(FATAL_ERROR "register_compiler_flags: \"${target}\" is not a target")
    endif()
  endforeach()

  foreach(lang ${COMPILER_LANGUAGES})
    list(JOIN COMPILER_FLAGS " " COMPILER_FLAGS_STRING)

    if(NOT COMPILER_TARGETS)
      set(CMAKE_${lang}_FLAGS "${CMAKE_${lang}_FLAGS} ${COMPILER_FLAGS_STRING}" PARENT_SCOPE)
    endif()

    foreach(target ${COMPILER_TARGETS})
      set(${target}_CMAKE_${lang}_FLAGS "${${target}_CMAKE_${lang}_FLAGS} ${COMPILER_FLAGS_STRING}" PARENT_SCOPE)
    endforeach()
  endforeach()

  foreach(lang ${COMPILER_LANGUAGES})
    foreach(flag ${COMPILER_FLAGS})
      if(NOT COMPILER_TARGETS)
        add_compile_options($<$<COMPILE_LANGUAGE:${lang}>:${flag}>)
      endif()
      
      foreach(target ${COMPILER_TARGETS})
        get_target_property(type ${target} TYPE)
        if(type MATCHES "EXECUTABLE|LIBRARY")
          target_compile_options(${target} PRIVATE $<$<COMPILE_LANGUAGE:${lang}>:${flag}>)
        endif()
      endforeach()
    endforeach()
  endforeach()
endfunction()

function(register_compiler_definitions)
  
endfunction()

# register_linker_flags()
# Description:
#   Registers a linker flag, similar to `add_link_options()`.
# Arguments:
#   flags string[]     - The flags to register
#   DESCRIPTION string - The description of the flag
function(register_linker_flags)
  set(args DESCRIPTION)
  cmake_parse_arguments(LINKER "" "${args}" "" ${ARGN})

  foreach(flag ${LINKER_UNPARSED_ARGUMENTS})
    if(flag STREQUAL "ON")
      continue()
    elseif(flag STREQUAL "OFF")
      list(POP_FRONT LINKER_FLAGS)
    elseif(flag MATCHES "^(-|/)")
      list(APPEND LINKER_FLAGS ${flag})
    else()
      message(FATAL_ERROR "register_linker_flags: Invalid flag: \"${flag}\"")
    endif()
  endforeach()

  add_link_options(${LINKER_FLAGS})
endfunction()

# create_toolchain_file()
# Description:
#   Creates a CMake toolchain file.
# Arguments:
#   filename string - The path to create the toolchain file
#   target   string - The target to create the toolchain file
function(create_toolchain_file filename target)
  parse_path(filename)
  parse_target(target)

  set(lines)

  if(CMAKE_TOOLCHAIN_FILE)
    file(STRINGS ${CMAKE_TOOLCHAIN_FILE} lines)
    list(PREPEND lines "# Copied from ${CMAKE_TOOLCHAIN_FILE}")
  endif()

  list(APPEND lines "# Generated from ${CMAKE_CURRENT_FUNCTION} in ${CMAKE_CURRENT_LIST_FILE}")

  set(variables
    CMAKE_BUILD_TYPE
    CMAKE_EXPORT_COMPILE_COMMANDS
    CMAKE_COLOR_DIAGNOSTICS
    CMAKE_C_COMPILER
    CMAKE_C_COMPILER_LAUNCHER
    CMAKE_CXX_COMPILER
    CMAKE_CXX_COMPILER_LAUNCHER
    CMAKE_LINKER
    CMAKE_AR
    CMAKE_RANLIB
    CMAKE_STRIP
    CMAKE_OSX_SYSROOT
    CMAKE_OSX_DEPLOYMENT_TARGET
  )

  macro(append variable value)
    if(value MATCHES " ")
      list(APPEND lines "set(${variable} \"${value}\")")
    else()
      list(APPEND lines "set(${variable} ${value})")
    endif()
  endmacro()

  foreach(variable ${variables})
    if(DEFINED ${variable})
      append(${variable} ${${variable}})
    endif()
  endforeach()

  set(flags
    CMAKE_C_FLAGS
    CMAKE_CXX_FLAGS
    CMAKE_LINKER_FLAGS
  )

  foreach(flag ${flags})
    set(value)
    if(DEFINED ${flag})
      set(value "${${flag}}")
    endif()
    if(DEFINED ${target}_${flag})
      set(value "${value} ${${target}_${flag}}")
    endif()
    if(value)
      append(${flag} ${value})
    endif()
  endforeach()

  set(definitions
    CMAKE_DEFINITIONS
    ${target}_CMAKE_DEFINITIONS
  )

  foreach(definition ${definitions})
    foreach(entry ${${definition}})
      string(REGEX MATCH "^([^=]+)=(.*)$" match ${entry})
      if(NOT match)
        message(FATAL_ERROR "Invalid definition: ${entry}")
      endif()
      append(${CMAKE_MATCH_1} ${CMAKE_MATCH_2})
    endforeach()
  endforeach()

  list(JOIN lines "\n" lines)
  file(GENERATE OUTPUT ${filename} CONTENT "${lines}\n")
endfunction()

# --- Parsing functions ---

function(parse_semver value variable)
  string(REGEX MATCH "([0-9]+)\\.([0-9]+)\\.([0-9]+)" match "${value}")
  if(NOT match)
    message(FATAL_ERROR "${CMAKE_CURRENT_FUNCTION}: Invalid semver: \"${value}\"")
  endif()
  set(${variable}_VERSION "${CMAKE_MATCH_1}.${CMAKE_MATCH_2}.${CMAKE_MATCH_3}" PARENT_SCOPE)
  set(${variable}_VERSION_MAJOR "${CMAKE_MATCH_1}" PARENT_SCOPE)
  set(${variable}_VERSION_MINOR "${CMAKE_MATCH_2}" PARENT_SCOPE)
  set(${variable}_VERSION_PATCH "${CMAKE_MATCH_3}" PARENT_SCOPE)
endfunction()

function(parse_language variable)
  if(NOT ${variable})
    set(${variable} C CXX PARENT_SCOPE)
  endif()
  foreach(value ${${variable}})
    if(NOT value MATCHES "^(C|CXX)$")
      message(FATAL_ERROR "${CMAKE_CURRENT_FUNCTION}: Invalid language: \"${value}\"")
    endif()
  endforeach()
endfunction()

function(parse_target variable)
  foreach(value ${${variable}})
    if(NOT TARGET ${value})
      message(FATAL_ERROR "${CMAKE_CURRENT_FUNCTION}: Invalid target: \"${value}\"")
    endif()
  endforeach()
endfunction()

function(parse_path variable)
  foreach(value ${${variable}})
    if(NOT IS_ABSOLUTE ${value})
      message(FATAL_ERROR "${CMAKE_CURRENT_FUNCTION}: ${variable} is not an absolute path: \"${value}\"")
    endif()
    if(NOT ${value} MATCHES "^(${CWD}|${BUILD_PATH}|${CACHE_PATH}|${VENDOR_PATH})")
      message(FATAL_ERROR "${CMAKE_CURRENT_FUNCTION}: ${variable} is not in the source, build, cache, or vendor path: \"${value}\"")
    endif()
  endforeach()
endfunction()

function(parse_list variable output)
  set(items)
  macro(check_expression)
    if(DEFINED expression)
      if(NOT (${expression}))
        list(POP_BACK items)
      endif()
      unset(expression)
    endif()
  endmacro()
  foreach(item ${${variable}})
    if(item MATCHES "^(ON|OFF|AND|OR|NOT)$")
      set(expression ${expression} ${item})
    else()
      check_expression()
      list(APPEND items ${item})
    endif()
  endforeach()
  check_expression()
  set(${output} ${items} PARENT_SCOPE)
endfunction()

# --- New functions ---

# register_vendor_target()
# Description:
#   Registers a target that builds a vendor dependency.
# Arguments:
#   target string - The name of the target
function(register_vendor_target target)
  add_custom_target(${target})

  set(${target} ${target} PARENT_SCOPE)
  set(${target}_PATH ${VENDOR_PATH}/${target} PARENT_SCOPE)
  set(${target}_BUILD_PATH ${BUILD_PATH}/vendor/${target} PARENT_SCOPE)
  
  if(NOT TARGET vendor)
    add_custom_target(vendor)
  endif()
  add_dependencies(vendor ${target})
endfunction()

# register_cmake_project()
# Description:
#   Registers an external CMake project.
# Arguments:
#   TARGET       string   - The target to associate the project
#   CWD          string   - The working directory of the project
#   CMAKE_TARGET string[] - The CMake targets to build
#   CMAKE_PATH   string   - The path to the CMake project (default: CWD)
function(register_cmake_project)
  set(args TARGET CWD CMAKE_PATH LIBRARY_PATH)
  set(multiArgs CMAKE_TARGET)
  cmake_parse_arguments(PROJECT "" "${args}" "${multiArgs}" ${ARGN})

  parse_target(PROJECT_TARGET)
  
  if(NOT PROJECT_CWD)
    set(PROJECT_CWD ${${PROJECT_TARGET}_PATH})
  endif()
  parse_path(PROJECT_CWD)

  if(PROJECT_CMAKE_PATH)
    set(PROJECT_CMAKE_PATH ${PROJECT_CWD}/${PROJECT_CMAKE_PATH})
  else()
    set(PROJECT_CMAKE_PATH ${PROJECT_CWD})
  endif()
  parse_path(PROJECT_CMAKE_PATH)

  set(PROJECT_BUILD_PATH ${${PROJECT_TARGET}_BUILD_PATH})
  set(PROJECT_TOOLCHAIN_PATH ${PROJECT_BUILD_PATH}/CMakeLists-toolchain.txt)

  register_command(
    TARGET
      configure-${PROJECT_TARGET}
    COMMENT
      "Configuring ${PROJECT_TARGET}"
    COMMAND
      ${CMAKE_COMMAND}
        -G ${CMAKE_GENERATOR}
        -B ${PROJECT_BUILD_PATH}
        -S ${PROJECT_CMAKE_PATH}
        --toolchain ${PROJECT_TOOLCHAIN_PATH}
        --fresh
        -DCMAKE_POLICY_DEFAULT_CMP0077=NEW
    CWD
      ${PROJECT_CWD}
    SOURCES
      ${PROJECT_TOOLCHAIN_PATH}
    OUTPUTS
      ${PROJECT_BUILD_PATH}/CMakeCache.txt
  )

  if(TARGET clone-${PROJECT_TARGET})
    add_dependencies(configure-${PROJECT_TARGET} clone-${PROJECT_TARGET})
  endif()

  set(PROJECT_BUILD_ARGS --build ${PROJECT_BUILD_PATH})

  parse_list(PROJECT_CMAKE_TARGET PROJECT_CMAKE_TARGET)
  foreach(target ${PROJECT_CMAKE_TARGET})
    list(APPEND PROJECT_BUILD_ARGS --target ${target})
  endforeach()

  get_libraries(${PROJECT_TARGET} PROJECT_OUTPUTS)

  register_command(
    TARGET
      build-${PROJECT_TARGET}
    COMMENT
      "Building ${PROJECT_TARGET}"
    COMMAND
      ${CMAKE_COMMAND}
        ${PROJECT_BUILD_ARGS}
    CWD
      ${PROJECT_CWD}
    TARGETS
      configure-${PROJECT_TARGET}
    ARTIFACTS
      ${PROJECT_OUTPUTS}
  )

  add_dependencies(${PROJECT_TARGET} build-${PROJECT_TARGET})
  
  cmake_language(EVAL CODE "cmake_language(DEFER CALL create_toolchain_file ${PROJECT_TOOLCHAIN_PATH} ${PROJECT_TARGET})")
endfunction()

# register_cmake_definitions()
# Description:
#   Registers definitions, when compiling an external CMake project.
# Arguments:
#   TARGET string        - The target to register the definitions (if not defined, sets for all targets)
#   DESCRIPTION string   - The description of the definitions
#   definitions string[] - The definitions to register
function(register_cmake_definitions)
  set(args TARGET DESCRIPTION)
  cmake_parse_arguments(CMAKE "" "${args}" "" ${ARGN})

  parse_target(CMAKE_TARGET)
  parse_list(CMAKE_UNPARSED_ARGUMENTS CMAKE_EXTRA_DEFINITIONS)

  foreach(definition ${CMAKE_EXTRA_DEFINITIONS})
    string(REGEX MATCH "^([^=]+)=(.*)$" match ${definition})
    if(NOT match)
      message(FATAL_ERROR "${CMAKE_CURRENT_FUNCTION}: Invalid definition: \"${definition}\"")
    endif()
  endforeach()

  if(CMAKE_TARGET)
    set(${CMAKE_TARGET}_CMAKE_DEFINITIONS ${${CMAKE_TARGET}_CMAKE_DEFINITIONS} ${CMAKE_EXTRA_DEFINITIONS} PARENT_SCOPE)
  else()
    set(CMAKE_DEFINITIONS ${CMAKE_DEFINITIONS} ${CMAKE_EXTRA_DEFINITIONS} PARENT_SCOPE)
  endif()
endfunction()

# register_libraries()
# Description:
#   Registers libraries that are built from a target.
# Arguments:
#   TARGET    string   - The target that builds the libraries
#   PATH      string   - The relative path to the libraries
#   VARIABLE  string   - The variable to set to the libraries
#   libraries string[] - The libraries to register
function(register_libraries)
  set(args TARGET PATH VARIABLE)
  cmake_parse_arguments(LIBRARY "" "${args}" "" ${ARGN})

  parse_target(LIBRARY_TARGET)
  parse_list(LIBRARY_UNPARSED_ARGUMENTS LIBRARY_NAMES)

  if(LIBRARY_PATH)
    if(NOT IS_ABSOLUTE ${LIBRARY_PATH})
      set(LIBRARY_PATH ${${LIBRARY_TARGET}_BUILD_PATH}/${LIBRARY_PATH})
    endif()
  else()
    set(LIBRARY_PATH ${${LIBRARY_TARGET}_BUILD_PATH})
  endif()
  parse_path(LIBRARY_PATH)

  set(LIBRARY_PATHS)
  foreach(name ${LIBRARY_NAMES})
    if(name MATCHES "\\.")
      list(APPEND LIBRARY_PATHS ${LIBRARY_PATH}/${name})
    else()
      list(APPEND LIBRARY_PATHS ${LIBRARY_PATH}/${CMAKE_STATIC_LIBRARY_PREFIX}${name}${CMAKE_STATIC_LIBRARY_SUFFIX})
    endif()
  endforeach()

  set_property(TARGET ${LIBRARY_TARGET} PROPERTY OUTPUT ${LIBRARY_PATHS} APPEND)

  if(LIBRARY_VARIABLE)
    set(${LIBRARY_VARIABLE} ${LIBRARY_PATHS} PARENT_SCOPE)
  endif()
endfunction()

function(get_libraries target variable)
  get_target_property(libraries ${target} OUTPUT)
  if(libraries MATCHES "NOTFOUND")
    set(libraries)
  endif()
  set(${variable} ${libraries} PARENT_SCOPE)
endfunction()
