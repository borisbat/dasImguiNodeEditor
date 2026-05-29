options gen2
options indenting = 4
options no_unused_block_arguments = false
options no_unused_function_arguments = false

require dastest/testing_boost public
require imgui/imgui_node_editor_app public
require imgui/imgui_editor_playwright public

//! Integration smoke for the node-editor topology-edit loop.
//!
//! Drives `examples/node-editor/shader_graph.das` through the project-agnostic live
//! commands (via the imgui_editor_playwright `ne_*` helpers) and asserts on the snapshot —
//! proving the editor is both drivable and observable end-to-end:
//!   1. The editor canvas + sample graph render (nodes/links keyed by id).
//!   2. The app-owned editor handle is exposed in the node_editor payload.
//!   3. `ne_add_link` injects a link that the app's create handler commits.
//!   4. `ne_delete_link` / `ne_delete_node` drop items (node delete cascades its pins +
//!      touching links).
//! Kept to a single editor session with a lean command count to stay well under the
//! Windows libhv ~16-POST/subprocess ceiling.

let SHADER_GRAPH = "modules/dasImguiNodeEditor/examples/node-editor/shader_graph.das"

[test]
def test_topology_loop(t : T?) {
    with_node_editor_app(SHADER_GRAPH) $(d) {
        // Gate 1+2: canvas rendered → sample graph present, handle exposed.
        let s = ne_open(d, "MAIN_WIN/shader_graph")
        t |> success(s.handle != uint64(0), "editor canvas rendered + handle present")
        if (s.handle == uint64(0)) return
        var snap0 = ne_snapshot(s)
        t |> success(ne_node_exists(snap0, s, 5), "sample node_5 present")
        t |> success(widget_exists(snap0, "{s.canvas}/link_11"), "sample link_11 present")

        // Gate 3: add_link injects pin2->pin7 (output->input); app commits link_14.
        ne_add_link(s, 2, 7)
        var snap1 = ne_wait_widget(s, "link_14", 5.0f)
        t |> success(snap1 != null, "ne_add_link created link_14")
        if (snap1 != null) {
            var l14 = find_widget(snap1, "{s.canvas}/link_14")
            t |> equal(l14?["payload"]?["from_pin"] ?? -1, 2, "link_14.from_pin == 2")
            t |> equal(l14?["payload"]?["to_pin"] ?? -1, 7, "link_14.to_pin == 7")
        }

        // Gate 4a: delete_link drops link_11.
        ne_delete_link(s, 11)
        var snap2 = wait_until_sec(d, 5.0f) $(var sn) {
            return !widget_exists(sn, "{s.canvas}/link_11")
        }
        t |> success(snap2 != null, "ne_delete_link removed link_11")

        // Gate 4b: delete_node drops node_5 and cascades its pins.
        ne_delete_node(s, 5)
        var snap3 = wait_until_sec(d, 5.0f) $(var sn) {
            return !ne_node_exists(sn, s, 5)
        }
        t |> success(snap3 != null, "ne_delete_node removed node_5")
        if (snap3 != null) {
            t |> success(!widget_exists(snap3, "{s.canvas}/node_5/pin_6"),
                         "node_5's pin_6 cascaded out")
        }
    }
}
