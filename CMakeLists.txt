cmake_minimum_required(VERSION 3.5)
project(fsd
        VERSION 3.99.0
        LANGUAGES C CXX)

add_executable(fsd
        fsd/attributes.h
        fsd/authenticate.c
        fsd/authenticate.h
        fsd/certificate.cpp
        fsd/certificate.h
        fsd/client.cpp
        fsd/client.h
        fsd/clinterface.cpp
        fsd/clinterface.h
        fsd/cluser.cpp
        fsd/cluser.h
        fsd/config.cpp
        fsd/config.h
        fsd/fsd.cpp
        fsd/fsd.h
        fsd/fsdpaths.h
        fsd/global.h
        fsd/interface.cpp
        fsd/interface.h
        fsd/main.cpp
        fsd/manage.cpp
        fsd/manage.h
        fsd/mm.cpp
        fsd/mm.h
        fsd/process.cpp
        fsd/process.h
        fsd/protocol.h
        fsd/server.cpp
        fsd/server.h
        fsd/servinterface.cpp
        fsd/servinterface.h
        fsd/servuser.cpp
        fsd/servuser.h
        fsd/support.cpp
        fsd/support.h
        fsd/sysinterface.cpp
        fsd/sysinterface.h
        fsd/sysuser.cpp
        fsd/sysuser.h
        fsd/user.cpp
        fsd/user.h
        fsd/wprofile.cpp
        fsd/wprofile.h)


find_package(SQLite3 REQUIRED)


# Jsoncpp und Geographic hinzufügen
include_directories(/usr/include/jsoncpp)
target_link_libraries(fsd sqlite3 jsoncpp GeographicLib)





set_property(TARGET fsd PROPERTY CXX_STANDARD 20)
set_property(TARGET fsd PROPERTY CXX_STANDARD_REQUIRED ON)

option(FSD_ENABLE_WARNINGS "Enable extra compiler warnings" ON)
option(FSD_ENABLE_WERROR   "Treat warnings as errors" OFF)
option(FSD_ENABLE_SANITIZERS "Enable ASan/UBSan (Debug/RelWithDebInfo recommended)" OFF)

if(FSD_ENABLE_WARNINGS)
  if(CMAKE_CXX_COMPILER_ID MATCHES "GNU|Clang")
    target_compile_options(fsd PRIVATE
      -Wall -Wextra -Wpedantic
      -Wshadow -Wconversion -Wsign-conversion
      -Wformat=2 -Wundef
      -Wnon-virtual-dtor
    )
  endif()
endif()

if(FSD_ENABLE_WERROR)
  if(CMAKE_CXX_COMPILER_ID MATCHES "GNU|Clang")
    target_compile_options(fsd PRIVATE -Werror)
  endif()
endif()

if(FSD_ENABLE_SANITIZERS)
  if(CMAKE_CXX_COMPILER_ID MATCHES "GNU|Clang")
    target_compile_options(fsd PRIVATE -fsanitize=address,undefined -fno-omit-frame-pointer)
    target_link_options(fsd PRIVATE -fsanitize=address,undefined)
  endif()
endif()


