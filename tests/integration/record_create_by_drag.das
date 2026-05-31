options gen2
options indenting = 4
options no_unused_block_arguments = false
options no_unused_function_arguments = false

require imgui/imgui_node_editor_app public
require imgui/imgui_editor_playwright public
require daslib/json public
require daslib/json_boost public

//! Driver: record create_by_drag.apng — drag from the source output pin into EMPTY
//! canvas, pick a kind from the create-node menu, and watch the new node spawn at the
//! drop point already wired to the source. Narrated, with a slow synthetic pin-drag then
//! a real synthetic click on the menu. Run with
//! `daslang tests/integration/record_create_by_drag.das`, then ffmpeg the .apng to .mp4.
//!
//! NB: set_user_control(false) hands IO fully to the synthetic timeline — without it the
//! real OS cursor races the synth and the drag / menu click are eaten. The headless
//! regression for the same gesture is test_create_by_drag.das.

let CANVAS = "MAIN_WIN/graph"

def widget_center(var snap : JsonValue?; ident : string) : tuple<float; float> {
    let b = find_widget(snap, ident)?["bbox"]
    return (((b?["x"] ?? 0.0f) + (b?["z"] ?? 0.0f)) * 0.5f,
            ((b?["y"] ?? 0.0f) + (b?["w"] ?? 0.0f)) * 0.5f)
}

[export]
def main {
    with_node_editor_recording_app("examples/tutorial/create_by_drag.das",
                                   "create_by_drag.apng", 50) $(app) {
        var snap = wait_for_widget(app, "{CANVAS}/node_1/pin_11", 15.0f)
        if (snap == null) {
            panic("{CANVAS}/node_1/pin_11 never rendered — wrong app running?")
        }
        // Synthetic IO only — no real-cursor race (see header note).
        post_command(app, "set_user_control", JV((enabled = false)))

        let out_c = widget_center(snap, "{CANVAS}/node_1/pin_11")
        let drop : tuple<float; float> = (680.0, 430.0)   // empty canvas
        let add_mul = "{CANVAS}/CREATE_MENU/ADD_MUL"

        move_to(app, out_c, 700)
        wait_for_mouse_idle(app)
        say(app, "Drag from an output pin - but release in EMPTY canvas instead of on a pin.", "{CANVAS}/node_1/pin_11")

        // The hero gesture. Timing VERBATIM from connect_by_drag (the proven committing
        // sequence): park ON the pin through the press, travel ~900ms with the button held,
        // park at the drop point through the release.
        var events <- [
            JV((t_ms = 0,    kind = "move",   x = out_c._0, y = out_c._1)),
            JV((t_ms = 350,  kind = "move",   x = out_c._0, y = out_c._1)),
            JV((t_ms = 400,  kind = "button", button = 0,   action = "press")),
            JV((t_ms = 500,  kind = "move",   x = out_c._0, y = out_c._1)),
            JV((t_ms = 1400, kind = "move",   x = drop._0,  y = drop._1)),
            JV((t_ms = 1550, kind = "move",   x = drop._0,  y = drop._1)),
            JV((t_ms = 1650, kind = "button", button = 0,   action = "release")),
            JV((t_ms = 1800, kind = "move",   x = drop._0,  y = drop._1))
        ]
        post_command(app, "imgui_mouse_play", JV((events = events)))
        wait_for_mouse_idle(app)

        var menuSnap = wait_for_widget(app, add_mul, 6.0f)
        print("create menu opened -> {menuSnap != null}\n")
        say(app, "show_new_node_drag reports the source pin + drop point; the app opens its create menu.", add_mul)
        click(app, add_mul)

        var nSnap = wait_for_widget(app, "{CANVAS}/link_100", 6.0f)
        print("node + auto-link created -> {nSnap != null}\n")
        if (nSnap != null) {
            say(app, "Picked Multiply: spawned at the drop point and enqueue_new_link wired it to the source.", "{CANVAS}/node_200")
        } else {
            say(app, "(the create did not land - see test_create_by_drag for the geometry)", "{CANVAS}/node_1")
        }
    }
}
