options gen2
options indenting = 4
options no_unused_block_arguments = false
options no_unused_function_arguments = false

require dastest/testing_boost public
require imgui/imgui_node_editor_app public
require daslib/json public
require daslib/json_boost public

//! Integration coverage for clipboard/edit shortcuts (duplicate + copy/paste).
//!
//! Shortcuts are key-chord-driven, so we drive them deterministically through the injection
//! rail (shortcut_cmd → enqueue_shortcut), which replays through the SAME accept_<kind>
//! handler a real Ctrl+C/V/D hits. Each accept records the action on the editor
//! (node_editor_payload.last_shortcut_*), so the snapshot confirms the event fired and how
//! many objects it targeted; the node count confirms the app's clipboard recreated topology.
//! Selection is cleared between phases (clear_selection_cmd) so each action's context is
//! exactly the one node we select. Sample graph: 4 nodes (Mul = node_5, Texture = node_1).

let SHADER_GRAPH = "modules/dasImguiNodeEditor/examples/node-editor/shader_graph.das"

def private wait_for_action(d : ImguiApp; action : string) : JsonValue? {
    return wait_until_sec(d, 5.0f) $(var s) {
        return (find_widget(s, "MAIN_WIN/shader_graph")?["payload"]?["last_shortcut_action"] ?? "") == action
    }
}

[test]
def test_shortcuts(t : T?) {
    with_node_editor_app(SHADER_GRAPH) $(d) {
        var snap0 = wait_for_widget(d, "MAIN_WIN/shader_graph/node_5", 15.0f)
        t |> success(snap0 != null, "sample graph rendered")
        if (snap0 == null) return
        let handle = find_widget(snap0, "MAIN_WIN/shader_graph")?["payload"]?["handle"] ?? uint64(0)
        t |> success(handle != uint64(0), "editor handle present")
        t |> equal(post_command(d, "ordered_node_ids_cmd", JV((editor = handle)))?["count"] ?? -1, 4,
                   "4 sample nodes initially")

        // ---- duplicate: select Mul (node_5), inject Ctrl+D → clone added ----
        post_command(d, "clear_selection_cmd", JV((editor = handle)))
        post_command(d, "select_node_cmd", JV((editor = handle, id = 5, on = true)))
        post_command(d, "shortcut_cmd", JV((editor = handle, kind = "duplicate")))
        var snapD = wait_for_action(d, "duplicate")
        t |> success(snapD != null, "duplicate served (telemetry last_shortcut_action == duplicate)")
        t |> success((find_widget(snapD, "MAIN_WIN/shader_graph")?["payload"]?["last_shortcut_context_size"] ?? 0) >= 1,
                     "duplicate action context held the selected node")
        t |> equal(post_command(d, "ordered_node_ids_cmd", JV((editor = handle)))?["count"] ?? -1, 5,
                   "duplicate added one node (4 -> 5)")

        // ---- copy + paste: select Texture (node_1), inject Ctrl+C then Ctrl+V ----
        post_command(d, "clear_selection_cmd", JV((editor = handle)))
        post_command(d, "select_node_cmd", JV((editor = handle, id = 1, on = true)))
        post_command(d, "shortcut_cmd", JV((editor = handle, kind = "copy")))
        t |> success(wait_for_action(d, "copy") != null, "copy served (telemetry == copy)")

        post_command(d, "shortcut_cmd", JV((editor = handle, kind = "paste")))
        t |> success(wait_for_action(d, "paste") != null, "paste served (telemetry == paste)")
        t |> equal(post_command(d, "ordered_node_ids_cmd", JV((editor = handle)))?["count"] ?? -1, 6,
                   "paste recreated the copied node (5 -> 6)")
    }
}
