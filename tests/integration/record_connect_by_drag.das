options gen2
options indenting = 4
options no_unused_block_arguments = false
options no_unused_function_arguments = false

require imgui/imgui_node_editor_app public
require imgui/imgui_editor_playwright public
require daslib/json public
require daslib/json_boost public

//! Driver: record connect_by_drag.apng — the signature gesture, narrated and
//! driven by a SLOW synthetic mouse drag (with the cursor sprite + trail on).
//! Press on the output pin, drag across, release on the input pin → link.
//! Run with `daslang tests/integration/record_connect_by_drag.das`, then ffmpeg
//! the .apng to .mp4. The headless regression for the same gesture is
//! test_connect_drag.das.

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
        var snap = wait_for_widget(app, "{CANVAS}/node_1/pin_11", 15.0f)
        if (snap == null) {
            panic("{CANVAS}/node_1/pin_11 never rendered — wrong app running?")
        }
        let out_c = widget_center(snap, "{CANVAS}/node_1/pin_11")
        let in_c  = widget_center(snap, "{CANVAS}/node_2/pin_21")

        move_to(app, out_c, 700)
        sleep(SETTLE_MS)
        say(app, "begin_create opens the create scope. Press on an output pin and start dragging...", "{CANVAS}/node_1/pin_11")

        // The hero gesture, slow for the camera. Same recipe as test_connect_drag:
        // park ON the output pin through the press, travel the full distance with the
        // button held, park ON the input pin through the release. (drag_along presses
        // ~10% into the travel — off-pin for a small target.)
        var events <- [
            JV((t_ms = 0,    kind = "move",   x = out_c._0, y = out_c._1)),
            JV((t_ms = 500,  kind = "move",   x = out_c._0, y = out_c._1)),
            JV((t_ms = 600,  kind = "button", button = 0,   action = "press")),
            JV((t_ms = 800,  kind = "move",   x = out_c._0, y = out_c._1)),
            JV((t_ms = 2200, kind = "move",   x = in_c._0,  y = in_c._1)),
            JV((t_ms = 2450, kind = "move",   x = in_c._0,  y = in_c._1)),
            JV((t_ms = 2600, kind = "button", button = 0,   action = "release")),
            JV((t_ms = 2900, kind = "move",   x = in_c._0,  y = in_c._1))
        ]
        post_command(app, "imgui_mouse_play", JV((events = events)))

        // Wait for the drag to land and the link to commit before narrating the result.
        var snapL = wait_for_widget(app, "{CANVAS}/link_100", 10.0f)
        if (snapL != null) {
            say(app, "...release on a compatible input pin. query_new_link reports the pair; accept_new_item commits the link.", "{CANVAS}/link_100")
        } else {
            say(app, "(the drag did not land — see test_connect_drag for the geometry)", "{CANVAS}/node_2/pin_21")
        }
    }
}
