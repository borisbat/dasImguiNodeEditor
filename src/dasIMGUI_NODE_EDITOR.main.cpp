#include "daScript/misc/platform.h"
#include "daScript/ast/ast.h"
#include "daScript/ast/ast_interop.h"
#include "daScript/ast/ast_handle.h"
#include "daScript/ast/ast_typefactory_bind.h"
#include "daScript/simulate/bind_enum.h"
#include "dasIMGUI_NODE_EDITOR.h"
#include "need_dasIMGUI_NODE_EDITOR.h"
#include "aot_dasIMGUI_NODE_EDITOR.h"

namespace das {
    // Custom factory: create an editor with settings persistence disabled.
    // imgui-node-editor gates load/save on `if (SettingsFile)` (imgui_node_editor.cpp),
    // so nullptr disables the NodeEditor.json read/write entirely. The generated
    // binding exposes Config::SettingsFile as `const char*` (read-only from daslang),
    // so a setter-free factory is the supported way to disable persistence.
    ax::NodeEditor::EditorContext * CreateEditorNoSettings() {
        ax::NodeEditor::Config config;
        config.SettingsFile = nullptr;
        return ax::NodeEditor::CreateEditor(&config);
    }

    void Module_dasIMGUI_NODE_EDITOR::initAotAlias () {
    }

	void Module_dasIMGUI_NODE_EDITOR::initMain () {
        addExtern<DAS_BIND_FUN(CreateEditorNoSettings)>(*this, lib, "CreateEditorNoSettings",
            SideEffects::modifyExternal, "CreateEditorNoSettings");
        auto fnLink = findUniqueFunction("Link");
        fnLink->arg_init(3, new ExprConstFloat4(float4(1.0f)));
        // time to fix-up const & ImVec2 and const & ImVec4
        for ( auto & pfn : this->functions.each() ) {
            bool anyString = false;
            for ( auto & arg : pfn->arguments ) {
                if ( arg->type->constant && arg->type->ref && arg->type->dim.size()==0 ) {
                    if ( arg->type->baseType==Type::tFloat2 || arg->type->baseType==Type::tFloat4 ) {
                        arg->type->ref = false;
                    }
                }
                if ( arg->type->isString() && !arg->type->ref ) {
                    anyString = true;
                }
            }
            if ( anyString ) {
                pfn->needStringCast = true;
            }
        }
    }

	ModuleAotType Module_dasIMGUI_NODE_EDITOR::aotRequire ( TextWriter & tw ) const {
        // add your stuff here
        tw << "#include \"../modules/dasImguiNodeEditor/src/imgui_node_editor_stub.h\"\n";
        tw << "#include \"../modules/dasImguiNodeEditor/src/aot_dasIMGUI_NODE_EDITOR.h\"\n";
        tw << "#include \"daScript/simulate/bind_enum.h\"\n";
        tw << "#include \"../modules/dasImguiNodeEditor/src/dasIMGUI_NODE_EDITOR.enum.decl.cast.inc\"\n";
        // forward-decl the custom factory so AOT-generated C++ can call it
        tw << "namespace das { ax::NodeEditor::EditorContext * CreateEditorNoSettings(); }\n";
        // specifying AOT type, in this case direct cpp mode (and not hybrid mode)
        return ModuleAotType::cpp;
    }

}
