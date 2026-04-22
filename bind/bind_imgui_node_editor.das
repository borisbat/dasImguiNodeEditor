options gen2
require cbind/cbind_boost
require daslib/fio
require daslib/defer
require daslib/strings_boost

class ImguiNodeEditorGen : CppGenBind {
    override include_parse_file = false
    override func_to_stdout = false
    override generate_constant_decl = true
    imgui_skip_func : table<string; bool>
    def ImguiNodeEditorGen {
        bind_root = "{get_das_root()}/modules/dasImguiNodeEditor/src"
        bind_module = "dasIMGUI_NODE_EDITOR"
        bind_das_module = "imgui_node_editor"
        let pfn = "imgui_node_editor.h"
        let pfp = "{get_das_root()}/modules/dasImguiNodeEditor/imgui-node-editor/"
        let i_imgui = "{get_das_root()}/modules/dasImgui/imgui/"
        let args <- array<string>(
            "-xc++-header",
            "-std=c++1z",
            "-I{get_full_file_name(i_imgui)}",
            "-I{get_full_file_name(pfp)}",
            "-DIMGUI_DISABLE_OBSOLETE_FUNCTIONS",
            "-D_ALLOW_COMPILER_AND_STL_VERSION_MISMATCH=1"
        )
        func_per_chunk = 20
        init_args(pfn, pfp, args)
        init_rename()
        setDefaultFiles()
        openAllFiles()
    }
    def override get_module_temp_fn : string {
        return ", imgui_node_editorTempFn"
    }
    def init_rename {
        aot_alias <- {
            "ImVec2"                 => true,
            "ImVec4"                 => true,
            "ImColor"                => true,
            "ax::NodeEditor::NodeId" => true,
            "ax::NodeEditor::LinkId" => true,
            "ax::NodeEditor::PinId"  => true
        }
        alias2type <- {
            "ImGuiCol"                  => "ImGuiCol_",
            "ImGuiCond"                 => "ImGuiCond_",
            "ImGuiDataType"             => "ImGuiDataType_",
            "ImGuiDir"                  => "ImGuiDir_",
            "ImGuiNavInput"             => "ImGuiNavInput_",
            "ImGuiMouseButton"          => "ImGuiMouseButton_",
            "ImGuiMouseCursor"          => "ImGuiMouseCursor_",
            "ImGuiSortDirection"        => "ImGuiSortDirection_",
            "ImGuiStyleVar"             => "ImGuiStyleVar_",
            "ImGuiTableBgTarget"        => "ImGuiTableBgTarget_",
            "ImDrawFlags"               => "ImDrawFlags_",
            "ImDrawListFlags"           => "ImDrawListFlags_",
            "ImFontAtlasFlags"          => "ImFontAtlasFlags_",
            "ImGuiBackendFlags"         => "ImGuiBackendFlags_",
            "ImGuiButtonFlags"          => "ImGuiButtonFlags_",
            "ImGuiColorEditFlags"       => "ImGuiColorEditFlags_",
            "ImGuiConfigFlags"          => "ImGuiConfigFlags_",
            "ImGuiComboFlags"           => "ImGuiComboFlags_",
            "ImGuiDragDropFlags"        => "ImGuiDragDropFlags_",
            "ImGuiFocusedFlags"         => "ImGuiFocusedFlags_",
            "ImGuiHoveredFlags"         => "ImGuiHoveredFlags_",
            "ImGuiInputTextFlags"       => "ImGuiInputTextFlags_",
            "ImGuiKeyModFlags"          => "ImGuiKeyModFlags_",
            "ImGuiPopupFlags"           => "ImGuiPopupFlags_",
            "ImGuiSelectableFlags"      => "ImGuiSelectableFlags_",
            "ImGuiSliderFlags"          => "ImGuiSliderFlags_",
            "ImGuiTabBarFlags"          => "ImGuiTabBarFlags_",
            "ImGuiTabItemFlags"         => "ImGuiTabItemFlags_",
            "ImGuiTableFlags"           => "ImGuiTableFlags_",
            "ImGuiTableColumnFlags"     => "ImGuiTableColumnFlags_",
            "ImGuiTableRowFlags"        => "ImGuiTableRowFlags_",
            "ImGuiTreeNodeFlags"        => "ImGuiTreeNodeFlags_",
            "ImGuiViewportFlags"        => "ImGuiViewportFlags_",
            "ImGuiWindowFlags"          => "ImGuiWindowFlags_",
            "ImGuiChildFlags"           => "ImGuiChildFlags_"
        }
        local_type_names <- {
            "ImGuiTableColumnSortSpecs" => true,
            "Config"                    => true
        }
        imgui_skip_func <- {
            "ImGui::TextUnformatted"                      => true,
            "ImGuiTextFilter::PassFilter"                 => true,
            "ImGuiTextBuffer::append"                     => true,
            "ImGuiInputTextCallbackData::InsertChars"     => true,
            "ImGui::CalcTextSize"                         => true,
            "ImGui::SetNextWindowSizeConstraints"         => true,
            "ImDrawList::AddText"                         => true
        }
        for (v in values(alias2type)) {
            enums_with_flags.insert(v, true)
        }
    }
    def override skip_anyFunction(var c : CXCursor; isMethod : bool) {
        if (AnyGenBind`skip_anyFunction(self, c, isMethod)) {
            return true
        }
        let function_name = namespace_name(string(clang_getCursorSpelling(c)))
        if (imgui_skip_func |> key_exists(function_name)) {
            to_log(LOG_INFO, "skipping IMGUI_NODE_EDITOR blocked function {function_name} at {clang_getCursorLocationDescription(c)}")
            return true
        }
        return false
    }
    def override isArgByValue(name : string) {
        return true
    }
    def override generateModuleHPrefix {
        module_h_file |> fwrite("#include \"cb_dasIMGUI.h\"\n")
        module_h_file |> fwrite("#include \"cb_dasIMGUI_NODE_EDITOR.h\"\n")
        module_h_file |> fwrite("#include \"need_dasIMGUI.h\"\n")
    }
}

[export]
def main {
    var cgb = new ImguiNodeEditorGen()
    defer <| $() {
        unsafe {
            delete cgb
        }
    }
    cgb.require_modules <- [ "imgui" ]
    cgb.already_defined <- {
        "ImGuiContext" => true
    }
    cgb->generate()
    cgb->genCMakeDecl("DAS_IMGUI_NODE_EDITOR_BIND")
}
