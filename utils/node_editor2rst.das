options gen2
options rtti = true

require daslib/fio
require daslib/rtti
require daslib/ast
require daslib/rst_comment
require daslib/rst
require daslib/regex
require daslib/regex_boost
require daslib/profiler_boost

// Pull in every documented module so RTTI can see them. The v1 thin-wrapper
// module (imgui_node_editor_boost) and the live-command module (no //! docs,
// covered by a hand-written sec_live_commands.rst) are intentionally excluded.
require imgui/imgui_node_editor_boost_v2
require imgui/imgui_editor_playwright
require imgui/imgui_node_editor_theme_daslang
require imgui/imgui_node_editor_app


def document_module_imgui_node_editor_boost_v2() {
    var mod = find_module("imgui_node_editor_boost_v2")
    // node_editor / node / pin / link / node_group are forward_argument widget
    // macros (no documentable render function survives expansion), so they auto-
    // list under "Call macros" and are explained in prose in the handmade intro.
    var groups <- array<DocGroup>(
        group_by_regex("Editor lifecycle",      mod, %regex~^(create_node_editor|destroy_node_editor|handle_to_editor|set_node_editor_id_tracking)$%%),
        group_by_regex("Node geometry & view",  mod, %regex~^(set_node_position|get_node_position|set_node_z_position|set_group_size|center_node_on_screen|navigate_to_selection|restore_node_state|get_ordered_node_ids)$%%),
        group_by_regex("Selection",             mod, %regex~^(get_selected_nodes|get_selected_links|select_node|select_link|clear_selection|get_action_context_nodes|get_action_context_links)$%%),
        group_by_regex("Link creation",         mod, %regex~^(begin_create|query_new_link|accept_new_item|reject_new_item|enqueue_new_link|clear_pending_links|show_new_node_drag|enqueue_new_node_drag)$%%),
        group_by_regex("Item deletion",         mod, %regex~^(begin_delete|query_deleted_link|query_deleted_node|accept_deleted_link|reject_deleted_link|accept_deleted_node|reject_deleted_node|enqueue_delete_node|enqueue_delete_link|clear_pending_deletes)$%%),
        group_by_regex("Context menus",         mod, %regex~^(with_suspended|show_node_context_menu|show_pin_context_menu|show_link_context_menu|show_background_context_menu)$%%),
        group_by_regex("Clipboard & shortcuts", mod, %regex~^(with_shortcuts|enable_shortcuts|accept_copy|accept_cut|accept_paste|accept_duplicate|accept_create_node|enqueue_shortcut|clear_pending_shortcuts)$%%),
        group_by_regex("Styling",               mod, %regex~^(with_style_var|with_style_color)$%%),
        group_by_regex("Drawing & hints",       mod, %regex~^(group_hint|with_node_background_drawlist)$%%),
        group_by_regex("Flow animation",        mod, %regex~^flow$%%),
        hide_group(group_by_regex("Finalizers", mod, %regex~^.*_finalize$%%)),
        hide_group(group_by_regex("Internal",   mod, %regex~^(_|priv_).*%%))
    )
    document("Boost v2 — the node-editor DSL: graph entities, link/delete queues, selection, context menus, shortcuts, styling", mod, "imgui_node_editor_boost_v2.rst", groups)
}

def document_module_imgui_editor_playwright() {
    var mod = find_module("imgui_editor_playwright")
    var groups <- array<DocGroup>(
        group_by_regex("Session",            mod, %regex~^ne_open$%%),
        group_by_regex("Actions",            mod, %regex~^(ne_select_node|ne_select_link|ne_clear_selection|ne_shortcut|ne_add_link|ne_delete_node|ne_delete_link|ne_move_node|ne_new_node_drag)$%%),
        group_by_regex("Snapshots & queries", mod, %regex~^(ne_snapshot|ne_node_count|ne_payload|ne_node|ne_node_exists|ne_node_selected)$%%),
        group_by_regex("Polling / await",    mod, %regex~^(ne_wait_widget|ne_wait_selected|ne_wait_payload_str|ne_wait_shortcut)$%%),
        hide_group(group_by_regex("Internal", mod, %regex~^(_|priv_).*%%))
    )
    document("Editor playwright — node-editor-aware test layer over imgui_playwright (EditorSession + ne_* helpers)", mod, "imgui_editor_playwright.rst", groups)
}

def document_module_imgui_node_editor_theme_daslang() {
    var mod = find_module("imgui_node_editor_theme_daslang")
    var groups <- array<DocGroup>(
        group_by_regex("Canvas theme", mod, %regex~^apply_daslang_node_editor_style$%%),
        hide_group(group_by_regex("Internal", mod, %regex~^(_|priv_).*%%))
    )
    document("Canvas theme — daslang-styled node-editor colors and style vars", mod, "imgui_node_editor_theme_daslang.rst", groups)
}

def document_module_imgui_node_editor_app() {
    var mod = find_module("imgui_node_editor_app")
    var groups <- array<DocGroup>(
        group_by_regex("App harness", mod, %regex~^with_node_editor(_recording)?_app$%%),
        hide_group(group_by_regex("Internal", mod, %regex~^(_|priv_).*%%))
    )
    document("App harness — with_node_editor_app + with_node_editor_recording_app, thin node-editor delegates over imgui_playwright's with_imgui_app / with_recording_app", mod, "imgui_node_editor_app.rst", groups)
}


// dasImguiNodeEditor repo root, derived from a loaded module's own source path
// so docs generate correctly under both -load_module (dev) and daspkg-install
// (CI), without assuming the package lives under <das_root>/modules/.
def dasimguinodeeditor_root() : string {
    let m = find_module("imgui_node_editor_boost_v2")
    assert(m != null, "imgui_node_editor_boost_v2 not loaded — cannot locate dasImguiNodeEditor root")
    return dir_name(dir_name(string(m.fileName)))
}

[export]
def main {
    disable_profiler(this_context())
    disable_profiler_log(this_context())
    ast_gc_guard() {
        let ne_doc = dasimguinodeeditor_root() + "/doc/source/stdlib"
        topic_root = "{ne_doc}/generated"
        handmade_root = ne_doc

        document_module_imgui_node_editor_boost_v2()
        document_module_imgui_editor_playwright()
        document_module_imgui_node_editor_theme_daslang()
        document_module_imgui_node_editor_app()
    }
}
