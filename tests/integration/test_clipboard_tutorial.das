options gen2
options indenting = 4
options no_unused_block_arguments = false
options no_unused_function_arguments = false

require dastest/testing_boost public
require imgui/imgui_node_editor_app public
require imgui/imgui_editor_playwright public
require daslib/json public
require daslib/json_boost public

//! Headless regression for the clipboard tutorial. Drives the edit shortcuts with REAL
//! Ctrl chords: a synthetic click selects a node AND focuses the canvas (the editor's
//! shortcut gate is IsFocused), then Ctrl+D duplicates it and Ctrl+C / Ctrl+V copy+paste
//! it. The node count confirms the app's clipboard recreated the topology.
//!
//! imgui-node-editor checks io.KeyCtrl directly, so the chord is Ctrl on every platform
//! (NOT Cmd on macOS — unlike an ImGui InputText). Distinct from test_clipboard.das /
//! test_shortcuts.das, which drive shader_graph through the ne_shortcut INJECTION rail;
//! this proves the real key chord routes through the same accept_<kind> path end to end.

let SUBJECT = "modules/dasImguiNodeEditor/examples/tutorial/clipboard.das"

[test]
def test_clipboard_tutorial(t : T?) {
    with_node_editor_app(SUBJECT) $(d) {
        let s = ne_open(d, "MAIN_WIN/graph")
        t |> success(s.handle != uint64(0), "editor handle present")
        if (s.handle == uint64(0)) return
        let canvas = s.canvas

        t |> success(ne_wait_widget(s, "node_1", 15.0f) != null, "seed graph rendered")
        t |> equal(ne_node_count(s), 2, "2 seed nodes initially")

        // ---- duplicate: click node A (selects + focuses), Ctrl+D ----
        click(d, "{canvas}/node_1/NODE_TITLE[1]")
        wait_for_mouse_idle(d)
        post_command(d, "imgui_key_chord", JV((mods = ["Ctrl"], key = "D")))
        t |> success(wait_for_key_idle(d, 4.0f), "Ctrl+D chord completes")
        var dup = ne_wait_widget(s, "node_200", 6.0f)
        t |> success(dup != null, "Ctrl+D duplicated the selected node (clone node_200 spawned)")
        t |> equal(ne_node_count(s), 3, "node count 2 -> 3 after Ctrl+D")

        // ---- copy + paste: click node B, Ctrl+C then Ctrl+V ----
        click(d, "{canvas}/node_2/NODE_TITLE[2]")
        wait_for_mouse_idle(d)
        post_command(d, "imgui_key_chord", JV((mods = ["Ctrl"], key = "C")))
        t |> success(wait_for_key_idle(d, 4.0f), "Ctrl+C chord completes")
        post_command(d, "imgui_key_chord", JV((mods = ["Ctrl"], key = "V")))
        t |> success(wait_for_key_idle(d, 4.0f), "Ctrl+V chord completes")
        var pasted = ne_wait_widget(s, "node_210", 6.0f)
        t |> success(pasted != null, "Ctrl+C then Ctrl+V pasted the copied node (node_210 spawned)")
        t |> equal(ne_node_count(s), 4, "node count 3 -> 4 after paste")
    }
}
