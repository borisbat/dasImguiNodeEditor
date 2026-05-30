options gen2
options indenting = 4
options no_unused_block_arguments = false
options no_unused_function_arguments = false

require dastest/testing_boost public
require imgui/imgui_node_editor_app public
require imgui/imgui_editor_playwright public

//! Integration coverage for clipboard fidelity: copy preserves INTERNAL links + RELATIVE
//! layout (not a bare node-kind stack).
//!
//! Selects the sample graph's Texture (node_1) + Multiply (node_5) — joined by link_11
//! (pin2 -> pin6) — then copy + paste. The paste must recreate BOTH nodes (count 4 -> 6),
//! the internal link remapped onto the pasted pins (link_20, endpoints among the fresh pins
//! >= 15), and the two pasted nodes must keep their ~300px x / ~50px y separation rather than
//! landing on top of each other. (link_12 / link_13 touch unselected nodes, so they are NOT
//! copied — only links internal to the selection travel.)

let SHADER_GRAPH = "modules/dasImguiNodeEditor/examples/node-editor/shader_graph.das"

[test]
def test_clipboard(t : T?) {
    with_node_editor_app(SHADER_GRAPH) $(d) {
        let s = ne_open(d, "MAIN_WIN/shader_graph")
        t |> success(s.handle != uint64(0), "editor handle present")
        if (s.handle == uint64(0)) return
        t |> success(ne_wait_widget(s, "node_5", 15.0f) != null, "sample graph rendered")
        t |> equal(ne_node_count(s), 4, "4 sample nodes initially")

        // Select the Texture + Multiply pair (joined by link_11), then copy.
        ne_clear_selection(s)
        ne_select_node(s, 1, true)
        ne_select_node(s, 5, true)
        ne_shortcut(s, "copy")
        t |> success(ne_wait_shortcut(s, "copy") != null, "copy served")

        // Paste — wait for the SETTLED paste: link_20 up and the two pasted nodes' relative
        // layout preserved (~300px x / ~50px y apart, not stacked). We read bbox.x/.y, which is
        // GetNodePosition (canvas space) — set by SetNodePosition and reliable even though the
        // nodes, pasted at the headless cursor (0,0), land off-canvas and get culled (so their
        // GetNodeSize stays 0). Position commit lags the link draw by a frame (read 0 on macOS),
        // so we gate the poll on the final geometry: snapP != null IS the layout-preserved proof,
        // with no half-committed transient able to slip through.
        // Paste — poll until link_20 is up and the two pasted nodes have committed their
        // relative layout (~300px x / ~50px y apart, not stacked). Positions are seeded in-frame
        // on first render, so they settle a frame or two after the paste shortcut; gating on the
        // final geometry makes snapP != null itself the layout-preserved proof. An uncommitted
        // node reads imgui-node-editor's un-laid-out sentinel (~INT_MIN), which the band rejects,
        // so the poll only passes once BOTH nodes hold real, correctly-separated positions.
        ne_shortcut(s, "paste")
        var snapP = wait_until_sec(d, 8.0f) $(var snap) {
            if (!widget_exists(snap, "{s.canvas}/link_20")) return false
            let other = widget_exists(snap, "{s.canvas}/node_16") ? 16 : 18
            // canvas_bbox carries the editor canvas-space rect (GetNodePosition); payload.bbox
            // is now screen-space, so the canvas-layout spacing check reads canvas_bbox.
            let bA = find_widget(snap, "{s.canvas}/node_14")?["payload"]?["canvas_bbox"]
            let bB = find_widget(snap, "{s.canvas}/node_{other}")?["payload"]?["canvas_bbox"]
            var dx = (bA?["x"] ?? 0.0) - (bB?["x"] ?? 0.0)
            var dy = (bA?["y"] ?? 0.0) - (bB?["y"] ?? 0.0)
            if (dx < 0.0) {
                dx = -dx
            }
            if (dy < 0.0) {
                dy = -dy
            }
            return dx > 250.0 && dx < 350.0 && dy > 20.0 && dy < 80.0
        }
        t |> success(snapP != null,
                     "paste preserved layout: pasted nodes ~300px x / ~50px y apart (not stacked), link_20 up")
        t |> equal(ne_node_count(s), 6, "paste added both nodes (4 -> 6)")

        if (snapP != null) {
            // The copied link connects two PASTED pins (fresh ids >= 15, not the originals <= 10).
            var l20 = find_widget(snapP, "{s.canvas}/link_20")
            t |> success((l20?["payload"]?["from_pin"] ?? 0) >= 15 && (l20?["payload"]?["to_pin"] ?? 0) >= 15,
                         "copied link joins the pasted nodes, not the originals")
        }
    }
}
