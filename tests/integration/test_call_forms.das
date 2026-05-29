options gen2
options indenting = 4
options no_unused_block_arguments = false
options no_unused_function_arguments = false

require dastest/testing_boost public
require imgui/imgui_node_editor_app public
require imgui/imgui_editor_playwright public

//! Integration coverage for the [widget]/[container] forward_argument CALL FORMS.
//!
//! Drives `examples/node-editor/call_forms.das`, which renders every node-editor entity BOTH
//! ways — tuple and non-tuple/positional/auto-fill — and asserts both forms land identical
//! snapshot entries (same path key, same payload). Locks the macro's container auto-fill path
//! (a no-tuple `node(id)` and a `size`-omitted `node_editor`) that test_topology never exercises.

let CALL_FORMS = "modules/dasImguiNodeEditor/examples/node-editor/call_forms.das"

[test]
def test_call_forms(t : T?) {
    with_node_editor_app(CALL_FORMS) $(d) {
        // node_editor with `size` OMITTED still renders (container auto-fill) + exposes its handle.
        let s = ne_open(d, "MAIN_WIN/forms")
        t |> success(s.handle != uint64(0), "size-omitted node_editor rendered + handle present")
        if (s.handle == uint64(0)) return
        var snap = ne_snapshot(s)

        // node: non-tuple AND tuple forms both render under the canvas.
        t |> success(ne_node_exists(snap, s, 1), "node(1) non-tuple rendered")
        t |> success(ne_node_exists(snap, s, 2), "node(2,(color=)) tuple rendered")
        t |> success(ne_node_exists(snap, s, 3), "node(3) non-tuple rendered")
        // The lazy node serializer fires identically for both forms (payload.id).
        t |> equal(ne_node(snap, s, 1)?["payload"]?["id"] ?? -1, 1, "node_1 (non-tuple) payload id == 1")
        t |> equal(ne_node(snap, s, 2)?["payload"]?["id"] ?? -1, 2, "node_2 (tuple) payload id == 2")

        // pin: positional kind AND tuple kind both render, nested under their node.
        t |> success(widget_exists(snap, "{s.canvas}/node_1/pin_11"), "pin positional-kind rendered")
        t |> success(widget_exists(snap, "{s.canvas}/node_2/pin_21"), "pin tuple-kind rendered")
        t |> success(widget_exists(snap, "{s.canvas}/node_3/pin_31"), "pin tuple-kind (node_3) rendered")

        // link: positional AND tuple forms both render with the right pins.
        var l100 = find_widget(snap, "{s.canvas}/link_100")
        t |> success(l100 != null, "link positional rendered")
        if (l100 != null) {
            t |> equal(l100?["payload"]?["from_pin"] ?? -1, 11, "link_100 (positional) from_pin == 11")
            t |> equal(l100?["payload"]?["to_pin"] ?? -1, 21, "link_100 (positional) to_pin == 21")
        }
        var l101 = find_widget(snap, "{s.canvas}/link_101")
        t |> success(l101 != null, "link tuple rendered")
        if (l101 != null) {
            t |> equal(l101?["payload"]?["from_pin"] ?? -1, 22, "link_101 (tuple) from_pin == 22")
            t |> equal(l101?["payload"]?["to_pin"] ?? -1, 31, "link_101 (tuple) to_pin == 31")
        }
    }
}
