include(Macros)

find_command(
  VARIABLE
    BUN_EXECUTABLE
  COMMAND
    bun
  PATHS
    $ENV{HOME}/.bun/bin
  VERSION
    >=1.1.0
)

if(CMAKE_HOST_WIN32)
  setx(ESBUILD_EXECUTABLE ${CWD}/node_modules/.bin/esbuild.exe)
else()
  setx(ESBUILD_EXECUTABLE ${CWD}/node_modules/.bin/esbuild)
endif()

if(CMAKE_COLOR_DIAGNOSTICS)
  set(ESBUILD_ARGS --color)
endif()

register_command(
  COMMAND
    ${BUN_EXECUTABLE}
      install
      --frozen-lockfile
  SOURCES
    ${CWD}/package.json
  OUTPUTS
    ${ESBUILD_EXECUTABLE}
  BYPRODUCTS
    ${CWD}/bun.lockb
)