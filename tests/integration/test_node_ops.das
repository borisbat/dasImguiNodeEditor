options gen2
options indenting = 4
options no_unused_block_arguments = false
options no_unused_function_arguments = false

require dastest/testing_boost public
require imgui/imgui_node_editor_app public
require imgui/imgui_editor_playwright public

//! Integration coverage for node ops: z-order (observable) + ordered-node enumerate.
//!
//! set_node_z_position folds z into node()'s snapshot payload — set node_5's z and watch it
//! surface. ne_node_count enumerates the editor's draw order (matches the sample graph's
//! node count). Lean (2 commands + 1 wait-loop) for the Windows libhv ~16-POST ceiling. The
//! transient view actions (center_node_on_screen, navigate_to_selection, restore_node_state)
//! carry no observable state — covered by the demo toolbar + compile, not asserted here.

let SHADER_GRAPH = "modules/dasImguiNodeEditor/examples/node-editor/shader_graph.das"

[test]
def test_node_ops(t : T?) {
    with_node_editor_app(SHADER_GRAPH) $(d) {
        let s = ne_open(d, "MAIN_WIN/shader_graph")
        t |> success(s.handle != uint64(0), "editor handle present")
        if (s.handle == uint64(0)) return
        var snap0 = ne_wait_widget(s, "node_5", 15.0f)
        t |> success(snap0 != null, "sample node_5 rendered")
        if (snap0 == null) return

        // z defaults to 0 and folds into node_payload.
        t |> equal(ne_node(snap0, s, 5)?["payload"]?["z"] ?? -1.0, 0.0, "node_5 default z == 0")

        // set_node_z_cmd → observable in a later snapshot.
        post_command(d, "set_node_z_cmd", JV((editor = s.handle, id = 5, z = 5.0)))
        var snapZ = wait_until_sec(d, 5.0f) $(var sn) {
            return (ne_node(sn, s, 5)?["payload"]?["z"] ?? 0.0) >= 4.9
        }
        t |> success(snapZ != null, "set_node_z_cmd: node_5 z surfaced in node_payload")

        // Enumerate draw order — the sample graph has 4 nodes.
        t |> equal(ne_node_count(s), 4, "ordered_node_ids: 4 sample nodes")
    }
}
