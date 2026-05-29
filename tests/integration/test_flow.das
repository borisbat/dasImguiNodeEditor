options gen2
options indenting = 4
options no_unused_block_arguments = false
options no_unused_function_arguments = false

require dastest/testing_boost public
require imgui/imgui_node_editor_app public
require daslib/json public
require daslib/json_boost public

//! Smoke for flow_cmd / the flow() wrapper. Flow is a transient visual pulse with
//! NO snapshot telemetry by design (it's an animation, not link state), so this
//! proves the command + wrapper run end-to-end — the handle resolves, FlowDirection
//! maps, the SetCurrentEditor bracket is safe, nothing crashes — and that flowing a
//! link does not mutate topology. The animation itself is visual-only and unasserted.

let SHADER_GRAPH = "modules/dasImguiNodeEditor/examples/node-editor/shader_graph.das"

[test]
def test_flow(t : T?) {
    with_node_editor_app(SHADER_GRAPH) $(d) {
        var snap0 = wait_for_widget(d, "MAIN_WIN/shader_graph", 15.0f)
        t |> success(snap0 != null, "editor canvas rendered")
        if (snap0 == null) return
        let handle = find_widget(snap0, "MAIN_WIN/shader_graph")?["payload"]?["handle"] ?? uint64(0)
        t |> success(handle != uint64(0), "editor handle present")

        // Flow an existing sample link — wrapper runs, command returns a response.
        let resp = post_command(d, "flow_cmd", JV((editor = handle, id = 11)))
        t |> success(resp != null, "flow_cmd returned a response")

        // Flow is non-destructive: link_11 still present, editor still rendering.
        var snap1 = wait_for_widget(d, "MAIN_WIN/shader_graph/link_11", 5.0f)
        t |> success(snap1 != null, "link_11 intact after flow (no crash, no topology change)")
    }
}
