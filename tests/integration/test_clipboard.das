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

        // Paste — wait until link_20 AND both pasted nodes have laid out (non-zero bbox width
        // ⇒ their canvas position is committed). The link draws a frame BEFORE the node bboxes
        // settle, so gating on link_20 alone reads pos=0 on slower cadences (macOS CI).
        ne_shortcut(s, "paste")
        var snapP = wait_until_sec(d, 6.0f) $(var snap) {
            if (!widget_exists(snap, "{s.canvas}/link_20")) return false
            let other = widget_exists(snap, "{s.canvas}/node_16") ? 16 : 18
            let bA = find_widget(snap, "{s.canvas}/node_14")?["payload"]?["bbox"]
            let bB = find_widget(snap, "{s.canvas}/node_{other}")?["payload"]?["bbox"]
            let wA = (bA?["z"] ?? 0.0) - (bA?["x"] ?? 0.0)
            let wB = (bB?["z"] ?? 0.0) - (bB?["x"] ?? 0.0)
            return wA > 0.0 && wB > 0.0
        }
        t |> success(snapP != null, "paste laid out both nodes + the internal link (link_20)")
        t |> equal(ne_node_count(s), 6, "paste added both nodes (4 -> 6)")

        if (snapP != null) {
            // The copied link connects two PASTED pins (fresh ids >= 15, not the originals <= 10).
            var l20 = find_widget(snapP, "{s.canvas}/link_20")
            t |> success((l20?["payload"]?["from_pin"] ?? 0) >= 15 && (l20?["payload"]?["to_pin"] ?? 0) >= 15,
                         "copied link joins the pasted nodes, not the originals")

            // Relative layout preserved: the two pasted nodes (node_14 + node_16-or-18) keep the
            // Texture<->Multiply gap (~300px x, ~50px y) instead of stacking.
            var other = 16
            if (!ne_node_exists(snapP, s, 16)) {
                other = 18
            }
            let b14 = ne_node(snapP, s, 14)?["payload"]?["bbox"]
            let bO = ne_node(snapP, s, other)?["payload"]?["bbox"]
            var dx = (b14?["x"] ?? 0.0) - (bO?["x"] ?? 0.0)
            var dy = (b14?["y"] ?? 0.0) - (bO?["y"] ?? 0.0)
            if (dx < 0.0) {
                dx = -dx
            }
            if (dy < 0.0) {
                dy = -dy
            }
            t |> success(dx > 250.0 && dx < 350.0, "pasted nodes keep the ~300px x-gap (not stacked) — got {dx}")
            t |> success(dy > 20.0 && dy < 80.0, "pasted nodes keep the ~50px y-gap — got {dy}")
        }
    }
}
