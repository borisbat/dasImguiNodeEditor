options gen2
options _comment_hygiene = true
options indenting = 4
options no_unused_block_arguments = false
options no_unused_function_arguments = false

require imgui/imgui_node_editor_app public
require imgui/imgui_editor_playwright public
require daslib/json public
require daslib/json_boost public

//! Driver: record styling.apng - a guided, self-verifying tour of the editor's styling
//! layers (canvas theme, per-node tint, scoped style var/color, pin pivot, background
//! draw list), closing with a data-flow pulse along the link. Voiced (terse caption +
//! natural voice); every node, pin and the link is asserted rendered, so a broken
//! example aborts the recording at teardown. Styling is declarative - there is nothing
//! to click; the cursor sweeps left to right, pointing at each layer as it is named.

let CANVAS = "MAIN_WIN/graph"

def widget_center(var snap : JsonValue?; ident : string) : tuple<float; float> {
    let b = find_widget(snap, ident)?["bbox"]
    return (((b?["x"] ?? 0.0f) + (b?["z"] ?? 0.0f)) * 0.5f,
            ((b?["y"] ?? 0.0f) + (b?["w"] ?? 0.0f)) * 0.5f)
}

[export]
def main {
    with_node_editor_recording_app("examples/tutorial/styling.das",
                                   "styling.apng", 60) $(app) {
        let T_NODE1 = "{CANVAS}/node_1"
        let T_NODE2 = "{CANVAS}/node_2"
        let T_NODE3 = "{CANVAS}/node_3"
        let T_OUT1 = "{CANVAS}/node_1/pin_12"
        let T_LINK = "{CANVAS}/link_100"

        let s = ne_open(app, CANVAS)
        if (s.handle == uint64(0)) {
            panic("{CANVAS} never rendered / no editor handle - wrong app running?")
        }
        var snap = wait_for_widget(app, T_NODE3, 15.0f)
        if (snap == null) {
            panic("{T_NODE3} never rendered - wrong app running?")
        }

        let c_node1 = widget_center(snap, T_NODE1)
        let c_node3 = widget_center(snap, T_NODE3)
        let c_out1 = widget_center(snap, T_OUT1)
        // The accent stripe sits on node 3's left edge - point just inside it.
        let b3 = find_widget(snap, T_NODE3)?["bbox"]
        let c_stripe : tuple<float; float> = ((b3?["x"] ?? 0.0f) + 4.0f,
            ((b3?["y"] ?? 0.0f) + (b3?["w"] ?? 0.0f)) * 0.5f)

        // ---- Beat 1: the canvas theme (broadest layer) ----
        move_to(app, (500.0f, 300.0f), 600)
        wait_for_mouse_idle(app)
        record_check_rendered(app, CANVAS, true)
        say(app, "theme: warm-dark canvas", "",
            [voice = "Styling is layered. The broadest layer is the theme - apply_daslang_node_editor_style paints the whole canvas, grid and links warm-dark with amber, to match daslang's ImGui look."])

        // ---- Beat 2: per-node tint (and the default node for contrast) ----
        move_to(app, c_node1, 700)
        wait_for_mouse_idle(app)
        record_check_rendered(app, T_NODE1, true)
        record_check_rendered(app, T_NODE2, true)
        say(app, "node(color=...): tint", T_NODE1,
            [voice = "The color arg on a node fills just its background - node one is a green source. Node two passes no color and keeps the editor default, square and untinted, for contrast."])

        // ---- Beat 3: pin pivot (adjacent to node 1) ----
        move_to(app, c_out1, 600)
        wait_for_mouse_idle(app)
        record_check_rendered(app, T_OUT1, true)
        say(app, "pin pivot -> node edge", T_OUT1,
            [voice = "A pin's pivot_alignment moves where its link attaches. Node one's output pivots to the right edge, so the link leaves the node cleanly instead of springing from the pin label's center."])

        // ---- Beat 4: scoped style var + color ----
        move_to(app, c_node3, 800)
        wait_for_mouse_idle(app)
        record_check_rendered(app, T_NODE3, true)
        say(app, "with_style_var + with_style_color", T_NODE3,
            [voice = "For properties that aren't a node arg, wrap the node in scoped brackets. with_style_var rounds node three's corners and with_style_color gives it an amber border - the two compose, and each restores its previous value when the block ends."])

        // ---- Beat 5: background draw list (custom art, lowest layer) ----
        move_to(app, c_stripe, 600)
        wait_for_mouse_idle(app)
        record_check_rendered(app, T_NODE3, true)
        say(app, "background drawlist: accent", T_NODE3,
            [voice = "The lowest layer is raw drawing. with_node_background_drawlist hands you a draw list behind the node - here a red accent stripe down node three's left edge, drawn from the editor-owned geometry read back after the node."])

        // ---- Beat 6: pulse the link to show the styled graph is live ----
        let dwell = say_begin(app, "the link is live", T_LINK,
            [voice = "The styling is only skin deep - the graph still runs. We can pulse the link to watch data flow from the green source into the styled output."])
        var pulses = int(dwell) / 500
        if (pulses < 4) {
            pulses = 4
        }
        let interval = dwell / uint(pulses)
        for (_i in range(pulses)) {
            ne_flow(s, 100)
            hold_content(app, interval)
        }
    }
}
