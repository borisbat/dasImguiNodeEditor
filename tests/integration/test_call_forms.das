options gen2
options indenting = 4
options no_unused_block_arguments = false
options no_unused_function_arguments = false

require dastest/testing_boost public
require imgui/imgui_node_editor_app public
require imgui/imgui_editor_playwright public

//! Integration coverage for the call_forms.das node-editor demo. One host spawn, two
//! subtests with `reset(d)` (re-simulate, no recompile) between:
//!   1. call_forms — the [widget]/[container] forward_argument CALL FORMS (tuple vs
//!      non-tuple/positional/auto-fill) land identical snapshot entries.
//!   2. snapshot_space — node-editor snapshot geometry is uniformly SCREEN-space, with
//!      the canvas-local rect carried alongside as `canvas_bbox`.

let CALL_FORMS = "modules/dasImguiNodeEditor/examples/node-editor/call_forms.das"

def private near(a : float; b : float; tol : float) : bool {
    let d = a - b
    return d <= tol && d >= -tol
}

[test]
def test_call_forms(t : T?) {
    with_node_editor_app(CALL_FORMS) $(d) {
        //! forward_argument CALL FORMS — tuple and non-tuple both land identical snapshot entries.
        t |> run("call_forms") <| @(t : T?) {
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
        reset(d)

        //! Snapshot geometry is uniformly SCREEN-space; canvas-local rect rides as canvas_bbox.
        t |> run("snapshot_space") <| @(t : T?) {
            let s = ne_open(d, "MAIN_WIN/forms")
            t |> success(s.handle != uint64(0), "node_editor canvas rendered + handle present")
            if (s.handle == uint64(0)) return
            var snap = ne_snapshot(s)

            // ---- 1. pins have real screen-space geometry (were a zero bbox pre-fix) ----
            t |> success(widget_exists(snap, "{s.canvas}/node_1/pin_11"), "pin_11 present")
            let pin = find_widget(snap, "{s.canvas}/node_1/pin_11")
            let pminx = pin?["bbox"]?["x"] ?? 0.0f
            let pminy = pin?["bbox"]?["y"] ?? 0.0f
            let pmaxx = pin?["bbox"]?["z"] ?? 0.0f
            let pmaxy = pin?["bbox"]?["w"] ?? 0.0f
            t |> success(pmaxx > pminx, "pin_11 bbox has positive width (was zero)")
            t |> success(pmaxy > pminy, "pin_11 bbox has positive height (was zero)")

            // ---- 2. canvas_bbox carries the seeded canvas coords (nodes at x = 40, 340) ----
            t |> success(ne_node_exists(snap, s, 1), "node_1 present")
            t |> success(ne_node_exists(snap, s, 2), "node_2 present")
            let n1 = ne_node(snap, s, 1)
            let n2 = ne_node(snap, s, 2)
            let c1x = n1?["canvas_bbox"]?["x"] ?? -1.0f
            let c2x = n2?["canvas_bbox"]?["x"] ?? -1.0f
            t |> success(near(c1x, 40.0f, 2.0f), "node_1 canvas_bbox.x ~= seeded 40 (got {c1x})")
            t |> success(near(c2x, 340.0f, 2.0f), "node_2 canvas_bbox.x ~= seeded 340 (got {c2x})")

            // ---- 3. bbox is a uniform affine image of canvas_bbox ----
            // Recover scale + offset from the two nodes and require BOTH map by the same
            // affine. This is translation-invariant — it holds whether or not the canvas has
            // a screen offset, so it never assumes a non-zero origin.
            let b1x = n1?["bbox"]?["x"] ?? 0.0f
            let b2x = n2?["bbox"]?["x"] ?? 0.0f
            let canvas_span = c2x - c1x
            t |> success(canvas_span > 1.0f, "nodes separated in canvas space ({canvas_span})")
            let scale = (b2x - b1x) / canvas_span
            t |> success(scale > 0.25f && scale < 4.0f, "screen/canvas scale is sane ({scale})")
            let off1 = b1x - c1x * scale
            let off2 = b2x - c2x * scale
            t |> success(near(off1, off2, 1.0f),
                         "bbox maps canvas_bbox by a single affine (offset {off1} vs {off2})")
            // Fixture-specific (NOT a general invariant): this windowed canvas sits inside a
            // padded window, so its screen origin is non-zero and screen-space bbox is offset
            // from canvas_bbox. A canvas pinned at screen (0,0) scale 1 would legitimately
            // coincide — hence this is the only offset-assuming check, and it's scoped here.
            t |> success(off1 > 0.0f, "screen bbox carries the canvas screen origin ({off1})")

            // ---- 4. the canvas boundary itself (outside the transform) has NO canvas_bbox ----
            // node_editor() sets only the item-transform, never its own canvas_bbox; the @optional
            // float4 stays zero and JV drops it. A present canvas_bbox here would mean the transform
            // leaked past Begin/End.
            let canvas_cbb_z = find_widget(snap, s.canvas)?["canvas_bbox"]?["z"] ?? -1.0f
            t |> success(canvas_cbb_z < 0.0f, "canvas entry carries no canvas_bbox (identity outside Begin/End)")
        }
    }
}
