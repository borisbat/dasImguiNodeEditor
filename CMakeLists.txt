# dasImguiNodeEditor builds two ways from a single CMakeLists:
#  - included from a daslang superbuild (the ADD_MODULE_* macros exist): the module
#    links statically into the host app via the convention path (dasImgui provides
#    imgui headers + the libDasModuleImgui target) -- how an embedding app and the
#    fat-man static-link example consume it.
#  - configured directly (top-level project, DASLANG_DIR set): the standalone
#    .shared_module build CI, the daspkg index, and -load_module consumers run on.
IF(NOT COMMAND ADD_MODULE_CPP)
    cmake_minimum_required(VERSION 3.16)
    project(dasImguiNodeEditor CXX C)
ENDIF()

IF((NOT DAS_IMGUI_NODE_EDITOR_INCLUDED) AND ((NOT ${DAS_IMGUI_NODE_EDITOR_DISABLED}) OR (NOT DEFINED DAS_IMGUI_NODE_EDITOR_DISABLED)))
SET(DAS_IMGUI_NODE_EDITOR_INCLUDED TRUE)
MESSAGE(STATUS "dasImguiNodeEditor module included.")

SET(DAS_IMGUI_NODE_EDITOR_DIR ${CMAKE_CURRENT_LIST_DIR})

IF(COMMAND ADD_MODULE_CPP)
    # superbuild: dasImgui's CMakeLists (included earlier -- the modules glob is
    # alphabetical) already set imgui_INCLUDE_DIR and created libDasModuleImgui
    IF(NOT DEFINED imgui_INCLUDE_DIR)
        MESSAGE(FATAL_ERROR "dasImguiNodeEditor superbuild: dasImgui must be included first (imgui_INCLUDE_DIR unset)")
    ENDIF()
    SET(DAS_IMGUI_DIR ${CMAKE_CURRENT_LIST_DIR}/../dasImgui)
ELSE()
    # DASLANG_DIR must point to the daslang SDK root
    if(NOT DEFINED DASLANG_DIR)
        message(FATAL_ERROR "DASLANG_DIR must be set to the daslang SDK root")
    endif()

# Locate dasImgui (sibling module under same modules/ parent)
get_filename_component(MODULES_DIR "${DAS_IMGUI_NODE_EDITOR_DIR}" DIRECTORY)
SET(DAS_IMGUI_DIR "${MODULES_DIR}/dasImgui")
if(NOT EXISTS "${DAS_IMGUI_DIR}/src/cb_dasIMGUI.h")
    message(FATAL_ERROR "dasImgui not found at ${DAS_IMGUI_DIR}. Install it first: daspkg install github.com/borisbat/dasImgui")
endif()

# imgui headers (from dasImgui's FetchContent download)
if(EXISTS "${DAS_IMGUI_DIR}/imgui/imgui.h")
    SET(imgui_INCLUDE_DIR "${DAS_IMGUI_DIR}/imgui")
else()
    message(FATAL_ERROR "imgui headers not found at ${DAS_IMGUI_DIR}/imgui/. Build dasImgui first.")
endif()

# dasModuleImgui import library (from dasImgui build)
if(WIN32)
    SET(DAS_MODULE_IMGUI_LIB "${DAS_IMGUI_DIR}/dasModuleImgui.lib")
    if(NOT EXISTS "${DAS_MODULE_IMGUI_LIB}")
        message(FATAL_ERROR "dasModuleImgui.lib not found at ${DAS_IMGUI_DIR}/. Build dasImgui first.")
    endif()
endif()
ENDIF()

# imgui-node-editor (vendored, patched for imgui 1.90.6 compatibility)
SET(NODE_EDITOR_INCLUDE_DIR ${DAS_IMGUI_NODE_EDITOR_DIR}/imgui-node-editor)

# imgui-node-editor source files
SET(DAS_NODE_EDITOR_SRC
    ${NODE_EDITOR_INCLUDE_DIR}/crude_json.cpp
    ${NODE_EDITOR_INCLUDE_DIR}/imgui_canvas.cpp
    ${NODE_EDITOR_INCLUDE_DIR}/imgui_node_editor.cpp
    ${NODE_EDITOR_INCLUDE_DIR}/imgui_node_editor_api.cpp
)

# binding source files
SET(DAS_NODE_EDITOR_BIND_SRC
    ${DAS_IMGUI_NODE_EDITOR_DIR}/src/dasIMGUI_NODE_EDITOR.cpp
    ${DAS_IMGUI_NODE_EDITOR_DIR}/src/dasIMGUI_NODE_EDITOR.main.cpp
    ${DAS_IMGUI_NODE_EDITOR_DIR}/src/dasIMGUI_NODE_EDITOR.func_1.cpp
    ${DAS_IMGUI_NODE_EDITOR_DIR}/src/dasIMGUI_NODE_EDITOR.func_2.cpp
    ${DAS_IMGUI_NODE_EDITOR_DIR}/src/dasIMGUI_NODE_EDITOR.func_3.cpp
    ${DAS_IMGUI_NODE_EDITOR_DIR}/src/dasIMGUI_NODE_EDITOR.func_4.cpp
    ${DAS_IMGUI_NODE_EDITOR_DIR}/src/dasIMGUI_NODE_EDITOR.func_5.cpp
    ${DAS_IMGUI_NODE_EDITOR_DIR}/src/dasIMGUI_NODE_EDITOR.func_6.cpp
)


IF(COMMAND ADD_MODULE_CPP)
    # ===== daslang superbuild: static-embed =====
    # `require imgui/<name>` -> modules/dasImguiNodeEditor/daslib/<name>.das; the glob IS the
    # .das_module register_native_path list (file stem == module name throughout).
    ADD_MODULE_CPP(dasIMGUI_NODE_EDITOR)
    FILE(GLOB _dasImguiNodeEditor_das_files "${DAS_IMGUI_NODE_EDITOR_DIR}/daslib/*.das")
    FOREACH(_f ${_dasImguiNodeEditor_das_files})
        GET_FILENAME_COMPONENT(_n "${_f}" NAME_WE)
        ADD_MODULE_DAS(imgui daslib ${_n})
    ENDFOREACH()

    IF(EMSCRIPTEN)
        ADD_DAS_STATIC_MODULE_LIB(libDasModuleImguiNodeEditor ${DAS_NODE_EDITOR_BIND_SRC} ${DAS_NODE_EDITOR_SRC})
        SET(_dasImguiNodeEditor_targets libDasModuleImguiNodeEditor)
    ELSE()
        ADD_MODULE_LIB(libDasModuleImguiNodeEditor dasModuleImguiNodeEditor ${DAS_NODE_EDITOR_BIND_SRC} ${DAS_NODE_EDITOR_SRC})
        SET(_dasImguiNodeEditor_targets libDasModuleImguiNodeEditor dasModuleImguiNodeEditor)
    ENDIF()
    FOREACH(_t ${_dasImguiNodeEditor_targets})
        TARGET_INCLUDE_DIRECTORIES(${_t} PRIVATE
            ${imgui_INCLUDE_DIR}
            ${NODE_EDITOR_INCLUDE_DIR}
            ${DAS_IMGUI_DIR}/src
            ${DAS_IMGUI_NODE_EDITOR_DIR}/src
        )
        TARGET_COMPILE_DEFINITIONS(${_t} PRIVATE IMGUI_DISABLE_OBSOLETE_FUNCTIONS=1)
        SETUP_CPP11(${_t})
    ENDFOREACH()
    # imgui core symbols come from dasImgui's libs
    TARGET_LINK_LIBRARIES(libDasModuleImguiNodeEditor PUBLIC libDasModuleImgui)
    IF(NOT EMSCRIPTEN)
        TARGET_LINK_LIBRARIES(dasModuleImguiNodeEditor PUBLIC dasModuleImgui)
    ENDIF()
ELSE()
IF(WIN32)
    SET(NE_PUBLIC_ATTR "__declspec\(dllexport\)")
    SET(IMGUI_IMPORT_ATTR "__declspec\(dllimport\)")
ELSE()
    SET(NE_PUBLIC_ATTR "__attribute__\(\(visibility\(\"default\"\)\)\)")
    SET(IMGUI_IMPORT_ATTR "")
ENDIF()

# dasModuleImguiNodeEditor.shared_module
add_library(dasModuleImguiNodeEditor SHARED ${DAS_NODE_EDITOR_BIND_SRC} ${DAS_NODE_EDITOR_SRC})
target_compile_features(dasModuleImguiNodeEditor PRIVATE cxx_std_17)
target_compile_definitions(dasModuleImguiNodeEditor PRIVATE
    DAS_MOD_EXPORTS DAS_ENABLE_DLL=1
    IMGUI_DISABLE_OBSOLETE_FUNCTIONS=1
    IMGUI_API=${IMGUI_IMPORT_ATTR}
    $<$<CONFIG:Release>:DAS_NO_ASSERTIONS>
    $<$<CONFIG:MinSizeRel>:DAS_NO_ASSERTIONS>
    $<$<CONFIG:RelWithDebInfo>:DAS_NO_ASSERTIONS>
)
target_include_directories(dasModuleImguiNodeEditor PRIVATE
    ${DASLANG_DIR}/include
    ${imgui_INCLUDE_DIR}
    ${NODE_EDITOR_INCLUDE_DIR}
    ${DAS_IMGUI_DIR}/src
    ${DAS_IMGUI_NODE_EDITOR_DIR}/src
)
if(WIN32)
    if(EXISTS "${DASLANG_DIR}/lib/Release/libDaScriptDyn.lib")
        target_link_libraries(dasModuleImguiNodeEditor PRIVATE
            ${DASLANG_DIR}/lib/Release/libDaScriptDyn.lib
            ${DASLANG_DIR}/lib/Release/libDaScriptDyn_runtime.lib
            ${DAS_MODULE_IMGUI_LIB}
        )
    else()
        target_link_libraries(dasModuleImguiNodeEditor PRIVATE
            ${DASLANG_DIR}/lib/libDaScriptDyn.lib
            ${DASLANG_DIR}/lib/libDaScriptDyn_runtime.lib
            ${DAS_MODULE_IMGUI_LIB}
        )
    endif()
elseif(APPLE)
    # daslang names the dynamic runtime liblibDaScriptDyn.dylib (CMake prepends
    # 'lib' to the libDaScriptDyn target) — mirror dasImgui's CMakeLists.
    target_link_libraries(dasModuleImguiNodeEditor PRIVATE
        ${DASLANG_DIR}/lib/liblibDaScriptDyn.dylib
        ${DASLANG_DIR}/lib/liblibDaScriptDyn_runtime.dylib
        ${DAS_IMGUI_DIR}/dasModuleImgui.shared_module
    )
else()
    target_link_libraries(dasModuleImguiNodeEditor PRIVATE
        ${DASLANG_DIR}/lib/liblibDaScriptDyn.so
        ${DASLANG_DIR}/lib/liblibDaScriptDyn_runtime.so
        ${DAS_IMGUI_DIR}/dasModuleImgui.shared_module
    )
endif()
if(MSVC)
    target_compile_options(dasModuleImguiNodeEditor PRIVATE /wd4005 /bigobj)
else()
    # daslang runtime libs are built -fno-rtti for optimized configs; match the
    # ABI (mirror dasImgui's SETUP_OPTIONS) or the .shared_module mislinks.
    target_compile_options(dasModuleImguiNodeEditor PRIVATE
        $<$<CONFIG:Release>:-fno-rtti>
        $<$<CONFIG:MinSizeRel>:-fno-rtti>
        $<$<CONFIG:RelWithDebInfo>:-fno-rtti>)
endif()
set_target_properties(dasModuleImguiNodeEditor PROPERTIES
    SUFFIX ".shared_module"
    PREFIX ""
    RUNTIME_OUTPUT_DIRECTORY_RELEASE "${DAS_IMGUI_NODE_EDITOR_DIR}"
    LIBRARY_OUTPUT_DIRECTORY "${DAS_IMGUI_NODE_EDITOR_DIR}"
)
ENDIF() # superbuild / standalone

ENDIF() # DAS_IMGUI_NODE_EDITOR_INCLUDED guard
