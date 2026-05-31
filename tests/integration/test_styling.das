options gen2
options indenting = 4
options no_unused_block_arguments = false
options no_unused_function_arguments = false

require dastest/testing_boost public
require imgui/imgui_node_editor_app public
require imgui/imgui_editor_playwright public

//! Headless regression for the styling tutorial. The decorative rails (node `color`,
//! with_style_var + with_style_color, pin pivot_alignment, with_node_background_drawlist)
//! carry no snapshot payload of their own, so the bar is the same as test_render_config:
//! the styled entity still registers + renders with a non-degenerate bbox and the brackets
//! don't crash. Node 3 is the showcase (NodeRounding var + amber NodeBorder color + accent
//! stripe drawn behind it); its input pin uses pivot_alignment; the link joins 12 -> 31.

let SUBJECT = "modules/dasImguiNodeEditor/examples/tutorial/styling.das"

[test]
def test_styling(t : T?) {
    with_node_editor_app(SUBJECT) $(d) {
        let s = ne_open(d, "MAIN_WIN/graph")
        t |> success(s.handle != uint64(0), "editor handle present")
        if (s.handle == uint64(0)) return

        var snap = ne_wait_widget(s, "node_3", 15.0f)
        t |> success(snap != null, "styled output node (node_3) rendered")
        if (snap == null) return

        // with_style_var (NodeRounding) + with_style_color (NodeBorder) compose around node 3:
        // it still registers with a non-degenerate bbox (the brackets didn't crash the build).
        var n3 = ne_node(snap, s, 3)
        let bx = n3?["payload"]?["bbox"]
        let w = (bx?["z"] ?? 0.0) - (bx?["x"] ?? 0.0)
        let h = (bx?["w"] ?? 0.0) - (bx?["y"] ?? 0.0)
        t |> success(w > 0.0 && h > 0.0, "styled node bbox non-degenerate ({w} x {h})")

        // pivot_alignment on the input pin — the pin still nests + renders under node 3.
        t |> success(widget_exists(snap, "{s.canvas}/node_3/pin_31"),
                     "input pin with pivot_alignment renders (node_3/pin_31)")

        // The tinted source node and the link both render — the full styled graph is intact.
        t |> success(widget_exists(snap, "{s.canvas}/node_1"), "tinted source node renders (node_1)")
        var snapLink = ne_wait_widget(s, "link_100", 6.0f)
        t |> success(snapLink != null, "link 12 -> 31 renders (link_100)")
        if (snapLink != null) {
            // Pin ids are unique per editor — assert the link resolves to the intended pins
            // (12 = node 1's output, 31 = node 3's input). A pin-id collision would silently
            // merge pins and misroute this; the explicit endpoints catch that.
            var l = find_widget(snapLink, "{s.canvas}/link_100")
            t |> equal(l?["payload"]?["from_pin"] ?? -1, 12, "link leaves node 1's output pin 12")
            t |> equal(l?["payload"]?["to_pin"] ?? -1, 31, "link arrives at node 3's input pin 31")
        }
    }
}
