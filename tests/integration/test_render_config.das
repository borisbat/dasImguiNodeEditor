options gen2
options indenting = 4
options no_unused_block_arguments = false
options no_unused_function_arguments = false

require dastest/testing_boost public
require imgui/imgui_node_editor_app public
require imgui/imgui_editor_playwright public

//! Integration coverage for the non-telemetry rendering rails: with_style_var +
//! with_style_color compose on a node, pin pivot_scale, and group_hint's active path.
//!
//! These are decorative wrappers with no snapshot payload of their own, so the bar is "the
//! styled entity still registers + renders, and the bracket doesn't crash" — the same class
//! of regression as the with_node_background_drawlist mid-body crash. The sample graph leaves
//! the ColorOutput node at id 9 (styled: NodeRounding via with_style_var + amber NodeBorder
//! via with_style_color) and the Mul node at id 5 with its output pin at id 8 (pivot_scale).
//! group_hint only fires when zoomed out (view.Scale <= 0.75), so we spawn an oversized group,
//! NavigateToContent to force a fit-zoom past the threshold (confirmed via editor_dims.zoom,
//! which is InvScale = 1/scale, so zoomed-out reads >= 1.333), and assert the group still
//! renders — exercising BeginGroupHint -> draw -> EndGroupHint live.

let SHADER_GRAPH = "modules/dasImguiNodeEditor/examples/node-editor/shader_graph.das"

[test]
def test_render_config(t : T?) {
    with_node_editor_app(SHADER_GRAPH) $(d) {
        let s = ne_open(d, "MAIN_WIN/shader_graph")
        t |> success(s.handle != uint64(0), "editor handle present")
        if (s.handle == uint64(0)) return
        var snap0 = ne_wait_widget(s, "node_9", 15.0f)
        t |> success(snap0 != null, "styled output node (node_9) rendered")
        if (snap0 == null) return

        // with_style_var (NodeRounding) + with_style_color (NodeBorder) compose around the
        // output node: it still registers with a non-degenerate bbox.
        var n9 = ne_node(snap0, s, 9)
        let bx = n9?["payload"]?["bbox"]
        let w = (bx?["z"] ?? 0.0) - (bx?["x"] ?? 0.0)
        let h = (bx?["w"] ?? 0.0) - (bx?["y"] ?? 0.0)
        t |> success(w > 0.0 && h > 0.0, "styled output node bbox non-degenerate ({w} x {h})")

        // pivot_scale on the Mul node's output pin (pin_8) — the pin still nests + renders.
        t |> success(widget_exists(snap0, "{s.canvas}/node_5/pin_8"),
                     "output pin with pivot_scale renders (node_5/pin_8)")

        // ===== group_hint active path =====
        let resp = post_command(d, "spawn_group_cmd",
                                JV((title = "Big Group", x = 60.0, y = 60.0, w = 4000.0, h = 3000.0)))
        t |> equal(resp?["id"] ?? -1, 14, "spawn_group_cmd returned group id 14")
        t |> success(ne_wait_widget(s, "node_group_14", 6.0f) != null, "oversized group registered")

        post_command(d, "navigate_to_content", JV((q = 0)))
        // editor_dims.zoom is InvScale; zoomed-out reads >= 1/0.75 (~1.333). Poll until it settles.
        var zoom = 1.0
        for (_attempt in range(10)) {
            zoom = post_command(d, "editor_dims", JV((q = 0)))?["zoom"] ?? 1.0
            break if (zoom >= 1.34)
            wait_until_sec(d, 0.1f) $(var sn) {
                return false
            }
        }
        t |> success(zoom >= 1.34, "navigate zoomed out to InvScale {zoom} (>= 1.333) → group_hint active")
        t |> success(ne_wait_widget(s, "node_group_14", 3.0f) != null,
                     "group still renders with group_hint live (no crash)")
    }
}
