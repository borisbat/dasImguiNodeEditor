options gen2
options _comment_hygiene = true
options indenting = 4
options no_unused_block_arguments = false
options no_unused_function_arguments = false

require dastest/testing_boost public
require imgui/imgui_node_editor_app public
require imgui/imgui_editor_playwright public
require daslib/json public
require daslib/json_boost public

//! Headless regression for the navigation tutorial. NavigateToContent (Fit All) and
//! navigate_to_selection (Frame Selection) are VIEW ops — a node's SCREEN-space bbox shifts
//! while its canvas position holds. center_node_on_screen is NOT a view op: despite the
//! name it MOVES the node to the view center (upstream CenterNodeOnScreen translates the
//! node bounds). This test asserts both: Fit All moves node 3's screen center (the graph is
//! seeded wide, node 3 at canvas 1180,560), and Center #1 moves node 1's CANVAS bbox.

let SUBJECT = "modules/dasImguiNodeEditor/examples/tutorial/navigation.das"

def widget_center(var snap : JsonValue?; ident : string) : float2 {
    let b = find_widget(snap, ident)?["bbox"]
    return float2(((b?["x"] ?? 0.0f) + (b?["z"] ?? 0.0f)) * 0.5f,
                  ((b?["y"] ?? 0.0f) + (b?["w"] ?? 0.0f)) * 0.5f)
}

[test]
def test_navigation(t : T?) {
    with_node_editor_app(SUBJECT) $(d) {
        let s = ne_open(d, "MAIN_WIN/graph")
        t |> success(s.handle != uint64(0), "editor handle present")
        if (s.handle == uint64(0)) return

        var snap = ne_wait_widget(s, "node_3", 15.0f)
        t |> success(snap != null, "far node (node_3) rendered at the default view")
        if (snap == null) return

        let before = widget_center(snap, "{s.canvas}/node_3")
        t |> success(before.x > 0.0, "node_3 screen center resolved ({before.x}, {before.y})")

        // Real click on the toolbar's "Fit All" → NavigateToContent fits the whole graph.
        click(d, "MAIN_WIN/FIT_ALL")
        var moved = wait_until_sec(d, 6.0f) $(var sn) {
            let c = widget_center(sn, "{s.canvas}/node_3")
            let dx = c.x - before.x
            let dy = c.y - before.y
            return dx * dx + dy * dy > 400.0f   // shifted > 20px in screen space
        }
        t |> success(moved != null, "Fit All moved the view (node_3 screen center shifted > 20px)")

        // The footgun: center_node_on_screen MOVES node 1 (not the view). Assert its
        // canvas-space bbox changes after a real "Center #1" click.
        var snap2 = ne_wait_widget(s, "node_1", 5.0f)
        t |> success(snap2 != null, "node_1 present before Center #1")
        if (snap2 == null) return
        let n1_canvas_before = write_json(widget_payload_field(snap2, "{s.canvas}/node_1", "canvas_bbox"))
        click(d, "MAIN_WIN/CENTER_FIRST")
        var node_moved = wait_until_sec(d, 6.0f) $(var sn) {
            let now = widget_payload_field(sn, "{s.canvas}/node_1", "canvas_bbox")
            return now != null && write_json(now) != n1_canvas_before
        }
        t |> success(node_moved != null, "Center #1 MOVED node 1's canvas bbox (it relocates the node, not the view)")
    }
}
