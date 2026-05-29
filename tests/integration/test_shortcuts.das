options gen2
options indenting = 4
options no_unused_block_arguments = false
options no_unused_function_arguments = false

require dastest/testing_boost public
require imgui/imgui_node_editor_app public
require imgui/imgui_editor_playwright public

//! Integration coverage for clipboard/edit shortcuts (duplicate + copy/paste).
//!
//! Shortcuts are key-chord-driven, so we drive them deterministically through the injection
//! rail (ne_shortcut → shortcut_cmd → enqueue_shortcut), which replays through the SAME
//! accept_<kind> handler a real Ctrl+C/V/D hits. Each accept records the action on the editor
//! (ne_wait_shortcut polls last_shortcut_action); the node count confirms the app's clipboard
//! recreated topology. Selection is cleared between phases so each action's context is exactly
//! the node we select. Sample graph: 4 nodes (Mul = node_5, Texture = node_1).

let SHADER_GRAPH = "modules/dasImguiNodeEditor/examples/node-editor/shader_graph.das"

[test]
def test_shortcuts(t : T?) {
    with_node_editor_app(SHADER_GRAPH) $(d) {
        let s = ne_open(d, "MAIN_WIN/shader_graph")
        t |> success(s.handle != uint64(0), "editor handle present")
        if (s.handle == uint64(0)) return
        t |> success(ne_wait_widget(s, "node_5", 15.0f) != null, "sample graph rendered")
        t |> equal(ne_node_count(s), 4, "4 sample nodes initially")

        // ---- duplicate: select Mul (node_5), inject Ctrl+D → clone added ----
        ne_clear_selection(s)
        ne_select_node(s, 5, true)
        ne_shortcut(s, "duplicate")
        var snapD = ne_wait_shortcut(s, "duplicate")
        t |> success(snapD != null, "duplicate served (telemetry last_shortcut_action == duplicate)")
        t |> success((ne_payload(snapD, s)?["last_shortcut_context_size"] ?? 0) >= 1,
                     "duplicate action context held the selected node")
        t |> equal(ne_node_count(s), 5, "duplicate added one node (4 -> 5)")

        // ---- copy + paste: select Texture (node_1), inject Ctrl+C then Ctrl+V ----
        ne_clear_selection(s)
        ne_select_node(s, 1, true)
        ne_shortcut(s, "copy")
        t |> success(ne_wait_shortcut(s, "copy") != null, "copy served (telemetry == copy)")

        ne_shortcut(s, "paste")
        t |> success(ne_wait_shortcut(s, "paste") != null, "paste served (telemetry == paste)")
        t |> equal(ne_node_count(s), 6, "paste recreated the copied node (5 -> 6)")
    }
}
