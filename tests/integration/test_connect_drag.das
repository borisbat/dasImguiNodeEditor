options gen2
options indenting = 4
options no_unused_block_arguments = false
options no_unused_function_arguments = false

require dastest/testing_boost public
require imgui/imgui_node_editor_app public
require imgui/imgui_editor_playwright public

//! Milestone-0 spike: prove the HERO gesture — a synthetic mouse drag from an output
//! pin to an input pin — drives the editor's begin_create/query_new_link/accept path
//! and commits a link. This is the real interaction (not ne_add_link's command
//! injection), and it depends on pins now having a real screen-space bbox (so the
//! drag can target their centers). Drives examples/tutorial/connect_by_drag.das.

let CONNECT_BY_DRAG = "modules/dasImguiNodeEditor/examples/tutorial/connect_by_drag.das"

def private widget_center(var snap : JsonValue?; ident : string) : tuple<float; float> {
    let b = find_widget(snap, ident)?["bbox"]
    return (((b?["x"] ?? 0.0f) + (b?["z"] ?? 0.0f)) * 0.5f,
            ((b?["y"] ?? 0.0f) + (b?["w"] ?? 0.0f)) * 0.5f)
}

[test]
def test_connect_drag(t : T?) {
    with_node_editor_app(CONNECT_BY_DRAG) $(d) {
        let s = ne_open(d, "MAIN_WIN/graph")
        t |> success(s.handle != uint64(0), "editor handle present")
        if (s.handle == uint64(0)) return

        // Both pins must render (screen-space bbox) before we can target them.
        t |> success(ne_wait_widget(s, "node_1/pin_11", 15.0f) != null, "output pin rendered")
        t |> success(ne_wait_widget(s, "node_2/pin_21", 6.0f) != null, "input pin rendered")
        var snap = ne_snapshot(s)

        let out_c = widget_center(snap, "{s.canvas}/node_1/pin_11")
        let in_c  = widget_center(snap, "{s.canvas}/node_2/pin_21")
        t |> success(out_c._0 > 0.0f && in_c._0 > out_c._0,
                     "pin centers resolved, output left of input ({out_c._0} -> {in_c._0})")

        // No link before the gesture.
        t |> success(!widget_exists(snap, "{s.canvas}/link_100"), "no link before drag")

        // Synthesize the pin-drag. Grabbing a small pin needs the press to land exactly
        // ON the pin, so park the cursor at the output pin THROUGH the press (drag_along
        // presses ~10% into the travel — fine for a big drag-drop target, off-pin here),
        // drag to the input pin over ~900ms with the button held, then park on the input
        // pin through the release. imgui_mouse_play drains over wall-clock; the subject
        // applies synth IO each frame.
        var events : array<JsonValue?>
        events |> push(JV((t_ms = 0,    kind = "move",   x = out_c._0, y = out_c._1)))
        events |> push(JV((t_ms = 350,  kind = "move",   x = out_c._0, y = out_c._1)))
        events |> push(JV((t_ms = 400,  kind = "button", button = 0,   action = "press")))
        events |> push(JV((t_ms = 500,  kind = "move",   x = out_c._0, y = out_c._1)))
        events |> push(JV((t_ms = 1400, kind = "move",   x = in_c._0,  y = in_c._1)))
        events |> push(JV((t_ms = 1550, kind = "move",   x = in_c._0,  y = in_c._1)))
        events |> push(JV((t_ms = 1650, kind = "button", button = 0,   action = "release")))
        events |> push(JV((t_ms = 1800, kind = "move",   x = in_c._0,  y = in_c._1)))
        post_command(d, "imgui_mouse_play", JV((events = events)))

        // The link should commit once the drag releases over the input pin.
        var snapL = ne_wait_widget(s, "link_100", 10.0f)
        t |> success(snapL != null, "drag from output pin to input pin created link_100")
        if (snapL != null) {
            var l = find_widget(snapL, "{s.canvas}/link_100")
            t |> equal(l?["payload"]?["from_pin"] ?? -1, 11, "link_100 from the output pin (11)")
            t |> equal(l?["payload"]?["to_pin"] ?? -1, 21, "link_100 to the input pin (21)")
        }
    }
}
