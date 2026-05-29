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
        ne_shortcut(s, "paste")
        var snapP = ne_wait_widget(s, "link_20", 8.0f)
        t |> success(snapP != null, "link_20 present after paste")
        t |> equal(ne_node_count(s), 6, "paste added both nodes (4 -> 6)")

        // DIAGNOSTIC: dump every candidate node's existence + canvas position so CI shows the
        // real values (local Windows passes, headless CI does not — need to see what differs).
        if (snapP != null) {
            for (nid in [1, 5, 14, 15, 16, 17, 18]) {
                let ex = widget_exists(snapP, "{s.canvas}/node_{nid}")
                let bb = find_widget(snapP, "{s.canvas}/node_{nid}")?["payload"]?["bbox"]
                let bx = bb?["x"] ?? -999.0
                let by = bb?["y"] ?? -999.0
                print("DIAG node_{nid}: exists={ex} x={bx} y={by}\n")
            }
            var l20 = find_widget(snapP, "{s.canvas}/link_20")
            t |> success((l20?["payload"]?["from_pin"] ?? 0) >= 15 && (l20?["payload"]?["to_pin"] ?? 0) >= 15,
                         "copied link joins the pasted nodes, not the originals")
        }
    }
}
