cmake_minimum_required(VERSION 3.16)
project(dasImguiNodeEditor CXX C)

# DASLANG_DIR must point to the daslang SDK root
if(NOT DEFINED DASLANG_DIR)
    message(FATAL_ERROR "DASLANG_DIR must be set to the daslang SDK root")
endif()

SET(DAS_IMGUI_NODE_EDITOR_DIR ${CMAKE_CURRENT_LIST_DIR})

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
    target_link_libraries(dasModuleImguiNodeEditor PRIVATE
        ${DASLANG_DIR}/lib/Release/libDaScriptDyn.lib
        ${DAS_MODULE_IMGUI_LIB}
    )
else()
    target_link_libraries(dasModuleImguiNodeEditor PRIVATE
        ${DASLANG_DIR}/lib/libDaScriptDyn.so
        ${DAS_IMGUI_DIR}/dasModuleImgui.shared_module
    )
endif()
if(MSVC)
    target_compile_options(dasModuleImguiNodeEditor PRIVATE /wd4005 /bigobj)
endif()
set_target_properties(dasModuleImguiNodeEditor PROPERTIES
    SUFFIX ".shared_module"
    PREFIX ""
    RUNTIME_OUTPUT_DIRECTORY_RELEASE "${DAS_IMGUI_NODE_EDITOR_DIR}"
    LIBRARY_OUTPUT_DIRECTORY "${DAS_IMGUI_NODE_EDITOR_DIR}"
)
