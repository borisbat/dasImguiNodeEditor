options gen2
options indenting = 4
options no_unused_block_arguments = false
options no_unused_function_arguments = false

require imgui/imgui_node_editor_app public
require imgui/imgui_editor_playwright public
require daslib/json public
require daslib/json_boost public

//! Driver: record connect_by_drag.apng - the signature gesture, voiced and
//! self-verifying. A REAL synthetic pin-drag (press on the output pin, travel
//! across, release on the input pin) commits a link; the recording asserts the
//! link committed (a no-op aborts at teardown) and pulses it to show data flow.
//! The headless regression for the same gesture is test_connect_drag.das.

let CANVAS = "MAIN_WIN/graph"

def widget_center(var snap : JsonValue?; ident : string) : tuple<float; float> {
    let b = find_widget(snap, ident)?["bbox"]
    return (((b?["x"] ?? 0.0f) + (b?["z"] ?? 0.0f)) * 0.5f,
            ((b?["y"] ?? 0.0f) + (b?["w"] ?? 0.0f)) * 0.5f)
}

[export]
def main {
    with_node_editor_recording_app("examples/tutorial/connect_by_drag.das",
                                   "connect_by_drag.apng", 50) $(app) {
        let T_OUT = "{CANVAS}/node_1/pin_11"
        let T_IN = "{CANVAS}/node_2/pin_21"
        let T_LINK = "{CANVAS}/link_100"

        let s = ne_open(app, CANVAS)
        if (s.handle == uint64(0)) {
            panic("{CANVAS} never rendered / no editor handle - wrong app running?")
        }
        var snap = wait_for_widget(app, T_OUT, 15.0f)
        if (snap == null) {
            panic("{T_OUT} never rendered - wrong app running?")
        }
        let out_c = widget_center(snap, T_OUT)
        let in_c = widget_center(snap, T_IN)

        // ---- Beat 1: the setup ----
        move_to(app, out_c, 700)
        wait_for_mouse_idle(app)
        record_check_rendered(app, T_OUT, true)
        record_check_rendered(app, T_IN, true)
        say(app, "drag output -> input", T_OUT,
            [voice = "To connect two nodes you drag from an output pin to an input pin. begin_create opens the create scope."])

        // ---- Beat 2: the hero drag (proven committing timeline) ----
        // Press ON the output pin, travel the full distance with the button held, release
        // ON the input pin. Verbatim from test_connect_drag (drag_along presses ~10% into
        // the travel - off-pin for a small target - so the timeline is hand-built).
        var events <- [
            JV((t_ms = 0, kind = "move", x = out_c._0, y = out_c._1)),
            JV((t_ms = 350, kind = "move", x = out_c._0, y = out_c._1)),
            JV((t_ms = 400, kind = "button", button = 0, action = "press")),
            JV((t_ms = 500, kind = "move", x = out_c._0, y = out_c._1)),
            JV((t_ms = 1400, kind = "move", x = in_c._0, y = in_c._1)),
            JV((t_ms = 1550, kind = "move", x = in_c._0, y = in_c._1)),
            JV((t_ms = 1650, kind = "button", button = 0, action = "release")),
            JV((t_ms = 1800, kind = "move", x = in_c._0, y = in_c._1))
        ]
        post_command(app, "imgui_mouse_play", JV((events = events)))
        wait_for_mouse_idle(app)

        // Hard self-verify: the drag MUST commit the link, or the recording aborts at teardown.
        record_check_rendered(app, T_LINK, true)

        // ---- Beat 3: the committed link + data-flow pulse ----
        let dwell = say_begin(app, "link 11 -> 21 created", T_LINK,
            [voice = "query_new_link reports the pair, accept_new_item commits it, and now the link carries data from the output to the input."])
        var pulses = int(dwell) / 500
        if (pulses < 4) { pulses = 4 }
        let interval = dwell / uint(pulses)
        for (_i in range(pulses)) {
            ne_flow(s, 100)
            hold_content(app, interval)
        }
    }
}
