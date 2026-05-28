options gen2
options indenting = 4
options no_unused_block_arguments = false
options no_unused_function_arguments = false

require dastest/testing_boost public
require imgui/imgui_node_editor_app public
require daslib/json public
require daslib/json_boost public

//! Integration smoke for the node-editor topology-edit loop.
//!
//! Drives `examples/node-editor/shader_graph.das` through the project-agnostic
//! live commands and asserts on the snapshot — proving the editor is both
//! drivable and observable end-to-end:
//!   1. The editor canvas + sample graph render (nodes/links keyed by id).
//!   2. The app-owned editor handle is exposed in the node_editor payload.
//!   3. `add_link_cmd` injects a link that the app's create handler commits.
//!   4. `delete_link_cmd` / `delete_node_cmd` drop items (node delete cascades
//!      its pins + touching links).
//! Kept to a single editor session with a lean command count to stay well under
//! the Windows libhv ~16-POST/subprocess ceiling.

let SHADER_GRAPH = "modules/dasImguiNodeEditor/examples/node-editor/shader_graph.das"

[test]
def test_topology_loop(t : T?) {
    with_node_editor_app(SHADER_GRAPH) $(d) {
        // Gate 1: editor canvas rendered → sample graph present.
        var snap0 = wait_for_widget(d, "MAIN_WIN/shader_graph", 15.0f)
        t |> success(snap0 != null, "editor canvas rendered")
        if (snap0 == null) return
        t |> success(widget_exists(snap0, "MAIN_WIN/shader_graph/node_5"), "sample node_5 present")
        t |> success(widget_exists(snap0, "MAIN_WIN/shader_graph/link_11"), "sample link_11 present")

        // Gate 2: app-owned editor handle exposed in the node_editor payload.
        let handle = find_widget(snap0, "MAIN_WIN/shader_graph")?["payload"]?["handle"] ?? uint64(0)
        t |> success(handle != uint64(0), "editor handle present in snapshot")

        // Gate 3: add_link_cmd injects pin2->pin7 (output->input); app commits link_14.
        post_command(d, "add_link_cmd", JV((editor = handle, from = 2, to = 7)))
        var snap1 = wait_for_widget(d, "MAIN_WIN/shader_graph/link_14", 5.0f)
        t |> success(snap1 != null, "add_link_cmd created link_14")
        if (snap1 != null) {
            var l14 = find_widget(snap1, "MAIN_WIN/shader_graph/link_14")
            t |> equal(l14?["payload"]?["from_pin"] ?? -1, 2, "link_14.from_pin == 2")
            t |> equal(l14?["payload"]?["to_pin"] ?? -1, 7, "link_14.to_pin == 7")
        }

        // Gate 4a: delete_link_cmd drops link_11.
        post_command(d, "delete_link_cmd", JV((editor = handle, id = 11)))
        var snap2 = wait_until_sec(d, 5.0f) $(var s) {
            return !widget_exists(s, "MAIN_WIN/shader_graph/link_11")
        }
        t |> success(snap2 != null, "delete_link_cmd removed link_11")

        // Gate 4b: delete_node_cmd drops node_5 and cascades its pins.
        post_command(d, "delete_node_cmd", JV((editor = handle, id = 5)))
        var snap3 = wait_until_sec(d, 5.0f) $(var s) {
            return !widget_exists(s, "MAIN_WIN/shader_graph/node_5")
        }
        t |> success(snap3 != null, "delete_node_cmd removed node_5")
        if (snap3 != null) {
            t |> success(!widget_exists(snap3, "MAIN_WIN/shader_graph/node_5/pin_6"),
                         "node_5's pin_6 cascaded out")
        }
    }
}
