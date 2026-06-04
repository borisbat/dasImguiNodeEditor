options gen2
options indenting = 4
options no_unused_block_arguments = false
options no_unused_function_arguments = false

require imgui/imgui_node_editor_app public
require imgui/imgui_editor_playwright public
require daslib/json public
require daslib/json_boost public

//! Driver: record create_by_drag.apng - drag from the source output pin into EMPTY
//! canvas, pick a kind from the create-node menu, and watch the new node spawn at the
//! drop point already wired to the source. Voiced and self-verifying: the drag MUST open
//! the create menu and the menu pick MUST spawn the node + auto-link, or the recording
//! aborts at teardown. Closes by pulsing the freshly enqueued link to show it is live.
//! The headless regression for the same gesture is test_create_by_drag.das.

let CANVAS = "MAIN_WIN/graph"

def widget_center(var snap : JsonValue?; ident : string) : tuple<float; float> {
    let b = find_widget(snap, ident)?["bbox"]
    return (((b?["x"] ?? 0.0f) + (b?["z"] ?? 0.0f)) * 0.5f,
            ((b?["y"] ?? 0.0f) + (b?["w"] ?? 0.0f)) * 0.5f)
}

[export]
def main {
    with_node_editor_recording_app("examples/tutorial/create_by_drag.das",
                                   "create_by_drag.apng", 60) $(app) {
        let T_OUT = "{CANVAS}/node_1/pin_11"
        let T_MENU = "{CANVAS}/CREATE_MENU/ADD_MUL"
        let T_NODE = "{CANVAS}/node_200"
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
        let drop : tuple<float; float> = (680.0f, 430.0f)   // empty canvas

        // ---- Beat 1: the setup ----
        move_to(app, out_c, 700)
        wait_for_mouse_idle(app)
        record_check_rendered(app, T_OUT, true)
        say(app, "drag output -> EMPTY canvas", T_OUT,
            [voice = "Drag from an output pin again - but this time release in empty canvas, not on a pin."])

        // ---- Beat 2: the hero drag into empty canvas (proven committing timeline) ----
        // Press ON the output pin, travel the full distance with the button held, release
        // in empty canvas. Verbatim timing from connect_by_drag.
        var events <- [
            JV((t_ms = 0, kind = "move", x = out_c._0, y = out_c._1)),
            JV((t_ms = 350, kind = "move", x = out_c._0, y = out_c._1)),
            JV((t_ms = 400, kind = "button", button = 0, action = "press")),
            JV((t_ms = 500, kind = "move", x = out_c._0, y = out_c._1)),
            JV((t_ms = 1400, kind = "move", x = drop._0, y = drop._1)),
            JV((t_ms = 1550, kind = "move", x = drop._0, y = drop._1)),
            JV((t_ms = 1650, kind = "button", button = 0, action = "release")),
            JV((t_ms = 1800, kind = "move", x = drop._0, y = drop._1))
        ]
        post_command(app, "imgui_mouse_play", JV((events = events)))
        wait_for_mouse_idle(app)

        // Hard self-verify: a drop in empty canvas MUST open the create menu (show_new_node_drag
        // fired), or the recording aborts at teardown.
        record_check_rendered(app, T_MENU, true)
        say(app, "show_new_node_drag -> create menu", T_MENU,
            [voice = "Releasing in empty canvas fires show_new_node_drag - it reports the source pin and the drop point, so the app opens its create-node menu right there."])

        // ---- Beat 3: pick a kind -> spawn + auto-connect ----
        click(app, T_MENU)
        // Hard self-verify: the pick MUST spawn the node AND the auto-link, or abort.
        record_check_rendered(app, T_NODE, true)
        record_check_rendered(app, T_LINK, true)
        say(app, "spawned + auto-wired", T_NODE,
            [voice = "Picking Multiply spawns the node at the drop point, and enqueue_new_link wires it straight back to the source pin."])

        // ---- Beat 4: pulse the new link to show it is live ----
        let dwell = say_begin(app, "the new link is live", T_LINK,
            [voice = "The link the editor just made carries data exactly like a hand-dragged one - we can pulse it to watch it flow from the source into the node we just created."])
        var pulses = int(dwell) / 500
        if (pulses < 4) { pulses = 4 }
        let interval = dwell / uint(pulses)
        for (_i in range(pulses)) {
            ne_flow(s, 100)
            sleep(interval)
        }
    }
}
