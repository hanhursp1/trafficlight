cmake_minimum_required(VERSION 3.13)

# initialize pico-sdk from GIT
# (note this can come from environment, CMake cache etc)
#set(PICO_SDK_FETCH_FROM_GIT on)

# pico_sdk_import.cmake is a single file copied from this SDK
# note: this must happen before project()
include(pico_sdk_import.cmake)

project(trafficlight)
# initialize the Raspberry Pi Pico SDK
pico_sdk_init()

set(Imports imports.cmake)

if(EXISTS "../${Imports}")

# add program file(s)
file(GLOB NimSources build/nimcache/*.c)

# Suppress gcc warnings for nim-generated files
set_source_files_properties(${NimSources} PROPERTIES COMPILE_OPTIONS "-w")

add_executable(trafficlight ${NimSources})

# Add directory containing this CMakeLists file to include search path.
# This is required so that the nimbase.h file is found. Other headers
# required for a project can also be placed here.
target_include_directories(trafficlight PUBLIC ${CMAKE_CURRENT_LIST_DIR})

include(${Imports}) # Include our generated file
link_imported_libs(trafficlight) # call our generated function to import all libs we're using

target_link_libraries(hardware_flash)

# enable usb output, disable uart output
pico_enable_stdio_usb(trafficlight 1)
pico_enable_stdio_uart(trafficlight 0)

# create map/bin/hex/uf2 file etc.
pico_add_extra_outputs(trafficlight)

# add url via pico_set_program_url
pico_set_program_url(trafficlight 1)
endif()

