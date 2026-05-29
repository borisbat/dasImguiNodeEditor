options gen2
options indenting = 4
options no_unused_block_arguments = false
options no_unused_function_arguments = false

require dastest/testing_boost public
require imgui/imgui_node_editor_app public
require daslib/json public
require daslib/json_boost public

//! Integration coverage for the node_group (group / comment box) entity.
//!
//! A group is a first-class telemetry entity, not a fire-and-forget call: node_group()
//! registers it (path "node_group_{id}", distinct from a node's "node_{id}") with a
//! lazily-built payload, so its bounds stay snapshot-observable for frames to come.
//! Spawns a group via the app's spawn_group_cmd (a fresh app leaves next_id == 14, so
//! the group is deterministically id 14), then asserts the entity registers, its payload
//! id, a non-degenerate bbox (a group is geometrically a node), and that its title text
//! nests under it.

let SHADER_GRAPH = "modules/dasImguiNodeEditor/examples/node-editor/shader_graph.das"

[test]
def test_node_group(t : T?) {
    with_node_editor_app(SHADER_GRAPH) $(d) {
        var snap0 = wait_for_widget(d, "MAIN_WIN/shader_graph", 15.0f)
        t |> success(snap0 != null, "editor canvas rendered")
        if (snap0 == null) return
        let handle = find_widget(snap0, "MAIN_WIN/shader_graph")?["payload"]?["handle"] ?? uint64(0)
        t |> success(handle != uint64(0), "editor handle present")
        t |> success(!widget_exists(snap0, "MAIN_WIN/shader_graph/node_group_14"),
                     "no group present initially")

        // Fresh app → the sample graph leaves next_id == 14, so the spawned group is 14.
        let resp = post_command(d, "spawn_group_cmd",
                                JV((title = "Inputs", x = 60.0, y = 60.0, w = 260.0, h = 300.0)))
        t |> equal(resp?["id"] ?? -1, 14, "spawn_group_cmd returned group id 14")

        var snapG = wait_for_widget(d, "MAIN_WIN/shader_graph/node_group_14", 6.0f)
        t |> success(snapG != null, "group registered as node_group_14 (distinct kind from node)")
        if (snapG != null) {
            var g14 = find_widget(snapG, "MAIN_WIN/shader_graph/node_group_14")
            t |> equal(g14?["payload"]?["id"] ?? -1, 14, "group payload id == 14")
            // A group is geometrically a node — its bbox should be non-degenerate.
            let bx = g14?["payload"]?["bbox"]
            let w = (bx?["z"] ?? 0.0) - (bx?["x"] ?? 0.0)
            let h = (bx?["w"] ?? 0.0) - (bx?["y"] ?? 0.0)
            t |> success(w > 0.0 && h > 0.0, "group bbox is non-degenerate ({w} x {h})")
            // The group title renders as a child text under the group's path.
            t |> success(widget_exists(snapG, "MAIN_WIN/shader_graph/node_group_14/GROUP_TITLE[14]"),
                         "group title text nests under the group")
        }
    }
}
