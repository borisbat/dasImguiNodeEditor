options gen2
options indenting = 4
options no_unused_block_arguments = false
options no_unused_function_arguments = false

require dastest/testing_boost public
require imgui/imgui_node_editor_app public
require imgui/imgui_editor_playwright public

//! Headless regression for the groups tutorial. node_group is a first-class telemetry
//! entity (path "node_group_{id}", distinct from a node's "node_{id}") with a lazily-built
//! payload, so its bounds stay snapshot-observable. The tutorial seeds one group (id 1) with
//! two nodes (10, 20) on top of it. Asserts the group registers, its payload id + a
//! non-degenerate bbox, that its title nests under it, and that group_hint's unconditional
//! loop didn't crash the build (the two regular nodes still render).

let SUBJECT = "modules/dasImguiNodeEditor/examples/tutorial/groups.das"

[test]
def test_groups(t : T?) {
    with_node_editor_app(SUBJECT) $(d) {
        let s = ne_open(d, "MAIN_WIN/graph")
        t |> success(s.handle != uint64(0), "editor handle present")
        if (s.handle == uint64(0)) return

        var snap = ne_wait_widget(s, "node_group_1", 15.0f)
        t |> success(snap != null, "group registered as node_group_1 (distinct kind from node)")
        if (snap == null) return

        var g1 = find_widget(snap, "{s.canvas}/node_group_1")
        t |> equal(g1?["payload"]?["id"] ?? -1, 1, "group payload id == 1")
        // A group is geometrically a node — its bbox should be non-degenerate.
        let bx = g1?["payload"]?["bbox"]
        let w = (bx?["z"] ?? 0.0) - (bx?["x"] ?? 0.0)
        let h = (bx?["w"] ?? 0.0) - (bx?["y"] ?? 0.0)
        t |> success(w > 0.0 && h > 0.0, "group bbox is non-degenerate ({w} x {h})")
        // The group title renders as a child text under the group's path.
        t |> success(widget_exists(snap, "{s.canvas}/node_group_1/GROUP_TITLE"),
                     "group title text nests under the group")

        // The two ordinary nodes seeded inside the group still render (group_hint loop OK).
        t |> success(widget_exists(snap, "{s.canvas}/node_10"), "node 10 renders on top of the group")
        t |> success(widget_exists(snap, "{s.canvas}/node_20"), "node 20 renders on top of the group")
    }
}
